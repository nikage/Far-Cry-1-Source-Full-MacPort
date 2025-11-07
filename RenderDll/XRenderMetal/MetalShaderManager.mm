////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalShaderManager.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal shader manager implementation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalShaderManager.m"
#include "MetalBaseRenderer.m"
#include "MetalTextureManager.m"
#include "MetalRenderElements.m"  // For Metal render element classes
#include "MetalVertexDescriptor.m"  // For CMetalVertexDescriptorHelper
#include <Cocoa/Cocoa.h>
#include <cassert>
#include <iostream>


// Render element implementations moved to MetalRenderElements.cpp to avoid duplicates
// Constructor and destructor are in MetalShaderLoader.cpp to avoid duplicates

static void ConvertDOSToUnixName(char* dst, const char* src)
{
    while (*src)
    {
        if (*src == '\\')
            *dst = '/';
        else
            *dst = *src;
        dst++;
        src++;
    }
    *dst = 0;
}

static const char* GetExtension(const char* filename)
{
    if (!filename)
        return nullptr;
    
    const char* ext = nullptr;
    const char* p = filename;
    while (*p)
    {
        if (*p == '.')
            ext = p;
        p++;
    }
    return ext;
}

static std::string NormalizeShaderName(const char* name)
{
    if (!name)
        return "";
    
    char normalized[256];
    strncpy(normalized, name, sizeof(normalized) - 1);
    normalized[sizeof(normalized) - 1] = 0;
    
    ConvertDOSToUnixName(normalized, normalized);
    ::strlwr(normalized);
    
    return std::string(normalized);
}

CMetalShader::CMetalShader(int shaderId, CMetalShaderManager* manager)
    : m_shaderId(shaderId)
    , m_manager(manager)
    , m_refCount(1)
    , m_flags(0)
    , m_flags2(0)
    , m_flags3(0)
    , m_renderFlags(0)
    , m_sort(eS_Unknown)
    , m_cull(eCULL_Back)
    , m_templates(nullptr)
    , m_shaderGenParams(nullptr)
    , m_pGenShader(nullptr)
    , m_LMFlags(0)
{
    assert(manager != nullptr && "CMetalShader: manager cannot be null!");
    assert(shaderId > 0 && "CMetalShader: shaderId must be positive!");
}

CMetalShader::~CMetalShader()
{
    if (m_templates)
    {
        if (m_templates->m_TemplShaders.Num() > 0)
        {
            for (int i = 0; i < m_templates->m_TemplShaders.Num(); i++)
            {
                IShader* shader = reinterpret_cast<IShader*>(m_templates->m_TemplShaders[i]);
                if (shader && shader != this)
                {
                    shader->Release();
                }
            }
        }
        delete m_templates;
        m_templates = nullptr;
    }
    
    if (m_shaderGenParams)
    {
        for (int i = 0; i < m_shaderGenParams->m_BitMask.Num(); i++)
        {
            SShaderGenBit* bit = m_shaderGenParams->m_BitMask[i];
            if (bit)
            {
                delete bit;
            }
        }
        delete m_shaderGenParams;
        m_shaderGenParams = nullptr;
    }
    
    m_pGenShader = nullptr;
}

int CMetalShader::GetID()
{
    return m_shaderId;
}

void CMetalShader::AddRef()
{
    assert(m_refCount > 0 && "CMetalShader: Invalid ref count!");
    m_refCount++;
}

void CMetalShader::Release(bool bForce)
{
    assert(m_refCount > 0 && "CMetalShader: Release called on object with zero ref count!");
    
    m_refCount--;
    if (m_refCount <= 0 || bForce)
    {
        CMetalShaderManager* manager = m_manager;
        int shaderId = m_shaderId;
        m_manager = nullptr;
        
        if (manager)
        {
            manager->ReleaseShaderId(shaderId);
        }
        delete this;
    }
}

int CMetalShader::GetRefCount()
{
    return m_refCount;
}

const char* CMetalShader::GetName()
{
    if (!m_manager)
    {
        assert(false);
        return "";
    }
    
    auto it = m_manager->m_shaders.find(m_shaderId);
    if (it != m_manager->m_shaders.end())
    {
        return it->second.name.c_str();
    }
    iLog->LogWarning("Shader %d not found in shader manager!", m_shaderId);
    return "";
}

