#include "MetalRenderPCH.h"
#include "MetalMaterialTextureBinder.h"
#include "MetalBaseRenderer.m"
#include "MetalTextureManager.m"
#include "MetalShaderManager.m"

#include "IShader.h"
#include <unordered_set>
#include <cstring>

namespace MetalMaterialTextureBinder {

namespace {

struct EfttNameMap
{
    const char* name;
    int         eftt;
};

constexpr EfttNameMap kFragmentNameToEftt[] = {
    { "baseMap",        EFTT_DIFFUSE        },
    { "baseMap0",       EFTT_DIFFUSE        },
    { "diffuseMap",     EFTT_DIFFUSE        },
    { "difMap",         EFTT_DIFFUSE        },
    { "decalMap",       EFTT_DECAL_OVERLAY  },
    { "bumpMap",        EFTT_BUMP           },
    { "BumpMap",        EFTT_BUMP           },
    { "normalMap",      EFTT_NORMALMAP      },
    { "normMap",        EFTT_NORMALMAP      },
    { "bumpMapDiffuse", EFTT_BUMP_DIFFUSE   },
    { "bumpHeight",     EFTT_BUMP_HEIGHT    },
    { "glossMap",       EFTT_GLOSS          },
    { "specularMap",    EFTT_SPECULAR       },
    { "phongMap",       EFTT_PHONG          },
    { "envMap",         EFTT_CUBEMAP        },
    { "Environment",    EFTT_CUBEMAP        },
    { "detMap",         EFTT_DETAIL_OVERLAY },
    { "detMap0",        EFTT_DETAIL_OVERLAY },
    { "reflMap",        EFTT_REFLECTION     },
    { "opacityMap",     EFTT_OPACITY        },
    { "alphaMap",       EFTT_OPACITY        },
    { "lightMap",       EFTT_LIGHTMAP       },
    { "lightMapHDR",    EFTT_LIGHTMAP_HDR   },
    { "lightDirMap",    EFTT_LIGHTMAP_DIR   },
    { "occlusionMap",   EFTT_OCCLUSION      },
    { "attenMap",       EFTT_ATTENUATION2D  },
};

bool IsKnownBuiltinName(const std::string& name)
{
    static const std::unordered_set<std::string> kBuiltins = {
        "normCubeMap", "normCubeMapHA", "normCubeMapLV",
        "projMap",
        "shadMap", "shadMap0", "shadMap1", "shadMap2", "shadMap3", "shadMap4",
        "shadowMap0", "shadowMap1", "shadowMap2",
        "fogMap", "fogEnterMap",
        "noiseMap",
        "caustMap",
        "starMap", "starMapRG", "starMapBA",
        "ScreenMap", "ScreenTex", "ScreenTexMask", "ScreenBluredTex",
        "CurrScreen", "LastScreen",
        "refrMap", "refrMapR", "refrMapG", "refrMapB",
        "refMap",
        "bloomMap", "adaptedLumMap", "lumMap", "lumMap0", "lumMap1",
        "depthMap",
        "sunMap",
        "GlareTex",
        "fresnelMap",
        "modMap", "maskMap", "bumpMask",
        "heatMap", "HeatTex", "NoiseTex", "HeatPaleteTex",
        "tableMap", "gradMap", "palMap", "Rainbow",
        "specPowMap", "glowMap", "fadeMap", "flashMap",
        "iridescenceMap", "plasmaMap", "rainbMap", "lensMap", "screenMap",
        "basisMap0", "basisMap1", "horizonMap0", "horizonMap1",
        "furMap", "furLightMap", "furNormalMap",
        "BlurSampler", "FocalDistMap",
        "offsMap",
        "dirtyMap",
        "clampMap",
        "glareAmountMap",
        "texScreen01", "texScreen02", "texScreen03", "texScreen04",
        "baseMapRG", "baseMapBA", "baseMap_K",
        "baseMap1", "baseMap2", "baseMap3", "baseMap4",
        "baseMap5", "baseMap6", "baseMap7",
        "detMap1", "detMap2", "detMap3",
    };
    return kBuiltins.find(name) != kBuiltins.end();
}

} // namespace

int Binder::LookupEfttIndexForName(const char* name)
{
    if (!name)
        return -1;
    for (const EfttNameMap& m : kFragmentNameToEftt)
    {
        if (strcmp(m.name, name) == 0)
            return m.eftt;
    }
    return -1;
}

Binder::Binder() = default;
Binder::~Binder() = default;

void Binder::RegisterShader(const char* shaderName, NSArray* manifestTextures)
{
    if (!shaderName || ![manifestTextures isKindOfClass:[NSArray class]] || [manifestTextures count] == 0)
        return;
    ShaderTextureLayout layout;
    layout.shaderName = shaderName;
    for (id obj in manifestTextures)
    {
        if (![obj isKindOfClass:[NSDictionary class]])
            continue;
        NSDictionary* dict = (NSDictionary*)obj;
        NSString* nameNS = dict[@"name"];
        NSNumber* slotNum = dict[@"slot"];
        if (!nameNS || !slotNum)
            continue;
        FragmentTextureSlot fts;
        fts.name = [nameNS UTF8String];
        fts.slot = [slotNum intValue];
        fts.efttIndex = LookupEfttIndexForName(fts.name.c_str());
        layout.slots.push_back(fts);
    }
    if (!layout.slots.empty())
        m_layouts[shaderName] = std::move(layout);
}

bool Binder::HasShader(const char* shaderName) const
{
    if (!shaderName)
        return false;
    return m_layouts.find(shaderName) != m_layouts.end();
}

bool Binder::BindForShader(id<MTLRenderCommandEncoder> encoder,
                           const char* shaderName,
                           SRenderShaderResources* pRes,
                           CMetalTextureManager* textureManager)
{
    const bool diag = (m_diagCallsRemaining > 0);
    if (diag)
        --m_diagCallsRemaining;
    if (!encoder || !shaderName || !textureManager)
    {
        if (diag && iLog)
            iLog->Log("\003[MaterialTextureBinder] EARLY-OUT encoder=%p shader=%s mgr=%p",
                      (void*)encoder, shaderName ? shaderName : "(null)", (void*)textureManager);
        return false;
    }
    auto it = m_layouts.find(shaderName);
    if (it == m_layouts.end())
    {
        if (diag && iLog)
            iLog->Log("\003[MaterialTextureBinder] NO LAYOUT for shader=%s registered=%zu pRes=%p",
                      shaderName, m_layouts.size(), (void*)pRes);
        return false;
    }
    const ShaderTextureLayout& layout = it->second;

    if (diag && iLog)
        iLog->Log("\003[MaterialTextureBinder] BIND shader=%s slots=%zu pRes=%p",
                  shaderName, layout.slots.size(), (void*)pRes);

    id<MTLTexture> fallback = textureManager->EnsureWhiteTexture();

    for (const FragmentTextureSlot& fts : layout.slots)
    {
        id<MTLTexture> tex = nil;
        if (fts.efttIndex >= 0 && fts.efttIndex < EFTT_MAX && pRes &&
            pRes->m_Textures[fts.efttIndex] &&
            pRes->m_Textures[fts.efttIndex]->m_TU.m_ITexPic)
        {
            ITexPic* iPic = pRes->m_Textures[fts.efttIndex]->m_TU.m_ITexPic;
            const int texId = iPic->GetTextureID();
            tex = textureManager->ResolveMetalTextureByID(texId);
        }
        if (!tex)
        {
            tex = fallback;
            if (fts.efttIndex < 0 && !IsKnownBuiltinName(fts.name))
            {
                auto wit = m_unknownNameWarnings.find(fts.name);
                if (wit == m_unknownNameWarnings.end())
                {
                    m_unknownNameWarnings[fts.name] = 1;
                    if (iLog)
                        iLog->Log("\003[MaterialTextureBinder] no EFTT mapping for fragment texture name '%s' (shader %s) — bound white",
                                  fts.name.c_str(), shaderName);
                }
            }
        }
        if (tex)
        {
            [encoder setFragmentTexture:tex atIndex:fts.slot];
            id<MTLSamplerState> sampler = textureManager->AcquireDefaultSampler();
            if (sampler)
                [encoder setFragmentSamplerState:sampler atIndex:fts.slot];
        }
        if (diag && iLog)
        {
            iLog->Log("\003[MaterialTextureBinder]   slot=%d name=%s eftt=%d tex=%p fallback=%d",
                      fts.slot, fts.name.c_str(), fts.efttIndex, (void*)tex, (tex == fallback) ? 1 : 0);
        }
    }
    return true;
}

} // namespace MetalMaterialTextureBinder
