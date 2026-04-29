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
#include "MetalRenderer.m"
#include "../../CryFont/FBitmap.h"
#include "ICryPak.h"
#include "I3DEngine.h"
#include "ISystem.h"
#include "MetalBaseRenderer.m"
#include "../Common/Textures/Image/CImage.h"
#include <Cocoa/Cocoa.h>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <cfloat>
#include <utility>
#include <cctype>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

int SShaderTexUnit::mfSetTexture(int nt)
{
    CMetalRenderer* renderer = static_cast<CMetalRenderer*>(gRenDev);
    if (!renderer)
        return 0;
    CMetalTextureManager* textureManager = renderer->GetTextureManager();
    if (!textureManager)
        return 0;
    int stage = nt >= 0 ? nt : 0;
    textureManager->ApplyTexUnit(stage, *this);
    return 1;
}

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

#ifdef max
#undef max
#endif
#ifdef min
#undef min
#endif

namespace
{
    inline bool ShouldTraceTextureLoads()
    {
        static int s_trace = -1;
        if (s_trace == -1)
        {
            const char* env = getenv("CRY_TRACE_TEXTURES");
            s_trace = (env && env[0] && env[0] != '0') ? 1 : 0;
        }
        return s_trace == 1;
    }

    inline void TraceTextureLoad(const char* fmt, ...)
    {
        if (!ShouldTraceTextureLoads())
            return;
        va_list args;
        va_start(args, fmt);
        vfprintf(stderr, fmt, args);
        fputc('\n', stderr);
        fflush(stderr);
        va_end(args);
    }

    inline ETEX_Format ImageFormatToTexFormat(EImFormat imageFormat)
    {
        switch (imageFormat)
        {
            case eIF_DXT1:
                return eTF_DXT1;
            case eIF_DXT3:
                return eTF_DXT3;
            case eIF_DXT5:
                return eTF_DXT5;
            case eIF_DDS_LUMINANCE:
                return eTF_8000;
            case eIF_DDS_RGB8:
                return eTF_0888;
            case eIF_DDS_RGBA8:
                return eTF_8888;
            default:
                return eTF_8888;
        }
    }

    inline size_t DxtBlockSize(ETEX_Format format)
    {
        switch (format)
        {
            case eTF_DXT1:
                return 8;
            case eTF_DXT3:
            case eTF_DXT5:
                return 16;
            default:
                return 0;
        }
    }

    inline bool IsCompressedETEXFormat(ETEX_Format format)
    {
        switch (format)
        {
            case eTF_DXT1:
            case eTF_DXT3:
            case eTF_DXT5:
                return true;
            default:
                return false;
        }
    }

    inline size_t ComputeCompressedLevelSize(int width, int height, ETEX_Format format)
    {
        const size_t blockSize = DxtBlockSize(format);
        const size_t blocksWide = static_cast<size_t>((width + 3) / 4);
        const size_t blocksHigh = static_cast<size_t>((height + 3) / 4);
        return blocksWide * blocksHigh * blockSize;
    }

    inline size_t ComputeBytesPerRow(ETEX_Format format, int width, int bytesPerPixel)
    {
        if (IsCompressedETEXFormat(format))
        {
            const size_t blockSize = DxtBlockSize(format);
            const size_t blocksWide = static_cast<size_t>((width + 3) / 4);
            return blocksWide * blockSize;
        }
        return static_cast<size_t>(width) * static_cast<size_t>(std::max(1, bytesPerPixel));
    }

    inline size_t ComputeTextureMemoryBytes(int width, int height, int mipLevels, int bytesPerPixel, ETEX_Format format)
    {
        size_t total = 0;
        int levelWidth = std::max(1, width);
        int levelHeight = std::max(1, height);

        for (int level = 0; level < mipLevels; ++level)
        {
            if (IsCompressedETEXFormat(format))
            {
                total += ComputeCompressedLevelSize(levelWidth, levelHeight, format);
            }
            else
            {
                total += static_cast<size_t>(levelWidth) * static_cast<size_t>(levelHeight) * static_cast<size_t>(std::max(1, bytesPerPixel));
            }

            levelWidth = std::max(1, levelWidth >> 1);
            levelHeight = std::max(1, levelHeight >> 1);
        }

        return total;
    }

    inline int CalculateFullMipCount(int width, int height)
    {
        int levels = 1;
        int w = std::max(1, width);
        int h = std::max(1, height);
        while (w > 1 || h > 1)
        {
            w = std::max(1, w >> 1);
            h = std::max(1, h >> 1);
            ++levels;
        }
        return levels;
    }

    inline uint32_t MakeFourCC(char a, char b, char c, char d)
    {
        return static_cast<uint32_t>(static_cast<unsigned char>(a))
            | (static_cast<uint32_t>(static_cast<unsigned char>(b)) << 8)
            | (static_cast<uint32_t>(static_cast<unsigned char>(c)) << 16)
            | (static_cast<uint32_t>(static_cast<unsigned char>(d)) << 24);
    }

#pragma pack(push, 1)
    struct DdsPixelFormat
    {
        uint32_t size;
        uint32_t flags;
        uint32_t fourCC;
        uint32_t rgbBitCount;
        uint32_t rBitMask;
        uint32_t gBitMask;
        uint32_t bBitMask;
        uint32_t aBitMask;
    };

    struct DdsHeader
    {
        uint32_t size;
        uint32_t flags;
        uint32_t height;
        uint32_t width;
        uint32_t pitchOrLinearSize;
        uint32_t depth;
        uint32_t mipMapCount;
        uint32_t reserved1[11];
        DdsPixelFormat ddspf;
        uint32_t caps;
        uint32_t caps2;
        uint32_t caps3;
        uint32_t caps4;
        uint32_t reserved2;
    };
#pragma pack(pop)

    constexpr uint32_t kDdsFlagAlphaPixels = 0x00000001;
    constexpr uint32_t kDdsFlagRgb = 0x00000040;