EF_Sort CMetalShader::GetSort()
{
    return m_sort;
}

int CMetalShader::GetFlags()
{
    return m_flags;
}

int CMetalShader::GetFlags2()
{
    return m_flags2;
}

int CMetalShader::GetFlags3()
{
    return m_flags3;
}

int CMetalShader::GetRenderFlags()
{
    return m_renderFlags;
}

void CMetalShader::SetRenderFlags(int nFlags)
{
    m_renderFlags = nFlags;
}

int CMetalShader::GetLFlags()
{
    return m_LMFlags;
}

int CMetalShader::GetCull()
{
    return m_cull;
}

uint CMetalShader::GetPreprocessFlags()
{
    return 0;
}

void CMetalShader::SetFlags3(int Flags)
{
    m_flags3 |= Flags;
}

bool CMetalShader::Reload(int nFlags)
{
    return true;
}

TArray<CRendElement*>* CMetalShader::GetREs()
{
    return &m_renderElements;
}

bool CMetalShader::AddTemplate(SRenderShaderResources* Res, int& TemplId, const char* Name, bool bSetPreferred, uint64 nMaskGen)
{
    if (m_flags2 & (EF2_TEMPLATE | EF_SYSTEM))
        return false;
    
    if (!m_templates)
    {
        m_templates = new SEfTemplates;
    }
    
    if (TemplId < 0)
    {
        if (!Name || !Name[0])
            return false;
        
        for (int i = EFT_USER_FIRST; i < m_templates->m_TemplShaders.Num(); i++)
        {
            IShader* sh = reinterpret_cast<IShader*>(m_templates->m_TemplShaders[i]);
            if (sh && !strcmp(Name, sh->GetName()))
            {
                TemplId = i;
                return true;
            }
        }
        TemplId = m_templates->m_TemplShaders.Num();
    }
    
    if (TemplId >= m_templates->m_TemplShaders.Num())
    {
        m_templates->m_TemplShaders.ReserveNew(TemplId + 1);
        while (m_templates->m_TemplShaders.Num() <= TemplId)
        {
            m_templates->m_TemplShaders.AddElem(nullptr);
        }
    }
    
    if (Name && Name[0] && m_manager)
    {
        IShader* templateShader = m_manager->EF_LoadShader(Name, eSH_Misc, 0, nMaskGen);
        if (templateShader)
        {
            IShader* oldShader = reinterpret_cast<IShader*>(m_templates->m_TemplShaders[TemplId]);
            if (oldShader && oldShader != this)
            {
                oldShader->Release();
            }
            m_templates->m_TemplShaders[TemplId] = reinterpret_cast<SShader*>(templateShader);
            
            if (bSetPreferred)
            {
                m_templates->m_Preferred = reinterpret_cast<SShader*>(templateShader);
                m_templates->m_nPreferred = TemplId;
            }
            
            return true;
        }
    }
    
    return false;
}

void CMetalShader::RemoveTemplate(int TemplId)
{
    if (!m_templates || TemplId < 0 || TemplId >= m_templates->m_TemplShaders.Num())
        return;
    
    if (!m_templates->m_TemplShaders[TemplId])
        return;
    
    IShader* shader = reinterpret_cast<IShader*>(m_templates->m_TemplShaders[TemplId]);
    if (shader && shader != this)
    {
        shader->Release();
    }
    
    m_templates->m_TemplShaders[TemplId] = nullptr;
    
    if (m_templates->m_nPreferred == TemplId)
    {
        m_templates->m_Preferred = nullptr;
        m_templates->m_nPreferred = -1;
    }
}

IShader* CMetalShader::GetTemplate(int num)
{
    if (!m_templates)
        return this;
    
    if (num >= 0 && num < m_templates->m_TemplShaders.Num() && m_templates->m_TemplShaders[num])
    {
        return reinterpret_cast<IShader*>(m_templates->m_TemplShaders[num]);
    }
    
    if (m_templates->m_Preferred)
    {
        return reinterpret_cast<IShader*>(m_templates->m_Preferred);
    }
    
    return this;
}

