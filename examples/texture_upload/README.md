# Metal Texture Upload Example

This example demonstrates the proper implementation of the `DownLoadToVideoMemory` method for uploading textures to Metal GPU on macOS.

## Overview

The `DownLoadToVideoMemory` method is a critical component of the FarCry Mac Silicon port, responsible for uploading texture data from CPU memory to GPU video memory using Apple's Metal API.

## Features Demonstrated

1. **Basic Texture Upload** - Simple RGBA texture upload
2. **Mipmap Generation** - Automatic mipmap creation using Metal blit encoder
3. **Terrain Texture Simulation** - Example similar to terrain sector texture updates
4. **Format Conversion** - Support for various texture formats (RGBA8, RGB8, DXT/BC compression)

## Building the Example

```bash
cd /Users/mykola/projects/FarCry/examples/texture_upload
mkdir -p build
cd build
cmake ..
make
```

## Running the Example

```bash
./texture_upload_example
```

## Implementation Details

### Method Signature

```cpp
unsigned int DownLoadToVideoMemory(
    unsigned char* data,   // Texture data buffer
    int w,                 // Width in pixels
    int h,                 // Height in pixels
    ETEX_Format eTFSrc,    // Source format
    ETEX_Format eTFDst,    // Destination format
    int nummipmap,         // Number of mipmap levels (0 = no mipmaps)
    bool repeat,           // Texture wrapping mode
    int filter,            // Filter mode (FILTER_BILINEAR, etc.)
    int Id,                // Texture ID (0 = allocate new)
    char* szCacheName,     // Optional cache name
    int flags              // Additional flags
);
```

### Key Implementation Features

1. **Format-Aware Byte Calculation**
   - Uses `GetBytesPerPixel()` to calculate correct data size
   - Supports 1, 2, and 4 bytes-per-pixel formats
   - Handles compressed formats (DXT1/3/5)

2. **Mipmap Generation**
   - Configures texture descriptor with mipmap support
   - Uses Metal's hardware-accelerated blit encoder
   - Automatically generates all mipmap levels

3. **Memory Management**
   - Proper texture descriptor configuration
   - Shared storage mode for CPU-GPU accessibility
   - Accurate memory tracking

4. **Format Conversion**
   - Comprehensive ETEX_Format to MTLPixelFormat mapping
   - Platform-specific BC/DXT compression support
   - Fallback to RGBA8 for unsupported formats

## Texture Formats Supported

| ETEX_Format | MTLPixelFormat | Bytes/Pixel | Description |
|-------------|----------------|-------------|-------------|
| eTF_8888 | RGBA8Unorm | 4 | Standard 32-bit RGBA |
| eTF_0888 | RGBA8Unorm | 4 | 24-bit RGB (stored as RGBA) |
| eTF_4444 | RGBA8Unorm | 2 | 16-bit RGBA (converted) |
| eTF_1555 | RGBA8Unorm | 2 | 16-bit RGB + 1-bit alpha |
| eTF_0565 | RGBA8Unorm | 2 | 16-bit RGB (5-6-5) |
| eTF_DXT1 | BC1_RGBA* | 0 | Block compression 1 |
| eTF_DXT3 | BC2_RGBA* | 0 | Block compression 2 |
| eTF_DXT5 | BC3_RGBA* | 0 | Block compression 3 |

*BC formats only available on macOS desktop (not iOS)

## Usage in FarCry

This implementation is used throughout the FarCry engine for:

- Terrain sector texture uploads
- Dynamic texture updates
- Font texture management
- Shader texture loading
- Lightmap uploads

## Example Usage

```cpp
// Create texture data
std::vector<unsigned char> textureData(256 * 256 * 4);
// ... fill with data ...

// Upload to GPU
unsigned int texId = DownLoadToVideoMemory(
    textureData.data(),
    256,               // width
    256,               // height
    eTF_8888,          // source format
    eTF_8888,          // destination format
    4,                 // generate 4 mipmap levels
    true,              // repeat wrapping
    FILTER_TRILINEAR,  // trilinear filtering
    0,                 // allocate new ID
    "my_texture",      // cache name
    0                  // no special flags
);
```
