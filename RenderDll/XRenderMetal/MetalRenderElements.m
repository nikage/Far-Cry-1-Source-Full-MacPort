////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalRenderElements.h
//  Version:     v1.00
//  Created:     29/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal render element declarations for terrain, sky, vegetation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_RENDER_ELEMENTS_H
#define METAL_RENDER_ELEMENTS_H

#if defined(__APPLE__) && defined(__MACH__)

#include "RendElement.h"

CRendElement* CreateMetalRenderElement(EDataType edt);

#endif // __APPLE__ && __MACH__

#endif // METAL_RENDER_ELEMENTS_H

