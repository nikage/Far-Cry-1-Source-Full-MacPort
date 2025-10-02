#include "SimpleMetalRenderer.h"
#include "IRenderer.h"
#include <Cocoa/Cocoa.h>
#include <cstdarg>
#include <cstdio>
#include <string>

// Define DLL_EXPORT for macOS
#ifndef DLL_EXPORT
#define DLL_EXPORT
#endif

// Forward declarations for missing types
class CCamera { public: CCamera() {} };

CSimpleMetalRenderer::CSimpleMetalRenderer()
    : m_device(nil)
    , m_commandQueue(nil)
    , m_renderEncoder(nil)
    , m_metalView(nil)
    , m_metalLayer(nil)
    , m_currentCommandBuffer(nil)
    , m_currentPipelineState(nil)
    , m_currentDepthStencilState(nil)
    , m_width(800)
    , m_height(600)
    , m_colorBpp(32)
    , m_depthBpp(24)
    , m_stencilBpp(8)
    , m_type(5) // R_METAL_RENDERER
    , m_isInitialized(false)
    , m_viewportX(0)
    , m_viewportY(0)
    , m_viewportWidth(m_width)
    , m_viewportHeight(m_height)
    , m_camera(nullptr)
    , m_2DMode(false)
    , m_2DWidth(m_width)
    , m_2DHeight(m_height)
    , m_frameID(0)
    , m_currentState(0)
{
}

CSimpleMetalRenderer::~CSimpleMetalRenderer()
{
    ShutDown();
}

void* CSimpleMetalRenderer::Init(int x, int y, int width, int height, unsigned int cbpp, int zbpp, int sbits, bool fullscreen, void* hinst, void* hWnd, void* hdc, void* hglrc, bool bReInit)
{
    m_width = width;
    m_height = height;
    m_colorBpp = cbpp;
    m_depthBpp = zbpp;
    m_stencilBpp = sbits;
    
    if (!InitializeDevice())
    {
        return nullptr;
    }
    
    if (!InitializeCommandQueue())
    {
        return nullptr;
    }
    
    if (!InitializeRenderPipeline())
    {
        return nullptr;
    }
    
    m_isInitialized = true;
    return (void*)this; // Return self as handle
}

void CSimpleMetalRenderer::ShutDown(bool bReInit)
{
    if (m_renderEncoder)
    {
        [m_renderEncoder endEncoding];
        m_renderEncoder = nil;
    }
    
    if (m_currentCommandBuffer)
    {
        m_currentCommandBuffer = nil;
    }
    
    if (m_currentPipelineState)
    {
        m_currentPipelineState = nil;
    }
    
    if (m_currentDepthStencilState)
    {
        m_currentDepthStencilState = nil;
    }
    
    if (m_commandQueue)
    {
        m_commandQueue = nil;
    }
    
    if (m_device)
    {
        m_device = nil;
    }
    
    m_isInitialized = false;
}

