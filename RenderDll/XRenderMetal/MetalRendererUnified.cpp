// Unified Metal renderer implementation to avoid duplicate symbol issues
// This file includes all Metal renderer code in a single compilation unit

#if defined(__APPLE__) && defined(__MACH__)

// Include math constants first to avoid duplicate symbol issues
#include "MetalMath.h"

// Include all Metal renderer headers
#include "MetalRenderer.h"
#include "MetalBaseRenderer.h"
#include "MetalTextureManager.h"
#include "MetalShaderManager.h"
#include "MetalUtilityRenderer.h"
#include "I3DEngine.h"
#include <Cocoa/Cocoa.h>

// Include all implementation files
#include "MetalBaseRenderer.cpp"
#include "MetalTextureManager.cpp"
#include "MetalShaderManager.cpp"
#include "MetalUtilityRenderer.cpp"
#include "MetalRenderer.cpp"

#endif // __APPLE__ && __MACH__
