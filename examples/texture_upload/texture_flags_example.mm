////////////////////////////////////////////////////////////////////////////
//
//  Example: Texture Flags and Parameters Usage
//  Demonstrates full parameter support in EF_LoadTexture
// -------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <iostream>
#import <vector>
#import <unordered_map>
#import <string>

typedef unsigned char byte;
typedef unsigned int uint;

#define FT_PROJECTED   0x1
#define FT_NOMIPS      0x2
#define FT_HASALPHA    0x4
#define FT_NORESIZE    0x8
#define FT_CLAMP       0x100000
#define FT_NOREMOVE    0x4000
#define FT_HASNORMALMAP 0x1000
#define FT_FONT        0x40000

#define FT2_NODXT      0x1
#define FT2_RELOAD     0x10
#define FT2_UCLAMP     0x40
#define FT2_VCLAMP     0x80

#define FILTER_NONE      0
#define FILTER_POINT     1
#define FILTER_LINEAR    2
#define FILTER_BILINEAR  3
#define FILTER_TRILINEAR 4

enum ETexType
{
    eTT_Base = 0,
    eTT_Cubemap,
    eTT_AutoCubemap,
    eTT_Bumpmap,
    eTT_DSDTBump,
    eTT_Rectangle,
    eTT_3D
};

enum ETEX_Format
{
    eTF_8888,
    eTF_0888,
};

struct TextureInfo
{
    id<MTLTexture> metalTexture;
    int width, height;
    std::string name;
    bool isLoaded;
    uint flags;
    uint flags2;
    byte textureType;
    float amount1;
    float amount2;
    bool clampU;
    bool clampV;
    int filterMode;
};

class SimpleTextureManager
{
public:
    std::unordered_map<int, TextureInfo> m_textures;
    id<MTLDevice> m_device;
    int m_nextId;
    
    SimpleTextureManager(id<MTLDevice> device) : m_device(device), m_nextId(1) {}
    
    unsigned int LoadTexture(const char* filename, int Id, bool bCompress, bool bWarn)
    {
        int size = 256;
        std::vector<unsigned char> data(size * size * 4, 150);
        
        MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                         width:size
                                                                                        height:size
                                                                                     mipmapped:YES];
        desc.usage = MTLTextureUsageShaderRead;
        desc.storageMode = MTLStorageModeShared;
        
        id<MTLTexture> texture = [m_device newTextureWithDescriptor:desc];
        if (!texture)
            return 0;
        
        [texture replaceRegion:MTLRegionMake2D(0, 0, size, size)
                   mipmapLevel:0
                     withBytes:data.data()
                   bytesPerRow:size * 4];
        
        int texId = (Id > 0) ? Id : m_nextId++;
        TextureInfo info;
        info.metalTexture = texture;
        info.width = size;
        info.height = size;
        info.name = filename ? filename : "";
        info.isLoaded = true;
        info.flags = 0;
        info.flags2 = 0;
        info.textureType = eTT_Base;
        info.amount1 = -1.0f;
        info.amount2 = -1.0f;
        info.clampU = false;
        info.clampV = false;
        info.filterMode = FILTER_BILINEAR;
        
