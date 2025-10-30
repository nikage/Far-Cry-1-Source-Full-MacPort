#include "SimpleStubRenderer.h"
#include <cstdarg>
#include <cstdio>

CSimpleStubRenderer::CSimpleStubRenderer()
    : m_width(0)
    , m_height(0)
    , m_frameID(0)
    , m_isInitialized(false)
{
    assert(false && "Renderer not implemented, fix dummy stubs");
}

CSimpleStubRenderer::~CSimpleStubRenderer()
{
    ShutDown();
}

void* CSimpleStubRenderer::Init(int x, int y, int width, int height, unsigned int cbpp, int zbpp, int sbits, bool fullscreen, void* hinst, void* hWnd, void* hdc, void* hglrc, bool bReInit)
{
    // Use the provided dimensions, or fall back to reasonable defaults if invalid
    m_width = (width > 0) ? width : 1024;
    m_height = (height > 0) ? height : 768;
    m_isInitialized = true;
    iLog->Log("SimpleStubRenderer: Initialized with %dx%d (requested: %dx%d)\n", m_width, m_height, width, height);
    return (void*)this;
}

void CSimpleStubRenderer::ShutDown(bool bReInit)
{
    m_isInitialized = false;
    iLog->Log("SimpleStubRenderer: Shutdown\n");
}

void CSimpleStubRenderer::BeginFrame()
{
    if (!m_isInitialized) return;
    m_frameID++;
    // iLog->Log("SimpleStubRenderer: BeginFrame %d\n", m_frameID);
}

void CSimpleStubRenderer::Update()
{
    if (!m_isInitialized) return;
    // iLog->Log("SimpleStubRenderer: Update\n");
}

void CSimpleStubRenderer::Set2DMode(bool enable, int ortox, int ortoy)
{
    // iLog->Log("SimpleStubRenderer: Set2DMode %s\n", enable ? "ON" : "OFF");
}

void CSimpleStubRenderer::SetState(int st)
{
    // iLog->Log("SimpleStubRenderer: SetState %d\n", st);
}

void CSimpleStubRenderer::Draw2dImage(float xpos, float ypos, float w, float h, int texture_id, float s0, float t0, float s1, float t1, float angle, float r, float g, float b, float a, float z)
{
    // iLog->Log("SimpleStubRenderer: Draw2dImage pos(%.1f,%.1f) size(%.1fx%.1f) tex=%d\n", xpos, ypos, w, h, texture_id);
}

void CSimpleStubRenderer::SetTexture(int tnum, int Type)
{
    // iLog->Log("SimpleStubRenderer: SetTexture %d\n", tnum);
}

void CSimpleStubRenderer::TextToScreen(float x, float y, const char* format, ...)
{
    va_list args;
    va_start(args, format);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    iLog->Log("SimpleStubRenderer TextToScreen: %s\n", buffer);
}

void CSimpleStubRenderer::TextToScreenColor(int x, int y, float r, float g, float b, float a, const char* format, ...)
{
    va_list args;
    va_start(args, format);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    iLog->Log("SimpleStubRenderer TextToScreenColor: %s\n", buffer);
}

int CSimpleStubRenderer::GetWidth()
{
    return m_width;
}

int CSimpleStubRenderer::GetHeight()
{
    return m_height;
}

int CSimpleStubRenderer::GetFrameID()
{
    return m_frameID;
}

void CSimpleStubRenderer::Release()
{
    ShutDown();
}

void CSimpleStubRenderer::SetType(char type)
{
    iLog->Log("SimpleStubRenderer: SetType called with type: %d\n", type);
}

// Simple IRenderer implementation that delegates to CSimpleStubRenderer
class CSimpleIRenderer : public IRenderer
{
private:
    CSimpleStubRenderer* m_stubRenderer;
    
public:
    CSimpleIRenderer() : m_stubRenderer(new CSimpleStubRenderer()) {}
    virtual ~CSimpleIRenderer() { delete m_stubRenderer; }
    
