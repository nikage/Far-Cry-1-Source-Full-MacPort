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

struct MatrixView
{
    const float* ModelViewProj = nullptr;
    const float* ProjMatrix    = nullptr;
    const float* ViewMatrix    = nullptr;
    const float* ModelMatrix   = nullptr;
    const float* LightPos      = nullptr;
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

    void RegisterShaderVertex(const char* fragmentShaderName,
                              const char* uniformStructName,
                              const std::vector<FieldDescriptor>& fields,
                              NSUInteger structSize);

    bool HasShader(const char* shaderName) const;
    bool HasVertexShader(const char* fragmentShaderName) const;
    size_t RegisteredShaderCount() const { return m_layouts.size(); }
    size_t RegisteredVertexShaderCount() const { return m_vertexLayouts.size(); }

    void SetMaterialView(const MaterialView& view) { m_material = view; }
    void SetGlobalView(const GlobalView& view) { m_global = view; }
    void SetMatrixView(const MatrixView& view) { m_matrix = view; }

    void BeginFrame();
    bool PackAndBind(id<MTLRenderCommandEncoder> encoder,
                     const char* shaderName,
                     NSUInteger slot);
    bool PackAndBindVertex(id<MTLRenderCommandEncoder> encoder,
                           const char* fragmentShaderName,
                           NSUInteger slot);

    static std::vector<FieldDescriptor> BuildFieldsFromManifestUniforms(
        NSArray* manifestUniforms,
        NSUInteger* outStructSize);

    void EnableOneShotDiagnostic(int remainingCalls) { m_diagCallsRemaining = remainingCalls; }

private:
    bool                                 EnsureCapacity(NSUInteger neededBytes);
    void                                 PackField(const FieldDescriptor& field, uint8_t* dst);

    id<MTLDevice>                        m_device = nil;
    id<MTLBuffer>                        m_ringBuffer = nil;
    NSUInteger                           m_ringCapacity = 0;
    NSUInteger                           m_ringCursor = 0;

    MaterialView                         m_material;
    GlobalView                           m_global;
    MatrixView                           m_matrix;

    std::unordered_map<std::string, ShaderLayout> m_layouts;
    std::unordered_map<std::string, ShaderLayout> m_vertexLayouts;

    mutable std::unordered_map<std::string, int> m_unknownFieldWarnings;
    int                                  m_diagCallsRemaining = 0;
};

} // namespace MetalPerShaderUniforms

#endif // METALPERSHADERUNIFORMS_H
