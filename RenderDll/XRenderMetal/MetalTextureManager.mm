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

#include "MetalTextureManager.m"
#include "../../CryFont/FBitmap.h"
#include "I3DEngine.h"
#include "ISystem.h"
#include "MetalBaseRenderer.m"
#include "../Common/Textures/Image/CImage.h"
#include <Cocoa/Cocoa.h>
#include <cmath>
#include <cstring>
#include <algorithm>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Forward declarations and external functions
class CCamera;
extern ISystem *iSystem;

// Simple implementation of StripExtension for Metal renderer
static void StripExtension(const char *in, char *out)
{
    if (!in || !out)
        return;
    
    strcpy(out, in);
    char *dot = strrchr(out, '.');
    if (dot && dot > out)
    {
        *dot = 0;
    }
}

////////////////////////////////////////////////////////////////////////////
// CMetalTexture - ITexPic implementation for Metal textures
////////////////////////////////////////////////////////////////////////////

CMetalTexture::CMetalTexture(int texId, CMetalTextureManager* manager)
    : m_textureId(texId)
    , m_manager(manager)
    , m_refCount(1)
{
    assert(manager && "CMetalTexture: Cannot create with null manager!");
    
    if (texId <= 0)
    {
        iLog->Log("ERROR: CMetalTexture constructed with invalid texture ID: %d\n", texId);
        iLog->Log("Stack trace: manager=%p\n", manager);
        assert(false && "CMetalTexture: Cannot create with invalid texture ID!");
        throw std::runtime_error("CMetalTexture: texture ID must be > 0!");
    }
    
    if (!manager)
    {
        iLog->Log("ERROR: CMetalTexture constructed with null manager!\n");
        assert(false && "CMetalTexture: Cannot create with null manager!");
        throw std::runtime_error("CMetalTexture: manager cannot be null!");
    }
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
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    assert(info && "CMetalTexture: texture info not found - texture may have been deleted!");
    
    return info ? info->name.c_str() : "";
}

int CMetalTexture::GetWidth()
{
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    assert(info && "CMetalTexture: texture info not found - texture may have been deleted!");
    
    return info ? info->width : 0;
}

int CMetalTexture::GetHeight()
{
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
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    return info ? info->flags : 0;
}

int CMetalTexture::GetFlags2()
{
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    return info ? info->flags2 : 0;
}

void CMetalTexture::SetClamp(bool bEnable)
{
    m_manager->SetTextureClamp(m_textureId, bEnable);
}

bool CMetalTexture::IsTextureLoaded()
{
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    return info ? info->isLoaded : false;
}

void CMetalTexture::PrecacheAsynchronously(float fDist, int Flags)
{
}

void CMetalTexture::Preload(int Flags)
{
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    if (!info || info->isLoaded)
        return;
}

byte* CMetalTexture::GetData32()
{
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
    const CMetalTextureManager::TextureInfo* info = m_manager->GetTextureInfo(m_textureId);
    if (!info || !info->metalTexture)
        return false;
    
    m_manager->SetTextureFilter(m_textureId, nFilter);
    
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
    assert(tnum >= 0 && "SetTexture: texture number cannot be negative!");
    
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
    assert(m_renderer && "SetWhiteTexture: renderer is null!");
    
    if (!m_whiteTexture)
    {
        m_whiteTexture = CreateMetalTexture(1, 1, MTLPixelFormatRGBA8Unorm);
        assert(m_whiteTexture && "SetWhiteTexture: failed to create white texture!");
        
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
        m_renderer->TrackCommandBuffer(commandBuffer);
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
    info.flags = 0;
    info.flags2 = 0;
    info.textureType = eTT_Base;
    info.amount1 = -1.0f;
    info.amount2 = -1.0f;
    info.clampU = !repeat;
    info.clampV = !repeat;
    info.filterMode = filter;
    
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
    assert(newdata && "UpdateTextureInVideoMemory: newdata cannot be null!");
    assert(w > 0 && h > 0 && "UpdateTextureInVideoMemory: width and height must be positive!");
    assert(posx >= 0 && posy >= 0 && "UpdateTextureInVideoMemory: position cannot be negative!");
    
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
            iLog->Log("Warning: Failed to load texture: %s\n", filename);
        }
        return def_tid;
    }
    
    if (width <= 0 || height <= 0 || data.empty())
    {
        if (bWarn)
            iLog->Log("Warning: Invalid texture dimensions for: %s\n", filename);
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
            iLog->Log("Warning: Failed to create Metal texture for: %s\n", filename);
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
        m_renderer->TrackCommandBuffer(commandBuffer);
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
    info.flags = 0;
    info.flags2 = 0;
    info.textureType = eTT_Base;
    info.amount1 = -1.0f;
    info.amount2 = -1.0f;
    info.clampU = false;
    info.clampV = false;
    info.filterMode = FILTER_BILINEAR;
    
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
            m_renderer->TrackCommandBuffer(commandBuffer);
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
                    
                    callback(mipData.data(), mipLevel, (DWORD)dataSize, w, h, nullptr);
                }
            }
        }
        
        return true;
    }
    
    iLog->Log("Warning: Software DXT compression not implemented. ");
    iLog->Log("Consider using pre-compressed textures or enable hardware compression (bUseHW=true).\n");
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
    
    // Convert ETEX_Format to Metal pixel format
    MTLPixelFormat compressedFormat;
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
            // Unsupported format
            return false;
    }
    
    // Calculate compressed data size using helper
    int blockSize = GetDXTBlockSize(eSrcTF);
    int DXTSize = ((nWidth + 3) / 4) * ((nHeight + 3) / 4) * blockSize;
    
    MTLTextureDescriptor* compressedDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:compressedFormat
                                                                                               width:nWidth
                                                                                              height:nHeight
                                                                                           mipmapped:NO];
    compressedDesc.usage = MTLTextureUsageShaderRead;
    compressedDesc.storageMode = MTLStorageModeShared;
    
    id<MTLTexture> compressedTexture = [m_renderer->m_device newTextureWithDescriptor:compressedDesc];
    if (!compressedTexture)
    {
        assert(false && "Failed to create compressed texture!");
        return false;
    }
    
    // Upload compressed data to texture (with error handling)
    @try
    {
        [compressedTexture replaceRegion:MTLRegionMake2D(0, 0, nWidth, nHeight)
                             mipmapLevel:0
                               withBytes:srcData
                             bytesPerRow:((nWidth + 3) / 4) * blockSize];
    }
    @catch (NSException *exception)
    {
        assert(false && "Failed to upload compressed texture data!");
        return false;
    }
    
    MTLTextureDescriptor* uncompressedDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                                 width:nWidth
                                                                                                height:nHeight
                                                                                             mipmapped:NO];
    uncompressedDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    uncompressedDesc.storageMode = MTLStorageModeShared;
    
    id<MTLTexture> uncompressedTexture = [m_renderer->m_device newTextureWithDescriptor:uncompressedDesc];
    if (!uncompressedTexture)
    {
        assert(false && "Failed to create uncompressed texture!");
        return false;
    }
    
    // Decompress using Metal blit encoder (hardware-accelerated)
    if (!m_renderer->m_commandQueue)
    {
        assert(false && "Command queue is null!");
        return false;
    }
    
    @try
    {
        id<MTLCommandBuffer> commandBuffer = [m_renderer->m_commandQueue commandBuffer];
        if (!commandBuffer)
        {
            assert(false && "Failed to create command buffer!");
            return false;
        }
        
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        if (!blitEncoder)
        {
            assert(false && "Failed to create blit encoder!");
            return false;
        }
        
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
        m_renderer->TrackCommandBuffer(commandBuffer);
        
        // Note: Synchronous wait - consider using batch API for multiple decompressions
        [commandBuffer waitUntilCompleted];
    }
    @catch (NSException *exception)
    {
        assert(false && "Metal decompression failed!");
        return false;
    }
    
    // Read back decompressed data from GPU
    std::vector<byte> rgbaData(nWidth * nHeight * 4);
    
    @try
    {
        [uncompressedTexture getBytes:rgbaData.data()
                          bytesPerRow:nWidth * 4
                           fromRegion:MTLRegionMake2D(0, 0, nWidth, nHeight)
                          mipmapLevel:0];
    }
    @catch (NSException *exception)
    {
        assert(false && "Failed to read back texture data!");
        return false;
    }
    
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
// BeginDXTDecompressionBatch
//
// Begins a batch of DXT decompression operations.
// Queued decompressions will be executed together to reduce GPU sync overhead.
//
// Notes:
//   - Use QueueDXTDecompression() to add jobs to the batch
//   - Call ExecuteDXTDecompressionBatch() to process all queued jobs
//   - Batch processing is more efficient than individual DXTDecompress() calls
////////////////////////////////////////////////////////////////////////////
void CMetalTextureManager::BeginDXTDecompressionBatch()
{
    m_decompressJobs.clear();
}

