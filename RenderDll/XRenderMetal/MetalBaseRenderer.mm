////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalBaseRenderer.cpp
//  Version:     v1.00 - Phase 1 Complete Implementation
//  Created:     30/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Complete Phase 1 implementation with:
//               - Command buffer management with triple buffering
//               - Vertex/Index buffer system with pooling
//               - Pipeline state management with caching
//               - Matrix stack and viewport transforms
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalBaseRenderer.m"
#include "I3DEngine.h"
#include "VertexFormats.h"
#include <Cocoa/Cocoa.h>
#include <cstring>
#include <cmath>
#include <algorithm>

#ifdef max
#undef max
#endif
#ifdef min
#undef min
#endif

extern ITimer* iTimer;

CMetalBaseRenderer::CMetalBaseRenderer()
    : m_device(nil)
    , m_commandQueue(nil)
    , m_renderEncoder(nil)
    , m_metalView(nil)
    , m_metalLayer(nil)
    , m_currentCommandBuffer(nil)
    , m_renderPassDescriptor(nil)
    , m_currentDrawable(nil)
    , m_currentPipelineState(nil)
    , m_currentDepthStencilState(nil)
    , m_numActiveRenderTargets(1)
    , m_isInitialized(false)
    , m_width(0)
    , m_height(0)
    , m_cbpp(32)
    , m_zbpp(24)
    , m_sbpp(8)
    , m_fullscreen(false)
    , m_nextVertexBufferId(1)
    , m_nextIndexBufferId(1)
    , m_depthTestEnabled(true)
    , m_depthWriteEnabled(true)
    , m_depthFunction(MTLCompareFunctionLess)
    , m_blendingEnabled(false)
    , m_sourceBlendFactor(MTLBlendFactorOne)
    , m_destBlendFactor(MTLBlendFactorZero)
    , m_blendOperation(MTLBlendOperationAdd)
    , m_sourceAlphaBlendFactor(MTLBlendFactorOne)
    , m_destAlphaBlendFactor(MTLBlendFactorZero)
    , m_alphaBlendOperation(MTLBlendOperationAdd)
    , m_colorWriteMask(MTLColorWriteMaskAll)
    , m_viewportX(0)
    , m_viewportY(0)
    , m_viewportWidth(0)
    , m_viewportHeight(0)
    , m_matrixDirty(true)
    , m_currentFrameIndex(0)
    , m_currentDynamicVBPool(0)
    , m_uniformBuffer(nil)
    , m_uniformBufferCPU(nullptr)
    , m_materialBuffer(nil)
    , m_materialBufferCPU(nullptr)
    , m_waterNoiseBuffer(nil)
    , m_hdrColorRT(nil)
    , m_hdrDepthRT(nil)
    , m_hdrToneMapPSO(nil)
    , m_hdrSampler(nil)
    , m_hdrEnabled(false)
    , m_hdrRTWidth(0)
    , m_hdrRTHeight(0)
    , m_bloomBrightRT(nil)
    , m_bloomBlurHRT(nil)
    , m_bloomBlurVRT(nil)
    , m_hdrBrightPassPSO(nil)
    , m_hdrBlurHPSO(nil)
    , m_hdrBlurVPSO(nil)
    , m_currentState(0)
    , m_currentCullMode(R_CULL_BACK)
    , m_fogEnabled(false)
    , m_texGenEnabled(false)
    , m_texGenScaleX(1.0f)
    , m_texGenScaleY(1.0f)
    , m_texGenTranslateX(0.0f)
    , m_texGenTranslateY(0.0f)
    , m_texGen3D{}
    , m_lodBias(0.0f)
    , m_vSyncEnabled(true)
    , m_shaderNeedsTangents(false)
    , m_currentTMU(0)
    , m_clipPlaneEnabled(false)
    , m_clipPlaneRefract(false)
    , m_frameID(0)
    , m_numDrawCalls(0)
    , m_numTriangles(0)
{
    m_currentMatrix.SetIdentity();
    m_viewMatrix.SetIdentity();
    m_projectionMatrix.SetIdentity();
    m_modelViewProjectionMatrix.SetIdentity();
    
    // Initialize clip plane parameters
    m_clipPlaneParams[0] = 0.0f;
    m_clipPlaneParams[1] = 0.0f;
    m_clipPlaneParams[2] = 0.0f;
    m_clipPlaneParams[3] = 0.0f;
    
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; ++i)
    {
        m_commandBufferPool[i] = nil;
        m_frameSemaphores[i] = nullptr;
    }
    
    for (int i = 0; i < NUM_DYNAMIC_VB_POOLS; ++i)
    {
        m_dynamicVBPools[i].buffer = nil;
        m_dynamicVBPools[i].size = 0;
        m_dynamicVBPools[i].offset = 0;
        m_dynamicVBPools[i].cpuData = nullptr;
    }

    m_nFrameID = 0;
    m_nFrameUpdateID = 0;
}

CMetalBaseRenderer::~CMetalBaseRenderer()
{
    ShutDown();
}

WIN_HWND CMetalBaseRenderer::Init(int x, int y, int width, int height, unsigned int cbpp, 
                                 int zbpp, int sbits, bool fullscreen, WIN_HINSTANCE hinst, 
                                 WIN_HWND Glhwnd, WIN_HDC Glhdc, WIN_HGLRC hGLrc, bool bReInit)
{
    iLog->Log("Metal Base Renderer Init: %dx%d, %dbpp color, %dbpp depth\n",
           width, height, cbpp, zbpp);
    
    m_width = width;
    m_height = height;
    m_cbpp = cbpp;
    m_zbpp = zbpp;
    m_sbpp = sbits;
    m_fullscreen = fullscreen;
    m_viewportWidth = width;
    m_viewportHeight = height;
    
    if (!InitializeDevice())
    {
        iLog->LogError("Failed to initialize Metal device\n");
        return nullptr;
    }
    
    if (!InitializeCommandQueue())
    {
        iLog->LogError("Failed to initialize Metal command queue\n");
        return nullptr;
    }
    
    if (!InitializeCommandBufferPool())
    {
        iLog->LogError("Failed to initialize command buffer pool\n");
        return nullptr;
    }
    
    if (!InitializeDynamicVBPools())
    {
        iLog->LogError("Failed to initialize dynamic VB pools\n");
        return nullptr;
    }
    
    if (!InitializeUniformBuffers())
    {
        iLog->LogError("Failed to initialize uniform buffers\n");
        return nullptr;
    }
    
    if (!InitializeDepthStencilTextures())
    {
        iLog->LogError("Failed to initialize depth/stencil textures\n");
        return nullptr;
    }
    
    m_stateCache = std::make_unique<CMetalStateCache>(m_device);
    if (!m_stateCache)
    {
        iLog->LogError("Failed to create state cache\n");
        return nullptr;
    }
    
    if (!InitializeRenderPipeline())
    {
        iLog->LogError("Failed to initialize Metal render pipeline\n");
        return nullptr;
    }
    
    m_isInitialized = true;
    iLog->Log("Metal base renderer initialized successfully\n");
    iLog->Log("  Device: %s\n", [[m_device name] UTF8String]);
    const MTLSize tgSize = [m_device maxThreadsPerThreadgroup];
    iLog->Log("  Max threadgroup size: %lu x %lu x %lu\n",
              static_cast<unsigned long>(tgSize.width),
              static_cast<unsigned long>(tgSize.height),
              static_cast<unsigned long>(tgSize.depth));
    iLog->Log("  Triple buffering: enabled (%d frames)\n", MAX_FRAMES_IN_FLIGHT);
    
    return (WIN_HWND)m_metalView;
}

void CMetalBaseRenderer::ShutDown(bool bReInit)
{
    if (!m_isInitialized)
        return;
    
    iLog->Log("Shutting down Metal base renderer\n");
    
    // Wait for all tracked command buffers to complete before cleanup
    WaitForAllCommandBuffers();
    
    CleanupCommandBufferPool();
    CleanupDynamicVBPools();
    CleanupUniformBuffers();
    CleanupDepthStencilTextures();
    ClearRenderPassCache();
    
    m_vertexBuffers.clear();
    m_indexBuffers.clear();
    m_renderTargets.fill(nil);
    m_numActiveRenderTargets = 1;
    
    m_stateCache.reset();
    
    if (m_renderEncoder)
    {
        [m_renderEncoder endEncoding];
        [m_renderEncoder release];
        m_renderEncoder = nil;
    }
    m_currentCommandBuffer = nil;
    if (m_renderPassDescriptor)
    {
        [m_renderPassDescriptor release];
        m_renderPassDescriptor = nil;
    }
    if (m_currentDrawable)
    {
        [m_currentDrawable release];
        m_currentDrawable = nil;
    }
    m_currentPipelineState = nil;
    m_currentDepthStencilState = nil;
    m_commandQueue = nil;
    m_blitCommandQueue = nil;
    m_device = nil;
    m_metalView = nil;
    m_metalLayer = nil;
    
    m_isInitialized = false;
}

void CMetalBaseRenderer::TrackCommandBuffer(id<MTLCommandBuffer> buffer)
{
    if (!buffer)
        return;
    
    // Check if buffer has already been committed - this would cause a crash
    if (buffer.status != MTLCommandBufferStatusNotEnqueued && 
        buffer.status != MTLCommandBufferStatusEnqueued) {
        iLog->LogError("TrackCommandBuffer: Cannot track command buffer in status %d (already committed)\n", (int)buffer.status);
        return;
    }
    
    std::lock_guard<std::mutex> lock(m_commandBufferMutex);
    
    // Add to tracking list
    m_activeCommandBuffers.push_back(buffer);
    iLog->Log("TrackCommandBuffer: Now tracking %zu command buffer(s)\n", m_activeCommandBuffers.size());
    
    // Add completion handler: remove from tracking list and accumulate GPU timing
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> completedBuffer) {
        std::lock_guard<std::mutex> lock(m_commandBufferMutex);

        auto it = std::find(m_activeCommandBuffers.begin(), m_activeCommandBuffers.end(), completedBuffer);
        if (it != m_activeCommandBuffers.end()) {
            m_activeCommandBuffers.erase(it);
        }

        // Accumulate GPU frame time into the atomic; drained on the render thread
        // at BeginFrame to avoid a data race on m_RP.m_PS.m_fFlushTime.
        const CFTimeInterval gpuMs = (completedBuffer.GPUEndTime - completedBuffer.GPUStartTime) * 1000.0;
        if (gpuMs > 0.0) {
            float prev = m_pendingGpuFlushMs.load(std::memory_order_relaxed);
            while (!m_pendingGpuFlushMs.compare_exchange_weak(
                       prev, prev + static_cast<float>(gpuMs),
                       std::memory_order_relaxed, std::memory_order_relaxed))
                ;
        }
    }];
}

void CMetalBaseRenderer::WaitForAllCommandBuffers()
{
    iLog->Log("Waiting for %zu active command buffers to complete...\n", m_activeCommandBuffers.size());
    
    // Make a copy to avoid holding lock during wait
    std::vector<id<MTLCommandBuffer>> buffersToWait;
    {
        std::lock_guard<std::mutex> lock(m_commandBufferMutex);
        buffersToWait = m_activeCommandBuffers;
    }
    
    // Wait for each buffer
    for (id<MTLCommandBuffer> buffer : buffersToWait) {
        [buffer waitUntilCompleted];
    }
    
    // Clear the list
    {
        std::lock_guard<std::mutex> lock(m_commandBufferMutex);
        m_activeCommandBuffers.clear();
    }
    
    iLog->Log("All command buffers completed\n");
}

bool CMetalBaseRenderer::InitializeDevice()
{
    m_device = MTLCreateSystemDefaultDevice();
    if (!m_device)
    {
        iLog->LogError("Metal is not supported on this device\n");
        return false;
    }
    
    iLog->Log("Metal device created: %s\n", [[m_device name] UTF8String]);
    return true;
}

bool CMetalBaseRenderer::InitializeCommandQueue()
{
    if (!m_device)
        return false;
        
    m_commandQueue = [m_device newCommandQueue];
    if (!m_commandQueue)
    {
        iLog->LogError("Failed to create Metal command queue\n");
        return false;
    }
    [m_commandQueue setLabel:@"FarCryCommandQueue"];

    m_blitCommandQueue = [m_device newCommandQueue];
    if (!m_blitCommandQueue)
    {
        iLog->LogError("Failed to create Metal blit command queue\n");
        return false;
    }
    [m_blitCommandQueue setLabel:@"FarCryBlitQueue"];

    return true;
}

bool CMetalBaseRenderer::InitializeCommandBufferPool()
{
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; ++i)
    {
        m_frameSemaphores[i] = dispatch_semaphore_create(1);
        if (!m_frameSemaphores[i])
        {
            iLog->LogError("Failed to create frame semaphore %d\n", i);
            return false;
        }
    }
    
    m_currentFrameIndex = 0;
    return true;
}