SEfTemplates* CMetalShader::GetTemplates()
{
    return m_templates;
}

TArray<SShaderParam>& CMetalShader::GetPublicParams()
{
    return m_publicParams;
}

int CMetalShader::GetTexId()
{
    return 0;
}

ITexPic* CMetalShader::GetBaseTexture(int* nPass, int* nTU)
{
    if (nPass)
        *nPass = 0;
    if (nTU)
        *nTU = 0;
    return nullptr;
}

unsigned int CMetalShader::GetUsedTextureTypes(void)
{
    return 0;
}

int CMetalShader::GetVertexFormat(void)
{
    return 0;
}

int CMetalShader::Size(int Flags)
{
    return 0;
}

uint64 CMetalShader::GetGenerationMask()
{
    if (!m_manager)
        return 0;
    
    auto it = m_manager->m_shaders.find(m_shaderId);
    if (it != m_manager->m_shaders.end())
    {
        return it->second.nMaskGen;
    }
    return 0;
}

SShaderGen* CMetalShader::GetGenerationParams()
{
    if (m_shaderGenParams)
        return m_shaderGenParams;
    if (m_pGenShader)
        return m_pGenShader->m_shaderGenParams;
    return nullptr;
}

// Shader System Interface (EF_ methods)
bool CMetalShaderManager::EF_PrecacheResource(IShader* pSH, float fDist, float fTimeToReady, int Flags)
{
    if (!pSH)
        return false;
        
    // Precache shader resources
    return true;
}

bool CMetalShaderManager::EF_PrecacheResource(ITexPic* pTP, float fDist, float fTimeToReady, int Flags)
{
    if (!pTP)
        return false;
        
    // Precache texture resources
    return true;
}

bool CMetalShaderManager::EF_PrecacheResource(CLeafBuffer* pPB, float fDist, float fTimeToReady, int Flags)
{
    if (!pPB)
        return false;
        
    // Precache geometry resources
    return true;
}

bool CMetalShaderManager::EF_PrecacheResource(CDLight* pLS, float fDist, float fTimeToReady, int Flags)
{
    if (!pLS)
        return false;
        
    // Precache light resources
    return true;
}

void CMetalShaderManager::EF_AddPolyToScene3D(int Ef, int numPts, SColorVert* verts, CCObject* obj, int nFogID)
{
    // Add 3D polygon to scene
    // This would queue the polygon for rendering
}

CCObject* CMetalShaderManager::EF_AddSpriteToScene(int Ef, int numPts, SColorVert* verts, CCObject* obj, byte* inds, int ninds, int nFogID)
{
    // Add sprite to scene
    // This would create and return a CCObject for the sprite
    return nullptr;
}

void CMetalShaderManager::EF_AddPolyToScene2D(int Ef, int numPts, SColorVert2D* verts)
{
    // Add 2D polygon to scene
    // This would queue the 2D polygon for rendering
}

void CMetalShaderManager::EF_AddPolyToScene2D(SShaderItem si, int nTempl, int numPts, SColorVert2D* verts)
{
    // Add 2D polygon to scene with shader item
    // This would queue the 2D polygon for rendering with specific shader
}