////////////////////////////////////////////////////////////////////////////
// QueueDXTDecompression
//
// Queues a DXT decompression job for batch processing.
//
// Parameters:
//   job - DXTDecompressJob structure containing decompression parameters
//
// Notes:
//   - Call BeginDXTDecompressionBatch() first
//   - Call ExecuteDXTDecompressionBatch() to process all queued jobs
//   - Jobs are NOT executed immediately
////////////////////////////////////////////////////////////////////////////
void CMetalTextureManager::QueueDXTDecompression(const DXTDecompressJob& job)
{
    assert(job.srcData && "QueueDXTDecompression: srcData cannot be null!");
    assert(job.dstData && "QueueDXTDecompression: dstData cannot be null!");
    assert(job.width > 0 && job.height > 0 && "QueueDXTDecompression: dimensions must be positive!");
    assert(job.dstBytesPerPix == 3 || job.dstBytesPerPix == 4 && "QueueDXTDecompression: dstBytesPerPix must be 3 or 4!");
    
    m_decompressJobs.push_back(job);
}

////////////////////////////////////////////////////////////////////////////
// ExecuteDXTDecompressionBatch
//
// Executes all queued DXT decompression jobs in a single batch.
// More efficient than individual DXTDecompress() calls due to reduced GPU sync.
//
// Returns:
//   true if all jobs succeeded, false if any job failed
//
// Notes:
//   - Processes all jobs queued via QueueDXTDecompression()
//   - Uses single command buffer for all decompressions
//   - Only one GPU sync at the end (vs. N syncs for individual calls)
//   - Clears job queue when complete
//   - For best performance, batch as many decompressions as possible
////////////////////////////////////////////////////////////////////////////
bool CMetalTextureManager::ExecuteDXTDecompressionBatch()
{
    if (m_decompressJobs.empty())
        return true;
    
    assert(m_renderer && "MetalTextureManager: renderer is null!");
    assert(m_renderer->m_device && "MetalTextureManager: Metal device is null!");
    assert(m_renderer->m_commandQueue && "MetalTextureManager: command queue is null!");
    
    if (!m_renderer || !m_renderer->m_device || !m_renderer->m_commandQueue)
        return false;
    
    id<MTLCommandBuffer> commandBuffer = [m_renderer->m_commandQueue commandBuffer];
    if (!commandBuffer)
    {
        assert(false && "ExecuteDXTDecompressionBatch: failed to create command buffer!");
        return false;
    }
    
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    if (!blitEncoder)
    {
        assert(false && "ExecuteDXTDecompressionBatch: failed to create blit encoder!");
        return false;
    }
    
    bool success = true;
    std::vector<std::pair<id<MTLTexture>, std::vector<byte>*>> readbackOperations;
    
    for (const auto& job : m_decompressJobs)
    {
        MTLPixelFormat compressedFormat;
        switch (job.format)
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
                success = false;
                continue;
        }
        
        int blockSize = GetDXTBlockSize(job.format);
        
        MTLTextureDescriptor* compressedDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:compressedFormat
                                                                                                   width:job.width
                                                                                                  height:job.height
                                                                                               mipmapped:NO];
        compressedDesc.usage = MTLTextureUsageShaderRead;
        compressedDesc.storageMode = MTLStorageModeShared;
        
        id<MTLTexture> compressedTexture = [m_renderer->m_device newTextureWithDescriptor:compressedDesc];
        if (!compressedTexture)
        {
            assert(false && "ExecuteDXTDecompressionBatch: failed to create compressed texture!");
            success = false;
            continue;
        }
        
        @try
        {
            [compressedTexture replaceRegion:MTLRegionMake2D(0, 0, job.width, job.height)
                                 mipmapLevel:0
                                   withBytes:job.srcData
                                 bytesPerRow:((job.width + 3) / 4) * blockSize];
        }
        @catch (NSException *exception)
        {
            assert(false && "ExecuteDXTDecompressionBatch: failed to upload compressed data!");
            success = false;
            continue;
        }
        
        MTLTextureDescriptor* uncompressedDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                                     width:job.width
                                                                                                    height:job.height
                                                                                                 mipmapped:NO];
        uncompressedDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
        uncompressedDesc.storageMode = MTLStorageModeShared;
        
        id<MTLTexture> uncompressedTexture = [m_renderer->m_device newTextureWithDescriptor:uncompressedDesc];
        if (!uncompressedTexture)
        {
            assert(false && "ExecuteDXTDecompressionBatch: failed to create uncompressed texture!");
            success = false;
            continue;
        }
        
        [blitEncoder copyFromTexture:compressedTexture
                         sourceSlice:0
                         sourceLevel:0
                        sourceOrigin:MTLOriginMake(0, 0, 0)
                          sourceSize:MTLSizeMake(job.width, job.height, 1)
                           toTexture:uncompressedTexture
                    destinationSlice:0
                    destinationLevel:0
                   destinationOrigin:MTLOriginMake(0, 0, 0)];
        
        std::vector<byte>* rgbaData = new std::vector<byte>(job.width * job.height * 4);
        readbackOperations.push_back({uncompressedTexture, rgbaData});
    }
    
    [blitEncoder endEncoding];
    [commandBuffer commit];
    m_renderer->TrackCommandBuffer(commandBuffer);
    [commandBuffer waitUntilCompleted];
    
    size_t jobIdx = 0;
    for (const auto& readback : readbackOperations)
    {
        if (jobIdx >= m_decompressJobs.size())
            break;
            
        const auto& job = m_decompressJobs[jobIdx++];
        
        @try
        {
            [readback.first getBytes:readback.second->data()
                         bytesPerRow:job.width * 4
                          fromRegion:MTLRegionMake2D(0, 0, job.width, job.height)
                         mipmapLevel:0];
            
            if (job.dstBytesPerPix == 3)
            {
                for (int i = 0; i < job.width * job.height; i++)
                {
                    job.dstData[i * 3 + 0] = (*readback.second)[i * 4 + 0];
                    job.dstData[i * 3 + 1] = (*readback.second)[i * 4 + 1];
                    job.dstData[i * 3 + 2] = (*readback.second)[i * 4 + 2];
                }
            }
            else
            {
                memcpy(job.dstData, readback.second->data(), job.width * job.height * 4);
            }
        }
        @catch (NSException *exception)
        {
            assert(false && "ExecuteDXTDecompressionBatch: failed to read back texture data!");
            success = false;
        }
        
        delete readback.second;
    }
    
    m_decompressJobs.clear();
    
    return success;
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
    assert(TextureId > 0 && "RemoveTexture: invalid texture ID!");
    
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
    assert(pTexPic && "RemoveTexture: pTexPic cannot be null!");
    
    if (!pTexPic)
        return;
    
    int textureId = pTexPic->GetTextureID();
    assert(textureId > 0 && "RemoveTexture: texture ID must be positive!");
    
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
        iLog->Log("Warning: Gamma value %.2f out of reasonable range (0.1 to 5.0), clamping.\n", totalGamma);
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
        iLog->Log("Gamma delta set to %.2f (total gamma: %.2f)\n", m_gammaValue, totalGamma);
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
    assert(pData && "FontCreateTexture: pData cannot be null!");
    assert(Width > 0 && Height > 0 && "FontCreateTexture: dimensions must be positive!");
    
    if (!pData || Width <= 0 || Height <= 0)
        return 0;
        
    MTLPixelFormat format = ConvertToMetalFormat(eTF);
    id<MTLTexture> texture = CreateMetalTexture(Width, Height, format, pData, Width * Height * 4);
    if (!texture)
        return 0;
        
    int textureId = AllocateTextureId();
    assert(textureId > 0 && "FontCreateTexture: failed to allocate texture ID!");
    
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
    info.flags = FT_FONT;
    info.flags2 = 0;
    info.textureType = eTT_Base;
    info.amount1 = -1.0f;
    info.amount2 = -1.0f;
    info.clampU = true;
    info.clampV = true;
    info.filterMode = FILTER_LINEAR;
    
    m_textures[textureId] = info;
    m_totalTextureMemory += info.memorySize;
    
    return textureId;
}

