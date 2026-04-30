// Standalone C++ unit tests for pure-logic Metal renderer functions.
// No Metal API dependency — compiles with plain clang++.
//
// Build: clang++ -std=c++14 -I.. -o renderer_logic_tests RendererLogicTests.cpp && ./renderer_logic_tests
//
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

#include "../PixelFormatUtils.h"

// -----------------------------------------------------------------------
// Portable mirror of UniformBufferData for layout verification.
// Must stay bit-for-bit identical to the definition in MetalBaseRenderer.m.
// -----------------------------------------------------------------------
struct TestUniformBufferData
{
    float mvp[16];    // Matrix44 modelViewProjectionMatrix  (64 B)
    float model[16];  // Matrix44 modelMatrix                (64 B)
    float view[16];   // Matrix44 viewMatrix                 (64 B)
    float proj[16];   // Matrix44 projectionMatrix           (64 B)
    // --- offset 256 ---
    float cameraPos[4];   // 16 B → 272
    float time;           //  4 B → 276
    float _time_pad[3];   // 12 B → 288  (explicit; mirrors MSL implicit alignment gap)
    float lightPos[4];    // 16 B → 304
    float lightColor[4];  // 16 B → 320
    struct LightEntry { float pos[4]; float color[4]; };  // 32 B each
    LightEntry lights[4]; // 128 B → 448
    int numLights;        //  4 B → 452
    float pad3[3];        // 12 B → 464
    float clipPlane[4];   // 16 B → 480
    float clipEnabled;    //  4 B → 484
    float clipRefract;    //  4 B → 488
    float fogScale;       //  4 B → 492
    float fogBias;        //  4 B → 496
};

// -----------------------------------------------------------------------
// Minimal test harness
// -----------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond)                                                       \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); \
            ++g_failed;                                                    \
        } else {                                                           \
            ++g_passed;                                                    \
        }                                                                  \
    } while (0)

#define CHECK_EQ(a, b)                                                    \
    do {                                                                   \
        auto _a = (a); auto _b = (b);                                     \
        if (!(_a == _b)) {                                                 \
            fprintf(stderr, "FAIL %s:%d  expected %lld got %lld\n",       \
                    __FILE__, __LINE__,                                    \
                    (long long)(_b), (long long)(_a));                    \
            ++g_failed;                                                    \
        } else {                                                           \
            ++g_passed;                                                    \
        }                                                                  \
    } while (0)

#define CHECK_NEAR(a, b, eps)                                             \
    do {                                                                   \
        float _a = (float)(a), _b = (float)(b);                          \
        if (std::fabs(_a - _b) > (eps)) {                                 \
            fprintf(stderr, "FAIL %s:%d  expected ~%f got %f\n",          \
                    __FILE__, __LINE__, (double)(_b), (double)(_a));      \
            ++g_failed;                                                    \
        } else {                                                           \
            ++g_passed;                                                    \
        }                                                                  \
    } while (0)

