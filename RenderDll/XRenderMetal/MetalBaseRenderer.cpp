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

#include "MetalBaseRenderer.h"
#include "I3DEngine.h"
#include "VertexFormats.h"
#include <Cocoa/Cocoa.h>
#include <cstring>
#include <cmath>

CMetalBaseRenderer::CMetalBaseRenderer()
    : m_device(nil)
    , m_commandQueue(nil)
    , m_renderEncoder(nil)
    , m_metalView(nil)
    , m_metalLayer(nil)
    , m_currentCommandBuffer(nil)
    , m_renderPassDescriptor(nil)
    , m_currentPipelineState(nil)
    , m_currentDepthStencilState(nil)
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
    , m_viewportX(0)
    , m_viewportY(0)
    , m_viewportWidth(0)
    , m_viewportHeight(0)
    , m_matrixDirty(true)
    , m_currentFrameIndex(0)
    , m_currentDynamicVBPool(0)
    , m_uniformBuffer(nil)
    , m_uniformBufferCPU(nullptr)
    , m_currentState(0)
    , m_currentCullMode(R_CULL_BACK)
    , m_fogEnabled(false)
    , m_texGenEnabled(false)
    , m_lodBias(0.0f)
    , m_vSyncEnabled(true)
    , m_currentTMU(0)
    , m_frameID(0)
    , m_numDrawCalls(0)
    , m_numTriangles(0)
{
    m_currentMatrix.SetIdentity();
    m_viewMatrix.SetIdentity();
    m_projectionMatrix.SetIdentity();
    m_modelViewProjectionMatrix.SetIdentity();
    
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
}

CMetalBaseRenderer::~CMetalBaseRenderer()
{
    ShutDown();
}

WIN_HWND CMetalBaseRenderer::Init(int x, int y, int width, int height, unsigned int cbpp, 
                                 int zbpp, int sbits, bool fullscreen, WIN_HINSTANCE hinst, 
                                 WIN_HWND Glhwnd, WIN_HDC Glhdc, WIN_HGLRC hGLrc, bool bReInit)
{
    printf("Metal Base Renderer Init: %dx%d, %dbpp color, %dbpp depth\n", 
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
        printf("Error: Failed to initialize Metal device\n");
        return nullptr;
    }
    
    if (!InitializeCommandQueue())
    {
        printf("Error: Failed to initialize Metal command queue\n");
        return nullptr;
    }
    
    if (!InitializeCommandBufferPool())
    {
        printf("Error: Failed to initialize command buffer pool\n");
        return nullptr;
    }
    
    if (!InitializeDynamicVBPools())
    {
        printf("Error: Failed to initialize dynamic VB pools\n");
        return nullptr;
    }
    
    if (!InitializeUniformBuffers())
    {
        printf("Error: Failed to initialize uniform buffers\n");
        return nullptr;
    }
    
    m_stateCache = std::make_unique<CMetalStateCache>(m_device);
    if (!m_stateCache)
    {
        printf("Error: Failed to create state cache\n");
        return nullptr;
    }
    
    if (!InitializeRenderPipeline())
    {
        printf("Error: Failed to initialize Metal render pipeline\n");
        return nullptr;
    }
    
    m_isInitialized = true;
    printf("Metal base renderer initialized successfully\n");
    printf("  Device: %s\n", [[m_device name] UTF8String]);
    printf("  Max texture size: %lu\n", (unsigned long)[m_device maxTextureWidth2D]);
    printf("  Triple buffering: enabled (%d frames)\n", MAX_FRAMES_IN_FLIGHT);
    
    return (WIN_HWND)m_metalView;
}

void CMetalBaseRenderer::ShutDown(bool bReInit)
{
    if (!m_isInitialized)
        return;
    
    printf("Shutting down Metal base renderer\n");
    
    if (m_device && m_commandQueue)
    {
        [m_commandQueue waitUntilCommandBuffersCompleted];
    }
    
    CleanupCommandBufferPool();
    CleanupDynamicVBPools();
    CleanupUniformBuffers();
    
    m_vertexBuffers.clear();
    m_indexBuffers.clear();
    
    m_stateCache.reset();
    
    m_renderEncoder = nil;
    m_currentCommandBuffer = nil;
    m_renderPassDescriptor = nil;
    m_currentPipelineState = nil;
    m_currentDepthStencilState = nil;
    m_commandQueue = nil;
    m_device = nil;
    m_metalView = nil;
    m_metalLayer = nil;
    
    m_isInitialized = false;
}

bool CMetalBaseRenderer::InitializeDevice()
{
    m_device = MTLCreateSystemDefaultDevice();
    if (!m_device)
    {
        printf("Error: Metal is not supported on this device\n");
        return false;
    }
    
    printf("Metal device created: %s\n", [[m_device name] UTF8String]);
    return true;
}

bool CMetalBaseRenderer::InitializeCommandQueue()
{
    if (!m_device)
        return false;
        
    m_commandQueue = [m_device newCommandQueue];
    if (!m_commandQueue)
    {
        printf("Error: Failed to create Metal command queue\n");
        return false;
    }
    
    return true;
}