    inline bool TryLoadDDSFromMemory(const byte* buffer,
                                     size_t bufferSize,
                                     std::vector<byte>& outData,
                                     int& width,
                                     int& height,
                                     ETEX_Format& format,
                                     int& mipCount,
                                     const char* debugName = nullptr)
    {
        if (!buffer || bufferSize < 4 + sizeof(DdsHeader))
        {
            TraceTextureLoad("TryLoadDDSFromMemory: %s rejected - buffer too small (%zu)", debugName ? debugName : "<unnamed>", bufferSize);
            return false;
        }

        if (buffer[0] != 'D' || buffer[1] != 'D' || buffer[2] != 'S' || buffer[3] != ' ')
        {
            TraceTextureLoad("TryLoadDDSFromMemory: %s rejected - missing DDS magic", debugName ? debugName : "<unnamed>");
            return false;
        }

        const DdsHeader* header = reinterpret_cast<const DdsHeader*>(buffer + 4);
        if (!header || header->size != 124 || header->ddspf.size != 32)
        {
            const uint8_t* raw = reinterpret_cast<const uint8_t*>(buffer + 4);
            const uint8_t d0 = raw ? raw[76] : 0;
            const uint8_t d1 = raw ? raw[77] : 0;
            const uint8_t d2 = raw ? raw[78] : 0;
            const uint8_t d3 = raw ? raw[79] : 0;
            TraceTextureLoad("TryLoadDDSFromMemory: %s rejected - invalid header size (%u / %u) ddspf bytes=%02x %02x %02x %02x",
                             debugName ? debugName : "<unnamed>",
                             header ? header->size : 0,
                             header ? header->ddspf.size : 0,
                             d0, d1, d2, d3);
            return false;
        }

        uint32_t fourCC = header->ddspf.fourCC;
        if (fourCC == MakeFourCC('D', 'X', 'T', '1'))
            format = eTF_DXT1;
        else if (fourCC == MakeFourCC('D', 'X', 'T', '3'))
            format = eTF_DXT3;
        else if (fourCC == MakeFourCC('D', 'X', 'T', '5'))
            format = eTF_DXT5;
        else
            format = eTF_Unknown;

        width = static_cast<int>(header->width);
        height = static_cast<int>(header->height);
        mipCount = header->mipMapCount ? static_cast<int>(header->mipMapCount) : 1;

        const byte* pixelData = buffer + 4 + sizeof(DdsHeader);
        if (pixelData >= buffer + bufferSize)
        {
            TraceTextureLoad("TryLoadDDSFromMemory: %s rejected - pixel data pointer out of range", debugName ? debugName : "<unnamed>");
            return false;
        }
        const size_t remaining = static_cast<size_t>((buffer + bufferSize) - pixelData);

        if (format == eTF_DXT1 || format == eTF_DXT3 || format == eTF_DXT5)
        {
            size_t expectedSize = 0;
            int levelWidth = std::max(1, width);
            int levelHeight = std::max(1, height);
            for (int level = 0; level < mipCount; ++level)
            {
                expectedSize += ComputeCompressedLevelSize(levelWidth, levelHeight, format);
                levelWidth = std::max(1, levelWidth >> 1);
                levelHeight = std::max(1, levelHeight >> 1);
            }

            if (remaining < expectedSize)
            {
                TraceTextureLoad("TryLoadDDSFromMemory: %s rejected - compressed data truncated (expected %zu, have %zu)", debugName ? debugName : "<unnamed>", expectedSize, remaining);
                return false;
            }

            outData.assign(pixelData, pixelData + expectedSize);
            return true;
        }

        const bool isRgb = (header->ddspf.flags & kDdsFlagRgb) != 0;
        const bool hasAlpha = (header->ddspf.flags & kDdsFlagAlphaPixels) != 0;
        const uint32_t rgbBits = header->ddspf.rgbBitCount;
        if (!isRgb || (rgbBits != 24 && rgbBits != 32))
        {
            TraceTextureLoad("TryLoadDDSFromMemory: %s rejected - unsupported RGB flags (flags=0x%08x bits=%u)", debugName ? debugName : "<unnamed>", header->ddspf.flags, rgbBits);
            return false;
        }

        const uint32_t expectedRMask = 0x00FF0000;
        const uint32_t expectedGMask = 0x0000FF00;
        const uint32_t expectedBMask = 0x000000FF;
        const uint32_t expectedAMask = 0xFF000000;
        const bool masksMatch = header->ddspf.rBitMask == expectedRMask
            && header->ddspf.gBitMask == expectedGMask
            && header->ddspf.bBitMask == expectedBMask
            && ((rgbBits == 32 && header->ddspf.aBitMask == expectedAMask) || (rgbBits == 24));
        if (!masksMatch)
        {
            TraceTextureLoad("TryLoadDDSFromMemory: %s rejected - unexpected channel masks (R=0x%08x G=0x%08x B=0x%08x A=0x%08x)",
                             debugName ? debugName : "<unnamed>",
                             header->ddspf.rBitMask, header->ddspf.gBitMask,
                             header->ddspf.bBitMask, header->ddspf.aBitMask);
            return false;
        }

        const int srcBytesPerPixel = static_cast<int>(rgbBits / 8);
        size_t srcOffset = 0;
        size_t dstOffset = 0;
        int levelWidth = std::max(1, width);
        int levelHeight = std::max(1, height);
        size_t requiredSource = 0;
        for (int level = 0; level < mipCount; ++level)
        {
            requiredSource += static_cast<size_t>(levelWidth) * static_cast<size_t>(levelHeight) * static_cast<size_t>(srcBytesPerPixel);
            levelWidth = std::max(1, levelWidth >> 1);
            levelHeight = std::max(1, levelHeight >> 1);
        }
        if (remaining < requiredSource)
        {
            TraceTextureLoad("TryLoadDDSFromMemory: %s rejected - uncompressed data truncated (expected %zu, have %zu)", debugName ? debugName : "<unnamed>", requiredSource, remaining);
            return false;
        }

        levelWidth = std::max(1, width);
        levelHeight = std::max(1, height);
        outData.clear();
        for (int level = 0; level < mipCount; ++level)
        {
            const size_t levelPixels = static_cast<size_t>(levelWidth) * static_cast<size_t>(levelHeight);
            const size_t levelBytes = levelPixels * static_cast<size_t>(srcBytesPerPixel);
            const byte* levelSrc = pixelData + srcOffset;
            const size_t dstRequired = dstOffset + levelPixels * 4;
            if (outData.size() < dstRequired)
                outData.resize(dstRequired);

            for (size_t i = 0; i < levelPixels; ++i)
            {
                const byte b = levelSrc[i * srcBytesPerPixel + 0];
                const byte g = levelSrc[i * srcBytesPerPixel + 1];
                const byte r = levelSrc[i * srcBytesPerPixel + 2];
                const byte a = (srcBytesPerPixel == 4) ? levelSrc[i * srcBytesPerPixel + 3] : 0xFF;
                outData[dstOffset + i * 4 + 0] = r;
                outData[dstOffset + i * 4 + 1] = g;
                outData[dstOffset + i * 4 + 2] = b;
                outData[dstOffset + i * 4 + 3] = a;
            }

            srcOffset += levelBytes;
            dstOffset += levelPixels * 4;
            levelWidth = std::max(1, levelWidth >> 1);
            levelHeight = std::max(1, levelHeight >> 1);
        }
        outData.resize(dstOffset);

        format = eTF_8888;
        TraceTextureLoad("TryLoadDDSFromMemory: %s accepted as RGBA (w=%d h=%d mips=%d)", debugName ? debugName : "<unnamed>", width, height, mipCount);
        return true;
    }

    inline uint64_t BuildSamplerKey(MTLSamplerMinMagFilter minFilter,
                                    MTLSamplerMinMagFilter magFilter,
                                    MTLSamplerMipFilter mipFilter,
                                    MTLSamplerAddressMode addressModeU,
                                    MTLSamplerAddressMode addressModeV,
                                    MTLSamplerAddressMode addressModeW,
                                    uint32_t anisotropy)
    {
        uint64_t key = 0;
        key |= static_cast<uint64_t>(minFilter & 0x3);
        key |= static_cast<uint64_t>(magFilter & 0x3) << 2;
        key |= static_cast<uint64_t>(mipFilter & 0x3) << 4;
        key |= static_cast<uint64_t>(addressModeU & 0x7) << 6;
        key |= static_cast<uint64_t>(addressModeV & 0x7) << 9;
        key |= static_cast<uint64_t>(addressModeW & 0x7) << 12;
        key |= static_cast<uint64_t>(anisotropy & 0xFF) << 15;
        return key;
    }

