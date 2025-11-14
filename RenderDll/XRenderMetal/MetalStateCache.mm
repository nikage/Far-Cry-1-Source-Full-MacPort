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
#include "MetalStateCache.m"
#include <cstdio>
#include <cstdint>

namespace {
enum PipelineBlendMode : uint32_t
{
    kBlendNone = 0,
    kBlendAlpha = 1,
    kBlendAdditive = 2
};
}

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
    // Validate inputs before proceeding - these should never be nil in production
    assert(vertexFunction != nil && "GetOrCreatePipelineState: vertex function cannot be nil");
    assert(fragmentFunction != nil && "GetOrCreatePipelineState: fragment function cannot be nil");
    assert(vertexDescriptor != nil && "GetOrCreatePipelineState: vertex descriptor cannot be nil");
    
    if (!vertexFunction || !fragmentFunction || !vertexDescriptor)
    {
        iLog->Log("Error: Cannot create pipeline state with nil functions (vertex=%p, fragment=%p, descriptor=%p)\n",
               vertexFunction, fragmentFunction, vertexDescriptor);
        return nil;
    }
    
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
    
    uint32_t blendMode = (key.renderStateHash >> 16) & 0xFF;
    switch (blendMode)
    {
        case kBlendAdditive:
            descriptor.colorAttachments[0].blendingEnabled = YES;
            descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
            break;
        case kBlendNone:
            descriptor.colorAttachments[0].blendingEnabled = NO;
            break;
        case kBlendAlpha:
        default:
            descriptor.colorAttachments[0].blendingEnabled = YES;
            descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
            descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
            break;
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

MTLBlendFactor CMetalStateCache::ConvertBlendFactor(int gsBlendFactor)
{
    switch (gsBlendFactor)
    {
        case 0x1:  return MTLBlendFactorZero;
        case 0x2:  return MTLBlendFactorOne;
        case 0x3:  return MTLBlendFactorDestinationColor;
        case 0x4:  return MTLBlendFactorOneMinusDestinationColor;
        case 0x5:  return MTLBlendFactorSourceAlpha;
        case 0x6:  return MTLBlendFactorOneMinusSourceAlpha;
        case 0x7:  return MTLBlendFactorDestinationAlpha;
        case 0x8:  return MTLBlendFactorOneMinusDestinationAlpha;
        case 0x9:  return MTLBlendFactorSourceAlphaSaturated;
        default:   return MTLBlendFactorOne;
    }
}

MTLCompareFunction CMetalStateCache::ConvertCompareFunction(int state)
{
    if (state & 0x00020000)
        return MTLCompareFunctionAlways;
    
    if (state & 0x00100000)
        return MTLCompareFunctionEqual;
    
    if (state & 0x00200000)
        return MTLCompareFunctionGreater;
    
    return MTLCompareFunctionLessEqual;
}

MTLCullMode CMetalStateCache::ConvertCullMode(int cullMode)
{
    switch (cullMode)
    {
        case 0:  return MTLCullModeNone;
        case 1:  return MTLCullModeFront;
        case 2:  return MTLCullModeBack;
        default: return MTLCullModeBack;
    }
}

void CMetalStateCache::ParseRenderState(int state, bool& depthTest, bool& depthWrite,
                                        MTLBlendFactor& srcBlend, MTLBlendFactor& dstBlend,
                                        bool& blendEnabled, MTLCompareFunction& depthFunc)
{
    depthTest = !(state & 0x00020000);
    depthWrite = (state & 0x00000100) != 0;
    depthFunc = ConvertCompareFunction(state);
    
    int srcFactor = state & 0xF;
    int dstFactor = (state & 0xF0) >> 4;
    
    blendEnabled = (srcFactor != 0 || dstFactor != 0);
    
    if (blendEnabled)
    {
        srcBlend = ConvertBlendFactor(srcFactor);
        dstBlend = ConvertBlendFactor(dstFactor);
    }
    else
    {
        srcBlend = MTLBlendFactorOne;
        dstBlend = MTLBlendFactorZero;
    }
}

#endif