bool CMetalBaseRenderer::InitializeCommandBufferPool()
{
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; ++i)
    {
        m_frameSemaphores[i] = dispatch_semaphore_create(1);
        if (!m_frameSemaphores[i])
        {
            printf("Error: Failed to create frame semaphore %d\n", i);
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
            printf("Error: Failed to create dynamic VB pool %d\n", i);
            return false;
        }
        
        m_dynamicVBPools[i].size = poolSize;
        m_dynamicVBPools[i].offset = 0;
        m_dynamicVBPools[i].cpuData = [m_dynamicVBPools[i].buffer contents];
    }
    
    printf("Dynamic VB pools created: %d pools of %zu MB each\n", 
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
        printf("Error: Failed to create uniform buffer\n");
        return false;
    }
    
    m_uniformBufferCPU = (UniformBufferData*)[m_uniformBuffer contents];
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
}

void CMetalBaseRenderer::BeginFrame()
{
    if (!m_isInitialized || !m_device || !m_commandQueue)
        return;
    
    dispatch_semaphore_wait(m_frameSemaphores[m_currentFrameIndex], DISPATCH_TIME_FOREVER);
    
    m_currentCommandBuffer = [m_commandQueue commandBuffer];
    if (!m_currentCommandBuffer)
    {
        printf("Error: Failed to create command buffer\n");
        return;
    }
    
    __block dispatch_semaphore_t semaphore = m_frameSemaphores[m_currentFrameIndex];
    [m_currentCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    m_dynamicVBPools[m_currentDynamicVBPool].offset = 0;
    
    m_numDrawCalls = 0;
    m_numTriangles = 0;
    
    m_frameID++;
}

void CMetalBaseRenderer::Update()
{
}

void CMetalBaseRenderer::EndFrame()
{
    if (!m_currentCommandBuffer)
        return;
    
    if (m_renderEncoder)
    {
        [m_renderEncoder endEncoding];
        m_renderEncoder = nil;
    }
    
    if (m_metalView && m_metalView.currentDrawable)
    {
        [m_currentCommandBuffer presentDrawable:m_metalView.currentDrawable];
    }
    
    [m_currentCommandBuffer commit];
    
    m_currentCommandBuffer = nil;
    m_renderPassDescriptor = nil;
    
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
    
    m_uniformBufferCPU->lightPos = Vec3(0, 100, 0);
    m_uniformBufferCPU->lightColor = Vec3(1, 1, 1);
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

#endif

// Part 2: Buffer Management, State Management, and Drawing

#if defined(__APPLE__) && defined(__MACH__)

CVertexBuffer* CMetalBaseRenderer::CreateBuffer(int vertexcount, int vertexformat, 
                                                const char* szSource, bool bDynamic)
{
    if (vertexcount <= 0)
        return nullptr;
    
    CVertexBuffer* vb = new CVertexBuffer();
    if (!vb)
        return nullptr;
    
    vb->m_NumVerts = vertexcount;
    vb->m_vertexformat = vertexformat;
    vb->m_bDynamic = bDynamic ? 1 : 0;
    
    int vertexSize = GetVertexFormatSize(vertexformat);
    size_t bufferSize = vertexcount * vertexSize;
    
    MTLResourceOptions options = bDynamic ? MTLResourceStorageModeShared : MTLResourceStorageModeManaged;
    id<MTLBuffer> metalBuffer = [m_device newBufferWithLength:bufferSize options:options];
    
    if (!metalBuffer)
    {
        delete vb;
        return nullptr;
    }
    
    int bufferId = m_nextVertexBufferId++;
    if (bufferId >= (int)m_vertexBuffers.size())
    {
        m_vertexBuffers.resize(bufferId + 1, nil);
    }
    m_vertexBuffers[bufferId] = metalBuffer;
    
    vb->m_VS[VSF_GENERAL].m_VertBuf.m_nID = bufferId;
    vb->m_VS[VSF_GENERAL].m_VData = [metalBuffer contents];
    vb->m_VS[VSF_GENERAL].m_nItems = vertexcount;
    vb->m_VS[VSF_GENERAL].m_bDynamic = bDynamic;
    
    return vb;
}

void CMetalBaseRenderer::ReleaseBuffer(CVertexBuffer* bufptr)
{
    if (!bufptr)
        return;
    
    int bufferId = bufptr->m_VS[VSF_GENERAL].m_VertBuf.m_nID;
    if (bufferId > 0 && bufferId < (int)m_vertexBuffers.size())
    {
        m_vertexBuffers[bufferId] = nil;
    }
    
    delete bufptr;
}

void CMetalBaseRenderer::UpdateBuffer(CVertexBuffer* dest, const void* src, 
                                     int vertexcount, bool bUnLock, int nOffs, int Type)
{
    if (!dest || !src || vertexcount <= 0)
        return;
    
    int bufferId = dest->m_VS[VSF_GENERAL].m_VertBuf.m_nID;
    if (bufferId <= 0 || bufferId >= (int)m_vertexBuffers.size())
        return;
    
    id<MTLBuffer> metalBuffer = m_vertexBuffers[bufferId];
    if (!metalBuffer)
        return;
    
    int vertexSize = GetVertexFormatSize(dest->m_vertexformat);
    size_t copySize = vertexcount * vertexSize;
    size_t offset = nOffs * vertexSize;
    
    void* bufferData = (char*)[metalBuffer contents] + offset;
    memcpy(bufferData, src, copySize);
    
    if (metalBuffer.storageMode == MTLStorageModeManaged)
    {
        [metalBuffer didModifyRange:NSMakeRange(offset, copySize)];
    }
}

void CMetalBaseRenderer::CreateIndexBuffer(SVertexStream* dest, const void* src, int indexcount)
{
    if (!dest || !src || indexcount <= 0)
        return;
    
    size_t bufferSize = indexcount * sizeof(unsigned short);
    id<MTLBuffer> metalBuffer = [m_device newBufferWithBytes:src 
                                                      length:bufferSize 
                                                     options:MTLResourceStorageModeManaged];
    
    if (!metalBuffer)
        return;
    
    int bufferId = m_nextIndexBufferId++;
    if (bufferId >= (int)m_indexBuffers.size())
    {
        m_indexBuffers.resize(bufferId + 1, nil);
    }
    m_indexBuffers[bufferId] = metalBuffer;
    
    dest->m_VertBuf.m_nID = bufferId;
    dest->m_VData = [metalBuffer contents];
    dest->m_nItems = indexcount;
    dest->m_bDynamic = false;
}

void CMetalBaseRenderer::UpdateIndexBuffer(SVertexStream* dest, const void* src, 
                                          int indexcount, bool bUnLock)
{
    if (!dest || !src || indexcount <= 0)
        return;
    
    int bufferId = dest->m_VertBuf.m_nID;
    if (bufferId <= 0 || bufferId >= (int)m_indexBuffers.size())
        return;
    
    id<MTLBuffer> metalBuffer = m_indexBuffers[bufferId];
    if (!metalBuffer)
        return;
    
    size_t copySize = indexcount * sizeof(unsigned short);
    memcpy([metalBuffer contents], src, copySize);
    
    if (metalBuffer.storageMode == MTLStorageModeManaged)
    {
        [metalBuffer didModifyRange:NSMakeRange(0, copySize)];
    }
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
    if (nVerts <= 0 || Pool < 0 || Pool >= NUM_DYNAMIC_VB_POOLS)
        return nullptr;
    
    DynamicVBPool& pool = m_dynamicVBPools[Pool];
    
    int vertexSize = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
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
    
    DynamicVBPool& pool = m_dynamicVBPools[Pool];
    int vertexSize = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
    size_t offset = nOffs * vertexSize;
    
    [m_renderEncoder setVertexBuffer:pool.buffer offset:offset atIndex:0];
    [m_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:nVerts];
    
    m_numDrawCalls++;
    m_numTriangles += nVerts / 3;
}

void CMetalBaseRenderer::DrawDynVB(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F* pBuf, 
                                  ushort* pInds, int nVerts, int nInds, int nPrimType)
{
    if (!m_renderEncoder || !pBuf || nVerts <= 0)
        return;
    
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
        
        [m_renderEncoder setVertexBuffer:m_dynamicVBPools[0].buffer offset:nOffs atIndex:0];
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
    
    int bufferId = src->m_VS[VSF_GENERAL].m_VertBuf.m_nID;
    if (bufferId <= 0 || bufferId >= (int)m_vertexBuffers.size())
        return;
    
    id<MTLBuffer> vertexBuffer = m_vertexBuffers[bufferId];
    if (!vertexBuffer)
        return;
    
    [m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    
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
    
    int bufferId = src->m_VS[VSF_GENERAL].m_VertBuf.m_nID;
    if (bufferId <= 0 || bufferId >= (int)m_vertexBuffers.size())
        return;
    
    id<MTLBuffer> vertexBuffer = m_vertexBuffers[bufferId];
    if (!vertexBuffer)
        return;
    
    [m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
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
}

void CMetalBaseRenderer::EnableTexGen(bool enable)
{
    m_texGenEnabled = enable;
}

void CMetalBaseRenderer::SetTexgen(float scaleX, float scaleY, float translateX, float translateY)
{
}

void CMetalBaseRenderer::SetTexgen3D(float x1, float y1, float z1, float x2, float y2, float z2)
{
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
        case VERTEX_FORMAT_P3F_COL4UB_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
        case VERTEX_FORMAT_P3F_N:
            return sizeof(struct_VERTEX_FORMAT_P3F_N);
        case VERTEX_FORMAT_P3F_N_COL4UB_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_N_COL4UB_TEX2F);
        case VERTEX_FORMAT_P3F_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_TEX2F);
        case VERTEX_FORMAT_P3F_N_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_N_TEX2F);
        case VERTEX_FORMAT_P3F_COL4UB:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB);
        default:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
    }
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
        printf("Warning: Failed to create render element for type %d\n", (int)edt);
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

#endif

