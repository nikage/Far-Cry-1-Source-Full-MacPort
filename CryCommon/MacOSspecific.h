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
// Define BOOL before any system headers are included
#define BOOL int
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

// Windows compatibility macros
#define ILINE inline
#define APIENTRY
#define WINAPI
#define _ACCESS_POOL   // Empty macro for macOS
#define __forceinline inline

// Windows API compatibility
#define GetProcAddress(hModule, lpProcName) dlsym(hModule, lpProcName)
#define HINSTANCE void*

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

// Additional math functions
inline float cry_fmod(float x, float y) { return fmodf(x, y); }
inline double cry_fmod(double x, double y) { return fmod(x, y); }

// Windows min/max macros
#define __min(a,b) ((a) < (b) ? (a) : (b))
#define __max(a,b) ((a) > (b) ? (a) : (b))

// Additional missing functions
inline float cry_powf(float base, float exp) { return powf(base, exp); }
inline double cry_pow(double base, double exp) { return pow(base, exp); }

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

// Plane utility function  
template<class F>
struct Plane_tpl;

template<class F>
Plane_tpl<F> GetPlane(const Vec3_tpl<F>& normal, const Vec3_tpl<F>& point);

// Quaternion from matrix conversion
template<class F,int SI,int SJ> 
Quaternion_tpl<F> GetQuatFromMat33(const Matrix33_tpl<F,SI,SJ>& m);
#endif
#endif

#endif //_CRY_COMMON_MACOS_SPECIFIC_HDR_
