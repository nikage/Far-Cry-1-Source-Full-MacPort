////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalShaderManager.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal shader management system
//               Handles Metal shader compilation and pipeline state creation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_SHADER_MANAGER_H
#define METAL_SHADER_MANAGER_H

#if defined(__APPLE__) && defined(__MACH__)

#include <Metal/Metal.h>
#include <map>
#include <string>

// Shader types supported by the Metal renderer
enum class MetalShaderType
{
    Vertex,
    Fragment,
    Compute
};

// Pipeline state cache entry
struct MetalPipelineState
{
    id<MTLRenderPipelineState> pipelineState;
    id<MTLFunction> vertexFunction;
    id<MTLFunction> fragmentFunction;
    std::string vertexShaderName;
    std::string fragmentShaderName;
    
    MetalPipelineState() : pipelineState(nil), vertexFunction(nil), fragmentFunction(nil) {}
    
    ~MetalPipelineState()
    {
        if (pipelineState) [pipelineState release];
        if (vertexFunction) [vertexFunction release];
        if (fragmentFunction) [fragmentFunction release];
    }
};

// Uniform buffer structure for shaders
struct MetalUniforms
{
    matrix_float4x4 modelViewProjectionMatrix;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 normalMatrix;
    vector_float3 lightPos;
    vector_float3 viewPos;
    vector_float4 lightColor;
    vector_float4 materialColor;
};

class CMetalShaderManager
{
public:
    CMetalShaderManager();
    ~CMetalShaderManager();
    
    // Initialization
    bool Initialize(id<MTLDevice> device);
    void Shutdown();
    
    // Shader loading and compilation
    id<MTLFunction> LoadShaderFunction(const std::string& functionName, MetalShaderType type);
    bool CompileShaderLibrary(const std::string& source);
    bool LoadShaderLibraryFromFile(const std::string& filename);
    
    // Pipeline state management
    id<MTLRenderPipelineState> GetPipelineState(const std::string& vertexShader, 
                                               const std::string& fragmentShader,
                                               MTLPixelFormat colorFormat = MTLPixelFormatBGRA8Unorm,
                                               MTLPixelFormat depthFormat = MTLPixelFormatDepth32Float);
    
    id<MTLRenderPipelineState> CreatePipelineState(const std::string& vertexShader,
                                                   const std::string& fragmentShader,
                                                   MTLPixelFormat colorFormat,
                                                   MTLPixelFormat depthFormat);
    
    // Predefined shader functions
    id<MTLFunction> GetBasicVertexShader() { return LoadShaderFunction("basic_vertex", MetalShaderType::Vertex); }
    id<MTLFunction> GetBasicFragmentShader() { return LoadShaderFunction("basic_fragment", MetalShaderType::Fragment); }
    id<MTLFunction> GetUnlitFragmentShader() { return LoadShaderFunction("unlit_fragment", MetalShaderType::Fragment); }
    id<MTLFunction> GetSolidColorFragmentShader() { return LoadShaderFunction("solid_color_fragment", MetalShaderType::Fragment); }
    
    // Uniform buffer management
    id<MTLBuffer> CreateUniformBuffer(const MetalUniforms& uniforms);
    void UpdateUniformBuffer(id<MTLBuffer> buffer, const MetalUniforms& uniforms);
    
    // Utility methods
    bool IsInitialized() const { return m_device != nil && m_library != nil; }
    id<MTLDevice> GetDevice() const { return m_device; }
    
protected:
    id<MTLDevice> m_device;
    id<MTLLibrary> m_library;
    
    // Cache for compiled functions and pipeline states
    std::map<std::string, id<MTLFunction>> m_functionCache;
    std::map<std::string, MetalPipelineState*> m_pipelineCache;
    
    // Internal methods
    std::string GeneratePipelineCacheKey(const std::string& vertexShader,
                                        const std::string& fragmentShader,
                                        MTLPixelFormat colorFormat,
                                        MTLPixelFormat depthFormat);
    
    void ClearCaches();
    
private:
    bool m_initialized;
};

// Utility functions for matrix operations
matrix_float4x4 CreateMatrix4x4(float m[16]);
matrix_float4x4 CreateIdentityMatrix();
matrix_float4x4 CreatePerspectiveMatrix(float fov, float aspect, float nearZ, float farZ);
matrix_float4x4 CreateLookAtMatrix(vector_float3 eye, vector_float3 center, vector_float3 up);
matrix_float4x4 CreateTranslationMatrix(vector_float3 translation);
matrix_float4x4 CreateRotationMatrix(vector_float3 axis, float angle);
matrix_float4x4 CreateScaleMatrix(vector_float3 scale);
matrix_float4x4 MultiplyMatrices(const matrix_float4x4& a, const matrix_float4x4& b);

#endif // __APPLE__ && __MACH__

#endif // METAL_SHADER_MANAGER_H
