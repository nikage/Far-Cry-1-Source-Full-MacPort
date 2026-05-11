////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalShaderManager.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal shader manager class
//               Handles all shader operations for Metal API
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_SHADER_MANAGER_H
#define METAL_SHADER_MANAGER_H

#if defined(__APPLE__) && defined(__MACH__)

#include <Metal/Metal.h>
#include <MetalKit/MetalKit.h>
#include <vector>
#include <unordered_map>
#include <string>
#include <cstdint>
#include "MetalGeneratedVertex.h"
#include "MetalPerShaderUniforms.h"
#include "MetalMaterialTextureBinder.h"

// Include CryEngine interfaces
#include "IRenderer.h"
#include "IShader.h"
#include "Cry_Math.h"

// Forward declarations
class CMetalBaseRenderer;
class CMetalTextureManager;
class CMetalShaderManager;
struct SShader;

enum class UniformScalarType : uint8_t
{
    Float,
    Int,
    Bool
};

enum class UniformValueSource : uint8_t
{
    ShaderParam,
    RendererModelViewProj,
    RendererModel,
    RendererView,
    RendererProjection,
    RendererCameraPos,
    RendererLightPos,
    RendererLightColor,
    RendererClipPlane,
    RendererClipEnabled,
    RendererClipRefract,
    RendererTime,
    RendererGlobalFogColor
};

class CMetalShader : public IShader
{
    friend class CMetalShaderManager;
    
public:
    CMetalShader(int shaderId, CMetalShaderManager* manager);
    virtual ~CMetalShader();
    
    virtual int GetID();
    virtual void AddRef();
    virtual void Release(bool bForce = false);
    virtual int GetRefCount();
    virtual const char* GetName();
    virtual EF_Sort GetSort();
    virtual int GetFlags();
    virtual int GetFlags2();
    virtual int GetFlags3();
    virtual int GetRenderFlags();
    virtual void SetRenderFlags(int nFlags);
    virtual int GetLFlags();
    virtual int GetCull();
    virtual uint GetPreprocessFlags();
    virtual void SetFlags3(int Flags);
    virtual bool Reload(int nFlags);
    virtual TArray<CRendElement*>* GetREs();
    virtual bool AddTemplate(SRenderShaderResources* Res, int& TemplId, const char* Name = NULL, bool bSetPreferred = false, uint64 nMaskGen = 0);
    virtual void RemoveTemplate(int TemplId);
    virtual IShader* GetTemplate(int num);
    virtual SEfTemplates* GetTemplates();
    virtual TArray<SShaderParam>& GetPublicParams();
    virtual int GetTexId();
    virtual ITexPic* GetBaseTexture(int* nPass, int* nTU);
    virtual unsigned int GetUsedTextureTypes(void);
    virtual int GetVertexFormat(void);
    virtual int Size(int Flags);
    virtual uint64 GetGenerationMask();
    virtual SShaderGen* GetGenerationParams();

    void ApplyRendPipelineSortFlags(bool depthWriteEnabled, bool blendEnabled);
    
private:
    int m_shaderId;
    CMetalShaderManager* m_manager;
    int m_refCount;
    uint m_flags;
    uint m_flags2;
    uint m_flags3;
    int m_renderFlags;
    EF_Sort m_sort;
    ECull m_cull;
    TArray<SShaderParam> m_publicParams;
    TArray<CRendElement*> m_renderElements;
    SEfTemplates* m_templates;
    SShaderGen* m_shaderGenParams;
    CMetalShader* m_pGenShader;
    int m_LMFlags;
};

// Metal shader manager class
class CMetalShaderManager
{
    friend class CMetalShader;
    
public:
    struct GeneratedUniformBinding
    {
        std::string name;
        std::string type;
        std::string semantic;
        int arraySize = 0;
    };

    struct GeneratedTextureBinding
    {
        std::string name;
        std::string type;
        std::string semantic;
        int slot;
    };

