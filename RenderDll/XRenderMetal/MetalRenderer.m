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
//  11/05/2025 - Updated utility renderer methods (WriteXY, Draw2dText, etc.) to use
//               assert() instead of if-checks for m_utilityRenderer. This ensures
//               fail-fast behavior consistent with texture/shader manager methods,
//               catching initialization order bugs early rather than silently failing.
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
#include <string>
#include <cstdint>
#include <memory>

// Include CryEngine interfaces
#include "IShader.h"
#include "Cry_Math.h"
#include "Cry_Camera.h"  // For CCamera member

// Include specialized manager classes  
#include "MetalBaseRenderer.m"
#include "MetalTextureManager.m"
#include "MetalShaderManager.m"
#include "MetalUtilityRenderer.m"

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
 *    - All manager-dependent methods (texture, shader, utility) assert if called before Init()
 *    - This fail-fast behavior ensures initialization bugs are caught early
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
    CMetalTextureManager* GetTextureManager() const;
    
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
    void SetTexClampMode(bool clamp) override;
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
    int LoadAnimatedTexture(const char *format, const int nCount) override;
    void RemoveAnimatedTexture(AnimTexInfo *pInfo) override;
    AnimTexInfo* GetAnimTexInfoFromId(int nId) override;
    
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
    bool EF_DrawEf(IShader* ef, float x, float y, float width, float height, CFColor& col, int nTempl=-1) override;
    bool EF_DrawEf(SShaderItem si, float x, float y, float width, float height, CFColor& col, int nTempl=-1) override;
    bool EF_DrawPartialEfForName(char* name, SVrect *vr, SVrect *pr, CFColor& col) override;
    bool EF_DrawPartialEfForNum(int num, SVrect *vr, SVrect *pr, CFColor& col) override;
    bool EF_DrawPartialEf(IShader *ef, SVrect *vr, SVrect *pr, CFColor& col, float iwdt=0, float ihgt=0) override;
    
    // Shader query and construction
    void* EF_Query(int Query, int Param=0) override;
    void EF_ConstructEf(IShader *Ef) override;
    void EF_SetWorldColor(float r, float g, float b, float a=1.0f) override;
    int EF_RegisterFogVolume(float fMaxFogDist, float fFogLayerZ, CFColor color, int nIndex=-1, bool bCaustics=false) override;
    
    // Leaf buffer management
    CLeafBuffer* CreateLeafBuffer(bool bDynamic, const char *szSource, CIndexedMesh * pIndexedMesh=0) override;
    CLeafBuffer* CreateLeafBufferInitialized(void * pVertBuffer, int nVertCount, int nVertFormat, 
                                             ushort* pIndices, int nIndices,
                                             int nPrimetiveType, const char *szSource, EBufferType eBufType = eBT_Dynamic,
                                             int nMatInfoCount=1, int nClientTextureBindID=0,    
                                             bool (*PrepareBufferCallback)(CLeafBuffer *, bool)=NULL,
                                             void *CustomData = NULL,
                                             bool bOnlyVideoBuffer=false, bool bPrecache=true) override;
    void DeleteLeafBuffer(CLeafBuffer * pLBuffer) override;
    
    /**
     * @brief 2D drawing and utility rendering methods
     * 
     * These methods delegate to CMetalUtilityRenderer for text rendering, 2D image drawing,
     * and utility operations. All methods assert that m_utilityRenderer is initialized
     * (i.e., Init() has been called successfully) before delegating.
     * 
     * @precondition Init() must be called successfully before any of these methods are invoked.
     *              If called before initialization, these methods will assert and terminate
     *              the program, ensuring initialization bugs are caught early.
     * 
     * @note This fail-fast behavior differs from silent failure patterns. The assert ensures
     *       consistency with texture/shader manager methods and helps catch initialization
     *       order bugs during development.
     * 
     * @see CMetalUtilityRenderer for implementation details
     * @see InitializeManagers() for initialization logic
     */
    void WriteXY(CXFont *currfont,int x,int y, float xscale,float yscale,float r,float g,float b,float a,const char *message, ...) override;
    void TextToScreen(float x, float y, const char * format, ...) override;
    void TextToScreenColor(int x, int y, float r, float g, float b, float a, const char * format, ...) override;
    void Draw2dText(float posX,float posY,const char *szText,SDrawTextInfo &info) override;
    void Draw2dImage(float xpos,float ypos,float w,float h,int texture_id,float s0=0,float t0=0,float s1=1,float t1=1,float angle=0,float r=1,float g=1,float b=1,float a=1,float z=1) override;
    void DrawImage(float xpos,float ypos,float w,float h,int texture_id,float s0,float t0,float s1,float t1,float r,float g,float b,float a) override;
    int SetPolygonMode(int mode) override;
    void TransformTextureMatrix(float x, float y, float angle, float scale) override;
    void ResetTextureMatrix() override;
    void SetMaterialColor(float r, float g, float b, float a) override;
    int CreateRenderTarget(int nWidth, int nHeight, ETEX_Format eTF) override;
    bool DestroyRenderTarget(int nHandle) override;
    bool SetRenderTarget(int nHandle) override;
    void FlushTextMessages() override;
    int GenerateAlphaGlowTexture(float k) override;
    void OnEntityDeleted(IEntityRender* pEntityRender) override;
    void SetGlobalShaderTemplateId(int nTemplateId) override;
    int GetGlobalShaderTemplateId() override;
    int EnumAAFormats(TArray<SAAFormat>& Formats, bool bReset) override;
    float EF_GetWaterZElevation(float fX, float fY) override;
    void Draw2dLine(float x1, float y1, float x2, float y2) override;
    void SetLineWidth(float fWidth) override;
    void DrawLine(const Vec3& vPos1, const Vec3& vPos2) override;
    void DrawLineColor(const Vec3& vPos1, const CFColor& vColor1, const Vec3& vPos2, const CFColor& vColor2) override;
    void Graph(byte* g, int x, int y, int wdt, int hgt, int nC, int type, char* text, CFColor& color, float fScale) override;
    void DrawBall(float x, float y, float z, float radius) override;
    void ResetToDefault() override;
    int ScreenToTexture() override;
    
    // Vertex/Index buffer management (from CRenderer/IRenderer)
    void* GetDynVBPtr(int nVerts, int &nOffs, int Pool) override;
    void DrawDynVB(int nOffs, int Pool, int nVerts) override;
    void DrawDynVB(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F *pBuf, ushort *pInds, int nVerts, int nInds, int nPrimType) override;
    CVertexBuffer* CreateBuffer(int vertexcount, int vertexformat, const char *szSource, bool bDynamic=false) override;
    void CreateBuffer(int size, int vertexformat, CVertexBuffer *buf, int Type, const char *szSource) override;
    void ReleaseBuffer(CVertexBuffer *bufptr) override;
    void DrawBuffer(CVertexBuffer *src, SVertexStream *indicies, int numindices, int offsindex, int prmode, int vert_start=0, int vert_stop=0, CMatInfo *mi=NULL) override;
    void UpdateBuffer(CVertexBuffer *dest, const void *src, int vertexcount, bool bUnLock, int offs=0, int Type=0) override;
    void CreateIndexBuffer(SVertexStream *dest, const void *src, int indexcount) override;
    void UpdateIndexBuffer(SVertexStream *dest, const void *src, int indexcount, bool bUnLock=true) override;
    void ReleaseIndexBuffer(SVertexStream *dest) override;
    void DrawTriStrip(CVertexBuffer *src, int vert_num=4) override;
    
    // Rendering state and control methods
    void CheckError(const char *comment) override;
    void Draw3dBBox(const Vec3 &mins, const Vec3 &maxs, int nPrimType) override;
    void SetState(int State) override;
    void Set2DMode(bool enable, int ortox, int ortoy) override;
    void SetCullMode(int mode=R_CULL_BACK) override;
    bool EnableFog(bool enable) override;
    void SetFog(float density, float fogstart, float fogend, const float *color, int fogmode) override;
    void EnableTexGen(bool enable) override;
    void SetTexgen(float scaleX, float scaleY, float translateX=0, float translateY=0) override;
    void SetTexgen3D(float x1, float y1, float z1, float x2, float y2, float z2) override;
    void SetLodBias(float value=R_DEFAULT_LODBIAS) override;
    void EnableVSync(bool enable) override;
    
    // Metal-specific methods (not virtual in base)
    void Draw3dPrim(const Vec3 &mins, const Vec3 &maxs, int nPrimType, const float *fRGBA);
    void SetFenceCompleted(CVertexBuffer *buffer);
    
    // Matrix operations
    void PushMatrix() override;
    void RotateMatrix(float a, float x, float y, float z) override;
    void RotateMatrix(const Vec3 & angels) override;
    void TranslateMatrix(float x, float y, float z) override;
    void ScaleMatrix(float x, float y, float z) override;
    void TranslateMatrix(const Vec3 &pos) override;
    void MultMatrix(float * mat) override;
    void LoadMatrix(const Matrix44 *src=0) override;
    void PopMatrix() override;
    void EnableTMU(bool enable) override;
    void SelectTMU(int tnum) override;
    bool ChangeDisplay(unsigned int width, unsigned int height, unsigned int cbpp) override;
    void ChangeViewport(unsigned int x, unsigned int y, unsigned int width, unsigned int height) override;
    
    // Display and utility methods
    bool SaveTga(unsigned char *sourcedata, int sourceformat, int w, int h, const char *filename, bool flip) override;
    int GetWidth() override;
    int GetHeight() override;
    void GetMemoryUsage(ICrySizer* Sizer) override;
    void ScreenShot(const char *filename=NULL) override;
    int GetColorBpp() override;
    int GetDepthBpp() override;
    int GetStencilBpp() override;
    Vec3 GetUnProject(const Vec3 &WindowCoords, const CCamera &cam) override;
    
    // Projection and transformation methods
    void ProjectToScreen(float ptx, float pty, float ptz, float *sx, float *sy, float *sz) override;
    int UnProject(float sx, float sy, float sz, float *px, float *py, float *pz, const float modelMatrix[16], const float projMatrix[16], const int viewport[4]) override;
    int UnProjectFromScreen(float sx, float sy, float sz, float *px, float *py, float *pz) override;
    void GetModelViewMatrix(float *mat) override;
    void GetModelViewMatrix(double *mat) override;
    void GetProjectionMatrix(float *mat) override;
    void GetProjectionMatrix(double *mat) override;
    void RenderToViewport(const CCamera &cam, float x, float y, float width, float height) override;
    
    // Viewport and frame management  
    void BeginFrame(void) override;
    void Update(void) override;
    void EndFrame(void) override;
    void SetScissor(int x=0, int y=0, int width=0, int height=0) override;
    void SetViewport(int x=0, int y=0, int width=0, int height=0) override;
    void GetViewport(int *x, int *y, int *width, int *height) override;
    int GetFeatures() override;
    void MakeCurrent() override;
    
    // Platform-specific methods
    void DisplaySplash(); // Display Far Cry splash screen on startup
    bool CreateContext(WIN_HWND hWnd, bool bAllowFSAA=false) override;
    bool DeleteContext(WIN_HWND hWnd) override;
    
    // Resource and lifecycle management
    /**
     * @brief Initialize the Metal renderer and create managers
     * 
     * Calls base class Init() to create Metal device, then creates
     * texture/shader/utility managers that depend on the device.
     * 
     * @return Window handle if successful, nullptr on failure
     */
    WIN_HWND Init(int x, int y, int width, int height, unsigned int cbpp, int zbpp, int sbits, bool fullscreen, WIN_HINSTANCE hinst, WIN_HWND Glhwnd=0, WIN_HDC Glhdc=0, WIN_HGLRC hGLrc=0, bool bReInit=false) override;
    void ShutDown(bool bReInit=false) override;
    void Release() override;
    void FreeResources(int nFlags) override;
    void RefreshResources(int nFlags) override;
    void ShareResources(IRenderer *renderer) override;
    bool SetCurrentContext(WIN_HWND hWnd) override;
    bool ChangeResolution(int nNewWidth, int nNewHeight, int nNewColDepth, int nNewRefreshHZ, bool bFullScreen) override;
    int EnumDisplayFormats(TArray<SDispFormat>& Formats, bool bReset) override;
    int GetMaxTextureMemory() override;
    void PreLoad(void) override;
    void PostLoad(void) override;
    
    // Pure virtual methods that MUST be implemented
    void Reset(void) override;
    char* GetStatusText(ERendStats type) override;
    void PrepareDepthMap(ShadowMapFrustum * lof, bool make_new_tid=0) override;
    void SetupShadowOnlyPass(int Num, ShadowMapFrustum * pFrustum, Vec3 * vShadowTrans, const float fShadowScale, Vec3 vObjTrans, float fObjScale, const Vec3 vObjAngles, Matrix44 * pObjMat) override;
    void DrawAllShadowsOnTheScreen() override;
    void SetClipPlane(int id, float * params) override;
    void EF_SetClipPlane(bool bEnable, float *pPlane, bool bRefract) override;
    void DrawPoints(Vec3 v[], int nump, CFColor& col, int flags) override;
    void DrawLines(Vec3 v[], int nump, CFColor& col, int flags, float fGround) override;
    void EF_Release(int nFlags) override;
    void EF_PipelineShutdown() override;
    void EF_LightMaterial(SLightMaterial *lm, int Flags) override;
    void EF_CheckOverflow(int nVerts, int nTris, CRendElement *re) override;
    void EF_Start(SShader *ef, SShader *efState, SRenderShaderResources *Res, int nFog, CRendElement *re) override;
    void EF_Start(SShader *ef, SShader *efState, SRenderShaderResources *Res, CRendElement *re) override;
    STexPic* EF_MakePhongTexture(int Exp) override;

    unsigned int MakeSprite(float object_scale, int tex_size, float angle,
                            IStatObj* pStatObj, uchar* pTmpBuffer, uint def_tid) override;
    unsigned int Make3DSprite(int nTexSize, float fAngleStep, IStatObj* pStatObj) override;
    ShadowMapFrustum* MakeShadowMapFrustum(ShadowMapFrustum* lof, ShadowMapLightSource* pLs,
                                           const Vec3& obj_pos, list2<IStatObj*>* pStatObjects,
                                           int shadow_type) override;
    void DrawObjSprites(list2<CStatObjInst*>* pList, float fMaxViewDist, CObjManager* pObjMan) override;

    CMetalShaderManager* GetShaderManager() const { return m_shaderManager.get(); }

