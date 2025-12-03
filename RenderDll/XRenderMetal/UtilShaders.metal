//
//  BasicShaders.metal
//  FarCry Mac Silicon Port
//
//  Basic Metal shaders for initial rendering support
//

#include <metal_stdlib>
using namespace metal;

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
    float4 color;
    float clipDistance; // Distance to clip plane for fragment clipping
};

// Uniform buffer for transformation matrices - MUST match UniformBufferData in MetalBaseRenderer.h exactly
struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3 cameraPos;
    float time;
    float3 lightPos;
    float padding1;
    float3 lightColor;
    float padding2;
    float4 clipPlane;      // Normal.xyz + Distance
    float clipEnabled;     // 1.0f if enabled, 0.0f if disabled
    float clipRefract;     // 1.0f if refract mode, 0.0f if not
    float padding3;        // Maintain 16-byte alignment
    float padding4;        // Maintain 16-byte alignment
};

// Basic vertex shader
vertex VertexOut basic_vertex(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
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
    
    // Pass through texture coordinates and color
    out.texCoord = in.texCoord;
    out.color = in.color;
    
    return out;
}

// Basic fragment shader with texture and lighting
fragment float4 basic_fragment(VertexOut in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(0)]],
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
    float3 lightDir = normalize(uniforms.lightPos - in.worldPos);
    float3 viewDir = normalize(uniforms.cameraPos - in.worldPos);
    float3 reflectDir = reflect(-lightDir, normal);
    
    // Ambient
    float ambientStrength = 0.1;
    float3 ambient = ambientStrength * uniforms.lightColor;
    
    // Diffuse
    float diff = max(dot(normal, lightDir), 0.0);
    float3 diffuse = diff * uniforms.lightColor;
    
    // Specular
    float specularStrength = 0.5;
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32);
    float3 specular = specularStrength * spec * uniforms.lightColor;
    
    // Combine lighting with texture (no materialColor in our structure)
    float3 lighting = ambient + diffuse + specular;
    float4 finalColor = float4(lighting, 1.0) * textureColor * in.color;
    
    return finalColor;
}

// Unlit fragment shader (for UI and simple rendering)
fragment float4 unlit_fragment(VertexOut in [[stage_in]],
                              texture2d<float> baseTexture [[texture(0)]],
                              sampler textureSampler [[sampler(0)]]) {
    
    float4 textureColor = baseTexture.sample(textureSampler, in.texCoord);
    return textureColor * in.color;
}

// Solid color fragment shader (for debug rendering)
fragment float4 solid_color_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(0)]]) {
    // Perform clip plane test if enabled
    if (uniforms.clipEnabled > 0.0 && in.clipDistance < 0.0) {
        discard_fragment();
    }
    
    return in.color;
}

// Simple position-only vertex shader
struct VertexIn_P3F {
    float3 position [[attribute(0)]];
};

struct VertexOut_Simple {
    float4 position [[position]];
    float4 color;
    float clipDistance; // Distance to clip plane for fragment clipping
};

vertex VertexOut_Simple simple_vertex(VertexIn_P3F in [[stage_in]],
                                      constant Uniforms& uniforms [[buffer(1)]],
                                      constant float4& color [[buffer(2)]]) {
    VertexOut_Simple out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.color = color;
    
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
    
    return in.color;
}

// Position + Color vertex shader
struct VertexIn_P3F_COL4UB {
    float3 position [[attribute(0)]];
    uchar4 color [[attribute(1)]];
};

vertex VertexOut_Simple color_vertex(VertexIn_P3F_COL4UB in [[stage_in]],
                                     constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut_Simple out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.color = float4(in.color) / 255.0;
    
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
    float4 color;
    float2 texCoord;
    float clipDistance; // Distance to clip plane for fragment clipping
};

vertex VertexOut_ColorTex colortex_vertex(VertexIn_P3F_COL4UB_TEX2F in [[stage_in]],
                                          constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut_ColorTex out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.color = float4(in.color) / 255.0;
    out.texCoord = in.texCoord;
    
    // Calculate clip distance if clipping is enabled
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0; // Always pass when clipping disabled
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
    float2 texCoord;
    float clipDistance;
};

