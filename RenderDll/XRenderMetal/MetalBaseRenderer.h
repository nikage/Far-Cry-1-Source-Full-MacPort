////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalBaseRenderer.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Base Metal renderer class with core functionality
//               Implements essential IRenderer methods for Metal API
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_BASE_RENDERER_H
#define METAL_BASE_RENDERER_H

#if defined(__APPLE__) && defined(__MACH__)

// Include all CryEngine infrastructure in proper order
#include "MetalRenderPCH.h"
#include "MetalStateCache.h"
#include "MetalRenderElements.h"

// Forward declarations
struct SSystemInitParams;
struct SCryRenderInterface;
class CCamera;
class ISystem;
class CVertexBuffer;
class SShader;
class SMaterial;
class STexPic;
class CMetalStateCache;

// Metal base renderer class that implements core CRenderer functionality
// Inherits from CRenderer which provides m_RP and other common renderer infrastructure
class CMetalBaseRenderer : public CRenderer
{
public:
    CMetalBaseRenderer();
    virtual ~CMetalBaseRenderer();

    // Core IRenderer interface implementation
    virtual WIN_HWND Init(int x, int y, int width, int height, unsigned int cbpp, int zbpp, int sbits, 
                         bool fullscreen, WIN_HINSTANCE hinst, WIN_HWND Glhwnd = 0, 
                         WIN_HDC Glhdc = 0, WIN_HGLRC hGLrc = 0, bool bReInit = false);
    virtual bool SetCurrentContext(WIN_HWND hWnd);
    virtual bool CreateContext(WIN_HWND hWnd, bool bAllowFSAA = false);
    virtual bool DeleteContext(WIN_HWND hWnd);
    virtual int GetFeatures();
    virtual int GetMaxTextureMemory();
    virtual void ShutDown(bool bReInit = false);
    virtual int EnumDisplayFormats(TArray<SDispFormat>& Formats, bool bReset);
    virtual bool ChangeResolution(int nNewWidth, int nNewHeight, int nNewColDepth, 
                                 int nNewRefreshHZ, bool bFullScreen);
    virtual void Release();
    virtual void FreeResources(int nFlags);
    virtual void RefreshResources(int nFlags);
    virtual void PreLoad();
    virtual void PostLoad();
    virtual void BeginFrame();
    virtual void Update();
    virtual void EndFrame();
    virtual void ShareResources(IRenderer* renderer);
    
    // Viewport and Camera
    virtual void GetViewport(int* x, int* y, int* width, int* height);
    virtual void SetViewport(int x = 0, int y = 0, int width = 0, int height = 0);
    virtual void SetScissor(int x = 0, int y = 0, int width = 0, int height = 0);
    virtual void MakeCurrent();
    virtual void SetCamera(const CCamera& cam);
    virtual const CCamera& GetCamera();  // Non-const method (matches IRenderer)
    
    // Drawing Methods
    virtual void DrawTriStrip(CVertexBuffer* src, int vert_num = 4);
    virtual void* GetDynVBPtr(int nVerts, int& nOffs, int Pool);
    virtual void DrawDynVB(int nOffs, int Pool, int nVerts);
    virtual void DrawDynVB(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F* pBuf, ushort* pInds, 
                          int nVerts, int nInds, int nPrimType);
    virtual void SetFenceCompleted(CVertexBuffer* buffer);
    
    // Buffer Management
    virtual CVertexBuffer* CreateBuffer(int vertexcount, int vertexformat, const char* szSource, 
                                       bool bDynamic = false);
    virtual void ReleaseBuffer(CVertexBuffer* bufptr);
    virtual void DrawBuffer(CVertexBuffer* src, SVertexStream* indicies, int numindices, 
                           int offsindex, int prmode, int vert_start = 0, int vert_stop = 0, 
                           CMatInfo* mi = NULL);
    virtual void UpdateBuffer(CVertexBuffer* dest, const void* src, int vertexcount, 
                             bool bUnLock, int nOffs = 0, int Type = 0);
    virtual void CreateIndexBuffer(SVertexStream* dest, const void* src, int indexcount);
    virtual void UpdateIndexBuffer(SVertexStream* dest, const void* src, int indexcount, 
                                  bool bUnLock = true);
    virtual void ReleaseIndexBuffer(SVertexStream* dest);
    