bool CMetalTextureManager::FontUpdateTexture(int nTexId, int X, int Y, int USize, int VSize, byte* pData)
{
    assert(nTexId > 0 && "FontUpdateTexture: invalid texture ID!");
    assert(pData && "FontUpdateTexture: pData cannot be null!");
    assert(USize > 0 && VSize > 0 && "FontUpdateTexture: update size must be positive!");
    assert(X >= 0 && Y >= 0 && "FontUpdateTexture: position cannot be negative!");
    
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
    assert(pBmp && "FontReleaseTexture: pBmp cannot be null!");
    
    if (!pBmp)
        return;
    
    int* pRenderData = (int*)pBmp->GetRenderData();
    if (pRenderData)
    {
        int textureId = *pRenderData;
        assert(textureId > 0 && "FontReleaseTexture: invalid texture ID in render data!");
        
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
    assert(bitmap && "FontSetTexture: bitmap cannot be null!");
    
    if (!bitmap)
        return;
    
    int* pRenderData = (int*)bitmap->GetRenderData();
    if (pRenderData && *pRenderData > 0)
    {
        assert(*pRenderData > 0 && "FontSetTexture: invalid texture ID in render data!");
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
    assert(nTexId > 0 && "FontSetTexture: invalid texture ID!");
    
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
    assert(m_renderer && "FontSetRenderingState: renderer is null!");
    assert(nVirtualScreenWidth > 0 && nVirtualScreenHeight > 0 && "FontSetRenderingState: invalid screen dimensions!");
    
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
    if (Id <= 0)
    {
        iLog->Log("ERROR: EF_GetTextureByID called with invalid ID: %d\n", Id);
        assert(false && "CMetalTextureManager: EF_GetTextureByID called with invalid ID!");
        return nullptr;
    }
    
    auto it = m_textures.find(Id);
    if (it == m_textures.end())
    {
        iLog->Log("Warning: EF_GetTextureByID - texture ID %d not found in texture map\n", Id);
        return nullptr;
    }
    
    if (!it->second.isLoaded)
    {
        iLog->Log("Warning: EF_GetTextureByID - texture ID %d exists but is not loaded\n", Id);
        assert(it->second.isLoaded && "CMetalTextureManager: Texture exists but is not loaded!");
        return nullptr;
    }
    
    iLog->Log("EF_GetTextureByID: Creating CMetalTexture wrapper for ID %d\n", Id);
    return new CMetalTexture(Id, this);
}

////////////////////////////////////////////////////////////////////////////
// EF_LoadTexture
//
// Loads a texture for the shader system and returns ITexPic interface.
//
// Parameters:
//   nameTex  - Texture filename
//   flags    - Texture flags (FT_CLAMP, FT_NOREMOVE, FT_NOMIPS, etc.)
//   flags2   - Additional flags (FT2_RELOAD, FT2_NODXT, FT2_UCLAMP, FT2_VCLAMP, etc.)
//   eTT      - Texture type (eTT_Base, eTT_Bumpmap, eTT_Cubemap, etc.)
//   fAmount1 - Amount parameter 1 (for detail textures, blending)
//   fAmount2 - Amount parameter 2 (for decals, opacity)
//   Id       - Texture ID (0 = allocate new)
//   BindId   - Bind ID (shader texture slot) [Currently unused]
//
// Returns:
//   ITexPic interface pointer on success, nullptr on failure
//
// Notes:
//   - Returns newly allocated CMetalTexture wrapper with reference count = 1
//   - Caller must call Release() when done
//   - Stores flags, flags2, textureType, and amount parameters in TextureInfo
//   - Handles FT_CLAMP, FT_NOMIPS, FT_NOREMOVE, FT_HASNORMALMAP flags
//   - Handles FT2_NODXT, FT2_UCLAMP, FT2_VCLAMP flags
//   - Sets appropriate flags for bump maps (eTT_Bumpmap → FT_HASNORMALMAP)
////////////////////////////////////////////////////////////////////////////
ITexPic* CMetalTextureManager::EF_LoadTexture(const char* nameTex, uint flags, uint flags2, byte eTT, 
                                               float fAmount1, float fAmount2, 
                                               int Id, int BindId)
{
    assert(nameTex && "CMetalTextureManager: EF_LoadTexture called with null filename!");
    
    if (!nameTex || !nameTex[0])
        return nullptr;
    
    assert(m_renderer && "CMetalTextureManager: renderer is null!");
    assert(m_renderer->m_device && "CMetalTextureManager: Metal device is null!");
    
    if (!m_renderer || !m_renderer->m_device)
        return nullptr;
    
    bool bWarn = !(flags & FT_NOREMOVE);
    bool bCompress = !(flags2 & FT2_NODXT);
    
    unsigned int textureId = LoadTexture(nameTex, nullptr, Id, bCompress, bWarn);
    if (textureId == 0 || textureId == (unsigned int)-1)
    {
        iLog->Log("EF_LoadTexture: LoadTexture returned invalid ID %u for '%s'\n", textureId, nameTex);
        return nullptr;
    }
    
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
    
    CMetalTexture* pTexture = new CMetalTexture(textureId, this);
    assert(pTexture && "CMetalTextureManager: Failed to allocate CMetalTexture!");
    
    (void)BindId;
    
    return pTexture;
}

////////////////////////////////////////////////////////////////////////////
// EF_LoadLightmap
//
// Loads a lightmap texture for the shader system.
//
// Parameters:
//   name - Lightmap texture filename
//
// Returns:
//   Texture ID on success, 0 on failure
//
// Notes:
//   - Lightmaps are typically used for pre-baked lighting
//   - Uses standard LoadTexture() with default settings
////////////////////////////////////////////////////////////////////////////
int CMetalTextureManager::EF_LoadLightmap(const char* name)
{
    assert(name && "CMetalTextureManager: EF_LoadLightmap called with null name!");
    
    if (!name || !name[0])
        return 0;
    
    return LoadTexture(name, nullptr, 0, true, true);
}

////////////////////////////////////////////////////////////////////////////
// EF_ScanEnvironmentCM
//
// Scans environment for cube map creation by rendering 6 cube faces.
//
// Parameters:
//   name - Output filename base (will create name_posx.jpg, name_negx.jpg, etc.)
//   size - Cube map face size (e.g., 256, 512)
//   Pos  - World position to render from
//
// Returns:
//   true on success, false on failure
//
// Notes:
//   - Renders scene from 6 directions (+X, -X, +Y, -Y, +Z, -Z)
//   - Creates Metal cube texture as render target
//   - Saves each face as separate JPG file
//   - Used by Material Editor for environment map generation
//   - Requires full rendering pipeline integration
////////////////////////////////////////////////////////////////////////////
bool CMetalTextureManager::EF_ScanEnvironmentCM(const char* name, int size, Vec3& Pos)
{
    assert(name && "CMetalTextureManager: EF_ScanEnvironmentCM called with null name!");
    assert(size > 0 && "CMetalTextureManager: EF_ScanEnvironmentCM called with invalid size!");
    assert(m_renderer && "CMetalTextureManager: renderer is null!");
    
    if (!name || size <= 0 || !m_renderer || !m_renderer->m_device)
        return false;
    
    // Validate size is power of 2
    if ((size & (size - 1)) != 0)
        return false;
    
    // Get 3D engine once (fail early if not available)
    I3DEngine* pEngine = iSystem ? iSystem->GetI3DEngine() : nullptr;
    if (!pEngine)
        return false;
    
    // Create Metal cube texture for rendering
    MTLTextureDescriptor* desc = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                        size:size
                                                                                   mipmapped:NO];
    desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    desc.storageMode = MTLStorageModePrivate;
    
    id<MTLTexture> cubeTexture = [m_renderer->m_device newTextureWithDescriptor:desc];
    if (!cubeTexture)
        return false;
    
    // Cube face names for output files
    static const char* cubeFaceNames[6] = {"posx", "negx", "posy", "negy", "posz", "negz"};
    
    // Camera angles for each cube face (yaw, pitch, roll)
    static const float cubeAngles[6][3] = {
        {  90.0f, -90.0f,  0.0f },  // +X
        {  90.0f,  90.0f,  0.0f },  // -X
        { 180.0f, 180.0f,  0.0f },  // +Y
        {   0.0f, 180.0f,  0.0f },  // -Y
        {  90.0f, 180.0f,  0.0f },  // +Z
        {  90.0f,   0.0f,  0.0f }   // -Z
    };
    
    // Save current viewport
    int vX, vY, vWidth, vHeight;
    m_renderer->GetViewport(&vX, &vY, &vWidth, &vHeight);
    
    char szName[256];
    StripExtension(name, szName);
    
    bool success = true;
    
    // Create render pass descriptor for cube map rendering
    MTLRenderPassDescriptor* renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    assert(renderPassDesc && "Failed to create render pass descriptor!");
    if (!renderPassDesc)
    {
        success = false;
        return success;
    }
    
    // Create temporary texture for reading back data (cube textures in Private storage can't be read directly)
    MTLTextureDescriptor* readbackDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                             width:size
                                                                                            height:size
                                                                                         mipmapped:NO];
    assert(readbackDesc && "Failed to create texture descriptor!");
    
    readbackDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    readbackDesc.storageMode = MTLStorageModeShared;  // Shared so we can read from CPU
    
    id<MTLTexture> readbackTexture = [m_renderer->m_device newTextureWithDescriptor:readbackDesc];
    assert(readbackTexture && "Failed to create readback texture!");
    if (!readbackTexture)
        return false;
    
    // Save current camera state from BOTH renderer and engine
    CCamera savedCamera = m_renderer->GetCamera();
    
    // Create cube map camera (created once, updated per face)
    CCamera cubeCamera;
    cubeCamera.Init(size, size, 90.0f * M_PI / 180.0f, 1.0f, 10000.0f);
    cubeCamera.SetPos(Pos);
    
    // ============================================================
    // PHASE 1: Render all cube faces (GPU work)
    // ============================================================
    for (int faceIdx = 0; faceIdx < 6; faceIdx++)
    {
        assert(faceIdx >= 0 && faceIdx < 6 && "Invalid cube face index!");
        
        // Setup camera for this cube face
        cubeCamera.SetAngle(Vec3(cubeAngles[faceIdx][0], cubeAngles[faceIdx][1], cubeAngles[faceIdx][2]));
        cubeCamera.Update(size, size);
        
        // Set camera on both renderer and 3D engine
        m_renderer->SetCamera(cubeCamera);
        pEngine->SetCamera(cubeCamera, false);
        
        // Render this cube face
        if (!RenderCubeFace(pEngine, cubeTexture, faceIdx, renderPassDesc, size))
        {
            success = false;
            continue;
        }
    }
    
    // ============================================================
    // PHASE 2: Copy all cube faces to readback buffer (batched)
    // ============================================================
    id<MTLCommandBuffer> blitCommandBuffer = [m_renderer->m_commandQueue commandBuffer];
    assert(blitCommandBuffer && "Failed to create blit command buffer!");
    if (!blitCommandBuffer)
    {
        return false;
    }
    
    id<MTLBlitCommandEncoder> blitEncoder = [blitCommandBuffer blitCommandEncoder];
    assert(blitEncoder && "Failed to create blit encoder!");
    if (!blitEncoder)
    {
        return false;
    }
    
    // Batch all copy operations
    for (int faceIdx = 0; faceIdx < 6; faceIdx++)
    {
        [blitEncoder copyFromTexture:cubeTexture
                         sourceSlice:faceIdx
                         sourceLevel:0
                        sourceOrigin:MTLOriginMake(0, 0, 0)
                          sourceSize:MTLSizeMake(size, size, 1)
                           toTexture:readbackTexture
                    destinationSlice:0
                    destinationLevel:0
                   destinationOrigin:MTLOriginMake(0, 0, 0)];
    }
    
    [blitEncoder endEncoding];
    [blitCommandBuffer commit];
    m_renderer->TrackCommandBuffer(blitCommandBuffer);
    [blitCommandBuffer waitUntilCompleted];  // Single wait for all copies
    
    // ============================================================
    // PHASE 3: Read back and save all faces (CPU work)
    // ============================================================
    const int dataSize = size * size * 4;
    const NSUInteger bytesPerRow = size * 4;
    const MTLRegion region = MTLRegionMake2D(0, 0, size, size);
    
    // Use std::vector for automatic memory management
    std::vector<byte> pixelBuffer(dataSize);
    
    for (int faceIdx = 0; faceIdx < 6; faceIdx++)
    {
        // Note: We copy each face to the same readback texture sequentially
        // This could be optimized with 6 separate readback textures
        id<MTLCommandBuffer> copyBuffer = [m_renderer->m_commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> copyEncoder = [copyBuffer blitCommandEncoder];
        
        [copyEncoder copyFromTexture:cubeTexture
                         sourceSlice:faceIdx
                         sourceLevel:0
                        sourceOrigin:MTLOriginMake(0, 0, 0)
                          sourceSize:MTLSizeMake(size, size, 1)
                           toTexture:readbackTexture
                    destinationSlice:0
                    destinationLevel:0
                   destinationOrigin:MTLOriginMake(0, 0, 0)];
        
        [copyEncoder endEncoding];
        [copyBuffer commit];
        m_renderer->TrackCommandBuffer(copyBuffer);
        [copyBuffer waitUntilCompleted];
        
        // Read pixel data from GPU
        [readbackTexture getBytes:pixelBuffer.data()
                      bytesPerRow:bytesPerRow
                       fromRegion:region
                      mipmapLevel:0];
        
        // Save to JPG file
        char outputPath[512];
        snprintf(outputPath, sizeof(outputPath), "%s_%s.jpg", szName, cubeFaceNames[faceIdx]);
        
        if (!SaveTextureAsJPG(pixelBuffer.data(), size, size, outputPath))
        {
            success = false;
        }
    }
    
    // Restore viewport and camera (on BOTH renderer and engine)
    m_renderer->SetViewport(vX, vY, vWidth, vHeight);
    m_renderer->SetCamera(savedCamera);
    
    // CRITICAL: Restore engine camera too (was missing!)
    if (pEngine)
    {
        pEngine->SetCamera(savedCamera, false);
    }
    
    return success;
}

////////////////////////////////////////////////////////////////////////////
// RenderCubeFace
//
// Renders a single cube face using Metal and the engine's rendering pipeline.
//
// Parameters:
//   pEngine          - I3DEngine instance (with camera already set by caller)
//   cubeTexture      - Cube texture to render to
//   faceIdx          - Which face (0-5)
//   renderPassDesc   - Render pass descriptor
//   size             - Render target size
//
// Returns:
//   true on success, false on failure
//
// Prerequisites:
//   - Camera MUST be set by caller on pEngine (via pEngine->SetCamera())
//   - This is a pure RENDER method - no state management
//
// Responsibilities:
//   - Sets up Metal render pass for cube face
//   - Configures viewport/scissor
//   - Calls pEngine->DrawLowDetail() to render scene
//   - Does NOT touch camera, viewport state is local to render pass
////////////////////////////////////////////////////////////////////////////
bool CMetalTextureManager::RenderCubeFace(I3DEngine* pEngine,
                                           id<MTLTexture> cubeTexture,
                                           int faceIdx,
                                           MTLRenderPassDescriptor* renderPassDesc,
                                           int size)
{
    assert(cubeTexture && "Cube texture is null!");
    assert(renderPassDesc && "Render pass descriptor is null!");
    assert(faceIdx >= 0 && faceIdx < 6 && "Invalid face index!");
    assert(m_renderer && "Renderer is null!");
    assert(m_renderer->m_commandQueue && "Command queue is null!");
    
    if (!cubeTexture || !renderPassDesc || !m_renderer)
        return false;
    
    // Configure render pass for this cube face
    renderPassDesc.colorAttachments[0].texture = cubeTexture;
    renderPassDesc.colorAttachments[0].slice = faceIdx;
    renderPassDesc.colorAttachments[0].level = 0;
    renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // Set clear color (different per face for debugging)
    static const MTLClearColor faceClearColors[6] = {
        MTLClearColorMake(1.0, 0.2, 0.2, 1.0),  // +X: Red
        MTLClearColorMake(0.2, 1.0, 0.2, 1.0),  // -X: Green
        MTLClearColorMake(0.2, 0.2, 1.0, 1.0),  // +Y: Blue
        MTLClearColorMake(1.0, 1.0, 0.2, 1.0),  // -Y: Yellow
        MTLClearColorMake(1.0, 0.2, 1.0, 1.0),  // +Z: Magenta
        MTLClearColorMake(0.2, 1.0, 1.0, 1.0)   // -Z: Cyan
    };
    renderPassDesc.colorAttachments[0].clearColor = faceClearColors[faceIdx];
    
    // Create command buffer using renderer's command queue
    id<MTLCommandBuffer> commandBuffer = [m_renderer->m_commandQueue commandBuffer];
    assert(commandBuffer && "Failed to create command buffer!");
    if (!commandBuffer)
        return false;
    
    // Create render encoder
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];
    assert(renderEncoder && "Failed to create render encoder!");
    if (!renderEncoder)
        return false;
    
    // Setup viewport and scissor using renderer's systems
    m_renderer->SetViewport(0, 0, size, size);
    m_renderer->SetScissor(0, 0, size, size);
    
    // Render scene using I3DEngine (camera already set by caller)
    if (pEngine)
    {
        // Render the scene with appropriate flags
        // Camera is already set by caller, we just render
        int renderFlags = DLD_TERRAIN | DLD_STATIC_OBJECTS | DLD_TERRAIN_WATER | 
                         DLD_PARTICLES | DLD_FAR_SPRITES | DLD_DETAIL_TEXTURES;
        renderFlags &= ~DLD_ENTITIES;  // Exclude entities for cube maps
        
        pEngine->DrawLowDetail(renderFlags);
    }

    
    // Finalize rendering
    [renderEncoder endEncoding];
    [commandBuffer commit];
    m_renderer->TrackCommandBuffer(commandBuffer);
    [commandBuffer waitUntilCompleted];
    
    return true;
}