vertex VertexOut_Tex tex_vertex(VertexIn_P3F_TEX2F in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut_Tex out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.texCoord = in.texCoord;
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
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
                                  constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut_Tex2 out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.Tex0 = float4(in.texCoord0, 0.0, 1.0);
    out.Tex1 = float4(in.texCoord1, 0.0, 1.0);
    return out;
}

vertex VertexOut_ColorTex2 colortex2_vertex(VertexIn_P3F_COL4UB_TEX2F_TEX2F in [[stage_in]],
                                           constant Uniforms& uniforms [[buffer(1)]]) {
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
    float4 color;
    float4 color1;
    float clipDistance;
};

struct VertexOut_DualColorTex {
    float4 position [[position]];
    float4 color;
    float4 color1;
    float4 Tex0;
    float clipDistance;
};

vertex VertexOut_DualColor colordual_vertex(VertexIn_P3F_COL4UB_COL4UB in [[stage_in]],
                                            constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut_DualColor out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.color = float4(in.color0) / 255.0;
    out.color1 = float4(in.color1) / 255.0;
    if (uniforms.clipEnabled > 0.0) {
        float3 worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
        out.clipDistance = dot(worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

vertex VertexOut_DualColorTex colordual_tex_vertex(VertexIn_P3F_COL4UB_COL4UB_TEX2F in [[stage_in]],
                                                   constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut_DualColorTex out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.color = float4(in.color0) / 255.0;
    out.color1 = float4(in.color1) / 255.0;
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
    float4 color;
    float4 color1;
    float clipDistance;
};

vertex VertexOut_LitDualColor basic_colordual_vertex(VertexIn_P3F_N_COL4UB_COL4UB in [[stage_in]],
                                                     constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut_LitDualColor out;
    float4 localPos = float4(in.position, 1.0);
    out.position = uniforms.modelViewProjectionMatrix * localPos;
    out.worldPos = (uniforms.modelMatrix * localPos).xyz;
    out.normal = normalize((uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.texCoord = float2(0.0);
    out.color = float4(in.color0) / 255.0;
    out.color1 = float4(in.color1) / 255.0;
    if (uniforms.clipEnabled > 0.0) {
        out.clipDistance = dot(out.worldPos, uniforms.clipPlane.xyz) + uniforms.clipPlane.w;
    } else {
        out.clipDistance = 1.0;
    }
    return out;
}

vertex VertexOut_LitDualColor basic_colordual_tex_vertex(VertexIn_P3F_N_COL4UB_COL4UB_TEX2F in [[stage_in]],
                                                         constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut_LitDualColor out;
    float4 localPos = float4(in.position, 1.0);
    out.position = uniforms.modelViewProjectionMatrix * localPos;
    out.worldPos = (uniforms.modelMatrix * localPos).xyz;
    out.normal = normalize((uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.texCoord = in.texCoord;
    out.color = float4(in.color0) / 255.0;
    out.color1 = float4(in.color1) / 255.0;
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
    
    float4 textureColor = baseTexture.sample(textureSampler, in.texCoord);
    return textureColor * in.color;
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
    float4 color;
    float height;
};

vertex VertexOut_Terrain terrain_vertex(VertexIn_Terrain in [[stage_in]],
                                        constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut_Terrain out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
    out.normal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
    out.texCoord = in.texCoord;
    out.color = in.color;
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
    float3 lightDir = normalize(uniforms.lightPos - in.worldPos);
    float diff = max(dot(normal, lightDir), 0.0);
    
    float3 lighting = float3(0.3) + diff * uniforms.lightColor.rgb * 0.7;
    float4 finalColor = baseColor * detailColor * float4(lighting, 1.0) * in.color;
    
    return finalColor;
}

// Sky shader
vertex VertexOut sky_vertex(VertexIn in [[stage_in]],
                            constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 pos = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.position = pos.xyww;
    out.worldPos = in.position;
    out.normal = in.normal;
    out.texCoord = in.texCoord;
    out.color = in.color;
    return out;
}

fragment float4 sky_fragment(VertexOut in [[stage_in]],
                            texturecube<float> skyTexture [[texture(0)]],
                            sampler textureSampler [[sampler(0)]]) {
    float3 direction = normalize(in.worldPos);
    return skyTexture.sample(textureSampler, direction);
}
