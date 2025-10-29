////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalRenderer.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Main Metal renderer class that combines specialized managers
//               Apple's Metal graphics API provides low-level GPU access
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_RENDERER_H
#define METAL_RENDERER_H

#if defined(__APPLE__) && defined(__MACH__)

#include <Metal/Metal.h>
#include <MetalKit/MetalKit.h>
#include <QuartzCore/CAMetalLayer.h>
#include <Cocoa/Cocoa.h>
#include <vector>
#include <memory>

// Include CryEngine interfaces
#include "IShader.h"
#include "Cry_Math.h"
#include "Cry_Camera.h"  // For CCamera member

// Include specialized manager classes  
#include "MetalBaseRenderer.h"
#include "MetalTextureManager.h"
#include "MetalShaderManager.h"
#include "MetalUtilityRenderer.h"

// Forward declarations
struct SSystemInitParams;
struct SCryRenderInterface;
class CCamera;
class ISystem;
class CVertexBuffer;
class SShader;
class SMaterial;
class STexPic;

////////////////////////////////////////////////////////////////////////////
/**
 * @class CMetalRenderer
 * @brief Main Metal renderer implementation using manager pattern
 * 
 * CMetalRenderer is the primary renderer for the Mac Silicon port of FarCry.
 * It implements the IRenderer interface and uses a manager-based architecture
 * for clean separation of concerns:
 * 
 * - CMetalTextureManager: Handles all texture operations (load, upload, compression)
 * - CMetalShaderManager: Manages shaders and render elements
 * - CMetalUtilityRenderer: Provides debug rendering and utilities
 * 
 * @architecture
 * This class delegates most functionality to specialized managers, acting as
 * a facade that routes IRenderer calls to the appropriate manager. Camera state
 * is managed by the base class (CMetalBaseRenderer) to avoid duplication.
 * 
 * @lifecycle
 * 1. Construction: Creates renderer instance, initializes manager pointers to null
 * 2. Init(): Creates Metal device, command queue, and initializes all managers
 * 3. Rendering: Delegates texture/shader/drawing calls to managers
 * 4. Shutdown: Cleans up managers and Metal resources
 * 
 * @threading
 * Not thread-safe. All rendering operations must be called from the main thread.
 * 
 * @see CMetalTextureManager, CMetalShaderManager, CMetalUtilityRenderer
 * @see IRenderer (base interface from CryEngine)
 */
////////////////////////////////////////////////////////////////////////////
class CMetalRenderer : public CMetalBaseRenderer
{
public:
    /**
     * @brief Constructs a Metal renderer instance
     * 
     * Creates the renderer object with null managers. Actual initialization
     * of Metal device and managers happens in Init().
     * 
     * @note Does not throw exceptions, but managers may fail to initialize
     */
    CMetalRenderer();
    
    /**
     * @brief Destructor - cleans up all Metal resources
     * 
     * Calls ShutdownManagers() to properly release all managers and
     * associated Metal objects (textures, buffers, shaders, etc.)
     */
    virtual ~CMetalRenderer();
    
    ////////////////////////////////////////////////////////////////////////////
    // Camera Management (delegated to CMetalBaseRenderer)
    ////////////////////////////////////////////////////////////////////////////
    
    /**
     * @brief Sets the current camera for rendering
     * 
     * Delegates to CMetalBaseRenderer::SetCamera() which stores the camera
     * and updates Metal view/projection matrices for rendering.
     * 
     * @param cam Camera object containing position, orientation, FOV, etc.
     * 
     * @note Camera is stored by value in CMetalBaseRenderer::m_camera
     * @see CMetalBaseRenderer::SetCamera()
     */
    virtual void SetCamera(const CCamera& cam) override;
    
    /**
     * @brief Gets the current camera
     * 
     * Delegates to CMetalBaseRenderer::GetCamera() which returns the
     * camera stored in the base class.
     * 
     * @return Reference to the current camera object
     * 
     * @note Returns non-const reference (matches IRenderer interface)
     * @see CMetalBaseRenderer::GetCamera()
     */
    virtual const CCamera& GetCamera() override;
    
