////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSspecific.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM
//  Description: Specific to macOS declarations, inline functions etc.
//               Provides cross-platform compatibility layer
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////
#ifndef _CRY_COMMON_MACOS_SPECIFIC_HDR_
#define _CRY_COMMON_MACOS_SPECIFIC_HDR_

#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>
#include <unistd.h>
#include <pthread.h>
#include <mach/mach_time.h>

#ifdef __cplusplus
extern "C" {
#endif

// Type definitions matching Windows types
typedef int8_t          int8;
typedef int16_t         int16;
typedef int32_t         int32;
typedef int64_t         int64;
typedef uint8_t         uint8;
typedef uint16_t        uint16;
typedef uint32_t        uint32;
typedef uint64_t        uint64;

typedef float           f32;
typedef double          f64;

// Old-style (compatible with existing code)
typedef int8_t          s8;
typedef int16_t         s16;
typedef int32_t         s32;
typedef int64_t         s64;
typedef uint8_t         u8;
typedef uint16_t        u16;
typedef uint32_t        u32;
typedef uint64_t        u64;

// Windows compatibility types (avoid conflicts with system headers)
typedef void*           THREAD_HANDLE;
typedef void*           EVENT_HANDLE;
// typedef int32_t         BOOL;  // Commented out to avoid conflict with objc BOOL
typedef uint32_t        DWORD;
typedef int32_t         LONG;
typedef void*           HMODULE;
typedef void*           HINSTANCE;
typedef void*           HWND;
typedef void*           HDC;
typedef void*           HGLRC;

// Boolean values
#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

// Memory debugging function for debug builds (renamed to avoid Carbon conflict)
#ifdef __cplusplus
inline int CryIsHeapValid()
{
#ifdef _DEBUG
    // On macOS, we can use malloc_zone_check_all for heap validation
    // For now, just return true - can be enhanced with actual validation
    return true;
#else
    return true;
#endif
}

// Note: IsHeapValid macro removed to avoid conflict with Carbon framework
#endif

#ifdef __cplusplus
}
#endif

#endif //_CRY_COMMON_MACOS_SPECIFIC_HDR_
