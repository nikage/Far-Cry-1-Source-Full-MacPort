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
    descriptor.stencilAttachmentPixelFormat = key.depthPixelFormat;
    
    bool blendEnabled = (key.renderStateHash & 0x1ULL) != 0;
    MTLBlendFactor srcColor = static_cast<MTLBlendFactor>((key.renderStateHash >> 1) & 0x3FULL);
    MTLBlendFactor dstColor = static_cast<MTLBlendFactor>((key.renderStateHash >> 7) & 0x3FULL);
    MTLBlendFactor srcAlpha = static_cast<MTLBlendFactor>((key.renderStateHash >> 13) & 0x3FULL);
    MTLBlendFactor dstAlpha = static_cast<MTLBlendFactor>((key.renderStateHash >> 19) & 0x3FULL);
    MTLBlendOperation colorOp = static_cast<MTLBlendOperation>((key.renderStateHash >> 25) & 0x7ULL);
    MTLBlendOperation alphaOp = static_cast<MTLBlendOperation>((key.renderStateHash >> 28) & 0x7ULL);
    uint8_t colorMaskBits = static_cast<uint8_t>((key.renderStateHash >> 31) & 0xF);

    descriptor.colorAttachments[0].blendingEnabled = blendEnabled ? YES : NO;
    if (blendEnabled)
    {
        descriptor.colorAttachments[0].sourceRGBBlendFactor = srcColor;
        descriptor.colorAttachments[0].destinationRGBBlendFactor = dstColor;
        descriptor.colorAttachments[0].rgbBlendOperation = colorOp;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = srcAlpha;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = dstAlpha;
        descriptor.colorAttachments[0].alphaBlendOperation = alphaOp;
    }

    MTLColorWriteMask writeMask = 0;
    if (colorMaskBits & 0x1)
        writeMask |= MTLColorWriteMaskRed;
    if (colorMaskBits & 0x2)
        writeMask |= MTLColorWriteMaskGreen;
    if (colorMaskBits & 0x4)
        writeMask |= MTLColorWriteMaskBlue;
    if (colorMaskBits & 0x8)
        writeMask |= MTLColorWriteMaskAlpha;
    descriptor.colorAttachments[0].writeMask = writeMask;
    
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

MTLBlendFactor CMetalStateCache::ConvertSourceBlendFactor(int state)
{
    switch (state & GS_BLSRC_MASK)
    {
        case GS_BLSRC_ZERO: return MTLBlendFactorZero;
        case GS_BLSRC_ONE: return MTLBlendFactorOne;
        case GS_BLSRC_DSTCOL: return MTLBlendFactorDestinationColor;
        case GS_BLSRC_ONEMINUSDSTCOL: return MTLBlendFactorOneMinusDestinationColor;
        case GS_BLSRC_SRCALPHA: return MTLBlendFactorSourceAlpha;
        case GS_BLSRC_ONEMINUSSRCALPHA: return MTLBlendFactorOneMinusSourceAlpha;
        case GS_BLSRC_DSTALPHA: return MTLBlendFactorDestinationAlpha;
        case GS_BLSRC_ONEMINUSDSTALPHA: return MTLBlendFactorOneMinusDestinationAlpha;
        case GS_BLSRC_ALPHASATURATE: return MTLBlendFactorSourceAlphaSaturated;
        default: return MTLBlendFactorOne;
    }
}

MTLBlendFactor CMetalStateCache::ConvertDestinationBlendFactor(int state)
{
    switch (state & GS_BLDST_MASK)
    {
        case GS_BLDST_ZERO: return MTLBlendFactorZero;
        case GS_BLDST_ONE: return MTLBlendFactorOne;
        case GS_BLDST_SRCCOL: return MTLBlendFactorSourceColor;
        case GS_BLDST_ONEMINUSSRCCOL: return MTLBlendFactorOneMinusSourceColor;
        case GS_BLDST_SRCALPHA: return MTLBlendFactorSourceAlpha;
        case GS_BLDST_ONEMINUSSRCALPHA: return MTLBlendFactorOneMinusSourceAlpha;
        case GS_BLDST_DSTALPHA: return MTLBlendFactorDestinationAlpha;
        case GS_BLDST_ONEMINUSDSTALPHA: return MTLBlendFactorOneMinusDestinationAlpha;
        default: return MTLBlendFactorZero;
    }
}

MTLColorWriteMask CMetalStateCache::ConvertColorMask(int state)
{
    if (state & GS_NOCOLMASK)
        return static_cast<MTLColorWriteMask>(0);
    if (state & GS_COLMASKONLYALPHA)
        return MTLColorWriteMaskAlpha;
    if (state & GS_COLMASKONLYRGB)
        return static_cast<MTLColorWriteMask>(MTLColorWriteMaskRed | MTLColorWriteMaskGreen | MTLColorWriteMaskBlue);
    return MTLColorWriteMaskAll;
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
    depthTest = (state & GS_NODEPTHTEST) == 0;
    depthWrite = (state & GS_DEPTHWRITE) != 0;
    depthFunc = ConvertCompareFunction(state);
    
    int srcFactor = state & GS_BLSRC_MASK;
    int dstFactor = state & GS_BLDST_MASK;
    blendEnabled = (srcFactor != 0) || (dstFactor != 0);
    
    if (blendEnabled)
    {
        srcBlend = ConvertSourceBlendFactor(state);
        dstBlend = ConvertDestinationBlendFactor(state);
    }
    else
    {
        srcBlend = MTLBlendFactorOne;
        dstBlend = MTLBlendFactorZero;
    }
}

#endif