    // Delegate essential methods to stub renderer
    virtual void* Init(int x, int y, int width, int height, unsigned int cbpp, int zbpp, int sbits, bool fullscreen, void* hinst, void* hWnd, void* hdc = 0, void* hglrc = 0, bool bReInit = false) override {
        return m_stubRenderer->Init(x, y, width, height, cbpp, zbpp, sbits, fullscreen, hinst, hWnd, hdc, hglrc, bReInit);
    }
    virtual void ShutDown(bool bReInit = false) override { m_stubRenderer->ShutDown(bReInit); }
    virtual void BeginFrame() override { m_stubRenderer->BeginFrame(); }
    virtual void Update() override { m_stubRenderer->Update(); }
    virtual void Set2DMode(bool enable, int ortox, int ortoy) override { m_stubRenderer->Set2DMode(enable, ortox, ortoy); }
    virtual void SetState(int st) override { m_stubRenderer->SetState(st); }
    virtual void Draw2dImage(float xpos, float ypos, float w, float h, int texture_id, float s0 = 0, float t0 = 0, float s1 = 1, float t1 = 1, float angle = 0, float r = 1, float g = 1, float b = 1, float a = 1, float z = 1) override {
        m_stubRenderer->Draw2dImage(xpos, ypos, w, h, texture_id, s0, t0, s1, t1, angle, r, g, b, a, z);
    }
    virtual void SetTexture(int tnum, int Type = 0) override { m_stubRenderer->SetTexture(tnum, Type); }
    virtual void TextToScreen(float x, float y, const char* format, ...) override { m_stubRenderer->TextToScreen(x, y, format); }
    virtual void TextToScreenColor(int x, int y, float r, float g, float b, float a, const char* format, ...) override { m_stubRenderer->TextToScreenColor(x, y, r, g, b, a, format); }
    virtual int GetWidth() override { return m_stubRenderer->GetWidth(); }
    virtual int GetHeight() override { return m_stubRenderer->GetHeight(); }
    virtual int GetFrameID() override { return m_stubRenderer->GetFrameID(); }
    virtual void Release() override { m_stubRenderer->Release(); }
    virtual void SetType(char type) override { m_stubRenderer->SetType(type); }
    