    // Debug and Utility Drawing
    virtual void CheckError(const char* comment);
    virtual void Draw3dBBox(const Vec3& mins, const Vec3& maxs, int nPrimType = DPRIM_WHIRE_BOX);
    virtual void Draw3dPrim(const Vec3& mins, const Vec3& maxs, int nPrimType = DPRIM_WHIRE_BOX, 
                           const float* fRGBA = NULL);
    
    // State Management
    virtual void SetState(int State);
    virtual void SetCullMode(int mode = R_CULL_BACK);
    virtual bool EnableFog(bool enable);
    virtual void SetFog(float density, float fogstart, float fogend, const float* color, int fogmode);
    virtual void EnableTexGen(bool enable);
    virtual void SetTexgen(float scaleX, float scaleY, float translateX = 0, float translateY = 0);
    virtual void SetTexgen3D(float x1, float y1, float z1, float x2, float y2, float z2);
    virtual void SetLodBias(float value = R_DEFAULT_LODBIAS);
    virtual void EnableVSync(bool enable);
    virtual void PushMatrix();
    virtual void RotateMatrix(float a, float x, float y, float z);
    virtual void RotateMatrix(const Vec3& angels);
    virtual void TranslateMatrix(float x, float y, float z);
    virtual void ScaleMatrix(float x, float y, float z);
    virtual void TranslateMatrix(const Vec3& pos);
    virtual void MultMatrix(float* mat);
    virtual void LoadMatrix(const Matrix44* src = 0);
    virtual void PopMatrix();
    virtual void EnableTMU(bool enable);
    virtual void SelectTMU(int tnum);
    
    // Display and Resolution
    virtual bool ChangeDisplay(unsigned int width, unsigned int height, unsigned int cbpp);
    virtual void ChangeViewport(unsigned int x, unsigned int y, unsigned int width, unsigned int height);
    virtual bool SaveTga(unsigned char* sourcedata, int sourceformat, int w, int h, 
                        const char* filename, bool flip);
    
    // Screen Information
    virtual int GetWidth();
    virtual int GetHeight();
    virtual void GetMemoryUsage(ICrySizer* Sizer);
    virtual void ScreenShot(const char* filename = NULL);
    virtual int GetColorBpp();
    virtual int GetDepthBpp();
    virtual int GetStencilBpp();
    
    // Projection and Unprojection
    virtual void ProjectToScreen(float ptx, float pty, float ptz, float* sx, float* sy, float* sz);
    virtual int UnProject(float sx, float sy, float sz, float* px, float* py, float* pz,
                         const float modelMatrix[16], const float projMatrix[16], 
                         const int viewport[4]);
    virtual int UnProjectFromScreen(float sx, float sy, float sz, float* px, float* py, float* pz);
    virtual void GetModelViewMatrix(float* mat);
    virtual void GetModelViewMatrix(double* mat);
    virtual void GetProjectionMatrix(double* mat);
    virtual void GetProjectionMatrix(float* mat);
    virtual Vec3 GetUnProject(const Vec3& WindowCoords, const CCamera& cam);
    virtual void RenderToViewport(const CCamera& cam, float x, float y, float width, float height);
    
    // Basic utility methods
    virtual char GetType() { return R_METAL_RENDERER; }
    virtual char* GetVertexProfile(bool bSupportedProfile) { return nullptr; }
    virtual char* GetPixelProfile(bool bSupportedProfile) { return nullptr; }
    virtual void SetType(char type) {}
    virtual float ScaleCoordX(float value) { return value; }
    virtual float ScaleCoordY(float value) { return value; }
    virtual void SetColorOp(byte eCo, byte eAo, byte eCa, byte eAa) {}
    virtual void EnableSwapBuffers(bool bEnable) {}
    virtual WIN_HWND GetHWND() { return nullptr; }
    virtual void OnEntityDeleted(IEntityRender* pEntityRender) {}
    virtual void SetGlobalShaderTemplateId(int nTemplateId) {}
    virtual int GetGlobalShaderTemplateId() { return 0; }
    virtual int EnumAAFormats(TArray<SAAFormat>& Formats, bool bReset) { return 0; }
    virtual int CreateRenderTarget(int nWidth, int nHeight, ETEX_Format eTF) { return 0; }
    virtual bool DestroyRenderTarget(int nHandle) { return false; }
    virtual bool SetRenderTarget(int nHandle) { return false; }
    virtual float EF_GetWaterZElevation(float fX, float fY) { return 0.0f; }
    