// Shader Management
IShader* CMetalShaderManager::EF_LoadShader(const char* name, EShClass Class, int flags, uint64 nMaskGen)
{
    if (!name || !name[0])
        return nullptr;
    
    std::string normalizedName = NormalizeShaderName(name);
    if (normalizedName.empty())
        return nullptr;
    
    std::string lookupName = normalizedName;
    if (nMaskGen != 0)
    {
        char nameWithMask[512];
        snprintf(nameWithMask, sizeof(nameWithMask), "%s(%llx)", normalizedName.c_str(), (unsigned long long)nMaskGen);
        lookupName = nameWithMask;
    }
    
    auto nameIt = m_shaderNameMap.find(lookupName);
    if (nameIt != m_shaderNameMap.end())
    {
        auto shaderIt = m_shaders.find(nameIt->second);
        if (shaderIt != m_shaders.end())
        {
            ShaderInfo& info = shaderIt->second;
            if (info.shaderWrapper)
            {
                if (!(flags & 1))
                {
                    info.shaderWrapper->AddRef();
                    if (flags != 0)
                    {
                        info.shaderWrapper->m_flags |= flags;
                    }
                    return info.shaderWrapper;
                }
            }
        }
    }
    
    if (flags & 1)
    {
        if (nameIt != m_shaderNameMap.end())
        {
            int shaderId = nameIt->second;
            auto shaderIt = m_shaders.find(shaderId);
            if (shaderIt != m_shaders.end())
            {
                ShaderInfo& info = shaderIt->second;
                if (info.shaderWrapper)
                {
                    info.shaderWrapper->Release(true);
                }
                m_shaders.erase(shaderIt);
                m_shaderNameMap.erase(nameIt);
            }
        }
    }
    
    auto defaultIt = m_shaderNameMap.find(normalizedName);
    if (defaultIt != m_shaderNameMap.end())
    {
        auto shaderIt = m_shaders.find(defaultIt->second);
        if (shaderIt != m_shaders.end())
        {
            ShaderInfo& baseInfo = shaderIt->second;
            
            int shaderId = AllocateShaderId();
            ShaderInfo info = baseInfo;
            info.name = lookupName;
            info.nMaskGen = nMaskGen;
            info.shaderWrapper = new CMetalShader(shaderId, this);
            
            if (nMaskGen != 0 && baseInfo.shaderWrapper)
            {
                info.shaderWrapper->m_pGenShader = baseInfo.shaderWrapper;
            }
            
            m_shaders[shaderId] = info;
            m_shaderNameMap[lookupName] = shaderId;
            
            return info.shaderWrapper;
        }
    }
    
    return nullptr;
}

SShaderItem CMetalShaderManager::EF_LoadShaderItem(const char* name, EShClass Class, bool bShare, const char* templName, int flags, SInputShaderResources* Res, uint64 nMaskGen)
{
    // Load shader item
    SShaderItem item;
    // Initialize shader item
    return item;
}

bool CMetalShaderManager::EF_ReloadFile(const char* szFileName)
{
    if (!szFileName)
        return false;
        
    // Reload shader file
    return true;
}

void CMetalShaderManager::EF_ReloadShaderFiles(int nCategory)
{
    // Reload all shader files in category
}

void CMetalShaderManager::EF_ReloadTextures()
{
    // Reload all textures
}

IShader* CMetalShaderManager::EF_CopyShader(IShader* ef)
{
    if (!ef)
        return nullptr;
        
    // Copy shader
    return nullptr;
}

char** CMetalShaderManager::EF_GetShadersForFile(const char* File, int num)
{
    if (!File)
        return nullptr;
        
    // Get shaders for file
    return nullptr;
}

SLightMaterial* CMetalShaderManager::EF_GetLightMaterial(char* Str)
{
    if (!Str)
        return nullptr;
        
    // Get light material
    return nullptr;
}

bool CMetalShaderManager::EF_RegisterTemplate(int nTemplId, char* Name, bool bReplace)
{
    if (!Name)
        return false;
        
    // Register shader template
    return true;
}

void CMetalShaderManager::EF_AddSplash(Vec3 Pos, eSplashType eST, float fForce, int Id)
{
    // Add splash effect
}

bool CMetalShaderManager::EF_HideTemplate(const char* name)
{
    if (!name)
        return false;
        
    // Hide shader template
    return true;
}

bool CMetalShaderManager::EF_UnhideTemplate(const char* name)
{
    if (!name)
        return false;
        
    // Unhide shader template
    return true;
}

bool CMetalShaderManager::EF_UnhideAllTemplates()
{
    // Unhide all shader templates
    return true;
}

bool CMetalShaderManager::EF_SetLightHole(Vec3 vPos, Vec3 vNormal, int idTex, float fScale, bool bAdditive)
{
    // Set light hole
    return true;
}


void CMetalShaderManager::EF_StartEf()
{
    // Start shader effects
}

CCObject* CMetalShaderManager::EF_GetObject(bool bTemp, int num)
{
    // Get CCObject for rendering
    return nullptr;
}

