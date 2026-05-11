#ifndef METALPERSHADERUNIFORMS_H
#define METALPERSHADERUNIFORMS_H

#import <Metal/Metal.h>

#include <string>
#include <unordered_map>
#include <vector>

namespace MetalPerShaderUniforms {

struct FieldDescriptor
{
    std::string name;
    std::string type;
    NSUInteger  offset;
    NSUInteger  size;
};

struct ShaderLayout
{
    std::string              shaderName;
    std::string              uniformStructName;
    std::vector<FieldDescriptor> fields;
    NSUInteger               structSize = 0;
};

struct MaterialView
{
    const float* Ambient   = nullptr;
    const float* Diffuse   = nullptr;
    const float* Specular  = nullptr;
    const float* FogColor  = nullptr;
};

struct GlobalView
{
    const float* DiffuseSun = nullptr;
};

class Binder
{
public:
    Binder();
    ~Binder();

    bool Initialize(id<MTLDevice> device);
    void Shutdown();

    void RegisterShader(const char* shaderName,
                        const char* uniformStructName,
                        const std::vector<FieldDescriptor>& fields,
                        NSUInteger structSize);

    bool HasShader(const char* shaderName) const;
    size_t RegisteredShaderCount() const { return m_layouts.size(); }

    void SetMaterialView(const MaterialView& view) { m_material = view; }
    void SetGlobalView(const GlobalView& view) { m_global = view; }

    void BeginFrame();
    bool PackAndBind(id<MTLRenderCommandEncoder> encoder,
                     const char* shaderName,
                     NSUInteger slot);

    static std::vector<FieldDescriptor> BuildFieldsFromManifestUniforms(
        NSArray* manifestUniforms,
        NSUInteger* outStructSize);

private:
    bool                                 EnsureCapacity(NSUInteger neededBytes);
    void                                 PackField(const FieldDescriptor& field, uint8_t* dst);

    id<MTLDevice>                        m_device = nil;
    id<MTLBuffer>                        m_ringBuffer = nil;
    NSUInteger                           m_ringCapacity = 0;
    NSUInteger                           m_ringCursor = 0;

    MaterialView                         m_material;
    GlobalView                           m_global;

    std::unordered_map<std::string, ShaderLayout> m_layouts;

    mutable std::unordered_map<std::string, int> m_unknownFieldWarnings;
};

} // namespace MetalPerShaderUniforms

#endif // METALPERSHADERUNIFORMS_H
