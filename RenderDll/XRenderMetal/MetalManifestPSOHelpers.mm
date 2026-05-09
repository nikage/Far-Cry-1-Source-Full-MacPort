////////////////////////////////////////////////////////////////////////////
//
//  Manifest-driven Metal PSO helpers shared by MetalShaderLoader and offline validators.
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalManifestPSOHelpers.h"
#include "MetalVertexDescriptor.m"

#include <string>

namespace
{

static NSString* NormalizeBlendString(NSString* value)
{
    if (!value)
        return nil;
    NSString* lowered = [[value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    lowered = [lowered stringByReplacingOccurrencesOfString:@"_" withString:@""];
    lowered = [lowered stringByReplacingOccurrencesOfString:@"-" withString:@""];
    lowered = [lowered stringByReplacingOccurrencesOfString:@" " withString:@""];
    return lowered;
}

static const uint32_t kFC_FogEnabled     = 0;
static const uint32_t kFC_HdrEnabled     = 1;
static const uint32_t kFC_GlossAlpha     = 2;
static const uint32_t kFC_EnvLight       = 3;
static const uint32_t kFC_AttenEnabled   = 4;
static const uint32_t kFC_ProjLight      = 5;
static const uint32_t kFC_PlantsBending  = 6;
static const uint32_t kFC_AlphaGlow      = 7;
static const uint32_t kFC_MultipleLights = 8;
static const uint32_t kFC_HighPrecision  = 9;

static std::string NSStringToStdString(NSString* value)
{
    if (!value)
        return std::string();
    const char* utf8 = [value UTF8String];
    if (!utf8)
        return std::string();
    return std::string(utf8);
}

static MTLBlendFactor BlendFactorFromString(NSString* value)
{
    NSString* token = NormalizeBlendString(value);
    if (!token || [token length] == 0)
        return MTLBlendFactorOne;
    if ([token isEqualToString:@"zero"])
        return MTLBlendFactorZero;
    if ([token isEqualToString:@"one"])
        return MTLBlendFactorOne;
    if ([token isEqualToString:@"srccolor"] || [token isEqualToString:@"src"])
        return MTLBlendFactorSourceColor;
    if ([token isEqualToString:@"invsrccolor"] || [token isEqualToString:@"oneminussrccolor"])
        return MTLBlendFactorOneMinusSourceColor;
    if ([token isEqualToString:@"dstcolor"] || [token isEqualToString:@"dst"])
        return MTLBlendFactorDestinationColor;
    if ([token isEqualToString:@"invdstcolor"] || [token isEqualToString:@"oneminusdstcolor"])
        return MTLBlendFactorOneMinusDestinationColor;
    if ([token isEqualToString:@"srcalpha"])
        return MTLBlendFactorSourceAlpha;
    if ([token isEqualToString:@"invsrcalpha"] || [token isEqualToString:@"oneminussrcalpha"])
        return MTLBlendFactorOneMinusSourceAlpha;
    if ([token isEqualToString:@"dstalpha"])
        return MTLBlendFactorDestinationAlpha;
    if ([token isEqualToString:@"invdstalpha"] || [token isEqualToString:@"oneminusdstalpha"])
        return MTLBlendFactorOneMinusDestinationAlpha;
    if ([token isEqualToString:@"srcalphasat"] || [token isEqualToString:@"srcalphasaturate"])
        return MTLBlendFactorSourceAlphaSaturated;
    return MTLBlendFactorOne;
}

static MTLBlendOperation BlendOperationFromString(NSString* value)
{
    NSString* token = NormalizeBlendString(value);
    if (!token || [token length] == 0)
        return MTLBlendOperationAdd;
    if ([token isEqualToString:@"add"])
        return MTLBlendOperationAdd;
    if ([token isEqualToString:@"subtract"])
        return MTLBlendOperationSubtract;
    if ([token isEqualToString:@"revsubtract"] || [token isEqualToString:@"reversesubtract"])
        return MTLBlendOperationReverseSubtract;
    if ([token isEqualToString:@"min"])
        return MTLBlendOperationMin;
    if ([token isEqualToString:@"max"])
        return MTLBlendOperationMax;
    return MTLBlendOperationAdd;
}

} // namespace

PipelineStateConfig MetalManifestDefaultPipelineConfig()
{
    return PipelineStateConfig();
}

void MetalManifestApplyPipelineConfigFromManifest(PipelineStateConfig& config, NSDictionary* pipelineDict)
{
    if (!pipelineDict || ![pipelineDict isKindOfClass:[NSDictionary class]])
        return;

    NSNumber* blendEnabledValue = pipelineDict[@"blendEnabled"];
    if (blendEnabledValue)
        config.blendEnabled = blendEnabledValue.boolValue;

    NSString* blendModeValue = pipelineDict[@"blendMode"];
    if (blendModeValue)
    {
        NSString* lower = [blendModeValue lowercaseString];
        if ([lower isEqualToString:@"none"])
        {
            config.blendEnabled = false;
            config.blendMode = kBlendNone;
        }
        else if ([lower isEqualToString:@"add"] || [lower isEqualToString:@"additive"])
        {
            config.blendEnabled = true;
            config.blendMode = kBlendAdditive;
            config.sourceBlendFactor = MTLBlendFactorOne;
            config.destinationBlendFactor = MTLBlendFactorOne;
            config.blendOperation = MTLBlendOperationAdd;
        }
        else
        {
            config.blendEnabled = true;
            config.blendMode = kBlendAlpha;
            config.sourceBlendFactor = MTLBlendFactorSourceAlpha;
            config.destinationBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            config.blendOperation = MTLBlendOperationAdd;
        }
    }

    NSDictionary* blendFactorsDict = pipelineDict[@"blendFactors"];
    if (blendFactorsDict && [blendFactorsDict isKindOfClass:[NSDictionary class]])
    {
        NSString* srcValue = blendFactorsDict[@"src"];
        if (srcValue)
            config.sourceBlendFactor = BlendFactorFromString(srcValue);
        NSString* dstValue = blendFactorsDict[@"dst"];
        if (dstValue)
            config.destinationBlendFactor = BlendFactorFromString(dstValue);
        NSString* srcAlphaValue = blendFactorsDict[@"srcAlpha"];
        if (srcAlphaValue)
            config.sourceAlphaBlendFactor = BlendFactorFromString(srcAlphaValue);
        else
            config.sourceAlphaBlendFactor = config.sourceBlendFactor;
        NSString* dstAlphaValue = blendFactorsDict[@"dstAlpha"];
        if (dstAlphaValue)
            config.destinationAlphaBlendFactor = BlendFactorFromString(dstAlphaValue);
        else
            config.destinationAlphaBlendFactor = config.destinationBlendFactor;
        NSString* opValue = blendFactorsDict[@"op"];
        if (opValue)
            config.blendOperation = BlendOperationFromString(opValue);
        NSString* opAlphaValue = blendFactorsDict[@"opAlpha"];
        if (opAlphaValue)
            config.alphaBlendOperation = BlendOperationFromString(opAlphaValue);
        else
            config.alphaBlendOperation = config.blendOperation;
    }
    else
    {
        config.sourceAlphaBlendFactor = config.sourceBlendFactor;
        config.destinationAlphaBlendFactor = config.destinationBlendFactor;
        config.alphaBlendOperation = config.blendOperation;
    }

    NSNumber* depthTestValue = pipelineDict[@"depthTest"];
    if (depthTestValue)
        config.depthTestEnabled = depthTestValue.boolValue;

    NSNumber* depthWriteValue = pipelineDict[@"depthWrite"];
    if (depthWriteValue)
        config.depthWriteEnabled = depthWriteValue.boolValue;

    NSString* depthCompareValue = pipelineDict[@"depthCompare"];
    if (depthCompareValue)
    {
        NSString* lower = [depthCompareValue lowercaseString];
        if ([lower isEqualToString:@"less"])
            config.depthCompareFunction = MTLCompareFunctionLess;
        else if ([lower isEqualToString:@"always"])
            config.depthCompareFunction = MTLCompareFunctionAlways;
        else
            config.depthCompareFunction = MTLCompareFunctionLessEqual;
    }

    NSString* cullValue = pipelineDict[@"cullMode"];
    if (cullValue)
    {
        NSString* lower = [cullValue lowercaseString];
        if ([lower isEqualToString:@"none"])
            config.cullMode = MTLCullModeNone;
        else if ([lower isEqualToString:@"front"])
            config.cullMode = MTLCullModeFront;
        else
            config.cullMode = MTLCullModeBack;
    }

    if (!config.blendEnabled)
        config.blendMode = kBlendNone;

    NSDictionary* colorMaskDict = pipelineDict[@"colorMask"];
    if (colorMaskDict && [colorMaskDict isKindOfClass:[NSDictionary class]])
    {
        uint8_t mask = 0;
        NSNumber* rValue = colorMaskDict[@"r"];
        NSNumber* gValue = colorMaskDict[@"g"];
        NSNumber* bValue = colorMaskDict[@"b"];
        NSNumber* aValue = colorMaskDict[@"a"];
        if (!rValue || rValue.boolValue)
            mask |= 0x1;
        if (!gValue || gValue.boolValue)
            mask |= 0x2;
        if (!bValue || bValue.boolValue)
            mask |= 0x4;
        if (!aValue || aValue.boolValue)
            mask |= 0x8;
        config.colorWriteMask = mask ? mask : 0;
    }
}

void MetalManifestApplyPipelineConfigToDescriptor(MTLRenderPipelineDescriptor* descriptor,
                                                  const PipelineStateConfig& config,
                                                  MTLPixelFormat colorFormat,
                                                  MTLPixelFormat depthStencilFormat)
{
    if (!descriptor)
        return;

    descriptor.colorAttachments[0].pixelFormat = colorFormat;
    const bool blendEnabled = config.blendEnabled;
    descriptor.colorAttachments[0].blendingEnabled = blendEnabled ? YES : NO;
    if (blendEnabled)
    {
        descriptor.colorAttachments[0].sourceRGBBlendFactor = config.sourceBlendFactor;
        descriptor.colorAttachments[0].destinationRGBBlendFactor = config.destinationBlendFactor;
        descriptor.colorAttachments[0].rgbBlendOperation = config.blendOperation;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = config.sourceAlphaBlendFactor;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = config.destinationAlphaBlendFactor;
        descriptor.colorAttachments[0].alphaBlendOperation = config.alphaBlendOperation;
    }
    MTLColorWriteMask writeMask = 0;
    if (config.colorWriteMask & 0x1)
        writeMask |= MTLColorWriteMaskRed;
    if (config.colorWriteMask & 0x2)
        writeMask |= MTLColorWriteMaskGreen;
    if (config.colorWriteMask & 0x4)
        writeMask |= MTLColorWriteMaskBlue;
    if (config.colorWriteMask & 0x8)
        writeMask |= MTLColorWriteMaskAlpha;
    descriptor.colorAttachments[0].writeMask = writeMask;

    descriptor.depthAttachmentPixelFormat = depthStencilFormat;
    descriptor.stencilAttachmentPixelFormat = depthStencilFormat;
}

MTLFunctionConstantValues* MetalManifestBuildFunctionConstants(NSString* lowerName,
                                                               NSArray* directives)
{
    MTLFunctionConstantValues* cv = [[MTLFunctionConstantValues alloc] init];

    bool fog_enabled     = false;
    bool hdr_enabled     = false;
    bool gloss_alpha     = false;
    bool env_light       = false;
    bool atten_enabled   = false;
    bool proj_light      = false;
    bool plants_bending  = false;
    bool alpha_glow      = false;
    bool multiple_lights = false;
    bool high_precision  = false;

    if (lowerName)
    {
        env_light       = [lowerName containsString:@"envlight"];
        alpha_glow      = [lowerName containsString:@"alphaglow"];
        gloss_alpha     = [lowerName containsString:@"glossalpha"];
        multiple_lights = [lowerName containsString:@"multiplelight"];
        atten_enabled   = [lowerName containsString:@"atten"];
        proj_light      = [lowerName containsString:@"proj"];
        plants_bending  = [lowerName containsString:@"plants"] ||
                          [lowerName containsString:@"vegetation"];
    }

    if (directives && [directives isKindOfClass:[NSArray class]])
    {
        for (id dir in directives)
        {
            NSString* d = [NSString stringWithFormat:@"%@", dir].lowercaseString;
            if ([d isEqualToString:@"hdr"] || [d containsString:@"hdr"])
                hdr_enabled = true;
            if ([d containsString:@"fog"])
                fog_enabled = true;
            if ([d containsString:@"highprecision"] || [d containsString:@"high_precision"])
                high_precision = true;
        }
    }

    [cv setConstantValue:&fog_enabled      type:MTLDataTypeBool atIndex:kFC_FogEnabled];
    [cv setConstantValue:&hdr_enabled      type:MTLDataTypeBool atIndex:kFC_HdrEnabled];
    [cv setConstantValue:&gloss_alpha      type:MTLDataTypeBool atIndex:kFC_GlossAlpha];
    [cv setConstantValue:&env_light        type:MTLDataTypeBool atIndex:kFC_EnvLight];
    [cv setConstantValue:&atten_enabled    type:MTLDataTypeBool atIndex:kFC_AttenEnabled];
    [cv setConstantValue:&proj_light       type:MTLDataTypeBool atIndex:kFC_ProjLight];
    [cv setConstantValue:&plants_bending   type:MTLDataTypeBool atIndex:kFC_PlantsBending];
    [cv setConstantValue:&alpha_glow       type:MTLDataTypeBool atIndex:kFC_AlphaGlow];
    [cv setConstantValue:&multiple_lights  type:MTLDataTypeBool atIndex:kFC_MultipleLights];
    [cv setConstantValue:&high_precision   type:MTLDataTypeBool atIndex:kFC_HighPrecision];

    return [cv autorelease];
}

std::vector<GeneratedVertexAttributeDesc> MetalManifestBuildGeneratedVertexAttributes(NSArray* metadata)
{
    std::vector<GeneratedVertexAttributeDesc> attributes;
    if (!metadata || ![metadata isKindOfClass:[NSArray class]])
        return attributes;

    for (id entry in metadata)
    {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;
        NSDictionary* dict = (NSDictionary*)entry;
        GeneratedVertexAttributeDesc attribute;
        NSString* token = dict[@"token"];
        NSString* category = dict[@"category"];
        NSString* semantic = dict[@"semantic"];
        NSString* label = dict[@"label"];
        NSNumber* components = dict[@"components"];
        NSNumber* index = dict[@"index"];
        attribute.token = NSStringToStdString(token);
        attribute.category = NSStringToStdString(category);
        attribute.semantic = NSStringToStdString(semantic);
        attribute.label = NSStringToStdString(label);
        attribute.components = components ? components.intValue : 0;
        attribute.index = index ? index.intValue : -1;
        attributes.push_back(attribute);
    }
    return attributes;
}

std::vector<GeneratedVertexAttributeDesc> MetalManifestBuildGeneratedVertexInputs(NSArray* vertexInputs)
{
    std::vector<GeneratedVertexAttributeDesc> result;
    if (!vertexInputs || ![vertexInputs isKindOfClass:[NSArray class]])
        return result;
    for (id entry in vertexInputs)
    {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;
        NSDictionary* dict = (NSDictionary*)entry;
        GeneratedVertexAttributeDesc attr;
        NSString* name     = dict[@"name"];
        NSString* category = dict[@"category"];
        NSString* semantic = dict[@"semantic"];
        NSString* label    = dict[@"label"];
        NSNumber* components  = dict[@"components"];
        NSNumber* index       = dict[@"index"];
        NSNumber* slot        = dict[@"slot"];
        NSNumber* bufferIndex = dict[@"bufferIndex"];
        attr.token       = NSStringToStdString(name);
        attr.category    = NSStringToStdString(category);
        attr.semantic    = NSStringToStdString(semantic);
        attr.label       = NSStringToStdString(label);
        attr.components  = components  ? components.intValue  : 0;
        attr.index       = index       ? index.intValue       : -1;
        attr.slot        = slot        ? slot.intValue        : static_cast<int>(result.size());
        attr.bufferIndex = bufferIndex ? bufferIndex.intValue : 0;
        result.push_back(attr);
    }
    return result;
}

std::vector<GeneratedVertexOutputDesc> MetalManifestBuildGeneratedVertexOutputs(NSArray* outputsArray)
{
    std::vector<GeneratedVertexOutputDesc> outputs;
    if (!outputsArray || ![outputsArray isKindOfClass:[NSArray class]])
        return outputs;
    for (id entry in outputsArray)
    {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;
        NSDictionary* dict = (NSDictionary*)entry;
        NSString* nameValue = dict[@"name"];
        if (!nameValue || ![nameValue isKindOfClass:[NSString class]])
            continue;
        GeneratedVertexOutputDesc desc;
        desc.name = NSStringToStdString(nameValue);
        NSNumber* componentsValue = dict[@"components"];
        if (componentsValue && [componentsValue isKindOfClass:[NSNumber class]])
            desc.components = componentsValue.intValue;
        outputs.push_back(desc);
    }
    return outputs;
}

MTLVertexDescriptor* MetalManifestCreateVertexDescriptorFromManifestVertexEntry(NSDictionary* vertexManifestEntry)
{
    if (!vertexManifestEntry)
        return nil;

    NSArray* vertexInputsArray = vertexManifestEntry[@"vertexInputs"];
    NSArray* vertexAttrMetaArray = vertexManifestEntry[@"vertexAttributeMetadata"];

    if (vertexInputsArray && [vertexInputsArray isKindOfClass:[NSArray class]] && [vertexInputsArray count] > 0)
    {
        std::vector<GeneratedVertexAttributeDesc> inputs =
            MetalManifestBuildGeneratedVertexInputs(vertexInputsArray);
        return CMetalVertexDescriptorHelper::CreateVertexDescriptorFromVertexInputs(inputs);
    }

    if (vertexAttrMetaArray && [vertexAttrMetaArray isKindOfClass:[NSArray class]] && [vertexAttrMetaArray count] > 0)
    {
        std::vector<GeneratedVertexAttributeDesc> attrs =
            MetalManifestBuildGeneratedVertexAttributes(vertexAttrMetaArray);
        bool metadataNeedsTangents = false;
        int vertexFormat = 0;
        return CMetalVertexDescriptorHelper::CreateVertexDescriptorFromMetadata(
            attrs, &metadataNeedsTangents, &vertexFormat);
    }

    return nil;
}

#endif