    struct ShaderInfo
    {
        id<MTLFunction> vertexFunction;
        id<MTLFunction> fragmentFunction;
        id<MTLRenderPipelineState> pipelineState;
        std::string name;
        EShClass shaderClass;
        bool isLoaded;
        CMetalShader* shaderWrapper;
        uint64 nMaskGen;
        std::vector<GeneratedUniformBinding> uniformBindings;
        std::vector<GeneratedTextureBinding> textureBindings;
        std::vector<std::string> directives;
        std::vector<std::string> maskReferences;
        bool blendEnabled;
        uint32 blendMode;
        MTLBlendFactor sourceBlendFactor;
        MTLBlendFactor destinationBlendFactor;
        MTLBlendOperation blendOperation;
        MTLBlendFactor sourceAlphaBlendFactor;
        MTLBlendFactor destinationAlphaBlendFactor;
        MTLBlendOperation alphaBlendOperation;
        bool depthTestEnabled;
        bool depthWriteEnabled;
        MTLCompareFunction depthCompareFunction;
        MTLCullMode cullMode;
        uint8_t colorWriteMask = 0xF;
        bool needsTangents = false;
        MTLVertexDescriptor* vertexDescriptor = nil;
        struct UniformRuntimeBinding
        {
            int paramIndex = -1;
            GeneratedUniformBinding binding;
            std::vector<int> arrayParamIndices;
            UniformScalarType scalarType = UniformScalarType::Float;
            int rows = 1;
            int columns = 1;
            int arrayCount = 1;
            size_t offset = 0;
            size_t size = 0;
            size_t elementStride = 0;
            UniformValueSource source = UniformValueSource::ShaderParam;
        };
        struct TextureRuntimeBinding
        {
            int slot;
            GeneratedTextureBinding binding;
        };
        std::vector<UniformRuntimeBinding> uniformRuntimeBindings;
        std::vector<TextureRuntimeBinding> textureRuntimeBindings;
        size_t publicParamSignature = 0;
        bool runtimeBindingsPrepared = false;
        size_t uniformDataSize = 0;
        std::vector<uint8_t> uniformStaging;
        SShader* rendItemStub = nullptr;
    };

    CMetalShaderManager(CMetalBaseRenderer* renderer, CMetalTextureManager* textureManager);
    virtual ~CMetalShaderManager();

    // Shader System Interface (EF_ methods)
    bool EF_PrecacheResource(IShader* pSH, float fDist, float fTimeToReady, int Flags);
    bool EF_PrecacheResource(ITexPic* pTP, float fDist, float fTimeToReady, int Flags);
    bool EF_PrecacheResource(CLeafBuffer* pPB, float fDist, float fTimeToReady, int Flags);
    bool EF_PrecacheResource(CDLight* pLS, float fDist, float fTimeToReady, int Flags);
    void EF_EnableHeatVision(bool bEnable);
    bool EF_GetHeatVision();
    void EF_PolygonOffset(bool bEnable, float fFactor, float fUnits);
    void EF_AddPolyToScene3D(int Ef, int numPts, SColorVert* verts, CCObject* obj = NULL, int nFogID = 0);
    CCObject* EF_AddSpriteToScene(int Ef, int numPts, SColorVert* verts, CCObject* obj, 
                                 byte* inds = NULL, int ninds = 0, int nFogID = 0);
    void EF_AddPolyToScene2D(int Ef, int numPts, SColorVert2D* verts);
    void EF_AddPolyToScene2D(SShaderItem si, int nTempl, int numPts, SColorVert2D* verts);
    
    // Shader Management
    IShader* EF_LoadShader(const char* name, EShClass Class, int flags = 0, uint64 nMaskGen = 0);
    SShaderItem EF_LoadShaderItem(const char* name, EShClass Class, bool bShare, 
                                 const char* templName, int flags = 0, 
                                 SInputShaderResources* Res = NULL, uint64 nMaskGen = 0);
    bool EF_ReloadFile(const char* szFileName);
    void EF_ReloadShaderFiles(int nCategory);
    void EF_ReloadTextures();
    IShader* EF_CopyShader(IShader* ef);
    char** EF_GetShadersForFile(const char* File, int num);
    SLightMaterial* EF_GetLightMaterial(char* Str);
    bool EF_RegisterTemplate(int nTemplId, char* Name, bool bReplace);
    void EF_AddSplash(Vec3 Pos, eSplashType eST, float fForce, int Id = -1);
    bool EF_HideTemplate(const char* name);
    bool EF_UnhideTemplate(const char* name);
    bool EF_UnhideAllTemplates();
    bool EF_SetLightHole(Vec3 vPos, Vec3 vNormal, int idTex, float fScale = 1.0f, bool bAdditive = true);
    
    // Render Elements
    CRendElement* EF_CreateRE(EDataType edt);
    void EF_StartEf();
    CCObject* EF_GetObject(bool bTemp = false, int num = -1);
    void EF_AddEf(int NumFog, CRendElement* re, IShader* ef, 
                 SRenderShaderResources* sr, CCObject* obj, int nTempl, 
                 IShader* efState = 0, int nSort = 0);
    void EF_EndEf3D(int nFlags);
    
