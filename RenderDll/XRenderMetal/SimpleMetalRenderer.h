#ifndef SIMPLE_METAL_RENDERER_H
#define SIMPLE_METAL_RENDERER_H

#if defined(__APPLE__) && defined(__MACH__)

#include <Metal/Metal.h>
#include <MetalKit/MetalKit.h>
#include <QuartzCore/CAMetalLayer.h>
#include <Cocoa/Cocoa.h>
#include <vector>
#include <cassert>

// Forward declarations for CryEngine types

// Forward declarations for CryEngine types
struct SCryRenderInterface;
class CCamera;
class CVertexBuffer;
class SVertexStream;
class CMatInfo;
class CXFont;
struct SDrawTextInfo;
struct SDispFormat;
class ICrySizer;

// Simple Vec3 definition for Metal renderer
struct Vec3 { 
    float x, y, z; 
    Vec3() : x(0), y(0), z(0) {}
    Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}
};

// Simple Metal renderer that provides essential rendering functionality
class CSimpleMetalRenderer
{
public:
    CSimpleMetalRenderer();
    virtual ~CSimpleMetalRenderer();

    // Essential IRenderer interface methods
    virtual void* Init(int x, int y, int width, int height, unsigned int cbpp, int zbpp, int sbits, bool fullscreen, void* hinst, void* hWnd, void* hdc = 0, void* hglrc = 0, bool bReInit = false);
    virtual void ShutDown(bool bReInit = false);
    virtual void BeginFrame();
    virtual void Update();
    virtual void SetViewport(int x = 0, int y = 0, int width = 0, int height = 0);
    virtual void SetScissor(int x = 0, int y = 0, int width = 0, int height = 0);
    virtual void SetCamera(const CCamera& cam);
    virtual const CCamera& GetCamera();
    virtual void SetTexture(int tnum, int Type = 0);
    virtual void SetWhiteTexture();
    
    // Additional IRenderer methods
    virtual bool SetCurrentContext(void* hWnd);
    virtual bool CreateContext(void* hWnd, bool bAllowFSAA = false);
    virtual bool DeleteContext(void* hWnd);
    virtual int EnumDisplayFormats(void* Formats, bool bReset);
    virtual bool ChangeResolution(int nNewWidth, int nNewHeight, int nNewColDepth, int nNewRefreshHZ, bool bFullScreen);
    virtual void Release();
    virtual void FreeResources(int nFlags);
    virtual void RefreshResources(int nFlags);
    virtual void PreLoad();
    virtual void PostLoad();
    virtual void GetViewport(int* x, int* y, int* width, int* height);
    virtual void MakeCurrent();
    virtual void DrawTriStrip(CVertexBuffer* src, int vert_num = 4);
    virtual void DrawBuffer(CVertexBuffer* src, SVertexStream* indices, int numindices, int offsindex, int prmode, int vert_start = 0, int vert_stop = 0, CMatInfo* mi = NULL);
    virtual void Draw3dBBox(const Vec3& mins, const Vec3& maxs, int nPrimType = 0);
    virtual void Draw2dImage(float xpos, float ypos, float w, float h, int texture_id, float s0 = 0, float t0 = 0, float s1 = 1, float t1 = 1, float angle = 0, float r = 1, float g = 1, float b = 1, float a = 1, float z = 1);
    virtual void WriteXY(CXFont* currfont, int x, int y, float xscale, float yscale, float r, float g, float b, float a, const char* message, ...);
    virtual void Draw2dText(float posX, float posY, const char* szText, SDrawTextInfo& info);
    virtual int GetWidth();
    virtual int GetHeight();
    
    // Essential methods used by the game
    virtual void Set2DMode(bool enable, int ortox, int ortoy);
    virtual void SetState(int st);
    virtual void TextToScreen(float x, float y, const char* format, ...);
    virtual void TextToScreenColor(int x, int y, float r, float g, float b, float a, const char* format, ...);
    virtual int GetFrameID();
    virtual int GetColorBpp();
    virtual int GetDepthBpp();
    virtual int GetStencilBpp();
    virtual int GetType();
    virtual void SetType(int type);
    virtual void ShareResources(CSimpleMetalRenderer* renderer);

private:
    // Metal-specific members
    id<MTLDevice> m_device;
    id<MTLCommandQueue> m_commandQueue;
    id<MTLRenderCommandEncoder> m_renderEncoder;
    MTKView* m_metalView;
    CAMetalLayer* m_metalLayer;
    id<MTLCommandBuffer> m_currentCommandBuffer;
    id<MTLRenderPipelineState> m_currentPipelineState;
    id<MTLDepthStencilState> m_currentDepthStencilState;
    
    // Renderer state
    int m_width;
    int m_height;
    int m_colorBpp;
    int m_depthBpp;
    int m_stencilBpp;
    int m_type;
    bool m_isInitialized;
    
    // Viewport state
    int m_viewportX, m_viewportY, m_viewportWidth, m_viewportHeight;
    
    // Camera
    CCamera* m_camera;
    
    // 2D mode state
    bool m_2DMode;
    int m_2DWidth, m_2DHeight;
    
    // Frame tracking
    int m_frameID;
    
    // Current render state
    int m_currentState;
    
    // Helper methods
    bool InitializeDevice();
    bool InitializeCommandQueue();
    bool InitializeRenderPipeline();
    MTLPixelFormat ConvertToMetalFormat(int format);
    MTLPrimitiveType ConvertToMetalPrimitive(int type);
};


#endif // __APPLE__ && __MACH__

#endif // SIMPLE_METAL_RENDERER_H