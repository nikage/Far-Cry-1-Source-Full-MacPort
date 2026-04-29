#pragma once
#include <vector>
#include <cstdint>

// ------------------------------------------------------------------
// Packed 16-bit → RGBA8 unpacking
// These formats are not natively supported by Metal on macOS, so the
// CPU decodes them into 4-byte-per-pixel RGBA8 before GPU upload.
// ------------------------------------------------------------------

enum PackedPixelFormat
{
    kPF_4444,   // ARGB4444 — each nibble is a channel
    kPF_1555,   // A1 R5 G5 B5
    kPF_0555,   // X1 R5 G5 B5 (alpha = 255)
    kPF_0565,   // R5 G6 B5 (alpha = 255)
};

inline std::vector<uint8_t> UnpackPackedPixels(
    const uint8_t* src, int width, int height, PackedPixelFormat fmt)
{
    const int nPixels = width * height;
    std::vector<uint8_t> out(nPixels * 4);
    const uint16_t* p = reinterpret_cast<const uint16_t*>(src);
    uint8_t* d = out.data();
    for (int i = 0; i < nPixels; ++i, ++p, d += 4)
    {
        const uint16_t px = *p;
        switch (fmt)
        {
        case kPF_4444:
            d[0] = static_cast<uint8_t>(((px >>  8) & 0xF) * 17); // R
            d[1] = static_cast<uint8_t>(((px >>  4) & 0xF) * 17); // G
            d[2] = static_cast<uint8_t>(( px        & 0xF) * 17); // B
            d[3] = static_cast<uint8_t>(((px >> 12) & 0xF) * 17); // A
            break;
        case kPF_1555:
            d[0] = static_cast<uint8_t>(((px >> 10) & 0x1F) * 8); // R
            d[1] = static_cast<uint8_t>(((px >>  5) & 0x1F) * 8); // G
            d[2] = static_cast<uint8_t>(( px        & 0x1F) * 8); // B
            d[3] = (px >> 15) ? 255 : 0;                           // A (1 bit)
            break;
        case kPF_0555:
            d[0] = static_cast<uint8_t>(((px >> 10) & 0x1F) * 8); // R
            d[1] = static_cast<uint8_t>(((px >>  5) & 0x1F) * 8); // G
            d[2] = static_cast<uint8_t>(( px        & 0x1F) * 8); // B
            d[3] = 255;                                             // A always opaque
            break;
        case kPF_0565:
            d[0] = static_cast<uint8_t>(((px >> 11) & 0x1F) * 8); // R (5 bits)
            d[1] = static_cast<uint8_t>(((px >>  5) & 0x3F) * 4); // G (6 bits)
            d[2] = static_cast<uint8_t>(( px        & 0x1F) * 8); // B (5 bits)
            d[3] = 255;
            break;
        }
    }
    return out;
}

// ------------------------------------------------------------------
// Fog parameter computation (matches SetFog in MetalBaseRenderer)
// fogScale = 1 / (fogEnd - fogStart)
// fogBias  = fogEnd / (fogEnd - fogStart)
// A vertex's fog factor: saturate(fogScale * (-clipZ/clipW) + fogBias)
// ------------------------------------------------------------------
struct FogParams
{
    float scale;
    float bias;
};

inline FogParams ComputeFogParams(float fogStart, float fogEnd)
{
    const float range = fogEnd - fogStart;
    if (range > 0.0001f)
        return { 1.0f / range, fogEnd / range };
    return { 0.0f, 1.0f };
}
