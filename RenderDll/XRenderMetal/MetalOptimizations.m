////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalOptimizations.h
//  Version:     v1.00
//  Created:     29/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal-specific optimizations and modern features
//               - State caching
//               - Argument buffers
//               - Indirect rendering
//               - Resource heaps
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_OPTIMIZATIONS_H
#define METAL_OPTIMIZATIONS_H

#if defined(__APPLE__) && defined(__MACH__)

#include <Metal/Metal.h>
#include <unordered_map>
#include <vector>

// Forward declarations
class CMetalBaseRenderer;

//=========================================================================
// MetalResourcePool - Efficient resource management with pooling
//=========================================================================

/// Efficient GPU buffer pooling with per-frame recycling
///
/// Reduces Metal buffer allocation overhead by reusing buffers across frames.
/// Particularly beneficial for dynamic geometry (particles, UI, temp meshes).
///
/// Strategy:
/// - Pools buffers by size and options (hash-based lookup)
/// - Tracks "available" vs "in-use" buffers per pool
/// - Resets all buffers to available at frame end
/// - Never deallocates buffers (grows to steady state)
///
/// Performance Impact:
/// - Typical allocation: O(1) from pool vs O(n) Metal allocation
/// - Reduces frame hitches from buffer creation
/// - Memory tradeoff: Higher steady-state usage for better perf
///
/// Thread Safety: NOT thread-safe (single-threaded renderer)
///
/// Usage Pattern:
///   pool->BeginFrame();
///   id<MTLBuffer> buf = pool->AllocateBuffer(1024, MTLResourceStorageModeShared);
///   // ... use buffer ...
///   pool->ReleaseBuffer(buf);  // Returns to pool
///   pool->EndFrame();          // Recycles all buffers
class CMetalResourcePool
{
public:
    /// Constructs buffer pool for the given renderer
    /// @param renderer Renderer that owns this pool (borrowed reference)
    CMetalResourcePool(CMetalBaseRenderer* renderer);
    
    /// Destroys pool and releases all cached buffers
    ~CMetalResourcePool();
    
    /// Allocates or reuses a buffer from the pool
    /// @param size Buffer size in bytes (must be > 0)
    /// @param options Metal resource options (storage mode, CPU cache mode)
    /// @return Metal buffer of requested size/options, or nil on failure
    /// @note Returns pooled buffer if available, otherwise creates new one
    id<MTLBuffer> AllocateBuffer(size_t size, MTLResourceOptions options);
    
    /// Returns a buffer to the pool for reuse
    /// @param buffer Buffer to release (must have been allocated from this pool)
    /// @note Buffer is not deallocated, just marked available for reuse
    void ReleaseBuffer(id<MTLBuffer> buffer);
    
    /// Marks the start of a new frame
    /// @note Increments frame counter for tracking
    void BeginFrame();
    
    /// Recycles all used buffers back to available pool
    /// @note Call at frame end to make all buffers available for next frame
    void EndFrame();
    
private:
    CMetalBaseRenderer* m_renderer;
    
    struct BufferPool
    {
        std::vector<id<MTLBuffer>> availableBuffers;
        std::vector<id<MTLBuffer>> usedBuffers;
        size_t bufferSize;
        MTLResourceOptions options;
    };
    
    std::unordered_map<size_t, BufferPool> m_bufferPools;
    int m_currentFrame;
};

//=========================================================================
// MetalIndirectCommandEncoder - GPU-driven rendering support
//=========================================================================

/// GPU-driven rendering support via indirect command buffers
///
/// Enables encoding draw commands into GPU buffers that can be executed
/// without CPU intervention, reducing driver overhead for scenes with
/// many similar objects (e.g., vegetation, debris, particles).
///
/// Ownership Model:
/// - Does NOT own m_renderer pointer (borrowed reference)
/// - Caller MUST ensure renderer outlives this object
/// - No custom destructor needed (Rule of Zero)
///
/// Metal API Requirements:
/// - Requires Metal 2.0+ (macOS 10.13+)
/// - Indirect command buffers must be pre-allocated
/// - Each command encodes a complete draw call
///
/// Performance Benefits:
/// - Reduces CPU→GPU communication overhead
/// - Enables GPU culling and LOD selection
/// - Better parallelization of draw call submission
///
/// Usage Example:
///   CMetalIndirectCommandEncoder encoder(renderer);
///   encoder.EncodeDrawCommand(icb, 0, pipeline, vb, ib, count);
///   [renderEncoder executeCommandsInBuffer:icb withRange:NSMakeRange(0, 1)];
class CMetalIndirectCommandEncoder
{
public:
    /// Constructs encoder with borrowed reference to renderer
    /// @param renderer Non-owning pointer to Metal renderer (must outlive this object)
    CMetalIndirectCommandEncoder(CMetalBaseRenderer* renderer);
    
    /// Encodes a single indexed draw call into an indirect command buffer
    ///
    /// @param icb Indirect command buffer to encode into (must be pre-allocated)
    /// @param index Slot index in the command buffer (0-based)
    /// @param pipeline Pipeline state to use for this draw call
    /// @param vertexBuffer Vertex data buffer (can be nil if vertices in pipeline)
    /// @param indexBuffer Index buffer for indexed drawing
    /// @param indexCount Number of indices to draw (must be > 0 for indexed draws)
    ///
    /// Preconditions:
    /// - icb must be created with MTLIndirectCommandTypeDrawIndexed
    /// - index must be < command buffer size
    /// - pipeline must be compatible with current render pass
    ///
    /// Encoded Command:
    /// - Sets pipeline state
    /// - Binds vertex buffer at index 0
    /// - Issues drawIndexedPrimitives call with specified parameters
    ///
    /// Example:
    ///   encoder.EncodeDrawCommand(icb, 0, treePipeline, treeVB, treeIB, 3600);
    ///   // Encodes draw call for tree geometry with 1200 triangles
    void EncodeDrawCommand(id<MTLIndirectCommandBuffer> icb, 
                          int index,
                          id<MTLRenderPipelineState> pipeline,
                          id<MTLBuffer> vertexBuffer,
                          id<MTLBuffer> indexBuffer,
                          int indexCount);
    
private:
    CMetalBaseRenderer* m_renderer;  ///< Non-owning pointer to renderer (borrowed)
};

//=========================================================================
// Optimization Statistics
//=========================================================================

struct MetalOptimizationStats
{
    // State caching
    int pipelineStateHits;
    int pipelineStateMisses;
    int depthStencilStateHits;
    int depthStencilStateMisses;
    int samplerStateHits;
    int samplerStateMisses;
    
    // Resource pooling
    int bufferAllocations;
    int bufferReuses;
    
    // Draw calls
    int drawCalls;
    int drawCallsMerged;
    int indirectDrawCalls;
    
    void Reset()
    {
        pipelineStateHits = 0;
        pipelineStateMisses = 0;
        depthStencilStateHits = 0;
        depthStencilStateMisses = 0;
        samplerStateHits = 0;
        samplerStateMisses = 0;
        bufferAllocations = 0;
        bufferReuses = 0;
        drawCalls = 0;
        drawCallsMerged = 0;
        indirectDrawCalls = 0;
    }
};

#endif // __APPLE__ && __MACH__

#endif // METAL_OPTIMIZATIONS_H

