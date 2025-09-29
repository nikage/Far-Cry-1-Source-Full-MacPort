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
#include <mach-o/dyld.h>  // for _NSGetExecutablePath
#include <string.h>       // for string functions
#include <stdio.h>        // for FILE type

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
// Define BOOL before any system headers are included
#define BOOL int
#ifndef DWORD
typedef uint32_t        DWORD;
#endif
typedef int32_t         LONG;
typedef uint32_t        HRESULT;  // COM HRESULT type
typedef void*           HMODULE;
typedef void*           HINSTANCE;
typedef void*           HWND;
typedef void*           HDC;
typedef void*           HGLRC;
typedef void*           LPVOID;
typedef char*           LPSTR;
typedef uint8_t         BYTE;
typedef uint16_t        WORD;
typedef uintptr_t       WPARAM;
typedef intptr_t        LPARAM;
typedef intptr_t        LRESULT;
#define CALLBACK        // Empty macro for macOS

// Windows message constants (stubs for macOS)
#define WM_MOVE             0x0003
#define WM_SIZE             0x0005  
#define WM_ACTIVATE         0x0006
#define WM_DISPLAYCHANGE    0x007E
#define WM_ACTIVATEAPP      0x001C
#define WM_MOUSEACTIVATE    0x0021
#define WM_ENTERSIZEMOVE    0x0231
#define WM_ENTERMENULOOP    0x0211
#define SIZE_MAXHIDE       4
#define SIZE_MINIMIZED     1
#define MA_ACTIVATEANDEAT   2
#define WA_INACTIVE        0
#define WA_ACTIVE          1
#define WA_CLICKACTIVE     2

// Windows utility macros
#define LOWORD(l) ((uint16_t)(((uintptr_t)(l)) & 0xffff))
#define HIWORD(l) ((uint16_t)((((uintptr_t)(l)) >> 16) & 0xffff))

// Rectangle structure
typedef struct tagRECT {
    int32_t left;
    int32_t top;
    int32_t right;
    int32_t bottom;
} RECT;

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

// Windows compatibility macros
#define ILINE inline
#define _inline inline
#define APIENTRY
#define WINAPI
#define _ACCESS_POOL   // Empty macro for macOS
#define __forceinline inline
#define __declspec(x)  // Empty macro for macOS - ignore Windows DLL specifications

// Windows API compatibility
#define GetProcAddress(hModule, lpProcName) dlsym(hModule, lpProcName)
#define HINSTANCE void*

// Windows file/module API compatibility
inline void* GetModuleHandle(void* lpModuleName) { 
    // For main executable, return a dummy handle
    return (void*)1; 
}

inline uint32_t GetModuleFileName(void* hModule, char* lpFilename, uint32_t nSize) {
    // Get the executable path on macOS
    uint32_t size = nSize;
    if (_NSGetExecutablePath(lpFilename, &size) == 0) {
        return strlen(lpFilename);
    }
    return 0;
}

// Path manipulation functions (Windows compatibility)
inline void _splitpath(const char* path, char* drive, char* dir, char* fname, char* ext) {
    // macOS doesn't have drive letters, so drive is always empty
    if (drive) drive[0] = '\0';
    
    const char* last_slash = strrchr(path, '/');
    const char* last_dot = strrchr(path, '.');
    
    // Extract directory
    if (dir) {
        if (last_slash) {
            size_t dir_len = last_slash - path + 1;
            strncpy(dir, path, dir_len);
            dir[dir_len] = '\0';
        } else {
            strcpy(dir, "./");
        }
    }
    
    // Extract filename and extension
    const char* name_start = last_slash ? last_slash + 1 : path;
    
    if (fname) {
        if (last_dot && last_dot > name_start) {
            size_t name_len = last_dot - name_start;
            strncpy(fname, name_start, name_len);
            fname[name_len] = '\0';
        } else {
            strcpy(fname, name_start);
        }
    }
    
    if (ext && last_dot && last_dot > name_start) {
        strcpy(ext, last_dot);
    } else if (ext) {
        ext[0] = '\0';
    }
}

inline void _makepath(char* path, const char* drive, const char* dir, const char* fname, const char* ext) {
    // Ignore drive on macOS
    path[0] = '\0';
    
    if (dir && dir[0]) {
        strcat(path, dir);
    }
    
    if (fname && fname[0]) {
        strcat(path, fname);
    }
    
    if (ext && ext[0]) {
        strcat(path, ext);
    }
}

inline int SetCurrentDirectory(const char* lpPathName) {
    return chdir(lpPathName) == 0 ? 1 : 0;
}

inline uint32_t GetCurrentDirectory(uint32_t nBufferLength, char* lpBuffer) {
    if (getcwd(lpBuffer, nBufferLength) != NULL) {
        return strlen(lpBuffer);
    }
    return 0;
}

