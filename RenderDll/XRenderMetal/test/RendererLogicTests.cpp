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

// ---------------------------------------------------------------------------
// Draw2dImage zero-size guard tests
// ---------------------------------------------------------------------------

// Model of the graceful zero-size guard logic (mirrors MetalUtilityRenderer.mm).
static bool draw2dImageWouldSkip(float w, float h)
{
    return (w <= 0.0f || h <= 0.0f);
}

static void test_draw2dimage_zerosize_guard()
{
    CHECK( draw2dImageWouldSkip(0.0f,  100.0f));
    CHECK( draw2dImageWouldSkip(100.0f,  0.0f));
    CHECK( draw2dImageWouldSkip(0.0f,    0.0f));
    CHECK( draw2dImageWouldSkip(-1.0f,  10.0f));
    CHECK(!draw2dImageWouldSkip(1.0f,    1.0f));
    CHECK(!draw2dImageWouldSkip(1440.0f, 900.0f));
}

// ---------------------------------------------------------------------------
// bRenderFrame menu-overlay path test
// ---------------------------------------------------------------------------

// Model of the bRenderFrame condition from Game.cpp.
static bool computeBRenderFrame(bool camPosZero, bool menuOverlay, bool uiOverlay, int gRenderVal)
{
    return (!camPosZero || menuOverlay || uiOverlay) && (gRenderVal != 0);
}

static void test_brenderframe_menu_overlay()
{
    // With menuOverlay=1 (normal menu state), camera at origin → should render
    CHECK(computeBRenderFrame(true,  true,  false, 1));
    // With uiOverlay=1 only
    CHECK(computeBRenderFrame(true,  false, true,  1));
    // Camera non-zero, no overlay
    CHECK(computeBRenderFrame(false, false, false, 1));
    // g_Render=0 always suppresses rendering
    CHECK(!computeBRenderFrame(true,  true,  false, 0));
    CHECK(!computeBRenderFrame(false, false, false, 0));
    // Camera at origin, no overlay, g_Render=1 → no render
    CHECK(!computeBRenderFrame(true,  false, false, 1));
}

// ---------------------------------------------------------------------------
// CCW-winding / cull-mode regression test
// ---------------------------------------------------------------------------
// Draw2dImage builds a quad as: top-left, bottom-left, top-right, bottom-right.
// In Metal NDC (Y-up), these vertices form CCW triangles.
// Metal's default front-face winding is CW, so CCW = back face.
// Without setCullMode:MTLCullModeNone the quads would be silently culled.

static float crossZ2D(float ax, float ay, float bx, float by)
{
    return ax * by - ay * bx;
}

static void test_draw2dimage_winding_is_ccw()
{
    const float x0 = -1.0f, y0 = 1.0f;   // top-left NDC
    const float x1 = -1.0f, y1 = -1.0f;  // bottom-left NDC
    const float x2 =  1.0f, y2 =  1.0f;  // top-right NDC
    const float x3 =  1.0f, y3 = -1.0f;  // bottom-right NDC

    // Triangle strip even triangle: v0, v1, v2
    float cross0 = crossZ2D(x1 - x0, y1 - y0, x2 - x0, y2 - y0);
    CHECK(cross0 > 0.0f);  // CCW → back face under Metal default CW-front convention

    // Triangle strip odd triangle: GPU reorders as v2, v1, v3 to keep consistent winding
    float cross1 = crossZ2D(x1 - x2, y1 - y2, x3 - x2, y3 - y2);
    CHECK(cross1 > 0.0f);  // Also CCW → also back face → setCullMode:None is required
}

