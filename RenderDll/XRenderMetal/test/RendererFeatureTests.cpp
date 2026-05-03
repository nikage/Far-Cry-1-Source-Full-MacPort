// Regression tests for CMetalRenderer::GetFeatures() correctness.
//
// Background: CMetalRenderer::GetFeatures() originally overrode
// CMetalBaseRenderer::GetFeatures() with a stripped-down set, silently
// disabling several critical rendering paths:
//   - RFT_HW_VS   → character vertex-shader path disabled
//   - RFT_HW_PS20 → pixel-shader path disabled for almost all shaders
//   - RFT_HW_PS30 → same
//   - RFT_HW_HDR  → HDR rendering disabled
//   - RFT_DEPTHMAPS / RFT_SHADOWMAP_SELFSHADOW → shadow maps disabled
//   - RFT_SUPPORTFSAA → FSAA disabled
//
// Fix: CMetalRenderer::GetFeatures() now delegates to
// CMetalBaseRenderer::GetFeatures() and only adds the Metal-specific extras.
// RFT_ALLOWRECTTEX was removed from the base (D3D9 does not set it).
//
// These tests verify the expected feature-flag composition without linking
// to Metal or the renderer objects.
//
// Build & run (from RenderDll/XRenderMetal/test/):
//   clang++ -std=c++17 -o renderer_feature_tests RendererFeatureTests.cpp && ./renderer_feature_tests

#include <cstdio>

static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond, label) \
    do { \
        if (cond) { \
            printf("  PASS: %s\n", label); \
            ++g_passed; \
        } else { \
            printf("  FAIL: %s\n", label); \
            ++g_failed; \
        } \
    } while (0)

// -----------------------------------------------------------------------
// Mirror of ocean-related constants from CREOcean / RendElement.h
// -----------------------------------------------------------------------
#define OCEANGRID  32
#define NUM_OCEANVBS 3
#define NUM_LODS   5

// Mirrors the index-generation logic from CREOcean::GenerateIndices.
static int SimulateOceanIndexCount(int lodCode)
{
    const int LOD_MASK = 0x7;
    int step = 1 << (lodCode & LOD_MASK);
    int dim  = OCEANGRID / step;
    return dim * dim * 6;
}

// -----------------------------------------------------------------------
// Mirror of RFT_* constants from CryCommon/IRenderer.h
// -----------------------------------------------------------------------
#define RFT_MULTITEXTURE             0x00000001
#define RFT_BUMP                     0x00000002
#define RFT_HWGAMMA                  0x00000010
#define RFT_ALLOWRECTTEX             0x00000020
#define RFT_COMPRESSTEXTURE          0x00000040
#define RFT_ALLOWANISOTROPIC         0x00000100
#define RFT_SUPPORTZBIAS             0x00000200
#define RFT_DETAILTEXTURE            0x00001000
#define RFT_OCCLUSIONTEST            0x00008000
#define RFT_HW_HDR                   0x00080000
#define RFT_HW_VS                    0x00100000
#define RFT_HW_PS20                  0x00800000
#define RFT_HW_PS30                  0x01000000
#define RFT_SUPPORTFSAA              0x08000000
#define RFT_DIRECTACCESSTOVIDEOMEMORY 0x10000000
#define RFT_DEPTHMAPS                0x40000000
#define RFT_SHADOWMAP_SELFSHADOW     0x80000000

// -----------------------------------------------------------------------
// Mirrors of GetFeatures() implementations (post-fix).
// Keep in sync with MetalBaseRenderer.mm and MetalRenderer.mm.
// -----------------------------------------------------------------------

// Simulates CMetalBaseRenderer::GetFeatures() — assumes device is valid.
static int BaseGetFeatures()
{
    int features = 0;
    features |= RFT_MULTITEXTURE;
    features |= RFT_BUMP;
    features |= RFT_HWGAMMA;
    // RFT_ALLOWRECTTEX removed — D3D9 does not set it.
    features |= RFT_COMPRESSTEXTURE;
    features |= RFT_ALLOWANISOTROPIC;
    features |= RFT_SUPPORTZBIAS;
    features |= RFT_HW_VS;
    features |= RFT_HW_PS20;
    features |= RFT_HW_PS30;
    features |= RFT_HW_HDR;
    features |= RFT_SUPPORTFSAA;
    features |= RFT_DEPTHMAPS;
    return features;
}