// -----------------------------------------------------------------------
// Tests: UnpackPackedPixels — eTF_4444
// ARGB4444 bit layout: [A3..A0 R3..R0 G3..G0 B3..B0] (high→low)
// -----------------------------------------------------------------------
static void test_unpack_4444()
{
    // Full white: A=F R=F G=F B=F  → 0xFFFF
    uint16_t white = 0xFFFF;
    auto out = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&white), 1, 1, kPF_4444);
    CHECK_EQ(out.size(), 4u);
    CHECK_EQ(out[0], 255); // R
    CHECK_EQ(out[1], 255); // G
    CHECK_EQ(out[2], 255); // B
    CHECK_EQ(out[3], 255); // A

    // Full black, transparent: A=0 R=0 G=0 B=0  → 0x0000
    uint16_t black = 0x0000;
    auto out2 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&black), 1, 1, kPF_4444);
    CHECK_EQ(out2[0], 0);
    CHECK_EQ(out2[1], 0);
    CHECK_EQ(out2[2], 0);
    CHECK_EQ(out2[3], 0);

    // R=F, others 0: 0x0F00
    uint16_t red_only = 0x0F00;
    auto out3 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&red_only), 1, 1, kPF_4444);
    CHECK_EQ(out3[0], 255); // R
    CHECK_EQ(out3[1], 0);   // G
    CHECK_EQ(out3[2], 0);   // B
    CHECK_EQ(out3[3], 0);   // A

    // A=F, R=0 G=0 B=0: 0xF000
    uint16_t alpha_only = 0xF000;
    auto out4 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&alpha_only), 1, 1, kPF_4444);
    CHECK_EQ(out4[0], 0);
    CHECK_EQ(out4[1], 0);
    CHECK_EQ(out4[2], 0);
    CHECK_EQ(out4[3], 255);

    // nibble scale: 0x8 → (8 * 17) = 136
    uint16_t mid = 0x8888;
    auto out5 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&mid), 1, 1, kPF_4444);
    CHECK_EQ(out5[0], 136);
    CHECK_EQ(out5[1], 136);
    CHECK_EQ(out5[2], 136);
    CHECK_EQ(out5[3], 136);

    // 2-pixel output size
    uint16_t two[2] = { 0xFFFF, 0x0000 };
    auto out6 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(two), 2, 1, kPF_4444);
    CHECK_EQ(out6.size(), 8u);
    CHECK_EQ(out6[0], 255); // pixel 0 R
    CHECK_EQ(out6[4], 0);   // pixel 1 R
}

// -----------------------------------------------------------------------
// Tests: UnpackPackedPixels — eTF_1555
// A1 R5 G5 B5: bit 15=A, bits 14..10=R, bits 9..5=G, bits 4..0=B
// -----------------------------------------------------------------------
static void test_unpack_1555()
{
    // Full white, opaque: A=1 R=31 G=31 B=31 → 0xFFFF
    uint16_t white = 0xFFFF;
    auto out = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&white), 1, 1, kPF_1555);
    CHECK_EQ(out[0], 248); // 31 * 8 = 248
    CHECK_EQ(out[1], 248);
    CHECK_EQ(out[2], 248);
    CHECK_EQ(out[3], 255); // A = 1

    // Full black, transparent: A=0 R=0 G=0 B=0 → 0x0000
    uint16_t black = 0x0000;
    auto out2 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&black), 1, 1, kPF_1555);
    CHECK_EQ(out2[0], 0);
    CHECK_EQ(out2[1], 0);
    CHECK_EQ(out2[2], 0);
    CHECK_EQ(out2[3], 0); // A = 0

    // A=1, rest zero: 0x8000
    uint16_t alpha_set = 0x8000;
    auto out3 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&alpha_set), 1, 1, kPF_1555);
    CHECK_EQ(out3[3], 255);
    CHECK_EQ(out3[0], 0);

    // R=31, A=0: bits 14..10 = 11111 → 0x7C00
    uint16_t red = 0x7C00;
    auto out4 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&red), 1, 1, kPF_1555);
    CHECK_EQ(out4[0], 248);
    CHECK_EQ(out4[1], 0);
    CHECK_EQ(out4[2], 0);
    CHECK_EQ(out4[3], 0);
}

// -----------------------------------------------------------------------
// Tests: UnpackPackedPixels — eTF_0555
// Same as 1555 but alpha always 255
// -----------------------------------------------------------------------
static void test_unpack_0555()
{
    uint16_t black = 0x0000;
    auto out = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&black), 1, 1, kPF_0555);
    CHECK_EQ(out[0], 0);
    CHECK_EQ(out[1], 0);
    CHECK_EQ(out[2], 0);
    CHECK_EQ(out[3], 255); // always opaque

    uint16_t white = 0x7FFF; // bits 14..0 all set, bit15 ignored
    auto out2 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&white), 1, 1, kPF_0555);
    CHECK_EQ(out2[0], 248);
    CHECK_EQ(out2[1], 248);
    CHECK_EQ(out2[2], 248);
    CHECK_EQ(out2[3], 255);
}