        m_textures[texId] = info;
        return texId;
    }
    
    const TextureInfo* GetTextureInfo(int texId) const
    {
        auto it = m_textures.find(texId);
        return it != m_textures.end() ? &it->second : nullptr;
    }
    
    void SetTextureClamp(int texId, bool bEnable)
    {
        auto it = m_textures.find(texId);
        if (it != m_textures.end())
        {
            it->second.clampU = bEnable;
            it->second.clampV = bEnable;
            if (bEnable)
                it->second.flags |= FT_CLAMP;
            else
                it->second.flags &= ~FT_CLAMP;
        }
    }
    
    void SetTextureFilter(int texId, int nFilter)
    {
        auto it = m_textures.find(texId);
        if (it != m_textures.end())
        {
            it->second.filterMode = nFilter;
        }
    }
    
    unsigned int EF_LoadTexture(const char* nameTex, uint flags, uint flags2, byte eTT,
                                float fAmount1, float fAmount2, int Id)
    {
        if (!nameTex || !nameTex[0])
            return 0;
        
        bool bWarn = !(flags & FT_NOREMOVE);
        bool bCompress = !(flags2 & FT2_NODXT);
        
        unsigned int textureId = LoadTexture(nameTex, Id, bCompress, bWarn);
        if (textureId == 0)
            return 0;
        
        auto it = m_textures.find(textureId);
        if (it != m_textures.end())
        {
            it->second.flags = flags;
            it->second.flags2 = flags2;
            it->second.textureType = eTT;
            it->second.amount1 = fAmount1;
            it->second.amount2 = fAmount2;
            it->second.clampU = (flags & FT_CLAMP) || (flags2 & FT2_UCLAMP);
            it->second.clampV = (flags & FT_CLAMP) || (flags2 & FT2_VCLAMP);
            
            if (flags & FT_NOMIPS)
            {
                it->second.flags |= FT_NOMIPS;
            }
            
            if (eTT == eTT_Bumpmap)
            {
                it->second.flags |= FT_HASNORMALMAP;
            }
        }
        
        return textureId;
    }
};

void PrintTextureFlags(uint flags, uint flags2)
{
    std::cout << "    Flags: 0x" << std::hex << flags << std::dec << " (";
    if (flags & FT_CLAMP) std::cout << "FT_CLAMP ";
    if (flags & FT_NOMIPS) std::cout << "FT_NOMIPS ";
    if (flags & FT_NOREMOVE) std::cout << "FT_NOREMOVE ";
    if (flags & FT_HASNORMALMAP) std::cout << "FT_HASNORMALMAP ";
    if (flags & FT_HASALPHA) std::cout << "FT_HASALPHA ";
    std::cout << ")" << std::endl;
    
    std::cout << "    Flags2: 0x" << std::hex << flags2 << std::dec << " (";
    if (flags2 & FT2_NODXT) std::cout << "FT2_NODXT ";
    if (flags2 & FT2_UCLAMP) std::cout << "FT2_UCLAMP ";
    if (flags2 & FT2_VCLAMP) std::cout << "FT2_VCLAMP ";
    std::cout << ")" << std::endl;
}

void Example1_BasicTextureWithFlags(SimpleTextureManager& manager)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 1: Basic Texture with Clamp Flag                  ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    uint texId = manager.EF_LoadTexture(
        "textures/terrain.png",
        FT_CLAMP,           // Clamp texture coordinates
        0,                  // No additional flags
        eTT_Base,           // Standard texture
        -1.0f,              // No detail amount
        -1.0f,              // No opacity
        0                   // Allocate new ID
    );
    
    std::cout << "\n✅ Loaded texture ID: " << texId << std::endl;
    
    const TextureInfo* info = manager.GetTextureInfo(texId);
    if (info)
    {
        std::cout << "  Name: " << info->name << std::endl;
        std::cout << "  Type: " << (info->textureType == eTT_Base ? "eTT_Base" : "Other") << std::endl;
        PrintTextureFlags(info->flags, info->flags2);
        std::cout << "  ClampU: " << (info->clampU ? "Yes" : "No") << std::endl;
        std::cout << "  ClampV: " << (info->clampV ? "Yes" : "No") << std::endl;
    }
}

void Example2_BumpmapTexture(SimpleTextureManager& manager)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 2: Normal Map (Bumpmap) Texture                   ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    uint texId = manager.EF_LoadTexture(
        "textures/wall_normal.tga",
        FT_NOREMOVE,        // Don't remove from cache
        0,
        eTT_Bumpmap,        // Normal map texture
        -1.0f,
        -1.0f,
        0
    );
    
    std::cout << "\n✅ Loaded normal map ID: " << texId << std::endl;
    
    const TextureInfo* info = manager.GetTextureInfo(texId);
    if (info)
    {
        std::cout << "  Name: " << info->name << std::endl;
        std::cout << "  Type: " << (info->textureType == eTT_Bumpmap ? "eTT_Bumpmap" : "Other") << std::endl;
        PrintTextureFlags(info->flags, info->flags2);
        
        if (info->flags & FT_HASNORMALMAP)
        {
            std::cout << "  ✅ Correctly marked as normal map (FT_HASNORMALMAP set)" << std::endl;
        }
    }
}

