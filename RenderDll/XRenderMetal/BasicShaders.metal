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
};

// Uniform buffer for transformation matrices
struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float4x4 modelMatrix;
    float4x4 normalMatrix;
    float3 lightPos;
    float3 viewPos;
    float4 lightColor;
    float4 materialColor;
};

// Basic vertex shader
vertex VertexOut basic_vertex(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    
    // Transform position to clip space
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    
    // Transform position to world space
    out.worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
    
    // Transform normal to world space
    out.normal = (uniforms.normalMatrix * float4(in.normal, 0.0)).xyz;
    
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
    
    // Sample the base texture
    float4 textureColor = baseTexture.sample(textureSampler, in.texCoord);
    
    // Simple Phong lighting calculation
    float3 normal = normalize(in.normal);
    float3 lightDir = normalize(uniforms.lightPos - in.worldPos);
    float3 viewDir = normalize(uniforms.viewPos - in.worldPos);
    float3 reflectDir = reflect(-lightDir, normal);
    
    // Ambient
    float ambientStrength = 0.1;
    float3 ambient = ambientStrength * uniforms.lightColor.rgb;
    
    // Diffuse
    float diff = max(dot(normal, lightDir), 0.0);
    float3 diffuse = diff * uniforms.lightColor.rgb;
    
    // Specular
    float specularStrength = 0.5;
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32);
    float3 specular = specularStrength * spec * uniforms.lightColor.rgb;
    
    // Combine lighting with texture and material color
    float3 lighting = ambient + diffuse + specular;
    float4 finalColor = float4(lighting, 1.0) * textureColor * uniforms.materialColor * in.color;
    
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
    return uniforms.materialColor * in.color;
}
