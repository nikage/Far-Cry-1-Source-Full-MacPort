#ifndef SIMPLE_STUB_RENDERER_H
#define SIMPLE_STUB_RENDERER_H

#if defined(__APPLE__) && defined(__MACH__)

#include <Metal/Metal.h>
#include <MetalKit/MetalKit.h>
#include <QuartzCore/CAMetalLayer.h>
#include <Cocoa/Cocoa.h>
#include <vector>
#include <cassert>

// Forward declarations for CryEngine types
struct SCryRenderInterface;
struct Vec3 { float x, y, z; Vec3() : x(0), y(0), z(0) {} Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {} };

// Forward declaration of IRenderer interface
class IRenderer;

// Simple stub renderer that provides minimal functionality
class CSimpleStubRenderer
{
public:
    CSimpleStubRenderer();
    virtual ~CSimpleStubRenderer();

    // Essential methods that the game actually calls
    virtual void* Init(int x, int y, int width, int height, unsigned int cbpp, int zbpp, int sbits, bool fullscreen, void* hinst, void* hWnd, void* hdc = 0, void* hglrc = 0, bool bReInit = false);
    virtual void ShutDown(bool bReInit = false);
    virtual void BeginFrame();
    virtual void Update();
    virtual void Set2DMode(bool enable, int ortox, int ortoy);
    virtual void SetState(int st);
    virtual void Draw2dImage(float xpos, float ypos, float w, float h, int texture_id, float s0 = 0, float t0 = 0, float s1 = 1, float t1 = 1, float angle = 0, float r = 1, float g = 1, float b = 1, float a = 1, float z = 1);
    virtual void SetTexture(int tnum, int Type = 0);
    virtual void TextToScreen(float x, float y, const char* format, ...);
    virtual void TextToScreenColor(int x, int y, float r, float g, float b, float a, const char* format, ...);
    virtual int GetWidth();
    virtual int GetHeight();
    virtual int GetFrameID();
    virtual void Release();
    virtual void SetType(char type);

private:
    int m_width;
    int m_height;
    int m_frameID;
    bool m_isInitialized;
};

#endif // __APPLE__ && __MACH__

#endif // SIMPLE_STUB_RENDERER_H
