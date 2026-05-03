#if defined(__APPLE__) && defined(__MACH__)

// platform_macos.h (force-included by CMake) defines BOOL as int,
// which conflicts with CoreGraphics's typedef signed char BOOL.
// Reset it here before importing the system framework.
#ifdef BOOL
#undef BOOL
#endif
#import <CoreGraphics/CoreGraphics.h>
#include <algorithm>

extern "C" {

void MacOS_GetMouseVScreenXY(float screenW, float screenH, float* outVX, float* outVY)
{
    CGEventRef ev = CGEventCreate(NULL);
    CGPoint pt = CGEventGetLocation(ev);
    CFRelease(ev);

    if (screenW > 0 && screenH > 0) {
        float vx = (float)pt.x / screenW * 800.f;
        float vy = (float)pt.y / screenH * 600.f;
        *outVX = vx < 0.f ? 0.f : (vx > 800.f ? 800.f : vx);
        *outVY = vy < 0.f ? 0.f : (vy > 600.f ? 600.f : vy);
    }
}

void MacOS_GetMouseButtons(int* left, int* right, int* middle)
{
    *left   = CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft)   ? 1 : 0;
    *right  = CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonRight)  ? 1 : 0;
    *middle = CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonCenter) ? 1 : 0;
}

void MacOS_GetScreenDimensions(float* outW, float* outH)
{
    *outW = (float)CGDisplayPixelsWide(CGMainDisplayID());
    *outH = (float)CGDisplayPixelsHigh(CGMainDisplayID());
}

void MacOS_SetSystemCursorVisible(int visible)
{
    if (visible)
        CGDisplayShowCursor(kCGNullDirectDisplay);
    else
        CGDisplayHideCursor(kCGNullDirectDisplay);
}

int MacOS_IsKeyDown(unsigned short hidKeyCode)
{
    return CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, hidKeyCode) ? 1 : 0;
}

void MacOS_GetRawMouseDelta(float* outDX, float* outDY)
{
    int32_t dx = 0, dy = 0;
    CGGetLastMouseDelta(&dx, &dy);
    *outDX = (float)dx;
    *outDY = (float)dy;
}

void MacOS_ConfineCursorToRect(float x, float y, float w, float h)
{
    CGEventRef ev = CGEventCreate(NULL);
    CGPoint pt = CGEventGetLocation(ev);
    CFRelease(ev);

    float nx = pt.x < x ? x : (pt.x > x + w ? x + w : pt.x);
    float ny = pt.y < y ? y : (pt.y > y + h ? y + h : pt.y);
    if (nx != pt.x || ny != pt.y)
        CGWarpMouseCursorPosition(CGPointMake(nx, ny));
}

void MacOS_ReleaseCursorConfinement(void)
{
}

}

#endif // __APPLE__ && __MACH__
