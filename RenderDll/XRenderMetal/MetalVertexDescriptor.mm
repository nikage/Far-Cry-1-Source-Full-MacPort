////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalVertexDescriptor.cpp
//  Version:     v1.00
//  Created:     30/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Implementation of Metal vertex descriptor helpers
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalVertexDescriptor.m"
#include <cassert>

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateVertexDescriptor(int vertexFormat)
{
    assert(vertexFormat >= 0 && "CreateVertexDescriptor: vertexFormat must be non-negative!");
    
    switch (vertexFormat)
    {
        case VERTEX_FORMAT_P3F:
            return CreateDescriptor_P3F();
            
        case VERTEX_FORMAT_P3F_COL4UB:
            return CreateDescriptor_P3F_COL4UB();
            
        case VERTEX_FORMAT_P3F_COL4UB_TEX2F:
            return CreateDescriptor_P3F_COL4UB_TEX2F();
            
        case VERTEX_FORMAT_P3F_N:
            return CreateDescriptor_P3F_N();
        
        case VERTEX_FORMAT_P3F_N_COL4UB_TEX2F:
            return CreateDescriptor_P3F_N_COL4UB_TEX2F();
            
        case VERTEX_FORMAT_P3F_TEX2F:
            return CreateDescriptor_P3F_TEX2F();
            
        case VERTEX_FORMAT_P3F_N_TEX2F:
            return CreateDescriptor_P3F_N_TEX2F();
            
        case VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F:
            return CreateDescriptor_P3F_COL4UB_TEX2F_TEX2F();
            
        case VERTEX_FORMAT_P3F_COL4UB_COL4UB:
            return CreateDescriptor_P3F_COL4UB_COL4UB();
            
        case VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F:
            return CreateDescriptor_P3F_COL4UB_COL4UB_TEX2F();
            
        case VERTEX_FORMAT_P3F_N_COL4UB_COL4UB:
            return CreateDescriptor_P3F_N_COL4UB_COL4UB();
            
        case VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F:
            return CreateDescriptor_P3F_N_COL4UB_COL4UB_TEX2F();
            
        case VERTEX_FORMAT_P3F_N_COL4UB:
            return CreateDescriptor_P3F_N_COL4UB();
            
        default:
            return CreateDescriptor_P3F_COL4UB_TEX2F();
    }
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = 0;
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F: stride must be positive!");
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_COL4UB()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_COL4UB: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatUChar4;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB, color);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_COL4UB: stride must be positive!");
    assert(descriptor.attributes[1].offset > descriptor.attributes[0].offset && 
           "CreateDescriptor_P3F_COL4UB: attribute offsets must be in order!");
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_COL4UB_TEX2F()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_COL4UB_TEX2F: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatUChar4;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F, color);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.attributes[2].format = MTLVertexFormatFloat2;
    descriptor.attributes[2].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F, st);
    descriptor.attributes[2].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_COL4UB_TEX2F: stride must be positive!");
    assert(descriptor.attributes[2].offset > descriptor.attributes[1].offset && 
           "CreateDescriptor_P3F_COL4UB_TEX2F: attribute offsets must be in order!");
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_N()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_N: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_N, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatFloat3;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_N, normal);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_N);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_N: stride must be positive!");
    assert(descriptor.attributes[1].offset > descriptor.attributes[0].offset && 
           "CreateDescriptor_P3F_N: attribute offsets must be in order!");
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_N_COL4UB_TEX2F()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_N_COL4UB_TEX2F: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_TEX2F, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatFloat3;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_TEX2F, normal);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.attributes[2].format = MTLVertexFormatUChar4;
    descriptor.attributes[2].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_TEX2F, color);
    descriptor.attributes[2].bufferIndex = 0;
    
    descriptor.attributes[3].format = MTLVertexFormatFloat2;
    descriptor.attributes[3].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_TEX2F, st);
    descriptor.attributes[3].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_N_COL4UB_TEX2F);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_N_COL4UB_TEX2F: stride must be positive!");
    assert(descriptor.attributes[3].offset > descriptor.attributes[2].offset && 
           "CreateDescriptor_P3F_N_COL4UB_TEX2F: attribute offsets must be in order!");
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_TEX2F()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_TEX2F: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_TEX2F, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatFloat2;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_TEX2F, st);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_TEX2F);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_TEX2F: stride must be positive!");
    assert(descriptor.attributes[1].offset > descriptor.attributes[0].offset && 
           "CreateDescriptor_P3F_TEX2F: attribute offsets must be in order!");
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_N_TEX2F()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_N_TEX2F: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_TEX2F, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatFloat3;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_TEX2F, normal);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.attributes[2].format = MTLVertexFormatFloat2;
    descriptor.attributes[2].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_TEX2F, st);
    descriptor.attributes[2].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_N_TEX2F);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_N_TEX2F: stride must be positive!");
    assert(descriptor.attributes[2].offset > descriptor.attributes[1].offset && 
           "CreateDescriptor_P3F_N_TEX2F: attribute offsets must be in order!");
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_COL4UB_TEX2F_TEX2F()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_COL4UB_TEX2F_TEX2F: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatUChar4;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F, color);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.attributes[2].format = MTLVertexFormatFloat2;
    descriptor.attributes[2].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F, st0);
    descriptor.attributes[2].bufferIndex = 0;
    
    descriptor.attributes[3].format = MTLVertexFormatFloat2;
    descriptor.attributes[3].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F, st1);
    descriptor.attributes[3].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_COL4UB_TEX2F_TEX2F: stride must be positive!");
    assert(descriptor.attributes[3].offset > descriptor.attributes[2].offset);
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_COL4UB_COL4UB()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_COL4UB_COL4UB: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatUChar4;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB, color);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.attributes[2].format = MTLVertexFormatUChar4;
    descriptor.attributes[2].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB, seccolor);
    descriptor.attributes[2].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_COL4UB_COL4UB: stride must be positive!");
    assert(descriptor.attributes[2].offset > descriptor.attributes[1].offset);
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_COL4UB_COL4UB_TEX2F()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_COL4UB_COL4UB_TEX2F: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatUChar4;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F, color);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.attributes[2].format = MTLVertexFormatUChar4;
    descriptor.attributes[2].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F, seccolor);
    descriptor.attributes[2].bufferIndex = 0;
    
    descriptor.attributes[3].format = MTLVertexFormatFloat2;
    descriptor.attributes[3].offset = offsetof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F, st);
    descriptor.attributes[3].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_COL4UB_COL4UB_TEX2F: stride must be positive!");
    assert(descriptor.attributes[3].offset > descriptor.attributes[2].offset);
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_N_COL4UB_COL4UB()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_N_COL4UB_COL4UB: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatFloat3;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB, normal);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.attributes[2].format = MTLVertexFormatUChar4;
    descriptor.attributes[2].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB, color);
    descriptor.attributes[2].bufferIndex = 0;
    
    descriptor.attributes[3].format = MTLVertexFormatUChar4;
    descriptor.attributes[3].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB, seccolor);
    descriptor.attributes[3].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_N_COL4UB_COL4UB: stride must be positive!");
    assert(descriptor.attributes[3].offset > descriptor.attributes[2].offset);
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_N_COL4UB_COL4UB_TEX2F()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_N_COL4UB_COL4UB_TEX2F: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatFloat3;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F, normal);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.attributes[2].format = MTLVertexFormatUChar4;
    descriptor.attributes[2].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F, color);
    descriptor.attributes[2].bufferIndex = 0;
    
    descriptor.attributes[3].format = MTLVertexFormatUChar4;
    descriptor.attributes[3].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F, seccolor);
    descriptor.attributes[3].bufferIndex = 0;
    
    descriptor.attributes[4].format = MTLVertexFormatFloat2;
    descriptor.attributes[4].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F, st);
    descriptor.attributes[4].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_N_COL4UB_COL4UB_TEX2F: stride must be positive!");
    assert(descriptor.attributes[4].offset > descriptor.attributes[3].offset);
    return descriptor;
}

