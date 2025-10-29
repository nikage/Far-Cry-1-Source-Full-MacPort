////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalOptimizations.cpp
//  Version:     v1.00
//  Created:     29/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal-specific optimizations implementation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalOptimizations.h"
#include "MetalBaseRenderer.h"
#include <cassert>

//=========================================================================
// CMetalResourcePool Implementation
//=========================================================================

CMetalResourcePool::CMetalResourcePool(CMetalBaseRenderer* renderer)
    : m_renderer(renderer)
    , m_currentFrame(0)
{
    assert(renderer && "CMetalResourcePool: renderer cannot be null!");
}

CMetalResourcePool::~CMetalResourcePool()
{
    for (auto& poolPair : m_bufferPools)
    {
        BufferPool& pool = poolPair.second;
        pool.availableBuffers.clear();
        pool.usedBuffers.clear();
    }
}

id<MTLBuffer> CMetalResourcePool::AllocateBuffer(size_t size, MTLResourceOptions options)
{
    assert(m_renderer && "CMetalResourcePool: renderer is null!");
    assert(m_renderer->m_device && "CMetalResourcePool: Metal device is null!");
    assert(size > 0 && "CMetalResourcePool: buffer size must be positive!");
    
    if (!m_renderer || !m_renderer->m_device || size == 0)
        return nil;
    
    size_t poolKey = (size << 16) | static_cast<size_t>(options);
    
    BufferPool& pool = m_bufferPools[poolKey];
    pool.bufferSize = size;
    pool.options = options;
    
    id<MTLBuffer> buffer = nil;
    
    if (!pool.availableBuffers.empty())
    {
        buffer = pool.availableBuffers.back();
        pool.availableBuffers.pop_back();
    }
    else
    {
        buffer = [m_renderer->m_device newBufferWithLength:size options:options];
    }
    
    if (buffer)
    {
        pool.usedBuffers.push_back(buffer);
    }
    
    return buffer;
}

void CMetalResourcePool::ReleaseBuffer(id<MTLBuffer> buffer)
{
    assert(buffer && "CMetalResourcePool: cannot release null buffer!");
    
    if (!buffer)
        return;
    
    size_t size = [buffer length];
    MTLResourceOptions options = [buffer resourceOptions];
    size_t poolKey = (size << 16) | static_cast<size_t>(options);
    
    auto it = m_bufferPools.find(poolKey);
    if (it != m_bufferPools.end())
    {
        BufferPool& pool = it->second;
        
        auto usedIt = std::find(pool.usedBuffers.begin(), pool.usedBuffers.end(), buffer);
        if (usedIt != pool.usedBuffers.end())
        {
            pool.usedBuffers.erase(usedIt);
            pool.availableBuffers.push_back(buffer);
        }
    }
}

void CMetalResourcePool::BeginFrame()
{
    m_currentFrame++;
}

void CMetalResourcePool::EndFrame()
{
    for (auto& poolPair : m_bufferPools)
    {
        BufferPool& pool = poolPair.second;
        
        for (auto& buffer : pool.usedBuffers)
        {
            pool.availableBuffers.push_back(buffer);
        }
        pool.usedBuffers.clear();
    }
}

//=========================================================================
// CMetalIndirectCommandEncoder Implementation
//=========================================================================

CMetalIndirectCommandEncoder::CMetalIndirectCommandEncoder(CMetalBaseRenderer* renderer)
    : m_renderer(renderer)
{
    assert(renderer && "CMetalIndirectCommandEncoder: renderer cannot be null!");
}

void CMetalIndirectCommandEncoder::EncodeDrawCommand(id<MTLIndirectCommandBuffer> icb,
                                                     int index,
                                                     id<MTLRenderPipelineState> pipeline,
                                                     id<MTLBuffer> vertexBuffer,
                                                     id<MTLBuffer> indexBuffer,
                                                     int indexCount)
{
    assert(icb && "CMetalIndirectCommandEncoder: indirect command buffer is null!");
    assert(pipeline && "CMetalIndirectCommandEncoder: pipeline state is null!");
    assert(m_renderer && "CMetalIndirectCommandEncoder: renderer is null!");
    
    if (!icb || !pipeline || !m_renderer)
        return;
    
    id<MTLIndirectRenderCommand> command = [icb indirectRenderCommandAtIndex:index];
    if (!command)
    {
        assert(false && "CMetalIndirectCommandEncoder: failed to get indirect render command!");
        return;
    }
    
    [command setRenderPipelineState:pipeline];
    
    if (vertexBuffer)
    {
        [command setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    }
    
    if (indexBuffer && indexCount > 0)
    {
        [command drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                            indexCount:indexCount
                             indexType:MTLIndexTypeUInt16
                           indexBuffer:indexBuffer
                     indexBufferOffset:0
                         instanceCount:1
                            baseVertex:0
                          baseInstance:0];
    }
}

#endif // __APPLE__ && __MACH__

