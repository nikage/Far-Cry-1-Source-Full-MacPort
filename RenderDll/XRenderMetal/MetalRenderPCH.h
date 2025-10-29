////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port  
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalRenderPCH.h
//  Version:     v1.00
//  Created:     29/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Precompiled header for Metal renderer - includes all
//               necessary CryEngine infrastructure in proper order
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_RENDER_PCH_H
#define METAL_RENDER_PCH_H

#if defined(__APPLE__) && defined(__MACH__)

// Standard C/C++ headers first (before platform.h which may define macros)
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>

// STL headers
#include <vector>
#include <list>
#include <map>
#include <unordered_map>
#define hash_map unordered_map
#include <set>
#include <string>
#include <algorithm>
#include <memory>
#include <stack>
#include <array>

// Metal frameworks MUST come before platform.h to avoid macro conflicts
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Cocoa/Cocoa.h>

// Now platform headers
#include <platform.h>

// Define constants needed by renderer
#define MAX_TMU 8

// CryEngine utility headers
#include <list2.h>
#include <Names.h>

// CryEngine interface headers
#include <IProcess.h>
#include <ITimer.h>
#include <ISystem.h>
#include <ILog.h>
#include <IConsole.h>
#include <IRenderer.h>

// Math headers
#include <Cry_Math.h>
#include "Cry_Camera.h"

// Vertex formats
#include <VertexFormats.h>

// Shader system
#include "../Common/Shaders/Shader.h"
#include "../Common/Shaders/CShader.h"
#include "../Common/EvalFuncs.h"
#include "../Common/RenderPipeline.h"

// Core renderer
#include "../Common/Renderer.h"

#endif // __APPLE__

#endif // METAL_RENDER_PCH_H

