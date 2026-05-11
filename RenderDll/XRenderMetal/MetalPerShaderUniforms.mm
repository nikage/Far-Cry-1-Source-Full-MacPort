#include "MetalRenderPCH.h"
#include "MetalPerShaderUniforms.h"

#include <cstring>
#include <cstdint>

namespace MetalPerShaderUniforms {

namespace {

constexpr NSUInteger kInitialRingCapacity = 64 * 1024;
constexpr NSUInteger kSlotAlignment       = 256;

NSUInteger AlignUp(NSUInteger value, NSUInteger alignment)
{
    return (value + (alignment - 1)) & ~(alignment - 1);
}

NSUInteger SizeForType(const std::string& type)
{
    if (type == "float4" || type == "FLOAT4" || type == "half4")
        return 16;
    if (type == "float3" || type == "FLOAT3" || type == "half3")
        return 12;
    if (type == "float2" || type == "FLOAT2" || type == "half2")
        return 8;
    if (type == "float" || type == "FLOAT" || type == "half")
        return 4;
    return 16;
}

NSUInteger AlignmentForType(const std::string& type)
{
    NSUInteger size = SizeForType(type);
    if (size >= 16) return 16;
    if (size >= 8)  return 8;
    if (size >= 4)  return 4;
    return 4;
}

} // namespace

std::vector<FieldDescriptor> Binder::BuildFieldsFromManifestUniforms(
    NSArray* manifestUniforms, NSUInteger* outStructSize)
{
    std::vector<FieldDescriptor> fields;
    NSUInteger offset = 0;
    if ([manifestUniforms isKindOfClass:[NSArray class]])
    {
        for (id obj in manifestUniforms)
        {
            if (![obj isKindOfClass:[NSDictionary class]])
                continue;
            NSDictionary* dict = (NSDictionary*)obj;
            NSString* nameNS = dict[@"name"];
            NSString* typeNS = dict[@"type"];
            if (!nameNS || !typeNS)
                continue;
            FieldDescriptor fd;
            fd.name = [nameNS UTF8String];
            fd.type = [typeNS UTF8String];
            fd.size = SizeForType(fd.type);
            NSUInteger alignment = AlignmentForType(fd.type);
            offset = AlignUp(offset, alignment);
            fd.offset = offset;
            offset += fd.size;
            fields.push_back(fd);
        }
    }
    if (outStructSize)
        *outStructSize = AlignUp(offset, 16);
    return fields;
}

Binder::Binder() = default;
Binder::~Binder() { Shutdown(); }

bool Binder::Initialize(id<MTLDevice> device)
{
    if (!device)
        return false;
    m_device = device;
    m_ringCapacity = kInitialRingCapacity;
    m_ringBuffer = [m_device newBufferWithLength:m_ringCapacity
                                         options:MTLResourceStorageModeShared];
    if (!m_ringBuffer)
        return false;
    [m_ringBuffer setLabel:@"PerShaderUniformsRing"];
    m_ringCursor = 0;
    return true;
}

void Binder::Shutdown()
{
    m_ringBuffer = nil;
    m_device = nil;
    m_ringCapacity = 0;
    m_ringCursor = 0;
    m_layouts.clear();
}

void Binder::RegisterShader(const char* shaderName,
                            const char* uniformStructName,
                            const std::vector<FieldDescriptor>& fields,
                            NSUInteger structSize)
{
    if (!shaderName || fields.empty() || structSize == 0)
        return;
    ShaderLayout layout;
    layout.shaderName = shaderName;
    layout.uniformStructName = uniformStructName ? uniformStructName : "";
    layout.fields = fields;
    layout.structSize = structSize;
    m_layouts[layout.shaderName] = std::move(layout);
}

bool Binder::HasShader(const char* shaderName) const
{
    if (!shaderName)
        return false;
    return m_layouts.find(shaderName) != m_layouts.end();
}

void Binder::BeginFrame()
{
    m_ringCursor = 0;
}

bool Binder::EnsureCapacity(NSUInteger neededBytes)
{
    if (m_ringCursor + neededBytes <= m_ringCapacity)
        return true;
    NSUInteger newCapacity = m_ringCapacity;
    while (m_ringCursor + neededBytes > newCapacity)
        newCapacity *= 2;
    id<MTLBuffer> newBuffer = [m_device newBufferWithLength:newCapacity
                                                    options:MTLResourceStorageModeShared];
    if (!newBuffer)
        return false;
    [newBuffer setLabel:@"PerShaderUniformsRing"];
    if (m_ringBuffer && m_ringCursor > 0)
    {
        memcpy([newBuffer contents], [m_ringBuffer contents], m_ringCursor);
    }
    m_ringBuffer = newBuffer;
    m_ringCapacity = newCapacity;
    return true;
}

void Binder::PackField(const FieldDescriptor& field, uint8_t* dst)
{
    uint8_t* slot = dst + field.offset;
    const float* src = nullptr;
    if (field.name == "Diffuse")
        src = m_material.Diffuse;
    else if (field.name == "Ambient")
        src = m_material.Ambient;
    else if (field.name == "Specular")
        src = m_material.Specular;
    else if (field.name == "FogColor" || field.name == "GlobalFogColor")
        src = m_material.FogColor;
    else if (field.name == "DiffuseSun")
        src = m_global.DiffuseSun;

    if (src)
    {
        NSUInteger bytes = field.size < 16 ? field.size : 16;
        memcpy(slot, src, bytes);
    }
    else
    {
        memset(slot, 0, field.size);
        auto it = m_unknownFieldWarnings.find(field.name);
        if (it == m_unknownFieldWarnings.end())
        {
            m_unknownFieldWarnings[field.name] = 1;
            if (iLog)
                iLog->Log("\003[PerShaderUniforms] no supplier for field '%s' — zeroed", field.name.c_str());
        }
    }
}

bool Binder::PackAndBind(id<MTLRenderCommandEncoder> encoder,
                         const char* shaderName,
                         NSUInteger slot)
{
    if (!encoder || !shaderName || !m_ringBuffer)
        return false;
    auto it = m_layouts.find(shaderName);
    if (it == m_layouts.end())
        return false;
    const ShaderLayout& layout = it->second;
    if (layout.structSize == 0)
        return false;

    NSUInteger alignedCursor = AlignUp(m_ringCursor, kSlotAlignment);
    NSUInteger needed = layout.structSize;
    if (alignedCursor + needed > m_ringCapacity)
    {
        m_ringCursor = alignedCursor;
        if (!EnsureCapacity(needed))
            return false;
        alignedCursor = m_ringCursor;
    }

    uint8_t* base = (uint8_t*)[m_ringBuffer contents] + alignedCursor;
    memset(base, 0, needed);
    for (const FieldDescriptor& field : layout.fields)
        PackField(field, base);

    if (m_diagCallsRemaining > 0 && iLog)
    {
        --m_diagCallsRemaining;
        iLog->Log("\003[PerShaderUniforms] PACK shader=%s structSize=%lu fields=%zu",
                  shaderName, (unsigned long)layout.structSize, layout.fields.size());
        for (const FieldDescriptor& field : layout.fields)
        {
            const float* src = nullptr;
            if (field.name == "Diffuse")        src = m_material.Diffuse;
            else if (field.name == "Ambient")   src = m_material.Ambient;
            else if (field.name == "Specular")  src = m_material.Specular;
            else if (field.name == "FogColor" ||
                     field.name == "GlobalFogColor") src = m_material.FogColor;
            else if (field.name == "DiffuseSun") src = m_global.DiffuseSun;
            if (src)
                iLog->Log("\003[PerShaderUniforms]   %s = (%g, %g, %g, %g)",
                          field.name.c_str(),
                          src[0], src[1],
                          field.size >= 12 ? src[2] : 0.0f,
                          field.size >= 16 ? src[3] : 0.0f);
            else
                iLog->Log("\003[PerShaderUniforms]   %s = (no supplier — zero)",
                          field.name.c_str());
        }
    }

    [encoder setFragmentBuffer:m_ringBuffer offset:alignedCursor atIndex:slot];
    m_ringCursor = alignedCursor + needed;
    return true;
}

} // namespace MetalPerShaderUniforms
