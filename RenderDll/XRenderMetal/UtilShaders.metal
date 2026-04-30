//
//  BasicShaders.metal
//  FarCry Mac Silicon Port
//
//  Basic Metal shaders for initial rendering support
//

#include <metal_stdlib>
using namespace metal;

#define METAL_VERTEX_UNIFORM_BUFFER_INDEX   2
#define METAL_FRAGMENT_UNIFORM_BUFFER_INDEX 0
#define METAL_MATERIAL_BUFFER_INDEX         1
#define METAL_VERTEX_COLOR_BUFFER_INDEX     3
#define METAL_WATER_NOISE_BUFFER_INDEX      4

// Vertex shader input structure
struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
    float4 color    [[attribute(3)]];
};

// Vertex shader output structure
struct VertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 texCoord;
    float4 Color;
    float clipDistance; // Distance to clip plane for fragment clipping
    float fog [[user(fog)]]; // Linear fog factor (0=fully fogged, 1=clear)
};

// Uniform buffer for transformation matrices - MUST match UniformBufferData in MetalBaseRenderer.h exactly
// pos.w = radius, color.w = intensity; float4 matches C++ float[4] on both sizes and offsets.
struct LightEntry {
    float4 pos;    // xyz=position, w=radius
    float4 color;  // xyz=color, w=intensity
};

struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    // float4 fields (not float3) so MSL implicit alignment == C++ explicit float[4] layout.
    // After the 4 matrices (offset 256):
    //   float4 cameraPos  → offset 256 (16-aligned ✓)
    //   float  time       → offset 272
    //   implicit 12-byte gap (MSL aligns next float4 to 288)
    //   float4 lightPos   → offset 288
    //   float4 lightColor → offset 304
    float4 cameraPos;
    float  time;
    float4 lightPos;    // w unused
    float4 lightColor;  // w unused
    // Full light list (up to 4 dynamic lights)
    LightEntry lights[4];
    int    numLights;
    // Three float scalars (alignof=4) to bridge to the next 16-byte boundary.
    float  _pad3_0, _pad3_1, _pad3_2;
    float4 clipPlane;      // Normal.xyz + Distance
    float clipEnabled;
    float clipRefract;
    float fogScale;        // 1/(fogEnd - fogStart) for linear fog
    float fogBias;         // fogEnd/(fogEnd - fogStart) for linear fog
};

struct MaterialUniforms {
    float4 Ambient;      // Cg PS c0
    float4 Diffuse;      // Cg PS c1
    float4 Specular;     // Cg PS c2
    float4 InlineDef0;   // Cg PS c3 — bias/scale/constants
    float4 InlineDef1;   // Cg PS c4
    float4 FogColor;     // GlobalFogColor (c7/c31 depending on shader)
};

// Basic vertex shader
vertex VertexOut basic_vertex(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut out;
    
    // Transform position to clip space
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    
    // Transform position to world space
    out.worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
    
    // Transform normal to world space (using modelMatrix since we don't have normalMatrix)
    out.normal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
    
    // Calculate clip distance if clipping is enabled
    if (uniforms.clipEnabled > 0.0) {
        out.clipDistance = dot(out.worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0; // Always pass when clipping disabled
    }
    
    // Linear fog factor: 1=clear, 0=fully fogged
    float eyeZ = out.position.z / out.position.w;
    out.fog = saturate(uniforms.fogBias - uniforms.fogScale * eyeZ);
    
    // Pass through texture coordinates and color
    out.texCoord = in.texCoord;
    out.Color = in.color;
    
    return out;
}

// Basic fragment shader with texture and lighting
fragment float4 basic_fragment(VertexOut in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(METAL_FRAGMENT_UNIFORM_BUFFER_INDEX)]],
                              constant MaterialUniforms& mat [[buffer(METAL_MATERIAL_BUFFER_INDEX)]],
                              texture2d<float> baseTexture [[texture(0)]],
                              sampler textureSampler [[sampler(0)]]) {
    
    // Perform clip plane test if enabled
    if (uniforms.clipEnabled > 0.0 && in.clipDistance < 0.0) {
        discard_fragment();
    }
    
    // Sample the base texture
    float4 textureColor = baseTexture.sample(textureSampler, in.texCoord);
    
    // Simple Phong lighting calculation
    float3 normal = normalize(in.normal);
    float3 lightDir = normalize(uniforms.lightPos.xyz - in.worldPos);
    float3 viewDir = normalize(uniforms.cameraPos.xyz - in.worldPos);
    float3 reflectDir = reflect(-lightDir, normal);
    
    // Ambient
    float ambientStrength = 0.1;
    float3 ambient = ambientStrength * uniforms.lightColor.xyz;
    
    // Diffuse
    float diff = max(dot(normal, lightDir), 0.0);
    float3 diffuse = diff * uniforms.lightColor.xyz;
    
    // Specular
    float specularStrength = 0.5;
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32);
    float3 specular = specularStrength * spec * uniforms.lightColor.xyz;
    
    float3 lighting = ambient + diffuse + specular;
    float4 finalColor = float4(lighting, 1.0) * textureColor * in.Color;
    
    // Apply linear fog
    if (uniforms.fogScale > 0.0) {
        finalColor.rgb = mix(mat.FogColor.rgb, finalColor.rgb, in.fog);
    }
    
    return finalColor;
}