bool CMetalBaseRenderer::InitializeDynamicVBPools()
{
    const size_t poolSize = 4 * 1024 * 1024;
    
    for (int i = 0; i < NUM_DYNAMIC_VB_POOLS; ++i)
    {
        m_dynamicVBPools[i].buffer = [m_device newBufferWithLength:poolSize 
                                                           options:MTLResourceStorageModeShared];
        if (!m_dynamicVBPools[i].buffer)
        {
            iLog->LogError("Failed to create dynamic VB pool %d\n", i);
            return false;
        }
        
        m_dynamicVBPools[i].size = poolSize;
        m_dynamicVBPools[i].offset = 0;
        m_dynamicVBPools[i].cpuData = [m_dynamicVBPools[i].buffer contents];
    }
    
    iLog->Log("Dynamic VB pools created: %d pools of %zu MB each\n",
           NUM_DYNAMIC_VB_POOLS, poolSize / (1024 * 1024));
    return true;
}

bool CMetalBaseRenderer::InitializeUniformBuffers()
{
    size_t bufferSize = sizeof(UniformBufferData);
    
    m_uniformBuffer = [m_device newBufferWithLength:bufferSize 
                                            options:MTLResourceStorageModeShared];
    if (!m_uniformBuffer)
    {
        iLog->Log("Error: Failed to create uniform buffer\n");
        return false;
    }
    [m_uniformBuffer setLabel:@"GlobalUniforms"];
    
    m_uniformBufferCPU = (UniformBufferData*)[m_uniformBuffer contents];
    
    // Initialize uniform buffer with clean data
    if (m_uniformBufferCPU) {
        memset(m_uniformBufferCPU, 0, bufferSize);
        
        // Set identity matrices
        m_uniformBufferCPU->modelViewProjectionMatrix.SetIdentity();
        m_uniformBufferCPU->modelMatrix.SetIdentity();
        m_uniformBufferCPU->viewMatrix.SetIdentity();
        m_uniformBufferCPU->projectionMatrix.SetIdentity();
        
        // Initialize clip plane to disabled state
        m_uniformBufferCPU->clipEnabled = 0.0f;
        m_uniformBufferCPU->clipRefract = 0.0f;
        m_uniformBufferCPU->clipPlane[0] = 0.0f;
        m_uniformBufferCPU->clipPlane[1] = 0.0f;
        m_uniformBufferCPU->clipPlane[2] = 0.0f;
        m_uniformBufferCPU->clipPlane[3] = 0.0f;
        m_uniformBufferCPU->fogScale = 0.0f;
        m_uniformBufferCPU->fogBias  = 1.0f;
    }

    // Allocate the per-draw material uniform buffer (shared, small)
    size_t matSize = sizeof(MaterialUniformsData);
    m_materialBuffer = [m_device newBufferWithLength:matSize
                                            options:MTLResourceStorageModeShared];
    if (!m_materialBuffer) {
        iLog->Log("Error: Failed to create material uniform buffer\n");
        return false;
    }
    [m_materialBuffer setLabel:@"MaterialUniforms"];
    m_materialBufferCPU = (MaterialUniformsData*)[m_materialBuffer contents];
    if (m_materialBufferCPU) {
        memset(m_materialBufferCPU, 0, matSize);
        // Default white material
        m_materialBufferCPU->Ambient[0] = m_materialBufferCPU->Ambient[1] = m_materialBufferCPU->Ambient[2] = m_materialBufferCPU->Ambient[3] = 1.0f;
        m_materialBufferCPU->Diffuse[0] = m_materialBufferCPU->Diffuse[1] = m_materialBufferCPU->Diffuse[2] = m_materialBufferCPU->Diffuse[3] = 1.0f;
        m_materialBufferCPU->Specular[3] = 1.0f;
        m_materialBufferCPU->FogColor[3] = 1.0f;
    }

    // Build static water Perlin noise table (mirrors D3D c30..c95, 66 float4 entries)
    // Permutation table generated from classic Perlin noise permutation array
    static const float kPerlinPerm[256] = {
        151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,
        140,36,103,30,69,142,8,99,37,240,21,10,23,190,6,148,
        247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,
        57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,
        74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,
        60,211,133,230,220,105,92,41,55,46,245,40,244,102,143,54,
        65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,
        200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,
        52,217,226,250,124,123,5,202,38,147,118,126,255,82,85,212,
        207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,
        119,248,152,2,44,154,163,70,221,153,101,155,167,43,172,9,
        129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,
        218,246,97,228,251,34,242,193,238,210,144,12,191,179,162,241,
        81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,157,
        184,84,204,176,115,121,50,45,127,4,150,254,138,236,205,93,
        222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
    };
    struct WaterNoiseEntry { float x, y, z, w; };
    const int kNoiseCount = 66;
    m_waterNoiseBuffer = [m_device newBufferWithLength:kNoiseCount * sizeof(WaterNoiseEntry)
                                              options:MTLResourceStorageModeShared];
    if (m_waterNoiseBuffer) {
        WaterNoiseEntry* tbl = (WaterNoiseEntry*)[m_waterNoiseBuffer contents];
        for (int i = 0; i < kNoiseCount; ++i) {
            int p0 = (int)kPerlinPerm[(i * 4 + 0) & 0xFF];
            int p1 = (int)kPerlinPerm[(i * 4 + 1) & 0xFF];
            int p2 = (int)kPerlinPerm[(i * 4 + 2) & 0xFF];
            int p3 = (int)kPerlinPerm[(i * 4 + 3) & 0xFF];
            tbl[i].x = (p0 / 255.0f) * 2.0f - 1.0f;
            tbl[i].y = (p1 / 255.0f) * 2.0f - 1.0f;
            tbl[i].z = (p2 / 255.0f) * 2.0f - 1.0f;
            tbl[i].w = (p3 / 255.0f) * 2.0f - 1.0f;
        }
        [m_waterNoiseBuffer setLabel:@"WaterNoiseTable"];
    }
    
    return true;
}

bool CMetalBaseRenderer::InitializeRenderPipeline()
{
    return true;
}

void CMetalBaseRenderer::CleanupCommandBufferPool()
{
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; ++i)
    {
        if (m_frameSemaphores[i])
        {
            m_frameSemaphores[i] = nullptr;
        }
        m_commandBufferPool[i] = nil;
    }
}

void CMetalBaseRenderer::CleanupDynamicVBPools()
{
    for (int i = 0; i < NUM_DYNAMIC_VB_POOLS; ++i)
    {
        m_dynamicVBPools[i].buffer = nil;
        m_dynamicVBPools[i].cpuData = nullptr;
        m_dynamicVBPools[i].size = 0;
        m_dynamicVBPools[i].offset = 0;
    }
}

void CMetalBaseRenderer::CleanupUniformBuffers()
{
    m_uniformBuffer = nil;
    m_uniformBufferCPU = nullptr;
    m_materialBuffer = nil;
    m_materialBufferCPU = nullptr;
    m_waterNoiseBuffer = nil;
    m_hdrColorRT = nil;
    m_hdrDepthRT = nil;
    m_hdrToneMapPSO = nil;
    m_hdrSampler = nil;
    m_bloomBrightRT = nil;
    m_bloomBlurHRT  = nil;
    m_bloomBlurVRT  = nil;
    m_hdrBrightPassPSO = nil;
    m_hdrBlurHPSO      = nil;
    m_hdrBlurVPSO      = nil;
}

bool CMetalBaseRenderer::InitializeDepthStencilTextures()
{
    MTLTextureDescriptor* depthStencilDesc = [MTLTextureDescriptor 
        texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float_Stencil8
                                     width:m_width
                                    height:m_height
                                 mipmapped:NO];
    depthStencilDesc.usage = MTLTextureUsageRenderTarget;
    depthStencilDesc.storageMode = MTLStorageModePrivate;
    
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; ++i)
    {
        m_depthStencilTextures[i] = [m_device newTextureWithDescriptor:depthStencilDesc];
        if (!m_depthStencilTextures[i])
        {
            iLog->LogError("Failed to create depth/stencil texture %d\n", i);
            return false;
        }
    }
    
    iLog->Log("Depth/stencil textures created: %dx%d, format=Depth32Float_Stencil8\n", 
              m_width, m_height);
    return true;
}

void CMetalBaseRenderer::CleanupDepthStencilTextures()
{
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; ++i)
    {
        if (m_depthStencilTextures[i])
        {
            [m_depthStencilTextures[i] release];
            m_depthStencilTextures[i] = nil;
        }
    }
}

MTLRenderPassDescriptor* CMetalBaseRenderer::CreateRenderPassDescriptor(id<MTLTexture> colorTexture, id<MTLTexture> depthStencilTexture)
{
    return GetOrCreateRenderPassDescriptor(colorTexture, depthStencilTexture, 
                                           MTLLoadActionClear, MTLLoadActionClear, MTLLoadActionClear);
}

MTLRenderPassDescriptor* CMetalBaseRenderer::GetOrCreateRenderPassDescriptor(id<MTLTexture> colorTexture, 
                                                                              id<MTLTexture> depthStencilTexture,
                                                                              MTLLoadAction colorLoad,
                                                                              MTLLoadAction depthLoad,
                                                                              MTLLoadAction stencilLoad)
{
    // RenderPassCacheKey key;
    // key.hasDepth = (depthStencilTexture != nil);
    // key.hasStencil = (depthStencilTexture != nil);
    // key.colorLoadAction = colorLoad;
    // key.depthLoadAction = depthLoad;
    // key.stencilLoadAction = stencilLoad;
    //
    // auto it = m_renderPassCache.find(key);
    // if (it != m_renderPassCache.end())
    // {
    //     MTLRenderPassDescriptor* cachedDesc = it->second;
    //     if (colorTexture)
    //     {
    //         cachedDesc.colorAttachments[0].texture = colorTexture;
    //     }
    //     if (depthStencilTexture)
    //     {
    //         cachedDesc.depthAttachment.texture = depthStencilTexture;
    //         cachedDesc.stencilAttachment.texture = depthStencilTexture;
    //     }
    //     return cachedDesc;
    // }
    // TEMPORARY: Disable caching to avoid ARC memory management issues
    // MTLRenderPassDescriptor creation is lightweight, so this should be fine for now
    iLog->Log("GetOrCreateRenderPassDescriptor: Creating new descriptor (caching disabled)\n");
    
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    if (!renderPassDescriptor)
    {
        iLog->LogError("GetOrCreateRenderPassDescriptor: Failed to create MTLRenderPassDescriptor!\n");
        return nil;
    }
    
    @try {
        if (colorTexture)
        {
            // Validate texture before use
            if (![colorTexture conformsToProtocol:@protocol(MTLTexture)])
            {
                iLog->LogError("GetOrCreateRenderPassDescriptor: colorTexture is not a valid MTLTexture!\n");
                return nil;
            }
            
            renderPassDescriptor.colorAttachments[0].texture = colorTexture;
            renderPassDescriptor.colorAttachments[0].loadAction = colorLoad;
            renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
        }
        
        if (depthStencilTexture)
        {
            // Validate depth texture before use  
            if (![depthStencilTexture conformsToProtocol:@protocol(MTLTexture)])
            {
                iLog->LogError("GetOrCreateRenderPassDescriptor: depthStencilTexture is not a valid MTLTexture!\n");
                return nil;
            }
            
            renderPassDescriptor.depthAttachment.texture = depthStencilTexture;
            renderPassDescriptor.depthAttachment.loadAction = depthLoad;
            renderPassDescriptor.depthAttachment.storeAction = (depthLoad == MTLLoadActionLoad) ? MTLStoreActionStore : MTLStoreActionDontCare;
            renderPassDescriptor.depthAttachment.clearDepth = 1.0;
            
            renderPassDescriptor.stencilAttachment.texture = depthStencilTexture;
            renderPassDescriptor.stencilAttachment.loadAction = stencilLoad;
            renderPassDescriptor.stencilAttachment.storeAction = (stencilLoad == MTLLoadActionLoad) ? MTLStoreActionStore : MTLStoreActionDontCare;
            renderPassDescriptor.stencilAttachment.clearStencil = 0;
        }
    }
    @catch (NSException *exception) {
        iLog->LogError("GetOrCreateRenderPassDescriptor: Exception configuring render pass: %s\n", 
                      [[exception description] UTF8String]);
        return nil;
    }
    
    // Caching disabled - just return the new descriptor
    return renderPassDescriptor;
}

void CMetalBaseRenderer::ClearRenderPassCache()
{
    // Release all retained descriptors before clearing
    for (auto& pair : m_renderPassCache)
    {
        if (pair.second)
        {
            [pair.second release];
        }
    }
    m_renderPassCache.clear();
}