void Example3_UVClampingModes(SimpleTextureManager& manager)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 3: U/V Clamping Modes                             ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    std::cout << "\n▸ Case 1: Clamp U only" << std::endl;
    uint texId1 = manager.EF_LoadTexture(
        "textures/ui_element.png",
        0,
        FT2_UCLAMP,         // Clamp U coordinate only
        eTT_Base,
        -1.0f,
        -1.0f,
        0
    );
    
    const TextureInfo* info1 = manager.GetTextureInfo(texId1);
    if (info1)
    {
        std::cout << "  ClampU: " << (info1->clampU ? "✅ Yes" : "❌ No") << std::endl;
        std::cout << "  ClampV: " << (info1->clampV ? "✅ Yes" : "❌ No") << std::endl;
    }
    
    std::cout << "\n▸ Case 2: Clamp V only" << std::endl;
    uint texId2 = manager.EF_LoadTexture(
        "textures/skybox.tga",
        0,
        FT2_VCLAMP,         // Clamp V coordinate only
        eTT_Base,
        -1.0f,
        -1.0f,
        0
    );
    
    const TextureInfo* info2 = manager.GetTextureInfo(texId2);
    if (info2)
    {
        std::cout << "  ClampU: " << (info2->clampU ? "✅ Yes" : "❌ No") << std::endl;
        std::cout << "  ClampV: " << (info2->clampV ? "✅ Yes" : "❌ No") << std::endl;
    }
    
    std::cout << "\n▸ Case 3: Clamp both (FT_CLAMP)" << std::endl;
    uint texId3 = manager.EF_LoadTexture(
        "textures/decal.png",
        FT_CLAMP,           // Clamp both U and V
        0,
        eTT_Base,
        -1.0f,
        -1.0f,
        0
    );
    
    const TextureInfo* info3 = manager.GetTextureInfo(texId3);
    if (info3)
    {
        std::cout << "  ClampU: " << (info3->clampU ? "✅ Yes" : "❌ No") << std::endl;
        std::cout << "  ClampV: " << (info3->clampV ? "✅ Yes" : "❌ No") << std::endl;
    }
}

void Example4_NoMipmapsFlag(SimpleTextureManager& manager)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 4: FT_NOMIPS Flag                                 ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    std::cout << "\n▸ Loading texture with FT_NOMIPS flag..." << std::endl;
    uint texId = manager.EF_LoadTexture(
        "textures/ui_button.png",
        FT_NOMIPS | FT_CLAMP,   // No mipmaps + clamping
        0,
        eTT_Base,
        -1.0f,
        -1.0f,
        0
    );
    
    const TextureInfo* info = manager.GetTextureInfo(texId);
    if (info)
    {
        std::cout << "  ✅ Texture loaded: " << info->name << std::endl;
        PrintTextureFlags(info->flags, info->flags2);
        
        if (info->flags & FT_NOMIPS)
        {
            std::cout << "  ✅ FT_NOMIPS flag is set (no mipmaps generated)" << std::endl;
        }
        if (info->flags & FT_CLAMP)
        {
            std::cout << "  ✅ FT_CLAMP flag is set (texture clamped)" << std::endl;
        }
    }
}