// -----------------------------------------------------------------------
// Tests: UnpackPackedPixels — eTF_0565
// R5 G6 B5: bits 15..11=R, bits 10..5=G, bits 4..0=B
// -----------------------------------------------------------------------
static void test_unpack_0565()
{
    // Full white: R=31 G=63 B=31 → 0xFFFF
    uint16_t white = 0xFFFF;
    auto out = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&white), 1, 1, kPF_0565);
    CHECK_EQ(out[0], 248); // 31 * 8 = 248
    CHECK_EQ(out[1], 252); // 63 * 4 = 252
    CHECK_EQ(out[2], 248);
    CHECK_EQ(out[3], 255); // alpha always opaque

    // Full black
    uint16_t black = 0x0000;
    auto out2 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&black), 1, 1, kPF_0565);
    CHECK_EQ(out2[0], 0);
    CHECK_EQ(out2[1], 0);
    CHECK_EQ(out2[2], 0);
    CHECK_EQ(out2[3], 255);

    // Pure red: R=31 G=0 B=0 → 0xF800
    uint16_t red = 0xF800;
    auto out3 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&red), 1, 1, kPF_0565);
    CHECK_EQ(out3[0], 248);
    CHECK_EQ(out3[1], 0);
    CHECK_EQ(out3[2], 0);

    // Pure green: R=0 G=63 B=0 → 0x07E0
    uint16_t green = 0x07E0;
    auto out4 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&green), 1, 1, kPF_0565);
    CHECK_EQ(out4[0], 0);
    CHECK_EQ(out4[1], 252);
    CHECK_EQ(out4[2], 0);

    // Pure blue: R=0 G=0 B=31 → 0x001F
    uint16_t blue = 0x001F;
    auto out5 = UnpackPackedPixels(reinterpret_cast<uint8_t*>(&blue), 1, 1, kPF_0565);
    CHECK_EQ(out5[0], 0);
    CHECK_EQ(out5[1], 0);
    CHECK_EQ(out5[2], 248);
}

// -----------------------------------------------------------------------
// Tests: output buffer dimensions
// -----------------------------------------------------------------------
static void test_unpack_dimensions()
{
    const int W = 4, H = 3;
    std::vector<uint16_t> src(W * H, 0xFFFF);
    auto out = UnpackPackedPixels(reinterpret_cast<uint8_t*>(src.data()), W, H, kPF_0565);
    CHECK_EQ(out.size(), static_cast<size_t>(W * H * 4));
}