bool CMetalBaseRenderer::EnsureBackbufferSize(NSUInteger width, NSUInteger height)
{
    width = std::max<NSUInteger>(1, width);
    height = std::max<NSUInteger>(1, height);

    if (width == static_cast<NSUInteger>(m_width) &&
        height == static_cast<NSUInteger>(m_height))
    {
        return true;
    }

    iLog->Log("EnsureBackbufferSize: resizing from %dx%d to %lu x %lu\n",
              m_width, m_height,
              static_cast<unsigned long>(width),
              static_cast<unsigned long>(height));

    CleanupDepthStencilTextures();

    m_width = static_cast<int>(width);
    m_height = static_cast<int>(height);
    m_viewportWidth = m_width;
    m_viewportHeight = m_height;

    return InitializeDepthStencilTextures();
}

bool CMetalBaseRenderer::AcquireDrawableResources()
{
    if (m_renderPassDescriptor)
    {
        [m_renderPassDescriptor release];
        m_renderPassDescriptor = nil;
    }
    if (m_currentDrawable)
    {
        [m_currentDrawable release];
        m_currentDrawable = nil;
    }

    if (m_metalLayer)
    {
        return AcquireDrawableFromLayer();
    }
    if (m_metalView)
    {
        return AcquireDrawableFromView();
    }

    // No target to render to yet (headless mode)
    return true;
}

bool CMetalBaseRenderer::AcquireDrawableFromLayer()
{
    if (!m_metalLayer || !m_currentCommandBuffer)
        return false;

    CGSize drawableSize = m_metalLayer.drawableSize;
    NSUInteger targetWidth = static_cast<NSUInteger>(std::max(1.0, drawableSize.width));
    NSUInteger targetHeight = static_cast<NSUInteger>(std::max(1.0, drawableSize.height));

    if (!EnsureBackbufferSize(targetWidth, targetHeight))
        return false;

    id<CAMetalDrawable> drawable = [m_metalLayer nextDrawable];
    if (!drawable)
    {
        iLog->Log("AcquireDrawableFromLayer: nextDrawable returned nil (size %.0fx%.0f)\n",
                  drawableSize.width, drawableSize.height);
        return false;
    }

    m_currentDrawable = [drawable retain];

    id<MTLTexture> depthStencilTexture = m_depthStencilTextures[m_currentFrameIndex];
    if (!depthStencilTexture)
    {
        if (!InitializeDepthStencilTextures())
        {
            [m_currentDrawable release];
            m_currentDrawable = nil;
            return false;
        }
        depthStencilTexture = m_depthStencilTextures[m_currentFrameIndex];
    }

    MTLRenderPassDescriptor* descriptor = CreateRenderPassDescriptor(m_currentDrawable.texture, depthStencilTexture);
    if (!descriptor)
    {
        [m_currentDrawable release];
        m_currentDrawable = nil;
        return false;
    }
    m_renderPassDescriptor = [descriptor retain];

    m_renderEncoder = [[m_currentCommandBuffer renderCommandEncoderWithDescriptor:m_renderPassDescriptor] retain];
    if (!m_renderEncoder)
    {
        iLog->Log("AcquireDrawableFromLayer: Failed to create render encoder\n");
        [m_renderPassDescriptor release];
        m_renderPassDescriptor = nil;
        [m_currentDrawable release];
        m_currentDrawable = nil;
        return false;
    }

    SetViewport(0, 0, static_cast<int>(targetWidth), static_cast<int>(targetHeight));
    return true;
}

bool CMetalBaseRenderer::AcquireDrawableFromView()
{
    if (!m_metalView || !m_currentCommandBuffer)
        return false;

    CGSize drawableSize = m_metalView.drawableSize;
    NSUInteger targetWidth = static_cast<NSUInteger>(std::max(1.0, drawableSize.width));
    NSUInteger targetHeight = static_cast<NSUInteger>(std::max(1.0, drawableSize.height));

    if (!EnsureBackbufferSize(targetWidth, targetHeight))
        return false;

    id<CAMetalDrawable> drawable = [m_metalView currentDrawable];
    if (!drawable)
    {
        iLog->Log("AcquireDrawableFromView: currentDrawable returned nil (size %.0fx%.0f)\n",
                  drawableSize.width, drawableSize.height);
        return false;
    }

    m_currentDrawable = [drawable retain];

    id<MTLTexture> depthStencilTexture = m_depthStencilTextures[m_currentFrameIndex];
    if (!depthStencilTexture)
    {
        if (!InitializeDepthStencilTextures())
        {
            [m_currentDrawable release];
            m_currentDrawable = nil;
            return false;
        }
        depthStencilTexture = m_depthStencilTextures[m_currentFrameIndex];
    }

    MTLRenderPassDescriptor* descriptor = CreateRenderPassDescriptor(m_currentDrawable.texture, depthStencilTexture);
    if (!descriptor)
    {
        [m_currentDrawable release];
        m_currentDrawable = nil;
        return false;
    }
    m_renderPassDescriptor = [descriptor retain];

    m_renderEncoder = [[m_currentCommandBuffer renderCommandEncoderWithDescriptor:m_renderPassDescriptor] retain];
    if (!m_renderEncoder)
    {
        iLog->Log("AcquireDrawableFromView: Failed to create render encoder\n");
        [m_renderPassDescriptor release];
        m_renderPassDescriptor = nil;
        [m_currentDrawable release];
        m_currentDrawable = nil;
        return false;
    }

    SetViewport(0, 0, static_cast<int>(targetWidth), static_cast<int>(targetHeight));
    return true;
}

void CMetalBaseRenderer::BeginFrame()
{
    // #region agent debug
    static int beginFrameCount = 0;
    if (beginFrameCount++ < 5)
        iLog->Log("[DEBUG_RENDERER] BeginFrame called (count=%d) init=%d device=%p queue=%p", 
                 beginFrameCount, m_isInitialized, (void*)m_device, (void*)m_commandQueue);
    // #endregion
    
    if (!m_isInitialized || !m_device || !m_commandQueue)
        return;
    
    m_cEF.mfBeginFrame();

    m_nPolygons = 0;
    m_nShadowVolumePolys = 0;
    m_nFrameID++;
    m_nFrameUpdateID++;
    m_frameID = m_nFrameID;

    dispatch_semaphore_t frameSemaphore = m_frameSemaphores[m_currentFrameIndex];
    dispatch_semaphore_wait(frameSemaphore, DISPATCH_TIME_FOREVER);
    
    m_currentCommandBuffer = [m_commandQueue commandBuffer];
    if (!m_currentCommandBuffer)
    {
        iLog->Log("Error: Failed to create command buffer\n");
        dispatch_semaphore_signal(frameSemaphore);
        return;
    }
    
    __block dispatch_semaphore_t completionSemaphore = frameSemaphore;
    [m_currentCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(completionSemaphore);
    }];
    
    m_dynamicVBPools[m_currentDynamicVBPool].offset = 0;
    
    const bool needsDrawable = (m_metalLayer != nil) || (m_metalView != nil);
    if (needsDrawable && !AcquireDrawableResources())
    {
        iLog->Log("BeginFrame: Failed to acquire drawable resources\n");
        m_currentCommandBuffer = nil;
        dispatch_semaphore_signal(frameSemaphore);
        return;
    }
    
    m_numDrawCalls = 0;
    m_numTriangles = 0;
}

void CMetalBaseRenderer::Update()
{
    iLog->Log("CMetalBaseRenderer::Update ENTRY - calling EndFrame\n");

    
    // Update() in CryEngine is called at the end of each frame
    // It should swap buffers and present the frame
    EndFrame();
    
    iLog->Log("CMetalBaseRenderer::Update EXIT\n");

}

void CMetalBaseRenderer::EndFrame()
{
    if (!m_currentCommandBuffer)
        return;
    
    if (m_renderEncoder)
    {
        [m_renderEncoder endEncoding];
        [m_renderEncoder release];
        m_renderEncoder = nil;
    }
    
    if (m_currentDrawable)
    {
        [m_currentCommandBuffer presentDrawable:m_currentDrawable];
        [m_currentDrawable release];
        m_currentDrawable = nil;
    }
    else if (m_metalView && m_metalView.currentDrawable)
    {
        [m_currentCommandBuffer presentDrawable:m_metalView.currentDrawable];
    }
    
    if (m_renderPassDescriptor)
    {
        [m_renderPassDescriptor release];
        m_renderPassDescriptor = nil;
    }
    
    TrackCommandBuffer(m_currentCommandBuffer);
    [m_currentCommandBuffer commit];
    
    m_currentCommandBuffer = nil;
    
    m_currentFrameIndex = (m_currentFrameIndex + 1) % MAX_FRAMES_IN_FLIGHT;
    m_currentDynamicVBPool = (m_currentDynamicVBPool + 1) % NUM_DYNAMIC_VB_POOLS;
}

void CMetalBaseRenderer::SetCamera(const CCamera& cam)
{
    m_camera = cam;
    m_matrixDirty = true;
}

const CCamera& CMetalBaseRenderer::GetCamera()
{
    return m_camera;
}

void CMetalBaseRenderer::SetViewport(int x, int y, int width, int height)
{
    m_viewportX = x;
    m_viewportY = y;
    m_viewportWidth = (width == 0) ? m_width : width;
    m_viewportHeight = (height == 0) ? m_height : height;
    
    if (m_renderEncoder)
    {
        MTLViewport viewport;
        viewport.originX = m_viewportX;
        viewport.originY = m_viewportY;
        viewport.width = m_viewportWidth;
        viewport.height = m_viewportHeight;
        viewport.znear = 0.0;
        viewport.zfar = 1.0;
        [m_renderEncoder setViewport:viewport];
    }
}

void CMetalBaseRenderer::GetViewport(int* x, int* y, int* width, int* height)
{
    if (x) *x = m_viewportX;
    if (y) *y = m_viewportY;
    if (width) *width = m_viewportWidth;
    if (height) *height = m_viewportHeight;
}

void CMetalBaseRenderer::SetScissor(int x, int y, int width, int height)
{
    if (m_renderEncoder)
    {
        MTLScissorRect scissor;
        scissor.x = x;
        scissor.y = y;
        scissor.width = width;
        scissor.height = height;
        [m_renderEncoder setScissorRect:scissor];
    }
}

void CMetalBaseRenderer::PushMatrix()
{
    m_matrixStack.push(m_currentMatrix);
}

void CMetalBaseRenderer::PopMatrix()
{
    if (!m_matrixStack.empty())
    {
        m_currentMatrix = m_matrixStack.top();
        m_matrixStack.pop();
        m_matrixDirty = true;
    }
}

void CMetalBaseRenderer::LoadMatrix(const Matrix44* src)
{
    if (src)
    {
        m_currentMatrix = *src;
    }
    else
    {
        m_currentMatrix.SetIdentity();
    }
    m_matrixDirty = true;
}

void CMetalBaseRenderer::MultMatrix(float* mat)
{
    if (!mat)
        return;
    
    Matrix44 temp;
    for (int i = 0; i < 16; ++i)
        temp.GetData()[i] = mat[i];
    
    m_currentMatrix = m_currentMatrix * temp;
    m_matrixDirty = true;
}

void CMetalBaseRenderer::TranslateMatrix(float x, float y, float z)
{
    Matrix44 trans;
    trans.SetIdentity();
    trans(0,3) = x;
    trans(1,3) = y;
    trans(2,3) = z;
    m_currentMatrix = m_currentMatrix * trans;
    m_matrixDirty = true;
}

void CMetalBaseRenderer::TranslateMatrix(const Vec3& pos)
{
    TranslateMatrix(pos.x, pos.y, pos.z);
}

void CMetalBaseRenderer::RotateMatrix(float angle, float x, float y, float z)
{
    float rad = angle * 3.14159265f / 180.0f;
    float c = cosf(rad);
    float s = sinf(rad);
    float t = 1.0f - c;
    
    float len = sqrtf(x*x + y*y + z*z);
    if (len > 0.0f)
    {
        x /= len;
        y /= len;
        z /= len;
    }
    
    Matrix44 rot;
    rot.SetIdentity();
    rot(0,0) = t*x*x + c;
    rot(0,1) = t*x*y - s*z;
    rot(0,2) = t*x*z + s*y;
    rot(1,0) = t*x*y + s*z;
    rot(1,1) = t*y*y + c;
    rot(1,2) = t*y*z - s*x;
    rot(2,0) = t*x*z - s*y;
    rot(2,1) = t*y*z + s*x;
    rot(2,2) = t*z*z + c;
    
    m_currentMatrix = m_currentMatrix * rot;
    m_matrixDirty = true;
}

void CMetalBaseRenderer::RotateMatrix(const Vec3& angles)
{
    RotateMatrix(angles.z, 0, 0, 1);
    RotateMatrix(angles.y, 0, 1, 0);
    RotateMatrix(angles.x, 1, 0, 0);
}