    // Statistics
    virtual int GetPolyCount() { return 0; }
    virtual void GetPolyCount(int& nPolygons, int& nShadowVolPolys) { nPolygons = 0; nShadowVolPolys = 0; }
    virtual void SetClearColor(const Vec3& vColor) {}
    virtual int GetFrameID(bool bIncludeRecursiveCalls = true) { return 0; }
    virtual void MakeMatrix(const Vec3& pos, const Vec3& angles, const Vec3& scale, Matrix44* mat) {}
    
    // Stub implementations for complex methods (to be implemented by specialized classes)
    virtual void SetTexture(int tnum, ETexType Type = eTT_Base) {}
    virtual void SetWhiteTexture() {}
    virtual unsigned int DownLoadToVideoMemory(unsigned char* data, int w, int h, 
                                             ETEX_Format eTFSrc, ETEX_Format eTFDst, 
                                             int nummipmap, bool repeat = true, 
                                             int filter = FILTER_BILINEAR, int Id = 0, 
                                             char* szCacheName = NULL, int flags = 0) { return 0; }
    virtual void UpdateTextureInVideoMemory(uint tnum, unsigned char* newdata, int posx, int posy, 
                                           int w, int h, ETEX_Format eTF = eTF_0888) {}
    virtual unsigned int LoadTexture(const char* filename, int* tex_type = NULL, 
                                    unsigned int def_tid = 0, bool compresstodisk = true, 
                                    bool bWarn = true) { return 0; }
    virtual bool DXTCompress(byte* raw_data, int nWidth, int nHeight, ETEX_Format eTF, 
                            bool bUseHW, bool bGenMips, int nSrcBytesPerPix, 
                            MIPDXTcallback callback = 0) { return false; }
    virtual bool DXTDecompress(byte* srcData, byte* dstData, int nWidth, int nHeight, 
                              ETEX_Format eSrcTF, bool bUseHW, int nDstBytesPerPix) { return false; }
    virtual void RemoveTexture(unsigned int TextureId) {}
    virtual void RemoveTexture(ITexPic* pTexPic) {}
    virtual bool SetGammaDelta(const float fGamma) { return false; }
    
    // Text and UI Rendering stubs
    virtual void WriteXY(CXFont* currfont, int x, int y, float xscale, float yscale, 
                        float r, float g, float b, float a, const char* message, ...) {}
    virtual void Draw2dText(float posX, float posY, const char* szText, SDrawTextInfo& info) {}
    virtual void Draw2dImage(float xpos, float ypos, float w, float h, int texture_id, 
                            float s0 = 0, float t0 = 0, float s1 = 1, float t1 = 1, 
                            float angle = 0, float r = 1, float g = 1, float b = 1, 
                            float a = 1, float z = 1) {}
    virtual void DrawImage(float xpos, float ypos, float w, float h, int texture_id, 
                          float s0, float t0, float s1, float t1, float r, float g, float b, float a) {}
    virtual int SetPolygonMode(int mode) { return 0; }
    