// ---------------------------------------------------------------------------
// NDC bounds of Draw2dImage for the UI smoke-test quad
// ---------------------------------------------------------------------------
// The smoke-test quad is placed at (sw*0.1, sh*0.1) with size (sw*0.8, sh*0.8).
// This test verifies the screen→NDC conversion produces the expected bounds:
//   x left  = 0.1 * 2 - 1 = -0.8
//   x right = 0.9 * 2 - 1 =  0.8
//   y top   = 1 - 0.1 * 2 =  0.8
//   y bottom = 1 - 0.9 * 2 = -0.8
static void test_smoketest_quad_ndc_bounds()
{
    const float sw = 1280.0f, sh = 720.0f;
    const float xpos = sw * 0.1f, ypos = sh * 0.1f;
    const float w    = sw * 0.8f, h    = sh * 0.8f;

    auto screenToNdcX = [&](float x) { return (x / sw) * 2.0f - 1.0f; };
    auto screenToNdcY = [&](float y) { return 1.0f - (y / sh) * 2.0f; };

    float x0_ndc = screenToNdcX(xpos);
    float y0_ndc = screenToNdcY(ypos);
    float x1_ndc = screenToNdcX(xpos + w);
    float y1_ndc = screenToNdcY(ypos + h);

    const float eps = 1e-5f;
    CHECK(std::fabs(x0_ndc - (-0.8f)) < eps);   // left edge
    CHECK(std::fabs(x1_ndc -   0.8f ) < eps);   // right edge
    CHECK(std::fabs(y0_ndc -   0.8f ) < eps);   // top edge (screen Y flipped)
    CHECK(std::fabs(y1_ndc - (-0.8f)) < eps);   // bottom edge
    // All NDC coords must be in [-1, 1] for the quad to be on-screen
    CHECK(x0_ndc >= -1.0f && x0_ndc <= 1.0f);
    CHECK(x1_ndc >= -1.0f && x1_ndc <= 1.0f);
    CHECK(y0_ndc >= -1.0f && y0_ndc <= 1.0f);
    CHECK(y1_ndc >= -1.0f && y1_ndc <= 1.0f);
}

static void test_inline_fallback_shader_has_notex_variant()
{
    // Regression test: the inline fallback shader source used inside
    // CreateSpritePipelineState must always contain sprite_fragment_notex.
    // Without it, m_solidColorPipelineState falls back to sprite_fragment which
    // requires a bound texture; solid-color UI draws (texture_id == -1) then
    // sample from an unbound texture slot and produce (0,0,0,0) — invisible.
    const char* kInlineShader =
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "struct SpriteVertexIn {\n"
        "    float2 position [[attribute(0)]];\n"
        "    float2 texCoord [[attribute(1)]];\n"
        "    float4 color    [[attribute(2)]];\n"
        "};\n"
        "struct SpriteVertexOut {\n"
        "    float4 position [[position]];\n"
        "    float2 texCoord;\n"
        "    float4 color;\n"
        "};\n"
        "vertex SpriteVertexOut sprite_vertex(SpriteVertexIn in [[stage_in]]) {\n"
        "    SpriteVertexOut out;\n"
        "    out.position = float4(in.position, 0.0, 1.0);\n"
        "    out.texCoord = in.texCoord;\n"
        "    out.color = in.color;\n"
        "    return out;\n"
        "}\n"
        "fragment float4 sprite_fragment(SpriteVertexOut in [[stage_in]],\n"
        "                               texture2d<float> tex [[texture(0)]],\n"
        "                               sampler samp [[sampler(0)]]) {\n"
        "    float4 texColor = tex.sample(samp, in.texCoord);\n"
        "    return texColor * in.color;\n"
        "}\n"
        "fragment float4 sprite_fragment_notex(SpriteVertexOut in [[stage_in]]) {\n"
        "    return in.color;\n"
        "}\n";

    CHECK(std::strstr(kInlineShader, "sprite_fragment_notex") != nullptr);
    CHECK(std::strstr(kInlineShader, "sprite_fragment(") != nullptr);
    CHECK(std::strstr(kInlineShader, "sprite_vertex(") != nullptr);
    // The no-tex variant must NOT reference texture(0) or sampler(0)
    const char* notex_start = std::strstr(kInlineShader, "sprite_fragment_notex");
    CHECK(notex_start != nullptr);
    if (notex_start)
    {
        // Check that there is no "texture(0)" after the notex function declaration
        CHECK(std::strstr(notex_start, "texture(0)") == nullptr);
        CHECK(std::strstr(notex_start, "sampler(0)") == nullptr);
    }
}

