////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalVertexDescriptor.h
//  Version:     v1.00
//  Created:     30/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Helper functions for creating Metal vertex descriptors
//               from CryEngine vertex formats
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_VERTEX_DESCRIPTOR_H
#define METAL_VERTEX_DESCRIPTOR_H

#if defined(__APPLE__) && defined(__MACH__)

// Include all CryEngine infrastructure
#include "MetalRenderPCH.h"

class CMetalVertexDescriptorHelper
{
public:
    static MTLVertexDescriptor* CreateVertexDescriptor(int vertexFormat);
    
private:
    static MTLVertexDescriptor* CreateDescriptor_P3F();
    static MTLVertexDescriptor* CreateDescriptor_P3F_COL4UB();
    static MTLVertexDescriptor* CreateDescriptor_P3F_COL4UB_TEX2F();
    static MTLVertexDescriptor* CreateDescriptor_P3F_N();
    static MTLVertexDescriptor* CreateDescriptor_P3F_N_COL4UB_TEX2F();
    static MTLVertexDescriptor* CreateDescriptor_P3F_TEX2F();
    static MTLVertexDescriptor* CreateDescriptor_P3F_N_TEX2F();
};

#endif

#endif