private:
    void RegisterMetalConsoleVariables();
    void UnregisterMetalConsoleVariables();
    void DumpMetalDiagnostics() const;
    void WriteDiagnosticsJson(int drawCalls, int triangles, int shaderCount,
                              int textureCount, size_t textureBytes,
                              size_t pipelineStates, size_t depthStates,
                              size_t samplerStates) const;
    bool LoadDiagnosticsRequestFromFile(bool& requestFileFound);
    void PrepareDynVBColortexDrawState();

    int m_metalDumpStatsFlag;
    int m_metalGPUCaptureFlag;
    std::string m_diagOutputPath;

  protected:
    // Specialized manager instances
    std::unique_ptr<CMetalTextureManager> m_textureManager;
    std::unique_ptr<CMetalShaderManager> m_shaderManager;
    std::unique_ptr<CMetalUtilityRenderer> m_utilityRenderer;

    virtual id<MTLLibrary> GetShaderLibrary() override {
        return m_shaderManager ? m_shaderManager->GetDefaultLibrary() : nil;
    }
    virtual id<MTLRenderPipelineState> GetFontPSO() override {
        return m_utilityRenderer ? m_utilityRenderer->GetFontPipeline() : nil;
    }
    
    struct DebugVertex
    {
        float position[3];
        uint32_t color;
    };
    
    struct DebugCommand
    {
        MTLPrimitiveType primitiveType;
        std::vector<DebugVertex> vertices;
        bool depthTest;
        bool depthWrite;
        bool blend;
    };
    
    id<MTLRenderPipelineState> m_debugPipelineState;
    std::vector<DebugCommand> m_debugCommands;
    bool EnsureDebugPipelineState();