    // Texture methods
    void SetTexture(int tnum, ETexType Type) override;
    void SetWhiteTexture() override;
    unsigned int DownLoadToVideoMemory(unsigned char *data, int w, int h,
                                       ETEX_Format eTFSrc, ETEX_Format eTFDst,
                                       int nummipmap, bool repeat, int filter,
                                       int Id, char *szCacheName, int flags) override;
    void UpdateTextureInVideoMemory(uint tnum, unsigned char *newdata, int posx,
                                    int posy, int w, int h, ETEX_Format eTF) override;
    unsigned int LoadTexture(const char *filename, int *tex_type, unsigned int def_tid,
                            bool compresstodisk, bool bWarn) override;
    bool DXTCompress(byte *raw_data, int nWidth, int nHeight, ETEX_Format eTF, bool bUseHW, 
                    bool bGenMips, int nSrcBytesPerPix, MIPDXTcallback callback) override;
    bool DXTDecompress(byte *srcData, byte *dstData, int nWidth, int nHeight, 
                      ETEX_Format eSrcTF, bool bUseHW, int nDstBytesPerPix) override;
    void RemoveTexture(unsigned int TextureId) override;
    void RemoveTexture(ITexPic *pTexPic) override;
    bool SetGammaDelta(const float fGamma) override;
    
    // Font system methods
    bool FontUploadTexture(class CFBitmap *bitmap, ETEX_Format eTF) override;
    int FontCreateTexture(int Width, int Height, byte *pData, ETEX_Format eTF) override;
    bool FontUpdateTexture(int nTexId, int X, int Y, int USize, int VSize, byte *pData) override;
    void FontReleaseTexture(class CFBitmap *pBmp) override;
    void FontSetTexture(class CFBitmap *bitmap, int nFilterMode) override;
    void FontSetTexture(int nTexId, int nFilterMode) override;
    void FontSetRenderingState(unsigned long nVirtualScreenWidth, unsigned long nVirtualScreenHeight) override;
    void FontSetBlending(int src, int dst) override;
    void FontRestoreRenderingState() override;
    
    // Shader/Resource precaching
    bool EF_PrecacheResource(IShader *pSH, float fDist, float fTimeToReady, int Flags) override;
    bool EF_PrecacheResource(ITexPic *pTP, float fDist, float fTimeToReady, int Flags) override;
    bool EF_PrecacheResource(CLeafBuffer *pPB, float fDist, float fTimeToReady, int Flags) override;
    bool EF_PrecacheResource(CDLight *pLS, float fDist, float fTimeToReady, int Flags) override;
    
    // Shader system methods - corrected signatures to match base class
    void EF_PolygonOffset(bool bEnable, float fFactor, float fUnits) override;
    void EF_AddPolyToScene3D(int Ef, int numPts, SColorVert *verts, CCObject *obj=NULL, int nFogID=0) override;
    CCObject *EF_AddSpriteToScene(int Ef, int numPts, SColorVert *verts, CCObject *obj, byte *inds=NULL, int ninds=0, int nFogID=0) override;
    void EF_AddPolyToScene2D(int Ef, int numPts, SColorVert2D *verts) override;
    void EF_AddPolyToScene2D(SShaderItem si, int nTempl, int numPts, SColorVert2D *verts) override;
    IShader *EF_LoadShader(const char *name, EShClass Class, int flags=0, uint64 nMaskGen=0) override;
    SShaderItem EF_LoadShaderItem(const char *name, EShClass Class, bool bShare, const char *templName, int flags=0, SInputShaderResources *Res=NULL, uint64 nMaskGen=0) override;
    bool EF_ReloadFile(const char *szFileName) override;
    void EF_ReloadShaderFiles(int nCategory) override;
    void EF_ReloadTextures() override;
    IShader *EF_CopyShader(IShader *ef) override;
    ITexPic *EF_GetTextureByID(int Id) override;
    ITexPic *EF_LoadTexture(const char *nameTex, uint flags, uint flags2, byte eTT, float fAmount1, float fAmount2, int Id, int BindId) override;
    int EF_LoadLightmap(const char *name) override;
    bool EF_ScanEnvironmentCM(const char *name, int size, Vec3 &Pos) override;
    int EF_ReadAllImgFiles(IShader *ef, SShaderTexUnit *tl, STexAnim *ta, char *name) override;
    void EF_EnableHeatVision(bool bEnable) override;
    bool EF_GetHeatVision() override;  // Returns bool (not int)
    