void CMetalBaseRenderer::ScaleMatrix(float x, float y, float z)
{
    Matrix44 scale;
    scale.SetIdentity();
    scale(0,0) = x;
    scale(1,1) = y;
    scale(2,2) = z;
    m_currentMatrix = m_currentMatrix * scale;
    m_matrixDirty = true;
}

void CMetalBaseRenderer::UpdateMatrices()
{
    if (!m_matrixDirty)
        return;
    
    m_modelViewProjectionMatrix = m_projectionMatrix * m_viewMatrix * m_currentMatrix;
    m_matrixDirty = false;
}

void CMetalBaseRenderer::UpdateUniformBuffer()
{
    if (!m_uniformBufferCPU)
        return;
    
    UpdateMatrices();
    
    m_uniformBufferCPU->modelViewProjectionMatrix = m_modelViewProjectionMatrix;
    m_uniformBufferCPU->modelMatrix = m_currentMatrix;
    m_uniformBufferCPU->viewMatrix = m_viewMatrix;
    m_uniformBufferCPU->projectionMatrix = m_projectionMatrix;
    
    Vec3 camPos = m_camera.GetPos();
    m_uniformBufferCPU->cameraPos = camPos;
    m_uniformBufferCPU->time = iTimer ? iTimer->GetCurrTime() : 0.0f;
    
    // Build light list from active dynamic lights
    m_uniformBufferCPU->numLights = 0;
    for (int li = 0; li < m_RP.m_NumActiveDLights && li < kMaxLights; ++li) {
        const CDLight* pL = m_RP.m_pActiveDLights[li];
        if (!pL) continue;
        auto& entry = m_uniformBufferCPU->lights[m_uniformBufferCPU->numLights];
        entry.pos[0] = pL->m_Origin.x; entry.pos[1] = pL->m_Origin.y; entry.pos[2] = pL->m_Origin.z;
        entry.radius = pL->m_fRadius;
        entry.color[0] = pL->m_Color.r; entry.color[1] = pL->m_Color.g; entry.color[2] = pL->m_Color.b;
        entry.intensity = pL->m_Color.a > 0.f ? pL->m_Color.a : 1.f;
        m_uniformBufferCPU->numLights++;
    }
    // Primary light aliases light[0] (or a sun/ambient fallback)
    if (m_uniformBufferCPU->numLights > 0) {
        auto& e0 = m_uniformBufferCPU->lights[0];
        m_uniformBufferCPU->lightPos   = Vec3(e0.pos[0], e0.pos[1], e0.pos[2]);
        m_uniformBufferCPU->lightColor = Vec3(e0.color[0] * e0.intensity,
                                              e0.color[1] * e0.intensity,
                                              e0.color[2] * e0.intensity);
    } else {
        // No dynamic lights — use a high overhead directional fill light so scene isn't black
        m_uniformBufferCPU->lightPos   = Vec3(0, 500, 0);
        m_uniformBufferCPU->lightColor = Vec3(0.6f, 0.6f, 0.6f);
    }
    
    // Initialize clip plane data
    if (m_clipPlaneEnabled) {
        m_uniformBufferCPU->clipPlane[0] = m_clipPlaneParams[0];
        m_uniformBufferCPU->clipPlane[1] = m_clipPlaneParams[1];
        m_uniformBufferCPU->clipPlane[2] = m_clipPlaneParams[2];
        m_uniformBufferCPU->clipPlane[3] = m_clipPlaneParams[3];
        m_uniformBufferCPU->clipEnabled = 1.0f;
        m_uniformBufferCPU->clipRefract = m_clipPlaneRefract ? 1.0f : 0.0f;
    } else {
        m_uniformBufferCPU->clipPlane[0] = 0.0f;
        m_uniformBufferCPU->clipPlane[1] = 0.0f;
        m_uniformBufferCPU->clipPlane[2] = 0.0f;
        m_uniformBufferCPU->clipPlane[3] = 0.0f;
        m_uniformBufferCPU->clipEnabled = 0.0f;
        m_uniformBufferCPU->clipRefract = 0.0f;
    }
    
    // Debug logging (can be removed once stable)
    static int frameCount = 0;
    if ((frameCount++ % 60) == 0) { // Log every 60 frames to avoid spam
        iLog->Log("UpdateUniformBuffer: clipEnabled=%.1f clipRefract=%.1f clipPlane=(%.3f,%.3f,%.3f,%.3f)\n",
                  m_uniformBufferCPU->clipEnabled, m_uniformBufferCPU->clipRefract,
                  m_uniformBufferCPU->clipPlane[0], m_uniformBufferCPU->clipPlane[1],
                  m_uniformBufferCPU->clipPlane[2], m_uniformBufferCPU->clipPlane[3]);
    }
}

void CMetalBaseRenderer::GetModelViewMatrix(float* mat)
{
    if (!mat)
        return;
    
    Matrix44 mv = m_viewMatrix * m_currentMatrix;
    memcpy(mat, mv.GetData(), 16 * sizeof(float));
}

void CMetalBaseRenderer::GetModelViewMatrix(double* mat)
{
    if (!mat)
        return;
    
    Matrix44 mv = m_viewMatrix * m_currentMatrix;
    for (int i = 0; i < 16; ++i)
        mat[i] = mv.GetData()[i];
}

void CMetalBaseRenderer::GetProjectionMatrix(float* mat)
{
    if (!mat)
        return;
    
    memcpy(mat, m_projectionMatrix.GetData(), 16 * sizeof(float));
}

void CMetalBaseRenderer::GetProjectionMatrix(double* mat)
{
    if (!mat)
        return;
    
    for (int i = 0; i < 16; ++i)
        mat[i] = m_projectionMatrix.GetData()[i];
}

Matrix44 CMetalBaseRenderer::GetUniformModelViewProjection() const
{
    if (m_uniformBufferCPU)
        return m_uniformBufferCPU->modelViewProjectionMatrix;
    Matrix44 matrix;
    matrix.SetIdentity();
    return matrix;
}

Matrix44 CMetalBaseRenderer::GetUniformModelMatrix() const
{
    if (m_uniformBufferCPU)
        return m_uniformBufferCPU->modelMatrix;
    Matrix44 matrix;
    matrix.SetIdentity();
    return matrix;
}

Matrix44 CMetalBaseRenderer::GetUniformViewMatrix() const
{
    if (m_uniformBufferCPU)
        return m_uniformBufferCPU->viewMatrix;
    Matrix44 matrix;
    matrix.SetIdentity();
    return matrix;
}

Matrix44 CMetalBaseRenderer::GetUniformProjectionMatrix() const
{
    if (m_uniformBufferCPU)
        return m_uniformBufferCPU->projectionMatrix;
    Matrix44 matrix;
    matrix.SetIdentity();
    return matrix;
}

Vec3 CMetalBaseRenderer::GetUniformCameraPosition() const
{
    if (m_uniformBufferCPU)
        return m_uniformBufferCPU->cameraPos;
    return Vec3(0.0f, 0.0f, 0.0f);
}

Vec3 CMetalBaseRenderer::GetUniformLightPosition() const
{
    if (m_uniformBufferCPU)
        return m_uniformBufferCPU->lightPos;
    return Vec3(0.0f, 0.0f, 0.0f);
}

Vec3 CMetalBaseRenderer::GetUniformLightColor() const
{
    if (m_uniformBufferCPU)
        return m_uniformBufferCPU->lightColor;
    return Vec3(1.0f, 1.0f, 1.0f);
}

float CMetalBaseRenderer::GetUniformTime() const
{
    return m_uniformBufferCPU ? m_uniformBufferCPU->time : 0.0f;
}

void CMetalBaseRenderer::GetUniformClipPlane(float out[4]) const
{
    if (!out)
        return;
    if (m_uniformBufferCPU)
    {
        out[0] = m_uniformBufferCPU->clipPlane[0];
        out[1] = m_uniformBufferCPU->clipPlane[1];
        out[2] = m_uniformBufferCPU->clipPlane[2];
        out[3] = m_uniformBufferCPU->clipPlane[3];
    }
    else
    {
        out[0] = 0.0f;
        out[1] = 0.0f;
        out[2] = 0.0f;
        out[3] = 0.0f;
    }
}

float CMetalBaseRenderer::GetUniformClipEnabled() const
{
    return m_uniformBufferCPU ? m_uniformBufferCPU->clipEnabled : 0.0f;
}

float CMetalBaseRenderer::GetUniformClipRefract() const
{
    return m_uniformBufferCPU ? m_uniformBufferCPU->clipRefract : 0.0f;
}

#endif

// Part 2: Buffer Management, State Management, and Drawing

#if defined(__APPLE__) && defined(__MACH__)

CVertexBuffer* CMetalBaseRenderer::CreateBuffer(int vertexcount, int vertexformat, 
                                                const char* szSource, bool bDynamic)
{
    if (!m_device || vertexcount <= 0)
        return nullptr;
    
    const int vertexSize = GetVertexFormatSize(vertexformat);
    if (vertexSize <= 0)
        return nullptr;
    
    const size_t bufferSize = static_cast<size_t>(vertexcount) * static_cast<size_t>(vertexSize);
    
    CVertexBuffer* vb = new CVertexBuffer();
    if (!vb)
        return nullptr;
    
    vb->m_NumVerts = vertexcount;
    vb->m_vertexformat = vertexformat;
    vb->m_bDynamic = bDynamic ? 1 : 0;
    vb->m_VS[VSF_GENERAL].m_bDynamic = bDynamic;
    vb->m_VS[VSF_GENERAL].m_bLocked = false;
    vb->m_VS[VSF_GENERAL].m_nItems = vertexcount;
    
    id<MTLBuffer> metalBuffer = CreateMetalBuffer(nullptr, bufferSize, MTLResourceStorageModeShared);
    if (!metalBuffer)
    {
        delete vb;
        return nullptr;
    }
    
    int bufferId = m_nextVertexBufferId++;
    if (bufferId >= static_cast<int>(m_vertexBuffers.size()))
    {
        m_vertexBuffers.resize(bufferId + 1, nil);
    }
    m_vertexBuffers[bufferId] = metalBuffer;
    
    vb->m_VS[VSF_GENERAL].m_VertBuf.m_nID = bufferId;
    vb->m_VS[VSF_GENERAL].m_VData = [metalBuffer contents];
    vb->m_bFenceSet = 0;
    
    return vb;
}

void CMetalBaseRenderer::ReleaseBuffer(CVertexBuffer* bufptr)
{
    if (!bufptr)
        return;
    
    for (int stream = 0; stream < VSF_NUM; ++stream)
    {
        int bufferId = bufptr->m_VS[stream].m_VertBuf.m_nID;
        if (bufferId > 0 && bufferId < static_cast<int>(m_vertexBuffers.size()))
        {
            m_vertexBuffers[bufferId] = nil;
        }
        bufptr->m_VS[stream].m_VertBuf.m_nID = 0;
        bufptr->m_VS[stream].m_VData = nullptr;
        bufptr->m_VS[stream].m_nItems = 0;
        bufptr->m_VS[stream].m_bLocked = false;
    }
    
    delete bufptr;
}

namespace
{
inline size_t StreamStride(const CVertexBuffer* buffer, int streamIndex, CMetalBaseRenderer* renderer)
{
    if (streamIndex == VSF_TANGENTS)
        return sizeof(SPipTangents);
    if (!buffer)
        return 0;
    return renderer->GetVertexFormatSize(buffer->m_vertexformat);
}

inline int ResolveStreamIndex(int typeValue)
{
    if (typeValue == VSF_GENERAL || typeValue == 0)
        return VSF_GENERAL;
    if (typeValue < VSF_NUM)
        return typeValue;
    for (int i = 0; i < VSF_NUM; ++i)
    {
        if (typeValue & (1 << i))
            return i;
    }
    return VSF_GENERAL;
}

inline int ResolveStreamMask(int typeValue)
{
    if (typeValue == 0)
        return (1 << VSF_GENERAL);
    if (typeValue < VSF_NUM)
        return (1 << typeValue);
    return typeValue;
}
}

