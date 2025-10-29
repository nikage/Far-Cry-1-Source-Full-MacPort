////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   SpriteShaders.metal
//  Version:     v1.00
//  Created:     29/10/2025 by Mac Silicon Port Team.
//  Compilers:   xcrun metal
//  Description: Metal shaders for 2D sprite/image rendering
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#include <metal_stdlib>
using namespace metal;

// Vertex input structure for 2D sprites
struct SpriteVertexIn {
    float2 position [[attribute(0)]];  // NDC position (-1 to 1)
    float2 texCoord [[attribute(1)]];  // Texture coordinates (0 to 1)
    float4 color    [[attribute(2)]];  // Vertex color (0 to 1)
};

// Vertex output / Fragment input structure
struct SpriteVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

// Vertex shader for 2D sprites
vertex SpriteVertexOut sprite_vertex(SpriteVertexIn in [[stage_in]]) {
    SpriteVertexOut out;
    
    // Position is already in NDC, just convert to clip space
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.color = in.color;
    
    return out;
}

// Fragment shader for 2D sprites
fragment float4 sprite_fragment(SpriteVertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler samp [[sampler(0)]]) {
    // Sample texture
    float4 texColor = tex.sample(samp, in.texCoord);
    
    // Modulate with vertex color
    float4 finalColor = texColor * in.color;
    
    return finalColor;
}

// Alternative fragment shader without texture (for debug rendering)
fragment float4 sprite_fragment_notex(SpriteVertexOut in [[stage_in]]) {
    return in.color;
}

