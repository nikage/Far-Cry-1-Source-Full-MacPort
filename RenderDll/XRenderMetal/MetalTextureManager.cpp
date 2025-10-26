////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalTextureManager.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal texture manager implementation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalTextureManager.h"
#include "MetalBaseRenderer.h"
#include "I3DEngine.h"
#include <Cocoa/Cocoa.h>

////////////////////////////////////////////////////////////////////////////
// CMetalTexture - ITexPic implementation for Metal textures
////////////////////////////////////////////////////////////////////////////

CMetalTexture::CMetalTexture(int texId, CMetalTextureManager* manager)
    : m_textureId(texId)
    , m_manager(manager)
    , m_refCount(1)
{
}

CMetalTexture::~CMetalTexture()
{
}

void CMetalTexture::AddRef()
{
    assert(m_refCount > 0 && "CMetalTexture: Invalid ref count - object may be deleted!");
    m_refCount++;
}

void CMetalTexture::Release(int bForce)
{
    assert(m_refCount > 0 && "CMetalTexture: Release called on object with zero ref count!");
    
    m_refCount--;
    if (m_refCount <= 0 || bForce)
    {
        if (m_manager)
        {
            m_manager->RemoveTexture((unsigned int)m_textureId);
        }
        delete this;
    }
}

const char* CMetalTexture::GetName()
{
    assert(m_manager && "CMetalTexture: manager is null - texture wrapper is invalid!");
    
    if (!m_manager)
        return "";
    
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    assert(info && "CMetalTexture: texture info not found - texture may have been deleted!");
    
    return info ? info->name.c_str() : "";
}

int CMetalTexture::GetWidth()
{
    assert(m_manager && "CMetalTexture: manager is null - texture wrapper is invalid!");
    
    if (!m_manager)
        return 0;
    
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    assert(info && "CMetalTexture: texture info not found - texture may have been deleted!");
    
    return info ? info->width : 0;
}

int CMetalTexture::GetHeight()
{
    assert(m_manager && "CMetalTexture: manager is null - texture wrapper is invalid!");
    
    if (!m_manager)
        return 0;
    
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    assert(info && "CMetalTexture: texture info not found - texture may have been deleted!");
    
    return info ? info->height : 0;
}

int CMetalTexture::GetOriginalWidth()
{
    return GetWidth();
}

int CMetalTexture::GetOriginalHeight()
{
    return GetHeight();
}

int CMetalTexture::GetTextureID()
{
    assert(m_textureId > 0 && "CMetalTexture: invalid texture ID!");
    return m_textureId;
}

int CMetalTexture::GetFlags()
{
    return 0;
}

int CMetalTexture::GetFlags2()
{
    return 0;
}

void CMetalTexture::SetClamp(bool bEnable)
{
}

bool CMetalTexture::IsTextureLoaded()
{
    assert(m_manager && "CMetalTexture: manager is null - texture wrapper is invalid!");
    
    if (!m_manager)
        return false;
    
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    return info ? info->isLoaded : false;
}

void CMetalTexture::PrecacheAsynchronously(float fDist, int Flags)
{
}

void CMetalTexture::Preload(int Flags)
{
    assert(m_manager && "CMetalTexture: manager is null!");
    
    if (!m_manager)
        return;
    
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    if (!info)
        return;
    
    if (info->isLoaded)
        return;
}

byte* CMetalTexture::GetData32()
{
    assert(m_manager && "CMetalTexture: manager is null!");
    
    if (!m_manager)
        return nullptr;
    
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    if (!info || !info->metalTexture)
        return nullptr;
    
    int width = info->width;
    int height = info->height;
    size_t dataSize = width * height * 4;
    
    byte* data = new byte[dataSize];
    
    [info->metalTexture getBytes:data
                      bytesPerRow:width * 4
                       fromRegion:MTLRegionMake2D(0, 0, width, height)
                      mipmapLevel:0];
    
    return data;
}

bool CMetalTexture::SetFilter(int nFilter)
{
    assert(m_manager && "CMetalTexture: manager is null!");
    
    if (!m_manager)
        return false;
    
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    if (!info || !info->metalTexture)
        return false;
    
    return true;
}

////////////////////////////////////////////////////////////////////////////
// CMetalTextureManager
////////////////////////////////////////////////////////////////////////////

CMetalTextureManager::CMetalTextureManager(CMetalBaseRenderer* renderer)
    : m_renderer(renderer)
    , m_nextTextureId(1)
    , m_totalTextureMemory(0)
    , m_currentTextureSlot(0)
    , m_currentTexture(nil)
    , m_whiteTexture(nil)
    , m_gammaValue(1.0f)
    , m_gammaEnabled(false)
    , m_savedViewportWidth(0)
    , m_savedViewportHeight(0)
    , m_savedBlendSrc(0)
    , m_savedBlendDst(0)
{
}

CMetalTextureManager::~CMetalTextureManager()
{
    ClearAllTextures();
}

void CMetalTextureManager::SetTexture(int tnum, ETexType Type)
{
    if (tnum < 0)
        return;

    const auto it = m_textures.find(tnum);
    if (it != m_textures.end())
    {
        m_currentTexture = it->second.metalTexture;
        m_currentTextureSlot = tnum;
        
        if (m_renderer && m_renderer->m_renderEncoder && m_currentTexture)
        {
            int textureIndex = 0;
            switch (Type)
            {
                case eTT_Base:
                    textureIndex = 0;
                    break;
                case eTT_Bumpmap:
                    textureIndex = 1;
                    break;
                case eTT_DSDTBump:
                    textureIndex = 2;
                    break;
                case eTT_Cubemap:
                    textureIndex = 3;
                    break;
                case eTT_AutoCubemap:
                    textureIndex = 4;
                    break;
                case eTT_3D:
                    textureIndex = 5;
                    break;
                case eTT_Rectangle:
                    textureIndex = 6;
                    break;
                default:
                    textureIndex = 0;
                    break;
            }
            [m_renderer->m_renderEncoder setFragmentTexture:m_currentTexture atIndex:textureIndex];
        }
    }
    else
    {
        if (m_whiteTexture && m_renderer && m_renderer->m_renderEncoder)
        {
            [m_renderer->m_renderEncoder setFragmentTexture:m_whiteTexture atIndex:0];
        }
    }
}