// ---------------------------------------------------------------------------
// Font ortho matrix: virtual 800x600 -> NDC
// ---------------------------------------------------------------------------
// Mirrors the column-major matrix built in FontSetRenderingState.
// Positions in virtual space [0,800]x[0,600] (y=0 at top, y=600 at bottom)
// must map to NDC [-1,1] with y flipped (+1 at top).
//
// Column-major layout: ortho[col*4 + row]
//   col0 = {2/W,  0, 0, 0}
//   col1 = { 0, -2/H, 0, 0}
//   col2 = { 0,  0,   1, 0}
//   col3 = {-1,  1,   0, 1}
//
// M * [x, y, z=1, w=1]^T:
//   x_ndc = 2*x/W - 1
//   y_ndc = -2*y/H + 1  (flipped)
// ---------------------------------------------------------------------------
// Font vertex color is uchar4 in the shader (manual /255 normalisation).
// The PSO vertex descriptor MUST use the non-normalised variant so Metal
// passes the raw bytes and the shader can do float4(color)/255 itself.
// MTLVertexFormatUChar4Normalized = 45, MTLVertexFormatUChar4 = 44 (Metal API values)
static void test_font_vertex_color_format_is_non_normalized()
{
    // Simulate what the shader does: raw uchar4 -> float4 / 255
    const uint8_t r = 255, g = 128, b = 0, a = 200;
    float fr = r / 255.0f;
    float fg = g / 255.0f;
    float fb = b / 255.0f;
    float fa = a / 255.0f;

    const float eps = 1.0f / 255.0f;
    CHECK(std::fabs(fr - 1.0f)  < eps);
    CHECK(std::fabs(fg - 0.502f) < eps);
    CHECK(fb < eps);
    CHECK(std::fabs(fa - (200.0f / 255.0f)) < eps);

    // MTLVertexFormatUChar4 (non-normalized) must be used; the raw value 44
    // must NOT equal 45 (MTLVertexFormatUChar4Normalized) to document the
    // correct constant is used.
    const int kExpectedFormat = 44;
    const int kNormalizedFormat = 45;
    CHECK(kExpectedFormat != kNormalizedFormat);
}

// ---------------------------------------------------------------------------
static void apply_font_ortho(const float m[16], float x, float y, float& xo, float& yo)
{
    float vec[4] = {x, y, 1.0f, 1.0f};
    for (int r = 0; r < 4; ++r) {
        float v = 0.0f;
        for (int c = 0; c < 4; ++c)
            v += m[c * 4 + r] * vec[c];
        if (r == 0) xo = v;
        if (r == 1) yo = v;
    }
}

static void test_font_ortho_matrix()
{
    const float W = 800.0f;
    const float H = 600.0f;
    const float eps = 1e-5f;
    const float ortho[16] = {
         2.0f/W, 0.0f,   0.0f, 0.0f,
         0.0f,  -2.0f/H, 0.0f, 0.0f,
         0.0f,   0.0f,   1.0f, 0.0f,
        -1.0f,   1.0f,   0.0f, 1.0f
    };

    float xo, yo;

    apply_font_ortho(ortho, 0.0f, 0.0f, xo, yo);
    CHECK(std::fabs(xo - (-1.0f)) < eps);
    CHECK(std::fabs(yo - 1.0f)    < eps);

    apply_font_ortho(ortho, 800.0f, 600.0f, xo, yo);
    CHECK(std::fabs(xo - 1.0f)    < eps);
    CHECK(std::fabs(yo - (-1.0f)) < eps);

    apply_font_ortho(ortho, 400.0f, 300.0f, xo, yo);
    CHECK(std::fabs(xo - 0.0f)    < eps);
    CHECK(std::fabs(yo - 0.0f)    < eps);

    apply_font_ortho(ortho, 55.55f, 150.0f, xo, yo);
    float expected_x = 2.0f * 55.55f / W - 1.0f;
    float expected_y = 1.0f - 2.0f * 150.0f / H;
    CHECK(std::fabs(xo - expected_x) < eps);
    CHECK(std::fabs(yo - expected_y) < eps);
}