// Unlit fragment shader (for UI and simple rendering)
fragment float4 unlit_fragment(VertexOut in [[stage_in]],
                              texture2d<float> baseTexture [[texture(0)]],
                              sampler textureSampler [[sampler(0)]]) {
    
    float4 textureColor = baseTexture.sample(textureSampler, in.texCoord);
    return textureColor * in.Color;
}

// Solid color fragment shader (for debug rendering)
fragment float4 solid_color_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(0)]]) {
    // Perform clip plane test if enabled
    if (uniforms.clipEnabled > 0.0 && in.clipDistance < 0.0) {
        discard_fragment();
    }
    
    return in.Color;
}

// Simple position-only vertex shader
struct VertexIn_P3F {
    float3 position [[attribute(0)]];
};

struct VertexOut_Simple {
    float4 position [[position]];
    float4 Color;
    float clipDistance; // Distance to clip plane for fragment clipping
};

vertex VertexOut_Simple simple_vertex(VertexIn_P3F in [[stage_in]],
                                      constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]],
                                      constant float4& color [[buffer(METAL_VERTEX_COLOR_BUFFER_INDEX)]]) {
    VertexOut_Simple out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.Color = color;
    
    // Calculate clip distance if clipping is enabled
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0; // Always pass when clipping disabled
    }
    
    return out;
}

fragment float4 simple_fragment(VertexOut_Simple in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]]) {
    // Perform clip plane test if enabled
    if (uniforms.clipEnabled > 0.0 && in.clipDistance < 0.0) {
        discard_fragment();
    }
    
    return in.Color;
}

// Position + Color vertex shader
struct VertexIn_P3F_COL4UB {
    float3 position [[attribute(0)]];
    uchar4 color [[attribute(1)]];
};

vertex VertexOut_Simple color_vertex(VertexIn_P3F_COL4UB in [[stage_in]],
                                     constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_Simple out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.Color = float4(in.color) / 255.0;
    
    // Calculate clip distance if clipping is enabled
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0; // Always pass when clipping disabled
    }
    
    return out;
}