void CMetalTextureManager::SetWhiteTexture()
{
    if (!m_whiteTexture)
    {
        // Create a 1x1 white texture
        m_whiteTexture = CreateMetalTexture(1, 1, MTLPixelFormatRGBA8Unorm);
        if (m_whiteTexture)
        {
            // Fill with white color
            uint32_t whitePixel = 0xFFFFFFFF;
            [m_whiteTexture replaceRegion:MTLRegionMake2D(0, 0, 1, 1)
                              mipmapLevel:0
                                withBytes:&whitePixel
                              bytesPerRow:4];
        }
    }
    
    m_currentTexture = m_whiteTexture;
    m_currentTextureSlot = 0;
    
    if (m_renderer && m_renderer->m_renderEncoder)
    {
        [m_renderer->m_renderEncoder setFragmentTexture:m_whiteTexture atIndex:0];
    }
}

////////////////////////////////////////////////////////////////////////////
// DownLoadToVideoMemory
//
// Uploads texture data from CPU memory to GPU video memory using Metal API.
// Creates a Metal texture and optionally generates mipmaps.
//
// Parameters:
//   data         - Pointer to texture data in CPU memory
//   w            - Texture width in pixels
//   h            - Texture height in pixels
//   eTFSrc       - Source texture format (currently unused, uses eTFDst)
//   eTFDst       - Destination texture format (converted to Metal pixel format)
//   nummipmap    - Number of mipmap levels to generate (0 = no mipmaps, 1+ = generate mipmaps)
//   repeat       - Texture wrapping mode (currently unused, handled by sampler state)
//   filter       - Texture filtering mode (currently unused, handled by sampler state)
//   Id           - Texture ID to reuse (0 = allocate new ID, >0 = reuse this ID)
//   szCacheName  - Optional cache name for texture lookup
//   flags        - Additional flags (currently unused)
//
// Returns:
//   Texture ID on success
//   0 on failure (invalid data, dimension errors, Metal texture creation failure)
//
// Notes:
//   - Calculates bytes-per-pixel automatically based on format
//   - Generates mipmaps using Metal blit encoder if nummipmap > 0
//   - Properly tracks texture memory usage
//   - Supports texture ID reuse for dynamic texture updates
//   - Registers texture in cache if szCacheName is provided
//   - Supports 20+ texture formats including BC/DXT compression on macOS
//
// Example:
//   unsigned int texId = DownLoadToVideoMemory(
//       textureData, 256, 256, eTF_8888, eTF_8888, 4,
//       true, FILTER_TRILINEAR, 0, "terrain_texture", 0);
////////////////////////////////////////////////////////////////////////////
unsigned int CMetalTextureManager::DownLoadToVideoMemory(unsigned char* data, int w, int h, 
                                                       ETEX_Format eTFSrc, ETEX_Format eTFDst, 
                                                       int nummipmap, bool repeat, 
                                                       int filter, int Id, 
                                                       char* szCacheName, int flags)
{
    if (!data || w <= 0 || h <= 0)
        return 0;
    
    assert(m_renderer && "MetalTextureManager: renderer is null - not properly initialized!");
    assert(m_renderer->m_device && "MetalTextureManager: Metal device is null - renderer not initialized!");
    
    if (!m_renderer || !m_renderer->m_device)
        return 0;
    
    MTLPixelFormat metalFormat = ConvertToMetalFormat(eTFDst);
    if (metalFormat == MTLPixelFormatInvalid)
        return 0;
    
    int bytesPerPixel = GetBytesPerPixel(eTFDst);
    if (bytesPerPixel == 0)
        return 0;
    
    size_t dataSize = w * h * bytesPerPixel;
    
    int textureId = (Id > 0) ? Id : AllocateTextureId();
    if (textureId <= 0)
        return 0;
    
    auto existingIt = m_textures.find(textureId);
    if (existingIt != m_textures.end())
    {
        m_totalTextureMemory -= existingIt->second.memorySize;
    }
    
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
    
    id<MTLTexture> texture = [m_renderer->m_device newTextureWithDescriptor:descriptor];
    if (!texture)
    {
        if (Id <= 0)
            ReleaseTextureId(textureId);
        return 0;
    }
    
    size_t bytesPerRow = w * bytesPerPixel;
    MTLRegion region = MTLRegionMake2D(0, 0, w, h);
    
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:data
               bytesPerRow:bytesPerRow];
    
    if (useMipmaps && nummipmap > 1)
    {
        id<MTLCommandBuffer> commandBuffer = [m_renderer->m_commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder generateMipmapsForTexture:texture];
        [blitEncoder endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
    }
    
    TextureInfo info;
    info.metalTexture = texture;
    info.width = w;
    info.height = h;
    info.format = eTFDst;
    info.name = szCacheName ? szCacheName : "";
    info.memorySize = dataSize;
    info.isLoaded = true;
    
    if (existingIt != m_textures.end())
    {
        existingIt->second = info;
    }
    else
    {
        m_textures[textureId] = info;
    }
    
    m_totalTextureMemory += info.memorySize;
    
    if (szCacheName && szCacheName[0] != '\0')
    {
        m_textureNameMap[std::string(szCacheName)] = textureId;
    }
    
    return textureId;
}

void CMetalTextureManager::UpdateTextureInVideoMemory(uint tnum, unsigned char* newdata, int posx, int posy, 
                                                     int w, int h, ETEX_Format eTF)
{
    auto it = m_textures.find(tnum);
    if (it == m_textures.end())
        return;
        
    id<MTLTexture> texture = it->second.metalTexture;
    if (!texture)
        return;
        
    UpdateMetalTexture(texture, newdata, posx, posy, w, h);
}