void CMetalBaseRenderer::UpdateBuffer(CVertexBuffer* dest, const void* src, 
                                     int vertexcount, bool bUnLock, int nOffs, int Type)
{
    if (!dest)
        return;
    
    auto getBufferForStream = [this, dest](int streamIndex) -> id<MTLBuffer> {
        const int bufferId = dest->m_VS[streamIndex].m_VertBuf.m_nID;
        if (bufferId > 0 && bufferId < static_cast<int>(m_vertexBuffers.size()))
            return m_vertexBuffers[bufferId];
        return nil;
    };
    
    auto flushStream = [](id<MTLBuffer> buffer, size_t offset, size_t length) {
        if (buffer && buffer.storageMode == MTLStorageModeManaged)
        {
            [buffer didModifyRange:NSMakeRange(offset, length)];
        }
    };
    
    auto lockStream = [&](int streamIndex, bool unlock) {
        SVertexStream& stream = dest->m_VS[streamIndex];
        id<MTLBuffer> metalBuffer = getBufferForStream(streamIndex);
        if (unlock)
        {
            if (stream.m_bLocked)
            {
                stream.m_bLocked = false;
                if (metalBuffer)
                {
                    flushStream(metalBuffer, 0, [metalBuffer length]);
                }
            }
            return;
        }
        
        if (stream.m_bLocked)
            return;
        
        uint8_t* basePtr = nullptr;
        if (metalBuffer)
            basePtr = static_cast<uint8_t*>([metalBuffer contents]);
        else if (stream.m_VData)
            basePtr = static_cast<uint8_t*>(stream.m_VData);
        if (!basePtr)
            return;
        
        const size_t stride = StreamStride(dest, streamIndex, this);
        stream.m_VData = basePtr + static_cast<size_t>(nOffs) * stride;
        stream.m_bLocked = true;
    };
    
    if (!src)
    {
        const int mask = ResolveStreamMask(Type);
        for (int i = 0; i < VSF_NUM; ++i)
        {
            if (mask & (1 << i))
            {
                lockStream(i, bUnLock);
            }
        }
        return;
    }
    
    if (vertexcount <= 0)
        return;
    
    const int streamIndex = ResolveStreamIndex(Type);
    SVertexStream& stream = dest->m_VS[streamIndex];
    id<MTLBuffer> metalBuffer = getBufferForStream(streamIndex);
    
    const size_t stride = StreamStride(dest, streamIndex, this);
    if (stride == 0)
        return;
    
    const size_t copySize = static_cast<size_t>(vertexcount) * stride;
    const size_t offsetBytes = static_cast<size_t>(nOffs) * stride;
    
    uint8_t* dst = nullptr;
    if (metalBuffer)
        dst = static_cast<uint8_t*>([metalBuffer contents]);
    else if (stream.m_VData)
        dst = static_cast<uint8_t*>(stream.m_VData);
    
    if (!dst)
        return;
    
    std::memcpy(dst + offsetBytes, src, copySize);
    stream.m_VData = dst;
    stream.m_bLocked = false;
    stream.m_nItems = std::max(stream.m_nItems, nOffs + vertexcount);
    dest->m_NumVerts = std::max(dest->m_NumVerts, nOffs + vertexcount);
    
    if (metalBuffer)
        flushStream(metalBuffer, offsetBytes, copySize);
}

void CMetalBaseRenderer::CreateIndexBuffer(SVertexStream* dest, const void* src, int indexcount)
{
    if (!dest || indexcount <= 0 || !m_device)
        return;
    
    const size_t bufferSize = static_cast<size_t>(indexcount) * sizeof(unsigned short);
    id<MTLBuffer> metalBuffer = CreateMetalBuffer(const_cast<void*>(src), bufferSize, MTLResourceStorageModeShared);
    if (!metalBuffer)
        return;
    
    int bufferId = m_nextIndexBufferId++;
    if (bufferId >= static_cast<int>(m_indexBuffers.size()))
    {
        m_indexBuffers.resize(bufferId + 1, nil);
    }
    m_indexBuffers[bufferId] = metalBuffer;
    
    dest->m_VertBuf.m_nID = bufferId;
    dest->m_VData = [metalBuffer contents];
    dest->m_nItems = indexcount;
}

void CMetalBaseRenderer::UpdateIndexBuffer(SVertexStream* dest, const void* src, 
                                          int indexcount, bool bUnLock)
{
    if (!dest)
        return;
    
    auto getBuffer = [this, dest]() -> id<MTLBuffer> {
        const int bufferId = dest->m_VertBuf.m_nID;
        if (bufferId > 0 && bufferId < static_cast<int>(m_indexBuffers.size()))
            return m_indexBuffers[bufferId];
        return nil;
    };
    
    if (!src)
    {
        id<MTLBuffer> buffer = getBuffer();
        if (!bUnLock)
        {
            if (!dest->m_bLocked && buffer)
            {
                dest->m_VData = [buffer contents];
                dest->m_bLocked = true;
            }
        }
        else if (dest->m_bLocked)
        {
            if (buffer && buffer.storageMode == MTLStorageModeManaged)
            {
                [buffer didModifyRange:NSMakeRange(0, [buffer length])];
            }
            dest->m_bLocked = false;
        }
        return;
    }
    
    if (indexcount <= 0)
        return;
    
    if (dest->m_nItems < indexcount || dest->m_VertBuf.m_nID <= 0)
    {
        ReleaseIndexBuffer(dest);
        CreateIndexBuffer(dest, src, indexcount);
        return;
    }
    
    id<MTLBuffer> metalBuffer = getBuffer();
    const size_t copySize = static_cast<size_t>(indexcount) * sizeof(unsigned short);
    if (metalBuffer)
    {
        std::memcpy([metalBuffer contents], src, copySize);
        if (metalBuffer.storageMode == MTLStorageModeManaged)
        {
            [metalBuffer didModifyRange:NSMakeRange(0, copySize)];
        }
        dest->m_VData = [metalBuffer contents];
    }
    else if (dest->m_VData)
    {
        std::memcpy(dest->m_VData, src, copySize);
    }
    
    dest->m_nItems = std::max(dest->m_nItems, indexcount);
    dest->m_bLocked = false;
}

void CMetalBaseRenderer::ReleaseIndexBuffer(SVertexStream* dest)
{
    if (!dest)
        return;
    
    int bufferId = dest->m_VertBuf.m_nID;
    if (bufferId > 0 && bufferId < (int)m_indexBuffers.size())
    {
        m_indexBuffers[bufferId] = nil;
    }
    
    dest->Reset();
}

void* CMetalBaseRenderer::GetDynVBPtr(int nVerts, int& nOffs, int Pool)
{
    if (Pool < 0 || Pool >= NUM_DYNAMIC_VB_POOLS)
        return nullptr;
    
    DynamicVBPool& pool = m_dynamicVBPools[Pool];
    
    int vertexSize = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
    if (nVerts <= 0)
    {
        nOffs = 0;
        return pool.cpuData;
    }
    
    size_t requiredSize = nVerts * vertexSize;
    
    if (pool.offset + requiredSize > pool.size)
    {
        pool.offset = 0;
    }
    
    nOffs = static_cast<int>(pool.offset / vertexSize);
    void* ptr = (char*)pool.cpuData + pool.offset;
    pool.offset += requiredSize;
    
    return ptr;
}

void CMetalBaseRenderer::DrawDynVB(int nOffs, int Pool, int nVerts)
{
    if (!m_renderEncoder || nVerts <= 0 || Pool < 0 || Pool >= NUM_DYNAMIC_VB_POOLS)
        return;
    
    // #region agent debug - check for valid pipeline state
    if (!m_currentPipelineState)
    {
        static int warnCount = 0;
        if (warnCount++ < 3 && iLog)
            iLog->Log("MetalRenderer: Skipping dynamic VB draw - no valid pipeline state (shaders may be missing)");
        return;
    }
    // #endregion
    
    if (m_shaderNeedsTangents)
    {
        if (iLog)
            iLog->Log("MetalRenderer: Skipping dynamic VB draw because shader requires tangents");
        return;
    }
    
    DynamicVBPool& pool = m_dynamicVBPools[Pool];
    int vertexSize = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
    size_t offset = nOffs * vertexSize;
    
    [m_renderEncoder setVertexBuffer:pool.buffer offset:offset atIndex:kMetalVertexStream_General];
    [m_renderEncoder setVertexBuffer:nil offset:0 atIndex:kMetalVertexStream_Tangents];
    [m_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:nVerts];
    
    m_numDrawCalls++;
    m_numTriangles += nVerts / 3;
}

void CMetalBaseRenderer::DrawDynVB(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F* pBuf, 
                                  ushort* pInds, int nVerts, int nInds, int nPrimType)
{
    if (!m_renderEncoder || !pBuf || nVerts <= 0)
        return;
    
    // #region agent debug - check for valid pipeline state
    if (!m_currentPipelineState)
    {
        static int warnCount = 0;
        if (warnCount++ < 3 && iLog)
            iLog->Log("MetalRenderer: Skipping dynamic indexed draw - no valid pipeline state (shaders may be missing)");
        return;
    }
    // #endregion
    
    if (m_shaderNeedsTangents)
    {
        if (iLog)
            iLog->Log("MetalRenderer: Skipping dynamic indexed draw because shader requires tangents");
        return;
    }
    
    int nOffs;
    void* dynPtr = GetDynVBPtr(nVerts, nOffs, 0);
    if (!dynPtr)
        return;
    
    memcpy(dynPtr, pBuf, nVerts * sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F));
    
    MTLPrimitiveType primType = ConvertPrimitiveType(nPrimType);
    
    if (pInds && nInds > 0)
    {
        size_t indexBufferSize = nInds * sizeof(ushort);
        id<MTLBuffer> indexBuffer = [m_device newBufferWithBytes:pInds 
                                                          length:indexBufferSize 
                                                         options:MTLResourceStorageModeShared];
        
        [m_renderEncoder setVertexBuffer:m_dynamicVBPools[0].buffer offset:nOffs atIndex:kMetalVertexStream_General];
        [m_renderEncoder setVertexBuffer:nil offset:0 atIndex:kMetalVertexStream_Tangents];
        [m_renderEncoder drawIndexedPrimitives:primType 
                                    indexCount:nInds 
                                     indexType:MTLIndexTypeUInt16 
                                   indexBuffer:indexBuffer 
                             indexBufferOffset:0];
    }
    else
    {
        DrawDynVB(nOffs, 0, nVerts);
    }
    
    m_numDrawCalls++;
}

void CMetalBaseRenderer::DrawBuffer(CVertexBuffer* src, SVertexStream* indices, 
                                   int numindices, int offsindex, int prmode, 
                                   int vert_start, int vert_stop, CMatInfo* mi)
{
    if (!m_renderEncoder || !src)
        return;
    
    id<MTLBuffer> vertexBuffer = LookupStreamBuffer(src, VSF_GENERAL);
    if (!vertexBuffer)
        return;
    
    [m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:kMetalVertexStream_General];
    
    if (m_shaderNeedsTangents)
    {
        id<MTLBuffer> tangentBuffer = LookupStreamBuffer(src, VSF_TANGENTS);
        if (!tangentBuffer)
        {
            if (iLog)
                iLog->Log("MetalRenderer: Tangent data missing for current draw call; skipping draw");
            return;
        }

        [m_renderEncoder setVertexBuffer:tangentBuffer offset:0 atIndex:kMetalVertexStream_Tangents];
    }
    else
    {
        [m_renderEncoder setVertexBuffer:nil offset:0 atIndex:kMetalVertexStream_Tangents];
    }
    
    MTLPrimitiveType primType = ConvertPrimitiveType(prmode);
    
    if (indices && numindices > 0)
    {
        int indexBufferId = indices->m_VertBuf.m_nID;
        if (indexBufferId > 0 && indexBufferId < (int)m_indexBuffers.size())
        {
            id<MTLBuffer> indexBuffer = m_indexBuffers[indexBufferId];
            if (indexBuffer)
            {
                size_t indexOffset = offsindex * sizeof(unsigned short);
                [m_renderEncoder drawIndexedPrimitives:primType 
                                            indexCount:numindices 
                                             indexType:MTLIndexTypeUInt16 
                                           indexBuffer:indexBuffer 
                                     indexBufferOffset:indexOffset];
                
                m_numDrawCalls++;
                m_numTriangles += numindices / 3;
            }
        }
    }
    else
    {
        int vertCount = (vert_stop > 0) ? (vert_stop - vert_start) : src->m_NumVerts;
        [m_renderEncoder drawPrimitives:primType vertexStart:vert_start vertexCount:vertCount];
        
        m_numDrawCalls++;
        m_numTriangles += vertCount / 3;
    }
}

void CMetalBaseRenderer::DrawTriStrip(CVertexBuffer* src, int vert_num)
{
    if (!m_renderEncoder || !src)
        return;
    
    id<MTLBuffer> vertexBuffer = LookupStreamBuffer(src, VSF_GENERAL);
    if (!vertexBuffer)
        return;
    
    [m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:kMetalVertexStream_General];
    if (m_shaderNeedsTangents)
    {
        id<MTLBuffer> tangentBuffer = LookupStreamBuffer(src, VSF_TANGENTS);
        if (!tangentBuffer)
        {
            if (iLog)
                iLog->Log("MetalRenderer: Tangent data missing for tri-strip draw; skipping");
            return;
        }
        [m_renderEncoder setVertexBuffer:tangentBuffer offset:0 atIndex:kMetalVertexStream_Tangents];
    }
    else
    {
        [m_renderEncoder setVertexBuffer:nil offset:0 atIndex:kMetalVertexStream_Tangents];
    }
    [m_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip 
                        vertexStart:0 
                        vertexCount:vert_num];
    
    m_numDrawCalls++;
    m_numTriangles += vert_num - 2;
}