    // All EF_ (shader system) methods as stubs
    virtual bool EF_PrecacheResource(IShader* pSH, float fDist, float fTimeToReady, int Flags) { return false; }
    virtual bool EF_PrecacheResource(ITexPic* pTP, float fDist, float fTimeToReady, int Flags) { return false; }
    virtual bool EF_PrecacheResource(CLeafBuffer* pPB, float fDist, float fTimeToReady, int Flags) { return false; }
    virtual bool EF_PrecacheResource(CDLight* pLS, float fDist, float fTimeToReady, int Flags) { return false; }
    virtual void EF_EnableHeatVision(bool bEnable) {}
    virtual bool EF_GetHeatVision() { return false; }
    virtual void EF_PolygonOffset(bool bEnable, float fFactor, float fUnits) {}
    virtual void EF_AddPolyToScene3D(int Ef, int numPts, SColorVert* verts, CCObject* obj = NULL, int nFogID = 0) {}
    virtual CCObject* EF_AddSpriteToScene(int Ef, int numPts, SColorVert* verts, CCObject* obj, byte* inds = NULL, int ninds = 0, int nFogID = 0) { return nullptr; }
    virtual void EF_AddPolyToScene2D(int Ef, int numPts, SColorVert2D* verts) {}
    virtual void EF_AddPolyToScene2D(SShaderItem si, int nTempl, int numPts, SColorVert2D* verts) {}
    virtual IShader* EF_LoadShader(const char* name, EShClass Class, int flags = 0, uint64 nMaskGen = 0) { return nullptr; }
    virtual SShaderItem EF_LoadShaderItem(const char* name, EShClass Class, bool bShare, const char* templName, int flags = 0, SInputShaderResources* Res = NULL, uint64 nMaskGen = 0) { return SShaderItem(); }
    virtual bool EF_ReloadFile(const char* szFileName) { return false; }
    virtual void EF_ReloadShaderFiles(int nCategory) {}
    virtual void EF_ReloadTextures() {}
    virtual IShader* EF_CopyShader(IShader* ef) { return nullptr; }
    virtual ITexPic* EF_GetTextureByID(int Id) { return nullptr; }
    virtual ITexPic* EF_LoadTexture(const char* nameTex, uint flags, uint flags2, byte eTT, float fAmount1 = -1.0f, float fAmount2 = -1.0f, int Id = -1, int BindId = 0) { return nullptr; }
    virtual int EF_LoadLightmap(const char* name) { return 0; }
    virtual bool EF_ScanEnvironmentCM(const char* name, int size, Vec3& Pos) { return false; }
    virtual int EF_ReadAllImgFiles(IShader* ef, SShaderTexUnit* tl, STexAnim* ta, char* name) { return 0; }
    virtual char** EF_GetShadersForFile(const char* File, int num) { return nullptr; }
    virtual SLightMaterial* EF_GetLightMaterial(char* Str) { return nullptr; }
    virtual bool EF_RegisterTemplate(int nTemplId, char* Name, bool bReplace) { return false; }
    virtual void EF_AddSplash(Vec3 Pos, eSplashType eST, float fForce, int Id = -1) {}
    virtual bool EF_HideTemplate(const char* name) { return false; }
    virtual bool EF_UnhideTemplate(const char* name) { return false; }
    virtual bool EF_UnhideAllTemplates() { return false; }
    virtual bool EF_SetLightHole(Vec3 vPos, Vec3 vNormal, int idTex, float fScale = 1.0f, bool bAdditive = true) { return false; }
    virtual CRendElement* EF_CreateRE(EDataType edt);
    virtual void EF_StartEf() {}
    virtual CCObject* EF_GetObject(bool bTemp = false, int num = -1) { return nullptr; }
    virtual void EF_AddEf(int NumFog, CRendElement* re, IShader* ef, SRenderShaderResources* sr, CCObject* obj, int nTempl, IShader* efState = 0, int nSort = 0) {}
    virtual void EF_EndEf3D(int nFlags) {}
    virtual bool EF_IsFakeDLight(CDLight* Source) { return false; }
    virtual void EF_ADDDlight(CDLight* Source) {}
    virtual void EF_ClearLightsList() {}
    virtual bool EF_UpdateDLight(CDLight* pDL) { return false; }
    virtual void EF_EndEf2D(bool bSort) {}
    virtual bool EF_DrawEfForName(char* name, float x, float y, float width, float height, CFColor& col, int nTempl = -1) { return false; }
    virtual bool EF_DrawEfForNum(int num, float x, float y, float width, float height, CFColor& col, int nTempl = -1) { return false; }
    virtual bool EF_DrawEf(IShader* ef, float x, float y, float width, float height, CFColor& col, int nTempl = -1) { return false; }
    virtual bool EF_DrawEf(SShaderItem si, float x, float y, float width, float height, CFColor& col, int nTempl = -1) { return false; }
    virtual bool EF_DrawPartialEfForName(char* name, SVrect* vr, SVrect* pr, CFColor& col) { return false; }
    virtual bool EF_DrawPartialEfForNum(int num, SVrect* vr, SVrect* pr, CFColor& col) { return false; }
    virtual bool EF_DrawPartialEf(IShader* ef, SVrect* vr, SVrect* pr, CFColor& col, float iwdt = 0, float ihgt = 0) { return false; }
    virtual void* EF_Query(int Query, int Param = 0) { return nullptr; }
    virtual void EF_ConstructEf(IShader* Ef) {}
    virtual void EF_SetWorldColor(float r, float g, float b, float a = 1.0f) {}
    virtual int EF_RegisterFogVolume(float fMaxFogDist, float fFogLayerZ, CFColor color, int nIndex = -1, bool bCaustics = false) { return 0; }
    