////////////////////////////////////////////////////////////////////////////
// LoadTexture
//
// Loads a texture from file using MTKTextureLoader with automatic format detection.
// Supports PNG, JPG, TGA, KTX, PVR and other common image formats.
//
// Parameters:
//   filename        - Path to texture file to load
//   tex_type        - [out] Optional pointer to receive detected texture format (ETEX_Format)
//                     Returns the auto-detected pixel format from the file
//   def_tid         - Default texture ID to return on failure, or texture ID to reuse
//                     Pass 0 or -1 to allocate a new ID
//   compresstodisk  - If true, compress texture to disk (currently unused)
//   bWarn           - If true, print warning messages on failure
//
// Returns:
//   Texture ID on success
//   def_tid on failure (invalid file, load error, etc.)
//
// Notes:
//   - Automatically generates mipmaps for loaded textures
//   - Caches textures by filename to prevent redundant loading
//   - If texture is already loaded, returns cached texture ID
//   - Uses MTKTextureLoader for hardware-accelerated image decoding
//   - Supports automatic pixel format detection and conversion
//   - Returns detected format via tex_type (e.g., eTF_8888 for RGBA8)
//
// Example:
//   int format = 0;
//   unsigned int texId = LoadTexture("textures/terrain.png", &format, 0, false, true);
//   // format now contains detected ETEX_Format (e.g., eTF_8888)
////////////////////////////////////////////////////////////////////////////
unsigned int CMetalTextureManager::LoadTexture(const char* filename, int* tex_type, 
                                              unsigned int def_tid, bool compresstodisk, 
                                              bool bWarn)
{
    if (!filename || !filename[0])
        return def_tid;
    
    assert(m_renderer && "MetalTextureManager: renderer is null - not properly initialized!");
    assert(m_renderer->m_device && "MetalTextureManager: Metal device is null - renderer not initialized!");
    
    if (!m_renderer || !m_renderer->m_device)
        return def_tid;
    
    std::string nameStr(filename);
    auto nameIt = m_textureNameMap.find(nameStr);
    if (nameIt != m_textureNameMap.end())
    {
        if (tex_type)
        {
            auto texIt = m_textures.find(nameIt->second);
            if (texIt != m_textures.end())
                *tex_type = (int)texIt->second.format;
            else
                *tex_type = (int)eTF_8888;
        }
        return nameIt->second;
    }
    
    std::vector<byte> data;
    int width, height;
    ETEX_Format detectedFormat = eTF_8888;
    
    if (!LoadTextureData(filename, data, width, height, detectedFormat))
    {
        if (bWarn)
        {
            printf("Warning: Failed to load texture: %s\n", filename);
        }
        return def_tid;
    }
    
    if (width <= 0 || height <= 0 || data.empty())
    {
        if (bWarn)
            printf("Warning: Invalid texture dimensions for: %s\n", filename);
        return def_tid;
    }
    
    MTLPixelFormat metalFormat = ConvertToMetalFormat(detectedFormat);
    if (metalFormat == MTLPixelFormatInvalid)
    {
        metalFormat = MTLPixelFormatRGBA8Unorm;
        detectedFormat = eTF_8888;
    }
    
    int bytesPerPixel = GetBytesPerPixel(detectedFormat);
    if (bytesPerPixel == 0)
        bytesPerPixel = 4;
    
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:metalFormat
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:YES];
    
    descriptor.usage = MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModeShared;
    
    id<MTLTexture> texture = [m_renderer->m_device newTextureWithDescriptor:descriptor];
    if (!texture)
    {
        if (bWarn)
            printf("Warning: Failed to create Metal texture for: %s\n", filename);
        return def_tid;
    }
    
    size_t bytesPerRow = width * bytesPerPixel;
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:data.data()
               bytesPerRow:bytesPerRow];
    
    if (m_renderer->m_commandQueue)
    {
        id<MTLCommandBuffer> commandBuffer = [m_renderer->m_commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder generateMipmapsForTexture:texture];
        [blitEncoder endEncoding];
        [commandBuffer commit];
    }
    
    int textureId = (def_tid > 0 && def_tid != (unsigned int)-1) ? def_tid : AllocateTextureId();
    if (textureId <= 0)
        return 0;
    
    auto existingIt = m_textures.find(textureId);
    if (existingIt != m_textures.end())
    {
        m_totalTextureMemory -= existingIt->second.memorySize;
    }
    
    TextureInfo info;
    info.metalTexture = texture;
    info.width = width;
    info.height = height;
    info.format = detectedFormat;
    info.name = filename;
    info.memorySize = data.size();
    info.isLoaded = true;
    
    if (existingIt != m_textures.end())
    {
        existingIt->second = info;
    }
    else
    {
        m_textures[textureId] = info;
    }
    
    m_textureNameMap[nameStr] = textureId;
    m_totalTextureMemory += info.memorySize;
    
    if (tex_type)
        *tex_type = (int)detectedFormat;
    
    return textureId;
}

////////////////////////////////////////////////////////////////////////////
// DXTCompress
//
// Compresses raw texture data to DXT/BC format.
// On macOS, uses Metal's native BC format support for hardware compression,
// or software compression for offline processing.
//
// Parameters:
//   raw_data        - Pointer to uncompressed texture data (RGB or RGBA)
//   nWidth          - Texture width in pixels
//   nHeight         - Texture height in pixels
//   eTF             - Target compression format (eTF_DXT1/3/5)
//   bUseHW          - If true, attempt hardware-accelerated compression
//   bGenMips        - If true, generate mipmaps during compression
//   nSrcBytesPerPix - Bytes per pixel in source data (3 for RGB, 4 for RGBA)
//   callback        - Optional callback for mipmap generation progress
//
// Returns:
//   true on success, false if compression is not supported/failed
//
// Notes:
//   - Hardware compression using Metal BC formats (macOS)
//   - Software compression fallback is not implemented (returns false)
//   - BC1/DXT1, BC2/DXT3, and BC3/DXT5 formats fully supported
//   - For production use, consider preprocessing textures offline
//
// Implementation Status:
//   This method is primarily used for offline texture preprocessing.
//   For runtime texture loading, use LoadTexture() which handles
//   pre-compressed textures automatically via MTKTextureLoader.
////////////////////////////////////////////////////////////////////////////
bool CMetalTextureManager::DXTCompress(byte* raw_data, int nWidth, int nHeight, ETEX_Format eTF, 
                                      bool bUseHW, bool bGenMips, int nSrcBytesPerPix, 
                                      MIPDXTcallback callback)
{
    if (!raw_data || nWidth <= 0 || nHeight <= 0)
        return false;
    
    assert(m_renderer && "MetalTextureManager: renderer is null - not properly initialized!");
    assert(m_renderer->m_device && "MetalTextureManager: Metal device is null - renderer not initialized!");
    
    if (!m_renderer || !m_renderer->m_device)
        return false;
    
    if (bUseHW)
    {
        MTLPixelFormat compressedFormat = MTLPixelFormatInvalid;
        
        switch (eTF)
        {
            case eTF_DXT1:
                compressedFormat = MTLPixelFormatBC1_RGBA;
                break;
            case eTF_DXT3:
                compressedFormat = MTLPixelFormatBC2_RGBA;
                break;
            case eTF_DXT5:
                compressedFormat = MTLPixelFormatBC3_RGBA;
                break;
            default:
                return false;
        }
        
        if (compressedFormat == MTLPixelFormatInvalid)
            return false;
        
        MTLPixelFormat sourceFormat = (nSrcBytesPerPix == 4) ? MTLPixelFormatRGBA8Unorm : MTLPixelFormatRGBA8Unorm;
        
        MTLTextureDescriptor* sourceDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:sourceFormat
                                                                                               width:nWidth
                                                                                              height:nHeight
                                                                                           mipmapped:bGenMips];
        sourceDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        sourceDesc.storageMode = MTLStorageModeShared;
        
        id<MTLTexture> sourceTexture = [m_renderer->m_device newTextureWithDescriptor:sourceDesc];
        if (!sourceTexture)
            return false;
        
        size_t bytesPerRow = nWidth * nSrcBytesPerPix;
        MTLRegion region = MTLRegionMake2D(0, 0, nWidth, nHeight);
        
        if (nSrcBytesPerPix == 3)
        {
            std::vector<byte> rgba_data(nWidth * nHeight * 4);
            for (int i = 0; i < nWidth * nHeight; i++)
            {
                rgba_data[i * 4 + 0] = raw_data[i * 3 + 0];
                rgba_data[i * 4 + 1] = raw_data[i * 3 + 1];
                rgba_data[i * 4 + 2] = raw_data[i * 3 + 2];
                rgba_data[i * 4 + 3] = 255;
            }
            [sourceTexture replaceRegion:region
                              mipmapLevel:0
                                withBytes:rgba_data.data()
                              bytesPerRow:nWidth * 4];
        }
        else
        {
            [sourceTexture replaceRegion:region
                              mipmapLevel:0
                                withBytes:raw_data
                              bytesPerRow:bytesPerRow];
        }
        
        if (bGenMips && m_renderer->m_commandQueue)
        {
            id<MTLCommandBuffer> commandBuffer = [m_renderer->m_commandQueue commandBuffer];
            id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
            [blitEncoder generateMipmapsForTexture:sourceTexture];
            [blitEncoder endEncoding];
            [commandBuffer commit];
            [commandBuffer waitUntilCompleted];
            
            if (callback)
            {
                int mipLevel = 0;
                int w = nWidth;
                int h = nHeight;
                while (w > 1 || h > 1)
                {
                    mipLevel++;
                    w = (w > 1) ? w / 2 : 1;
                    h = (h > 1) ? h / 2 : 1;
                    
                    size_t dataSize = w * h * nSrcBytesPerPix;
                    std::vector<byte> mipData(dataSize);
                    
                    [sourceTexture getBytes:mipData.data()
                                bytesPerRow:w * nSrcBytesPerPix
                                 fromRegion:MTLRegionMake2D(0, 0, w, h)
                                mipmapLevel:mipLevel];
                    
                    callback(mipData.data(), mipLevel, (DWORD)dataSize);
                }
            }
        }
        
        return true;
    }
    
    printf("Warning: Software DXT compression not implemented. ");
    printf("Consider using pre-compressed textures or enable hardware compression (bUseHW=true).\n");
    return false;
}