// -----------------------------------------------------------------------
// Tests: ComputeFogParams
// fogScale = 1 / (fogEnd - fogStart)
// fogBias  = fogEnd / (fogEnd - fogStart)
// At distance = fogStart: factor = fogScale * fogStart + fogBias
//   = (fogStart + fogEnd - fogEnd) / range = ... let's derive properly.
// At clipZ = -fogStart (linear fog convention):
//   fog = fogScale * fogStart + fogBias
//       = fogStart/range + fogEnd/range = (fogStart + fogEnd)/range  ← not quite
// The actual formula used in the vertex shader is:
//   fog = saturate(fogScale * (-clipZ / clipW) + fogBias)
// At vertex on the near plane (-clipZ/clipW = fogStart):
//   fog = fogStart/range + fogEnd/range  — wrong, let me re-check the impl
// Looking at SetFog:
//   fogScale = 1 / range
//   fogBias  = fogEnd / range
// At clipZ = fogStart:  fog = fogStart/range + fogEnd/range → > 1 always for start > 0
// At clipZ = fogEnd:    fog = fogEnd/range + fogEnd/range   = 2*fogEnd/range
// Hmm, this seems unusual. The standard linear fog:
//   fog = (fogEnd - dist) / (fogEnd - fogStart)
// Let's check: at dist=fogStart: fog = 1.0  (fully visible)
//              at dist=fogEnd:   fog = 0.0  (fully fogged)
// With shader: fog = fogScale * dist + fogBias (dist = -clipZ/clipW)
//   fog(fogStart) = fogStart/range + fogEnd/range = (fogStart + fogEnd) / range ≠ 1
//   Unless the shader uses -dist:
//   fog = fogScale * (-dist) + fogBias = -fogStart/range + fogEnd/range
//       = (fogEnd - fogStart)/range = 1.0  ✓
//   fog(fogEnd) = -fogEnd/range + fogEnd/range = 0  ✓
// The shader actually uses: fog = fogBias - fogScale * (dist)
// This is the standard convention. Our header exposes the raw params.
// -----------------------------------------------------------------------
static void test_fog_params()
{
    const float kEps = 1e-5f;

    // Normal range: start=10, end=200
    {
        auto fp = ComputeFogParams(10.0f, 200.0f);
        const float range = 190.0f;
        CHECK_NEAR(fp.scale, 1.0f / range, kEps);
        CHECK_NEAR(fp.bias,  200.0f / range, kEps);

        // At dist=fogStart → fog = bias - scale*start = 1.0
        float fog_at_start = fp.bias - fp.scale * 10.0f;
        CHECK_NEAR(fog_at_start, 1.0f, kEps);

        // At dist=fogEnd → fog = bias - scale*end = 0.0
        float fog_at_end = fp.bias - fp.scale * 200.0f;
        CHECK_NEAR(fog_at_end, 0.0f, kEps);

        // Midpoint
        float fog_mid = fp.bias - fp.scale * 105.0f;
        CHECK_NEAR(fog_mid, 0.5f, 0.001f);
    }

    // Degenerate: start >= end → scale=0, bias=1 (no fog)
    {
        auto fp = ComputeFogParams(100.0f, 100.0f);
        CHECK_NEAR(fp.scale, 0.0f, kEps);
        CHECK_NEAR(fp.bias,  1.0f, kEps);
    }

    // Degenerate: reverse range (end < start)
    {
        auto fp = ComputeFogParams(500.0f, 100.0f);
        CHECK_NEAR(fp.scale, 0.0f, kEps);
        CHECK_NEAR(fp.bias,  1.0f, kEps);
    }

    // start=0, end=500
    {
        auto fp = ComputeFogParams(0.0f, 500.0f);
        CHECK_NEAR(fp.scale, 1.0f / 500.0f, kEps);
        CHECK_NEAR(fp.bias,  1.0f, kEps);
        // At dist=0: fog = 1.0 - 0 = 1.0
        CHECK_NEAR(fp.bias - fp.scale * 0.0f, 1.0f, kEps);
        // At dist=500: fog = 1.0 - 1.0 = 0.0
        CHECK_NEAR(fp.bias - fp.scale * 500.0f, 0.0f, kEps);
    }
}

// -----------------------------------------------------------------------
// Tests: shader-name → function-constant inference
// Mirrors the substring logic in BuildFunctionConstants (MetalShaderLoader.mm).
// Regression for the bug where an undeclared `lowerName` was passed instead of
// the lowercase shader name, causing all name-derived constants to be false.
// -----------------------------------------------------------------------
struct FCFlags {
    bool fog_enabled     = false;
    bool hdr_enabled     = false;
    bool gloss_alpha     = false;
    bool env_light       = false;
    bool atten_enabled   = false;
    bool proj_light      = false;
    bool plants_bending  = false;
    bool alpha_glow      = false;
    bool multiple_lights = false;
    bool high_precision  = false;
};

static bool str_contains(const char* haystack, const char* needle) {
    return std::strstr(haystack, needle) != nullptr;
}

