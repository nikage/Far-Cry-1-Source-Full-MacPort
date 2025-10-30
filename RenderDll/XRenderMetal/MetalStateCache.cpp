////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalStateCache.cpp
//  Version:     v1.00
//  Created:     30/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal render state caching implementation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalRenderPCH.h"
#include "MetalStateCache.h"
#include <cstdio>

CMetalStateCache::CMetalStateCache(id<MTLDevice> device)
    : m_device(device)
{
}

CMetalStateCache::~CMetalStateCache()
{
    ClearCache();
}

id<MTLRenderPipelineState> CMetalStateCache::GetOrCreatePipelineState(
    const MetalPipelineStateKey& key,
    id<MTLFunction> vertexFunction,
    id<MTLFunction> fragmentFunction,
    MTLVertexDescriptor* vertexDescriptor)
{
    auto it = m_pipelineStateCache.find(key);
    if (it != m_pipelineStateCache.end())
    {
        return it->second;
    }
    
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.vertexDescriptor = vertexDescriptor;
    
    descriptor.colorAttachments[0].pixelFormat = key.colorPixelFormat;
    descriptor.depthAttachmentPixelFormat = key.depthPixelFormat;
    
    uint32_t blendState = (key.renderStateHash >> 16) & 0xFFFF;
    if (blendState & 0x1)
    {
        descriptor.colorAttachments[0].blendingEnabled = YES;
        descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    }
    else
    {
        descriptor.colorAttachments[0].blendingEnabled = NO;
    }
    
    NSError* error = nil;
    id<MTLRenderPipelineState> pipelineState = [m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    
    if (!pipelineState)
    {
        iLog->Log("Error creating pipeline state: %s\n",
               error ? [[error localizedDescription] UTF8String] : "Unknown error");
        return nil;
    }
    
    m_pipelineStateCache[key] = pipelineState;
    return pipelineState;
}

id<MTLDepthStencilState> CMetalStateCache::GetOrCreateDepthStencilState(
    const MetalDepthStencilStateKey& key)
{
    auto it = m_depthStencilStateCache.find(key);
    if (it != m_depthStencilStateCache.end())
    {
        return it->second;
    }
    
    MTLDepthStencilDescriptor* descriptor = [[MTLDepthStencilDescriptor alloc] init];
    
    if (key.depthTestEnabled)
    {
        descriptor.depthCompareFunction = key.depthCompareFunction;
        descriptor.depthWriteEnabled = key.depthWriteEnabled;
    }
    else
    {
        descriptor.depthCompareFunction = MTLCompareFunctionAlways;
        descriptor.depthWriteEnabled = NO;
    }
    
    id<MTLDepthStencilState> depthStencilState = [m_device newDepthStencilStateWithDescriptor:descriptor];
    
    if (!depthStencilState)
    {
        iLog->Log("Error creating depth stencil state\n");
        return nil;
    }
    
    m_depthStencilStateCache[key] = depthStencilState;
    return depthStencilState;
}

id<MTLSamplerState> CMetalStateCache::GetOrCreateSamplerState(
    MTLSamplerAddressMode addressMode,
    MTLSamplerMinMagFilter minMagFilter,
    MTLSamplerMipFilter mipFilter,
    float maxAnisotropy)
{
    SamplerStateKey key{addressMode, minMagFilter, mipFilter, maxAnisotropy};
    
    auto it = m_samplerStateCache.find(key);
    if (it != m_samplerStateCache.end())
    {
        return it->second;
    }
    
    MTLSamplerDescriptor* descriptor = [[MTLSamplerDescriptor alloc] init];
    descriptor.sAddressMode = addressMode;
    descriptor.tAddressMode = addressMode;
    descriptor.rAddressMode = addressMode;
    descriptor.minFilter = minMagFilter;
    descriptor.magFilter = minMagFilter;
    descriptor.mipFilter = mipFilter;
    descriptor.maxAnisotropy = maxAnisotropy;
    
    id<MTLSamplerState> samplerState = [m_device newSamplerStateWithDescriptor:descriptor];
    
    if (!samplerState)
    {
        iLog->Log("Error creating sampler state\n");
        return nil;
    }
    
    m_samplerStateCache[key] = samplerState;
    return samplerState;
}

void CMetalStateCache::ClearCache()
{
    m_pipelineStateCache.clear();
    m_depthStencilStateCache.clear();
    m_samplerStateCache.clear();
}

#endif

