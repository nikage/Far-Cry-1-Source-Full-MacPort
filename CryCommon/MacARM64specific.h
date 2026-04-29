////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacARM64specific.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for ARM64
//  Description: Specific to macOS ARM64 (Apple Silicon) declarations
//               ARM64 architecture optimizations and compatibility
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////
#ifndef _CRY_COMMON_MAC_ARM64_SPECIFIC_HDR_
#define _CRY_COMMON_MAC_ARM64_SPECIFIC_HDR_

#include "MacOSspecific.h"
#include <arm_neon.h>

#ifdef __cplusplus
extern "C" {
#endif

// ARM64-specific optimizations and intrinsics

// CPU feature detection
#define CPUF_NEON     1    // ARM NEON SIMD
#define CPUF_ARM64    2    // ARM64 architecture
#define CPUF_APPLE_M  4    // Apple Silicon M-series

// High-resolution timer for ARM64
#ifdef __cplusplus
inline int64 GetTicks()
{
    // Use mach_absolute_time() for high-precision timing on macOS
    return (int64)mach_absolute_time();
}
#else
static int64 GetTicks()
{
    return (int64)mach_absolute_time();
}
#endif

// Memory barrier for ARM64
#define MEMORY_BARRIER() __dmb(0xB)  // Data Memory Barrier

// ARM64 cache line size (typically 64 bytes on Apple Silicon)
#define CACHE_LINE_SIZE 64

// ARM64-specific alignment
#define ARM64_CACHE_ALIGN __attribute__((aligned(CACHE_LINE_SIZE)))

// SIMD type definitions for ARM64 NEON
typedef float32x4_t     neon_f32x4;
typedef int32x4_t       neon_i32x4;
typedef uint32x4_t      neon_u32x4;

#ifdef __cplusplus
}
#endif

#endif //_CRY_COMMON_MAC_ARM64_SPECIFIC_HDR_
