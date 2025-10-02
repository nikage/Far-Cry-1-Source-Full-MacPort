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
        
    auto it = m_textures.find(tnum);
    if (it != m_textures.end())
    {
        m_currentTexture = it->second.metalTexture;
        m_currentTextureSlot = tnum;
        
        // Bind texture to Metal render encoder based on type
        if (m_renderer && m_renderer->m_renderEncoder && m_currentTexture)
        {
            int textureIndex = 0;
            switch (Type)
            {
                case eTT_Base:
                    textureIndex = 0;
                    break;
                case eTT_Cubemap:
                    textureIndex = 3;
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
        // Texture not found, use white texture as fallback
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
        
    MTLPixelFormat metalFormat = ConvertToMetalFormat(eTFDst);
    if (metalFormat == MTLPixelFormatInvalid)
        return 0;
        
    id<MTLTexture> texture = CreateMetalTexture(w, h, metalFormat, data, w * h * 4);
    if (!texture)
        return 0;
        
    int textureId = AllocateTextureId();
    if (textureId == -1)
        return 0;
        
    TextureInfo info;
    info.metalTexture = texture;
    info.width = w;
    info.height = h;
    info.format = eTFDst;
    info.name = szCacheName ? szCacheName : "";
    info.memorySize = w * h * 4;
    info.isLoaded = true;
    
    m_textures[textureId] = info;
    m_totalTextureMemory += info.memorySize;
    
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
        case eTF_8888: return MTLPixelFormatRGBA8Unorm;
        case eTF_0888: return MTLPixelFormatRGBA8Unorm; // RGB8Unorm not available, use RGBA8
        case eTF_4444: return MTLPixelFormatRGBA8Unorm; // RGBA4Unorm not available, use RGBA8
        case eTF_1555: return MTLPixelFormatRGBA8Unorm; // RGB5A1Unorm not available, use RGBA8
        case eTF_0565: return MTLPixelFormatRGBA8Unorm; // RGB565 not available, use RGBA8
        case eTF_DXT1: return MTLPixelFormatRGBA8Unorm; // BC formats not available on macOS, use RGBA8
        case eTF_DXT3: return MTLPixelFormatRGBA8Unorm; // BC formats not available on macOS, use RGBA8
        case eTF_DXT5: return MTLPixelFormatRGBA8Unorm; // BC formats not available on macOS, use RGBA8
        default: return MTLPixelFormatRGBA8Unorm;
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

#endif // __APPLE__ && __MACH__
