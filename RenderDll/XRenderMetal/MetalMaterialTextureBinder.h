#ifndef METALMATERIALTEXTUREBINDER_H
#define METALMATERIALTEXTUREBINDER_H

#import <Metal/Metal.h>

#include <string>
#include <unordered_map>
#include <vector>

struct SRenderShaderResources;
class CMetalTextureManager;

namespace MetalMaterialTextureBinder {

struct FragmentTextureSlot
{
    std::string name;
    int         slot       = -1;
    int         efttIndex  = -1;
};

struct ShaderTextureLayout
{
    std::string shaderName;
    std::vector<FragmentTextureSlot> slots;
};

class Binder
{
public:
    Binder();
    ~Binder();

    void RegisterShader(const char* shaderName, NSArray* manifestTextures);
    bool HasShader(const char* shaderName) const;
    size_t RegisteredShaderCount() const { return m_layouts.size(); }

    bool BindForShader(id<MTLRenderCommandEncoder> encoder,
                       const char* shaderName,
                       SRenderShaderResources* pRes,
                       CMetalTextureManager* textureManager);

    void EnableOneShotDiagnostic(int remainingCalls) { m_diagCallsRemaining = remainingCalls; }

    static int LookupEfttIndexForName(const char* name);

private:
    std::unordered_map<std::string, ShaderTextureLayout> m_layouts;
    mutable std::unordered_map<std::string, int>         m_unknownNameWarnings;
    int                                                  m_diagCallsRemaining = 0;
};

} // namespace MetalMaterialTextureBinder

#endif // METALMATERIALTEXTUREBINDER_H