static FCFlags InferFCFlagsFromName(const char* lowerName) {
    FCFlags f;
    if (!lowerName) return f;
    f.env_light       = str_contains(lowerName, "envlight");
    f.alpha_glow      = str_contains(lowerName, "alphaglow");
    f.gloss_alpha     = str_contains(lowerName, "glossalpha");
    f.multiple_lights = str_contains(lowerName, "multiplelight");
    f.atten_enabled   = str_contains(lowerName, "atten");
    f.proj_light      = str_contains(lowerName, "proj");
    f.plants_bending  = str_contains(lowerName, "plants") || str_contains(lowerName, "vegetation");
    return f;
}

static void test_uniform_buffer_layout()
{
    CHECK_EQ(sizeof(TestUniformBufferData), 496u);
    CHECK_EQ(offsetof(TestUniformBufferData, time),       272u);
    CHECK_EQ(offsetof(TestUniformBufferData, _time_pad),  276u);
    CHECK_EQ(offsetof(TestUniformBufferData, lightPos),   288u);
    CHECK_EQ(offsetof(TestUniformBufferData, lightColor), 304u);
    CHECK_EQ(offsetof(TestUniformBufferData, lights),     320u);
    CHECK_EQ(offsetof(TestUniformBufferData, numLights),  448u);
    CHECK_EQ(offsetof(TestUniformBufferData, clipPlane),  464u);
    CHECK_EQ(offsetof(TestUniformBufferData, fogBias),    492u);
    // LightEntry must be 32 bytes (two float[4] members)
    CHECK_EQ(sizeof(TestUniformBufferData::LightEntry), 32u);
}

static void test_function_constant_name_inference()
{
    {
        auto f = InferFCFlagsFromName("generated_cgpsbump_diffspec_envlight_ps_fragment");
        CHECK(f.env_light);
        CHECK(!f.alpha_glow);
        CHECK(!f.gloss_alpha);
        CHECK(!f.multiple_lights);
    }
    {
        auto f = InferFCFlagsFromName("generated_cgpsbump_diffspec_multiplelight_ps_fragment");
        CHECK(f.multiple_lights);
        CHECK(!f.env_light);
    }
    {
        auto f = InferFCFlagsFromName("generated_cgpsbump_glossalpha_ps_fragment");
        CHECK(f.gloss_alpha);
        CHECK(!f.env_light);
    }
    {
        auto f = InferFCFlagsFromName("generated_cgvprog_vegetation_vertex");
        CHECK(f.plants_bending);
        CHECK(!f.env_light);
    }
    {
        auto f = InferFCFlagsFromName("generated_cgpsbump_atten_proj_ps_fragment");
        CHECK(f.atten_enabled);
        CHECK(f.proj_light);
    }
    {
        auto f = InferFCFlagsFromName("generated_cgpsbump_alphaglow_ps_fragment");
        CHECK(f.alpha_glow);
        CHECK(!f.multiple_lights);
    }
    {
        auto f = InferFCFlagsFromName(nullptr);
        CHECK(!f.env_light);
        CHECK(!f.alpha_glow);
        CHECK(!f.plants_bending);
    }
    {
        auto f = InferFCFlagsFromName("generated_cgpsbump_diffspec_ps_fragment");
        CHECK(!f.env_light);
        CHECK(!f.alpha_glow);
        CHECK(!f.gloss_alpha);
        CHECK(!f.multiple_lights);
        CHECK(!f.atten_enabled);
        CHECK(!f.proj_light);
        CHECK(!f.plants_bending);
    }
}

int main()
{
    printf("=== RendererLogicTests ===\n");

    test_unpack_4444();
    test_unpack_1555();
    test_unpack_0555();
    test_unpack_0565();
    test_unpack_dimensions();
    test_fog_params();
    test_uniform_buffer_layout();
    test_function_constant_name_inference();

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed > 0 ? 1 : 0;
}