// Windows GUI API stubs (not functional on macOS)
inline void* FindWindow(const char* lpClassName, const char* lpWindowName) {
    return NULL;  // No equivalent on macOS console app
}

inline int SetForegroundWindow(void* hWnd) {
    return 0;  // Stub - no equivalent for console app
}

inline int GetClientRect(void* hWnd, RECT* lpRect) {
    // Stub implementation - return a default rectangle
    if (lpRect) {
        lpRect->left = 0;
        lpRect->top = 0;
        lpRect->right = 800;  // Default width
        lpRect->bottom = 600; // Default height
    }
    return 1;
}

// Math functions compatibility
#include <math.h>
inline void cry_sincos(double angle, double* pCosSin) 
{
    pCosSin[0] = cos(angle);
    pCosSin[1] = sin(angle);
}

inline void cry_sincosf(float angle, float* pCosSin)
{
    pCosSin[0] = cosf(angle);
    pCosSin[1] = sinf(angle);
}

inline float cry_cosf(float op) { return cosf(op); }
inline float cry_sinf(float op) { return sinf(op); }
inline float cry_acosf(float op) { return acosf(op); }
inline float cry_asinf(float op) { return asinf(op); }
inline float cry_atanf(float op) { return atanf(op); }
inline float cry_atan2f(float y, float x) { return atan2f(y, x); }
inline float cry_expf(float op) { return expf(op); }
inline float cry_logf(float op) { return logf(op); }
inline float cry_sqrtf(float op) { return sqrtf(op); }
inline float cry_fabsf(float op) { return fabsf(op); }
inline float cry_floorf(float op) { return floorf(op); }
inline float cry_ceilf(float op) { return ceilf(op); }
inline float cry_tanf(float op) { return tanf(op); }

// Handle declaration
typedef void* HANDLE;

// Missing Windows types
typedef intptr_t INT_PTR;
typedef uintptr_t UINT_PTR;
typedef uintptr_t DWORD_PTR;

// Additional math functions - use function overloading properly
inline float cry_fmodf(float x, float y) { return fmodf(x, y); }
inline double cry_fmod(double x, double y) { return fmod(x, y); }

// Windows min/max macros
#define __min(a,b) ((a) < (b) ? (a) : (b))
#define __max(a,b) ((a) > (b) ? (a) : (b))

// Additional missing functions
inline float cry_powf(float base, float exp) { return powf(base, exp); }
inline double cry_pow(double base, double exp) { return pow(base, exp); }

// File operations - macOS doesn't use CryPak by default
#ifndef FXOPEN_DEFINED
#define FXOPEN_DEFINED
inline FILE* fxopen(const char* file, const char* mode) { return fopen(file, mode); }
inline void fxclose(FILE* f) { fclose(f); }
#endif

// String comparison functions
#define stricmp strcasecmp
#define strnicmp strncasecmp
#define _stricmp strcasecmp
#define _strnicmp strncasecmp

// Path constants
#define _MAX_PATH 1024
#define MAX_PATH 1024
#define _MAX_DRIVE 3
#define _MAX_DIR 256
#define _MAX_FNAME 256
#define _MAX_EXT 256

// Atomic operations for multi-threading
inline long InterlockedIncrement(volatile long* target) {
    return __sync_add_and_fetch(target, 1);
}

inline long InterlockedDecrement(volatile long* target) {
    return __sync_sub_and_fetch(target, 1);
}

// For int variant used on Linux
inline int InterlockedIncrement(volatile int* target) {
    return __sync_add_and_fetch(target, 1);
}

inline int InterlockedDecrement(volatile int* target) {
    return __sync_sub_and_fetch(target, 1);
}

// SSE intrinsics compatibility
#if defined(__aarch64__) || defined(__arm64__)
// ARM64 doesn't have SSE, but we can define these for compatibility
#define _MM_HINT_NTA 0
inline void _mm_prefetch(const char* p, int i) { __builtin_prefetch(p, 0, 0); }
#else
// Intel Mac
#include <xmmintrin.h>
#ifndef _MM_HINT_NTA
#define _MM_HINT_NTA _MM_HINT_T0
#endif
#endif

#endif

#ifdef __cplusplus
}

// Forward declarations for CryEngine math functions (defined in headers)
template <class F> struct Vec3_tpl;
template <class F> struct Quaternion_tpl;
template <class F, int SI, int SJ> struct Matrix33_tpl;

// These will be properly defined when the math headers are included
template<class F> 
F GetLengthSquared( const Vec3_tpl<F> &v );
template<class F> 
F GetLength( const Vec3_tpl<F>& v );

// Quaternion from matrix conversion
template<class F,int SI,int SJ> 
Quaternion_tpl<F> GetQuatFromMat33(const Matrix33_tpl<F,SI,SJ>& m);
#endif

#endif //_CRY_COMMON_MACOS_SPECIFIC_HDR_
