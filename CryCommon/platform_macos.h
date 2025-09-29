////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   platform_macos.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Clean macOS platform header without legacy complications
// -------------------------------------------------------------------------

#ifndef _PLATFORM_MACOS_H_
#define _PLATFORM_MACOS_H_

#include "ProjectDefines.h"

#if _MSC_VER > 1000
#pragma once
#endif

// Thread and event handles
typedef void *THREAD_HANDLE;
typedef void *EVENT_HANDLE;

// Debug break for ARM64
#if defined(__aarch64__) || defined(__arm64__)
    #define DEBUG_BREAK __builtin_debugtrap()
    #define _CPU_ARM64
    #include "MacARM64specific.h"
#else
    #define DEBUG_BREAK __builtin_trap()
    #define _CPU_X86_64
    #include "MacOSspecific.h"
#endif

#define RC_EXECUTABLE "rc_mac"

#include "stdio.h"

// CPU feature definitions
#define CPUF_SSE   1
#define CPUF_SSE2  2
#define CPUF_3DNOW 4
#define CPUF_MMX   8

// 32/64 Bit versions
#define SIGN_MASK(x) ((intptr_t)(x) >> ((sizeof(size_t)*8)-1))

// Structure alignment macros
#define DEFINE_ALIGNED_DATA( type, name, alignment ) type name __attribute__ ((aligned(alignment)));
#define DEFINE_ALIGNED_DATA_STATIC( type, name, alignment ) static type name __attribute__ ((aligned(alignment)));
#define DEFINE_ALIGNED_DATA_CONST( type, name, alignment ) const type name __attribute__ ((aligned(alignment)));

// Common typedefs
typedef double real;
typedef int index_t;
typedef int                 INT;
typedef unsigned int        UINT;
typedef unsigned int        *PUINT;

// High-resolution timer is defined in MacARM64specific.h or MacOSspecific.h

#ifdef __cplusplus
// Standard C++ strings for macOS
#include <string>
#include <iostream>
#include <vector>
#include <map>

typedef std::string string;
typedef std::wstring wstring;

#endif // __cplusplus

#endif // _PLATFORM_MACOS_H_