    // Font system stubs
    virtual bool FontUploadTexture(class CFBitmap*, ETEX_Format eTF = eTF_8888) { return false; }
    virtual int FontCreateTexture(int Width, int Height, byte* pData, ETEX_Format eTF = eTF_8888) { return 0; }
    virtual bool FontUpdateTexture(int nTexId, int X, int Y, int USize, int VSize, byte* pData) { return false; }
    virtual void FontReleaseTexture(class CFBitmap* pBmp) {}
    virtual void FontSetTexture(class CFBitmap*, int nFilterMode) {}
    virtual void FontSetTexture(int nTexId, int nFilterMode) {}
    virtual void FontSetRenderingState(unsigned long nVirtualScreenWidth, unsigned long nVirtualScreenHeight) {}
    virtual void FontSetBlending(int src, int dst) {}
    virtual void FontRestoreRenderingState() {}
    
    // LeafBuffer stubs
    virtual CLeafBuffer* CreateLeafBuffer(bool bDynamic, const char* szSource = "Unknown", class CIndexedMesh* pIndexedMesh = 0) { return nullptr; }
    virtual CLeafBuffer* CreateLeafBufferInitialized(void* pVertBuffer, int nVertCount, int nVertFormat, ushort* pIndices, int nIndices, int nPrimetiveType, const char* szSource, EBufferType eBufType = eBT_Dynamic, int nMatInfoCount = 1, int nClientTextureBindID = 0, bool (*PrepareBufferCallback)(CLeafBuffer*, bool) = NULL, void* CustomData = NULL, bool bOnlyVideoBuffer = false, bool bPrecache = true) { return nullptr; }
    virtual void DeleteLeafBuffer(CLeafBuffer* pLBuffer) {}
    
    // Additional utility stubs
    virtual void TextToScreen(float x, float y, const char* format, ...) {}
    virtual void TextToScreenColor(int x, int y, float r, float g, float b, float a, const char* format, ...) {}
    virtual void ResetToDefault() {}
    virtual int GenerateAlphaGlowTexture(float k) { return 0; }
    virtual void SetMaterialColor(float r, float g, float b, float a) {}
    virtual int LoadAnimatedTexture(const char* format, const int nCount) { return 0; }
    virtual void RemoveAnimatedTexture(AnimTexInfo* pInfo) {}
    virtual AnimTexInfo* GetAnimTexInfoFromId(int nId) { return nullptr; }
    virtual void Draw2dLine(float x1, float y1, float x2, float y2) {}
    virtual void SetLineWidth(float fWidth) {}
    virtual void DrawLine(const Vec3& vPos1, const Vec3& vPos2) {}
    virtual void DrawLineColor(const Vec3& vPos1, const CFColor& vColor1, const Vec3& vPos2, const CFColor& vColor2) {}
    virtual void Graph(byte* g, int x, int y, int wdt, int hgt, int nC, int type, char* text, CFColor& color, float fScale) {}
    virtual void DrawBall(float x, float y, float z, float radius) {}
    virtual void DrawBall(const Vec3& pos, float radius) {}
    virtual void DrawPoint(float x, float y, float z, float fSize = 0.0f) {}
    virtual void FlushTextMessages() {}
    virtual void DrawObjSprites(list2<CStatObjInst*>* pList, float fMaxViewDist, CObjManager* pObjMan) {}
    virtual void DrawQuad(const Vec3& right, const Vec3& up, const Vec3& origin, int nFlipMode = 0) {}
    virtual void DrawQuad(float dy, float dx, float dz, float x, float y, float z) {}
    virtual void ClearDepthBuffer() {}
    virtual void ClearColorBuffer(const Vec3 vColor) {}
    virtual void ReadFrameBuffer(unsigned char* pRGB, int nSizeX, int nSizeY, bool bBackBuffer, bool bRGBA, int nScaledX = -1, int nScaledY = -1) {}
    virtual void SetFogColor(float* color) {}
    virtual void TransformTextureMatrix(float x, float y, float angle, float scale) {}
    virtual void ResetTextureMatrix() {}
    virtual unsigned int MakeSprite(float object_scale, int tex_size, float angle, IStatObj* pStatObj, uchar* pTmpBuffer, uint def_tid) { return 0; }
    virtual unsigned int Make3DSprite(int nTexSize, float fAngleStep, IStatObj* pStatObj) { return 0; }
    virtual ShadowMapFrustum* MakeShadowMapFrustum(ShadowMapFrustum* lof, ShadowMapLightSource* pLs, const Vec3& obj_pos, list2<IStatObj*>* pStatObjects, int shadow_type) { return nullptr; }
    virtual void Set2DMode(bool enable, int ortox, int ortoy) {}
    virtual int ScreenToTexture() { return 0; }
    virtual void SetTexClampMode(bool clamp) {}
    virtual void DrawLabelImage(const Vec3& vPos, float fSize, int nTextureId) {}
    virtual void DrawLabel(Vec3 pos, float font_size, const char* label_text, ...) {}
    virtual void DrawLabelEx(Vec3 pos, float font_size, float* pfColor, bool bFixedSize, bool bCenter, const char* label_text, ...) {}
    virtual void Draw2dLabel(float x, float y, float font_size, float* pfColor, bool bCenter, const char* label_text, ...) {}
    