public:
    void QueueDebugCommand(MTLPrimitiveType primitive, const std::vector<DebugVertex>& verts,
                           bool depthTest, bool depthWrite, bool blend);
    void QueueDebugLine(const Vec3& a, const Vec3& b, const CFColor& color, int stateFlags);
    void QueueDebugPoint(const Vec3& position, const CFColor& color, int stateFlags);
    void QueueDebugBox(const Vec3& mins, const Vec3& maxs, const CFColor& color, bool solid);
    void QueueDebugSphere(const Vec3& mins, const Vec3& maxs, const CFColor& color, bool solid);

protected:
    void FlushDebugCommands();
    void ApplyDebugRenderState(bool depthTest, bool depthWrite, bool blend);
    void RestoreDefaultRenderState();
    
    // Window and rendering surface
    NSWindow* m_window;
    CAMetalLayer* m_windowMetalLayer;
    id m_windowResizeObserver;
    id m_windowBackingObserver;

    void SyncMetalLayerDrawableToContentView();
    void RegisterWindowGeometryObservers();
    void UnregisterWindowGeometryObservers();
    
    // 2D mode state
    bool m_2DMode;
    int m_2DOriginX;
    int m_2DOriginY;
    std::vector<Matrix44> m_2DProjectionStack;
    std::vector<Matrix44> m_2DViewStack;
    
    // NOTE: Camera stored in CMetalBaseRenderer::m_camera (no duplication)
    
    // Initialization methods
    bool InitializeManagers();
    void ShutdownManagers();
    bool CreateGameWindow(int width, int height, bool fullscreen);
    void DestroyGameWindow();
};

// Metal utility functions
MTLPixelFormat ConvertToMetalFormat(ETEX_Format format);
MTLPrimitiveType ConvertToMetalPrimitive(int type);
MTLCompareFunction ConvertToMetalDepthFunc(int func);

#endif // __APPLE__ && __MACH__

#endif // METAL_RENDERER_H