void CMetalBaseRenderer::SetFenceCompleted(CVertexBuffer* buffer)
{
    if (buffer)
    {
        buffer->m_bFenceSet = 0;
    }
}

void CMetalBaseRenderer::SetShaderTangentRequirement(bool needsTangents)
{
    m_shaderNeedsTangents = needsTangents;
    if (!needsTangents && m_renderEncoder)
    {
        [m_renderEncoder setVertexBuffer:nil offset:0 atIndex:kMetalVertexStream_Tangents];
    }
}

void CMetalBaseRenderer::SetState(int State)
{
    m_currentState = State;
    
    if (State & GS_DEPTHWRITE)
        SetDepthWrite(true);
    else
        SetDepthWrite(false);
    
    if (State & GS_NODEPTHTEST)
        SetDepthTest(false);
    else
        SetDepthTest(true);
    
    if (State & GS_BLSRC_SRCALPHA)
    {
        SetBlending(true);
        SetBlendFactors(MTLBlendFactorSourceAlpha, MTLBlendFactorOneMinusSourceAlpha, 
                       MTLBlendOperationAdd);
    }
    else if (State & GS_BLSRC_ONE)
    {
        SetBlending(true);
        SetBlendFactors(MTLBlendFactorOne, MTLBlendFactorOne, MTLBlendOperationAdd);
    }
    else
    {
        SetBlending(false);
    }
    
    ApplyRenderState();
}

void CMetalBaseRenderer::SetCullMode(int mode)
{
    m_currentCullMode = mode;
    
    if (!m_renderEncoder)
        return;
    
    switch (mode)
    {
        case R_CULL_DISABLE:
            [m_renderEncoder setCullMode:MTLCullModeNone];
            break;
        case R_CULL_FRONT:
            [m_renderEncoder setCullMode:MTLCullModeFront];
            break;
        case R_CULL_BACK:
        default:
            [m_renderEncoder setCullMode:MTLCullModeBack];
            break;
    }
}

void CMetalBaseRenderer::SetDepthTest(bool enabled)
{
    m_depthTestEnabled = enabled;
}

void CMetalBaseRenderer::SetDepthWrite(bool enabled)
{
    m_depthWriteEnabled = enabled;
}

void CMetalBaseRenderer::SetDepthFunction(MTLCompareFunction function)
{
    m_depthFunction = function;
}

void CMetalBaseRenderer::SetBlending(bool enabled)
{
    m_blendingEnabled = enabled;
}

void CMetalBaseRenderer::SetBlendFactors(MTLBlendFactor source, MTLBlendFactor dest, 
                                        MTLBlendOperation operation)
{
    m_sourceBlendFactor = source;
    m_destBlendFactor = dest;
    m_blendOperation = operation;
    m_sourceAlphaBlendFactor = source;
    m_destAlphaBlendFactor = dest;
    m_alphaBlendOperation = operation;
}

void CMetalBaseRenderer::ApplyRenderState()
{
    if (!m_renderEncoder || !m_stateCache)
        return;
    
    MetalDepthStencilStateKey dsKey;
    dsKey.depthTestEnabled = m_depthTestEnabled;
    dsKey.depthWriteEnabled = m_depthWriteEnabled;
    dsKey.depthCompareFunction = m_depthFunction;
    dsKey.stencilReadMask = 0xFF;
    dsKey.stencilWriteMask = 0xFF;
    
    id<MTLDepthStencilState> depthState = m_stateCache->GetOrCreateDepthStencilState(dsKey);
    if (depthState)
    {
        [m_renderEncoder setDepthStencilState:depthState];
        m_currentDepthStencilState = depthState;
    }
}

bool CMetalBaseRenderer::EnableFog(bool enable)
{
    m_fogEnabled = enable;
    return true;
}

void CMetalBaseRenderer::SetFog(float density, float fogstart, float fogend, 
                               const float* color, int fogmode)
{
    if (!m_uniformBufferCPU)
        return;

    float range = fogend - fogstart;
    if (range > 0.0001f) {
        m_uniformBufferCPU->fogScale = 1.0f / range;
        m_uniformBufferCPU->fogBias  = fogend / range;
    } else {
        m_uniformBufferCPU->fogScale = 0.0f;
        m_uniformBufferCPU->fogBias  = 1.0f;
    }

    if (m_materialBufferCPU && color) {
        m_materialBufferCPU->FogColor[0] = color[0];
        m_materialBufferCPU->FogColor[1] = color[1];
        m_materialBufferCPU->FogColor[2] = color[2];
        m_materialBufferCPU->FogColor[3] = color[3];
    }
}

void CMetalBaseRenderer::EnableTexGen(bool enable)
{
    m_texGenEnabled = enable;
}

void CMetalBaseRenderer::SetMaterialParams(const float* ambient, const float* diffuse, const float* specular)
{
    if (!m_materialBufferCPU)
        return;
    if (ambient) {
        m_materialBufferCPU->Ambient[0] = ambient[0];
        m_materialBufferCPU->Ambient[1] = ambient[1];
        m_materialBufferCPU->Ambient[2] = ambient[2];
        m_materialBufferCPU->Ambient[3] = ambient[3];
    }
    if (diffuse) {
        m_materialBufferCPU->Diffuse[0] = diffuse[0];
        m_materialBufferCPU->Diffuse[1] = diffuse[1];
        m_materialBufferCPU->Diffuse[2] = diffuse[2];
        m_materialBufferCPU->Diffuse[3] = diffuse[3];
    }
    if (specular) {
        m_materialBufferCPU->Specular[0] = specular[0];
        m_materialBufferCPU->Specular[1] = specular[1];
        m_materialBufferCPU->Specular[2] = specular[2];
        m_materialBufferCPU->Specular[3] = specular[3];
    }
}

bool CMetalBaseRenderer::InitHDRPipeline()
{
    if (!m_device || m_hdrColorRT)
        return m_hdrColorRT != nil;

    const int w = m_width  > 0 ? m_width  : 1920;
    const int h = m_height > 0 ? m_height : 1080;
    m_hdrRTWidth  = w;
    m_hdrRTHeight = h;

    // HDR colour target — RGBA16Float, readable as shader texture
    MTLTextureDescriptor *colorDesc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                          width:w height:h mipmapped:NO];
    colorDesc.usage       = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    colorDesc.storageMode = MTLStorageModePrivate;
    m_hdrColorRT = [m_device newTextureWithDescriptor:colorDesc];
    if (!m_hdrColorRT) {
        iLog->Log("InitHDRPipeline: failed to allocate HDRColorRT (%dx%d RGBA16Float)\n", w, h);
        return false;
    }
    [m_hdrColorRT setLabel:@"HDRColorRT"];

    // HDR depth target — Depth32Float_Stencil8
    MTLTextureDescriptor *depthDesc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float_Stencil8
                                                          width:w height:h mipmapped:NO];
    depthDesc.usage       = MTLTextureUsageRenderTarget;
    depthDesc.storageMode = MTLStorageModePrivate;
    m_hdrDepthRT = [m_device newTextureWithDescriptor:depthDesc];
    if (!m_hdrDepthRT) {
        iLog->Log("InitHDRPipeline: failed to allocate HDRDepthRT (%dx%d Depth32Float_Stencil8)\n", w, h);
        [m_hdrColorRT release]; m_hdrColorRT = nil;
        return false;
    }
    [m_hdrDepthRT setLabel:@"HDRDepthRT"];

    // Build tone-map PSO: fullscreen triangle VS + Reinhard FS
    id<MTLLibrary> lib = GetShaderLibrary();
    if (!lib) return false;

    id<MTLFunction> vsFunc = [lib newFunctionWithName:@"hdr_fullscreen_vertex"];
    id<MTLFunction> fsFunc = [lib newFunctionWithName:@"hdr_tonemap_fragment"];
    if (!vsFunc || !fsFunc) return false;

    MTLRenderPipelineDescriptor *psoDesc = [[MTLRenderPipelineDescriptor alloc] init];
    psoDesc.label                           = @"HDRToneMapPSO";
    psoDesc.vertexFunction                  = vsFunc;
    psoDesc.fragmentFunction                = fsFunc;
    psoDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    psoDesc.depthAttachmentPixelFormat      = MTLPixelFormatInvalid;

    NSError *err = nil;
    m_hdrToneMapPSO = [m_device newRenderPipelineStateWithDescriptor:psoDesc error:&err];
    if (!m_hdrToneMapPSO) {
        iLog->Log("HDR ToneMap PSO error: %s",
                  err ? [[err localizedDescription] UTF8String] : "unknown");
        return false;
    }

    // Linear clamp sampler (reused every frame)
    MTLSamplerDescriptor *sDesc = [[MTLSamplerDescriptor alloc] init];
    sDesc.minFilter = MTLSamplerMinMagFilterLinear;
    sDesc.magFilter = MTLSamplerMinMagFilterLinear;
    sDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    m_hdrSampler = [m_device newSamplerStateWithDescriptor:sDesc];

    // Build bloom PSOs (bright-pass + separable Gaussian blur)
    auto makePSO = [&](NSString* fsName, NSString* label,
                       MTLPixelFormat fmt) -> id<MTLRenderPipelineState> {
        id<MTLFunction> fs = [lib newFunctionWithName:fsName];
        if (!fs) return nil;
        MTLRenderPipelineDescriptor *d = [[MTLRenderPipelineDescriptor alloc] init];
        d.label                           = label;
        d.vertexFunction                  = vsFunc;
        d.fragmentFunction                = fs;
        d.colorAttachments[0].pixelFormat = fmt;
        d.depthAttachmentPixelFormat      = MTLPixelFormatInvalid;
        NSError *e = nil;
        id<MTLRenderPipelineState> pso = [m_device newRenderPipelineStateWithDescriptor:d error:&e];
        if (!pso && e)
            iLog->Log("HDR PSO '%s' error: %s", [label UTF8String], [[e localizedDescription] UTF8String]);
        return pso;
    };
    m_hdrBrightPassPSO = makePSO(@"hdr_brightpass_fragment", @"HDRBrightPassPSO",
                                 MTLPixelFormatRGBA16Float);
    m_hdrBlurHPSO      = makePSO(@"hdr_blur_h_fragment",     @"HDRBlurHPSO",
                                 MTLPixelFormatRGBA16Float);
    m_hdrBlurVPSO      = makePSO(@"hdr_blur_v_fragment",     @"HDRBlurVPSO",
                                 MTLPixelFormatRGBA16Float);

    // Quarter-res bloom targets
    const int bw = std::max(1, w / 4);
    const int bh = std::max(1, h / 4);
    auto makeBloomTex = [&](NSString* label) -> id<MTLTexture> {
        MTLTextureDescriptor *bd =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                              width:bw height:bh mipmapped:NO];
        bd.usage       = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        bd.storageMode = MTLStorageModePrivate;
        id<MTLTexture> t = [m_device newTextureWithDescriptor:bd];
        if (t) [t setLabel:label];
        return t;
    };
    m_bloomBrightRT = makeBloomTex(@"BloomBrightRT");
    m_bloomBlurHRT  = makeBloomTex(@"BloomBlurHRT");
    m_bloomBlurVRT  = makeBloomTex(@"BloomBlurVRT");

    return m_hdrColorRT != nil && m_hdrToneMapPSO != nil;
}

static void runFullscreenPass(id<MTLCommandBuffer> cb,
                              id<MTLRenderPipelineState> pso,
                              id<MTLTexture> srcTex,
                              id<MTLSamplerState> samp,
                              id<MTLTexture> dstTex,
                              NSString* label)
{
    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture     = dstTex;
    rpd.colorAttachments[0].loadAction  = MTLLoadActionDontCare;
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rpd];
    if (!enc) return;
    [enc setLabel:label];
    [enc setRenderPipelineState:pso];
    [enc setFragmentTexture:srcTex atIndex:0];
    [enc setFragmentSamplerState:samp atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [enc endEncoding];
}

void CMetalBaseRenderer::DoBloomPass()
{
    if (!m_currentCommandBuffer || !m_hdrColorRT
        || !m_hdrBrightPassPSO || !m_hdrBlurHPSO || !m_hdrBlurVPSO
        || !m_bloomBrightRT || !m_bloomBlurHRT || !m_bloomBlurVRT)
    {
        if (m_hdrEnabled)
        {
            static bool s_logged = false;
            if (!s_logged) {
                s_logged = true;
                if (iLog)
                    iLog->Log("DoBloomPass: HDR enabled but bloom PSOs/RTs are nil — skipping bloom (install full Xcode to compile bloom shaders)");
            }
        }
        return;
    }

    runFullscreenPass(m_currentCommandBuffer, m_hdrBrightPassPSO,
                      m_hdrColorRT,    m_hdrSampler, m_bloomBrightRT, @"BloomBrightPass");
    runFullscreenPass(m_currentCommandBuffer, m_hdrBlurHPSO,
                      m_bloomBrightRT, m_hdrSampler, m_bloomBlurHRT,  @"BloomBlurH");
    runFullscreenPass(m_currentCommandBuffer, m_hdrBlurVPSO,
                      m_bloomBlurHRT,  m_hdrSampler, m_bloomBlurVRT,  @"BloomBlurV");
}