void CMetalShaderManager::EF_AddEf(int NumFog, CRendElement* re, IShader* ef, SRenderShaderResources* sr, CCObject* obj, int nTempl, IShader* efState, int nSort)
{
    // Add shader effect to render list
}

void CMetalShaderManager::EF_EndEf3D(int nFlags)
{
    // End 3D shader effects
}

bool CMetalShaderManager::EF_IsFakeDLight(CDLight* Source)
{
    if (!Source)
        return false;
        
    // Check if light is fake
    return false;
}

void CMetalShaderManager::EF_ADDDlight(CDLight* Source)
{
    if (!Source)
        return;
        
    // Add dynamic light
}

void CMetalShaderManager::EF_ClearLightsList()
{
    // Clear dynamic lights list
}

bool CMetalShaderManager::EF_UpdateDLight(CDLight* pDL)
{
    if (!pDL)
        return false;
        
    // Update dynamic light
    return true;
}

void CMetalShaderManager::EF_EndEf2D(bool bSort)
{
    // End 2D shader effects
}

bool CMetalShaderManager::EF_DrawEfForName(char* name, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    if (!name)
        return false;
        
    // Draw shader effect by name
    return true;
}

bool CMetalShaderManager::EF_DrawEfForNum(int num, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    // Draw shader effect by number
    return true;
}

bool CMetalShaderManager::EF_DrawEf(IShader* ef, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    if (!ef)
        return false;
        
    // Draw shader effect
    return true;
}

bool CMetalShaderManager::EF_DrawEf(SShaderItem si, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    // Draw shader effect with shader item
    return true;
}

bool CMetalShaderManager::EF_DrawPartialEfForName(char* name, SVrect* vr, SVrect* pr, CFColor& col)
{
    if (!name)
        return false;
        
    // Draw partial shader effect by name
    return true;
}

bool CMetalShaderManager::EF_DrawPartialEfForNum(int num, SVrect* vr, SVrect* pr, CFColor& col)
{
    // Draw partial shader effect by number
    return true;
}

bool CMetalShaderManager::EF_DrawPartialEf(IShader* ef, SVrect* vr, SVrect* pr, CFColor& col, float iwdt, float ihgt)
{
    if (!ef)
        return false;
        
    // Draw partial shader effect
    return true;
}

void* CMetalShaderManager::EF_Query(int Query, int Param)
{
    // Query shader system
    return nullptr;
}

void CMetalShaderManager::EF_ConstructEf(IShader* Ef)
{
    if (!Ef)
        return;
        
    // Construct shader effect
}

void CMetalShaderManager::EF_SetWorldColor(float r, float g, float b, float a)
{
    // Set world color for shaders
}

int CMetalShaderManager::EF_RegisterFogVolume(float fMaxFogDist, float fFogLayerZ, CFColor color, int nIndex, bool bCaustics)
{
    // Register fog volume
    return 0;
}

// LeafBuffer Management
CLeafBuffer* CMetalShaderManager::CreateLeafBuffer(bool bDynamic, const char* szSource, class CIndexedMesh* pIndexedMesh)
{
    if (!szSource)
        return nullptr;
        
    // Create leaf buffer
    return nullptr;
}

CLeafBuffer* CMetalShaderManager::CreateLeafBufferInitialized(void* pVertBuffer, int nVertCount, int nVertFormat, ushort* pIndices, int nIndices, int nPrimetiveType, const char* szSource, EBufferType eBufType, int nMatInfoCount, int nClientTextureBindID, bool (*PrepareBufferCallback)(CLeafBuffer*, bool), void* CustomData, bool bOnlyVideoBuffer, bool bPrecache)
{
    if (!pVertBuffer || !szSource)
        return nullptr;
        
    // Create initialized leaf buffer
    return nullptr;
}

void CMetalShaderManager::DeleteLeafBuffer(CLeafBuffer* pLBuffer)
{
    if (!pLBuffer)
        return;
        
    // Delete leaf buffer
}

