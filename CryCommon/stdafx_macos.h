////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   stdafx_macos.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Description: Clean precompiled header for macOS without legacy dependencies
// -------------------------------------------------------------------------

#ifndef __STDAFX_MACOS_H__
#define __STDAFX_MACOS_H__

// Disable STLPORT for macOS
#define _STLP_NO_STD_LIB 1
#define NOT_USE_CRY_MEMORY_MANAGER 1

// Use our clean platform header
#include "platform_macos.h"

// Standard C++ headers
#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <algorithm>
#include <memory>
#include <cassert>
#include <cstring>
#include <cmath>
#include <cstdlib>

// C headers
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <memory.h>
#include <math.h>
// Note: malloc.h not available on macOS, functions are in stdlib.h

// macOS specific headers (basic POSIX only, avoid Framework conflicts)
#if defined(__APPLE__) && defined(__MACH__)
#include <sys/time.h>
#include <unistd.h>
#include <pthread.h>
#include <mach/mach_time.h>
// Note: Foundation framework excluded to avoid BOOL conflicts
#endif

// Common CryEngine headers that are safe to include will be included later
// #include "Cry_Math.h"  // This may have dependencies, include later
// #include "ILog.h"      // This may have dependencies, include later

// Compatibility macros
#define stricmp strcasecmp
#define strnicmp strncasecmp
#define _stricmp strcasecmp
#define _strnicmp strncasecmp

#ifdef __cplusplus
// Make assert work in C++
#include <cassert>
#ifdef _DEBUG
#define CRY_ASSERT(condition) assert(condition)
#else
#define CRY_ASSERT(condition) ((void)0)
#endif
#endif

#endif // __STDAFX_MACOS_H__
