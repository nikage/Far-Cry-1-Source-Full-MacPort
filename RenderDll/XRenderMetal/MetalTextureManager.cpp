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

CMetalTextureManager::CMetalTextureManager(CMetalBaseRenderer* renderer)
    : m_renderer(renderer)
    , m_nextTextureId(1)
    , m_totalTextureMemory(0)
    , m_currentTextureSlot(0)
    , m_currentTexture(nil)
    , m_whiteTexture(nil)
    , m_gammaValue(1.0f)
    , m_gammaEnabled(false)
{
    // Initialize texture manager
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

unsigned int CMetalTextureManager::DownLoadToVideoMemory(unsigned char* data, int w, int h, 
                                                       ETEX_Format eTFSrc, ETEX_Format eTFDst, 
                                                       int nummipmap, bool repeat, 
                                                       int filter, int Id, 
                                                       char* szCacheName, int flags)
{
    if (!data || w <= 0 || h <= 0)
        return 0;
    
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

unsigned int CMetalTextureManager::LoadTexture(const char* filename, int* tex_type, 
                                              unsigned int def_tid, bool compresstodisk, 
                                              bool bWarn)
{
    if (!filename)
        return 0;
        
    // Check if texture is already loaded
    std::string nameStr(filename);
    auto nameIt = m_textureNameMap.find(nameStr);
    if (nameIt != m_textureNameMap.end())
    {
        return nameIt->second;
    }
    
    // Load texture data from file
    std::vector<byte> data;
    int width, height;
    if (!LoadTextureData(filename, data, width, height))
    {
        if (bWarn)
            printf("Warning: Failed to load texture: %s\n", filename);
        return 0;
    }
    
    // Create Metal texture
    MTLPixelFormat format = MTLPixelFormatRGBA8Unorm; // Default format
    id<MTLTexture> texture = CreateMetalTexture(width, height, format, data.data(), data.size());
    if (!texture)
    {
        if (bWarn)
            printf("Warning: Failed to create Metal texture for: %s\n", filename);
        return 0;
    }
    
    int textureId = AllocateTextureId();
    if (textureId == -1)
        return 0;
        
    TextureInfo info;
    info.metalTexture = texture;
    info.width = width;
    info.height = height;
    info.format = eTF_8888; // Default format
    info.name = filename;
    info.memorySize = data.size();
    info.isLoaded = true;
    
    m_textures[textureId] = info;
    m_textureNameMap[nameStr] = textureId;
    m_totalTextureMemory += info.memorySize;
    
    return textureId;
}

bool CMetalTextureManager::DXTCompress(byte* raw_data, int nWidth, int nHeight, ETEX_Format eTF, 
                                      bool bUseHW, bool bGenMips, int nSrcBytesPerPix, 
                                      MIPDXTcallback callback)
{
    // DXT compression is not directly supported in Metal
    // This would need to be implemented using a compute shader or external library
    return false;
}

bool CMetalTextureManager::DXTDecompress(byte* srcData, byte* dstData, int nWidth, int nHeight, 
                                        ETEX_Format eSrcTF, bool bUseHW, int nDstBytesPerPix)
{
    // DXT decompression is not directly supported in Metal
    // This would need to be implemented using a compute shader or external library
    return false;
}

void CMetalTextureManager::RemoveTexture(unsigned int TextureId)
{
    auto it = m_textures.find(TextureId);
    if (it != m_textures.end())
    {
        m_totalTextureMemory -= it->second.memorySize;
        m_textures.erase(it);
        ReleaseTextureId(TextureId);
    }
}

void CMetalTextureManager::RemoveTexture(ITexPic* pTexPic)
{
    // Find texture by ITexPic pointer and remove it
    for (auto it = m_textures.begin(); it != m_textures.end(); ++it)
    {
        // This would need to be implemented based on how ITexPic relates to our texture storage
        // For now, this is a placeholder
    }
}

bool CMetalTextureManager::SetGammaDelta(const float fGamma)
{
    m_gammaValue = fGamma;
    m_gammaEnabled = (fGamma != 1.0f);
    
    // Apply gamma correction to textures if needed
    // This would require updating all loaded textures
    return true;
}

// Font texture management methods
bool CMetalTextureManager::FontUploadTexture(class CFBitmap* bitmap, ETEX_Format eTF)
{
    if (!bitmap)
        return false;
        
    // Convert CFBitmap to Metal texture
    // This would need to be implemented based on CFBitmap structure
    return false;
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

void CMetalTextureManager::FontReleaseTexture(class CFBitmap* pBmp)
{
    // Release font texture resources
}

void CMetalTextureManager::FontSetTexture(class CFBitmap* bitmap, int nFilterMode)
{
    // Set font texture filtering mode
}

void CMetalTextureManager::FontSetTexture(int nTexId, int nFilterMode)
{
    auto it = m_textures.find(nTexId);
    if (it != m_textures.end())
    {
        SetTextureParameters(it->second.metalTexture, true, nFilterMode);
    }
}

void CMetalTextureManager::FontSetRenderingState(unsigned long nVirtualScreenWidth, unsigned long nVirtualScreenHeight)
{
    // Set font rendering state
}

void CMetalTextureManager::FontSetBlending(int src, int dst)
{
    // Set font blending mode
}

void CMetalTextureManager::FontRestoreRenderingState()
{
    // Restore font rendering state
}

// Shader texture management
ITexPic* CMetalTextureManager::EF_GetTextureByID(int Id)
{
    auto it = m_textures.find(Id);
    if (it == m_textures.end())
        return nullptr;
        
    // Return ITexPic interface - this would need to be implemented
    return nullptr;
}

ITexPic* CMetalTextureManager::EF_LoadTexture(const char* nameTex, uint flags, uint flags2, byte eTT, 
                                               float fAmount1, float fAmount2, 
                                               int Id, int BindId)
{
    // Load texture for shader system
    unsigned int textureId = LoadTexture(nameTex, nullptr, 0, true, true);
    if (textureId == 0)
        return nullptr;
        
    // Return ITexPic interface - this would need to be implemented
    return nullptr;
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

// Protected methods
id<MTLTexture> CMetalTextureManager::CreateMetalTexture(int width, int height, MTLPixelFormat format, 
                                                       const void* data, size_t dataSize)
{
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
    // Load texture data from file
    // This would need to be implemented based on the file format
    return false;
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
