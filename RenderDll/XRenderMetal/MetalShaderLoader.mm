////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalShaderLoader.cpp
//  Version:     v1.00 - Phase 2 Implementation
//  Created:     30/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Shader loading and compilation for Phase 2
//               Includes initialization of default shader library
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalShaderManager.m"
#include "MetalBaseRenderer.m"
#include "MetalVertexDescriptor.m"
#include "MetalStateCache.m"
#include <Cocoa/Cocoa.h>
#include <fstream>
#include <sstream>
#include <cassert>

CMetalShaderManager::CMetalShaderManager(CMetalBaseRenderer* renderer, 
                                        CMetalTextureManager* textureManager)
    : m_renderer(renderer)
    , m_textureManager(textureManager)
    , m_nextShaderId(1)
    , m_currentShaderId(0)
    , m_currentPipelineState(nil)
    , m_globalShaderTemplateId(0)
    , m_heatVisionEnabled(false)
    , m_generatedLibrary(nil)
{
    assert(renderer != nullptr && "CMetalShaderManager: renderer cannot be null!");
    assert(textureManager != nullptr && "CMetalShaderManager: textureManager cannot be null!");
    assert(renderer->m_device != nil && "CMetalShaderManager: renderer must have valid Metal device!");
    assert(m_nextShaderId == 1 && "CMetalShaderManager: shader ID counter must start at 1!");
    
    iLog->Log("MetalShaderManager: Initializing...\n");
    
    if (!InitializeDefaultShaderLibrary())
    {
        iLog->Log("Warning: Failed to initialize default shader library\n");
    }
    
    iLog->Log("MetalShaderManager: Initialization complete (%zu shaders loaded)\n", m_shaders.size());
}

CMetalShaderManager::~CMetalShaderManager()
{
    assert(m_renderer != nullptr && "CMetalShaderManager: renderer should not be null during destruction!");
    assert(m_textureManager != nullptr && "CMetalShaderManager: textureManager should not be null during destruction!");
    
    iLog->Log("MetalShaderManager: Shutting down...\n");
    ClearAllShaders();
    
    assert(m_shaders.empty() && "CMetalShaderManager: all shaders should be cleared!");
    assert(m_shaderNameMap.empty() && "CMetalShaderManager: shader name map should be cleared!");
}

bool CMetalShaderManager::InitializeDefaultShaderLibrary()
{
    assert(m_renderer != nullptr && "InitializeDefaultShaderLibrary: renderer cannot be null!");
    assert(m_renderer->m_device != nil && "InitializeDefaultShaderLibrary: Metal device cannot be null!");
    
    if (!m_renderer || !m_renderer->m_device)
    {
        iLog->Log("Error: No Metal device available\n");
        return false;
    }
    
    NSError* error = nil;
    
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* shaderPath = [bundle pathForResource:@"BasicShaders" ofType:@"metallib"];
    
    id<MTLLibrary> defaultLibrary = nil;
    
    if (shaderPath)
    {
        iLog->Log("Loading shader library from: %s\n", [shaderPath UTF8String]);
        defaultLibrary = [m_renderer->m_device newLibraryWithFile:shaderPath error:&error];
    }
    
    if (!defaultLibrary)
    {
        // Try loading from app bundle MacOS directory (where we copy the metallibs)
        NSString* exePath = [[NSBundle mainBundle] executablePath];
        NSString* exeDir = [exePath stringByDeletingLastPathComponent];
        NSString* metallibPath = [exeDir stringByAppendingPathComponent:@"BasicShaders.metallib"];
        
        iLog->Log("Attempting to load from executable directory: %s\n", [metallibPath UTF8String]);
        defaultLibrary = [m_renderer->m_device newLibraryWithFile:metallibPath error:&error];
    }
    
    if (!defaultLibrary)
    {
        iLog->Log("Attempting to load default library...\n");
        defaultLibrary = [m_renderer->m_device newDefaultLibrary];
    }
    
    if (!defaultLibrary)
    {
        iLog->Log("Error: Failed to create shader library: %s\n",
               error ? [[error localizedDescription] UTF8String] : "Unknown error");
        return false;
    }
    
    iLog->Log("Shader library loaded successfully\n");
    
    CreateDefaultShaders(defaultLibrary);
    LoadGeneratedShaders(defaultLibrary);
    if (iLog)
    {
        for (const auto& kv : m_shaderNameMap)
        {
            iLog->Log("MetalShaderManager: base shader '%s' has id=%d\n", kv.first.c_str(), kv.second);
        }
    }
    InitializeShaderFallbacks();
    
    return true;
}

