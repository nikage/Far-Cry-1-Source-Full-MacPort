////////////////////////////////////////////////////////////////////////////
//
//  Example: Metal Texture Upload Implementation
//  Demonstrates proper usage of DownLoadToVideoMemory method
// -------------------------------------------------------------------------
//  File name:   texture_upload_example.mm
//  Created:     26/10/2025
//  Description: Example code showing texture upload to Metal GPU
// -------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <iostream>
#import <vector>

enum ETEX_Format
{
    eTF_Unknown = 0,
    eTF_0888,
    eTF_8888,
    eTF_4444,
    eTF_1555,
    eTF_0565,
    eTF_DXT1,
    eTF_DXT3,
    eTF_DXT5,
};

#define FILTER_BILINEAR 1
#define FILTER_TRILINEAR 2

int GetBytesPerPixel(ETEX_Format format)
{
    switch (format)
    {
        case eTF_8888:
        case eTF_0888:
            return 4;
        
        case eTF_4444:
        case eTF_1555:
        case eTF_0565:
            return 2;
        
        case eTF_DXT1:
        case eTF_DXT3:
        case eTF_DXT5:
            return 0;
        
        default:
            return 4;
    }
}

MTLPixelFormat ConvertToMetalFormat(ETEX_Format format)
{
    switch (format)
    {
        case eTF_8888:
            return MTLPixelFormatRGBA8Unorm;
        
        case eTF_0888:
            return MTLPixelFormatRGBA8Unorm;
        
        case eTF_4444:
        case eTF_1555:
        case eTF_0565:
            return MTLPixelFormatRGBA8Unorm;
        
        case eTF_DXT1:
#if TARGET_OS_MAC && !TARGET_OS_IPHONE
            return MTLPixelFormatBC1_RGBA;
#else
            return MTLPixelFormatRGBA8Unorm;
#endif
        
        case eTF_DXT3:
#if TARGET_OS_MAC && !TARGET_OS_IPHONE
            return MTLPixelFormatBC2_RGBA;
#else
            return MTLPixelFormatRGBA8Unorm;
#endif
        
        case eTF_DXT5:
#if TARGET_OS_MAC && !TARGET_OS_IPHONE
            return MTLPixelFormatBC3_RGBA;
#else
            return MTLPixelFormatRGBA8Unorm;
#endif
        
        default:
            return MTLPixelFormatRGBA8Unorm;
    }
}

unsigned int DownLoadToVideoMemory(id<MTLDevice> device, id<MTLCommandQueue> commandQueue,
                                   unsigned char* data, int w, int h, 
                                   ETEX_Format eTFSrc, ETEX_Format eTFDst, 
                                   int nummipmap)
{
    assert(data && "DownLoadToVideoMemory: data cannot be null!");
    assert(w > 0 && h > 0 && "DownLoadToVideoMemory: dimensions must be positive!");
    assert(device && "DownLoadToVideoMemory: device cannot be null!");
    
    if (!data || w <= 0 || h <= 0)
    {
        std::cout << "   ❌ Invalid parameters" << std::endl;
        return 0;
    }
    
    if (!device)
    {
        std::cout << "   ❌ No Metal device" << std::endl;
        return 0;
    }
    
    MTLPixelFormat metalFormat = ConvertToMetalFormat(eTFDst);
    if (metalFormat == MTLPixelFormatInvalid)
    {
        std::cout << "   ❌ Invalid Metal format" << std::endl;
        return 0;
    }
    
    int bytesPerPixel = GetBytesPerPixel(eTFDst);
    if (bytesPerPixel == 0)
    {
        std::cout << "   ⚠️  Compressed format (bytes-per-pixel = 0)" << std::endl;
        bytesPerPixel = 4;
    }
    
    size_t dataSize = w * h * bytesPerPixel;
    
    bool useMipmaps = (nummipmap > 0);
    int mipLevels = useMipmaps ? nummipmap : 1;
    
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:metalFormat
                                                                                           width:w
                                                                                          height:h
                                                                                       mipmapped:useMipmaps];
    
    if (useMipmaps)
    {
        descriptor.mipmapLevelCount = mipLevels;
    }
    
    descriptor.usage = MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModeShared;
    
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    assert(texture && "DownLoadToVideoMemory: failed to create Metal texture!");
    
    if (!texture)
    {
        std::cout << "   ❌ Failed to create Metal texture" << std::endl;
        return 0;
    }
    
    size_t bytesPerRow = w * bytesPerPixel;
    MTLRegion region = MTLRegionMake2D(0, 0, w, h);
    
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:data
               bytesPerRow:bytesPerRow];
    
    if (useMipmaps && nummipmap > 1 && commandQueue)
    {
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder generateMipmapsForTexture:texture];
        [blitEncoder endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
        std::cout << "   ✅ Mipmaps generated" << std::endl;
    }
    
    std::cout << "   ✅ Texture created: " << w << "x" << h << " (" << dataSize << " bytes)" << std::endl;
    return (unsigned int)1;
}

void Example1_BasicTextureUpload(id<MTLDevice> device, id<MTLCommandQueue> commandQueue)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 1: Basic Texture Upload                           ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    const int width = 256;
    const int height = 256;
    std::vector<unsigned char> textureData(width * height * 4);
    
    for (int i = 0; i < width * height * 4; i += 4)
    {
        textureData[i + 0] = 255;
        textureData[i + 1] = 128;
        textureData[i + 2] = 64;
        textureData[i + 3] = 255;
    }
    
    std::cout << "\nUploading 256x256 RGBA texture..." << std::endl;
    unsigned int result = DownLoadToVideoMemory(
        device,
        commandQueue,
        textureData.data(),
        width,
        height,
        eTF_8888,
        eTF_8888,
        0
    );
    
    std::cout << (result > 0 ? "✅ Success" : "❌ Failed") << std::endl;
}