    // Dynamic Lights
    bool EF_IsFakeDLight(CDLight* Source);
    void EF_ADDDlight(CDLight* Source);
    void EF_ClearLightsList();
    bool EF_UpdateDLight(CDLight* pDL);
    
    // 2D Effects
    void EF_EndEf2D(bool bSort);
    bool EF_DrawEfForName(char* name, float x, float y, float width, float height, 
                         CFColor& col, int nTempl = -1);
    bool EF_DrawEfForNum(int num, float x, float y, float width, float height, 
                        CFColor& col, int nTempl = -1);
    bool EF_DrawEf(IShader* ef, float x, float y, float width, float height, 
                  CFColor& col, int nTempl = -1);
    bool EF_DrawEf(SShaderItem si, float x, float y, float width, float height, 
                  CFColor& col, int nTempl = -1);
    bool EF_DrawPartialEfForName(char* name, SVrect* vr, SVrect* pr, CFColor& col);
    bool EF_DrawPartialEfForNum(int num, SVrect* vr, SVrect* pr, CFColor& col);
    bool EF_DrawPartialEf(IShader* ef, SVrect* vr, SVrect* pr, CFColor& col, 
                         float iwdt = 0, float ihgt = 0);
    
    // Shader Utilities
    void* EF_Query(int Query, int Param = 0);
    void EF_ConstructEf(IShader* Ef);
    void EF_SetWorldColor(float r, float g, float b, float a = 1.0f);
    int EF_RegisterFogVolume(float fMaxFogDist, float fFogLayerZ, CFColor color, 
                            int nIndex = -1, bool bCaustics = false);
    
    // LeafBuffer Management
    CLeafBuffer* CreateLeafBuffer(bool bDynamic, const char* szSource = "Unknown", 
                                 class CIndexedMesh* pIndexedMesh = 0);
    CLeafBuffer* CreateLeafBufferInitialized(void* pVertBuffer, int nVertCount, 
                                            int nVertFormat, ushort* pIndices, 
                                            int nIndices, int nPrimetiveType, 
                                            const char* szSource, 
                                            EBufferType eBufType = eBT_Dynamic, 
                                            int nMatInfoCount = 1, 
                                            int nClientTextureBindID = 0, 
                                            bool (*PrepareBufferCallback)(CLeafBuffer*, bool) = NULL, 
                                            void* CustomData = NULL, 
                                            bool bOnlyVideoBuffer = false, 
                                            bool bPrecache = true);
    void DeleteLeafBuffer(CLeafBuffer* pLBuffer);
    
    // Utility methods
    void ClearAllShaders();
    int GetShaderCount() const;
    void SetGlobalShaderTemplateId(int nTemplateId);
    int GetGlobalShaderTemplateId() const;
    void ShareCacheWith(CMetalShaderManager* other);
    void ApplyShaderPipelineState(IShader* shader);
    ShaderInfo* FindShaderInfo(IShader* shader);
    void ApplyPipelineStateInternal(ShaderInfo& info);

    // Pipeline state access methods
    id<MTLRenderPipelineState> GetPipelineStateForShader(const char* shaderName);
    id<MTLRenderPipelineState> GetPipelineStateForFormat(int vertexFormat);

    id<MTLLibrary> GetDefaultLibrary() const { return m_defaultLibrary; }

    void RunValidateShaderPairs();
    int GetLastGeneratedShaderPsoFailureCount() const { return m_lastGeneratedShaderPsoFailureCount; }
    int GetLastValidateShaderPairsFailureCount() const { return m_lastValidateShaderPairsFailureCount; }

    MetalPerShaderUniforms::Binder& GetPerShaderUniformBinder() { return m_perShaderUniforms; }
    const MetalPerShaderUniforms::Binder& GetPerShaderUniformBinder() const { return m_perShaderUniforms; }

