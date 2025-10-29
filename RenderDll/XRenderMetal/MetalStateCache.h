////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalStateCache.h
//  Version:     v1.00
//  Created:     30/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal render state caching system
//               Implements State pattern for efficient state management
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_STATE_CACHE_H
#define METAL_STATE_CACHE_H

#if defined(__APPLE__) && defined(__MACH__)

#include <Metal/Metal.h>
#include <unordered_map>
#include <memory>

struct MetalPipelineStateKey
{
    uint64_t vertexFunctionHash;
    uint64_t fragmentFunctionHash;
    uint64_t vertexFormatHash;
    uint32_t renderStateHash;
    MTLPixelFormat colorPixelFormat;
    MTLPixelFormat depthPixelFormat;
    
    bool operator==(const MetalPipelineStateKey& other) const
    {
        return vertexFunctionHash == other.vertexFunctionHash &&
               fragmentFunctionHash == other.fragmentFunctionHash &&
               vertexFormatHash == other.vertexFormatHash &&
               renderStateHash == other.renderStateHash &&
               colorPixelFormat == other.colorPixelFormat &&
               depthPixelFormat == other.depthPixelFormat;
    }
};

struct MetalPipelineStateKeyHash
{
    size_t operator()(const MetalPipelineStateKey& key) const
    {
        size_t h1 = std::hash<uint64_t>{}(key.vertexFunctionHash);
        size_t h2 = std::hash<uint64_t>{}(key.fragmentFunctionHash);
        size_t h3 = std::hash<uint64_t>{}(key.vertexFormatHash);
        size_t h4 = std::hash<uint32_t>{}(key.renderStateHash);
        return h1 ^ (h2 << 1) ^ (h3 << 2) ^ (h4 << 3);
    }
};

struct MetalDepthStencilStateKey
{
    bool depthTestEnabled;
    bool depthWriteEnabled;
    MTLCompareFunction depthCompareFunction;
    uint32_t stencilReadMask;
    uint32_t stencilWriteMask;
    
    bool operator==(const MetalDepthStencilStateKey& other) const
    {
        return depthTestEnabled == other.depthTestEnabled &&
               depthWriteEnabled == other.depthWriteEnabled &&
               depthCompareFunction == other.depthCompareFunction &&
               stencilReadMask == other.stencilReadMask &&
               stencilWriteMask == other.stencilWriteMask;
    }
};

struct MetalDepthStencilStateKeyHash
{
    size_t operator()(const MetalDepthStencilStateKey& key) const
    {
        size_t h = 0;
        h ^= std::hash<bool>{}(key.depthTestEnabled);
        h ^= std::hash<bool>{}(key.depthWriteEnabled) << 1;
        h ^= std::hash<int>{}(static_cast<int>(key.depthCompareFunction)) << 2;
        h ^= std::hash<uint32_t>{}(key.stencilReadMask) << 3;
        h ^= std::hash<uint32_t>{}(key.stencilWriteMask) << 4;
        return h;
    }
};

class CMetalStateCache
{
public:
    CMetalStateCache(id<MTLDevice> device);
    ~CMetalStateCache();
    
    id<MTLRenderPipelineState> GetOrCreatePipelineState(
        const MetalPipelineStateKey& key,
        id<MTLFunction> vertexFunction,
        id<MTLFunction> fragmentFunction,
        MTLVertexDescriptor* vertexDescriptor);
    
    id<MTLDepthStencilState> GetOrCreateDepthStencilState(
        const MetalDepthStencilStateKey& key);
    
    id<MTLSamplerState> GetOrCreateSamplerState(
        MTLSamplerAddressMode addressMode,
        MTLSamplerMinMagFilter minMagFilter,
        MTLSamplerMipFilter mipFilter,
        float maxAnisotropy);
    
    void ClearCache();
    
    size_t GetPipelineStateCacheSize() const { return m_pipelineStateCache.size(); }
    size_t GetDepthStencilStateCacheSize() const { return m_depthStencilStateCache.size(); }
    size_t GetSamplerStateCacheSize() const { return m_samplerStateCache.size(); }
    
private:
    id<MTLDevice> m_device;
    
    std::unordered_map<MetalPipelineStateKey, id<MTLRenderPipelineState>, MetalPipelineStateKeyHash> m_pipelineStateCache;
    std::unordered_map<MetalDepthStencilStateKey, id<MTLDepthStencilState>, MetalDepthStencilStateKeyHash> m_depthStencilStateCache;
    
    struct SamplerStateKey
    {
        MTLSamplerAddressMode addressMode;
        MTLSamplerMinMagFilter minMagFilter;
        MTLSamplerMipFilter mipFilter;
        float maxAnisotropy;
        
        bool operator==(const SamplerStateKey& other) const
        {
            return addressMode == other.addressMode &&
                   minMagFilter == other.minMagFilter &&
                   mipFilter == other.mipFilter &&
                   maxAnisotropy == other.maxAnisotropy;
        }
    };
    
    struct SamplerStateKeyHash
    {
        size_t operator()(const SamplerStateKey& key) const
        {
            size_t h = 0;
            h ^= std::hash<int>{}(static_cast<int>(key.addressMode));
            h ^= std::hash<int>{}(static_cast<int>(key.minMagFilter)) << 1;
            h ^= std::hash<int>{}(static_cast<int>(key.mipFilter)) << 2;
            h ^= std::hash<float>{}(key.maxAnisotropy) << 3;
            return h;
        }
    };
    
    std::unordered_map<SamplerStateKey, id<MTLSamplerState>, SamplerStateKeyHash> m_samplerStateCache;
};

#endif

#endif