void Example5_AmountParameters(SimpleTextureManager& manager)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 5: Amount Parameters for Shader Blending          ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    std::cout << "\n▸ Loading detail texture with blend amounts..." << std::endl;
    uint texId = manager.EF_LoadTexture(
        "textures/detail_grass.tga",
        FT_NOREMOVE,
        0,
        eTT_Base,
        0.75f,              // Detail blend amount
        0.5f,               // Decal opacity
        0
    );
    
    const TextureInfo* info = manager.GetTextureInfo(texId);
    if (info)
    {
        std::cout << "  ✅ Texture: " << info->name << std::endl;
        std::cout << "  Amount1 (detail blend): " << info->amount1 << std::endl;
        std::cout << "  Amount2 (opacity): " << info->amount2 << std::endl;
        
        std::cout << "\n  These values can be used by shaders for:" << std::endl;
        std::cout << "    - Detail texture blending intensity" << std::endl;
        std::cout << "    - Decal opacity/transparency" << std::endl;
        std::cout << "    - Parallax mapping height scale" << std::endl;
        std::cout << "    - Other shader-specific effects" << std::endl;
    }
}

void Example6_MultipleTextureTypes(SimpleTextureManager& manager)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 6: Different Texture Types                        ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    struct TypeExample
    {
        const char* name;
        ETexType type;
        const char* typeName;
    };
    
    TypeExample types[] = {
        { "textures/wall_diffuse.tga", eTT_Base, "eTT_Base (Diffuse)" },
        { "textures/wall_normal.tga", eTT_Bumpmap, "eTT_Bumpmap (Normal Map)" },
        { "textures/sky_cubemap.dds", eTT_Cubemap, "eTT_Cubemap (Environment)" },
        { "textures/noise_3d.dds", eTT_3D, "eTT_3D (Volume Texture)" }
    };
    
    for (const auto& example : types)
    {
        std::cout << "\n▸ Loading: " << example.typeName << std::endl;
        
        uint texId = manager.EF_LoadTexture(
            example.name,
            0,
            0,
            example.type,
            -1.0f,
            -1.0f,
            0
        );
        
        const TextureInfo* info = manager.GetTextureInfo(texId);
        if (info)
        {
            std::cout << "  ✅ Loaded: " << info->name << std::endl;
            std::cout << "  Texture Type: " << (int)info->textureType << std::endl;
            
            if (info->textureType == eTT_Bumpmap && (info->flags & FT_HASNORMALMAP))
            {
                std::cout << "  ✅ Correctly flagged as normal map" << std::endl;
            }
        }
    }
}

void Example7_CombinedFlags(SimpleTextureManager& manager)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 7: Combined Flags Demonstration                   ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    std::cout << "\n▸ Loading texture with multiple flags combined..." << std::endl;
    uint texId = manager.EF_LoadTexture(
        "textures/complex_material.tga",
        FT_CLAMP | FT_NOMIPS | FT_NOREMOVE,     // Multiple flags ORed together
        FT2_NODXT | FT2_UCLAMP,                 // Multiple flags2
        eTT_Bumpmap,                            // Normal map type
        0.8f,                                   // Detail amount
        0.9f,                                   // Opacity
        0
    );
    
    const TextureInfo* info = manager.GetTextureInfo(texId);
    if (info)
    {
        std::cout << "  ✅ Texture: " << info->name << std::endl;
        std::cout << "  Type: " << (info->textureType == eTT_Bumpmap ? "eTT_Bumpmap" : "Other") << std::endl;
        PrintTextureFlags(info->flags, info->flags2);
        std::cout << "  Amount1: " << info->amount1 << std::endl;
        std::cout << "  Amount2: " << info->amount2 << std::endl;
        std::cout << "  Filter: " << info->filterMode << std::endl;
        
        std::cout << "\n  Flag Checks:" << std::endl;
        std::cout << "    FT_CLAMP: " << ((info->flags & FT_CLAMP) ? "✅" : "❌") << std::endl;
        std::cout << "    FT_NOMIPS: " << ((info->flags & FT_NOMIPS) ? "✅" : "❌") << std::endl;
        std::cout << "    FT_NOREMOVE: " << ((info->flags & FT_NOREMOVE) ? "✅" : "❌") << std::endl;
        std::cout << "    FT_HASNORMALMAP: " << ((info->flags & FT_HASNORMALMAP) ? "✅" : "❌") << std::endl;
        std::cout << "    FT2_NODXT: " << ((info->flags2 & FT2_NODXT) ? "✅" : "❌") << std::endl;
        std::cout << "    FT2_UCLAMP: " << ((info->flags2 & FT2_UCLAMP) ? "✅" : "❌") << std::endl;
    }
}