    MetalMaterialTextureBinder::Binder& GetMaterialTextureBinder() { return m_materialTextureBinder; }
    const MetalMaterialTextureBinder::Binder& GetMaterialTextureBinder() const { return m_materialTextureBinder; }

protected:
    // Metal-specific shader management
    bool InitializeDefaultShaderLibrary();
    void CreateDefaultShaders(id<MTLLibrary> library);
    void LoadGeneratedShaders(id<MTLLibrary> vertexLibrary);
    int TryRegisterOneManifestPipeline(
        NSDictionary* fragEntry,
        NSDictionary* aliasSourceOverride,
        const std::string& registrationNormalizedKey,
        id<MTLLibrary> generatedLibrary,
        id<MTLLibrary> vertexLibrary,
        const std::unordered_map<std::string, const GeneratedVertexEntry*>& vertexByFuncName,
        int* psoFailCount,
        bool fragmentPairingStats,
        size_t* matchedFragmentVertexCount,
        size_t* missingFragmentVertexCount);
    void ValidateShaderPairs(id<MTLDevice> device, id<MTLLibrary> generatedLib);
    id<MTLFunction> LoadMetalShader(const char* name, const char* source);
    id<MTLRenderPipelineState> CreatePipelineState(id<MTLFunction> vertexFunction, 
                                                   id<MTLFunction> fragmentFunction,
                                                   MTLVertexDescriptor* vertexDescriptor);
    id<MTLRenderPipelineState> CreatePipelineStateWithFunctions(id<MTLFunction> vertexFunction,
                                                                id<MTLFunction> fragmentFunction,
                                                                MTLVertexDescriptor* vertexDescriptor,
                                                                ShaderInfo* shaderInfo);
    void SetShaderUniforms(id<MTLRenderCommandEncoder> encoder, const SShaderParam& params);
    void PrepareRuntimeBindings(CMetalShader* shader, ShaderInfo& info);
    void ResetRuntimeBindingState(ShaderInfo& info);

    // Shader caching and management
    std::unordered_map<int, ShaderInfo> m_shaders;
    std::unordered_map<std::string, int> m_shaderNameMap;
    std::unordered_map<std::string, GeneratedVertexEntry> m_generatedVertexEntries;
    int m_nextShaderId;
    
    // Current shader state
    int m_currentShaderId;
    id<MTLRenderPipelineState> m_currentPipelineState;
    
    // Global shader template
    int m_globalShaderTemplateId;
    
    // Heat vision effect
    bool m_heatVisionEnabled;
    bool m_lastPipelineHadTangentMismatch;
    
    // Fog volumes
    std::vector<void*> m_fogVolumes; // FogVolume* - forward declaration to avoid include issues
    
    // Reference to base renderer and texture manager
    CMetalBaseRenderer* m_renderer;
    CMetalTextureManager* m_textureManager;
    id<MTLLibrary> m_generatedLibrary;
    id<MTLLibrary> m_defaultLibrary;
    
    // Internal methods
    int AllocateShaderId();
    void ReleaseShaderId(int id);
    bool LoadShaderFromFile(const char* filename, std::string& source);
    bool CompileShader(const std::string& source, id<MTLFunction>& function);
    void SetShaderParameters(id<MTLRenderCommandEncoder> encoder, IShader* shader);
    void BindShaderTextures(id<MTLRenderCommandEncoder> encoder, IShader* shader);

    void RegisterShaderAlias(const char* alias, const char* target);

    void InstallRendItemTableStub(int shaderId, ShaderInfo& info);
    void ReleaseRendItemTableStub(ShaderInfo& info);

    int GetStartupMissingShaderCount() const { return m_nStartupMissingShaders; }

    int m_nStartupMissingShaders;
    int m_lastGeneratedShaderPsoFailureCount;
    int m_lastValidateShaderPairsFailureCount;

    MetalPerShaderUniforms::Binder m_perShaderUniforms;
    MetalMaterialTextureBinder::Binder m_materialTextureBinder;
};

#endif // __APPLE__ && __MACH__

#if defined(__APPLE__) && defined(__MACH__)
inline uint64 BuildRenderStateHash(const CMetalShaderManager::ShaderInfo& info)
{
    uint64 hash = 0;
    hash |= info.blendEnabled ? 1ULL : 0ULL;
    hash |= (static_cast<uint64>(static_cast<uint32>(info.sourceBlendFactor)) & 0x3FULL) << 1;
    hash |= (static_cast<uint64>(static_cast<uint32>(info.destinationBlendFactor)) & 0x3FULL) << 7;
    hash |= (static_cast<uint64>(static_cast<uint32>(info.sourceAlphaBlendFactor)) & 0x3FULL) << 13;
    hash |= (static_cast<uint64>(static_cast<uint32>(info.destinationAlphaBlendFactor)) & 0x3FULL) << 19;
    hash |= (static_cast<uint64>(static_cast<uint32>(info.blendOperation)) & 0x7ULL) << 25;
    hash |= (static_cast<uint64>(static_cast<uint32>(info.alphaBlendOperation)) & 0x7ULL) << 28;
    hash |= (static_cast<uint64>(info.colorWriteMask & 0xF)) << 31;
    return hash;
}
#endif

#endif // METAL_SHADER_MANAGER_H