    // Implement all other IRenderer methods as stubs
    virtual void SetViewport(int x = 0, int y = 0, int width = 0, int height = 0) override { assert(!"Not implemented"); }
    virtual void SetScissor(int x = 0, int y = 0, int width = 0, int height = 0) override { assert(!"Not implemented"); }
    virtual void SetCamera(const void& cam) override { assert(!"Not implemented"); }
    virtual const void& GetCamera() override { assert(!"Not implemented"); }
    virtual void SetWhiteTexture() override { assert(!"Not implemented"); }
    virtual void DrawTriStrip(void* src, int vert_num = 4) override { assert(!"Not implemented"); }
    virtual void DrawBuffer(void* src, void* indices, int numindices, int offsindex, int prmode, int vert_start = 0, int vert_stop = 0, void* mi = NULL) override { assert(!"Not implemented"); }
    virtual void Draw3dBBox(const Vec3& mins, const Vec3& maxs, int nPrimType = 0) override { assert(!"Not implemented"); }
    virtual void Draw3dPrim(const Vec3& mins, const Vec3& maxs, int nPrimType = 0, const float* fRGBA = NULL) override { assert(!"Not implemented"); }
    virtual void DrawLabelImage(const Vec3& vPos, float fSize, int nTextureId) override { assert(!"Not implemented"); }
    virtual void DrawLineColor(const Vec3& vPos1, const void& vColor1, const Vec3& vPos2, const void& vColor2) override { assert(!"Not implemented"); }
    virtual void FlushTextMessages() override { assert(!"Not implemented"); }
    virtual void ClearDepthBuffer() override { assert(!"Not implemented"); }
    virtual void ClearColorBuffer(const Vec3 vColor) override { assert(!"Not implemented"); }
    virtual int ScreenToTexture() override { assert(!"Not implemented"); }
    virtual void SetTexClampMode(bool clamp) override { assert(!"Not implemented"); }
    virtual void SetCullMode(int mode = 0) override { assert(!"Not implemented"); }
    virtual void DrawImage(float xpos, float ypos, float w, float h, int texture_id, float s0, float t0, float s1, float t1, float r, float g, float b, float a) override { assert(!"Not implemented"); }
    virtual void UpdateBuffer(void* dest, const void* src, int vertexcount, bool bUnLock, int nOffs = 0, int Type = 0) override { assert(!"Not implemented"); }
    virtual void CreateIndexBuffer(void* dest, const void* src, int indexcount) override { assert(!"Not implemented"); }
    virtual void UpdateIndexBuffer(void* dest, const void* src, int indexcount, bool bUnLock = true) override { assert(!"Not implemented"); }
    virtual void ReleaseIndexBuffer(void* dest) override { assert(!"Not implemented"); }
    virtual void* CreateBuffer(int vertexcount, int vertexformat, const char* szSource, bool bDynamic = false) override { assert(!"Not implemented"); }
    virtual void ReleaseBuffer(void* bufptr) override { assert(!"Not implemented"); }
    virtual void DrawDynVB(void* pBuf, void* pInds, int nVerts, int nInds, int nPrimType) override { assert(!"Not implemented"); }
    virtual int EnumDisplayFormats(void* Formats, bool bReset) override { assert(!"Not implemented"); }
    virtual bool ChangeResolution(int nNewWidth, int nNewHeight, int nNewColDepth, int nNewRefreshHZ, bool bFullScreen) override { assert(!"Not implemented"); }
    virtual void* GetHWND() override { assert(!"Not implemented"); }
    virtual bool SetCurrentContext(void* hWnd) override { assert(!"Not implemented"); }
    virtual bool CreateContext(void* hWnd, bool bAllowFSAA = false) override { assert(!"Not implemented"); }
    virtual bool DeleteContext(void* hWnd) override { assert(!"Not implemented"); }
    virtual int GetFeatures() override { assert(!"Not implemented"); }
    virtual int GetMaxTextureMemory() override { assert(!"Not implemented"); }
    virtual bool SetGammaDelta(const float fGamma) override { assert(!"Not implemented"); }
    virtual bool SaveTga(unsigned char* sourcedata, int sourceformat, int w, int h, const char* filename, bool flip) override { assert(!"Not implemented"); }
    virtual int SetPolygonMode(int mode) override { assert(!"Not implemented"); }
    virtual void GetMemoryUsage(void* Sizer) override { assert(!"Not implemented"); }
    virtual void ScreenShot(const char* filename = NULL) override { assert(!"Not implemented"); }
    virtual void FreeResources(int nFlags) override { assert(!"Not implemented"); }
    virtual void RefreshResources(int nFlags) override { assert(!"Not implemented"); }
    virtual void PreLoad() override { assert(!"Not implemented"); }
    virtual void PostLoad() override { assert(!"Not implemented"); }
    virtual void ShareResources(IRenderer* renderer) override { assert(!"Not implemented"); }
    virtual void GetViewport(int* x, int* y, int* width, int* height) override { assert(!"Not implemented"); }
    virtual void MakeCurrent() override { assert(!"Not implemented"); }
    virtual void* GetDynVBPtr(int nVerts, int& nOffs, int Pool) override { assert(!"Not implemented"); }
    virtual void DrawDynVB(int nOffs, int Pool, int nVerts) override { assert(!"Not implemented"); }
    virtual void SetFenceCompleted(void* buffer) override { assert(!"Not implemented"); }
    virtual void CheckError(const char* comment) override { assert(!"Not implemented"); }
    virtual bool ChangeDisplay(unsigned int width, unsigned int height, unsigned int cbpp) override { assert(!"Not implemented"); }
    virtual void ChangeViewport(unsigned int x, unsigned int y, unsigned int width, unsigned int height) override { assert(!"Not implemented"); }
    virtual int GetColorBpp() override { assert(!"Not implemented"); }
    virtual int GetDepthBpp() override { assert(!"Not implemented"); }
    virtual int GetStencilBpp() override { assert(!"Not implemented"); }
    virtual char GetType() override { assert(!"Not implemented"); }
    virtual void SetType(char type) override { m_stubRenderer->SetType(type); }
    virtual int GetFrameID(bool bIncludeRecursiveCalls = true) override { return m_stubRenderer->GetFrameID(); }
    virtual void Set2DMode(bool enable, int ortox, int ortoy) override { m_stubRenderer->Set2DMode(enable, ortox, ortoy); }
    virtual void SetState(int State) override { m_stubRenderer->SetState(State); }
    virtual void TextToScreen(float x, float y, const char* format, ...) override { m_stubRenderer->TextToScreen(x, y, format); }
    virtual void TextToScreenColor(int x, int y, float r, float g, float b, float a, const char* format, ...) override { m_stubRenderer->TextToScreenColor(x, y, r, g, b, a, format); }
    virtual void* EF_LoadTexture(const char* nameTex, uint flags, uint flags2, byte eTT, float fAmount1 = -1.0f, float fAmount2 = -1.0f, int Id = -1, int BindId = 0) override { assert(!"Not implemented"); }
    virtual void* EF_GetTextureByID(int Id) override { assert(!"Not implemented"); }
    virtual void RemoveTexture(unsigned int TextureId) override { assert(!"Not implemented"); }
    virtual void RemoveTexture(void* pTexPic) override { assert(!"Not implemented"); }
    virtual int LoadAnimatedTexture(const char* format, const int nCount) override { assert(!"Not implemented"); }
    virtual void DrawLabelImage(const Vec3& vPos, float fSize, int nTextureId) override { assert(!"Not implemented"); }
    virtual void DrawLineColor(const Vec3& vPos1, const void& vColor1, const Vec3& vPos2, const void& vColor2) override { assert(!"Not implemented"); }
    virtual void FlushTextMessages() override { assert(!"Not implemented"); }
    virtual void ClearDepthBuffer() override { assert(!"Not implemented"); }
    virtual void ClearColorBuffer(const Vec3 vColor) override { assert(!"Not implemented"); }
    virtual int ScreenToTexture() override { assert(!"Not implemented"); }
    virtual void SetTexClampMode(bool clamp) override { assert(!"Not implemented"); }
    virtual void SetCullMode(int mode = 0) override { assert(!"Not implemented"); }
    virtual void DrawImage(float xpos, float ypos, float w, float h, int texture_id, float s0, float t0, float s1, float t1, float r, float g, float b, float a) override { assert(!"Not implemented"); }
    virtual void Draw3dPrim(const Vec3& mins, const Vec3& maxs, int nPrimType = 0, const float* fRGBA = NULL) override { assert(!"Not implemented"); }
    virtual void DrawTriStrip(void* src, int vert_num = 4) override { assert(!"Not implemented"); }
    virtual void DrawBuffer(void* src, void* indices, int numindices, int offsindex, int prmode, int vert_start = 0, int vert_stop = 0, void* mi = NULL) override { assert(!"Not implemented"); }
    virtual void UpdateBuffer(void* dest, const void* src, int vertexcount, bool bUnLock, int nOffs = 0, int Type = 0) override { assert(!"Not implemented"); }
    virtual void CreateIndexBuffer(void* dest, const void* src, int indexcount) override { assert(!"Not implemented"); }
    virtual void UpdateIndexBuffer(void* dest, const void* src, int indexcount, bool bUnLock = true) override { assert(!"Not implemented"); }
    virtual void ReleaseIndexBuffer(void* dest) override { assert(!"Not implemented"); }
    virtual void* CreateBuffer(int vertexcount, int vertexformat, const char* szSource, bool bDynamic = false) override { assert(!"Not implemented"); }
    virtual void ReleaseBuffer(void* bufptr) override { assert(!"Not implemented"); }
    virtual void DrawDynVB(void* pBuf, void* pInds, int nVerts, int nInds, int nPrimType) override { assert(!"Not implemented"); }
    virtual int EnumDisplayFormats(void* Formats, bool bReset) override { assert(!"Not implemented"); }
    virtual bool ChangeResolution(int nNewWidth, int nNewHeight, int nNewColDepth, int nNewRefreshHZ, bool bFullScreen) override { assert(!"Not implemented"); }
    virtual void* GetHWND() override { assert(!"Not implemented"); }
    virtual bool SetCurrentContext(void* hWnd) override { assert(!"Not implemented"); }
    virtual bool CreateContext(void* hWnd, bool bAllowFSAA = false) override { assert(!"Not implemented"); }
    virtual bool DeleteContext(void* hWnd) override { assert(!"Not implemented"); }
    virtual int GetFeatures() override { assert(!"Not implemented"); }
    virtual int GetMaxTextureMemory() override { assert(!"Not implemented"); }
    virtual bool SetGammaDelta(const float fGamma) override { assert(!"Not implemented"); }
    virtual bool SaveTga(unsigned char* sourcedata, int sourceformat, int w, int h, const char* filename, bool flip) override { assert(!"Not implemented"); }
    virtual int SetPolygonMode(int mode) override { assert(!"Not implemented"); }
    virtual void GetMemoryUsage(void* Sizer) override { assert(!"Not implemented"); }
    virtual void ScreenShot(const char* filename = NULL) override { assert(!"Not implemented"); }
    virtual void FreeResources(int nFlags) override { assert(!"Not implemented"); }
    virtual void RefreshResources(int nFlags) override { assert(!"Not implemented"); }
    virtual void PreLoad() override { assert(!"Not implemented"); }
    virtual void PostLoad() override { assert(!"Not implemented"); }
    virtual void ShareResources(IRenderer* renderer) override { assert(!"Not implemented"); }
    virtual void GetViewport(int* x, int* y, int* width, int* height) override { assert(!"Not implemented"); }
    virtual void MakeCurrent() override { assert(!"Not implemented"); }
    virtual void* GetDynVBPtr(int nVerts, int& nOffs, int Pool) override { assert(!"Not implemented"); }
    virtual void DrawDynVB(int nOffs, int Pool, int nVerts) override { assert(!"Not implemented"); }
    virtual void SetFenceCompleted(void* buffer) override { assert(!"Not implemented"); }
    virtual void CheckError(const char* comment) override { assert(!"Not implemented"); }
    virtual bool ChangeDisplay(unsigned int width, unsigned int height, unsigned int cbpp) override { assert(!"Not implemented"); }
    virtual void ChangeViewport(unsigned int x, unsigned int y, unsigned int width, unsigned int height) override { assert(!"Not implemented"); }
};

// Export function for the renderer
extern "C" {
    IRenderer* PackageRenderConstructor(int argc, char* argv[], SCryRenderInterface* sp)
    {
        CSimpleIRenderer* renderer = new CSimpleIRenderer();
        return renderer;
    }
}