MTLVertexDescriptor* CMetalVertexDescriptorHelper::CreateDescriptor_P3F_N_COL4UB()
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    assert(descriptor != nil && "CreateDescriptor_P3F_N_COL4UB: descriptor allocation failed!");
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB, xyz);
    descriptor.attributes[0].bufferIndex = 0;
    
    descriptor.attributes[1].format = MTLVertexFormatFloat3;
    descriptor.attributes[1].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB, normal);
    descriptor.attributes[1].bufferIndex = 0;
    
    descriptor.attributes[2].format = MTLVertexFormatUChar4;
    descriptor.attributes[2].offset = offsetof(struct_VERTEX_FORMAT_P3F_N_COL4UB, color);
    descriptor.attributes[2].bufferIndex = 0;
    
    descriptor.layouts[0].stride = sizeof(struct_VERTEX_FORMAT_P3F_N_COL4UB);
    descriptor.layouts[0].stepRate = 1;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    assert(descriptor.layouts[0].stride > 0 && "CreateDescriptor_P3F_N_COL4UB: stride must be positive!");
    assert(descriptor.attributes[2].offset > descriptor.attributes[1].offset);
    return descriptor;
}

void CMetalVertexDescriptorHelper::AttachTangentAttributes(MTLVertexDescriptor* descriptor)
{
    if (!descriptor)
        return;

    const NSUInteger tangentBufferIndex = kMetalVertexStream_Tangents;
    descriptor.attributes[4].format = MTLVertexFormatFloat3;
    descriptor.attributes[4].offset = offsetof(SPipTangents, m_Tangent);
    descriptor.attributes[4].bufferIndex = tangentBufferIndex;

    descriptor.attributes[5].format = MTLVertexFormatFloat3;
    descriptor.attributes[5].offset = offsetof(SPipTangents, m_Binormal);
    descriptor.attributes[5].bufferIndex = tangentBufferIndex;

    descriptor.attributes[6].format = MTLVertexFormatFloat3;
    descriptor.attributes[6].offset = offsetof(SPipTangents, m_TNormal);
    descriptor.attributes[6].bufferIndex = tangentBufferIndex;

    descriptor.layouts[tangentBufferIndex].stride = sizeof(SPipTangents);
    descriptor.layouts[tangentBufferIndex].stepRate = 1;
    descriptor.layouts[tangentBufferIndex].stepFunction = MTLVertexStepFunctionPerVertex;
}

#endif