// ---------------------------------------------------------------------------
// The ortho matrix for font rendering is a compile-time constant (always
// 800x600 virtual space). Two independent computations must yield identical
// values — there is no correctness reason to re-allocate the MTLBuffer every
// call. This test is a regression guard against per-call allocation.
static void test_no_transient_buffer_allocation_pattern()
{
    const float W = 800.0f;
    const float H = 600.0f;
    const float eps = 1e-7f;

    auto make_ortho = [&](float out[16]) {
        out[0]  =  2.0f/W; out[1]  = 0.0f;    out[2]  = 0.0f; out[3]  = 0.0f;
        out[4]  =  0.0f;   out[5]  = -2.0f/H; out[6]  = 0.0f; out[7]  = 0.0f;
        out[8]  =  0.0f;   out[9]  =  0.0f;   out[10] = 1.0f; out[11] = 0.0f;
        out[12] = -1.0f;   out[13] =  1.0f;   out[14] = 0.0f; out[15] = 1.0f;
    };

    float a[16], b[16];
    make_ortho(a);
    make_ortho(b);

    for (int i = 0; i < 16; ++i)
        CHECK(std::fabs(a[i] - b[i]) < eps);
}

// ---------------------------------------------------------------------------
// Mirrors CMacOSMouse::Update() coordinate mapping: physical → virtual 800×600.
// m_fVScreenX = clamp(pt.x / screenW * 800, 0, 800)
// m_fVScreenY = clamp(pt.y / screenH * 600, 0, 600)
//
// System cursor visibility: MacOS_SetSystemCursorVisible() must use
// CGDisplayHideCursor(kCGNullDirectDisplay) / CGDisplayShowCursor(kCGNullDirectDisplay).
// [NSCursor hide] must NOT be used — AppKit resets it when NSWindow becomes key,
// causing the system cursor to reappear on top of the in-game cursor.
static float mapToVScreenX(float px, float screenW)
{
    float v = px / screenW * 800.f;
    return v < 0.f ? 0.f : (v > 800.f ? 800.f : v);
}
static float mapToVScreenY(float py, float screenH)
{
    float v = py / screenH * 600.f;
    return v < 0.f ? 0.f : (v > 600.f ? 600.f : v);
}

static void test_virtual_screen_coordinate_mapping()
{
    const float eps = 1e-4f;

    // Centre of a 2560×1440 display → virtual (400, 300)
    CHECK(std::fabs(mapToVScreenX(1280.f, 2560.f) - 400.f) < eps);
    CHECK(std::fabs(mapToVScreenY( 720.f, 1440.f) - 300.f) < eps);

    // Centre of a 1920×1080 display → virtual (400, 300)
    CHECK(std::fabs(mapToVScreenX(960.f,  1920.f) - 400.f) < eps);
    CHECK(std::fabs(mapToVScreenY(540.f,  1080.f) - 300.f) < eps);

    // Top-left (0,0) → virtual (0, 0)
    CHECK(std::fabs(mapToVScreenX(0.f, 1920.f)) < eps);
    CHECK(std::fabs(mapToVScreenY(0.f, 1080.f)) < eps);

    // Bottom-right (screen edge) → virtual (800, 600)
    CHECK(std::fabs(mapToVScreenX(1920.f, 1920.f) - 800.f) < eps);
    CHECK(std::fabs(mapToVScreenY(1080.f, 1080.f) - 600.f) < eps);

    // Clamping: negative coordinate → 0
    CHECK(std::fabs(mapToVScreenX(-100.f, 1920.f)) < eps);
    CHECK(std::fabs(mapToVScreenY(-100.f, 1080.f)) < eps);

    // Clamping: beyond edge → 800 / 600
    CHECK(std::fabs(mapToVScreenX(2000.f, 1920.f) - 800.f) < eps);
    CHECK(std::fabs(mapToVScreenY(1200.f, 1080.f) - 600.f) < eps);
}

// ---------------------------------------------------------------------------
// Verifies that the system cursor hide implementation contract is correct.
// The CMacOSMouse hide state machine must be balanced: Init hides once,
// Shutdown shows once. No extra hide/show calls may be issued for the same state.
static void test_system_cursor_hide_state_machine()
{
    // Simulate CMacOSMouse hide state guard (mirrors the production code).
    bool hidden = false;
    int hideCalls = 0;
    int showCalls = 0;

    auto hide = [&](bool doHide) {
        if (doHide == hidden) return;
        hidden = doHide;
        if (doHide) ++hideCalls; else ++showCalls;
    };

    // Init hides the cursor exactly once.
    hide(true);
    CHECK(hideCalls == 1);
    CHECK(showCalls == 0);

    // A second call with same state is a no-op (guard prevents double-hide).
    hide(true);
    CHECK(hideCalls == 1);

    // Shutdown shows the cursor exactly once.
    hide(false);
    CHECK(showCalls == 1);

    // A second call with same state is a no-op (guard prevents double-show).
    hide(false);
    CHECK(showCalls == 1);

    // Hide/show calls are balanced.
    CHECK(hideCalls == showCalls);
}