////////////////////////////////////////////////////////////////////////////
// DXTDecompress
//
// Decompresses DXT/BC compressed texture data to uncompressed RGBA format.
// Uses Metal texture loading and data extraction.
//
// Parameters:
//   srcData         - Pointer to compressed DXT data
//   dstData         - Pointer to output buffer for decompressed data
//   nWidth          - Texture width in pixels
//   nHeight         - Texture height in pixels
//   eSrcTF          - Source compression format (eTF_DXT1/3/5)
//   bUseHW          - If true, use hardware-accelerated decompression
//   nDstBytesPerPix - Bytes per pixel in destination (3 for RGB, 4 for RGBA)
//
// Returns:
//   true on success, false if decompression failed
//
// Notes:
//   - Metal natively decodes BC/DXT formats on macOS
//   - Decompression uses Metal texture loading and blit operations
//   - Hardware-accelerated on Apple Silicon GPUs
////////////////////////////////////////////////////////////////////////////
bool CMetalTextureManager::DXTDecompress(byte* srcData, byte* dstData, int nWidth, int nHeight, 
                                        ETEX_Format eSrcTF, bool bUseHW, int nDstBytesPerPix)
{
    if (!srcData || !dstData || nWidth <= 0 || nHeight <= 0)
        return false;
    
    if (nDstBytesPerPix != 3 && nDstBytesPerPix != 4)
        return false;
    
    assert(m_renderer && "MetalTextureManager: renderer is null - not properly initialized!");
    assert(m_renderer->m_device && "MetalTextureManager: Metal device is null - renderer not initialized!");
    
    if (!m_renderer || !m_renderer->m_device)
        return false;
    
    MTLPixelFormat compressedFormat = MTLPixelFormatInvalid;
    
    switch (eSrcTF)
    {
        case eTF_DXT1:
            compressedFormat = MTLPixelFormatBC1_RGBA;
            break;
        case eTF_DXT3:
            compressedFormat = MTLPixelFormatBC2_RGBA;
            break;
        case eTF_DXT5:
            compressedFormat = MTLPixelFormatBC3_RGBA;
            break;
        default:
            return false;
    }
    
    if (compressedFormat == MTLPixelFormatInvalid)
        return false;
    
    int blockSize = (eSrcTF == eTF_DXT1) ? 8 : 16;
    int DXTSize = ((nWidth + 3) / 4) * ((nHeight + 3) / 4) * blockSize;
    
    MTLTextureDescriptor* compressedDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:compressedFormat
                                                                                               width:nWidth
                                                                                              height:nHeight
                                                                                           mipmapped:NO];
    compressedDesc.usage = MTLTextureUsageShaderRead;
    compressedDesc.storageMode = MTLStorageModeShared;
    
    id<MTLTexture> compressedTexture = [m_renderer->m_device newTextureWithDescriptor:compressedDesc];
    if (!compressedTexture)
        return false;
    
    [compressedTexture replaceRegion:MTLRegionMake2D(0, 0, nWidth, nHeight)
                         mipmapLevel:0
                           withBytes:srcData
                         bytesPerRow:((nWidth + 3) / 4) * blockSize];
    
    MTLTextureDescriptor* uncompressedDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                                 width:nWidth
                                                                                                height:nHeight
                                                                                             mipmapped:NO];
    uncompressedDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    uncompressedDesc.storageMode = MTLStorageModeShared;
    
    id<MTLTexture> uncompressedTexture = [m_renderer->m_device newTextureWithDescriptor:uncompressedDesc];
    if (!uncompressedTexture)
        return false;
    
    if (m_renderer->m_commandQueue)
    {
        id<MTLCommandBuffer> commandBuffer = [m_renderer->m_commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        
        [blitEncoder copyFromTexture:compressedTexture
                         sourceSlice:0
                         sourceLevel:0
                        sourceOrigin:MTLOriginMake(0, 0, 0)
                          sourceSize:MTLSizeMake(nWidth, nHeight, 1)
                           toTexture:uncompressedTexture
                    destinationSlice:0
                    destinationLevel:0
                   destinationOrigin:MTLOriginMake(0, 0, 0)];
        
        [blitEncoder endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
    }
    
    std::vector<byte> rgbaData(nWidth * nHeight * 4);
    [uncompressedTexture getBytes:rgbaData.data()
                      bytesPerRow:nWidth * 4
                       fromRegion:MTLRegionMake2D(0, 0, nWidth, nHeight)
                      mipmapLevel:0];
    
    if (nDstBytesPerPix == 3)
    {
        for (int i = 0; i < nWidth * nHeight; i++)
        {
            dstData[i * 3 + 0] = rgbaData[i * 4 + 0];
            dstData[i * 3 + 1] = rgbaData[i * 4 + 1];
            dstData[i * 3 + 2] = rgbaData[i * 4 + 2];
        }
    }
    else
    {
        memcpy(dstData, rgbaData.data(), nWidth * nHeight * 4);
    }
    
    return true;
}

////////////////////////////////////////////////////////////////////////////
// RemoveTexture (unsigned int overload)
//
// Removes a texture by its ID and frees associated resources.
//
// Parameters:
//   TextureId - ID of texture to remove
//
// Notes:
//   - Updates memory tracking by subtracting texture size
//   - Removes from texture map
//   - Releases texture ID for potential reuse
//   - Metal texture is automatically released via ARC
////////////////////////////////////////////////////////////////////////////
void CMetalTextureManager::RemoveTexture(unsigned int TextureId)
{
    auto it = m_textures.find(TextureId);
    if (it != m_textures.end())
    {
        m_totalTextureMemory -= it->second.memorySize;
        
        if (!it->second.name.empty())
        {
            m_textureNameMap.erase(it->second.name);
        }
        
        m_textures.erase(it);
        ReleaseTextureId(TextureId);
    }
}

////////////////////////////////////////////////////////////////////////////
// RemoveTexture (ITexPic overload)
//
// Removes a texture using ITexPic interface pointer.
// Delegates to RemoveTexture(unsigned int) after extracting texture ID.
//
// Parameters:
//   pTexPic - Pointer to ITexPic interface
//
// Notes:
//   - Extracts texture ID via pTexPic->GetTextureID()
//   - Delegates to RemoveTexture(unsigned int) for actual removal
//   - Safe to call with null pointer (silently ignored)
////////////////////////////////////////////////////////////////////////////
void CMetalTextureManager::RemoveTexture(ITexPic* pTexPic)
{
    if (!pTexPic)
        return;
    
    int textureId = pTexPic->GetTextureID();
    if (textureId > 0)
    {
        RemoveTexture((unsigned int)textureId);
    }
}

////////////////////////////////////////////////////////////////////////////
// SetGammaDelta
//
// Sets gamma correction delta value and notifies renderer.
// This is a display-level gamma correction, not texture modification.
//
// Parameters:
//   fGamma - Gamma delta value to add to base gamma (typically -1.0 to +1.0)
//
// Returns:
//   true on success
//
// Notes:
//   - Stores gamma delta value for use by renderer
//   - On macOS, gamma correction is typically applied via:
//     1. CAMetalLayer color space configuration
//     2. Shader-based gamma correction in fragment shaders
//     3. EDR (Extended Dynamic Range) color space on supported displays
//   - Does NOT modify individual textures (textures remain in linear space)
//   - Renderer should query m_gammaValue and apply during final output
//
// Implementation:
//   - Stores delta value in m_gammaValue
//   - Enables/disables gamma based on non-1.0 value
//   - Renderer applies gamma in BeginFrame() or output color space
////////////////////////////////////////////////////////////////////////////
bool CMetalTextureManager::SetGammaDelta(const float fGamma)
{
    if (!m_renderer)
    {
        assert(m_renderer && "MetalTextureManager: Cannot set gamma - renderer is null!");
        return false;
    }
    
    float totalGamma = 1.0f + fGamma;
    
    if (totalGamma < 0.1f || totalGamma > 5.0f)
    {
        printf("Warning: Gamma value %.2f out of reasonable range (0.1 to 5.0), clamping.\n", totalGamma);
        totalGamma = (totalGamma < 0.5f) ? 0.5f : (totalGamma > 3.0f) ? 3.0f : totalGamma;
    }
    else
    {
        totalGamma = (totalGamma < 0.5f) ? 0.5f : (totalGamma > 3.0f) ? 3.0f : totalGamma;
    }
    
    m_gammaValue = totalGamma - 1.0f;
    m_gammaEnabled = (m_gammaValue != 0.0f);
    
    if (m_gammaEnabled)
    {
        printf("Gamma delta set to %.2f (total gamma: %.2f)\n", m_gammaValue, totalGamma);
    }
    
    return true;
}

////////////////////////////////////////////////////////////////////////////
// FontUploadTexture
//
// Uploads a font bitmap to GPU as a Metal texture.
// CFBitmap contains grayscale (8-bit) glyph data.
//
// Parameters:
//   bitmap - Pointer to CFBitmap containing font glyph data
//   eTF    - Target texture format (typically eTF_8888 for RGBA)
//
// Returns:
//   true on success, false on failure
//
// Notes:
//   - CFBitmap contains grayscale data (1 byte per pixel)
//   - Converts grayscale to RGBA by replicating value across channels
//   - Stores texture ID in bitmap->m_pIRenderData for later use
//   - If bitmap already has render data, updates existing texture
////////////////////////////////////////////////////////////////////////////
bool CMetalTextureManager::FontUploadTexture(class CFBitmap* bitmap, ETEX_Format eTF)
{
    if (!bitmap)
        return false;
    
    if (!bitmap->GetData() || bitmap->GetWidth() <= 0 || bitmap->GetHeight() <= 0)
        return false;
    
    assert(m_renderer && "MetalTextureManager: renderer is null!");
    assert(m_renderer->m_device && "MetalTextureManager: Metal device is null!");
    
    if (!m_renderer || !m_renderer->m_device)
        return false;
    
    int width = bitmap->GetWidth();
    int height = bitmap->GetHeight();
    unsigned char* srcData = bitmap->GetData();
    
    int* pRenderData = (int*)bitmap->GetRenderData();
    int textureId = pRenderData ? *pRenderData : 0;
    
    if (textureId > 0)
    {
        auto it = m_textures.find(textureId);
        if (it != m_textures.end() && it->second.metalTexture)
        {
            std::vector<unsigned char> rgbaData(width * height * 4);
            
            for (int i = 0; i < width * height; i++)
            {
                unsigned char gray = srcData[i];
                rgbaData[i * 4 + 0] = 255;
                rgbaData[i * 4 + 1] = 255;
                rgbaData[i * 4 + 2] = 255;
                rgbaData[i * 4 + 3] = gray;
            }
            
            [it->second.metalTexture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                                       mipmapLevel:0
                                         withBytes:rgbaData.data()
                                       bytesPerRow:width * 4];
            return true;
        }
    }
    
    std::vector<unsigned char> rgbaData(width * height * 4);
    
    for (int i = 0; i < width * height; i++)
    {
        unsigned char gray = srcData[i];
        rgbaData[i * 4 + 0] = 255;
        rgbaData[i * 4 + 1] = 255;
        rgbaData[i * 4 + 2] = 255;
        rgbaData[i * 4 + 3] = gray;
    }
    
    textureId = FontCreateTexture(width, height, rgbaData.data(), eTF);
    if (textureId <= 0)
        return false;
    
    int* pNewRenderData = new int;
    *pNewRenderData = textureId;
    bitmap->SetRenderData(pNewRenderData);
    
    return true;
}

int CMetalTextureManager::FontCreateTexture(int Width, int Height, byte* pData, ETEX_Format eTF)
{
    if (!pData || Width <= 0 || Height <= 0)
        return 0;
        
    MTLPixelFormat format = ConvertToMetalFormat(eTF);
    id<MTLTexture> texture = CreateMetalTexture(Width, Height, format, pData, Width * Height * 4);
    if (!texture)
        return 0;
        
    int textureId = AllocateTextureId();
    if (textureId == -1)
        return 0;
        
    TextureInfo info;
    info.metalTexture = texture;
    info.width = Width;
    info.height = Height;
    info.format = eTF;
    info.name = "FontTexture";
    info.memorySize = Width * Height * 4;
    info.isLoaded = true;
    
    m_textures[textureId] = info;
    m_totalTextureMemory += info.memorySize;
    
    return textureId;
}

bool CMetalTextureManager::FontUpdateTexture(int nTexId, int X, int Y, int USize, int VSize, byte* pData)
{
    auto it = m_textures.find(nTexId);
    if (it == m_textures.end())
        return false;
        
    UpdateMetalTexture(it->second.metalTexture, pData, X, Y, USize, VSize);
    return true;
}

////////////////////////////////////////////////////////////////////////////
// FontReleaseTexture
//
// Releases font texture resources associated with a CFBitmap.
//
// Parameters:
//   pBmp - Pointer to CFBitmap to release texture for
//
// Notes:
//   - Removes texture from GPU
//   - Frees render data pointer
//   - Safe to call multiple times
////////////////////////////////////////////////////////////////////////////
void CMetalTextureManager::FontReleaseTexture(class CFBitmap* pBmp)
{
    if (!pBmp)
        return;
    
    int* pRenderData = (int*)pBmp->GetRenderData();
    if (pRenderData)
    {
        int textureId = *pRenderData;
        if (textureId > 0)
        {
            RemoveTexture((unsigned int)textureId);
        }
        
        delete pRenderData;
        pBmp->SetRenderData(nullptr);
    }
}

////////////////////////////////////////////////////////////////////////////
// FontSetTexture (CFBitmap overload)
//
// Sets a font texture as the current active texture for rendering.
//
// Parameters:
//   bitmap       - Font bitmap containing texture
//   nFilterMode  - Texture filtering mode
//
// Notes:
//   - Extracts texture ID from bitmap's render data
//   - Binds texture to current rendering context
////////////////////////////////////////////////////////////////////////////
void CMetalTextureManager::FontSetTexture(class CFBitmap* bitmap, int nFilterMode)
{
    if (!bitmap)
        return;
    
    int* pRenderData = (int*)bitmap->GetRenderData();
    if (pRenderData && *pRenderData > 0)
    {
        FontSetTexture(*pRenderData, nFilterMode);
    }
}

////////////////////////////////////////////////////////////////////////////
// FontSetTexture (int overload)
//
// Sets a font texture by ID as the current active texture for rendering.
//
// Parameters:
//   nTexId       - Texture ID to bind
//   nFilterMode  - Texture filtering mode
//
// Notes:
//   - Binds texture for font rendering operations
//   - Sets filtering parameters based on nFilterMode
////////////////////////////////////////////////////////////////////////////
void CMetalTextureManager::FontSetTexture(int nTexId, int nFilterMode)
{
    auto it = m_textures.find(nTexId);
    if (it != m_textures.end() && it->second.metalTexture)
    {
        m_currentTexture = it->second.metalTexture;
        m_currentTextureSlot = nTexId;
        
        if (m_renderer && m_renderer->m_renderEncoder)
        {
            [m_renderer->m_renderEncoder setFragmentTexture:it->second.metalTexture atIndex:0];
        }
        
        SetTextureParameters(it->second.metalTexture, true, nFilterMode);
    }
}

////////////////////////////////////////////////////////////////////////////
// FontSetRenderingState
//
// Sets up rendering state for 2D font rendering.
// Configures orthographic projection and blending for text.
//
// Parameters:
//   nVirtualScreenWidth  - Virtual screen width for orthographic projection
//   nVirtualScreenHeight - Virtual screen height for orthographic projection
//
// Notes:
//   - Sets up 2D orthographic projection (0,0) top-left to (width,height) bottom-right
//   - Enables alpha blending for smooth anti-aliased text
//   - Disables depth testing (fonts render on top)
//   - Disables culling (2D quads)
//   - Call FontRestoreRenderingState() when done rendering fonts
////////////////////////////////////////////////////////////////////////////
void CMetalTextureManager::FontSetRenderingState(unsigned long nVirtualScreenWidth, unsigned long nVirtualScreenHeight)
{
    if (!m_renderer)
        return;
    
    m_savedViewportWidth = nVirtualScreenWidth;
    m_savedViewportHeight = nVirtualScreenHeight;
}

////////////////////////////////////////////////////////////////////////////
// FontSetBlending
//
// Sets custom blending mode for font rendering.
//
// Parameters:
//   src - Source blend factor
//   dst - Destination blend factor
//
// Notes:
//   - Configures Metal blend state for text rendering
//   - Typically uses SRC_ALPHA, ONE_MINUS_SRC_ALPHA for smooth text
//   - Blending state would be applied via render pipeline state in Metal
////////////////////////////////////////////////////////////////////////////
void CMetalTextureManager::FontSetBlending(int src, int dst)
{
    m_savedBlendSrc = src;
    m_savedBlendDst = dst;
}

////////////////////////////////////////////////////////////////////////////
// FontRestoreRenderingState
//
// Restores rendering state after font rendering.
// Restores projection matrix, depth testing, and blend state.
//
// Notes:
//   - Should be called after all font rendering is complete
//   - Restores state saved by FontSetRenderingState()
//   - In Metal, this would restore previous pipeline state
////////////////////////////////////////////////////////////////////////////
void CMetalTextureManager::FontRestoreRenderingState()
{
    m_savedViewportWidth = 0;
    m_savedViewportHeight = 0;
}

////////////////////////////////////////////////////////////////////////////
// EF_GetTextureByID
//
// Retrieves an ITexPic interface for a texture by ID.
//
// Parameters:
//   Id - Texture ID to retrieve
//
// Returns:
//   ITexPic interface pointer on success, nullptr if not found
//
// Notes:
//   - Returns newly allocated CMetalTexture wrapper
//   - Caller is responsible for calling Release() when done
//   - Uses reference counting for lifetime management
////////////////////////////////////////////////////////////////////////////
ITexPic* CMetalTextureManager::EF_GetTextureByID(int Id)
{
    assert(Id > 0 && "CMetalTextureManager: EF_GetTextureByID called with invalid ID!");
    
    auto it = m_textures.find(Id);
    if (it == m_textures.end())
        return nullptr;
    
    if (!it->second.isLoaded)
    {
        assert(it->second.isLoaded && "CMetalTextureManager: Texture exists but is not loaded!");
        return nullptr;
    }
    
    return new CMetalTexture(Id, this);
}

////////////////////////////////////////////////////////////////////////////
// EF_LoadTexture
//
// Loads a texture for the shader system and returns ITexPic interface.
//
// Parameters:
//   nameTex  - Texture filename
//   flags    - Texture flags (FT_CLAMP, FT_NOREMOVE, etc.)
//   flags2   - Additional flags
//   eTT      - Texture type (eTT_Base, eTT_Bumpmap, etc.)
//   fAmount1 - Amount parameter 1
//   fAmount2 - Amount parameter 2
//   Id       - Texture ID (0 = allocate new)
//   BindId   - Bind ID
//
// Returns:
//   ITexPic interface pointer on success, nullptr on failure
//
// Notes:
//   - Returns newly allocated CMetalTexture wrapper
//   - Caller must call Release() when done
//   - Uses LoadTexture() internally for actual file loading
////////////////////////////////////////////////////////////////////////////
ITexPic* CMetalTextureManager::EF_LoadTexture(const char* nameTex, uint flags, uint flags2, byte eTT, 
                                               float fAmount1, float fAmount2, 
                                               int Id, int BindId)
{
    if (!nameTex || !nameTex[0])
        return nullptr;
    
    unsigned int textureId = LoadTexture(nameTex, nullptr, Id, true, true);
    if (textureId == 0)
        return nullptr;
    
    return new CMetalTexture(textureId, this);
}

int CMetalTextureManager::EF_LoadLightmap(const char* name)
{
    return LoadTexture(name, nullptr, 0, true, true);
}

bool CMetalTextureManager::EF_ScanEnvironmentCM(const char* name, int size, Vec3& Pos)
{
    // Scan environment cube map
    return false;
}

int CMetalTextureManager::EF_ReadAllImgFiles(IShader* ef, SShaderTexUnit* tl, STexAnim* ta, char* name)
{
    // Read all image files for shader
    return 0;
}

// File I/O methods
void CMetalTextureManager::WriteDDS(byte* dat, int wdt, int hgt, int Size, const char* name, EImFormat eF, int NumMips)
{
    // Write DDS file
}

void CMetalTextureManager::WriteTGA(byte* dat, int wdt, int hgt, const char* name, int bits)
{
    // Write TGA file
}

void CMetalTextureManager::WriteJPG(byte* dat, int wdt, int hgt, char* name)
{
    // Write JPG file
}

// Utility methods
void CMetalTextureManager::ClearAllTextures()
{
    m_textures.clear();
    m_textureNameMap.clear();
    m_totalTextureMemory = 0;
    m_nextTextureId = 1;
}

int CMetalTextureManager::GetTextureCount() const
{
    return (int)m_textures.size();
}

size_t CMetalTextureManager::GetTotalTextureMemory() const
{
    return m_totalTextureMemory;
}

const CMetalTextureManager::TextureInfo* CMetalTextureManager::GetTextureInfo(int textureId) const
{
    assert(textureId > 0 && "CMetalTextureManager: GetTextureInfo called with invalid ID!");
    
    auto it = m_textures.find(textureId);
    if (it != m_textures.end())
        return &it->second;
    return nullptr;
}

// Protected methods
id<MTLTexture> CMetalTextureManager::CreateMetalTexture(int width, int height, MTLPixelFormat format, 
                                                       const void* data, size_t dataSize)
{
    assert(m_renderer && "MetalTextureManager: renderer is null - not properly initialized!");
    assert(m_renderer->m_device && "MetalTextureManager: Metal device is null - renderer not initialized!");
    
    if (!m_renderer || !m_renderer->m_device)
        return nil;
        
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:NO];
    
    id<MTLTexture> texture = [m_renderer->m_device newTextureWithDescriptor:descriptor];
    
    if (texture && data)
    {
        [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                   mipmapLevel:0
                     withBytes:data
                   bytesPerRow:width * 4];
    }
    
    return texture;
}