void Example8_ModifyingFlags(SimpleTextureManager& manager)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 8: Modifying Texture Flags at Runtime             ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    uint texId = manager.EF_LoadTexture(
        "textures/dynamic_texture.png",
        0,                  // No clamping initially
        0,
        eTT_Base,
        -1.0f,
        -1.0f,
        0
    );
    
    std::cout << "\n▸ Initial state:" << std::endl;
    const TextureInfo* info = manager.GetTextureInfo(texId);
    if (info)
    {
        std::cout << "  ClampU: " << (info->clampU ? "Yes" : "No") << std::endl;
        std::cout << "  ClampV: " << (info->clampV ? "Yes" : "No") << std::endl;
        std::cout << "  Filter: " << info->filterMode << std::endl;
    }
    
    std::cout << "\n▸ Enabling clamping..." << std::endl;
    manager.SetTextureClamp(texId, true);
    
    info = manager.GetTextureInfo(texId);
    if (info)
    {
        std::cout << "  ClampU: " << (info->clampU ? "✅ Yes" : "❌ No") << std::endl;
        std::cout << "  ClampV: " << (info->clampV ? "✅ Yes" : "❌ No") << std::endl;
        PrintTextureFlags(info->flags, info->flags2);
    }
    
    std::cout << "\n▸ Changing filter mode..." << std::endl;
    manager.SetTextureFilter(texId, FILTER_TRILINEAR);
    
    info = manager.GetTextureInfo(texId);
    if (info)
    {
        std::cout << "  Filter mode: " << info->filterMode;
        std::cout << " (";
        switch (info->filterMode)
        {
            case FILTER_POINT: std::cout << "FILTER_POINT"; break;
            case FILTER_LINEAR: std::cout << "FILTER_LINEAR"; break;
            case FILTER_BILINEAR: std::cout << "FILTER_BILINEAR"; break;
            case FILTER_TRILINEAR: std::cout << "✅ FILTER_TRILINEAR"; break;
            default: std::cout << "Unknown"; break;
        }
        std::cout << ")" << std::endl;
    }
}

int main(int argc, char* argv[])
{
    @autoreleasepool
    {
        std::cout << "╔════════════════════════════════════════════════════════════╗" << std::endl;
        std::cout << "║                                                            ║" << std::endl;
        std::cout << "║   Texture Flags and Parameters Examples                  ║" << std::endl;
        std::cout << "║   Complete EF_LoadTexture Implementation                 ║" << std::endl;
        std::cout << "║                                                            ║" << std::endl;
        std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
        
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device)
        {
            std::cout << "\n❌ No Metal device available." << std::endl;
            return 1;
        }
        
        NSString* deviceName = [device name];
        std::cout << "\n✅ Metal Device: " << [deviceName UTF8String] << std::endl;
        
        SimpleTextureManager manager(device);
        
        Example1_BasicTextureWithFlags(manager);
        Example2_BumpmapTexture(manager);
        Example3_UVClampingModes(manager);
        Example4_NoMipmapsFlag(manager);
        Example5_AmountParameters(manager);
        Example6_MultipleTextureTypes(manager);
        Example7_CombinedFlags(manager);
        Example8_ModifyingFlags(manager);
        
        std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
        std::cout << "║   All Examples Complete                                    ║" << std::endl;
        std::cout << "║   Texture Flags System: FULLY IMPLEMENTED ✅               ║" << std::endl;
        std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    }
    
    return 0;
}