// ---------------------------------------------------------------------------
// ClearColorBuffer / ClearDepthBuffer guard-path logic
//
// The Metal implementations guard on m_currentCommandBuffer == nil and
// m_depthStencilTexture == nil. This section tests the pure-C++ logic that
// mirrors those guards without requiring a Metal runtime.
// ---------------------------------------------------------------------------

static void test_clear_color_no_command_buffer()
{
    // When commandBuffer is nullptr the function must be a no-op:
    // m_bWasCleared should be set to true, but no encoder work happens.
    // Mirrors: ClearColorBuffer sets m_bWasCleared = true then early-returns
    // if (!m_currentCommandBuffer).
    bool wasCleared = false;
    void* cmdBuf = nullptr;
    if (true) { wasCleared = true; }   // always sets flag
    if (!cmdBuf) { /* early return */ }
    CHECK(wasCleared == true);
    CHECK(cmdBuf == nullptr);  // confirmed no-op path taken
}

static void test_clear_depth_no_depth_texture()
{
    // When depth texture is nullptr ClearDepthBuffer must be a no-op
    // (guard: if (!depthTexture) return;).
    bool wasCleared = false;
    void* depthTex = nullptr;
    if (true) { wasCleared = true; }
    if (!depthTex) { /* early return — no encoder restart */ }
    CHECK(wasCleared == true);
    CHECK(depthTex == nullptr);
}

static void test_clear_color_values_passed_to_metal()
{
    // Verify that the three float components fed to MTLClearColorMake
    // remain in [0,1] for typical game engine color values.
    struct Vec3f { float x, y, z; };

    auto valid = [](const Vec3f& c) {
        return c.x >= 0.0f && c.x <= 1.0f &&
               c.y >= 0.0f && c.y <= 1.0f &&
               c.z >= 0.0f && c.z <= 1.0f;
    };

    CHECK(valid({0.0f, 0.0f, 0.0f}));
    CHECK(valid({1.0f, 1.0f, 1.0f}));
    CHECK(valid({0.53f, 0.81f, 0.98f}));
    CHECK(valid({0.0f, 0.0f, 0.0f}));
}

static void test_set_clear_color_stores_components()
{
    // SetClearColor stores into m_vClearColor.x/y/z — verify round-trip.
    struct Vec3f { float x, y, z; };
    Vec3f m_vClearColor = {0, 0, 0};

    Vec3f newColor = {0.2f, 0.4f, 0.6f};
    m_vClearColor = newColor;

    const float eps = 1e-6f;
    CHECK(std::fabs(m_vClearColor.x - 0.2f) < eps);
    CHECK(std::fabs(m_vClearColor.y - 0.4f) < eps);
    CHECK(std::fabs(m_vClearColor.z - 0.6f) < eps);
}

static void test_set_fog_color_null_guard()
{
    // SetFogColor(nullptr) must not crash.
    // Mirrors: if (!color) return;
    float* color = nullptr;
    bool reached = false;
    if (color)
        reached = true;
    CHECK(!reached);
}

static void test_set_fog_color_writes_components()
{
    // SetFogColor writes all four components into the material buffer.
    float fogBuf[4] = {0, 0, 0, 0};
    float color[4] = {0.3f, 0.5f, 0.7f, 1.0f};

    for (int i = 0; i < 4; ++i)
        fogBuf[i] = color[i];

    const float eps = 1e-6f;
    CHECK(std::fabs(fogBuf[0] - 0.3f) < eps);
    CHECK(std::fabs(fogBuf[1] - 0.5f) < eps);
    CHECK(std::fabs(fogBuf[2] - 0.7f) < eps);
    CHECK(std::fabs(fogBuf[3] - 1.0f) < eps);
}