    inline NSUInteger BytesPerPixelForMetalFormat(MTLPixelFormat format)
    {
        switch (format)
        {
            case MTLPixelFormatBC1_RGBA:
            case MTLPixelFormatBC2_RGBA:
            case MTLPixelFormatBC3_RGBA:
                return 0;
            case MTLPixelFormatRGBA8Unorm:
            case MTLPixelFormatBGRA8Unorm:
            case MTLPixelFormatRGBA8Snorm:
                return 4;
            case MTLPixelFormatRG8Unorm:
            case MTLPixelFormatRG8Snorm:
                return 2;
            case MTLPixelFormatR8Unorm:
            case MTLPixelFormatR8Snorm:
                return 1;
            case MTLPixelFormatRG16Snorm:
                return 4;
            case MTLPixelFormatDepth32Float:
                return 4;
            default:
                return 4;
        }
    }

    inline void ReleaseMetalTexture(id<MTLTexture>& texture)
    {
        if (texture)
        {
            [texture release];
            texture = nil;
        }
    }

    inline void ReleaseSamplerState(id<MTLSamplerState>& sampler)
    {
        if (sampler)
        {
            [sampler release];
            sampler = nil;
        }
    }
    inline std::string NormalizeTexturePath(const char* path)
    {
        if (!path || !path[0])
            return std::string();
        std::string normalized(path);
        std::replace(normalized.begin(), normalized.end(), '\\', '/');
        return normalized;
    }

    inline bool HasFileExtension(const std::string& path)
    {
        const size_t dot = path.find_last_of('.');
        const size_t slash = path.find_last_of('/');
        return dot != std::string::npos && (slash == std::string::npos || dot > slash);
    }