// Position + Color + TexCoord vertex shader (most common)
struct VertexIn_P3F_COL4UB_TEX2F {
    float3 position [[attribute(0)]];
    uchar4 color [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VertexOut_ColorTex {
    float4 position [[position]];
    float4 Color;
    float4 TexCoord0;
    float clipDistance; // Distance to clip plane for fragment clipping
};

struct VertexIn_P3F_N_COL4UB_TEX2F_Tangent {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    uchar4 color [[attribute(2)]];
    float2 texCoord [[attribute(3)]];
    float3 tangent [[attribute(4)]];
    float3 binormal [[attribute(5)]];
    float3 tnormal [[attribute(6)]];
};

struct VertexOut_TangentFrame {
    float4 position [[position]];
    float4 Color;
    float4 TexCoord0;
    float3 Tangent;
    float3 Binormal;
    float3 TNormal;
    float clipDistance;
};

vertex VertexOut_ColorTex colortex_vertex(VertexIn_P3F_COL4UB_TEX2F in [[stage_in]],
                                          constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_ColorTex out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.Color = float4(in.color) / 255.0;
    out.TexCoord0 = float4(in.texCoord, 0.0, 1.0);
    
    // Calculate clip distance if clipping is enabled
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0; // Always pass when clipping disabled
    }
    
    return out;
}

vertex VertexOut_TangentFrame tangent_vertex(VertexIn_P3F_N_COL4UB_TEX2F_Tangent in [[stage_in]],
                                             constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_TangentFrame out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.Color = float4(in.color) / 255.0;
    out.TexCoord0 = float4(in.texCoord, 0.0, 1.0);
    out.Tangent = in.tangent;
    out.Binormal = in.binormal;
    out.TNormal = in.tnormal;
    
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    
    return out;
}

// Position + TexCoord vertex shader (no per-vertex color)
struct VertexIn_P3F_TEX2F {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut_Tex {
    float4 position [[position]];
    float4 TexCoord0;
    float clipDistance;
};

vertex VertexOut_Tex tex_vertex(VertexIn_P3F_TEX2F in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_Tex out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.TexCoord0 = float4(in.texCoord, 0.0, 1.0);
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

vertex VertexOut_Tex screen_vertex(VertexIn_P3F_TEX2F in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_Tex out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.TexCoord0 = float4(in.texCoord, 0.0, 1.0);
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

struct VertexIn_P3F_N {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct VertexIn_P3F_N_TEX2F {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VertexIn_P3F_N_COL4UB {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    uchar4 color [[attribute(2)]];
};

vertex VertexOut normal_vertex(VertexIn_P3F_N in [[stage_in]],
                               constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
    out.normal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
    out.texCoord = float2(0.0);
    out.Color = float4(1.0);
    if (uniforms.clipEnabled > 0.0) {
        out.clipDistance = dot(out.worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

vertex VertexOut normaltex_vertex(VertexIn_P3F_N_TEX2F in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
    out.normal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
    out.texCoord = in.texCoord;
    out.Color = float4(1.0);
    if (uniforms.clipEnabled > 0.0) {
        out.clipDistance = dot(out.worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

vertex VertexOut basic_color_vertex(VertexIn_P3F_N_COL4UB in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
    out.normal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
    out.texCoord = float2(0.0);
    out.Color = float4(in.color) / 255.0;
    if (uniforms.clipEnabled > 0.0) {
        out.clipDistance = dot(out.worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

// Position + two TexCoords (with optional color) vertex shader
struct VertexIn_P3F_COL4UB_TEX2F_TEX2F {
    float3 position [[attribute(0)]];
    uchar4 color [[attribute(1)]];
    float2 texCoord0 [[attribute(2)]];
    float2 texCoord1 [[attribute(3)]];
};

struct VertexOut_Tex2 {
    float4 position [[position]];
    float4 Tex0;
    float4 Tex1;
};

struct VertexOut_ColorTex2 {
    float4 position [[position]];
    float4 Color;
    float4 Tex0;
    float4 Tex1;
};

vertex VertexOut_Tex2 tex2_vertex(VertexIn_P3F_COL4UB_TEX2F_TEX2F in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_Tex2 out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.Tex0 = float4(in.texCoord0, 0.0, 1.0);
    out.Tex1 = float4(in.texCoord1, 0.0, 1.0);
    return out;
}

vertex VertexOut_ColorTex2 colortex2_vertex(VertexIn_P3F_COL4UB_TEX2F_TEX2F in [[stage_in]],
                                           constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_ColorTex2 out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.Color = float4(in.color) / 255.0;
    out.Tex0 = float4(in.texCoord0, 0.0, 1.0);
    out.Tex1 = float4(in.texCoord1, 0.0, 1.0);
    return out;
}

struct VertexIn_P3F_COL4UB_COL4UB {
    float3 position [[attribute(0)]];
    uchar4 color0 [[attribute(1)]];
    uchar4 color1 [[attribute(2)]];
};

struct VertexIn_P3F_COL4UB_COL4UB_TEX2F {
    float3 position [[attribute(0)]];
    uchar4 color0 [[attribute(1)]];
    uchar4 color1 [[attribute(2)]];
    float2 texCoord [[attribute(3)]];
};

struct VertexOut_DualColor {
    float4 position [[position]];
    float4 Color;
    float4 Color1;
    float clipDistance;
};

struct VertexOut_DualColorTex {
    float4 position [[position]];
    float4 Color;
    float4 Color1;
    float4 Tex0;
    float clipDistance;
};

vertex VertexOut_DualColor colordual_vertex(VertexIn_P3F_COL4UB_COL4UB in [[stage_in]],
                                            constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_DualColor out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.Color = float4(in.color0) / 255.0;
    out.Color1 = float4(in.color1) / 255.0;
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

vertex VertexOut_DualColorTex colordual_tex_vertex(VertexIn_P3F_COL4UB_COL4UB_TEX2F in [[stage_in]],
                                                   constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_DualColorTex out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.Color = float4(in.color0) / 255.0;
    out.Color1 = float4(in.color1) / 255.0;
    out.Tex0 = float4(in.texCoord, 0.0, 1.0);
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

struct VertexIn_P3F_N_COL4UB_COL4UB {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    uchar4 color0 [[attribute(2)]];
    uchar4 color1 [[attribute(3)]];
};

struct VertexIn_P3F_N_COL4UB_COL4UB_TEX2F {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    uchar4 color0 [[attribute(2)]];
    uchar4 color1 [[attribute(3)]];
    float2 texCoord [[attribute(4)]];
};

struct VertexOut_LitDualColor {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 texCoord;
    float4 Color;
    float4 Color1;
    float clipDistance;
};

vertex VertexOut_LitDualColor basic_colordual_vertex(VertexIn_P3F_N_COL4UB_COL4UB in [[stage_in]],
                                                     constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_LitDualColor out;
    float4 localPos = float4(in.position, 1.0);
    out.position = uniforms.modelViewProjectionMatrix * localPos;
    out.worldPos = (uniforms.modelMatrix * localPos).xyz;
    out.normal = normalize((uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.texCoord = float2(0.0);
    out.Color = float4(in.color0) / 255.0;
    out.Color1 = float4(in.color1) / 255.0;
    if (uniforms.clipEnabled > 0.0) {
        out.clipDistance = dot(out.worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

vertex VertexOut_LitDualColor basic_colordual_tex_vertex(VertexIn_P3F_N_COL4UB_COL4UB_TEX2F in [[stage_in]],
                                                         constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_LitDualColor out;
    float4 localPos = float4(in.position, 1.0);
    out.position = uniforms.modelViewProjectionMatrix * localPos;
    out.worldPos = (uniforms.modelMatrix * localPos).xyz;
    out.normal = normalize((uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.texCoord = in.texCoord;
    out.Color = float4(in.color0) / 255.0;
    out.Color1 = float4(in.color1) / 255.0;
    if (uniforms.clipEnabled > 0.0) {
        out.clipDistance = dot(out.worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

fragment float4 colortex_fragment(VertexOut_ColorTex in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]],
                                  texture2d<float> baseTexture [[texture(0)]],
                                  sampler textureSampler [[sampler(0)]]) {
    // Perform clip plane test if enabled
    if (uniforms.clipEnabled > 0.0 && in.clipDistance < 0.0) {
        discard_fragment();
    }
    
    float4 textureColor = baseTexture.sample(textureSampler, in.TexCoord0.xy);
    return textureColor * in.Color;
}

// Terrain shader with multi-texturing
struct VertexIn_Terrain {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
    float4 color [[attribute(3)]];
};

struct VertexOut_Terrain {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 texCoord;
    float4 Color;
    float height;
};

vertex VertexOut_Terrain terrain_vertex(VertexIn_Terrain in [[stage_in]],
                                        constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut_Terrain out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
    out.normal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
    out.texCoord = in.texCoord;
    out.Color = in.color;
    out.height = in.position.y;
    return out;
}

fragment float4 terrain_fragment(VertexOut_Terrain in [[stage_in]],
                                 constant Uniforms& uniforms [[buffer(0)]],
                                 texture2d<float> baseTexture [[texture(0)]],
                                 texture2d<float> detailTexture [[texture(1)]],
                                 sampler textureSampler [[sampler(0)]]) {
    float4 baseColor = baseTexture.sample(textureSampler, in.texCoord);
    float4 detailColor = detailTexture.sample(textureSampler, in.texCoord * 8.0);
    
    float3 normal = normalize(in.normal);
    float3 lightDir = normalize(uniforms.lightPos.xyz - in.worldPos);
    float diff = max(dot(normal, lightDir), 0.0);
    
    float3 lighting = float3(0.3) + diff * uniforms.lightColor.xyz * 0.7;
    float4 finalColor = baseColor * detailColor * float4(lighting, 1.0) * in.Color;
    
    return finalColor;
}

// Sky shader
vertex VertexOut sky_vertex(VertexIn in [[stage_in]],
                            constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    VertexOut out;
    float4 pos = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.position = pos.xyww;
    out.worldPos = in.position;
    out.normal = in.normal;
    out.texCoord = in.texCoord;
    out.Color = in.color;
    return out;
}

fragment float4 sky_fragment(VertexOut in [[stage_in]],
                            texturecube<float> skyTexture [[texture(0)]],
                            sampler textureSampler [[sampler(0)]]) {
    float3 direction = normalize(in.worldPos);
    return skyTexture.sample(textureSampler, direction);
}

// Depth-only vertex shader for shadow map generation
// No fragment output — only writes to depth attachment
vertex float4 depth_vertex(VertexIn in [[stage_in]],
                           constant Uniforms& uniforms [[buffer(METAL_VERTEX_UNIFORM_BUFFER_INDEX)]]) {
    return uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
}

// ---- HDR tone-mapping pass ----
// Full-screen triangle: vertex positions are generated in the shader from vertex ID.

struct HDROut {
    float4 position [[position]];
    float2 texCoord;
};

vertex HDROut hdr_fullscreen_vertex(uint vid [[vertex_id]]) {
    // Full-screen triangle from vertex ID (no vertex buffer needed).
    // uv.xy covers [0,2] × [0,2] so the single triangle covers clip space.
    // Metal NDC: Y = +1 is screen top. Metal textures: V = 0 is texture top.
    // Therefore texCoord.y must be flipped: V = 1 - uv.y so that the
    // bottom of the screen (NDC Y = -1) reads the bottom of the source texture.
    HDROut out;
    float2 uv    = float2((vid & 1u) ? 2.0 : 0.0, (vid & 2u) ? 2.0 : 0.0);
    out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    out.texCoord = float2(uv.x, 1.0 - uv.y);
    return out;
}

fragment float4 hdr_tonemap_fragment(HDROut in [[stage_in]],
                                     texture2d<float> hdrTex  [[texture(0)]],
                                     texture2d<float> bloomTex [[texture(1)]],
                                     sampler samp [[sampler(0)]]) {
    float3 hdrColor  = hdrTex.sample(samp, in.texCoord).rgb;
    float3 bloomColor = bloomTex.sample(samp, in.texCoord).rgb;

    // Additive bloom before tone-mapping
    hdrColor += bloomColor * 0.25;

    // Reinhard tone-mapping
    float3 mapped = hdrColor / (hdrColor + float3(1.0));

    // Gamma correction (approximate sRGB)
    mapped = pow(mapped, float3(1.0 / 2.2));

    return float4(mapped, 1.0);
}

// ------------------------------------------------------------------
// HDR Bloom chain: bright-pass + separable Gaussian blur
// ------------------------------------------------------------------

fragment float4 hdr_brightpass_fragment(HDROut in [[stage_in]],
                                        texture2d<float> hdrTex [[texture(0)]],
                                        sampler samp [[sampler(0)]]) {
    float3 color = hdrTex.sample(samp, in.texCoord).rgb;
    // Extract pixels brighter than threshold
    float brightness = dot(color, float3(0.2126, 0.7152, 0.0722));
    float threshold  = 1.0;
    float contribution = max(0.0, brightness - threshold);
    return float4(color * (contribution / max(brightness, 0.0001)), 1.0);
}

fragment float4 hdr_blur_h_fragment(HDROut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]]) {
    constexpr float weights[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };
    float2 texOffset = float2(1.0 / float(src.get_width()), 0.0);
    float3 result = src.sample(samp, in.texCoord).rgb * weights[0];
    for (int i = 1; i < 5; ++i) {
        result += src.sample(samp, in.texCoord + texOffset * float(i)).rgb * weights[i];
        result += src.sample(samp, in.texCoord - texOffset * float(i)).rgb * weights[i];
    }
    return float4(result, 1.0);
}

fragment float4 hdr_blur_v_fragment(HDROut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]],
                                    sampler samp [[sampler(0)]]) {
    constexpr float weights[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };
    float2 texOffset = float2(0.0, 1.0 / float(src.get_height()));
    float3 result = src.sample(samp, in.texCoord).rgb * weights[0];
    for (int i = 1; i < 5; ++i) {
        result += src.sample(samp, in.texCoord + texOffset * float(i)).rgb * weights[i];
        result += src.sample(samp, in.texCoord - texOffset * float(i)).rgb * weights[i];
    }
    return float4(result, 1.0);
}