void CMetalShaderManager::CreateDefaultShaders(id<MTLLibrary> library)
{
    assert(library != nil && "CreateDefaultShaders: library cannot be null!");
    assert(m_renderer != nullptr && "CreateDefaultShaders: renderer cannot be null!");
    assert(m_renderer->m_device != nil && "CreateDefaultShaders: Metal device cannot be null!");
    
    if (!library)
        return;
    
    struct ShaderPair {
        const char* name;
        const char* vertexFunc;
        const char* fragmentFunc;
        int vertexFormat;
    };
    
    ShaderPair defaultShaders[] = {
        {"simple",     "simple_vertex",     "simple_fragment",     VERTEX_FORMAT_P3F},
        {"color",      "color_vertex",      "simple_fragment",     VERTEX_FORMAT_P3F_COL4UB},
        {"colortex",   "colortex_vertex",   "colortex_fragment",   VERTEX_FORMAT_P3F_COL4UB_TEX2F},
        {"basic",      "basic_vertex",      "basic_fragment",      VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
        {"unlit",      "basic_vertex",      "unlit_fragment",      VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
        {"terrain",    "terrain_vertex",    "terrain_fragment",    VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
        {"sky",        "sky_vertex",        "sky_fragment",        VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
    };
    
    for (const auto& shader : defaultShaders)
    {
        assert(shader.name != nullptr && "CreateDefaultShaders: shader name cannot be null!");
        assert(shader.vertexFunc != nullptr && "CreateDefaultShaders: vertex function name cannot be null!");
        assert(shader.fragmentFunc != nullptr && "CreateDefaultShaders: fragment function name cannot be null!");
        
        id<MTLFunction> vertexFunc = [library newFunctionWithName:@(shader.vertexFunc)];
        id<MTLFunction> fragmentFunc = [library newFunctionWithName:@(shader.fragmentFunc)];
        
        assert(vertexFunc != nil && fragmentFunc != nil && 
               "CreateDefaultShaders: Failed to load shader functions - shader library may be missing or outdated");
        
        MTLVertexDescriptor* vertexDesc = CMetalVertexDescriptorHelper::CreateVertexDescriptor(shader.vertexFormat);
        assert(vertexDesc != nil && "CreateDefaultShaders: Failed to create vertex descriptor - invalid vertex format");
        
        id<MTLRenderPipelineState> pipelineState = CreatePipelineStateWithFunctions(
            vertexFunc, fragmentFunc, vertexDesc);
        
        assert(pipelineState != nil && "CreateDefaultShaders: Failed to create pipeline state");
        
        int shaderId = AllocateShaderId();
        assert(shaderId > 0 && "CreateDefaultShaders: shader ID must be positive!");
        
        ShaderInfo info;
        info.vertexFunction = vertexFunc;
        info.fragmentFunction = fragmentFunc;
        info.pipelineState = pipelineState;
        info.name = shader.name;
        info.shaderClass = eSH_World;
        info.isLoaded = true;
        info.nMaskGen = 0;
        info.shaderWrapper = new CMetalShader(shaderId, this);
        
        m_shaders[shaderId] = info;
        m_shaderNameMap[shader.name] = shaderId;
        
        assert(m_shaders.find(shaderId) != m_shaders.end() && "CreateDefaultShaders: shader should be in map!");
        assert(m_shaderNameMap.find(shader.name) != m_shaderNameMap.end() && "CreateDefaultShaders: shader name should be in map!");
        
        iLog->Log("  Loaded shader: %s (ID: %d)\n", shader.name, shaderId);
    }
    
    iLog->Log("Default shaders created: %zu shaders\n", m_shaders.size());
}

void CMetalShaderManager::LoadGeneratedShaders(id<MTLLibrary> vertexLibrary)
{
    if (!m_renderer || !m_renderer->m_device)
        return;

    NSError* error = nil;
    id<MTLLibrary> generatedLibrary = nil;
    NSBundle* bundle = [NSBundle mainBundle];
    if (bundle)
    {
        NSString* resourcePath = [bundle pathForResource:@"GeneratedShaders" ofType:@"metallib"];
        if (resourcePath)
        {
            generatedLibrary = [m_renderer->m_device newLibraryWithFile:resourcePath error:&error];
        }
    }

    if (!generatedLibrary)
    {
        NSString* exePath = [[NSBundle mainBundle] executablePath];
        NSString* exeDir = [exePath stringByDeletingLastPathComponent];
        NSString* metallibPath = [exeDir stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
        generatedLibrary = [m_renderer->m_device newLibraryWithFile:metallibPath error:&error];
        if (!generatedLibrary)
        {
            NSString* sourcePath = [NSString stringWithUTF8String:"RenderDll/XRenderMetal/Generated/GeneratedShaders.metallib"];
            generatedLibrary = [m_renderer->m_device newLibraryWithFile:sourcePath error:&error];
        }
    }

    if (!generatedLibrary)
    {
        if (iLog)
            iLog->Log("MetalShaderManager: Generated shader library not found (%s)\n", error ? [[error localizedDescription] UTF8String] : "unknown error");
        return;
    }

    m_generatedLibrary = generatedLibrary;

    NSString* manifestPath = nil;
    if (bundle)
    {
        manifestPath = [bundle pathForResource:@"generated_manifest" ofType:@"json"];
    }
    if (!manifestPath)
    {
        NSString* exePath = [[NSBundle mainBundle] executablePath];
        NSString* exeDir = [exePath stringByDeletingLastPathComponent];
        NSString* candidate = [exeDir stringByAppendingPathComponent:@"generated_manifest.json"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate])
            manifestPath = candidate;
        else
            manifestPath = [NSString stringWithUTF8String:"RenderDll/XRenderMetal/Generated/generated_manifest.json"];
    }

    NSData* manifestData = manifestPath ? [NSData dataWithContentsOfFile:manifestPath] : nil;
    if (!manifestData)
    {
        if (iLog)
            iLog->Log("MetalShaderManager: Generated shader manifest not found");
        return;
    }

    NSError* jsonError = nil;
    id manifestJson = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&jsonError];
    if (!manifestJson || ![manifestJson isKindOfClass:[NSArray class]])
    {
        if (iLog)
            iLog->Log("MetalShaderManager: Failed to parse generated shader manifest (%s)", jsonError ? [[jsonError localizedDescription] UTF8String] : "unknown error");
        return;
    }

    NSArray* entries = (NSArray*)manifestJson;
    for (NSDictionary* entry in entries)
    {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;

        NSString* shaderName = entry[@"shader"];
        NSString* normalizedName = entry[@"normalized"];
        NSString* fragmentName = entry[@"fragment"];
        NSNumber* textureCountValue = entry[@"textureCount"];

        if (!shaderName || !fragmentName)
            continue;

        std::string normalizedKey;
        if (normalizedName && [normalizedName length] > 0)
            normalizedKey = NormalizeShaderName([normalizedName UTF8String]);
        else
            normalizedKey = NormalizeShaderName([shaderName UTF8String]);

        id<MTLFunction> fragmentFunction = [generatedLibrary newFunctionWithName:fragmentName];
        if (!fragmentFunction)
        {
            if (iLog)
                iLog->Log("MetalShaderManager: Missing generated fragment function '%s'\n", [fragmentName UTF8String]);
            continue;
        }

        int textureCount = textureCountValue ? textureCountValue.intValue : 0;
        NSString* vertexFunctionName = textureCount > 0 ? @"colortex_vertex" : @"color_vertex";
        int vertexFormat = textureCount > 0 ? VERTEX_FORMAT_P3F_COL4UB_TEX2F : VERTEX_FORMAT_P3F_COL4UB;
        id<MTLFunction> vertexFunction = nil;

        if (vertexLibrary)
        {
            vertexFunction = [vertexLibrary newFunctionWithName:vertexFunctionName];
            if (!vertexFunction)
                vertexFunction = [vertexLibrary newFunctionWithName:@"basic_vertex"];
        }

        if (!vertexFunction)
        {
            if (iLog)
                iLog->Log("MetalShaderManager: Missing generated vertex function for shader '%s'\n", [shaderName UTF8String]);
            continue;
        }

        MTLVertexDescriptor* descriptor = CMetalVertexDescriptorHelper::CreateVertexDescriptor(vertexFormat);
        if (!descriptor)
            continue;

        id<MTLRenderPipelineState> pipelineState = CreatePipelineStateWithFunctions(vertexFunction, fragmentFunction, descriptor);
        if (!pipelineState)
            continue;

        auto existing = m_shaderNameMap.find(normalizedKey);
        if (existing != m_shaderNameMap.end())
        {
            ReleaseShaderId(existing->second);
        }

        int shaderId = AllocateShaderId();
        ShaderInfo info;
        info.vertexFunction = vertexFunction;
        info.fragmentFunction = fragmentFunction;
        info.pipelineState = pipelineState;
        info.name = normalizedKey;
        info.shaderClass = eSH_Misc;
        info.isLoaded = true;
        info.nMaskGen = 0;
        info.shaderWrapper = new CMetalShader(shaderId, this);

        m_shaders[shaderId] = info;
        m_shaderNameMap[normalizedKey] = shaderId;

        if (iLog)
            iLog->Log("MetalShaderManager: Registered generated shader '%s' (id=%d)\n", [shaderName UTF8String], shaderId);
    }
}

id<MTLRenderPipelineState> CMetalShaderManager::CreatePipelineStateWithFunctions(
    id<MTLFunction> vertexFunction,
    id<MTLFunction> fragmentFunction,
    MTLVertexDescriptor* vertexDescriptor)
{
    assert(vertexFunction != nil && "CreatePipelineStateWithFunctions: vertexFunction cannot be nil");
    assert(fragmentFunction != nil && "CreatePipelineStateWithFunctions: fragmentFunction cannot be nil");
    assert(vertexDescriptor != nil && "CreatePipelineStateWithFunctions: vertexDescriptor cannot be nil");
    
    assert(m_renderer != nullptr && "CreatePipelineStateWithFunctions: renderer cannot be null!");
    assert(m_renderer->m_device != nil && "CreatePipelineStateWithFunctions: Metal device cannot be nil!");
    
    if (!m_renderer || !m_renderer->m_device)
        return nil;
    
    MTLPixelFormat colorFormat = MTLPixelFormatBGRA8Unorm;
    MTLPixelFormat depthFormat = MTLPixelFormatDepth32Float;
    
    MetalPipelineStateKey key;
    key.vertexFunctionHash = (uint64_t)vertexFunction;
    key.fragmentFunctionHash = (uint64_t)fragmentFunction;
    key.vertexFormatHash = 0;
    key.renderStateHash = 0;
    key.colorPixelFormat = colorFormat;
    key.depthPixelFormat = depthFormat;
    
    if (m_renderer->m_stateCache && vertexFunction && fragmentFunction && vertexDescriptor) // Only cache if functions are valid
    {
        id<MTLRenderPipelineState> cachedState = m_renderer->m_stateCache->GetOrCreatePipelineState(
                key, vertexFunction, fragmentFunction, vertexDescriptor);

        if (cachedState)
            return cachedState;
    }
    
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.vertexDescriptor = vertexDescriptor;
    
    descriptor.colorAttachments[0].pixelFormat = colorFormat;
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    
    descriptor.depthAttachmentPixelFormat = depthFormat;
    
    NSError* error = nil;
    id<MTLRenderPipelineState> pipelineState = 
        [m_renderer->m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    
    assert(pipelineState != nil && "CreatePipelineStateWithFunctions: Failed to create pipeline state - check Metal shader compilation");
    if (!pipelineState && error)
    {
        iLog->Log("Error details: %s\n", [[error localizedDescription] UTF8String]);
    }
    
    return pipelineState;
}

id<MTLRenderPipelineState> CMetalShaderManager::CreatePipelineState(
    id<MTLFunction> vertexFunction,
    id<MTLFunction> fragmentFunction,
    MTLVertexDescriptor* vertexDescriptor)
{
    assert(vertexFunction != nil && "CreatePipelineState: vertexFunction cannot be nil!");
    assert(fragmentFunction != nil && "CreatePipelineState: fragmentFunction cannot be nil!");
    assert(vertexDescriptor != nil && "CreatePipelineState: vertexDescriptor cannot be nil!");
    
    return CreatePipelineStateWithFunctions(vertexFunction, fragmentFunction, vertexDescriptor);
}

void CMetalShaderManager::SetShaderUniforms(id<MTLRenderCommandEncoder> encoder, 
                                           const SShaderParam& params)
{
    assert(encoder != nil && "SetShaderUniforms: encoder cannot be nil!");
    assert(m_renderer != nullptr && "SetShaderUniforms: renderer cannot be null!");
    
    if (!encoder || !m_renderer)
        return;
    
    m_renderer->UpdateUniformBuffer();
    
    if (m_renderer->m_uniformBuffer)
    {
        [encoder setVertexBuffer:m_renderer->m_uniformBuffer offset:0 atIndex:1];
        [encoder setFragmentBuffer:m_renderer->m_uniformBuffer offset:0 atIndex:0];
    }
}

int CMetalShaderManager::AllocateShaderId()
{
    int id = m_nextShaderId++;
    assert(id > 0 && "AllocateShaderId: shader ID must be positive!");
    assert(m_nextShaderId > id && "AllocateShaderId: shader ID counter overflow!");
    return id;
}

void CMetalShaderManager::ReleaseShaderId(int id)
{
    assert(id > 0 && "ReleaseShaderId: shader ID must be positive!");
    
    auto it = m_shaders.find(id);
    if (it != m_shaders.end())
    {
        ShaderInfo& info = it->second;
        info.shaderWrapper = nullptr;
        
        std::string nameToRemove = info.name;
        m_shaders.erase(it);
        
        auto nameIt = m_shaderNameMap.find(nameToRemove);
        if (nameIt != m_shaderNameMap.end() && nameIt->second == id)
        {
            m_shaderNameMap.erase(nameIt);
        }
    }
}

void CMetalShaderManager::ClearAllShaders()
{
    for (auto& pair : m_shaders)
    {
        ShaderInfo& info = pair.second;
        if (info.shaderWrapper)
        {
            info.shaderWrapper->m_manager = nullptr;
            info.shaderWrapper->Release(true);
            info.shaderWrapper = nullptr;
        }
    }
    
    m_shaders.clear();
    m_shaderNameMap.clear();
    m_nextShaderId = 1;
    m_currentShaderId = 0;
    m_currentPipelineState = nil;
}

void CMetalShaderManager::ShareCacheWith(CMetalShaderManager* other)
{
    if (!other || other == this)
        return;
    
    for (const auto& shaderPair : other->m_shaders) {
        const ShaderInfo& shaderInfo = shaderPair.second;
        
        if (!shaderInfo.name.empty()) {
            auto nameIt = m_shaderNameMap.find(shaderInfo.name);
            if (nameIt == m_shaderNameMap.end()) {
                int newShaderId = AllocateShaderId();
                ShaderInfo info = shaderInfo;
                info.shaderWrapper = new CMetalShader(newShaderId, this);
                m_shaders[newShaderId] = info;
                m_shaderNameMap[shaderInfo.name] = newShaderId;
            }
        }
    }
    
    for (const auto& shaderPair : m_shaders) {
        const ShaderInfo& shaderInfo = shaderPair.second;
        
        if (!shaderInfo.name.empty()) {
            auto nameIt = other->m_shaderNameMap.find(shaderInfo.name);
            if (nameIt == other->m_shaderNameMap.end()) {
                int newShaderId = other->AllocateShaderId();
                ShaderInfo info = shaderInfo;
                info.shaderWrapper = new CMetalShader(newShaderId, other);
                other->m_shaders[newShaderId] = info;
                other->m_shaderNameMap[shaderInfo.name] = newShaderId;
            }
        }
    }
}

int CMetalShaderManager::GetShaderCount() const
{
    return static_cast<int>(m_shaders.size());
}

void CMetalShaderManager::SetGlobalShaderTemplateId(int nTemplateId)
{
    m_globalShaderTemplateId = nTemplateId;
}

int CMetalShaderManager::GetGlobalShaderTemplateId() const
{
    return m_globalShaderTemplateId;
}

void CMetalShaderManager::EF_EnableHeatVision(bool bEnable)
{
    m_heatVisionEnabled = bEnable;
}

bool CMetalShaderManager::EF_GetHeatVision()
{
    return m_heatVisionEnabled;
}

void CMetalShaderManager::EF_PolygonOffset(bool bEnable, float fFactor, float fUnits)
{
    assert(m_renderer != nullptr && "EF_PolygonOffset: renderer cannot be null!");
    
    if (!m_renderer || !m_renderer->m_renderEncoder)
        return;
    
    if (bEnable)
    {
        [m_renderer->m_renderEncoder setDepthBias:fUnits slopeScale:fFactor clamp:0.0f];
    }
    else
    {
        [m_renderer->m_renderEncoder setDepthBias:0.0f slopeScale:0.0f clamp:0.0f];
    }
}

id<MTLRenderPipelineState> CMetalShaderManager::GetPipelineStateForShader(const char* shaderName)
{
    assert(shaderName != nullptr && "GetPipelineStateForShader: shaderName cannot be null!");
    
    if (!shaderName)
        return nil;
    
    auto it = m_shaderNameMap.find(shaderName);
    if (it != m_shaderNameMap.end())
    {
        int shaderId = it->second;
        auto shaderIt = m_shaders.find(shaderId);
        if (shaderIt != m_shaders.end())
        {
            return shaderIt->second.pipelineState;
        }
    }
    
    return nil;
}

id<MTLRenderPipelineState> CMetalShaderManager::GetPipelineStateForFormat(int vertexFormat)
{
    const char* shaderName = "colortex";
    
    switch (vertexFormat)
    {
        case VERTEX_FORMAT_P3F:
            shaderName = "simple";
            break;
        case VERTEX_FORMAT_P3F_COL4UB:
            shaderName = "color";
            break;
        case VERTEX_FORMAT_P3F_COL4UB_TEX2F:
        case VERTEX_FORMAT_P3F_N_COL4UB_TEX2F:
            shaderName = "colortex";
            break;
        default:
            shaderName = "basic";
            break;
    }
    
    return GetPipelineStateForShader(shaderName);
}

#endif

