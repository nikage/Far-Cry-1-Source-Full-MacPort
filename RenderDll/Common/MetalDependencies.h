////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalDependencies.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Missing Windows dependencies for Metal renderer on macOS
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_DEPENDENCIES_H
#define METAL_DEPENDENCIES_H

#if defined(__APPLE__) && defined(__MACH__)

// Windows-specific types that are missing on macOS
typedef int HRESULT;
typedef unsigned long DWORD;
typedef unsigned char BYTE;
typedef unsigned short WORD;
typedef unsigned int UINT;
typedef int BOOL;
typedef void* HANDLE;
typedef void* HINSTANCE;
typedef void* HWND;
typedef void* HDC;
typedef void* HGLRC;

// Windows calling conventions
#define __stdcall
#define __cdecl
#define __fastcall
#define __thiscall

// Windows macros
#define _inline inline
#define _inline inline
#define __forceinline inline
#define __declspec(x)
#define DLL_IMPORT
#define DLL_EXPORT

// Windows-specific constants
#define TRUE 1
#define FALSE 0
#define NULL 0

// Missing assert function
#include <cassert>
#ifdef NDEBUG
  // In release builds use the standard no-op
#else
  // In debug builds: redefine assert to use __builtin_trap so that the
  // debugger breaks on the exact failing line rather than aborting silently.
  #undef assert
  #define assert(x) \
    do { if (!(x)) { __builtin_trap(); } } while (0)
#endif

// Vec3 is already defined in CryEngine, no need to redefine

// Missing SRenderPipeline type - forward declaration
struct SRenderPipeline {
    // Add minimal implementation
    int m_FlagsPerFlush;
    void* m_pRE;
    void* m_pCurLightIndices;
    void* m_pCurLight;
    int m_NumActiveDLights;
    // Add other members as needed
    SRenderPipeline() : m_FlagsPerFlush(0), m_pRE(nullptr), m_pCurLightIndices(nullptr), m_pCurLight(nullptr), m_NumActiveDLights(0) {}
};

// Missing CCamera type - forward declaration
class CCamera {
public:
    // Add minimal implementation
    CCamera() {}
    virtual ~CCamera() {}
};

// Missing CShader type - forward declaration
class CShader {
public:
    // Add minimal implementation
    CShader() {}
    virtual ~CShader() {}
};

// Missing SRendItem class
class SRendItem {
public:
    static int m_RecurseLevel;
    static void* mfGetPointerCommon(int ePT, int Stride, int Type, void* Dst, int Flags) {
        return nullptr;
    }
};

// Missing Windows-specific structures
struct PIXELFORMATDESCRIPTOR {
    WORD nSize;
    WORD nVersion;
    DWORD dwFlags;
    BYTE iPixelType;
    BYTE cColorBits;
    BYTE cRedBits;
    BYTE cRedShift;
    BYTE cGreenBits;
    BYTE cGreenShift;
    BYTE cBlueBits;
    BYTE cBlueShift;
    BYTE cAlphaBits;
    BYTE cAlphaShift;
    BYTE cAccumBits;
    BYTE cAccumRedBits;
    BYTE cAccumGreenBits;
    BYTE cAccumBlueBits;
    BYTE cAccumAlphaBits;
    BYTE cDepthBits;
    BYTE cStencilBits;
    BYTE cAuxBuffers;
    BYTE iLayerType;
    BYTE bReserved;
    DWORD dwLayerMask;
    DWORD dwVisibleMask;
    DWORD dwDamageMask;
};

// Missing Windows-specific function pointers
typedef void* PROC;
typedef void* CONST;

// Missing Windows-specific constants
#define RBSI_GLOBALRGB 0x01
#define RBSI_GLOBALALPHA 0x02

#endif // __APPLE__

#endif // METAL_DEPENDENCIES_H