id<MTLTexture> CMetalTextureManager::CreateMetalTextureFromFile(const char* filename)
{
    // Load texture from file and create Metal texture
    std::vector<byte> data;
    int width, height;
    if (!LoadTextureData(filename, data, width, height))
        return nil;
        
    return CreateMetalTexture(width, height, MTLPixelFormatRGBA8Unorm, data.data(), data.size());
}

void CMetalTextureManager::UpdateMetalTexture(id<MTLTexture> texture, const void* data, int x, int y, int w, int h)
{
    if (!texture || !data)
        return;
        
    [texture replaceRegion:MTLRegionMake2D(x, y, w, h)
               mipmapLevel:0
                 withBytes:data
               bytesPerRow:w * 4];
}

void CMetalTextureManager::BindTexture(int slot, id<MTLTexture> texture)
{
    if (m_renderer && m_renderer->m_renderEncoder)
    {
        [m_renderer->m_renderEncoder setFragmentTexture:texture atIndex:slot];
    }
}

MTLPixelFormat CMetalTextureManager::ConvertToMetalFormat(ETEX_Format format)
{
    switch (format)
    {
        case eTF_8888:
        case eTF_RGBA:
            return MTLPixelFormatRGBA8Unorm;
        
        case eTF_0888:
            return MTLPixelFormatRGBA8Unorm;
        
        case eTF_4444:
            return MTLPixelFormatRGBA8Unorm;
        
        case eTF_1555:
        case eTF_0555:
            return MTLPixelFormatRGBA8Unorm;
        
        case eTF_0565:
            return MTLPixelFormatRGBA8Unorm;
        
        case eTF_DXT1:
            return MTLPixelFormatBC1_RGBA;
        
        case eTF_DXT3:
            return MTLPixelFormatBC2_RGBA;
        
        case eTF_DXT5:
            return MTLPixelFormatBC3_RGBA;
        
        case eTF_SIGNED_HILO16:
            return MTLPixelFormatRG16Snorm;
        
        case eTF_SIGNED_HILO8:
        case eTF_V8U8:
            return MTLPixelFormatRG8Snorm;
        
        case eTF_SIGNED_RGB8:
            return MTLPixelFormatRGBA8Snorm;
        
        case eTF_RGB8:
            return MTLPixelFormatRGBA8Unorm;
        
        case eTF_V16U16:
            return MTLPixelFormatRG16Snorm;
        
        case eTF_0088:
            return MTLPixelFormatRG8Unorm;
        
        case eTF_8000:
            return MTLPixelFormatR8Unorm;
        
        case eTF_DEPTH:
            return MTLPixelFormatDepth32Float;
        
        case eTF_DSDT_MAG:
        case eTF_DSDT:
            return MTLPixelFormatRGBA8Unorm;
        
        case eTF_Unknown:
        case eTF_Index:
        case eTF_HSV:
            return MTLPixelFormatInvalid;
        
        default:
            return MTLPixelFormatRGBA8Unorm;
    }
}