    // File I/O stubs
    virtual void WriteDDS(byte* dat, int wdt, int hgt, int Size, const char* name, EImFormat eF, int NumMips) {}
    virtual void WriteTGA(byte* dat, int wdt, int hgt, const char* name, int bits) {}
    virtual void WriteJPG(byte* dat, int wdt, int hgt, char* name) {}

public:
    // Metal-specific members (public for manager access)
    id<MTLDevice> m_device;
    id<MTLCommandQueue> m_commandQueue;
    id<MTLRenderCommandEncoder> m_renderEncoder;
    MTKView* m_metalView;
    CAMetalLayer* m_metalLayer;
    
    // Current frame resources
    id<MTLCommandBuffer> m_currentCommandBuffer;
    MTLRenderPassDescriptor* m_renderPassDescriptor;
    
    // Render state
    id<MTLRenderPipelineState> m_currentPipelineState;
    id<MTLDepthStencilState> m_currentDepthStencilState;
    
    // Render state management
    bool m_depthTestEnabled;
    bool m_depthWriteEnabled;
    MTLCompareFunction m_depthFunction;
    bool m_blendingEnabled;
    MTLBlendFactor m_sourceBlendFactor;
    MTLBlendFactor m_destBlendFactor;
    MTLBlendOperation m_blendOperation;
    
    // Vertex buffer management
    std::vector<id<MTLBuffer>> m_vertexBuffers;
    std::vector<id<MTLBuffer>> m_indexBuffers;
    int m_nextVertexBufferId;
    int m_nextIndexBufferId;
    
    // Basic renderer state
    bool m_isInitialized;
    int m_width, m_height;
    int m_cbpp, m_zbpp, m_sbpp;
    bool m_fullscreen;
    
    /**
     * @brief Current rendering camera (stored by value)
     * 
     * The camera is stored by value (not pointer) to avoid lifetime issues
     * and ensure the renderer owns its camera state. This is updated via
     * SetCamera() and queried via GetCamera().
     * 
     * @design_decision
     * Storing by value instead of pointer:
     * - PRO: No lifetime/ownership issues
     * - PRO: No null pointer checks needed
     * - PRO: Matches OpenGL renderer pattern
     * - CON: Copy overhead when calling SetCamera() (acceptable)
     * 
     * @note
     * CMetalRenderer delegates camera access to this base class member
     * to avoid duplication and ensure single source of truth.
     * 
     * @see SetCamera(), GetCamera()
     */
    CCamera m_camera;
    
