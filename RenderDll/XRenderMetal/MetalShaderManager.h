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

// Include CryEngine interfaces
#include "IRenderer.h"
#include "IShader.h"
#include "Cry_Math.h"

// Forward declarations
class CMetalBaseRenderer;
class CMetalTextureManager;

// Metal shader manager class
class CMetalShaderManager
{
public:
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
    int GetGlobalShaderTemplateId();

    // Pipeline state access methods
    id<MTLRenderPipelineState> GetPipelineStateForShader(const char* shaderName);
    id<MTLRenderPipelineState> GetPipelineStateForFormat(int vertexFormat);

protected:
    // Metal-specific shader management
    bool InitializeDefaultShaderLibrary();
    void CreateDefaultShaders(id<MTLLibrary> library);
    id<MTLFunction> LoadMetalShader(const char* name, const char* source);
    id<MTLRenderPipelineState> CreatePipelineState(id<MTLFunction> vertexFunction, 
                                                   id<MTLFunction> fragmentFunction,
                                                   MTLVertexDescriptor* vertexDescriptor);
    id<MTLRenderPipelineState> CreatePipelineStateWithFunctions(id<MTLFunction> vertexFunction,
                                                                id<MTLFunction> fragmentFunction,
                                                                MTLVertexDescriptor* vertexDescriptor);
    void SetShaderUniforms(id<MTLRenderCommandEncoder> encoder, const SShaderParam& params);
    
    // Shader caching and management
    struct ShaderInfo
    {
        id<MTLFunction> vertexFunction;
        id<MTLFunction> fragmentFunction;
        id<MTLRenderPipelineState> pipelineState;
        std::string name;
        EShClass shaderClass;
        bool isLoaded;
    };
    
    std::unordered_map<int, ShaderInfo> m_shaders;
    std::unordered_map<std::string, int> m_shaderNameMap;
    int m_nextShaderId;
    
    // Current shader state
    int m_currentShaderId;
    id<MTLRenderPipelineState> m_currentPipelineState;
    
    // Global shader template
    int m_globalShaderTemplateId;
    
    // Heat vision effect
    bool m_heatVisionEnabled;
    
    // Fog volumes
    std::vector<void*> m_fogVolumes; // FogVolume* - forward declaration to avoid include issues
    
    // Reference to base renderer and texture manager
    CMetalBaseRenderer* m_renderer;
    CMetalTextureManager* m_textureManager;
    
    // Internal methods
    int AllocateShaderId();
    void ReleaseShaderId(int id);
    bool LoadShaderFromFile(const char* filename, std::string& source);
    bool CompileShader(const std::string& source, id<MTLFunction>& function);
    void SetShaderParameters(id<MTLRenderCommandEncoder> encoder, IShader* shader);
    void BindShaderTextures(id<MTLRenderCommandEncoder> encoder, IShader* shader);
};

#endif // __APPLE__ && __MACH__

#endif // METAL_SHADER_MANAGER_H