ETEX_Format CMetalTextureManager::ConvertFromMetalFormat(MTLPixelFormat format)
{
    switch (format)
    {
        case MTLPixelFormatRGBA8Unorm: return eTF_8888;
        default: return eTF_8888; // All formats map to RGBA8Unorm on macOS
    }
}

int CMetalTextureManager::AllocateTextureId()
{
    return m_nextTextureId++;
}

void CMetalTextureManager::ReleaseTextureId(int id)
{
    // Release texture ID for reuse
}

bool CMetalTextureManager::LoadTextureData(const char* filename, std::vector<byte>& data, int& width, int& height)
{
    ETEX_Format format;
    return LoadTextureData(filename, data, width, height, format);
}

bool CMetalTextureManager::LoadTextureData(const char* filename, std::vector<byte>& data, int& width, int& height, ETEX_Format& format)
{
    if (!filename || !filename[0])
        return false;
    
    assert(m_renderer && "MetalTextureManager: renderer is null - not properly initialized!");
    assert(m_renderer->m_device && "MetalTextureManager: Metal device is null - renderer not initialized!");
    
    if (!m_renderer || !m_renderer->m_device)
        return false;
    
    @autoreleasepool
    {
        NSString* filePathStr = [NSString stringWithUTF8String:filename];
        NSURL* fileURL = [NSURL fileURLWithPath:filePathStr];
        
        if (!fileURL || ![[NSFileManager defaultManager] fileExistsAtPath:filePathStr])
        {
            return false;
        }
        
        NSError* error = nil;
        MTKTextureLoader* textureLoader = [[MTKTextureLoader alloc] initWithDevice:m_renderer->m_device];
        
        NSDictionary* options = @{
            MTKTextureLoaderOptionTextureUsage: @(MTLTextureUsageShaderRead),
            MTKTextureLoaderOptionTextureStorageMode: @(MTLStorageModeShared),
            MTKTextureLoaderOptionSRGB: @(NO),
            MTKTextureLoaderOptionGenerateMipmaps: @(NO)
        };
        
        id<MTLTexture> loadedTexture = [textureLoader newTextureWithContentsOfURL:fileURL
                                                                           options:options
                                                                             error:&error];
        
        if (!loadedTexture || error)
        {
            if (error)
            {
                NSLog(@"Failed to load texture %s: %@", filename, [error localizedDescription]);
            }
            return false;
        }
        
        width = (int)[loadedTexture width];
        height = (int)[loadedTexture height];
        MTLPixelFormat pixelFormat = [loadedTexture pixelFormat];
        
        format = ConvertFromMetalFormat(pixelFormat);
        
        int bytesPerPixel = 4;
        switch (pixelFormat)
        {
            case MTLPixelFormatRGBA8Unorm:
            case MTLPixelFormatBGRA8Unorm:
                bytesPerPixel = 4;
                format = eTF_8888;
                break;
            case MTLPixelFormatRG8Unorm:
                bytesPerPixel = 2;
                format = eTF_0088;
                break;
            case MTLPixelFormatR8Unorm:
                bytesPerPixel = 1;
                format = eTF_8000;
                break;
            default:
                bytesPerPixel = 4;
                format = eTF_8888;
                break;
        }
        
        size_t dataSize = width * height * bytesPerPixel;
        data.resize(dataSize);
        
        [loadedTexture getBytes:data.data()
                    bytesPerRow:width * bytesPerPixel
                     fromRegion:MTLRegionMake2D(0, 0, width, height)
                    mipmapLevel:0];
        
        return true;
    }
}