// Protected methods
bool CMetalShaderManager::LoadShaderFromFile(const char* filename, std::string& source)
{
    if (!filename || !filename[0])
    {
        iLog->Log("CMetalShaderManager::LoadShaderFromFile: Invalid filename\n");
        return false;
    }
    
    source.clear();
    
    std::string shaderPath = filename;
    ConvertDOSToUnixName(const_cast<char*>(shaderPath.c_str()), const_cast<char*>(shaderPath.c_str()));
    
    const char* ext = GetExtension(shaderPath.c_str());
    bool hasMetalExt = ext && !stricmp(ext, ".metal");
    
    if (!hasMetalExt)
    {
        shaderPath += ".metal";
    }
    
    FILE* fp = nullptr;
    std::string fullPath;
    
    if (shaderPath[0] == '/' || (shaderPath.length() > 1 && shaderPath[1] == ':'))
    {
        fullPath = shaderPath;
        fp = GetISystem()->GetIPak()->FOpen(fullPath.c_str(), "rb");
    }
    
    if (!fp)
    {
        const char* searchPaths[] = {
            "Shaders/Metal/",
            "Shaders/HWScripts/Metal/",
            "Shaders/HWScripts/Declarations/Metal/",
            "Shaders/",
            ""
        };
        
        for (auto & searchPath : searchPaths)
        {
            fullPath = searchPath;
            if (!fullPath.empty())
            {
                fullPath += shaderPath;
            }
            else
            {
                fullPath = shaderPath;
            }
            
            ConvertDOSToUnixName(const_cast<char*>(fullPath.c_str()), const_cast<char*>(fullPath.c_str()));
            fp = GetISystem()->GetIPak()->FOpen(fullPath.c_str(), "rb");
            
            if (fp)
            {
                break;
            }
        }
    }
    
    if (!fp)
    {
        iLog->Log("CMetalShaderManager::LoadShaderFromFile: Could not find shader file '%s'\n", filename);
        return false;
    }
    
    GetISystem()->GetIPak()->FSeek(fp, 0, SEEK_END);
    long fileSize = GetISystem()->GetIPak()->FTell(fp);
    
    if (fileSize <= 0)
    {
        GetISystem()->GetIPak()->FClose(fp);
        iLog->Log("CMetalShaderManager::LoadShaderFromFile: Shader file '%s' is empty\n", fullPath.c_str());
        return false;
    }
    
    GetISystem()->GetIPak()->FSeek(fp, 0, SEEK_SET);
    
    source.resize(fileSize);
    size_t bytesRead = GetISystem()->GetIPak()->FRead(&source[0], 1, fileSize, fp);
    GetISystem()->GetIPak()->FClose(fp);
    
    if (bytesRead != static_cast<size_t>(fileSize))
    {
        iLog->Log("CMetalShaderManager::LoadShaderFromFile: Failed to read entire shader file '%s' (read %zu of %ld bytes)\n", 
                  fullPath.c_str(), bytesRead, fileSize);
        source.clear();
        return false;
    }
    
    iLog->Log("CMetalShaderManager::LoadShaderFromFile: Successfully loaded shader from '%s' (%ld bytes)\n", 
              fullPath.c_str(), fileSize);
    
    return true;
}

bool CMetalShaderManager::CompileShader(const std::string& source, id<MTLFunction>& function)
{
    if (!m_renderer || !m_renderer->m_device)
        return false;
        
    NSError* error = nil;
    id<MTLLibrary> library = [m_renderer->m_device newLibraryWithSource:@(source.c_str()) options:nil error:&error];
    if (!library)
    {
        iLog->Log("Error: Failed to create Metal library: %s\n", error ? [[error localizedDescription] UTF8String] : "Unknown error");
        return false;
    }
    
    // Get the main function
    function = [library newFunctionWithName:@"main"];
    return function != nil;
}

void CMetalShaderManager::SetShaderParameters(id<MTLRenderCommandEncoder> encoder, IShader* shader)
{
    if (!encoder || !shader)
        return;
        
    // Set shader parameters
}

void CMetalShaderManager::BindShaderTextures(id<MTLRenderCommandEncoder> encoder, IShader* shader)
{
    if (!encoder || !shader)
        return;
        
    // Bind shader textures
}

#endif // __APPLE__ && __MACH__