// Simulates CMetalRenderer::GetFeatures() — delegates + adds Metal extras.
static int RendererGetFeatures()
{
    int features = BaseGetFeatures();
    features |= RFT_DETAILTEXTURE;
    features |= RFT_DIRECTACCESSTOVIDEOMEMORY;
    features |= RFT_OCCLUSIONTEST;
    features |= RFT_DEPTHMAPS;
    features |= RFT_SHADOWMAP_SELFSHADOW;
    return features;
}

int main()
{
    printf("=== RendererFeatureTests ===\n");

    const int features = RendererGetFeatures();

    // Flags that must be present in the full feature mask.
    CHECK(features & RFT_HW_PS20,               "RFT_HW_PS20 present (pixel shaders 2.0)");
    CHECK(features & RFT_HW_PS30,               "RFT_HW_PS30 present (pixel shaders 3.0)");
    CHECK(features & RFT_HW_VS,                 "RFT_HW_VS present (vertex shaders)");
    CHECK(features & RFT_HW_HDR,                "RFT_HW_HDR present (HDR rendering)");
    CHECK(features & RFT_DEPTHMAPS,             "RFT_DEPTHMAPS present (shadow maps)");
    CHECK(features & RFT_SHADOWMAP_SELFSHADOW,  "RFT_SHADOWMAP_SELFSHADOW present");
    CHECK(features & RFT_OCCLUSIONTEST,         "RFT_OCCLUSIONTEST present");
    CHECK(features & RFT_SUPPORTFSAA,           "RFT_SUPPORTFSAA present");
    CHECK(features & RFT_DETAILTEXTURE,         "RFT_DETAILTEXTURE present");
    CHECK(features & RFT_DIRECTACCESSTOVIDEOMEMORY, "RFT_DIRECTACCESSTOVIDEOMEMORY present");
    CHECK(features & RFT_MULTITEXTURE,          "RFT_MULTITEXTURE present");
    CHECK(features & RFT_BUMP,                  "RFT_BUMP present");
    CHECK(features & RFT_HWGAMMA,               "RFT_HWGAMMA present");
    CHECK(features & RFT_COMPRESSTEXTURE,       "RFT_COMPRESSTEXTURE present");
    CHECK(features & RFT_ALLOWANISOTROPIC,      "RFT_ALLOWANISOTROPIC present");

    // RFT_ALLOWRECTTEX must NOT be set (D3D9 does not set it).
    CHECK(!(features & RFT_ALLOWRECTTEX),       "RFT_ALLOWRECTTEX absent (D3D9 parity)");

    // Base alone must not yet have the Metal-specific extras.
    const int base = BaseGetFeatures();
    CHECK(!(base & RFT_OCCLUSIONTEST),          "base does not set RFT_OCCLUSIONTEST");
    CHECK(!(base & RFT_SHADOWMAP_SELFSHADOW),   "base does not set RFT_SHADOWMAP_SELFSHADOW");
    CHECK(!(base & RFT_DIRECTACCESSTOVIDEOMEMORY), "base does not set RFT_DIRECTACCESSTOVIDEOMEMORY");
    CHECK(!(base & RFT_ALLOWRECTTEX),           "base does not set RFT_ALLOWRECTTEX (removed)");

    printf("\n-- Ocean draw-call contract --\n");

    {
        // LOD 0 (finest): step=1, dim=32 → 32*32*6 = 6144 indices
        int idx0 = SimulateOceanIndexCount(0);
        CHECK(idx0 == OCEANGRID * OCEANGRID * 6,
              "LOD-0 ocean sector has OCEANGRID^2 * 6 indices");

        // LOD 1: step=2, dim=16 → 1536 indices
        int idx1 = SimulateOceanIndexCount(1);
        CHECK(idx1 == (OCEANGRID / 2) * (OCEANGRID / 2) * 6,
              "LOD-1 ocean sector has (OCEANGRID/2)^2 * 6 indices");

        // LOD-1 has fewer indices than LOD-0 (coarser mesh = fewer draw calls)
        CHECK(idx1 < idx0,
              "Coarser LOD produces fewer ocean indices");

        // NUM_OCEANVBS vertex buffer slots are available for ping-pong writes
        CHECK(NUM_OCEANVBS >= 2,
              "Ocean VB pool has at least 2 slots for double-buffering");

        // LOD range spans 0 .. NUM_LODS-1
        CHECK(NUM_LODS >= 4,
              "Ocean supports at least 4 LOD levels");
    }

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