void CSimpleMetalRenderer::BeginFrame()
{
    if (!m_isInitialized)
        return;
        
    // Create a new command buffer for this frame
    m_currentCommandBuffer = [m_commandQueue commandBuffer];
    
    // Create render pass descriptor
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    
    // Start encoding render commands
    m_renderEncoder = [m_currentCommandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    // Increment frame ID
    m_frameID++;
}

void CSimpleMetalRenderer::Update()
{
    if (!m_isInitialized)
        return;
        
    if (m_renderEncoder)
    {
        [m_renderEncoder endEncoding];
        m_renderEncoder = nil;
    }
    
    if (m_currentCommandBuffer)
    {
        [m_currentCommandBuffer commit];
        m_currentCommandBuffer = nil;
    }
}

void CSimpleMetalRenderer::SetViewport(int x, int y, int width, int height)
{
    m_viewportX = x;
    m_viewportY = y;
    m_viewportWidth = width;
    m_viewportHeight = height;
    
    if (m_renderEncoder)
    {
        MTLViewport viewport;
        viewport.originX = x;
        viewport.originY = y;
        viewport.width = width;
        viewport.height = height;
        viewport.znear = 0.0;
        viewport.zfar = 1.0;
        [m_renderEncoder setViewport:viewport];
    }
}

void CSimpleMetalRenderer::SetScissor(int x, int y, int width, int height)
{
    if (m_renderEncoder)
    {
        MTLScissorRect scissor;
        scissor.x = x;
        scissor.y = y;
        scissor.width = width;
        scissor.height = height;
        [m_renderEncoder setScissorRect:scissor];
    }
}

void CSimpleMetalRenderer::SetCamera(const CCamera& cam)
{
    assert(!"SetCamera not implemented");
}

const CCamera& CSimpleMetalRenderer::GetCamera()
{
    if (!m_camera)
    {
        m_camera = new CCamera();
    }
    return *m_camera;
}

void CSimpleMetalRenderer::SetTexture(int tnum, ETexType Type)
{
    // Basic texture binding - for now just log the call
    printf("SetTexture: tex=%d type=%d\n", tnum, (int)Type);
    // TODO: Implement actual texture binding with Metal
}

void CSimpleMetalRenderer::SetWhiteTexture()
{
    assert(!"SetWhiteTexture not implemented");
}

void CSimpleMetalRenderer::DrawTriStrip(CVertexBuffer* src, int vert_num)
{
    assert(!"DrawTriStrip not implemented");
}

void CSimpleMetalRenderer::DrawBuffer(CVertexBuffer* src, SVertexStream* indices, int numindices, int offsindex, int prmode, int vert_start, int vert_stop, CMatInfo* mi)
{
    assert(!"DrawBuffer not implemented");
}

void CSimpleMetalRenderer::Draw3dBBox(const Vec3& mins, const Vec3& maxs, int nPrimType)
{
    assert(!"Draw3dBBox not implemented");
}

void CSimpleMetalRenderer::Draw2dImage(float xpos, float ypos, float w, float h, int texture_id, float s0, float t0, float s1, float t1, float angle, float r, float g, float b, float a, float z)
{
    // Basic 2D image drawing - for now just log the call
    printf("Draw2dImage: pos(%.1f,%.1f) size(%.1fx%.1f) tex=%d\n", xpos, ypos, w, h, texture_id);
    // TODO: Implement actual 2D image rendering with Metal
}

void CSimpleMetalRenderer::WriteXY(CXFont* currfont, int x, int y, float xscale, float yscale, float r, float g, float b, float a, const char* message, ...)
{
    assert(!"WriteXY not implemented");
}

void CSimpleMetalRenderer::Draw2dText(float posX, float posY, const char* szText, SDrawTextInfo& info)
{
    assert(!"Draw2dText not implemented");
}

int CSimpleMetalRenderer::GetWidth()
{
    return m_width;
}

int CSimpleMetalRenderer::GetHeight()
{
    return m_height;
}

int CSimpleMetalRenderer::GetColorBpp()
{
    return m_colorBpp;
}

int CSimpleMetalRenderer::GetDepthBpp()
{
    return m_depthBpp;
}

int CSimpleMetalRenderer::GetStencilBpp()
{
    return m_stencilBpp;
}

char CSimpleMetalRenderer::GetType()
{
    return (char)m_type;
}

void CSimpleMetalRenderer::SetType(char type)
{
    printf("SetType called with type=%d\n", (int)type);
    printf("Renderer object: %p\n", this);
    printf("m_type before: %d\n", m_type);
    m_type = (int)type;
    printf("m_type after: %d\n", m_type);
    printf("SetType completed successfully\n");
}

// EF_GetObject implementation
CCObject* CSimpleMetalRenderer::EF_GetObject(bool bTemp, int num)
{
    printf("EF_GetObject called: bTemp=%d, num=%d\n", bTemp, num);
    // Return nullptr for now - CCObject needs proper implementation
    return nullptr;
}

// Simple shader stub class that implements IShader interface
class CSimpleShader : public IShader
{
public:
    CSimpleShader(const char* name) : m_name(name ? name : "Unknown"), m_refCount(1) {}
    
    // IShader interface
    virtual int GetID() { return 1; }
    virtual void AddRef() { m_refCount++; }
    virtual void Release(bool bForce = false) { 
        if (--m_refCount <= 0) {
            printf("CSimpleShader::Release called for %s\n", m_name.c_str());
            delete this;
        }
    }
    virtual int GetRefCount() { return m_refCount; }
    virtual const char* GetName() { return m_name.c_str(); }
    virtual EF_Sort GetSort() { return eS_Opaque; }
    virtual int GetFlags() { return 0; }
    virtual int GetFlags2() { return 0; }
    virtual int GetFlags3() { return 0; }
    virtual int GetRenderFlags() { return 0; }
    virtual void SetRenderFlags(int nFlags) {}
    virtual int GetLFlags() { return 0; }
    virtual int GetCull() { return 0; }
    virtual uint GetPreprocessFlags() { return 0; }
    virtual void SetFlags3(int Flags) {}
    virtual bool Reload(int nFlags) { return true; }
    virtual TArray<CRendElement*>* GetREs() { return nullptr; }
    virtual bool AddTemplate(SRenderShaderResources* Res, int& TemplId, const char* Name = NULL, bool bSetPreferred = false, uint64 nMaskGen = 0) { return false; }
    virtual void RemoveTemplate(int TemplId) {}
    virtual IShader* GetTemplate(int num) { return nullptr; }
    virtual SEfTemplates* GetTemplates() { return nullptr; }
    virtual TArray<SShaderParam>& GetPublicParams() { static TArray<SShaderParam> empty; return empty; }
    virtual int GetTexId() { return 0; }
    virtual ITexPic* GetBaseTexture(int* nPass, int* nTU) { return nullptr; }
    virtual unsigned int GetUsedTextureTypes(void) { return 0; }
    virtual int GetVertexFormat(void) { return 0; }
    virtual int Size(int Flags) { return 0; }
    virtual uint64 GetGenerationMask() { return 0; }
    virtual SShaderGen* GetGenerationParams() { return nullptr; }

private:
    std::string m_name;
    int m_refCount;
};

// EF_LoadShader implementation
IShader* CSimpleMetalRenderer::EF_LoadShader(const char *name, EShClass Class, int flags, uint64 nMaskGen)
{
    printf("EF_LoadShader called: name=%s, Class=%d, flags=%d\n", name ? name : "NULL", Class, flags);
    // Create a proper shader stub that can handle Release() calls
    return new CSimpleShader(name);
}

// Simple texture stub class that implements ITexPic interface
class CSimpleTexture : public ITexPic
{
public:
    CSimpleTexture(const char* name) : m_name(name ? name : "Unknown"), m_refCount(1), m_width(256), m_height(256), m_textureID(1) {}
    
    // ITexPic interface
    virtual void AddRef() { m_refCount++; }
    virtual void Release(int bForce = false) { 
        if (--m_refCount <= 0) {
            printf("CSimpleTexture::Release called for %s\n", m_name.c_str());
            delete this;
        }
    }
    virtual const char* GetName() { return m_name.c_str(); }
    virtual int GetWidth() { return m_width; }
    virtual int GetHeight() { return m_height; }
    virtual int GetOriginalWidth() { return m_width; }
    virtual int GetOriginalHeight() { return m_height; }
    virtual int GetTextureID() { return m_textureID; }
    virtual int GetFlags() { return 0; }
    virtual int GetFlags2() { return 0; }
    virtual void SetClamp(bool bEnable) {}
    virtual bool IsTextureLoaded() { return true; }
    virtual void PrecacheAsynchronously(float fDist, int Flags) {}
    virtual void Preload(int Flags) {}
    virtual byte* GetData32() { return nullptr; }
    virtual bool SetFilter(int nFilter) { return true; }

private:
    std::string m_name;
    int m_refCount;
    int m_width, m_height;
    int m_textureID;
};

// EF_LoadTexture implementation
ITexPic* CSimpleMetalRenderer::EF_LoadTexture(const char* nameTex, uint flags, uint flags2, byte eTT, float fAmount1, float fAmount2, int Id, int BindId)
{
    printf("EF_LoadTexture called: nameTex=%s, flags=%u, eTT=%d\n", nameTex ? nameTex : "NULL", flags, eTT);
    // Create a proper texture stub that can handle Release() calls
    return new CSimpleTexture(nameTex);
}

// DeleteLeafBuffer implementation
void CSimpleMetalRenderer::DeleteLeafBuffer(CLeafBuffer* pLBuffer)
{
    printf("DeleteLeafBuffer called: pLBuffer=%p\n", pLBuffer);
    if (pLBuffer) {
        // In a real implementation, this would properly clean up Metal buffers
        // For now, just log the call - the actual cleanup would happen in the CLeafBuffer destructor
        printf("Deleting leaf buffer: %s\n", pLBuffer->m_sSource ? pLBuffer->m_sSource : "Unknown");
    }
}

// Add more renderer methods that might be called during 3D Engine initialization
void CSimpleMetalRenderer::RemoveTexture(int nTextureId)
{
    printf("RemoveTexture called: nTextureId=%d\n", nTextureId);
}


void CSimpleMetalRenderer::Release()
{
    ShutDown();
}

void CSimpleMetalRenderer::FreeResources(int nFlags)
{
    assert(!"FreeResources not implemented");
}

void CSimpleMetalRenderer::RefreshResources(int nFlags)
{
    assert(!"RefreshResources not implemented");
}

void CSimpleMetalRenderer::PreLoad()
{
    assert(!"PreLoad not implemented");
}

void CSimpleMetalRenderer::PostLoad()
{
    assert(!"PostLoad not implemented");
}

void CSimpleMetalRenderer::ShareResources(CSimpleMetalRenderer* renderer)
{
    assert(!"ShareResources not implemented");
}

void CSimpleMetalRenderer::GetViewport(int* x, int* y, int* width, int* height)
{
    if (x) *x = m_viewportX;
    if (y) *y = m_viewportY;
    if (width) *width = m_viewportWidth;
    if (height) *height = m_viewportHeight;
}

void CSimpleMetalRenderer::MakeCurrent()
{
    assert(!"MakeCurrent not implemented");
}


bool CSimpleMetalRenderer::SetCurrentContext(void* hWnd)
{
    assert(!"SetCurrentContext not implemented");
    return true;
}

bool CSimpleMetalRenderer::CreateContext(void* hWnd, bool bAllowFSAA)
{
    assert(!"CreateContext not implemented");
    return true;
}

bool CSimpleMetalRenderer::DeleteContext(void* hWnd)
{
    assert(!"DeleteContext not implemented");
    return true;
}


bool CSimpleMetalRenderer::ChangeResolution(int nNewWidth, int nNewHeight, int nNewColDepth, int nNewRefreshHZ, bool bFullScreen)
{
    m_width = nNewWidth;
    m_height = nNewHeight;
    m_colorBpp = nNewColDepth;
    return true;
}

bool CSimpleMetalRenderer::InitializeDevice()
{
    m_device = MTLCreateSystemDefaultDevice();
    if (!m_device)
    {
        return false;
    }
    
    return true;
}

bool CSimpleMetalRenderer::InitializeCommandQueue()
{
    if (!m_device)
        return false;
        
    m_commandQueue = [m_device newCommandQueue];
    if (!m_commandQueue)
    {
        return false;
    }
    
    return true;
}

bool CSimpleMetalRenderer::InitializeRenderPipeline()
{
    if (!m_device)
        return false;
        
    // Create a basic render pipeline state
    MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    
    // Set up vertex and fragment shaders (basic triangle for now)
    // TODO: Implement proper shader loading
    pipelineDescriptor.vertexFunction = nil; // Will be set when shaders are loaded
    pipelineDescriptor.fragmentFunction = nil; // Will be set when shaders are loaded
    
    // Set up vertex descriptor
    MTLVertexDescriptor* vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.layouts[0].stride = 12; // 3 floats * 4 bytes
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;
    
    // Set up color attachment
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    // Set up depth attachment
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    
    NSError* error = nil;
    m_currentPipelineState = [m_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!m_currentPipelineState)
    {
        return false;
    }
    
    return true;
}

MTLPixelFormat CSimpleMetalRenderer::ConvertToMetalFormat(int format)
{
    assert(!"ConvertToMetalFormat not implemented");
    return MTLPixelFormatBGRA8Unorm;
}

MTLPrimitiveType CSimpleMetalRenderer::ConvertToMetalPrimitive(int type)
{
    assert(!"ConvertToMetalPrimitive not implemented");
    return MTLPrimitiveTypeTriangle;
}

// Essential methods used by the game
void CSimpleMetalRenderer::Set2DMode(bool enable, int ortox, int ortoy)
{
    m_2DMode = enable;
    if (enable) {
        // Use provided dimensions, or fall back to renderer dimensions if 0
        m_2DWidth = (ortox > 0) ? ortox : m_width;
        m_2DHeight = (ortoy > 0) ? ortoy : m_height;
    }
    // TODO: Set up 2D projection matrix for Metal
}

void CSimpleMetalRenderer::SetState(int st)
{
    m_currentState = st;
    // TODO: Apply render state to Metal pipeline
}

void CSimpleMetalRenderer::TextToScreen(float x, float y, const char* format, ...)
{
    // TODO: Implement text rendering to screen
    // For now, just log the text
    va_list args;
    va_start(args, format);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    printf("TextToScreen: %s\n", buffer);
}

void CSimpleMetalRenderer::TextToScreenColor(int x, int y, float r, float g, float b, float a, const char* format, ...)
{
    // TODO: Implement colored text rendering to screen
    // For now, just log the text
    va_list args;
    va_start(args, format);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    printf("TextToScreenColor: %s\n", buffer);
}

int CSimpleMetalRenderer::GetFrameID(bool bIncludeRecursiveCalls)
{
    return m_frameID;
}


// Create a simple renderer that can be cast to IRenderer
IRenderer* CreateSimpleRenderer(int argc, char* argv[], SCryRenderInterface* sp)
{
    FILE* f = fopen("/tmp/farcry_create.log", "w");
    if (f) {
        fprintf(f, "CreateSimpleRenderer called\n");
        fflush(f);
        fclose(f);
    }
    
    printf("CreateSimpleRenderer called\n");
    CSimpleMetalRenderer* renderer = new CSimpleMetalRenderer();
    printf("CreateSimpleRenderer created renderer=%p\n", renderer);
    
    f = fopen("/tmp/farcry_create_done.log", "w");
    if (f) {
        fprintf(f, "CreateSimpleRenderer done: renderer=%p\n", renderer);
        fflush(f);
        fclose(f);
    }
    
    return (IRenderer*)renderer;
}

// Test function with minimal signature
extern "C" void* TestFunction(int a, void* b, void* c)
{
    FILE* f = fopen("/tmp/farcry_test.log", "w");
    if (f) {
        fprintf(f, "TestFunction called: a=%d, b=%p, c=%p\n", a, b, c);
        fclose(f);
    }
    return nullptr;
}

// Test function with different signature
extern "C" DLL_EXPORT void* TestPackageRenderConstructor()
{
    FILE* f = fopen("/tmp/farcry_test.log", "w");
    if (f) {
        fprintf(f, "TestPackageRenderConstructor called successfully\n");
        fclose(f);
    }
    return nullptr;
}

// Add a constructor attribute to ensure initialization
__attribute__((constructor))
static void InitializeRenderer() {
    FILE* f = fopen("/tmp/farcry_init.log", "w");
    if (f) {
        fprintf(f, "Metal renderer library initialized\n");
        fflush(f);
        fclose(f);
    }
}

// Export the function that the system expects
extern "C" DLL_EXPORT IRenderer* PackageRenderConstructor(int argc, char* argv[], SCryRenderInterface *sp)
{
    // Write to file to confirm function is called
    FILE* f = fopen("/tmp/farcry_render_constructor.log", "w");
    if (f) {
        fprintf(f, "PackageRenderConstructor called successfully\n");
        fprintf(f, "argc=%d, argv=%p, sp=%p\n", argc, argv, sp);
        fflush(f);
        fclose(f);
    }
    
    // Create and return the renderer
    IRenderer* renderer = CreateSimpleRenderer(argc, argv, sp);
    
    f = fopen("/tmp/farcry_render_created.log", "w");
    if (f) {
        fprintf(f, "Renderer created: %p\n", renderer);
        fflush(f);
        fclose(f);
    }
    
    return renderer;
}

// Force the function to be exported by referencing it
IRenderer* (*g_PackageRenderConstructor)(int, char*[], SCryRenderInterface*) = PackageRenderConstructor;

// Missing implementation for EnumDisplayFormats
int CSimpleMetalRenderer::EnumDisplayFormats(TArray<SDispFormat>& Formats, bool bReset)
{
    // TODO: Implement display format enumeration
    printf("EnumDisplayFormats called\n");
    return 0;
}

// Implementation for FlushTextMessages
void CSimpleMetalRenderer::FlushTextMessages()
{
    // TODO: Implement text message flushing
}


// Implementation for EF_GetTextureByID
ITexPic* CSimpleMetalRenderer::EF_GetTextureByID(int texture_id)
{
    // TODO: Implement texture retrieval by ID
    return nullptr;
}
