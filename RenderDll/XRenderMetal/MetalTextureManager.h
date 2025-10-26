////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalTextureManager.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal texture manager class
//               Handles all texture operations for Metal API
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_TEXTURE_MANAGER_H
#define METAL_TEXTURE_MANAGER_H

#if defined(__APPLE__) && defined(__MACH__)

#include <Metal/Metal.h>
#include <MetalKit/MetalKit.h>
#include <vector>
#include <unordered_map>
#include <string>

// Include CryEngine interfaces
#include "IRenderer.h"
#include "Cry_Math.h"

// Forward declarations
class CMetalBaseRenderer;
struct STexPic;

// Metal texture manager class
class CMetalTextureManager
{
public:
    CMetalTextureManager(CMetalBaseRenderer* renderer);
    virtual ~CMetalTextureManager();

    // Texture Management Interface
    void SetTexture(int tnum, ETexType Type = eTT_Base);
    void SetWhiteTexture();
    unsigned int DownLoadToVideoMemory(unsigned char* data, int w, int h, 
                                     ETEX_Format eTFSrc, ETEX_Format eTFDst, 
                                     int nummipmap, bool repeat = true, 
                                     int filter = FILTER_BILINEAR, int Id = 0, 
                                     char* szCacheName = NULL, int flags = 0);
    void UpdateTextureInVideoMemory(uint tnum, unsigned char* newdata, int posx, int posy, 
                                   int w, int h, ETEX_Format eTF = eTF_0888);
    unsigned int LoadTexture(const char* filename, int* tex_type = NULL, 
                            unsigned int def_tid = 0, bool compresstodisk = true, 
                            bool bWarn = true);
    bool DXTCompress(byte* raw_data, int nWidth, int nHeight, ETEX_Format eTF, 
                    bool bUseHW, bool bGenMips, int nSrcBytesPerPix, 
                    MIPDXTcallback callback = 0);
    bool DXTDecompress(byte* srcData, byte* dstData, int nWidth, int nHeight, 
                      ETEX_Format eSrcTF, bool bUseHW, int nDstBytesPerPix);
    void RemoveTexture(unsigned int TextureId);
    void RemoveTexture(ITexPic* pTexPic);
    bool SetGammaDelta(const float fGamma);
    
    // Font texture management
    bool FontUploadTexture(class CFBitmap*, ETEX_Format eTF = eTF_8888);
    int FontCreateTexture(int Width, int Height, byte* pData, ETEX_Format eTF = eTF_8888);
    bool FontUpdateTexture(int nTexId, int X, int Y, int USize, int VSize, byte* pData);
    void FontReleaseTexture(class CFBitmap* pBmp);
    void FontSetTexture(class CFBitmap*, int nFilterMode);
    void FontSetTexture(int nTexId, int nFilterMode);
    void FontSetRenderingState(unsigned long nVirtualScreenWidth, unsigned long nVirtualScreenHeight);
    void FontSetBlending(int src, int dst);
    void FontRestoreRenderingState();
    
    // Shader texture management
    ITexPic* EF_GetTextureByID(int Id);
    ITexPic* EF_LoadTexture(const char* nameTex, uint flags, uint flags2, byte eTT, 
                           float fAmount1 = -1.0f, float fAmount2 = -1.0f, 
                           int Id = -1, int BindId = 0);
    int EF_LoadLightmap(const char* name);
    bool EF_ScanEnvironmentCM(const char* name, int size, Vec3& Pos);
    int EF_ReadAllImgFiles(IShader* ef, SShaderTexUnit* tl, STexAnim* ta, char* name);
    
    // File I/O
    void WriteDDS(byte* dat, int wdt, int hgt, int Size, const char* name, EImFormat eF, int NumMips);
    void WriteTGA(byte* dat, int wdt, int hgt, const char* name, int bits);
    void WriteJPG(byte* dat, int wdt, int hgt, char* name);
    
    // Utility methods
    void ClearAllTextures();
    int GetTextureCount() const;
    size_t GetTotalTextureMemory() const;

protected:
    // Metal-specific texture management
    id<MTLTexture> CreateMetalTexture(int width, int height, MTLPixelFormat format, 
                                     const void* data = nullptr, size_t dataSize = 0);
    id<MTLTexture> CreateMetalTextureFromFile(const char* filename);
    void UpdateMetalTexture(id<MTLTexture> texture, const void* data, int x, int y, int w, int h);
    void BindTexture(int slot, id<MTLTexture> texture);
    
    // Texture format conversion
    MTLPixelFormat ConvertToMetalFormat(ETEX_Format format);
    ETEX_Format ConvertFromMetalFormat(MTLPixelFormat format);
    
    // Texture caching and management
    struct TextureInfo
    {
        id<MTLTexture> metalTexture;
        int width, height;
        ETEX_Format format;
        std::string name;
        size_t memorySize;
        bool isLoaded;
    };
    
    std::unordered_map<int, TextureInfo> m_textures;
    std::unordered_map<std::string, int> m_textureNameMap;
    int m_nextTextureId;
    size_t m_totalTextureMemory;
    
    // Current state
    int m_currentTextureSlot;
    id<MTLTexture> m_currentTexture;
    id<MTLTexture> m_whiteTexture;
    
    // Gamma correction
    float m_gammaValue;
    bool m_gammaEnabled;
    
    // Reference to base renderer
    CMetalBaseRenderer* m_renderer;
    
    // Internal methods
    int AllocateTextureId();
    void ReleaseTextureId(int id);
    bool LoadTextureData(const char* filename, std::vector<byte>& data, int& width, int& height);
    void GenerateMipmaps(id<MTLTexture> texture);
    void SetTextureParameters(id<MTLTexture> texture, bool repeat, int filter);
    int GetBytesPerPixel(ETEX_Format format);
};

#endif // __APPLE__ && __MACH__

#endif // METAL_TEXTURE_MANAGER_H