bool CMetalBaseRenderer::BeginHDRPass()
{
    // m_currentCommandBuffer nil here is always a bug: BeginHDRPass is only
    // called from EF_EndEf3D which runs inside an active frame.
    assert(m_currentCommandBuffer && "BeginHDRPass: no active command buffer");
    if (!m_currentCommandBuffer)
        return false;

    // m_hdrColorRT nil means InitHDRPipeline failed (already logged at init
    // time). Log once so the frame-level fallback is visible without spam.
    if (!m_hdrColorRT) {
        static bool s_logged = false;
        if (!s_logged) {
            iLog->Log("BeginHDRPass: HDR colour RT is nil — falling back to LDR\n");
            s_logged = true;
        }
        return false;
    }

    // End the previous encoder if active
    if (m_renderEncoder) {
        [m_renderEncoder endEncoding];
        [m_renderEncoder release];
        m_renderEncoder = nil;
    }

    MTLRenderPassDescriptor *hdrRPD = [MTLRenderPassDescriptor renderPassDescriptor];
    hdrRPD.colorAttachments[0].texture     = m_hdrColorRT;
    hdrRPD.colorAttachments[0].loadAction  = MTLLoadActionClear;
    hdrRPD.colorAttachments[0].storeAction = MTLStoreActionStore;
    hdrRPD.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 1);
    hdrRPD.depthAttachment.texture         = m_hdrDepthRT;
    hdrRPD.depthAttachment.loadAction      = MTLLoadActionClear;
    hdrRPD.depthAttachment.storeAction     = MTLStoreActionDontCare;
    hdrRPD.depthAttachment.clearDepth      = 1.0;

    m_renderEncoder = [[m_currentCommandBuffer
        renderCommandEncoderWithDescriptor:hdrRPD] retain];
    if (m_renderEncoder) [m_renderEncoder setLabel:@"HDRScenePass"];
    return m_renderEncoder != nil;
}

void CMetalBaseRenderer::EndHDRPass()
{
    assert(m_hdrColorRT      && "EndHDRPass: HDR colour RT is nil");
    assert(m_currentCommandBuffer && "EndHDRPass: no active command buffer");
    assert(m_hdrToneMapPSO   && "EndHDRPass: tone-map PSO is nil");
    if (!m_hdrColorRT || !m_currentCommandBuffer || !m_hdrToneMapPSO)
        return;

    // End the HDR scene encoder so bloom passes can open their own encoders
    if (m_renderEncoder) {
        [m_renderEncoder endEncoding];
        [m_renderEncoder release];
        m_renderEncoder = nil;
    }

    // Bloom chain: each pass opens/closes its own encoder (no active encoder here)
    DoBloomPass();

    // Use the drawable that was already acquired in AcquireDrawableFromLayer/View
    id<MTLTexture> dstTexture = m_currentDrawable ? m_currentDrawable.texture : nil;
    if (!dstTexture) return;

    MTLRenderPassDescriptor *tonemapRPD = [MTLRenderPassDescriptor renderPassDescriptor];
    tonemapRPD.colorAttachments[0].texture     = dstTexture;
    tonemapRPD.colorAttachments[0].loadAction  = MTLLoadActionDontCare;
    tonemapRPD.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> tonemapEncoder =
        [m_currentCommandBuffer renderCommandEncoderWithDescriptor:tonemapRPD];
    if (!tonemapEncoder) return;
    [tonemapEncoder setLabel:@"HDRToneMapPass"];
    [tonemapEncoder setRenderPipelineState:m_hdrToneMapPSO];
    [tonemapEncoder setFragmentTexture:m_hdrColorRT atIndex:0];
    [tonemapEncoder setFragmentTexture:(m_bloomBlurVRT ? m_bloomBlurVRT : m_hdrColorRT) atIndex:1];
    [tonemapEncoder setFragmentSamplerState:m_hdrSampler atIndex:0];
    [tonemapEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [tonemapEncoder endEncoding];
    // Drawable is presented in EndFrame via the normal m_currentDrawable path
}

// SetTexgen / SetTexgen3D — fixed-function-era texture coordinate generation API.
//
// In D3D8/9 and OpenGL these configured hardware texgen (eye-plane, camera-space
// position projection). Metal has no fixed-function texgen; the vertex shader is
// solely responsible for UV generation. These methods therefore store the parameters
// for potential use as vertex-shader uniforms but do not drive any hardware state.
//
// There are zero call sites outside renderer DLLs in the current codebase — the
// parameters are preserved to avoid silent data loss if a caller is introduced.

void CMetalBaseRenderer::SetTexgen(float scaleX, float scaleY, float translateX, float translateY)
{
    m_texGenEnabled    = true;
    m_texGenScaleX     = scaleX;
    m_texGenScaleY     = scaleY;
    m_texGenTranslateX = translateX;
    m_texGenTranslateY = translateY;
}

// SetTexgen3D — planar texgen with arbitrary world-space S and T planes.
// S plane normal: (x1, y1, z1), T plane normal: (x2, y2, z2).
void CMetalBaseRenderer::SetTexgen3D(float x1, float y1, float z1, float x2, float y2, float z2)
{
    m_texGenEnabled = true;
    m_texGen3D[0] = x1; m_texGen3D[1] = y1; m_texGen3D[2] = z1;
    m_texGen3D[3] = x2; m_texGen3D[4] = y2; m_texGen3D[5] = z2;
}

void CMetalBaseRenderer::SetLodBias(float value)
{
    m_lodBias = value;
}

void CMetalBaseRenderer::EnableVSync(bool enable)
{
    m_vSyncEnabled = enable;
}

void CMetalBaseRenderer::EnableTMU(bool enable)
{
}

void CMetalBaseRenderer::SelectTMU(int tnum)
{
    m_currentTMU = tnum;
}

MTLPrimitiveType CMetalBaseRenderer::ConvertPrimitiveType(int prmode)
{
    switch (prmode)
    {
        case R_PRIMV_TRIANGLES:
            return MTLPrimitiveTypeTriangle;
        case R_PRIMV_TRIANGLE_STRIP:
            return MTLPrimitiveTypeTriangleStrip;
        case R_PRIMV_TRIANGLE_FAN:
            return MTLPrimitiveTypeTriangle;
        default:
            return MTLPrimitiveTypeTriangle;
    }
}

MTLCompareFunction CMetalBaseRenderer::ConvertCompareFunction(int func)
{
    switch (func)
    {
        case 0: return MTLCompareFunctionNever;
        case 1: return MTLCompareFunctionLess;
        case 2: return MTLCompareFunctionEqual;
        case 3: return MTLCompareFunctionLessEqual;
        case 4: return MTLCompareFunctionGreater;
        case 5: return MTLCompareFunctionNotEqual;
        case 6: return MTLCompareFunctionGreaterEqual;
        case 7: return MTLCompareFunctionAlways;
        default: return MTLCompareFunctionLess;
    }
}

MTLBlendFactor CMetalBaseRenderer::ConvertBlendFactor(int factor)
{
    switch (factor)
    {
        case 0: return MTLBlendFactorZero;
        case 1: return MTLBlendFactorOne;
        case 2: return MTLBlendFactorSourceColor;
        case 3: return MTLBlendFactorOneMinusSourceColor;
        case 4: return MTLBlendFactorSourceAlpha;
        case 5: return MTLBlendFactorOneMinusSourceAlpha;
        case 6: return MTLBlendFactorDestinationAlpha;
        case 7: return MTLBlendFactorOneMinusDestinationAlpha;
        default: return MTLBlendFactorOne;
    }
}

int CMetalBaseRenderer::GetVertexFormatSize(int vertexformat)
{
    switch (vertexformat)
    {
        case VERTEX_FORMAT_P3F:
            return sizeof(struct_VERTEX_FORMAT_P3F);
        case VERTEX_FORMAT_P3F_COL4UB:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB);
        case VERTEX_FORMAT_P3F_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_TEX2F);
        case VERTEX_FORMAT_P3F_COL4UB_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
        case VERTEX_FORMAT_TRP3F_COL4UB_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_TRP3F_COL4UB_TEX2F);
        case VERTEX_FORMAT_P3F_COL4UB_COL4UB:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB);
        case VERTEX_FORMAT_P3F_N:
            return sizeof(struct_VERTEX_FORMAT_P3F_N);
        case VERTEX_FORMAT_P3F_N_COL4UB:
            return sizeof(struct_VERTEX_FORMAT_P3F_N_COL4UB);
        case VERTEX_FORMAT_P3F_N_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_N_TEX2F);
        case VERTEX_FORMAT_P3F_N_COL4UB_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_N_COL4UB_TEX2F);
        case VERTEX_FORMAT_P3F_N_COL4UB_COL4UB:
            return sizeof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB);
        case VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F);
        case VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F);
        case VERTEX_FORMAT_T3F_B3F_N3F:
            return sizeof(SPipTangents);
        case VERTEX_FORMAT_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_TEX2F);
        case VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F);
        default:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
    }
}

MTLVertexDescriptor* CMetalBaseRenderer::CreateVertexDescriptor(int vertexformat)
{
    MTLVertexDescriptor* descriptor = [[MTLVertexDescriptor alloc] init];
    
    int stride = GetVertexFormatSize(vertexformat);
    if (stride == 0)
        return nil;
    
    descriptor.layouts[0].stride = stride;
    descriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    descriptor.layouts[0].stepRate = 1;
    
    descriptor.attributes[0].format = MTLVertexFormatFloat3;
    descriptor.attributes[0].offset = 0;
    descriptor.attributes[0].bufferIndex = 0;
    
    switch (vertexformat)
    {
        case VERTEX_FORMAT_P3F_COL4UB_TEX2F:
            descriptor.attributes[1].format = MTLVertexFormatUChar4;
            descriptor.attributes[1].offset = 12;
            descriptor.attributes[1].bufferIndex = 0;
            descriptor.attributes[2].format = MTLVertexFormatFloat2;
            descriptor.attributes[2].offset = 16;
            descriptor.attributes[2].bufferIndex = 0;
            break;
            
        case VERTEX_FORMAT_P3F_N_COL4UB_TEX2F:
            descriptor.attributes[1].format = MTLVertexFormatFloat3;
            descriptor.attributes[1].offset = 12;
            descriptor.attributes[1].bufferIndex = 0;
            descriptor.attributes[2].format = MTLVertexFormatUChar4;
            descriptor.attributes[2].offset = 24;
            descriptor.attributes[2].bufferIndex = 0;
            descriptor.attributes[3].format = MTLVertexFormatFloat2;
            descriptor.attributes[3].offset = 28;
            descriptor.attributes[3].bufferIndex = 0;
            break;
            
        case VERTEX_FORMAT_P3F_TEX2F:
            descriptor.attributes[1].format = MTLVertexFormatFloat2;
            descriptor.attributes[1].offset = 12;
            descriptor.attributes[1].bufferIndex = 0;
            break;
            
        case VERTEX_FORMAT_P3F_N:
            descriptor.attributes[1].format = MTLVertexFormatFloat3;
            descriptor.attributes[1].offset = 12;
            descriptor.attributes[1].bufferIndex = 0;
            break;
    }
    
    return descriptor;
}

id<MTLBuffer> CMetalBaseRenderer::LookupStreamBuffer(const CVertexBuffer* src, int streamIndex) const
{
    if (!src)
        return nil;

    const int bufferId = src->m_VS[streamIndex].m_VertBuf.m_nID;
    if (bufferId > 0 && bufferId < static_cast<int>(m_vertexBuffers.size()))
    {
        return m_vertexBuffers[bufferId];
    }

    return nil;
}

int CMetalBaseRenderer::GetWidth()
{
    return m_width;
}

int CMetalBaseRenderer::GetHeight()
{
    return m_height;
}

int CMetalBaseRenderer::GetColorBpp()
{
    return m_cbpp;
}

int CMetalBaseRenderer::GetDepthBpp()
{
    return m_zbpp;
}

int CMetalBaseRenderer::GetStencilBpp()
{
    return m_sbpp;
}

CRendElement* CMetalBaseRenderer::EF_CreateRE(EDataType edt)
{
    extern CRendElement* CreateMetalRenderElement(EDataType edt);
    
    CRendElement* re = CreateMetalRenderElement(edt);
    
    if (!re)
    {
        iLog->Log("Warning: Failed to create render element for type %d\n", (int)edt);
    }
    
    return re;
}

