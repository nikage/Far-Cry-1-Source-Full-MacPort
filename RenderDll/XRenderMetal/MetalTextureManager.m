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
#include <array>
#include <memory>
#include <cassert>

// Include CryEngine interfaces
#include "IRenderer.h"
#include "Cry_Math.h"

// Forward declarations
class CMetalBaseRenderer;
struct STexPic;
class I3DEngine;
class CMetalTextureManager;
struct SShaderTexUnit;

// Metal texture wrapper implementing ITexPic interface
class CMetalTexture : public ITexPic
{
public:
    CMetalTexture(int texId, CMetalTextureManager* manager);
    virtual ~CMetalTexture();
    
    virtual void AddRef();
    virtual void Release(int bForce = false);
    virtual const char* GetName();
    virtual int GetWidth();
    virtual int GetHeight();
    virtual int GetOriginalWidth();
    virtual int GetOriginalHeight();
    virtual int GetTextureID();
    virtual int GetFlags();
    virtual int GetFlags2();
    virtual void SetClamp(bool bEnable);
    virtual bool IsTextureLoaded();
    virtual void PrecacheAsynchronously(float fDist, int Flags);
    virtual void Preload(int Flags);
    virtual byte* GetData32();
    virtual bool SetFilter(int nFilter);
    
private:
    int m_textureId;
    CMetalTextureManager* m_manager;
    int m_refCount;
};

// Metal texture manager class
class CMetalTextureManager
{
public:
    CMetalTextureManager(CMetalBaseRenderer* renderer);
    virtual ~CMetalTextureManager();

    // Texture Management Interface

    void Update(float fTime);
    void SetTexture(int tnum, ETexType Type = eTT_Base);
    id<MTLTexture> GetBoundFragmentTexture(int index) const;
    id<MTLSamplerState> GetBoundFragmentSampler(int index) const;
    void SetWhiteTexture();
    id<MTLTexture> GetWhiteTexture() const { return m_whiteTexture; }
    id<MTLTexture> EnsureWhiteTexture();
    id<MTLTexture> ResolveMetalTextureByID(int textureId);
    void SetClampModeForLastTexture(bool clamp);
    void ApplyTexUnit(int stage, SShaderTexUnit& unit);
    id<MTLSamplerState> AcquireDefaultSampler();
    void BindDefaultSampler(int slot);
    void ApplyCachedFragmentBindingsToEncoder(int maxSlotExclusive = 16);
    
    // Upload texture data from memory to GPU
    unsigned int DownLoadToVideoMemory(unsigned char* data, int w, int h, 
                                     ETEX_Format eTFSrc, ETEX_Format eTFDst, 
                                     int nummipmap, bool repeat = true, 
                                     int filter = FILTER_BILINEAR, int Id = 0, 
                                     char* szCacheName = NULL, int flags = 0);
    
    // Update existing texture region with new data
    void UpdateTextureInVideoMemory(uint tnum, unsigned char* newdata, int posx, int posy, 
                                   int w, int h, ETEX_Format eTF = eTF_0888);
    
    // Load texture from file (PNG, JPG, TGA, etc.)
    unsigned int LoadTexture(const char* filename, int* tex_type = nullptr,
                            unsigned int def_tid = 0, bool compresstodisk = true, 
                            bool bWarn = true);
    
    // DXT decompression job structure (for batch API)
    struct DXTDecompressJob
    {
        byte* srcData;
        byte* dstData;
        int width;
        int height;
        ETEX_Format format;
        int dstBytesPerPix;
    };
    
    bool DXTCompress(byte* raw_data, int nWidth, int nHeight, ETEX_Format eTF, 
                    bool bUseHW, bool bGenMips, int nSrcBytesPerPix, 
                    MIPDXTcallback callback = 0);
    bool DXTDecompress(byte* srcData, byte* dstData, int nWidth, int nHeight, 
                      ETEX_Format eSrcTF, bool bUseHW, int nDstBytesPerPix);
    
    // Batch decompression API (reduces GPU sync overhead)
    void BeginDXTDecompressionBatch();
    void QueueDXTDecompression(const DXTDecompressJob& job);
    bool ExecuteDXTDecompressionBatch();
    
    void RemoveTexture(unsigned int TextureId);
    void RemoveTexture(ITexPic* pTexPic);
    
    // Display gamma correction (not texture modification)
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
    void ShareCacheWith(CMetalTextureManager* other);
    
    // Gamma accessors for renderer
    float GetGammaValue() const { return m_gammaValue; }
    bool IsGammaEnabled() const { return m_gammaEnabled; }
    
    // Texture info structure (public for CMetalTexture access)
    struct TextureInfo
    {
        id<MTLTexture> metalTexture;
        int width, height;
        ETEX_Format format;
        std::string name;
        size_t memorySize;
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

