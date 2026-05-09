////////////////////////////////////////////////////////////////////////////
//
//  Manifest-driven Metal PSO helpers shared by MetalShaderLoader and offline validators.
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_MANIFEST_PSO_HELPERS_H
#define METAL_MANIFEST_PSO_HELPERS_H

#if defined(__APPLE__) && defined(__MACH__)

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "MetalGeneratedVertex.h"

#include <cstdint>
#include <vector>

enum PipelineBlendMode : uint32_t
{
    kBlendNone = 0,
    kBlendAlpha = 1,
    kBlendAdditive = 2
};

struct PipelineStateConfig
{
    bool blendEnabled = true;
    PipelineBlendMode blendMode = kBlendAlpha;
    MTLBlendFactor sourceBlendFactor = MTLBlendFactorSourceAlpha;
    MTLBlendFactor destinationBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    MTLBlendOperation blendOperation = MTLBlendOperationAdd;
    MTLBlendFactor sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    MTLBlendFactor destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    MTLBlendOperation alphaBlendOperation = MTLBlendOperationAdd;
    bool depthTestEnabled = true;
    bool depthWriteEnabled = false;
    MTLCompareFunction depthCompareFunction = MTLCompareFunctionLessEqual;
    MTLCullMode cullMode = MTLCullModeBack;
    uint8_t colorWriteMask = 0xF;
};

PipelineStateConfig MetalManifestDefaultPipelineConfig();

void MetalManifestApplyPipelineConfigFromManifest(PipelineStateConfig& config, NSDictionary* pipelineDict);

void MetalManifestApplyPipelineConfigToDescriptor(MTLRenderPipelineDescriptor* descriptor,
                                                  const PipelineStateConfig& config,
                                                  MTLPixelFormat colorFormat,
                                                  MTLPixelFormat depthStencilFormat);

MTLFunctionConstantValues* MetalManifestBuildFunctionConstants(NSString* lowerShaderName,
                                                               NSArray* directives);

std::vector<GeneratedVertexAttributeDesc> MetalManifestBuildGeneratedVertexAttributes(NSArray* metadata);
std::vector<GeneratedVertexAttributeDesc> MetalManifestBuildGeneratedVertexInputs(NSArray* vertexInputs);
std::vector<GeneratedVertexOutputDesc> MetalManifestBuildGeneratedVertexOutputs(NSArray* outputsArray);

MTLVertexDescriptor* MetalManifestCreateVertexDescriptorFromManifestVertexEntry(NSDictionary* vertexManifestEntry);

#endif

#endif
