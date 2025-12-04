////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalShaderLoader.cpp
//  Version:     v1.00 - Phase 2 Implementation
//  Created:     30/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Shader loading and compilation for Phase 2
//               Includes initialization of default shader library
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalShaderManager.m"
#include "MetalBaseRenderer.m"
#include "MetalVertexDescriptor.m"
#include "MetalStateCache.m"
#include <Cocoa/Cocoa.h>
#include <fstream>
#include <sstream>
#include <cctype>
#include <cassert>
#include <strings.h>
#include <algorithm>
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

namespace
{
struct VertexLayoutInfo
{
    int format;
    NSString* functionName;
    bool hasTexCoords;
    bool hasColor;
    bool hasSecondTex;
    bool hasSecondColor;
    bool hasNormal;
    int texCoordCount;
};

struct VertexAttributeSummary
{
    bool hasPosition = true;
    bool hasNormal = false;
    bool hasColor0 = false;
    bool hasColor1 = false;
    int texCoordCount = 0;
};

VertexAttributeSummary BuildAttributeSummary(NSArray* attributes, NSArray* metadata, int textureCount, NSString* shaderName)
{
    VertexAttributeSummary summary;
    bool populatedFromMetadata = false;
    if (metadata && [metadata isKindOfClass:[NSArray class]] && [metadata count] > 0)
    {
        populatedFromMetadata = true;
        for (id entry in metadata)
        {
            if (![entry isKindOfClass:[NSDictionary class]])
                continue;
            NSDictionary* dict = (NSDictionary*)entry;
            NSString* category = dict[@"category"];
            if (!category || ![category isKindOfClass:[NSString class]])
                continue;
            if ([category isEqualToString:@"color"])
            {
                NSNumber* indexValue = dict[@"index"];
                int index = indexValue ? indexValue.intValue : 0;
                if (index <= 0)
                    summary.hasColor0 = true;
                else if (index == 1)
                    summary.hasColor1 = true;
            }
            else if ([category isEqualToString:@"texcoord"])
            {
                NSNumber* indexValue = dict[@"index"];
                if (indexValue)
                {
                    int idx = indexValue.intValue;
                    if (idx >= 0)
                        summary.texCoordCount = std::max(summary.texCoordCount, idx + 1);
                }
            }
            else if ([category isEqualToString:@"normal"])
            {
                summary.hasNormal = true;
            }
        }
    }

    const bool hasExplicitAttributes = attributes && [attributes count] > 0;
    if (!populatedFromMetadata)
    {
        if (hasExplicitAttributes)
        {
            for (id item in attributes)
            {
                if (![item isKindOfClass:[NSString class]])
                    continue;
                NSString* attrString = [(NSString*)item lowercaseString];
                if ([attrString containsString:@"normal"])
                    summary.hasNormal = true;
                if ([attrString containsString:@"color1"] || [attrString containsString:@"sec_color"])
                    summary.hasColor1 = true;
                else if ([attrString containsString:@"color"])
                    summary.hasColor0 = true;
                if ([attrString containsString:@"texcoord1"])
                    summary.texCoordCount = std::max(summary.texCoordCount, 2);
                else if ([attrString containsString:@"texcoord"])
                    summary.texCoordCount = std::max(summary.texCoordCount, 1);
            }
        }
        if (shaderName)
        {
            NSString* lowerName = [shaderName lowercaseString];
            if ([lowerName hasPrefix:@"cgv"])
            {
                summary.hasColor0 = true;
                summary.texCoordCount = std::max(summary.texCoordCount, 1);
            }
            else if (!hasExplicitAttributes)
            {
                if ([lowerName containsString:@"vegetation"] ||
                    [lowerName containsString:@"plants"])
                {
                    summary.hasColor0 = true;
                    summary.texCoordCount = std::max(summary.texCoordCount, 1);
                }
                if ([lowerName containsString:@"normal"] ||
                    [lowerName containsString:@"bump"])
                {
                    summary.hasNormal = true;
                    summary.texCoordCount = std::max(summary.texCoordCount, 1);
                }
            }
        }
    }

    if (summary.texCoordCount == 0 && textureCount > 0)
        summary.texCoordCount = 1;
    if (summary.hasColor1)
        summary.hasColor0 = true;
    summary.texCoordCount = std::min(summary.texCoordCount, 2);
    return summary;
}

VertexLayoutInfo InferVertexLayout(const VertexAttributeSummary& summary, NSString* shaderName)
{
    VertexLayoutInfo info;
    info.hasTexCoords = summary.texCoordCount > 0;
    info.hasColor = summary.hasColor0;
    info.hasSecondTex = summary.texCoordCount > 1;
    info.hasSecondColor = summary.hasColor1;
    info.hasNormal = summary.hasNormal;
    info.texCoordCount = summary.texCoordCount;

    if (summary.hasColor1)
    {
        if (summary.texCoordCount > 1 && iLog)
        {
            iLog->Log("MetalShaderManager: Shader '%s' requests dual colors with more than one texcoord set; using single texcoord fallback\n",
                      shaderName ? [shaderName UTF8String] : "<unnamed>");
        }
        if (summary.hasNormal)
        {
            if (summary.texCoordCount > 0)
            {
                info.format = VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F;
                info.functionName = @"basic_colordual_tex_vertex";
            }
            else
            {
                info.format = VERTEX_FORMAT_P3F_N_COL4UB_COL4UB;
                info.functionName = @"basic_colordual_vertex";
            }
        }
        else
        {
            if (summary.texCoordCount > 0)
            {
                info.format = VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F;
                info.functionName = @"colordual_tex_vertex";
            }
            else
            {
                info.format = VERTEX_FORMAT_P3F_COL4UB_COL4UB;
                info.functionName = @"colordual_vertex";
            }
        }
        return info;
    }

    if (summary.texCoordCount > 1)
        info.format = VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F;
    else if (summary.hasNormal && summary.hasColor0 && summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_N_COL4UB_TEX2F;
    else if (summary.hasNormal && summary.hasColor0 && summary.texCoordCount == 0)
        info.format = VERTEX_FORMAT_P3F_N_COL4UB;
    else if (summary.hasNormal && !summary.hasColor0 && summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_N_TEX2F;
    else if (summary.hasNormal && !summary.hasColor0)
        info.format = VERTEX_FORMAT_P3F_N;
    else if (summary.hasColor0 && summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_COL4UB_TEX2F;
    else if (summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_TEX2F;
    else if (summary.hasColor0)
        info.format = VERTEX_FORMAT_P3F_COL4UB;
    else
        info.format = VERTEX_FORMAT_P3F;

    if (summary.texCoordCount > 1)
        info.functionName = summary.hasColor0 ? @"colortex2_vertex" : @"tex2_vertex";
    else if (summary.hasNormal && summary.hasColor0 && summary.texCoordCount > 0)
        info.functionName = @"basic_vertex";
    else if (summary.hasNormal && summary.hasColor0 && summary.texCoordCount == 0)
        info.functionName = @"basic_color_vertex";
    else if (summary.hasNormal && !summary.hasColor0 && summary.texCoordCount > 0)
        info.functionName = @"normaltex_vertex";
    else if (summary.hasNormal && !summary.hasColor0)
        info.functionName = @"normal_vertex";
    else if (summary.texCoordCount > 0)
        info.functionName = summary.hasColor0 ? @"colortex_vertex" : @"tex_vertex";
    else
        info.functionName = summary.hasColor0 ? @"color_vertex" : @"simple_vertex";

    return info;
}


enum PipelineBlendMode : uint32
{
    kBlendNone = 0,
    kBlendAlpha = 1,
    kBlendAdditive = 2
};

struct PipelineStateConfig
{
    bool blendEnabled = true;
    PipelineBlendMode blendMode = kBlendAlpha;
    MTLBlendFactor sourceBlendFactor = MTLBlendFactorSourceAlpha;
    MTLBlendFactor destinationBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    MTLBlendOperation blendOperation = MTLBlendOperationAdd;
    MTLBlendFactor sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    MTLBlendFactor destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    MTLBlendOperation alphaBlendOperation = MTLBlendOperationAdd;
    bool depthTestEnabled = true;
    bool depthWriteEnabled = false;
    MTLCompareFunction depthCompareFunction = MTLCompareFunctionLessEqual;
    MTLCullMode cullMode = MTLCullModeBack;
    uint8_t colorWriteMask = 0xF;
};

PipelineStateConfig DefaultPipelineConfig()
{
    return PipelineStateConfig();
}

static NSString* NormalizeBlendString(NSString* value)
{
    if (!value)
        return nil;
    NSString* lowered = [[value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    lowered = [lowered stringByReplacingOccurrencesOfString:@"_" withString:@""];
    lowered = [lowered stringByReplacingOccurrencesOfString:@"-" withString:@""];
    lowered = [lowered stringByReplacingOccurrencesOfString:@" " withString:@""];
    return lowered;
}

static MTLBlendFactor BlendFactorFromString(NSString* value)
{
    NSString* token = NormalizeBlendString(value);
    if (!token || [token length] == 0)
        return MTLBlendFactorOne;
    if ([token isEqualToString:@"zero"])
        return MTLBlendFactorZero;
    if ([token isEqualToString:@"one"])
        return MTLBlendFactorOne;
    if ([token isEqualToString:@"srccolor"] || [token isEqualToString:@"src"])
        return MTLBlendFactorSourceColor;
    if ([token isEqualToString:@"invsrccolor"] || [token isEqualToString:@"oneminussrccolor"])
        return MTLBlendFactorOneMinusSourceColor;
    if ([token isEqualToString:@"dstcolor"] || [token isEqualToString:@"dst"])
        return MTLBlendFactorDestinationColor;
    if ([token isEqualToString:@"invdstcolor"] || [token isEqualToString:@"oneminusdstcolor"])
        return MTLBlendFactorOneMinusDestinationColor;
    if ([token isEqualToString:@"srcalpha"])
        return MTLBlendFactorSourceAlpha;
    if ([token isEqualToString:@"invsrcalpha"] || [token isEqualToString:@"oneminussrcalpha"])
        return MTLBlendFactorOneMinusSourceAlpha;
    if ([token isEqualToString:@"dstalpha"])
        return MTLBlendFactorDestinationAlpha;
    if ([token isEqualToString:@"invdstalpha"] || [token isEqualToString:@"oneminusdstalpha"])
        return MTLBlendFactorOneMinusDestinationAlpha;
    if ([token isEqualToString:@"srcalphasat"] || [token isEqualToString:@"srcalphasaturate"])
        return MTLBlendFactorSourceAlphaSaturated;
    return MTLBlendFactorOne;
}

static MTLBlendOperation BlendOperationFromString(NSString* value)
{
    NSString* token = NormalizeBlendString(value);
    if (!token || [token length] == 0)
        return MTLBlendOperationAdd;
    if ([token isEqualToString:@"add"])
        return MTLBlendOperationAdd;
    if ([token isEqualToString:@"subtract"])
        return MTLBlendOperationSubtract;
    if ([token isEqualToString:@"revsubtract"] || [token isEqualToString:@"reversesubtract"])
        return MTLBlendOperationReverseSubtract;
    if ([token isEqualToString:@"min"])
        return MTLBlendOperationMin;
    if ([token isEqualToString:@"max"])
        return MTLBlendOperationMax;
    return MTLBlendOperationAdd;
}

void ApplyPipelineConfigFromManifest(PipelineStateConfig& config, NSDictionary* pipelineDict)
{
    if (!pipelineDict || ![pipelineDict isKindOfClass:[NSDictionary class]])
        return;

    NSNumber* blendEnabledValue = pipelineDict[@"blendEnabled"];
    if (blendEnabledValue)
        config.blendEnabled = blendEnabledValue.boolValue;

    NSString* blendModeValue = pipelineDict[@"blendMode"];
    if (blendModeValue)
    {
        NSString* lower = [blendModeValue lowercaseString];
        if ([lower isEqualToString:@"none"])
        {
            config.blendEnabled = false;
            config.blendMode = kBlendNone;
        }
        else if ([lower isEqualToString:@"add"] || [lower isEqualToString:@"additive"])
        {
            config.blendEnabled = true;
            config.blendMode = kBlendAdditive;
            config.sourceBlendFactor = MTLBlendFactorOne;
            config.destinationBlendFactor = MTLBlendFactorOne;
            config.blendOperation = MTLBlendOperationAdd;
        }
        else
        {
            config.blendEnabled = true;
            config.blendMode = kBlendAlpha;
            config.sourceBlendFactor = MTLBlendFactorSourceAlpha;
            config.destinationBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            config.blendOperation = MTLBlendOperationAdd;
        }
    }

    NSDictionary* blendFactorsDict = pipelineDict[@"blendFactors"];
    if (blendFactorsDict && [blendFactorsDict isKindOfClass:[NSDictionary class]])
    {
        NSString* srcValue = blendFactorsDict[@"src"];
        if (srcValue)
            config.sourceBlendFactor = BlendFactorFromString(srcValue);
        NSString* dstValue = blendFactorsDict[@"dst"];
        if (dstValue)
            config.destinationBlendFactor = BlendFactorFromString(dstValue);
        NSString* srcAlphaValue = blendFactorsDict[@"srcAlpha"];
        if (srcAlphaValue)
            config.sourceAlphaBlendFactor = BlendFactorFromString(srcAlphaValue);
        else
            config.sourceAlphaBlendFactor = config.sourceBlendFactor;
        NSString* dstAlphaValue = blendFactorsDict[@"dstAlpha"];
        if (dstAlphaValue)
            config.destinationAlphaBlendFactor = BlendFactorFromString(dstAlphaValue);
        else
            config.destinationAlphaBlendFactor = config.destinationBlendFactor;
        NSString* opValue = blendFactorsDict[@"op"];
        if (opValue)
            config.blendOperation = BlendOperationFromString(opValue);
        NSString* opAlphaValue = blendFactorsDict[@"opAlpha"];
        if (opAlphaValue)
            config.alphaBlendOperation = BlendOperationFromString(opAlphaValue);
        else
            config.alphaBlendOperation = config.blendOperation;
    }
    else
    {
        config.sourceAlphaBlendFactor = config.sourceBlendFactor;
        config.destinationAlphaBlendFactor = config.destinationBlendFactor;
        config.alphaBlendOperation = config.blendOperation;
    }

    NSNumber* depthTestValue = pipelineDict[@"depthTest"];
    if (depthTestValue)
        config.depthTestEnabled = depthTestValue.boolValue;

    NSNumber* depthWriteValue = pipelineDict[@"depthWrite"];
    if (depthWriteValue)
        config.depthWriteEnabled = depthWriteValue.boolValue;

    NSString* depthCompareValue = pipelineDict[@"depthCompare"];
    if (depthCompareValue)
    {
        NSString* lower = [depthCompareValue lowercaseString];
        if ([lower isEqualToString:@"less"])
            config.depthCompareFunction = MTLCompareFunctionLess;
        else if ([lower isEqualToString:@"always"])
            config.depthCompareFunction = MTLCompareFunctionAlways;
        else
            config.depthCompareFunction = MTLCompareFunctionLessEqual;
    }

    NSString* cullValue = pipelineDict[@"cullMode"];
    if (cullValue)
    {
        NSString* lower = [cullValue lowercaseString];
        if ([lower isEqualToString:@"none"])
            config.cullMode = MTLCullModeNone;
        else if ([lower isEqualToString:@"front"])
            config.cullMode = MTLCullModeFront;
        else
            config.cullMode = MTLCullModeBack;
    }

    if (!config.blendEnabled)
        config.blendMode = kBlendNone;

    NSDictionary* colorMaskDict = pipelineDict[@"colorMask"];
    if (colorMaskDict && [colorMaskDict isKindOfClass:[NSDictionary class]])
    {
        uint8_t mask = 0;
        NSNumber* rValue = colorMaskDict[@"r"];
        NSNumber* gValue = colorMaskDict[@"g"];
        NSNumber* bValue = colorMaskDict[@"b"];
        NSNumber* aValue = colorMaskDict[@"a"];
        if (!rValue || rValue.boolValue)
            mask |= 0x1;
        if (!gValue || gValue.boolValue)
            mask |= 0x2;
        if (!bValue || bValue.boolValue)
            mask |= 0x4;
        if (!aValue || aValue.boolValue)
            mask |= 0x8;
        config.colorWriteMask = mask ? mask : 0;
    }
}

static std::string NormalizeShaderName(const char* name)
{
    if (!name)
        return "";

    char normalized[256];
    strncpy(normalized, name, sizeof(normalized) - 1);
    normalized[sizeof(normalized) - 1] = 0;

    for (char* p = normalized; *p; ++p)
    {
        if (*p == '\\')
            *p = '/';
        *p = static_cast<char>(std::tolower(static_cast<unsigned char>(*p)));
    }
    return std::string(normalized);
}
}

CMetalShaderManager::CMetalShaderManager(CMetalBaseRenderer* renderer, 
                                        CMetalTextureManager* textureManager)
    : m_renderer(renderer)
    , m_textureManager(textureManager)
    , m_nextShaderId(1)
    , m_currentShaderId(0)
    , m_currentPipelineState(nil)
    , m_globalShaderTemplateId(0)
    , m_heatVisionEnabled(false)
    , m_generatedLibrary(nil)
{
    assert(renderer != nullptr && "CMetalShaderManager: renderer cannot be null!");
    assert(textureManager != nullptr && "CMetalShaderManager: textureManager cannot be null!");
    assert(renderer->m_device != nil && "CMetalShaderManager: renderer must have valid Metal device!");
    assert(m_nextShaderId == 1 && "CMetalShaderManager: shader ID counter must start at 1!");
    
    iLog->Log("MetalShaderManager: Initializing...\n");
    
    if (!InitializeDefaultShaderLibrary())
    {
        iLog->Log("Warning: Failed to initialize default shader library\n");
    }
    
    iLog->Log("MetalShaderManager: Initialization complete (%zu shaders loaded)\n", m_shaders.size());
}

CMetalShaderManager::~CMetalShaderManager()
{
    assert(m_renderer != nullptr && "CMetalShaderManager: renderer should not be null during destruction!");
    assert(m_textureManager != nullptr && "CMetalShaderManager: textureManager should not be null during destruction!");
    
    iLog->Log("MetalShaderManager: Shutting down...\n");
    ClearAllShaders();
    
    assert(m_shaders.empty() && "CMetalShaderManager: all shaders should be cleared!");
    assert(m_shaderNameMap.empty() && "CMetalShaderManager: shader name map should be cleared!");
}

bool CMetalShaderManager::InitializeDefaultShaderLibrary()
{
    assert(m_renderer != nullptr && "InitializeDefaultShaderLibrary: renderer cannot be null!");
    assert(m_renderer->m_device != nil && "InitializeDefaultShaderLibrary: Metal device cannot be null!");
    
    if (!m_renderer || !m_renderer->m_device)
    {
        iLog->Log("Error: No Metal device available\n");
        return false;
    }
    
    NSError* error = nil;
    
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* shaderPath = [bundle pathForResource:@"UtilShaders" ofType:@"metallib"];
    
    id<MTLLibrary> defaultLibrary = nil;
    
    if (shaderPath)
    {
        iLog->Log("Loading shader library from: %s\n", [shaderPath UTF8String]);
        defaultLibrary = [m_renderer->m_device newLibraryWithFile:shaderPath error:&error];
    }
    
    if (!defaultLibrary)
    {
        // Try loading from app bundle MacOS directory (where we copy the metallibs)
        NSString* exePath = [[NSBundle mainBundle] executablePath];
        NSString* exeDir = [exePath stringByDeletingLastPathComponent];
        NSString* metallibPath = [exeDir stringByAppendingPathComponent:@"UtilShaders.metallib"];
        
        iLog->Log("Attempting to load from executable directory: %s\n", [metallibPath UTF8String]);
        defaultLibrary = [m_renderer->m_device newLibraryWithFile:metallibPath error:&error];
    }
    
    if (!defaultLibrary)
    {
        iLog->Log("Attempting to load default library...\n");
        defaultLibrary = [m_renderer->m_device newDefaultLibrary];
    }
    
    if (!defaultLibrary)
    {
        iLog->Log("Error: Failed to create shader library: %s\n",
               error ? [[error localizedDescription] UTF8String] : "Unknown error");
        return false;
    }
    
    iLog->Log("Shader library loaded successfully\n");
    
    CreateDefaultShaders(defaultLibrary);
    LoadGeneratedShaders(defaultLibrary);
    if (iLog)
    {
        for (const auto& kv : m_shaderNameMap)
        {
            iLog->Log("MetalShaderManager: base shader '%s' has id=%d\n", kv.first.c_str(), kv.second);
        }
    }
    InitializeShaderFallbacks();
    
    return true;
}

void CMetalShaderManager::CreateDefaultShaders(id<MTLLibrary> library)
{
    assert(library != nil && "CreateDefaultShaders: library cannot be null!");
    assert(m_renderer != nullptr && "CreateDefaultShaders: renderer cannot be null!");
    assert(m_renderer->m_device != nil && "CreateDefaultShaders: Metal device cannot be null!");
    
    if (!library)
        return;
    
    struct ShaderPair {
        const char* name;
        const char* vertexFunc;
        const char* fragmentFunc;
        int vertexFormat;
    };
    
    ShaderPair defaultShaders[] = {
        {"simple",     "simple_vertex",     "simple_fragment",     VERTEX_FORMAT_P3F},
        {"color",      "color_vertex",      "simple_fragment",     VERTEX_FORMAT_P3F_COL4UB},
        {"colortex",   "colortex_vertex",   "colortex_fragment",   VERTEX_FORMAT_P3F_COL4UB_TEX2F},
        {"basic",      "basic_vertex",      "basic_fragment",      VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
        {"unlit",      "basic_vertex",      "unlit_fragment",      VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
        {"terrain",    "terrain_vertex",    "terrain_fragment",    VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
        {"sky",        "sky_vertex",        "sky_fragment",        VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
    };
    
    for (const auto& shader : defaultShaders)
    {
        assert(shader.name != nullptr && "CreateDefaultShaders: shader name cannot be null!");
        assert(shader.vertexFunc != nullptr && "CreateDefaultShaders: vertex function name cannot be null!");
        assert(shader.fragmentFunc != nullptr && "CreateDefaultShaders: fragment function name cannot be null!");
        
        id<MTLFunction> vertexFunc = [library newFunctionWithName:@(shader.vertexFunc)];
        id<MTLFunction> fragmentFunc = [library newFunctionWithName:@(shader.fragmentFunc)];
        
        assert(vertexFunc != nil && fragmentFunc != nil && 
               "CreateDefaultShaders: Failed to load shader functions - shader library may be missing or outdated");
        
        MTLVertexDescriptor* vertexDesc = CMetalVertexDescriptorHelper::CreateVertexDescriptor(shader.vertexFormat);
        assert(vertexDesc != nil && "CreateDefaultShaders: Failed to create vertex descriptor - invalid vertex format");
        
        ShaderInfo info;
        info.blendEnabled = true;
        info.blendMode = static_cast<uint32>(kBlendAlpha);
        info.sourceBlendFactor = MTLBlendFactorSourceAlpha;
        info.destinationBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        info.blendOperation = MTLBlendOperationAdd;
        info.sourceAlphaBlendFactor = info.sourceBlendFactor;
        info.destinationAlphaBlendFactor = info.destinationBlendFactor;
        info.alphaBlendOperation = info.blendOperation;
        info.depthTestEnabled = true;
        info.depthWriteEnabled = true;
        info.depthCompareFunction = MTLCompareFunctionLessEqual;
        info.cullMode = MTLCullModeBack;
        info.colorWriteMask = 0xF;
        info.name = shader.name;

        id<MTLRenderPipelineState> pipelineState = CreatePipelineStateWithFunctions(
            vertexFunc, fragmentFunc, vertexDesc, &info);
        
        assert(pipelineState != nil && "CreateDefaultShaders: Failed to create pipeline state");
        
        int shaderId = AllocateShaderId();
        assert(shaderId > 0 && "CreateDefaultShaders: shader ID must be positive!");
        
        info.vertexFunction = vertexFunc;
        info.fragmentFunction = fragmentFunc;
        info.pipelineState = pipelineState;
        info.shaderClass = eSH_World;
        info.isLoaded = true;
        info.nMaskGen = 0;
        info.shaderWrapper = new CMetalShader(shaderId, this);
        
        m_shaders[shaderId] = info;
        m_shaderNameMap[shader.name] = shaderId;
        
        assert(m_shaders.find(shaderId) != m_shaders.end() && "CreateDefaultShaders: shader should be in map!");
        assert(m_shaderNameMap.find(shader.name) != m_shaderNameMap.end() && "CreateDefaultShaders: shader name should be in map!");
        
        iLog->Log("  Loaded shader: %s (ID: %d)\n", shader.name, shaderId);
    }
    
    iLog->Log("Default shaders created: %zu shaders\n", m_shaders.size());
}

void CMetalShaderManager::LoadGeneratedShaders(id<MTLLibrary> vertexLibrary)
{
    if (!m_renderer || !m_renderer->m_device)
        return;

    NSError* error = nil;
    id<MTLLibrary> generatedLibrary = nil;
    NSBundle* bundle = [NSBundle mainBundle];
    if (bundle)
    {
        NSString* resourcePath = [bundle pathForResource:@"GeneratedShaders" ofType:@"metallib"];
        if (resourcePath)
        {
            generatedLibrary = [m_renderer->m_device newLibraryWithFile:resourcePath error:&error];
        }
    }

    if (!generatedLibrary)
    {
        NSString* exePath = [[NSBundle mainBundle] executablePath];
        NSString* exeDir = [exePath stringByDeletingLastPathComponent];
        NSString* metallibPath = [exeDir stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
        generatedLibrary = [m_renderer->m_device newLibraryWithFile:metallibPath error:&error];
        if (!generatedLibrary)
        {
            NSString* sourcePath = [NSString stringWithUTF8String:"RenderDll/XRenderMetal/Generated/GeneratedShaders.metallib"];
            generatedLibrary = [m_renderer->m_device newLibraryWithFile:sourcePath error:&error];
        }
    }

    if (!generatedLibrary)
    {
        if (iLog)
            iLog->Log("MetalShaderManager: Generated shader library not found (%s)\n", error ? [[error localizedDescription] UTF8String] : "unknown error");
        return;
    }

    m_generatedLibrary = generatedLibrary;

    NSString* manifestPath = nil;
    if (bundle)
    {
        manifestPath = [bundle pathForResource:@"generated_manifest" ofType:@"json"];
    }
    if (!manifestPath)
    {
        NSString* exePath = [[NSBundle mainBundle] executablePath];
        NSString* exeDir = [exePath stringByDeletingLastPathComponent];
        NSString* candidate = [exeDir stringByAppendingPathComponent:@"generated_manifest.json"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate])
            manifestPath = candidate;
        else
            manifestPath = [NSString stringWithUTF8String:"RenderDll/XRenderMetal/Generated/generated_manifest.json"];
    }

    NSData* manifestData = manifestPath ? [NSData dataWithContentsOfFile:manifestPath] : nil;
    if (!manifestData)
    {
        if (iLog)
            iLog->Log("MetalShaderManager: Generated shader manifest not found");
        return;
    }

    NSError* jsonError = nil;
    id manifestJson = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&jsonError];
    if (!manifestJson || ![manifestJson isKindOfClass:[NSArray class]])
    {
        if (iLog)
            iLog->Log("MetalShaderManager: Failed to parse generated shader manifest (%s)", jsonError ? [[jsonError localizedDescription] UTF8String] : "unknown error");
        return;
    }

    NSArray* entries = (NSArray*)manifestJson;
    for (NSDictionary* entry in entries)
    {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;

        NSString* shaderName = entry[@"shader"];
        NSString* normalizedName = entry[@"normalized"];
        NSString* fragmentName = entry[@"fragment"];
        NSArray* uniformArray = entry[@"uniforms"];
        NSArray* textureArray = entry[@"textures"];
        NSArray* vertexAttrArray = entry[@"vertexAttributes"];
        NSArray* vertexAttrMetaArray = entry[@"vertexAttributeMetadata"];
        NSNumber* textureCountValue = entry[@"textureCount"];
        NSArray* directiveArray = entry[@"directives"];
        NSArray* maskArray = entry[@"maskReferences"];
        NSDictionary* pipelineDict = entry[@"pipeline"];

        if (!shaderName || !fragmentName)
            continue;

        std::string normalizedKey;
        if (normalizedName && [normalizedName length] > 0)
            normalizedKey = NormalizeShaderName([normalizedName UTF8String]);
        else
            normalizedKey = NormalizeShaderName([shaderName UTF8String]);

        id<MTLFunction> fragmentFunction = [generatedLibrary newFunctionWithName:fragmentName];
        if (!fragmentFunction)
        {
            if (iLog)
                iLog->Log("MetalShaderManager: Missing generated fragment function '%s'\n", [fragmentName UTF8String]);
            continue;
        }

        int textureCount = textureCountValue ? textureCountValue.intValue : 0;
        if (textureArray && [textureArray isKindOfClass:[NSArray class]])
        {
            textureCount = static_cast<int>([textureArray count]);
        }

        VertexAttributeSummary attributeSummary = BuildAttributeSummary(vertexAttrArray, vertexAttrMetaArray, textureCount, shaderName);
        VertexLayoutInfo layout = InferVertexLayout(attributeSummary, shaderName);
        NSString* vertexFunctionName = layout.functionName;
        int vertexFormat = layout.format;
        if (shaderName && ([shaderName isEqualToString:@"CGVProgShadow_Depth2_3Samples"] ||
            [shaderName isEqualToString:@"CGRCRefractive"]))
        {
            if (iLog)
                iLog->Log("MetalShaderManager: '%s' using vertex function %s, format %d (texCoords=%d color=%d color1=%d)\n",
                          [shaderName UTF8String],
                          [vertexFunctionName UTF8String],
                          vertexFormat,
                          layout.hasTexCoords ? 1 : 0,
                          layout.hasColor ? 1 : 0,
                          layout.hasSecondColor ? 1 : 0);
            fprintf(stderr, "MetalShaderManager: '%s' using vertex function %s, format %d (tex=%d color=%d color1=%d)\n",
                    [shaderName UTF8String],
                    [vertexFunctionName UTF8String],
                    vertexFormat,
                    layout.hasTexCoords ? 1 : 0,
                    layout.hasColor ? 1 : 0,
                    layout.hasSecondColor ? 1 : 0);
        }
        id<MTLFunction> vertexFunction = nil;

        PipelineStateConfig pipelineConfig = DefaultPipelineConfig();
        ApplyPipelineConfigFromManifest(pipelineConfig, pipelineDict);

        if (vertexLibrary)
        {
            vertexFunction = [vertexLibrary newFunctionWithName:vertexFunctionName];
            if (!vertexFunction)
            {
                const char* shaderLabel = shaderName ? [shaderName UTF8String] : "<unnamed>";
                const char* functionLabel = [vertexFunctionName UTF8String];
                if (iLog)
                {
                    iLog->LogError("MetalShaderManager: Missing vertex entry '%s' required by shader '%s' - "
                                   "ensure UtilShaders.metal defines this helper and regenerate UtilShaders.metallib\n",
                                   functionLabel, shaderLabel);
                }
                assert(!"MetalShaderManager: Missing vertex entry in UtilShaders.metallib");
                return;
            }
        }
        else
        {
            if (iLog)
                iLog->Log("MetalShaderManager: No vertex library available; skipping shader '%s'\n",
                          shaderName ? [shaderName UTF8String] : "<unnamed>");
            assert(!"MetalShaderManager: No default vertex library available");
            return;
        }

        if (!vertexFunction)
        {
            if (iLog)
                iLog->Log("MetalShaderManager: Missing generated vertex function for shader '%s'\n", [shaderName UTF8String]);
            assert(!"MetalShaderManager: Missing generated vertex function");
            return;
        }

        MTLVertexDescriptor* descriptor = CMetalVertexDescriptorHelper::CreateVertexDescriptor(vertexFormat);
        if (!descriptor)
        {
            assert(!"MetalShaderManager: Failed to create vertex descriptor");
            return;
        }

        ShaderInfo info;
        info.blendEnabled = pipelineConfig.blendEnabled;
        info.blendMode = static_cast<uint32>(pipelineConfig.blendMode);
        info.sourceBlendFactor = pipelineConfig.sourceBlendFactor;
        info.destinationBlendFactor = pipelineConfig.destinationBlendFactor;
        info.blendOperation = pipelineConfig.blendOperation;
        info.sourceAlphaBlendFactor = pipelineConfig.sourceAlphaBlendFactor;
        info.destinationAlphaBlendFactor = pipelineConfig.destinationAlphaBlendFactor;
        info.alphaBlendOperation = pipelineConfig.alphaBlendOperation;
        info.depthTestEnabled = pipelineConfig.depthTestEnabled;
        info.depthWriteEnabled = pipelineConfig.depthWriteEnabled;
        info.depthCompareFunction = pipelineConfig.depthCompareFunction;
        info.cullMode = pipelineConfig.cullMode;
        info.colorWriteMask = pipelineConfig.colorWriteMask;
        info.name = normalizedKey;
        id<MTLRenderPipelineState> pipelineState = CreatePipelineStateWithFunctions(vertexFunction, fragmentFunction, descriptor, &info);
        if (!pipelineState)
        {
            if (iLog)
            {
                iLog->Log("MetalShaderManager: Skipping shader '%s' due to pipeline creation failure\n",
                          shaderName ? [shaderName UTF8String] : "<unnamed>");
                assert(false);
            }
            continue;
        }

        auto existing = m_shaderNameMap.find(normalizedKey);
        if (existing != m_shaderNameMap.end())
        {
            ReleaseShaderId(existing->second);
        }

        int shaderId = AllocateShaderId();
        info.shaderClass = eSH_Misc;
        info.isLoaded = true;
        info.nMaskGen = 0;
        info.shaderWrapper = new CMetalShader(shaderId, this);
        info.vertexFunction = vertexFunction;
        info.fragmentFunction = fragmentFunction;
        info.pipelineState = pipelineState;
        if (uniformArray && [uniformArray isKindOfClass:[NSArray class]])
        {
            for (NSDictionary* uniformDict in uniformArray)
            {
                if (![uniformDict isKindOfClass:[NSDictionary class]])
                    continue;
                GeneratedUniformBinding binding;
                NSString* uName = uniformDict[@"name"];
                NSString* uType = uniformDict[@"type"];
                NSString* uSemantic = uniformDict[@"semantic"];
                NSNumber* uArraySize = uniformDict[@"arraySize"];
                if (uName)
                    binding.name = [uName UTF8String];
                if (uType)
                    binding.type = [uType UTF8String];
                if (uSemantic)
                    binding.semantic = [uSemantic UTF8String];
                binding.arraySize = uArraySize ? uArraySize.intValue : 0;
                info.uniformBindings.push_back(binding);
            }
        }
        if (textureArray && [textureArray isKindOfClass:[NSArray class]])
        {
            for (NSDictionary* textureDict in textureArray)
            {
                if (![textureDict isKindOfClass:[NSDictionary class]])
                    continue;
                GeneratedTextureBinding binding;
                NSString* tName = textureDict[@"name"];
                NSString* tType = textureDict[@"type"];
                NSString* tSemantic = textureDict[@"semantic"];
                NSNumber* tSlot = textureDict[@"slot"];
                if (tName)
                    binding.name = [tName UTF8String];
                if (tType)
                    binding.type = [tType UTF8String];
                if (tSemantic)
                    binding.semantic = [tSemantic UTF8String];
                binding.slot = tSlot ? tSlot.intValue : static_cast<int>(info.textureBindings.size());
                info.textureBindings.push_back(binding);
            }
        }
        if (directiveArray && [directiveArray isKindOfClass:[NSArray class]])
        {
            for (NSString* directive in directiveArray)
            {
                if (![directive isKindOfClass:[NSString class]])
                    continue;
                info.directives.emplace_back([directive UTF8String]);
            }
        }
        if (maskArray && [maskArray isKindOfClass:[NSArray class]])
        {
            for (NSString* mask in maskArray)
            {
                if (![mask isKindOfClass:[NSString class]])
                    continue;
                info.maskReferences.emplace_back([mask UTF8String]);
            }
        }

        m_shaders[shaderId] = info;
        m_shaderNameMap[normalizedKey] = shaderId;

        if (iLog)
            iLog->Log("MetalShaderManager: Registered generated shader '%s' (id=%d)\n", [shaderName UTF8String], shaderId);
    }
}

id<MTLRenderPipelineState> CMetalShaderManager::CreatePipelineStateWithFunctions(
    id<MTLFunction> vertexFunction,
    id<MTLFunction> fragmentFunction,
    MTLVertexDescriptor* vertexDescriptor,
    ShaderInfo* shaderInfo)
{
    assert(vertexFunction != nil && "CreatePipelineStateWithFunctions: vertexFunction cannot be nil");
    assert(fragmentFunction != nil && "CreatePipelineStateWithFunctions: fragmentFunction cannot be nil");
    assert(vertexDescriptor != nil && "CreatePipelineStateWithFunctions: vertexDescriptor cannot be nil");
    
    assert(m_renderer != nullptr && "CreatePipelineStateWithFunctions: renderer cannot be null!");
    assert(m_renderer->m_device != nil && "CreatePipelineStateWithFunctions: Metal device cannot be nil!");
    
    if (!m_renderer || !m_renderer->m_device)
        return nil;
    
    MTLPixelFormat colorFormat = MTLPixelFormatBGRA8Unorm;
    MTLPixelFormat depthFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    bool blendEnabled = true;
    MTLBlendFactor srcBlend = MTLBlendFactorSourceAlpha;
    MTLBlendFactor dstBlend = MTLBlendFactorOneMinusSourceAlpha;
    MTLBlendOperation blendOp = MTLBlendOperationAdd;
    MTLBlendFactor srcAlphaBlend = srcBlend;
    MTLBlendFactor dstAlphaBlend = dstBlend;
    MTLBlendOperation alphaOp = blendOp;
    uint8_t colorWriteMask = 0xF;
    uint64_t renderStateHash = 0;

    if (shaderInfo)
    {
        blendEnabled = shaderInfo->blendEnabled;
        srcBlend = shaderInfo->sourceBlendFactor;
        dstBlend = shaderInfo->destinationBlendFactor;
        blendOp = shaderInfo->blendOperation;
        srcAlphaBlend = shaderInfo->sourceAlphaBlendFactor;
        dstAlphaBlend = shaderInfo->destinationAlphaBlendFactor;
        alphaOp = shaderInfo->alphaBlendOperation;
        colorWriteMask = shaderInfo->colorWriteMask;
        renderStateHash = BuildRenderStateHash(*shaderInfo);
    }
    else
    {
        ShaderInfo temp;
        temp.blendEnabled = blendEnabled;
        temp.sourceBlendFactor = srcBlend;
        temp.destinationBlendFactor = dstBlend;
        temp.blendOperation = blendOp;
        temp.sourceAlphaBlendFactor = srcAlphaBlend;
        temp.destinationAlphaBlendFactor = dstAlphaBlend;
        temp.alphaBlendOperation = alphaOp;
        temp.colorWriteMask = colorWriteMask;
        renderStateHash = BuildRenderStateHash(temp);
    }

    MetalPipelineStateKey key;
    key.vertexFunctionHash = (uint64_t)vertexFunction;
    key.fragmentFunctionHash = (uint64_t)fragmentFunction;
    key.vertexFormatHash = 0;
    key.renderStateHash = renderStateHash;
    key.colorPixelFormat = colorFormat;
    key.depthPixelFormat = depthFormat;
    
    if (m_renderer->m_stateCache && vertexFunction && fragmentFunction && vertexDescriptor) // Only cache if functions are valid
    {
        id<MTLRenderPipelineState> cachedState = m_renderer->m_stateCache->GetOrCreatePipelineState(
                key, vertexFunction, fragmentFunction, vertexDescriptor);

        if (cachedState)
            return cachedState;
    }
    
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.vertexDescriptor = vertexDescriptor;
    
    descriptor.colorAttachments[0].pixelFormat = colorFormat;
    descriptor.colorAttachments[0].blendingEnabled = blendEnabled ? YES : NO;
    if (blendEnabled)
    {
        descriptor.colorAttachments[0].sourceRGBBlendFactor = srcBlend;
        descriptor.colorAttachments[0].destinationRGBBlendFactor = dstBlend;
        descriptor.colorAttachments[0].rgbBlendOperation = blendOp;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = srcAlphaBlend;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = dstAlphaBlend;
        descriptor.colorAttachments[0].alphaBlendOperation = alphaOp;
    }
    MTLColorWriteMask writeMask = 0;
    if (colorWriteMask & 0x1)
        writeMask |= MTLColorWriteMaskRed;
    if (colorWriteMask & 0x2)
        writeMask |= MTLColorWriteMaskGreen;
    if (colorWriteMask & 0x4)
        writeMask |= MTLColorWriteMaskBlue;
    if (colorWriteMask & 0x8)
        writeMask |= MTLColorWriteMaskAlpha;
    descriptor.colorAttachments[0].writeMask = writeMask;
 
    descriptor.depthAttachmentPixelFormat = depthFormat;
    descriptor.stencilAttachmentPixelFormat = depthFormat;
    
    NSError* error = nil;
    id<MTLRenderPipelineState> pipelineState = 
        [m_renderer->m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    
    if (!pipelineState)
    {
        const char* vsName = vertexFunction && [vertexFunction label]
            ? [[vertexFunction label] UTF8String]
            : "<unnamed>";
        const char* fsName = fragmentFunction && [fragmentFunction label]
            ? [[fragmentFunction label] UTF8String]
            : "<unnamed>";
        const char* shaderName = (shaderInfo && !shaderInfo->name.empty())
            ? shaderInfo->name.c_str()
            : "<unnamed>";
        if (error)
        {
            const char* errorText = [[error localizedDescription] UTF8String];
            iLog->Log("CreatePipelineState failed for shader '%s' VS '%s' / FS '%s': %s\n", shaderName, vsName, fsName, errorText);
            fprintf(stderr, "CreatePipelineState failed for shader '%s' VS '%s' / FS '%s': %s\n", shaderName, vsName, fsName, errorText);
        }
        else
        {
            iLog->Log("CreatePipelineState failed for shader '%s' VS '%s' / FS '%s' with unknown error\n", shaderName, vsName, fsName);
            fprintf(stderr, "CreatePipelineState failed for shader '%s' VS '%s' / FS '%s' with unknown error\n", shaderName, vsName, fsName);
        }
        
        NSString* compilerError = error.userInfo[@"MTLCompilerErrorKey"];
        if (compilerError)
        {
            const char* errorDetails = [compilerError UTF8String];
            iLog->Log("Metal compiler output for shader '%s':\n%s\n", shaderName, errorDetails);
            fprintf(stderr, "Metal compiler output for shader '%s':\n%s\n", shaderName, errorDetails);
        }
    }

    if (!pipelineState && error)
    {
        iLog->Log("CreatePipelineStateWithFunctions: Unable to build pipeline state (%s)\n",
                  [[error localizedDescription] UTF8String]);
    }
    
    return pipelineState;
}

id<MTLRenderPipelineState> CMetalShaderManager::CreatePipelineState(
    id<MTLFunction> vertexFunction,
    id<MTLFunction> fragmentFunction,
    MTLVertexDescriptor* vertexDescriptor)
{
    assert(vertexFunction != nil && "CreatePipelineState: vertexFunction cannot be nil!");
    assert(fragmentFunction != nil && "CreatePipelineState: fragmentFunction cannot be nil!");
    assert(vertexDescriptor != nil && "CreatePipelineState: vertexDescriptor cannot be nil!");
 
    return CreatePipelineStateWithFunctions(vertexFunction, fragmentFunction, vertexDescriptor, nullptr);
}

void CMetalShaderManager::SetShaderUniforms(id<MTLRenderCommandEncoder> encoder, 
                                           const SShaderParam& params)
{
    assert(encoder != nil && "SetShaderUniforms: encoder cannot be nil!");
    assert(m_renderer != nullptr && "SetShaderUniforms: renderer cannot be null!");
    
    if (!encoder || !m_renderer)
        return;
    
    m_renderer->UpdateUniformBuffer();
    
    if (m_renderer->m_uniformBuffer)
    {
        [encoder setVertexBuffer:m_renderer->m_uniformBuffer offset:0 atIndex:1];
        [encoder setFragmentBuffer:m_renderer->m_uniformBuffer offset:0 atIndex:0];
    }
}

int CMetalShaderManager::AllocateShaderId()
{
    int id = m_nextShaderId++;
    assert(id > 0 && "AllocateShaderId: shader ID must be positive!");
    assert(m_nextShaderId > id && "AllocateShaderId: shader ID counter overflow!");
    return id;
}

void CMetalShaderManager::ReleaseShaderId(int id)
{
    assert(id > 0 && "ReleaseShaderId: shader ID must be positive!");
    
    auto it = m_shaders.find(id);
    if (it != m_shaders.end())
    {
        ShaderInfo& info = it->second;
        info.shaderWrapper = nullptr;
        
        std::string nameToRemove = info.name;
        m_shaders.erase(it);
        
        auto nameIt = m_shaderNameMap.find(nameToRemove);
        if (nameIt != m_shaderNameMap.end() && nameIt->second == id)
        {
            m_shaderNameMap.erase(nameIt);
        }
    }
}

void CMetalShaderManager::ClearAllShaders()
{
    for (auto& pair : m_shaders)
    {
        ShaderInfo& info = pair.second;
        if (info.shaderWrapper)
        {
            info.shaderWrapper->m_manager = nullptr;
            info.shaderWrapper->Release(true);
            info.shaderWrapper = nullptr;
        }
    }
    
    m_shaders.clear();
    m_shaderNameMap.clear();
    m_nextShaderId = 1;
    m_currentShaderId = 0;
    m_currentPipelineState = nil;
}

void CMetalShaderManager::ShareCacheWith(CMetalShaderManager* other)
{
    if (!other || other == this)
        return;
    
    for (const auto& shaderPair : other->m_shaders) {
        const ShaderInfo& shaderInfo = shaderPair.second;
        
        if (!shaderInfo.name.empty()) {
            auto nameIt = m_shaderNameMap.find(shaderInfo.name);
            if (nameIt == m_shaderNameMap.end()) {
                int newShaderId = AllocateShaderId();
                ShaderInfo info = shaderInfo;
                info.shaderWrapper = new CMetalShader(newShaderId, this);
                m_shaders[newShaderId] = info;
                m_shaderNameMap[shaderInfo.name] = newShaderId;
            }
        }
    }
    
    for (const auto& shaderPair : m_shaders) {
        const ShaderInfo& shaderInfo = shaderPair.second;
        
        if (!shaderInfo.name.empty()) {
            auto nameIt = other->m_shaderNameMap.find(shaderInfo.name);
            if (nameIt == other->m_shaderNameMap.end()) {
                int newShaderId = other->AllocateShaderId();
                ShaderInfo info = shaderInfo;
                info.shaderWrapper = new CMetalShader(newShaderId, other);
                other->m_shaders[newShaderId] = info;
                other->m_shaderNameMap[shaderInfo.name] = newShaderId;
            }
        }
    }
}

int CMetalShaderManager::GetShaderCount() const
{
    return static_cast<int>(m_shaders.size());
}

void CMetalShaderManager::SetGlobalShaderTemplateId(int nTemplateId)
{
    m_globalShaderTemplateId = nTemplateId;
}

int CMetalShaderManager::GetGlobalShaderTemplateId() const
{
    return m_globalShaderTemplateId;
}

void CMetalShaderManager::EF_EnableHeatVision(bool bEnable)
{
    if (m_renderer)
        m_renderer->CRenderer::EF_EnableHeatVision(bEnable);
    m_heatVisionEnabled = bEnable;
}

bool CMetalShaderManager::EF_GetHeatVision()
{
    if (m_renderer)
        return m_renderer->CRenderer::EF_GetHeatVision();
    return m_heatVisionEnabled;
}

void CMetalShaderManager::EF_PolygonOffset(bool bEnable, float fFactor, float fUnits)
{
    assert(m_renderer != nullptr && "EF_PolygonOffset: renderer cannot be null!");
    
    if (!m_renderer || !m_renderer->m_renderEncoder)
        return;
    
    if (bEnable)
    {
        [m_renderer->m_renderEncoder setDepthBias:fUnits slopeScale:fFactor clamp:0.0f];
    }
    else
    {
        [m_renderer->m_renderEncoder setDepthBias:0.0f slopeScale:0.0f clamp:0.0f];
    }
}

id<MTLRenderPipelineState> CMetalShaderManager::GetPipelineStateForShader(const char* shaderName)
{
    assert(shaderName != nullptr && "GetPipelineStateForShader: shaderName cannot be null!");
    
    if (!shaderName)
        return nil;
    
    auto it = m_shaderNameMap.find(shaderName);
    if (it != m_shaderNameMap.end())
    {
        int shaderId = it->second;
        auto shaderIt = m_shaders.find(shaderId);
        if (shaderIt != m_shaders.end())
        {
            return shaderIt->second.pipelineState;
        }
    }
    
    return nil;
}

id<MTLRenderPipelineState> CMetalShaderManager::GetPipelineStateForFormat(int vertexFormat)
{
    const char* shaderName = "colortex";
    
    switch (vertexFormat)
    {
        case VERTEX_FORMAT_P3F:
            shaderName = "simple";
            break;
        case VERTEX_FORMAT_P3F_COL4UB:
            shaderName = "color";
            break;
        case VERTEX_FORMAT_P3F_COL4UB_TEX2F:
        case VERTEX_FORMAT_P3F_N_COL4UB_TEX2F:
            shaderName = "colortex";
            break;
        default:
            shaderName = "basic";
            break;
    }
    
    return GetPipelineStateForShader(shaderName);
}

#endif

