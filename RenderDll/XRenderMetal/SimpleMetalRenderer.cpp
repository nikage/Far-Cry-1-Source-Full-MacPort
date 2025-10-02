#include "SimpleMetalRenderer.h"
#include "IRenderer.h"
#include <Cocoa/Cocoa.h>
#include <cstdarg>
#include <cstdio>

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

void CSimpleMetalRenderer::SetTexture(int tnum, int Type)
{
    // Basic texture binding - for now just log the call
    printf("SetTexture: tex=%d type=%d\n", tnum, Type);
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

int CSimpleMetalRenderer::GetType()
{
    return m_type;
}

void CSimpleMetalRenderer::SetType(int type)
{
    m_type = type;
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

int CSimpleMetalRenderer::GetFrameID()
{
    return m_frameID;
}


// Create a simple renderer that can be cast to IRenderer
void* CreateSimpleRenderer(int argc, char* argv[], SCryRenderInterface* sp)
{
    CSimpleMetalRenderer* renderer = new CSimpleMetalRenderer();
    return (void*)renderer;
}

// Export the function that the system expects
extern "C" {
    __attribute__((visibility("default")))
    IRenderer* PackageRenderConstructor(int argc, char* argv[], SCryRenderInterface* sp)
    {
        return (IRenderer*)CreateSimpleRenderer(argc, argv, sp);
    }
}

// Force the function to be exported by referencing it
IRenderer* (*g_PackageRenderConstructor)(int, char*[], SCryRenderInterface*) = PackageRenderConstructor;

// Missing implementation for EnumDisplayFormats
int CSimpleMetalRenderer::EnumDisplayFormats(void* Formats, bool bReset)
{
    // TODO: Implement display format enumeration
    printf("EnumDisplayFormats called\n");
    return 0;
}