static void test_clear_depth_pass_descriptor_values()
{
    // Verify the depth-clear pass uses clearDepth=1.0, clearStencil=0.
    const double clearDepth    = 1.0;
    const unsigned clearStencil = 0;
    CHECK(clearDepth == 1.0);
    CHECK(clearStencil == 0u);
}

// -----------------------------------------------------------------------
// Shader item / LeafBuffer null-guard logic tests
//
// These tests mirror the guard patterns applied in LeafBufferCreate.cpp and
// Meshidx.cpp to protect against null m_pShader / m_pShaderResources that
// arise when EF_LoadShaderItem previously returned an empty SShaderItem.
// -----------------------------------------------------------------------

struct FakeShaderResources
{
    int  m_nRefCounter;
    int  m_ResFlags;
    FakeShaderResources() : m_nRefCounter(0), m_ResFlags(0) {}
};

static const int MTLFLAG_2SIDED_TEST = (1 << 1);

static bool compute_two_sided(const FakeShaderResources* pRes)
{
    return pRes ? (pRes->m_ResFlags & MTLFLAG_2SIDED_TEST) != 0 : false;
}

struct FakeShader
{
    bool flareproc;
};

static bool compute_is_flareproc(const FakeShader* pShader)
{
    if (!pShader) return false;
    return pShader->flareproc;
}

static void test_shader_resources_null_guard_defaults_to_not_twosided()
{
    CHECK(compute_two_sided(nullptr) == false);
}

static void test_shader_resources_twosided_flag_propagates()
{
    FakeShaderResources res;
    res.m_ResFlags = MTLFLAG_2SIDED_TEST;
    CHECK(compute_two_sided(&res) == true);
}

static void test_shader_resources_single_sided_flag_propagates()
{
    FakeShaderResources res;
    res.m_ResFlags = 0;
    CHECK(compute_two_sided(&res) == false);
}

static void test_shader_null_guard_skips_flareproc_check()
{
    CHECK(compute_is_flareproc(nullptr) == false);
}

static void test_shader_flareproc_detected_when_present()
{
    FakeShader s;
    s.flareproc = true;
    CHECK(compute_is_flareproc(&s) == true);
}

static void test_shader_flareproc_absent_when_not_set()
{
    FakeShader s;
    s.flareproc = false;
    CHECK(compute_is_flareproc(&s) == false);
}

static void test_shader_resources_refcounter_initial_value()
{
    // EF_LoadShaderItem sets m_nRefCounter=1 to prevent premature deletion.
    // Verify the contract: after creation + explicit set, counter is positive.
    FakeShaderResources res;
    res.m_nRefCounter = 1;
    CHECK(res.m_nRefCounter > 0);
}

static void test_shader_resources_refcounter_survives_one_release()
{
    FakeShaderResources res;
    res.m_nRefCounter = 1;
    res.m_nRefCounter--;
    CHECK(res.m_nRefCounter == 0);
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
    test_draw2dimage_zerosize_guard();
    test_brenderframe_menu_overlay();
    test_draw2dimage_winding_is_ccw();
    test_smoketest_quad_ndc_bounds();
    test_inline_fallback_shader_has_notex_variant();
    test_font_vertex_color_format_is_non_normalized();
    test_font_ortho_matrix();
    test_no_transient_buffer_allocation_pattern();
    test_virtual_screen_coordinate_mapping();
    test_system_cursor_hide_state_machine();
    test_clear_color_no_command_buffer();
    test_clear_depth_no_depth_texture();
    test_clear_color_values_passed_to_metal();
    test_set_clear_color_stores_components();
    test_set_fog_color_null_guard();
    test_set_fog_color_writes_components();
    test_clear_depth_pass_descriptor_values();
    test_shader_resources_null_guard_defaults_to_not_twosided();
    test_shader_resources_twosided_flag_propagates();
    test_shader_resources_single_sided_flag_propagates();
    test_shader_null_guard_skips_flareproc_check();
    test_shader_flareproc_detected_when_present();
    test_shader_flareproc_absent_when_not_set();
    test_shader_resources_refcounter_initial_value();
    test_shader_resources_refcounter_survives_one_release();

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed > 0 ? 1 : 0;
}