void Example2_MipmappedTexture(id<MTLDevice> device, id<MTLCommandQueue> commandQueue)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 2: Texture with Mipmap Generation                 ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    const int width = 512;
    const int height = 512;
    std::vector<unsigned char> textureData(width * height * 4);
    
    for (int y = 0; y < height; y++)
    {
        for (int x = 0; x < width; x++)
        {
            int idx = (y * width + x) * 4;
            textureData[idx + 0] = x % 256;
            textureData[idx + 1] = y % 256;
            textureData[idx + 2] = (x + y) % 256;
            textureData[idx + 3] = 255;
        }
    }
    
    std::cout << "\nUploading 512x512 RGBA texture with 4 mipmap levels..." << std::endl;
    unsigned int result = DownLoadToVideoMemory(
        device,
        commandQueue,
        textureData.data(),
        width,
        height,
        eTF_8888,
        eTF_8888,
        4
    );
    
    std::cout << (result > 0 ? "✅ Success" : "❌ Failed") << std::endl;
}

void Example3_TerrainTexture(id<MTLDevice> device, id<MTLCommandQueue> commandQueue)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 3: Terrain Sector Texture (Simulated)             ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    const int nTexSize = 128;
    std::vector<unsigned char> pTexData(nTexSize * nTexSize * 3);
    
    for (int y = 0; y < nTexSize; y++)
    {
        for (int x = 0; x < nTexSize; x++)
        {
            int idx = (y * nTexSize + x) * 3;
            pTexData[idx + 0] = (x + y) % 128 + 64;
            pTexData[idx + 1] = x % 128 + 64;
            pTexData[idx + 2] = y % 128 + 64;
        }
    }
    
    std::cout << "\nSimulating terrain texture update (128x128 RGB)..." << std::endl;
    std::cout << "Similar to: GetRenderer()->UpdateTextureInVideoMemory(...)" << std::endl;
    
    unsigned int result = DownLoadToVideoMemory(
        device,
        commandQueue,
        pTexData.data(),
        nTexSize,
        nTexSize,
        eTF_0888,
        eTF_0888,
        0
    );
    
    std::cout << (result > 0 ? "✅ Success" : "❌ Failed") << std::endl;
}

void Example4_DifferentFormats(id<MTLDevice> device, id<MTLCommandQueue> commandQueue)
{
    std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
    std::cout << "║ Example 4: Various Texture Formats                        ║" << std::endl;
    std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    
    struct FormatExample
    {
        ETEX_Format format;
        const char* name;
        const char* description;
    };
    
    FormatExample formats[] = {
        { eTF_8888, "RGBA8888", "Standard 32-bit RGBA" },
        { eTF_0888, "RGB888", "24-bit RGB (stored as RGBA on Metal)" },
        { eTF_4444, "RGBA4444", "16-bit RGBA (4 bits per channel)" },
        { eTF_DXT1, "DXT1/BC1", "Block compression (macOS desktop only)" },
    };
    
    const int width = 64;
    const int height = 64;
    
    for (const auto& fmt : formats)
    {
        std::cout << "\n▸ Format: " << fmt.name << " - " << fmt.description << std::endl;
        
        int bpp = GetBytesPerPixel(fmt.format);
        if (bpp == 0) bpp = 4;
        std::vector<unsigned char> textureData(width * height * bpp, 128);
        
        unsigned int result = DownLoadToVideoMemory(
            device,
            commandQueue,
            textureData.data(),
            width,
            height,
            fmt.format,
            fmt.format,
            0
        );
        
        std::cout << "  " << (result > 0 ? "✅" : "❌") << " " << fmt.name << std::endl;
    }
}

int main(int argc, char* argv[])
{
    @autoreleasepool
    {
        std::cout << "╔════════════════════════════════════════════════════════════╗" << std::endl;
        std::cout << "║                                                            ║" << std::endl;
        std::cout << "║   Metal Texture Upload Examples                           ║" << std::endl;
        std::cout << "║   DownLoadToVideoMemory Implementation                    ║" << std::endl;
        std::cout << "║                                                            ║" << std::endl;
        std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
        
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device)
        {
            std::cout << "\n⚠️  No Metal device available." << std::endl;
            std::cout << "    This example requires a Mac with Metal support." << std::endl;
            std::cout << "    Code compilation successful, but runtime requires GPU." << std::endl;
            return 0;
        }
        
        NSString* deviceName = [device name];
        std::cout << "\n✅ Metal Device: " << [deviceName UTF8String] << std::endl;
        
        id<MTLCommandQueue> commandQueue = [device newCommandQueue];
        if (!commandQueue)
        {
            std::cout << "❌ Failed to create command queue." << std::endl;
            return 1;
        }
        std::cout << "✅ Command Queue: Ready" << std::endl;
        
        Example1_BasicTextureUpload(device, commandQueue);
        Example2_MipmappedTexture(device, commandQueue);
        Example3_TerrainTexture(device, commandQueue);
        Example4_DifferentFormats(device, commandQueue);
        
        std::cout << "\n╔════════════════════════════════════════════════════════════╗" << std::endl;
        std::cout << "║   All Examples Complete                                    ║" << std::endl;
        std::cout << "╚════════════════════════════════════════════════════════════╝" << std::endl;
    }
    
    return 0;
}