////////////////////////////////////////////////////////////////////////////
// SaveTextureAsJPG
//
// Saves raw RGBA pixel data as a JPG file using Core Graphics.
//
// Parameters:
//   pixels - Raw RGBA8 pixel data
//   width  - Image width
//   height - Image height
//   path   - Output file path
//
// Returns:
//   true on success, false on failure
////////////////////////////////////////////////////////////////////////////
bool CMetalTextureManager::SaveTextureAsJPG(const byte* pixels, int width, int height, const char* path)
{
    assert(pixels && "SaveTextureAsJPG: pixels is null!");
    assert(path && "SaveTextureAsJPG: path is null!");
    assert(width > 0 && "SaveTextureAsJPG: width must be > 0!");
    assert(height > 0 && "SaveTextureAsJPG: height must be > 0!");
    assert(path[0] != '\0' && "SaveTextureAsJPG: path is empty!");
    
    if (!pixels || !path || width <= 0 || height <= 0)
        return false;
    
    @autoreleasepool
    {
        // Create CGImage from pixel data
        size_t bitsPerComponent = 8;
        size_t bitsPerPixel = 32;
        size_t bytesPerRow = width * 4;
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        assert(colorSpace && "Failed to create color space!");
        
        CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
        
        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, width * height * 4, NULL);
        assert(provider && "Failed to create data provider!");
        
        CGImageRef imageRef = CGImageCreate(width, height,
                                           bitsPerComponent, bitsPerPixel, bytesPerRow,
                                           colorSpace, bitmapInfo, provider,
                                           NULL, false, kCGRenderingIntentDefault);
        
        assert(imageRef && "Failed to create CGImage!");
        if (!imageRef)
        {
            CGDataProviderRelease(provider);
            CGColorSpaceRelease(colorSpace);
            return false;
        }
        
        // Create destination URL
        NSString* nsPath = [NSString stringWithUTF8String:path];
        assert(nsPath && "Failed to create NSString from path!");
        
        NSURL* url = [NSURL fileURLWithPath:nsPath];
        assert(url && "Failed to create NSURL!");
        
        // Create image destination (JPG)
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                                                            kUTTypeJPEG,
                                                                            1,
                                                                            NULL);
        
        assert(destination && "Failed to create image destination!");
        if (!destination)
        {
            CGImageRelease(imageRef);
            CGDataProviderRelease(provider);
            CGColorSpaceRelease(colorSpace);
            return false;
        }
        
        // Set JPG quality (0.9 = 90% quality)
        NSDictionary* properties = @{
            (__bridge NSString*)kCGImageDestinationLossyCompressionQuality: @0.9
        };
        
        // Add image to destination and finalize
        CGImageDestinationAddImage(destination, imageRef, (__bridge CFDictionaryRef)properties);
        bool success = CGImageDestinationFinalize(destination);
        
        // Cleanup
        CFRelease(destination);
        CGImageRelease(imageRef);
        CGDataProviderRelease(provider);
        CGColorSpaceRelease(colorSpace);
        
        return success;
    }
}