void CMetalBaseRenderer::CheckError(const char* comment)
{
}

int CMetalBaseRenderer::GetFeatures()
{
    if (!m_device)
        return 0;
        
    int features = 0;
    features |= RFT_MULTITEXTURE;
    features |= RFT_BUMP;
    features |= RFT_HWGAMMA;
    features |= RFT_ALLOWRECTTEX;
    features |= RFT_COMPRESSTEXTURE;
    features |= RFT_ALLOWANISOTROPIC;
    features |= RFT_SUPPORTZBIAS;
    features |= RFT_HW_VS;
    features |= RFT_HW_PS20;
    features |= RFT_HW_PS30;
    features |= RFT_HW_HDR;
    features |= RFT_SUPPORTFSAA;
    features |= RFT_DEPTHMAPS;
    
    return features;
}

int CMetalBaseRenderer::GetMaxTextureMemory()
{
    if (!m_device)
        return 0;
    
    return 256 * 1024 * 1024;
}

#endif

// Part 3: Projection, Utility Methods, and Remaining Stubs

#if defined(__APPLE__) && defined(__MACH__)

void CMetalBaseRenderer::ProjectToScreen(float ptx, float pty, float ptz, 
                                        float* sx, float* sy, float* sz)
{
    if (!sx || !sy || !sz)
        return;
    
    UpdateMatrices();
    
    Vec3 worldPos(ptx, pty, ptz);
    Matrix44 mvp = m_modelViewProjectionMatrix;
    
    float w = mvp(3,0) * worldPos.x + mvp(3,1) * worldPos.y + 
              mvp(3,2) * worldPos.z + mvp(3,3);
    
    if (fabs(w) < 0.0001f)
        w = 1.0f;
    
    float clipX = (mvp(0,0) * worldPos.x + mvp(0,1) * worldPos.y + 
                   mvp(0,2) * worldPos.z + mvp(0,3)) / w;
    float clipY = (mvp(1,0) * worldPos.x + mvp(1,1) * worldPos.y + 
                   mvp(1,2) * worldPos.z + mvp(1,3)) / w;
    float clipZ = (mvp(2,0) * worldPos.x + mvp(2,1) * worldPos.y + 
                   mvp(2,2) * worldPos.z + mvp(2,3)) / w;
    
    *sx = (clipX * 0.5f + 0.5f) * m_viewportWidth + m_viewportX;
    *sy = (1.0f - (clipY * 0.5f + 0.5f)) * m_viewportHeight + m_viewportY;
    *sz = clipZ;
}

int CMetalBaseRenderer::UnProject(float sx, float sy, float sz, 
                                 float* px, float* py, float* pz,
                                 const float modelMatrix[16], 
                                 const float projMatrix[16], 
                                 const int viewport[4])
{
    if (!px || !py || !pz)
        return 0;
    
    float normX = (sx - viewport[0]) / viewport[2] * 2.0f - 1.0f;
    float normY = 1.0f - (sy - viewport[1]) / viewport[3] * 2.0f;
    float normZ = sz;
    
    Matrix44 model, proj;
    for (int i = 0; i < 16; ++i)
    {
        model.GetData()[i] = modelMatrix[i];
        proj.GetData()[i] = projMatrix[i];
    }
    
    Matrix44 mvp = proj * model;
    Matrix44 invMVP = mvp;
    invMVP.Invert44();
    
    float clipW = 1.0f;
    float worldX = invMVP(0,0) * normX + invMVP(0,1) * normY + 
                   invMVP(0,2) * normZ + invMVP(0,3) * clipW;
    float worldY = invMVP(1,0) * normX + invMVP(1,1) * normY + 
                   invMVP(1,2) * normZ + invMVP(1,3) * clipW;
    float worldZ = invMVP(2,0) * normX + invMVP(2,1) * normY + 
                   invMVP(2,2) * normZ + invMVP(2,3) * clipW;
    float w = invMVP(3,0) * normX + invMVP(3,1) * normY + 
              invMVP(3,2) * normZ + invMVP(3,3) * clipW;
    
    if (fabs(w) > 0.0001f)
    {
        *px = worldX / w;
        *py = worldY / w;
        *pz = worldZ / w;
        return 1;
    }
    
    return 0;
}

int CMetalBaseRenderer::UnProjectFromScreen(float sx, float sy, float sz, 
                                           float* px, float* py, float* pz)
{
    int viewport[4] = {m_viewportX, m_viewportY, m_viewportWidth, m_viewportHeight};
    
    return UnProject(sx, sy, sz, px, py, pz, 
                    m_viewMatrix.GetData(), 
                    m_projectionMatrix.GetData(), 
                    viewport);
}

Vec3 CMetalBaseRenderer::GetUnProject(const Vec3& WindowCoords, const CCamera& cam)
{
    float px, py, pz;
    
    int viewport[4] = {0, 0, m_width, m_height};
    float modelMat[16], projMat[16];
    
    memcpy(modelMat, m_viewMatrix.GetData(), 16 * sizeof(float));
    memcpy(projMat, m_projectionMatrix.GetData(), 16 * sizeof(float));
    
    UnProject(WindowCoords.x, WindowCoords.y, WindowCoords.z,
             &px, &py, &pz, modelMat, projMat, viewport);
    
    return Vec3(px, py, pz);
}

void CMetalBaseRenderer::RenderToViewport(const CCamera& cam, float x, float y, 
                                         float width, float height)
{
    SetCamera(cam);
    SetViewport((int)x, (int)y, (int)width, (int)height);
}

void CMetalBaseRenderer::Draw3dBBox(const Vec3& mins, const Vec3& maxs, int nPrimType)
{
}

void CMetalBaseRenderer::Draw3dPrim(const Vec3& mins, const Vec3& maxs, 
                                   int nPrimType, const float* fRGBA)
{
}

bool CMetalBaseRenderer::ChangeDisplay(unsigned int width, unsigned int height, unsigned int cbpp)
{
    m_width = width;
    m_height = height;
    m_cbpp = cbpp;
    return true;
}

void CMetalBaseRenderer::ChangeViewport(unsigned int x, unsigned int y, 
                                       unsigned int width, unsigned int height)
{
    SetViewport(x, y, width, height);
}

bool CMetalBaseRenderer::SaveTga(unsigned char* sourcedata, int sourceformat, 
                                int w, int h, const char* filename, bool flip)
{
    return false;
}

void CMetalBaseRenderer::GetMemoryUsage(ICrySizer* Sizer)
{
}

void CMetalBaseRenderer::ScreenShot(const char* filename)
{
}

void CMetalBaseRenderer::MakeCurrent()
{
}

void CMetalBaseRenderer::ShareResources(IRenderer* renderer)
{
}

void CMetalBaseRenderer::Release()
{
    delete this;
}

void CMetalBaseRenderer::FreeResources(int nFlags)
{
    if (nFlags & FRR_REINITHW)
    {
        CleanupUniformBuffers();
        CleanupDepthStencilTextures();
        CleanupDynamicVBPools();
    }

    if (nFlags & FRR_ALL)
    {
        WaitForAllCommandBuffers();
        CleanupDynamicVBPools();
        CleanupUniformBuffers();
        CleanupDepthStencilTextures();
    }
}

void CMetalBaseRenderer::RefreshResources(int nFlags)
{
}

void CMetalBaseRenderer::PreLoad()
{
}

void CMetalBaseRenderer::PostLoad()
{
}

int CMetalBaseRenderer::EnumDisplayFormats(TArray<SDispFormat>& Formats, bool bReset)
{
    if (bReset)
        Formats.Clear();
    
    SDispFormat format;
    format.m_Width = 1920;
    format.m_Height = 1080;
    format.m_BPP = 32;
    Formats.AddElem(format);
    
    format.m_Width = 1280;
    format.m_Height = 720;
    Formats.AddElem(format);
    
    return Formats.Num();
}

bool CMetalBaseRenderer::ChangeResolution(int nNewWidth, int nNewHeight, 
                                         int nNewColDepth, int nNewRefreshHZ, bool bFullScreen)
{
    m_width = nNewWidth;
    m_height = nNewHeight;
    m_cbpp = nNewColDepth;
    m_fullscreen = bFullScreen;
    return true;
}

bool CMetalBaseRenderer::SetCurrentContext(WIN_HWND hWnd)
{
    return true;
}

bool CMetalBaseRenderer::CreateContext(WIN_HWND hWnd, bool bAllowFSAA)
{
    return true;
}

bool CMetalBaseRenderer::DeleteContext(WIN_HWND hWnd)
{
    return true;
}

void CMetalBaseRenderer::UpdateRenderPassDescriptor()
{
}

id<MTLTexture> CMetalBaseRenderer::CreateMetalTexture(int width, int height, MTLPixelFormat format)
{
    if (!m_device)
        return nil;
        
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:NO];
    
    return [m_device newTextureWithDescriptor:descriptor];
}

id<MTLBuffer> CMetalBaseRenderer::CreateMetalBuffer(void* data, size_t size, MTLResourceOptions options)
{
    if (!m_device)
        return nil;
        
    if (data)
        return [m_device newBufferWithBytes:data length:size options:options];
    else
        return [m_device newBufferWithLength:size options:options];
}

int CMetalBaseRenderer::CreateVertexBuffer(const void* data, size_t size)
{
    if (!m_device || size == 0)
        return 0;
    
    id<MTLBuffer> buffer = CreateMetalBuffer((void*)data, size, MTLResourceStorageModeShared);
    if (!buffer)
        return 0;
    
    int id = m_nextVertexBufferId++;
    if (id >= (int)m_vertexBuffers.size())
    {
        m_vertexBuffers.resize(id + 1, nil);
    }
    m_vertexBuffers[id] = buffer;
    
    return id;
}

int CMetalBaseRenderer::CreateIndexBuffer(const void* data, size_t size)
{
    if (!m_device || size == 0)
        return 0;
    
    id<MTLBuffer> buffer = CreateMetalBuffer((void*)data, size, MTLResourceStorageModeShared);
    if (!buffer)
        return 0;
    
    int id = m_nextIndexBufferId++;
    if (id >= (int)m_indexBuffers.size())
    {
        m_indexBuffers.resize(id + 1, nil);
    }
    m_indexBuffers[id] = buffer;
    
    return id;
}

void CMetalBaseRenderer::UpdateVertexBuffer(int bufferId, const void* data, size_t size)
{
    if (bufferId <= 0 || bufferId >= (int)m_vertexBuffers.size() || !data || size == 0)
        return;
    
    id<MTLBuffer> buffer = m_vertexBuffers[bufferId];
    if (!buffer)
        return;
    
    memcpy([buffer contents], data, size);
    
    if (buffer.storageMode == MTLStorageModeManaged)
    {
        [buffer didModifyRange:NSMakeRange(0, size)];
    }
}

void CMetalBaseRenderer::UpdateIndexBuffer(int bufferId, const void* data, size_t size)
{
    if (bufferId <= 0 || bufferId >= (int)m_indexBuffers.size() || !data || size == 0)
        return;
    
    id<MTLBuffer> buffer = m_indexBuffers[bufferId];
    if (!buffer)
        return;
    
    memcpy([buffer contents], data, size);
    
    if (buffer.storageMode == MTLStorageModeManaged)
    {
        [buffer didModifyRange:NSMakeRange(0, size)];
    }
}

void CMetalBaseRenderer::ReleaseVertexBuffer(int bufferId)
{
    if (bufferId > 0 && bufferId < (int)m_vertexBuffers.size())
    {
        m_vertexBuffers[bufferId] = nil;
    }
}

void CMetalBaseRenderer::ReleaseIndexBuffer(int bufferId)
{
    if (bufferId > 0 && bufferId < (int)m_indexBuffers.size())
    {
        m_indexBuffers[bufferId] = nil;
    }
}

id<MTLBuffer> CMetalBaseRenderer::GetVertexBuffer(int bufferId)
{
    if (bufferId > 0 && bufferId < (int)m_vertexBuffers.size())
        return m_vertexBuffers[bufferId];
    return nil;
}

id<MTLBuffer> CMetalBaseRenderer::GetIndexBuffer(int bufferId)
{
    if (bufferId > 0 && bufferId < (int)m_indexBuffers.size())
        return m_indexBuffers[bufferId];
    return nil;
}

int CMetalBaseRenderer::GetFrameID(bool bIncludeRecursiveCalls)
{
    return CRenderer::GetFrameID(bIncludeRecursiveCalls);
}

void CMetalBaseRenderer::SetType(char type)
{
    const char resolvedType = type == R_METAL_RENDERER ? type : R_METAL_RENDERER;

    if (type != R_METAL_RENDERER)
    {
        if (iLog)
        {
            iLog->Log("MetalBaseRenderer: forcing renderer type to R_METAL_RENDERER (requested: %d)\n", type);
        }
    }

    CRenderer::SetType(resolvedType);
}

#endif