    // Additional shader/template methods
    char** EF_GetShadersForFile(const char* File, int num) override;
    SLightMaterial* EF_GetLightMaterial(char* Str) override;
    bool EF_RegisterTemplate(int nTemplId, char* Name, bool bReplace) override;
    bool EF_HideTemplate(const char* name) override;
    bool EF_UnhideTemplate(const char* name) override;
    bool EF_UnhideAllTemplates() override;
    void EF_AddSplash(Vec3 Pos, eSplashType eST, float fForce, int Id=-1) override;
    bool EF_SetLightHole(Vec3 vPos, Vec3 vNormal, int idTex, float fScale=1.0f, bool bAdditive=true) override;
    
    // Shader effect management
    void EF_StartEf() override;
    CCObject* EF_GetObject(bool bTemp=false, int num=-1) override;
    void EF_AddEf(int NumFog, CRendElement *re, IShader *ef, SRenderShaderResources *sr, CCObject *obj, int nTempl, IShader *efState=0, int nSort=0) override;
    void EF_EndEf3D(int nFlags) override;
    void EF_EndEf2D(bool bSort) override;
    
    // Dynamic light management
    bool EF_IsFakeDLight(CDLight *Source) override;
    void EF_ADDDlight(CDLight *Source) override;
    void EF_ClearLightsList() override;
    bool EF_UpdateDLight(CDLight *pDL) override;
    
    // Effect drawing methods
    bool EF_DrawEfForName(char* name, float x, float y, float width, float height, CFColor& col, int nTempl) override;
    bool EF_DrawEfForNum(int num, float x, float y, float width, float height, CFColor& col, int nTempl) override;
    bool EF_DrawEf(IShader* ef, float x, float y, float width, float height, CFColor& col, int nTempl) override;
    bool EF_DrawPartialEfForName(IShader* ef, char* name, float x, float y, float width, float height, CFColor& col, int nTempl) override;
    bool EF_DrawPartialEfForNum(IShader* ef, int num, float x, float y, float width, float height, CFColor& col, int nTempl) override;
    
    // Leaf buffer management
    CLeafBuffer* CreateLeafBuffer(bool bDynamic, const char *szSource, CIndexedMesh * pIndexedMesh=0) override;
    CLeafBuffer* CreateLeafBufferInitialized(void* pVertBuffer, int nVertCount, VERTEX_FORMAT_ENUM eVF,
                                             ushort* pIndices, int nIndices, int nPrimetiveType,
                                             const char *szSource, EBufferType eBufType=eBT_Static, int nMatId=0,
                                             const list2<struct_VERTEXSTREAM> *pSrcVerts=NULL, bool bOnlyVideoBuffer=false,
                                             bool bPrecache=true, bool bSyncronBuffer=false) override;
    void DeleteLeafBuffer(CLeafBuffer * pLBuffer) override;
    
    // 2D drawing methods
    void WriteXY(CXFont *currfont,int x,int y, float xscale,float yscale,float r,float g,float b,float a,const char *message, ...) override;
    void Draw2dText(float posX,float posY,const char *szText,SDrawTextInfo &info) override;
    void Draw2dImage(float xpos,float ypos,float w,float h,int texture_id,float s0=0,float t0=0,float s1=1,float t1=1,float angle=0,float r=1,float g=1,float b=1,float a=1,float z=1) override;
    void DrawImage(float xpos,float ypos,float w,float h,int texture_id,float s0,float t0,float s1,float t1,float r,float g,float b,float a) override;
    int SetPolygonMode(int mode) override;

  protected:
    // Specialized manager instances
    std::unique_ptr<CMetalTextureManager> m_textureManager;
    std::unique_ptr<CMetalShaderManager> m_shaderManager;
    std::unique_ptr<CMetalUtilityRenderer> m_utilityRenderer;
    
    // NOTE: Camera stored in CMetalBaseRenderer::m_camera (no duplication)
    
    // Initialization methods
    bool InitializeManagers();
    void ShutdownManagers();
};

// Metal utility functions
MTLPixelFormat ConvertToMetalFormat(ETEX_Format format);
MTLPrimitiveType ConvertToMetalPrimitive(int type);
MTLCompareFunction ConvertToMetalDepthFunc(int func);

#endif // __APPLE__ && __MACH__

#endif // METAL_RENDERER_H