    // Viewport state
    int m_viewportX, m_viewportY, m_viewportWidth, m_viewportHeight;
    
    // Matrix stack for transformations
    std::stack<Matrix44> m_matrixStack;
    Matrix44 m_currentMatrix;
    Matrix44 m_viewMatrix;
    Matrix44 m_projectionMatrix;
    Matrix44 m_modelViewProjectionMatrix;
    bool m_matrixDirty;
    
    // Command buffer pool for triple buffering
    static const int MAX_FRAMES_IN_FLIGHT = 3;
    int m_currentFrameIndex;
    std::array<id<MTLCommandBuffer>, MAX_FRAMES_IN_FLIGHT> m_commandBufferPool;
    std::array<dispatch_semaphore_t, MAX_FRAMES_IN_FLIGHT> m_frameSemaphores;
    
    // Dynamic vertex buffer pool
    struct DynamicVBPool
    {
        id<MTLBuffer> buffer;
        size_t size;
        size_t offset;
        void* cpuData;
    };
    static const int NUM_DYNAMIC_VB_POOLS = 2;
    std::array<DynamicVBPool, NUM_DYNAMIC_VB_POOLS> m_dynamicVBPools;
    int m_currentDynamicVBPool;
    
    // Uniform buffer for MVP matrices and common parameters
    struct UniformBufferData
    {
        Matrix44 modelViewProjectionMatrix;
        Matrix44 modelMatrix;
        Matrix44 viewMatrix;
        Matrix44 projectionMatrix;
        Vec3 cameraPos;
        float time;
        Vec3 lightPos;
        float padding1;
        Vec3 lightColor;
        float padding2;
    };
    id<MTLBuffer> m_uniformBuffer;
    UniformBufferData* m_uniformBufferCPU;
    
    // State cache
    std::unique_ptr<CMetalStateCache> m_stateCache;
    
    // Current render state tracking
    int m_currentState;
    int m_currentCullMode;
    bool m_fogEnabled;
    bool m_texGenEnabled;
    float m_lodBias;
    bool m_vSyncEnabled;
    int m_currentTMU;
    
    // Frame statistics
    int m_frameID;
    int m_numDrawCalls;
    int m_numTriangles;
    
    // Internal methods
    bool InitializeDevice();
    bool InitializeCommandQueue();
    bool InitializeRenderPipeline();
    void UpdateRenderPassDescriptor();
    bool InitializeCommandBufferPool();
    bool InitializeDynamicVBPools();
    bool InitializeUniformBuffers();
    void CleanupCommandBufferPool();
    void CleanupDynamicVBPools();
    void CleanupUniformBuffers();
    
    // Vertex buffer management
    int CreateVertexBuffer(const void* data, size_t size);
    int CreateIndexBuffer(const void* data, size_t size);
    void UpdateVertexBuffer(int bufferId, const void* data, size_t size);
    void UpdateIndexBuffer(int bufferId, const void* data, size_t size);
    void ReleaseVertexBuffer(int bufferId);
    void ReleaseIndexBuffer(int bufferId);
    id<MTLBuffer> GetVertexBuffer(int bufferId);
    id<MTLBuffer> GetIndexBuffer(int bufferId);
    id<MTLTexture> CreateMetalTexture(int width, int height, MTLPixelFormat format);
    id<MTLBuffer> CreateMetalBuffer(void* data, size_t size, MTLResourceOptions options);
    
    // Render state management
    void SetDepthTest(bool enabled);
    void SetDepthWrite(bool enabled);
    void SetDepthFunction(MTLCompareFunction function);
    void SetBlending(bool enabled);
    void SetBlendFactors(MTLBlendFactor source, MTLBlendFactor dest, MTLBlendOperation operation);
    void ApplyRenderState();
    void UpdateMatrices();
    void UpdateUniformBuffer();
    
    // Helper conversion functions
    MTLPrimitiveType ConvertPrimitiveType(int prmode);
    MTLCompareFunction ConvertCompareFunction(int func);
    MTLBlendFactor ConvertBlendFactor(int factor);
    int GetVertexFormatSize(int vertexformat);
};

#endif // __APPLE__ && __MACH__

#endif // METAL_BASE_RENDERER_H
