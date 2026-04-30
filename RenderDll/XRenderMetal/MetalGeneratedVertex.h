////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalGeneratedVertex.h
//  Description: Shared types for generated Metal vertex metadata
// -------------------------------------------------------------------------
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_GENERATED_VERTEX_H
#define METAL_GENERATED_VERTEX_H

#if defined(__APPLE__) && defined(__MACH__)

#include <string>
#include <vector>

struct GeneratedVertexAttributeDesc
{
    std::string token;
    std::string category;
    std::string semantic;
    std::string label;
    int components = 0;
    int index = -1;
    int slot = -1;
    int bufferIndex = 0;
};

struct GeneratedVertexOutputDesc
{
    std::string name;
    int components = 0;
};

struct GeneratedVertexEntry
{
    std::string shaderName;
    std::string normalizedName;
    std::string entryPoint;
    std::vector<GeneratedVertexAttributeDesc> attributes;
    std::vector<GeneratedVertexOutputDesc> outputs;
    std::vector<GeneratedVertexAttributeDesc> vertexInputDescs;
};

#endif

#endif // METAL_GENERATED_VERTEX_H

