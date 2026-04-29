////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Cross Platform
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   platform.h
//  Version:     v1.00
//  Created:     29/09/2025 by Cross Platform Team.
//  Compilers:   MSVC, GCC, Clang
//  Description: Cross-platform header that detects platform and includes appropriate headers
// -------------------------------------------------------------------------

#ifndef _PLATFORM_H_
#define _PLATFORM_H_

// Disable the custom memory manager for macOS to use system malloc/free
#if defined(__APPLE__) && defined(__MACH__)
    #define NOT_USE_CRY_MEMORY_MANAGER 1
#endif

// Platform detection and header inclusion
#if defined(__APPLE__) && defined(__MACH__)
    // macOS Platform
    #include "platform_macos.h"
#elif defined(_WIN32) || defined(_WIN64)
    // Windows Platform
    #include "Win32specific.h"
#elif defined(__linux__)
    // Linux Platform
    #include "LinuxSpecific.h"
#else
    #error "Unsupported platform"
#endif

#endif // _PLATFORM_H_