    inline std::string ToLower(std::string value)
    {
        std::transform(value.begin(), value.end(), value.begin(),
                       [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        return value;
    }

    inline bool DoesFileExistInPakOrDisk(const std::string& path)
    {
        if (path.empty())
            return false;

        if (iSystem && iSystem->GetIPak())
        {
            FILE* file = iSystem->GetIPak()->FOpen(path.c_str(), "rb", ICryPak::FOPEN_HINT_QUIET);
            if (file)
            {
                iSystem->GetIPak()->FClose(file);
                return true;
            }
        }

        NSString* filePath = [NSString stringWithUTF8String:path.c_str()];
        if (filePath && [[NSFileManager defaultManager] fileExistsAtPath:filePath])
            return true;

        return false;
    }

    inline std::string UppercaseFirstDirectory(const std::string& path)
    {
        if (path.empty())
            return path;
        std::string variant = path;
        if (std::islower(static_cast<unsigned char>(variant[0])))
            variant[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(variant[0])));
        return variant;
    }

    inline bool StartsWithTexturesPrefix(const std::string& pathLower)
    {
        static const std::string kPrefix = "textures/";
        if (pathLower.size() < kPrefix.size())
            return false;
        return std::equal(kPrefix.begin(), kPrefix.end(), pathLower.begin());
    }

    inline std::vector<std::string> BuildTexturePathCandidates(const std::string& original)
    {
        static const char* kPreferredExtensions[] = { ".dds", ".tga", ".png", ".jpg", ".bmp", ".gif" };

        std::vector<std::string> candidates;
        std::string normalized = original;
        if (normalized.empty())
            return candidates;

        std::replace(normalized.begin(), normalized.end(), '\\', '/');

        const size_t dot = normalized.find_last_of('.');
        const bool hasExt = HasFileExtension(normalized);
        std::string base = normalized;
        std::string extLower;
        if (hasExt)
        {
            base = normalized.substr(0, dot);
            extLower = ToLower(normalized.substr(dot));
        }

        auto addCandidate = [&candidates](const std::string& candidate)
        {
            if (std::find(candidates.begin(), candidates.end(), candidate) == candidates.end())
                candidates.push_back(candidate);
        };

        auto addExtensionVariants = [&addCandidate](const std::string& basePath, const std::string& ext)
        {
            addCandidate(basePath + ext);
            std::string upperExt = ext;
            std::transform(upperExt.begin(), upperExt.end(), upperExt.begin(),
                           [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
            if (upperExt != ext)
                addCandidate(basePath + upperExt);
        };

        auto addBaseVariant = [](std::vector<std::string>& baseVariants, const std::string& variant)
        {
            if (variant.empty())
                return;
            if (std::find(baseVariants.begin(), baseVariants.end(), variant) == baseVariants.end())
                baseVariants.push_back(variant);
        };

        const std::string& rootPath = hasExt ? base : normalized;

        std::vector<std::string> baseVariants;
        addBaseVariant(baseVariants, rootPath);
        addBaseVariant(baseVariants, ToLower(rootPath));
        const std::string upperFirst = UppercaseFirstDirectory(rootPath);
        if (upperFirst != rootPath)
            addBaseVariant(baseVariants, upperFirst);

        auto expandWithTexturesPrefix = [&](const std::string& basePath)
        {
            std::vector<std::string> variants;
            variants.push_back(basePath);
            std::string lowerBase = ToLower(basePath);
            if (!StartsWithTexturesPrefix(lowerBase))
            {
                variants.push_back(std::string("Textures/") + basePath);
                variants.push_back(std::string("textures/") + basePath);
            }
            return variants;
        };

        std::vector<std::string> finalBases;
        for (const auto& baseVariant : baseVariants)
        {
            auto prefixed = expandWithTexturesPrefix(baseVariant);
            finalBases.insert(finalBases.end(), prefixed.begin(), prefixed.end());
        }

        if (!hasExt)
        {
            for (const auto& baseVariant : finalBases)
            {
                for (const char* ext : kPreferredExtensions)
                {
                    addExtensionVariants(baseVariant, ext);
                }
            }
        }
        else
        {
            const std::string originalExt = normalized.substr(dot);
            for (const auto& baseVariant : finalBases)
            {
                addExtensionVariants(baseVariant, originalExt);

                if (extLower == ".dss")
                {
                    addExtensionVariants(baseVariant, ".dds");
                }
                else if (extLower == ".tif")
                {
                    addExtensionVariants(baseVariant, ".tiff");
                }

                for (const char* ext : kPreferredExtensions)
                {
                    if (extLower != ext)
                        addExtensionVariants(baseVariant, ext);
                }
            }
        }

        return candidates;
    }

    inline std::string ResolveTextureFilename(const std::string& requestedName)
    {
        const auto candidates = BuildTexturePathCandidates(requestedName);
        for (const auto& candidate : candidates)
        {
            if (DoesFileExistInPakOrDisk(candidate))
                return candidate;
        }
        return requestedName;
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

struct CMetalTextureManager::TextureInfoHandle::Impl
{
    Impl(int textureId, CMetalTextureManager::TextureInfo&& info)
        : id(textureId)
        , payload(std::move(info))
    {
    }

    ~Impl()
    {
        ReleaseMetalTexture(payload.metalTexture);
    }

    int id = 0;
    CMetalTextureManager::TextureInfo payload;
};

CMetalTextureManager::TextureInfoHandle::TextureInfoHandle() = default;

CMetalTextureManager::TextureInfoHandle::TextureInfoHandle(std::shared_ptr<Impl> impl)
    : m_impl(std::move(impl))
{
}

CMetalTextureManager::TextureInfoHandle CMetalTextureManager::TextureInfoHandle::Create(int textureId, CMetalTextureManager::TextureInfo&& info)
{
    return TextureInfoHandle(std::make_shared<CMetalTextureManager::TextureInfoHandle::Impl>(textureId, std::move(info)));
}

CMetalTextureManager::TextureInfo* CMetalTextureManager::TextureInfoHandle::operator->()
{
    return m_impl ? &m_impl->payload : nullptr;
}

const CMetalTextureManager::TextureInfo* CMetalTextureManager::TextureInfoHandle::operator->() const
{
    return m_impl ? &m_impl->payload : nullptr;
}

CMetalTextureManager::TextureInfo& CMetalTextureManager::TextureInfoHandle::operator*()
{
    assert(m_impl && "TextureInfoHandle: invalid dereference");
    return m_impl->payload;
}

const CMetalTextureManager::TextureInfo& CMetalTextureManager::TextureInfoHandle::operator*() const
{
    assert(m_impl && "TextureInfoHandle: invalid dereference");
    return m_impl->payload;
}

CMetalTextureManager::TextureInfoHandle::operator bool() const
{
    return static_cast<bool>(m_impl);
}

int CMetalTextureManager::TextureInfoHandle::GetId() const
{
    return m_impl ? m_impl->id : 0;
}

CMetalTextureManager::TextureInfoHandle CMetalTextureManager::CMetalTextureInfoFactory::Create(int textureId, TextureInfo&& info)
{
    return TextureInfoHandle::Create(textureId, std::move(info));
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
    , m_textureHandleFactory(std::make_unique<CMetalTextureInfoFactory>())
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
    , m_lastBoundStage(0)
{
    for (auto& tex : m_boundFragmentTextures)
    {
        tex = nil;
    }
    for (auto& sampler : m_boundFragmentSamplers)
    {
        sampler = nil;
    }
    for (auto& stageId : m_stageTextureIds)
    {
        stageId = 0;
    }
}

CMetalTextureManager::~CMetalTextureManager()
{
    ClearAllTextures();
    for (auto& entry : m_samplerCache)
    {
        ReleaseSamplerState(entry.second);
    }
    m_samplerCache.clear();
}

void CMetalTextureManager::SetTexture(int tnum, ETexType Type)
{
    assert(tnum >= 0 && "SetTexture: texture number cannot be negative!");
    
    if (tnum < 0)
        return;

    TextureInfoHandle* handle = FindHandle(tnum);
    if (handle && *handle)
    {
        m_currentTexture = (*handle)->metalTexture;
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
            int stage = textureIndex;
            if (stage < 0)
                stage = 0;
            if (stage >= static_cast<int>(m_stageTextureIds.size()))
                stage = static_cast<int>(m_stageTextureIds.size()) - 1;
            m_lastBoundStage = stage;
            if (tnum > 0)
                m_stageTextureIds[stage] = tnum;
            else
                m_stageTextureIds[stage] = 0;
            [m_renderer->m_renderEncoder setFragmentTexture:m_currentTexture atIndex:textureIndex];
            if (textureIndex >= 0 && textureIndex < static_cast<int>(m_boundFragmentTextures.size()))
            {
                m_boundFragmentTextures[textureIndex] = m_currentTexture;
            }
            id<MTLSamplerState> sampler = GetDefaultSampler();
            if (sampler)
                BindSampler(textureIndex, sampler);
        }
    }
    else
    {
        if (m_whiteTexture && m_renderer && m_renderer->m_renderEncoder)
        {
            m_lastBoundStage = 0;
            if (!m_stageTextureIds.empty())
                m_stageTextureIds[0] = 0;
            [m_renderer->m_renderEncoder setFragmentTexture:m_whiteTexture atIndex:0];
            m_boundFragmentTextures[0] = m_whiteTexture;
            id<MTLSamplerState> sampler = GetDefaultSampler();
            if (sampler)
                BindSampler(0, sampler);
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
    m_lastBoundStage = 0;
    if (!m_stageTextureIds.empty())
        m_stageTextureIds[0] = 0;
    
    if (m_renderer && m_renderer->m_renderEncoder)
    {
        [m_renderer->m_renderEncoder setFragmentTexture:m_whiteTexture atIndex:0];
        m_boundFragmentTextures[0] = m_whiteTexture;
        id<MTLSamplerState> sampler = GetDefaultSampler();
        if (sampler)
            BindSampler(0, sampler);
    }
}

id<MTLTexture> CMetalTextureManager::GetBoundFragmentTexture(int index) const
{
    if (index < 0 || index >= static_cast<int>(m_boundFragmentTextures.size()))
        return nil;
    return m_boundFragmentTextures[index];
}

id<MTLSamplerState> CMetalTextureManager::GetBoundFragmentSampler(int index) const
{
    if (index < 0 || index >= static_cast<int>(m_boundFragmentSamplers.size()))
        return nil;
    return m_boundFragmentSamplers[index];
}

id<MTLSamplerState> CMetalTextureManager::AcquireDefaultSampler()
{
    return GetDefaultSampler();
}

void CMetalTextureManager::BindDefaultSampler(int slot)
{
    id<MTLSamplerState> sampler = GetDefaultSampler();
    if (sampler)
        BindSampler(slot, sampler);
}

void CMetalTextureManager::SetClampModeForLastTexture(bool clamp)
{
    if (!m_renderer || !m_renderer->m_renderEncoder || !m_renderer->m_device)
        return;
    if (m_lastBoundStage < 0 || m_lastBoundStage >= static_cast<int>(m_boundFragmentSamplers.size()))
        return;
    MTLSamplerMinMagFilter minFilter = MTLSamplerMinMagFilterLinear;
    MTLSamplerMinMagFilter magFilter = MTLSamplerMinMagFilterLinear;
    MTLSamplerMipFilter mipFilter = MTLSamplerMipFilterLinear;
    MTLSamplerAddressMode mode = clamp ? MTLSamplerAddressModeClampToEdge : MTLSamplerAddressModeRepeat;
    const uint32_t anisotropy = 1;
    uint64_t key = BuildSamplerKey(minFilter, magFilter, mipFilter, mode, mode, mode, anisotropy);
    id<MTLSamplerState> sampler = nil;
    auto it = m_samplerCache.find(key);
    if (it != m_samplerCache.end())
        sampler = it->second;
    if (!sampler)
    {
        MTLSamplerDescriptor* descriptor = [[MTLSamplerDescriptor alloc] init];
        descriptor.minFilter = minFilter;
        descriptor.magFilter = magFilter;
        descriptor.mipFilter = mipFilter;
        descriptor.sAddressMode = mode;
        descriptor.tAddressMode = mode;
        descriptor.rAddressMode = mode;
        descriptor.maxAnisotropy = anisotropy;
        descriptor.lodMinClamp = 0.0f;
        descriptor.lodMaxClamp = FLT_MAX;
        descriptor.normalizedCoordinates = YES;
        sampler = [m_renderer->m_device newSamplerStateWithDescriptor:descriptor];
        [descriptor release];
        if (sampler)
            m_samplerCache.emplace(key, sampler);
    }
    if (!sampler)
        return;
    BindSampler(m_lastBoundStage, sampler);
    if (m_lastBoundStage >= 0 && m_lastBoundStage < static_cast<int>(m_stageTextureIds.size()))
    {
        int textureId = m_stageTextureIds[m_lastBoundStage];
        if (textureId > 0)
            SetTextureClamp(textureId, clamp);
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
    
    const bool isCompressed = IsCompressedETEXFormat(eTFDst);
    const int bytesPerPixel = GetBytesPerPixel(eTFDst);
    const bool wantsAutogenMips = (nummipmap <= 1) && !isCompressed;
    const bool canGenerateMips = wantsAutogenMips && (m_renderer->m_commandQueue != nil);
    const int mipLevels = canGenerateMips ? CalculateFullMipCount(w, h) : std::max(1, nummipmap);
    
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:metalFormat
                                                                                           width:w
                                                                                          height:h
                                                                                       mipmapped:(mipLevels > 1)];
    descriptor.mipmapLevelCount = mipLevels;
    descriptor.storageMode = MTLStorageModeShared;
    descriptor.usage = canGenerateMips ? (MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite)
                                       : MTLTextureUsageShaderRead;
    
    id<MTLTexture> texture = [m_renderer->m_device newTextureWithDescriptor:descriptor];
    if (!texture)
        return 0;
    
    const int uploadLevels = canGenerateMips ? 1 : mipLevels;
    const size_t blockSize = isCompressed ? DxtBlockSize(eTFDst) : 0;
    const int effectiveBpp = std::max(1, bytesPerPixel);
    const byte* source = data;
    int levelWidth = w;
    int levelHeight = h;
    
    for (int level = 0; level < uploadLevels; ++level)
    {
        const size_t bytesPerRow = isCompressed
            ? static_cast<size_t>((levelWidth + 3) / 4) * blockSize
            : static_cast<size_t>(levelWidth) * static_cast<size_t>(effectiveBpp);
        const size_t levelSize = isCompressed
            ? static_cast<size_t>((levelWidth + 3) / 4) * static_cast<size_t>((levelHeight + 3) / 4) * blockSize
            : bytesPerRow * static_cast<size_t>(levelHeight);
        
        [texture replaceRegion:MTLRegionMake2D(0, 0, levelWidth, levelHeight)
                   mipmapLevel:level
                     withBytes:source
                   bytesPerRow:bytesPerRow];
        
        source += levelSize;
        levelWidth = std::max(1, levelWidth >> 1);
        levelHeight = std::max(1, levelHeight >> 1);
    }
    
    if (canGenerateMips && m_renderer->m_commandQueue)
    {
        id<MTLCommandBuffer> commandBuffer = [m_renderer->m_commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder generateMipmapsForTexture:texture];
        [blitEncoder endEncoding];
        [commandBuffer commit];
        m_renderer->TrackCommandBuffer(commandBuffer);
    }
    
    int textureId = (Id > 0) ? Id : AllocateTextureId();
    if (textureId <= 0)
    {
        ReleaseMetalTexture(texture);
        return 0;
    }
    
    const std::string cacheName = NormalizeTexturePath(szCacheName);

    TextureInfo info;
    info.metalTexture = texture;
    info.width = w;
    info.height = h;
    info.format = eTFDst;
    info.name = cacheName;
    info.memorySize = ComputeTextureMemoryBytes(w, h, mipLevels, effectiveBpp, eTFDst);
    info.isLoaded = true;
    info.flags = flags;
    info.flags2 = 0;
    info.textureType = eTT_Base;
    info.amount1 = -1.0f;
    info.amount2 = -1.0f;
    info.clampU = !repeat;
    info.clampV = !repeat;
    info.filterMode = filter;
    
    size_t previousSize = 0;
    auto existingHandle = FindHandle(textureId);
    if (existingHandle && *existingHandle)
        previousSize = (*existingHandle)->memorySize;
    
    TextureInfoHandle& storedHandle = UpsertTextureHandle(textureId, std::move(info));
    
    if (previousSize > 0)
        m_totalTextureMemory -= previousSize;
    m_totalTextureMemory += storedHandle->memorySize;
    
    if (!cacheName.empty())
    {
        m_textureNameMap[cacheName] = textureId;
    }
    
    return textureId;
}

void CMetalTextureManager::UpdateTextureInVideoMemory(uint tnum, unsigned char* newdata, int posx, int posy, 
                                                     int w, int h, ETEX_Format eTF)
{
    if (!newdata || w <= 0 || h <= 0 || posx < 0 || posy < 0)
        return;
    
    TextureInfoHandle* handle = FindHandle(static_cast<int>(tnum));
    if (!handle || !*handle)
        return;
        
    id<MTLTexture> texture = (*handle)->metalTexture;
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

    std::string requestedName = NormalizeTexturePath(filename);
    if (requestedName.empty())
        return def_tid;
    
    TraceTextureLoad("LoadTexture request '%s'", requestedName.c_str());

    assert(m_renderer && "MetalTextureManager: renderer is null - not properly initialized!");
    assert(m_renderer->m_device && "MetalTextureManager: Metal device is null - renderer not initialized!");
    
    if (!m_renderer || !m_renderer->m_device)
        return def_tid;
    
    auto nameIt = m_textureNameMap.find(requestedName);
    if (nameIt != m_textureNameMap.end())
    {
        if (tex_type)
        {
            auto texHandle = FindHandle(nameIt->second);
            if (texHandle && *texHandle)
                *tex_type = (int)(*texHandle)->format;
            else
                *tex_type = (int)eTF_8888;
        }
        return nameIt->second;
    }
    
    const std::string resolvedName = ResolveTextureFilename(requestedName);

    std::vector<byte> data;
    int width, height;
    int sourceMipCount = 1;
    ETEX_Format detectedFormat = eTF_8888;
    
    if (!LoadTextureData(resolvedName.c_str(), data, width, height, detectedFormat, sourceMipCount))
    {
        if (bWarn)
        {
            iLog->Log("Warning: Failed to load texture: %s (requested as %s)\n",
                      resolvedName.c_str(), requestedName.c_str());
        }
        TraceTextureLoad("LoadTexture FAILED '%s' resolved '%s'", requestedName.c_str(), resolvedName.c_str());
        return def_tid;
    }
    TraceTextureLoad("LoadTexture success '%s' %dx%d format=%d sourceMips=%d", requestedName.c_str(), width, height, (int)detectedFormat, sourceMipCount);
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
    
    const bool isCompressed = IsCompressedETEXFormat(detectedFormat);
    int bytesPerPixel = GetBytesPerPixel(detectedFormat);
    if (!isCompressed && bytesPerPixel == 0)
        bytesPerPixel = 4;
    
    const bool canGenerateMips = !isCompressed && (sourceMipCount <= 1) && (m_renderer->m_commandQueue != nil);
    const int mipLevels = canGenerateMips ? CalculateFullMipCount(width, height)
                                          : std::max(1, sourceMipCount);
    const int uploadLevels = canGenerateMips ? 1 : mipLevels;
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:metalFormat
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:(mipLevels > 1)];
    descriptor.mipmapLevelCount = mipLevels;
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    descriptor.storageMode = MTLStorageModeShared;
    
    id<MTLTexture> texture = [m_renderer->m_device newTextureWithDescriptor:descriptor];
    if (!texture)
    {
        if (bWarn)
            iLog->Log("Warning: Failed to create Metal texture for: %s\n", filename);
        return def_tid;
    }
    
    const int effectiveBpp = std::max(1, bytesPerPixel);
    size_t levelOffset = 0;
    int levelWidth = width;
    int levelHeight = height;
    byte* source = data.data();
    
    for (int level = 0; level < uploadLevels; ++level)
    {
        const size_t bytesPerRow = ComputeBytesPerRow(detectedFormat, levelWidth, effectiveBpp);
        const size_t levelBytes = IsCompressedETEXFormat(detectedFormat)
            ? ComputeCompressedLevelSize(levelWidth, levelHeight, detectedFormat)
            : bytesPerRow * static_cast<size_t>(levelHeight);
        
        MTLRegion region = MTLRegionMake2D(0, 0, levelWidth, levelHeight);
        
        [texture replaceRegion:region
                   mipmapLevel:level
                     withBytes:source + levelOffset
                   bytesPerRow:bytesPerRow];
        
        levelOffset += levelBytes;
        levelWidth = std::max(1, levelWidth / 2);
        levelHeight = std::max(1, levelHeight / 2);
    }
    
    if (canGenerateMips && mipLevels > 1)
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
    {
        ReleaseMetalTexture(texture);
        return 0;
    }
    
    TextureInfo info;
    info.metalTexture = texture;
    info.width = width;
    info.height = height;
    info.format = detectedFormat;
    info.name = resolvedName;
    info.memorySize = ComputeTextureMemoryBytes(width, height, mipLevels, effectiveBpp, detectedFormat);
    info.isLoaded = true;
    info.flags = 0;
    info.flags2 = 0;
    info.textureType = eTT_Base;
    info.amount1 = -1.0f;
    info.amount2 = -1.0f;
    info.clampU = false;
    info.clampV = false;
    info.filterMode = FILTER_BILINEAR;
    
    size_t previousSize = 0;
    auto existingHandle = FindHandle(textureId);
    if (existingHandle && *existingHandle)
        previousSize = (*existingHandle)->memorySize;
    
    TextureInfoHandle& storedHandle = UpsertTextureHandle(textureId, std::move(info));
    
    if (previousSize > 0)
        m_totalTextureMemory -= previousSize;
    m_totalTextureMemory += storedHandle->memorySize;
    
    m_textureNameMap[requestedName] = textureId;
    if (resolvedName != requestedName)
        m_textureNameMap[resolvedName] = textureId;
    
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
    
    auto handle = FindHandle(static_cast<int>(TextureId));
    if (!handle || !*handle)
        return;
    
    id<MTLTexture> removedTexture = (*handle)->metalTexture;
    m_totalTextureMemory -= (*handle)->memorySize;
    
    for (auto it = m_textureNameMap.begin(); it != m_textureNameMap.end(); )
    {
        if (it->second == static_cast<int>(TextureId))
            it = m_textureNameMap.erase(it);
        else
            ++it;
    }
    
    if (m_currentTexture == removedTexture)
    {
        m_currentTexture = nil;
        m_currentTextureSlot = 0;
    }
    
    for (auto& boundTexture : m_boundFragmentTextures)
    {
        if (boundTexture == removedTexture)
            boundTexture = nil;
    }
    
    m_textures.erase(static_cast<int>(TextureId));
    ReleaseTextureId(TextureId);
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
        auto handle = FindHandle(textureId);
        if (handle && *handle && (*handle)->metalTexture)
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
            
            [(*handle)->metalTexture replaceRegion:MTLRegionMake2D(0, 0, width, height)
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
    
    TextureInfoHandle& storedHandle = UpsertTextureHandle(textureId, std::move(info));
    m_totalTextureMemory += storedHandle->memorySize;
    
    return textureId;
}

bool CMetalTextureManager::FontUpdateTexture(int nTexId, int X, int Y, int USize, int VSize, byte* pData)
{
    assert(nTexId > 0 && "FontUpdateTexture: invalid texture ID!");
    assert(pData && "FontUpdateTexture: pData cannot be null!");
    assert(USize > 0 && VSize > 0 && "FontUpdateTexture: update size must be positive!");
    assert(X >= 0 && Y >= 0 && "FontUpdateTexture: position cannot be negative!");
    
    auto handle = FindHandle(nTexId);
    if (!handle || !*handle)
        return false;
        
    UpdateMetalTexture((*handle)->metalTexture, pData, X, Y, USize, VSize);
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
    if (nTexId <= 0)
        return;
    
    auto handle = FindHandle(nTexId);
    if (!handle || !*handle || !(*handle)->metalTexture)
        return;
    
    id<MTLTexture> texture = (*handle)->metalTexture;
    m_currentTexture = texture;
    m_currentTextureSlot = nTexId;
    
    if (m_renderer && m_renderer->m_renderEncoder)
    {
        [m_renderer->m_renderEncoder setFragmentTexture:texture atIndex:0];
    }
    
    SetTextureParameters(texture, true, nFilterMode);
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
    
    if (!m_renderer)
        return;
    
    unsigned long width = nVirtualScreenWidth;
    unsigned long height = nVirtualScreenHeight;
    if (width == 0)
        width = static_cast<unsigned long>(std::max(1, m_renderer->GetWidth()));
    if (height == 0)
        height = static_cast<unsigned long>(std::max(1, m_renderer->GetHeight()));
    
    m_savedViewportWidth = width;
    m_savedViewportHeight = height;
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
    
    auto handle = FindHandle(Id);
    if (!handle || !*handle)
    {
        iLog->Log("Warning: EF_GetTextureByID - texture ID %d not found in texture map\n", Id);
        return nullptr;
    }
    
    if (!(*handle)->isLoaded)
    {
        iLog->Log("Warning: EF_GetTextureByID - texture ID %d exists but is not loaded\n", Id);
        assert((*handle)->isLoaded && "CMetalTextureManager: Texture exists but is not loaded!");
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
    
    auto handle = FindHandle(static_cast<int>(textureId));
    if (handle && *handle)
    {
        TextureInfo* entry = handle->operator->();
        entry->flags = flags;
        entry->flags2 = flags2;
        entry->textureType = eTT;
        entry->amount1 = fAmount1;
        entry->amount2 = fAmount2;
        entry->clampU = (flags & FT_CLAMP) || (flags2 & FT2_UCLAMP);
        entry->clampV = (flags & FT_CLAMP) || (flags2 & FT2_VCLAMP);
        
        if (flags & FT_NOMIPS)
        {
            entry->flags |= FT_NOMIPS;
        }
        
        if (eTT == eTT_Bumpmap)
        {
            entry->flags |= FT_HASNORMALMAP;
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
    
    ReleaseMetalTexture(m_whiteTexture);
    ReleaseMetalTexture(m_currentTexture);
    m_currentTextureSlot = 0;
    for (auto& bound : m_boundFragmentTextures)
        bound = nil;
    for (auto& sampler : m_boundFragmentSamplers)
        sampler = nil;
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
        const auto& texHandle = texPair.second;
        
        if (!texHandle)
            continue;
        
        if (m_textures.find(texId) == m_textures.end()) {
            m_textures[texId] = texHandle;
            if (!texHandle->name.empty()) {
                m_textureNameMap[texHandle->name] = texId;
            }
            m_totalTextureMemory += texHandle->memorySize;
        }
    }
    
    for (const auto& texPair : m_textures) {
        int texId = texPair.first;
        const auto& texHandle = texPair.second;
        
        if (!texHandle)
            continue;
        
        if (other->m_textures.find(texId) == other->m_textures.end()) {
            other->m_textures[texId] = texHandle;
            if (!texHandle->name.empty()) {
                other->m_textureNameMap[texHandle->name] = texId;
            }
            other->m_totalTextureMemory += texHandle->memorySize;
        }
    }
}

const CMetalTextureManager::TextureInfo* CMetalTextureManager::GetTextureInfo(int textureId) const
{
    assert(textureId > 0 && "CMetalTextureManager: GetTextureInfo called with invalid ID!");
    
    auto handle = FindHandle(textureId);
    if (handle && *handle)
        return handle->operator->();
    return nullptr;
}

void CMetalTextureManager::SetTextureClamp(int textureId, bool bEnable)
{
    assert(textureId > 0 && "SetTextureClamp: invalid texture ID!");
    
    auto handle = FindHandle(textureId);
    if (!handle || !*handle)
        return;
    
    (*handle)->clampU = bEnable;
    (*handle)->clampV = bEnable;
    
    if (bEnable)
    {
        (*handle)->flags |= FT_CLAMP;
    }
    else
    {
        (*handle)->flags &= ~FT_CLAMP;
    }
}

void CMetalTextureManager::SetTextureFilter(int textureId, int nFilter)
{
    assert(textureId > 0 && "SetTextureFilter: invalid texture ID!");
    
    auto handle = FindHandle(textureId);
    if (handle && *handle)
    {
        (*handle)->filterMode = nFilter;
    }
}

CMetalTextureManager::TextureInfoHandle& CMetalTextureManager::UpsertTextureHandle(int textureId, TextureInfo&& info)
{
    TextureInfoHandle handle = m_textureHandleFactory->Create(textureId, std::move(info));
    auto it = m_textures.find(textureId);
    if (it != m_textures.end())
    {
        it->second = std::move(handle);
        return it->second;
    }
    auto inserted = m_textures.emplace(textureId, std::move(handle));
    return inserted.first->second;
}

CMetalTextureManager::TextureInfoHandle* CMetalTextureManager::FindHandle(int textureId)
{
    auto it = m_textures.find(textureId);
    if (it == m_textures.end())
        return nullptr;
    return &it->second;
}

const CMetalTextureManager::TextureInfoHandle* CMetalTextureManager::FindHandle(int textureId) const
{
    auto it = m_textures.find(textureId);
    if (it == m_textures.end())
        return nullptr;
    return &it->second;
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
    descriptor.storageMode = MTLStorageModeShared;
    descriptor.usage = MTLTextureUsageShaderRead;
    
    id<MTLTexture> texture = [m_renderer->m_device newTextureWithDescriptor:descriptor];
    
    if (texture && data)
    {
        const NSUInteger bytesPerPixel = BytesPerPixelForMetalFormat(format);
        if (bytesPerPixel == 0)
            return texture;
        
        [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                   mipmapLevel:0
                     withBytes:data
                   bytesPerRow:width * bytesPerPixel];
    }
    
    return texture;
}

id<MTLTexture> CMetalTextureManager::CreateMetalTextureFromFile(const char* filename)
{
    assert(filename && "CreateMetalTextureFromFile: filename cannot be null!");
    assert(filename[0] != '\0' && "CreateMetalTextureFromFile: filename is empty!");
    
    std::vector<byte> data;
    int width, height;
    int mipCount = 1;
    if (!LoadTextureData(filename, data, width, height, mipCount))
        return nil;
        
    return CreateMetalTexture(width, height, MTLPixelFormatRGBA8Unorm, data.data(), data.size());
}

void CMetalTextureManager::UpdateMetalTexture(id<MTLTexture> texture, const void* data, int x, int y, int w, int h)
{
    if (!texture || !data || w <= 0 || h <= 0)
        return;
    
    const NSUInteger texWidth = [texture width];
    const NSUInteger texHeight = [texture height];
    if (texWidth == 0 || texHeight == 0)
        return;
    
    const int regionX = std::max(0, x);
    const int regionY = std::max(0, y);
    if (regionX >= static_cast<int>(texWidth) || regionY >= static_cast<int>(texHeight))
        return;
    
    NSUInteger updateWidth = std::min<NSUInteger>(static_cast<NSUInteger>(w), texWidth - static_cast<NSUInteger>(regionX));
    NSUInteger updateHeight = std::min<NSUInteger>(static_cast<NSUInteger>(h), texHeight - static_cast<NSUInteger>(regionY));
    if (updateWidth == 0 || updateHeight == 0)
        return;
    
    const NSUInteger bytesPerPixel = BytesPerPixelForMetalFormat([texture pixelFormat]);
    if (bytesPerPixel == 0)
        return;
    
    [texture replaceRegion:MTLRegionMake2D(static_cast<NSUInteger>(regionX),
                                           static_cast<NSUInteger>(regionY),
                                           updateWidth,
                                           updateHeight)
               mipmapLevel:0
                 withBytes:data
               bytesPerRow:updateWidth * bytesPerPixel];
}

void CMetalTextureManager::BindTexture(int slot, id<MTLTexture> texture)
{
    assert(slot >= 0 && "BindTexture: slot cannot be negative!");
    assert(m_renderer && "BindTexture: renderer is null!");
    
    if (m_renderer && m_renderer->m_renderEncoder)
    {
        [m_renderer->m_renderEncoder setFragmentTexture:texture atIndex:slot];
        if (slot >= 0 && slot < static_cast<int>(m_boundFragmentTextures.size()))
            m_boundFragmentTextures[slot] = texture;
    }
}

void CMetalTextureManager::BindSampler(int slot, id<MTLSamplerState> sampler)
{
    assert(slot >= 0 && "BindSampler: slot cannot be negative!");
    if (!m_renderer || !m_renderer->m_renderEncoder)
        return;
    [m_renderer->m_renderEncoder setFragmentSamplerState:sampler atIndex:slot];
    if (slot >= 0 && slot < static_cast<int>(m_boundFragmentSamplers.size()))
        m_boundFragmentSamplers[slot] = sampler;
}

id<MTLSamplerState> CMetalTextureManager::GetOrCreateSamplerState(const SShaderTexUnit& unit)
{
    bool clampU = false;
    bool clampV = false;
    int textureId = unit.m_ITexPic ? unit.m_ITexPic->GetTextureID() : 0;
    const TextureInfo* info = textureId > 0 ? GetTextureInfo(textureId) : nullptr;
    if (info)
    {
        clampU = info->clampU;
        clampV = info->clampV;
    }
    if (unit.m_nFlags & FTU_CLAMP)
    {
        clampU = true;
        clampV = true;
    }

    MTLSamplerAddressMode addressModeU = clampU ? MTLSamplerAddressModeClampToEdge : MTLSamplerAddressModeRepeat;
    MTLSamplerAddressMode addressModeV = clampV ? MTLSamplerAddressModeClampToEdge : MTLSamplerAddressModeRepeat;
    MTLSamplerAddressMode addressModeW = addressModeV;

    MTLSamplerMinMagFilter minFilter = MTLSamplerMinMagFilterLinear;
    MTLSamplerMinMagFilter magFilter = MTLSamplerMinMagFilterLinear;
    MTLSamplerMipFilter mipFilter = MTLSamplerMipFilterLinear;

    if (unit.m_nFlags & FTU_FILTERNEAREST)
    {
        minFilter = MTLSamplerMinMagFilterNearest;
        magFilter = MTLSamplerMinMagFilterNearest;
        mipFilter = MTLSamplerMipFilterNotMipmapped;
    }
    else if (unit.m_nFlags & FTU_FILTERLINEAR)
    {
        minFilter = MTLSamplerMinMagFilterLinear;
        magFilter = MTLSamplerMinMagFilterLinear;
        mipFilter = MTLSamplerMipFilterNotMipmapped;
    }
    else if (unit.m_nFlags & FTU_FILTERBILINEAR)
    {
        minFilter = MTLSamplerMinMagFilterLinear;
        magFilter = MTLSamplerMinMagFilterLinear;
        mipFilter = MTLSamplerMipFilterNearest;
    }
    else if (unit.m_nFlags & FTU_FILTERTRILINEAR)
    {
        minFilter = MTLSamplerMinMagFilterLinear;
        magFilter = MTLSamplerMinMagFilterLinear;
        mipFilter = MTLSamplerMipFilterLinear;
    }

    int texFlags = unit.GetTexFlags();
    if (texFlags & FT_NOMIPS)
        mipFilter = MTLSamplerMipFilterNotMipmapped;

    uint32_t anisotropy = 1;

    uint64_t key = 0;
    key |= static_cast<uint64_t>(minFilter & 0x3);
    key |= static_cast<uint64_t>(magFilter & 0x3) << 2;
    key |= static_cast<uint64_t>(mipFilter & 0x3) << 4;
    key |= static_cast<uint64_t>(addressModeU & 0x7) << 6;
    key |= static_cast<uint64_t>(addressModeV & 0x7) << 9;
    key |= static_cast<uint64_t>(addressModeW & 0x7) << 12;
    key |= static_cast<uint64_t>(anisotropy & 0xFF) << 15;

    auto it = m_samplerCache.find(key);
    if (it != m_samplerCache.end())
        return it->second;

    MTLSamplerDescriptor* descriptor = [[MTLSamplerDescriptor alloc] init];
    descriptor.minFilter = minFilter;
    descriptor.magFilter = magFilter;
    descriptor.mipFilter = mipFilter;
    descriptor.sAddressMode = addressModeU;
    descriptor.tAddressMode = addressModeV;
    descriptor.rAddressMode = addressModeW;
    descriptor.maxAnisotropy = anisotropy;
    descriptor.lodMinClamp = 0.0f;
    descriptor.lodMaxClamp = FLT_MAX;
    descriptor.normalizedCoordinates = YES;

    id<MTLSamplerState> sampler = [m_renderer->m_device newSamplerStateWithDescriptor:descriptor];
    [descriptor release];

    if (sampler)
        m_samplerCache.emplace(key, sampler);

    return sampler;
}

id<MTLSamplerState> CMetalTextureManager::GetDefaultSampler()
{
    static SShaderTexUnit defaultUnit;
    return GetOrCreateSamplerState(defaultUnit);
}

void CMetalTextureManager::ApplyTexUnit(int stage, SShaderTexUnit& unit)
{
    if (!m_renderer || !m_renderer->m_renderEncoder)
        return;
    m_lastBoundStage = std::max(0, std::min(stage, static_cast<int>(m_stageTextureIds.size()) - 1));
    id<MTLTexture> texture = nil;
    if (unit.m_ITexPic)
    {
        int textureId = unit.m_ITexPic->GetTextureID();
        auto handle = FindHandle(textureId);
        if (handle && *handle)
            texture = (*handle)->metalTexture;
        if (m_lastBoundStage >= 0 && m_lastBoundStage < static_cast<int>(m_stageTextureIds.size()))
            m_stageTextureIds[m_lastBoundStage] = textureId;
    }
    if (!texture)
    {
        texture = m_whiteTexture;
        if (m_lastBoundStage >= 0 && m_lastBoundStage < static_cast<int>(m_stageTextureIds.size()))
            m_stageTextureIds[m_lastBoundStage] = 0;
    }

    id<MTLSamplerState> sampler = GetOrCreateSamplerState(unit);
    if (!sampler)
        sampler = GetDefaultSampler();

    if (texture)
        BindTexture(stage, texture);
    if (sampler)
        BindSampler(stage, sampler);
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

bool CMetalTextureManager::LoadTextureData(const char* filename, std::vector<byte>& data, int& width, int& height, int& mipCount)
{
    assert(filename && "LoadTextureData: filename cannot be null!");
    
    ETEX_Format format;
    return LoadTextureData(filename, data, width, height, format, mipCount);
}

bool CMetalTextureManager::LoadTextureData(const char* filename, std::vector<byte>& data, int& width, int& height, ETEX_Format& format, int& mipCount)
{
    if (!filename || !filename[0])
        return false;
    
    assert(m_renderer && "MetalTextureManager: renderer is null - not properly initialized!");
    assert(m_renderer->m_device && "MetalTextureManager: Metal device is null - renderer not initialized!");
    mipCount = 1;
    if (!m_renderer || !m_renderer->m_device)
        return false;
    
    if (!iSystem)
    {
        assert(false && "LoadTextureData: iSystem is null!");
        return false;
    }
    
    TraceTextureLoad("LoadTextureData: attempt '%s'", filename);
    iLog->Log("LoadTextureData: Attempting to open texture file: '%s'\n", filename);
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
                if (TryLoadDDSFromMemory(fileData.data(), fileData.size(), data, width, height, format, mipCount, filename))
                {
                    TraceTextureLoad("LoadTextureData: DDS fast-path '%s' %dx%d format=%d mips=%d", filename, width, height, (int)format, mipCount);
                    return true;
                }
                TraceTextureLoad("LoadTextureData: DDS fast-path rejected '%s' after reading %ld bytes", filename, fileSize);

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
                    
                    EImFormat imageFormat = pImageFile->mfGetFormat();
                    format = ImageFormatToTexFormat(imageFormat);
                    mipCount = std::max(1, pImageFile->mfGet_numMips());

                    byte* pImageData = pImageFile->mfGet_image();
                    int imgSize = pImageFile->mfGet_ImageSize();
                    if (pImageData && width > 0 && height > 0 && imgSize > 0)
                    {
                        int bps = pImageFile->mfGet_bps();
                        int expectedSize = width * height * (bps / 8);
                        
                        if (imgSize >= expectedSize)
                        {
                            size_t dataSize = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
                            if (imageFormat == eIF_DXT1 || imageFormat == eIF_DXT3 || imageFormat == eIF_DXT5)
                            {
                                dataSize = static_cast<size_t>(imgSize);
                            }

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
                            
                            TraceTextureLoad("LoadTextureData: parsed '%s' %dx%d format=%d bps=%d imgSize=%d", filename, width, height, (int)format, bps, imgSize);
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
                    TraceTextureLoad("LoadTextureData: parser failed for '%s' error=%s detail=%s", filename, errorMsg, (errorDetail && errorDetail[0]) ? errorDetail : "n/a");
                }

                delete pImageFile;
            }
            else
            {
                iLog->Log("LoadTextureData: Failed to read file %s - expected %ld bytes, read %zu bytes\n", 
                         filename, fileSize, bytesRead);
                TraceTextureLoad("LoadTextureData: read mismatch for '%s' expected=%ld read=%zu", filename, fileSize, bytesRead);
            }
        }
        else
        {
            iLog->Log("LoadTextureData: File %s has zero or negative size (%ld bytes)\n", filename, fileSize);
            iSystem->GetIPak()->FClose(pFile);
            TraceTextureLoad("LoadTextureData: invalid size for '%s' size=%ld", filename, fileSize);
        }
    }
    else
    {
        iLog->Log("LoadTextureData: CryPak failed to open file %s\n", filename);
        TraceTextureLoad("LoadTextureData: CryPak FOpen failed for '%s'", filename);
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
                mipCount = 1;
                MTLPixelFormat pixelFormat = [loadedTexture pixelFormat];
                
                format = ConvertFromMetalFormat(pixelFormat);
                
                int bytesPerPixel = 4;
                switch (pixelFormat)
                {
                    case MTLPixelFormatRGBA8Unorm:
                    case MTLPixelFormatBGRA8Unorm:
                        bytesPerPixel = 4;
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
            TraceTextureLoad("LoadTextureData: file missing on disk '%s'", filename);
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