////////////////////////////////////////////////////////////////////////////
// EF_ReadAllImgFiles
//
// Reads all image files for a shader's texture animation sequence.
// Supports wildcard patterns like "water*.tga" or "anim#.jpg".
//
// Parameters:
//   ef   - Shader effect
//   tl   - Shader texture unit
//   ta   - Texture animation data
//   name - Texture name with wildcard pattern (e.g., "water*.tga", "anim#.jpg")
//
// Returns:
//   Number of textures loaded, 0 on failure
//
// Notes:
//   - Wildcard patterns supported:
//     * "*.*" - load all files in directory
//     * "prefix*.ext" - load all files matching prefix
//     * "name#.ext" - load numbered sequence (name000.ext, name001.ext, ...)
//     * "name$.ext" - load numbered sequence (name0.ext, name1.ext, ...)
//   - Textures are stored in ta->m_TexPics array
//   - Used for animated water, fire, and other dynamic effects
////////////////////////////////////////////////////////////////////////////
int CMetalTextureManager::EF_ReadAllImgFiles(IShader* ef, SShaderTexUnit* tl, STexAnim* ta, char* name)
{
    assert(name && "CMetalTextureManager: EF_ReadAllImgFiles called with null name!");
    
    if (!name || !name[0])
        return 0;
    
    assert(ta && "CMetalTextureManager: EF_ReadAllImgFiles called with null texture animation!");
    if (!ta)
        return 0;
    
    std::string pattern(name);
    std::string directory;
    std::string filePattern;
    
    size_t lastSlash = pattern.find_last_of("/\\");
    if (lastSlash != std::string::npos)
    {
        directory = pattern.substr(0, lastSlash + 1);
        filePattern = pattern.substr(lastSlash + 1);
    }
    else
    {
        directory = "";
        filePattern = pattern;
    }
    
    bool hasNumberSequence = (filePattern.find('#') != std::string::npos) || 
                            (filePattern.find('$') != std::string::npos);
    bool hasWildcard = filePattern.find('*') != std::string::npos;
    
    int numLoaded = 0;
    
    if (hasNumberSequence)
    {
        char sequenceChar = '#';
        if (filePattern.find('$') != std::string::npos)
            sequenceChar = '$';
        
        std::string prefix = filePattern.substr(0, filePattern.find(sequenceChar));
        std::string suffix = filePattern.substr(filePattern.find(sequenceChar) + 1);
        
        int numDigits = 3;
        if (sequenceChar == '$')
            numDigits = 1;
        
        for (int i = 0; i < 1000; i++)
        {
            char filename[512];
            if (numDigits == 1)
                snprintf(filename, sizeof(filename), "%s%s%d%s", directory.c_str(), prefix.c_str(), i, suffix.c_str());
            else
                snprintf(filename, sizeof(filename), "%s%s%03d%s", directory.c_str(), prefix.c_str(), i, suffix.c_str());
            
            int texId = LoadTexture(filename, nullptr, 0, false, false);
            if (texId == 0)
                break;
            
            numLoaded++;
        }
    }
    else if (hasWildcard)
    {
        numLoaded = 0;
    }
    
    return numLoaded;
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

void CMetalTextureManager::ShareCacheWith(CMetalTextureManager* other)
{
    if (!other || other == this)
        return;
    
    for (const auto& texPair : other->m_textures) {
        int texId = texPair.first;
        const auto& texInfo = texPair.second;
        
        if (m_textures.find(texId) == m_textures.end()) {
            m_textures[texId] = texInfo;
            if (!texInfo.name.empty()) {
                m_textureNameMap[texInfo.name] = texId;
            }
            m_totalTextureMemory += texInfo.memorySize;
        }
    }
    
    for (const auto& texPair : m_textures) {
        int texId = texPair.first;
        const auto& texInfo = texPair.second;
        
        if (other->m_textures.find(texId) == other->m_textures.end()) {
            other->m_textures[texId] = texInfo;
            if (!texInfo.name.empty()) {
                other->m_textureNameMap[texInfo.name] = texId;
            }
            other->m_totalTextureMemory += texInfo.memorySize;
        }
    }
}

const CMetalTextureManager::TextureInfo* CMetalTextureManager::GetTextureInfo(int textureId) const
{
    assert(textureId > 0 && "CMetalTextureManager: GetTextureInfo called with invalid ID!");
    
    auto it = m_textures.find(textureId);
    if (it != m_textures.end())
        return &it->second;
    return nullptr;
}

void CMetalTextureManager::SetTextureClamp(int textureId, bool bEnable)
{
    assert(textureId > 0 && "SetTextureClamp: invalid texture ID!");
    
    auto it = m_textures.find(textureId);
    if (it != m_textures.end())
    {
        it->second.clampU = bEnable;
        it->second.clampV = bEnable;
        
        if (bEnable)
        {
            it->second.flags |= FT_CLAMP;
        }
        else
        {
            it->second.flags &= ~FT_CLAMP;
        }
    }
}

void CMetalTextureManager::SetTextureFilter(int textureId, int nFilter)
{
    assert(textureId > 0 && "SetTextureFilter: invalid texture ID!");
    
    auto it = m_textures.find(textureId);
    if (it != m_textures.end())
    {
        it->second.filterMode = nFilter;
    }
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
    assert(filename && "CreateMetalTextureFromFile: filename cannot be null!");
    assert(filename[0] != '\0' && "CreateMetalTextureFromFile: filename is empty!");
    
    std::vector<byte> data;
    int width, height;
    if (!LoadTextureData(filename, data, width, height))
        return nil;
        
    return CreateMetalTexture(width, height, MTLPixelFormatRGBA8Unorm, data.data(), data.size());
}

void CMetalTextureManager::UpdateMetalTexture(id<MTLTexture> texture, const void* data, int x, int y, int w, int h)
{
    assert(texture && "UpdateMetalTexture: texture cannot be null!");
    assert(data && "UpdateMetalTexture: data cannot be null!");
    assert(w > 0 && h > 0 && "UpdateMetalTexture: dimensions must be positive!");
    assert(x >= 0 && y >= 0 && "UpdateMetalTexture: position cannot be negative!");
    
    if (!texture || !data)
        return;
        
    [texture replaceRegion:MTLRegionMake2D(x, y, w, h)
               mipmapLevel:0
                 withBytes:data
               bytesPerRow:w * 4];
}

void CMetalTextureManager::BindTexture(int slot, id<MTLTexture> texture)
{
    assert(slot >= 0 && "BindTexture: slot cannot be negative!");
    assert(m_renderer && "BindTexture: renderer is null!");
    
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
    int id = m_nextTextureId++;
    assert(id > 0 && "AllocateTextureId: texture ID overflow!");
    return id;
}

void CMetalTextureManager::ReleaseTextureId(int id)
{
    assert(id > 0 && "ReleaseTextureId: invalid texture ID!");
}

bool CMetalTextureManager::LoadTextureData(const char* filename, std::vector<byte>& data, int& width, int& height)
{
    assert(filename && "LoadTextureData: filename cannot be null!");
    
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
    
    if (!iSystem)
        assert(false);
        return false;
    
    FILE* pFile = iSystem->GetIPak()->FOpen(filename, "rb");
    if (pFile)
    {
        iSystem->GetIPak()->FSeek(pFile, 0, SEEK_END);
        long fileSize = iSystem->GetIPak()->FTell(pFile);
        iSystem->GetIPak()->FSeek(pFile, 0, SEEK_SET);
        
        if (fileSize > 0)
        {
            std::vector<byte> fileData(fileSize);
            size_t bytesRead = iSystem->GetIPak()->FRead(fileData.data(), 1, fileSize, pFile);
            iSystem->GetIPak()->FClose(pFile);
            
            if (bytesRead == fileSize)
            {
                const char* baseName = strrchr(filename, '/');
                if (!baseName) baseName = strrchr(filename, '\\');
                if (!baseName) baseName = filename;
                else baseName++;
                
                strncpy(CImageFile::m_CurFileName, baseName, sizeof(CImageFile::m_CurFileName) - 1);
                CImageFile::m_CurFileName[sizeof(CImageFile::m_CurFileName) - 1] = '\0';
                strlwr(CImageFile::m_CurFileName);
                
                CImageFile* pImageFile = CImageFile::mfLoad_file(fileData.data(), fileSize);
                EImFileError imageError = CImageFile::mfGet_error();
                if (pImageFile && imageError == eIFE_OK)
                {
                    width = pImageFile->mfGet_width();
                    height = pImageFile->mfGet_height();
                    
                    byte* pImageData = pImageFile->mfGet_image();
                    int imgSize = pImageFile->mfGet_ImageSize();
                    if (pImageData && width > 0 && height > 0 && imgSize > 0)
                    {
                        int bps = pImageFile->mfGet_bps();
                        int expectedSize = width * height * (bps / 8);
                        
                        if (imgSize >= expectedSize)
                        {
                            size_t dataSize = width * height * 4;
                            data.resize(dataSize);
                            
                            if (bps == 32)
                            {
                                auto* pPixels = (SRGBPixel*)pImageData;
                                for (int i = 0; i < width * height; i++)
                                {
                                    data[i * 4 + 0] = pPixels[i].red;
                                    data[i * 4 + 1] = pPixels[i].green;
                                    data[i * 4 + 2] = pPixels[i].blue;
                                    data[i * 4 + 3] = pPixels[i].alpha;
                                }
                            }
                            else
                            {
                                size_t copySize = (imgSize < dataSize) ? imgSize : dataSize;
                                memcpy(data.data(), pImageData, copySize);
                            }
                            
                            format = eTF_8888;
                            delete pImageFile;
                            return true;
                        }
                        else
                        {
                            iLog->Log("LoadTextureData: Invalid image size for %s - expected %d bytes, got %d bytes (width=%d, height=%d, bps=%d)\n", 
                                     filename, expectedSize, imgSize, width, height, bps);
                        }
                    }
                    else
                    {
                        iLog->Log("LoadTextureData: Invalid image data for %s - pImageData=%p, width=%d, height=%d, imgSize=%d\n", 
                                 filename, pImageData, width, height, imgSize);
                    }
                }
                else
                {
                    const char* errorDetail = CImageFile::mfGet_error_detail();
                    const char* errorMsg = "";
                    switch (imageError)
                    {
                        case eIFE_IOerror:
                            errorMsg = "IO error";
                            break;
                        case eIFE_OutOfMemory:
                            errorMsg = "Out of memory";
                            break;
                        case eIFE_BadFormat:
                            errorMsg = "Bad format";
                            break;
                        default:
                            errorMsg = "Unknown error";
                            break;
                    }
                    iLog->Log("LoadTextureData: CImageFile failed to parse %s - %s%s%s\n", 
                             filename, errorMsg, 
                             errorDetail && errorDetail[0] ? " - " : "", 
                             errorDetail && errorDetail[0] ? errorDetail : "");
                }

                delete pImageFile;
            }
            else
            {
                iLog->Log("LoadTextureData: Failed to read file %s - expected %ld bytes, read %zu bytes\n", 
                         filename, fileSize, bytesRead);
            }
        }
        else
        {
            iLog->Log("LoadTextureData: File %s has zero or negative size (%ld bytes)\n", filename, fileSize);
            iSystem->GetIPak()->FClose(pFile);
        }
    }
    else
    {
        iLog->Log("LoadTextureData: CryPak failed to open file %s\n", filename);
    }
    
    @autoreleasepool
    {
        NSString* filePathStr = [NSString stringWithUTF8String:filename];
        NSURL* fileURL = [NSURL fileURLWithPath:filePathStr];
        
        if (fileURL && [[NSFileManager defaultManager] fileExistsAtPath:filePathStr])
        {
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
            
            if (loadedTexture && !error)
            {
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
            else
            {
                if (error)
                {
                    NSString* errorDesc = [error localizedDescription];
                    iLog->Log("LoadTextureData: MTKTextureLoader failed for %s - %s\n", 
                             filename, errorDesc ? [errorDesc UTF8String] : "Unknown error");
                }
                else
                {
                    iLog->Log("LoadTextureData: MTKTextureLoader returned nil texture for %s\n", filename);
                }
            }
        }
        else
        {
            iLog->Log("LoadTextureData: File does not exist at path %s\n", filename);
        }
        
        return false;
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