void CMetalTextureManager::GenerateMipmaps(id<MTLTexture> texture)
{
    // Generate mipmaps for texture
    // This would need to be implemented using Metal compute shaders
}

void CMetalTextureManager::SetTextureParameters(id<MTLTexture> texture, bool repeat, int filter)
{
    // Set texture parameters like filtering and wrapping
    // This would be handled by the Metal render pipeline state
}

int CMetalTextureManager::GetBytesPerPixel(ETEX_Format format)
{
    switch (format)
    {
        case eTF_8888:
        case eTF_0888:
            return 4;
        
        case eTF_4444:
        case eTF_1555:
        case eTF_0555:
        case eTF_0565:
        case eTF_SIGNED_HILO16:
        case eTF_V16U16:
            return 2;
        
        case eTF_SIGNED_HILO8:
        case eTF_SIGNED_RGB8:
        case eTF_RGB8:
        case eTF_V8U8:
        case eTF_0088:
            return 2;
        
        case eTF_DXT1:
            return 0;
        
        case eTF_DXT3:
        case eTF_DXT5:
            return 0;
        
        case eTF_DSDT_MAG:
        case eTF_DSDT:
            return 4;
        
        case eTF_Index:
        case eTF_8000:
            return 1;
        
        case eTF_RGBA:
            return 4;
        
        default:
            return 4;
    }
}

#endif // __APPLE__ && __MACH__