    class TextureInfoHandle
    {
    public:
        TextureInfoHandle();
        TextureInfo* operator->();
        const TextureInfo* operator->() const;
        TextureInfo& operator*();
        const TextureInfo& operator*() const;
        explicit operator bool() const;
        int GetId() const;
        static TextureInfoHandle Create(int textureId, TextureInfo&& info);
    private:
        struct Impl;
        std::shared_ptr<Impl> m_impl;
        explicit TextureInfoHandle(std::shared_ptr<Impl> impl);
        friend class CMetalTextureInfoFactory;
    };

    class ITextureInfoFactory
    {
    public:
        virtual ~ITextureInfoFactory() = default;
        virtual TextureInfoHandle Create(int textureId, TextureInfo&& info) = 0;
    };

    class CMetalTextureInfoFactory final : public ITextureInfoFactory
    {
    public:
        TextureInfoHandle Create(int textureId, TextureInfo&& info) override;
    };
    
    // Texture info accessors for CMetalTexture
    const TextureInfo* GetTextureInfo(int textureId) const;
    void SetTextureClamp(int textureId, bool bEnable);
    void SetTextureFilter(int textureId, int nFilter);
    TextureInfoHandle& UpsertTextureHandle(int textureId, TextureInfo&& info);
    TextureInfoHandle* FindHandle(int textureId);
    const TextureInfoHandle* FindHandle(int textureId) const;
    
    // Image file I/O
    bool SaveTextureAsJPG(const byte* pixels, int width, int height, const char* path);
    
    // Cube map rendering helpers
    bool RenderCubeFace(I3DEngine* pEngine, id<MTLTexture> cubeTexture, int faceIdx, 
                       MTLRenderPassDescriptor* renderPassDesc, int size);

protected:
    // Metal-specific texture management
    id<MTLTexture> CreateMetalTexture(int width, int height, MTLPixelFormat format, 
                                     const void* data = nullptr, size_t dataSize = 0);
    id<MTLTexture> CreateMetalTextureFromFile(const char* filename);
    void UpdateMetalTexture(id<MTLTexture> texture, const void* data, int x, int y, int w, int h);
    void BindTexture(int slot, id<MTLTexture> texture);
    void BindSampler(int slot, id<MTLSamplerState> sampler);
    id<MTLSamplerState> GetOrCreateSamplerState(const SShaderTexUnit& unit);
    id<MTLSamplerState> GetDefaultSampler();
    
    // Texture format conversion
    MTLPixelFormat ConvertToMetalFormat(ETEX_Format format);
    ETEX_Format ConvertFromMetalFormat(MTLPixelFormat format);
    
    
    std::unordered_map<int, TextureInfoHandle> m_textures;
    std::unordered_map<std::string, int> m_textureNameMap;
    int m_nextTextureId;
    size_t m_totalTextureMemory;
    
    // Batch decompression state
    std::vector<DXTDecompressJob> m_decompressJobs;
    
    // Helper functions
    static inline int GetDXTBlockSize(ETEX_Format format) {
        assert((format == eTF_DXT1 || format == eTF_DXT3 || format == eTF_DXT5) && 
               "GetDXTBlockSize: format must be DXT1, DXT3, or DXT5!");
        return (format == eTF_DXT1) ? 8 : 16;
    }
    
    // Current state
    int m_currentTextureSlot;
    id<MTLTexture> m_currentTexture;
    id<MTLTexture> m_whiteTexture;
    std::array<id<MTLTexture>, 16> m_boundFragmentTextures;
    std::array<id<MTLSamplerState>, 16> m_boundFragmentSamplers;
    std::unordered_map<uint64_t, id<MTLSamplerState>> m_samplerCache;
    int m_lastBoundStage;
    std::array<int, 16> m_stageTextureIds;
    
    // Animated-texture time (advanced each frame by Update())
    float m_animTime;

    // Display gamma correction
    float m_gammaValue;      // Gamma delta value (added to base gamma)
    bool m_gammaEnabled;     // True if gamma correction is active
    
    // Font rendering state
    unsigned long m_savedViewportWidth;
    unsigned long m_savedViewportHeight;
    unsigned long m_fontOrthoVirtualW;
    unsigned long m_fontOrthoVirtualH;
    int m_savedBlendSrc;
    int m_savedBlendDst;
    id<MTLBuffer> m_fontOrthoBuffer;
    
    // Reference to base renderer
    CMetalBaseRenderer* m_renderer;
    std::unique_ptr<ITextureInfoFactory> m_textureHandleFactory;
    
    // Internal methods
    int AllocateTextureId();
    void ReleaseTextureId(int id);
    bool LoadTextureData(const char* filename, std::vector<byte>& data, int& width, int& height, int& mipCount);
    bool LoadTextureData(const char* filename, std::vector<byte>& data, int& width, int& height, ETEX_Format& format, int& mipCount);
    void GenerateMipmaps(id<MTLTexture> texture);
    void SetTextureParameters(id<MTLTexture> texture, bool repeat, int filter);
    int GetBytesPerPixel(ETEX_Format format);
};

#endif // __APPLE__ && __MACH__

#endif // METAL_TEXTURE_MANAGER_H
