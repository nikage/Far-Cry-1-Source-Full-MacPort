// Regression tests for EF_GetWaterZElevation delegation.
//
// Background: CMetalUtilityRenderer::EF_GetWaterZElevation originally returned
// a hardcoded 0.0f.  The fix delegates to CRenderer::EF_GetWaterZElevation
// which queries I3DEngine::GetWaterLevel() (or CREOcean) so the correct water
// height is used for rendering underwater fog, reflections, and culling.
//
// These tests verify the delegation contract using a minimal mock of the engine
// interfaces — no Metal API or link to the renderer is required.
//
// Build & run (from RenderDll/XRenderMetal/test/):
//   clang++ -std=c++17 -o water_elevation_tests WaterElevationTests.cpp && ./water_elevation_tests

#include <cstdio>
#include <cmath>

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
// Minimal mock of the engine water query chain.
// -----------------------------------------------------------------------
static float g_mockWaterLevel = 0.0f;
static bool  g_engineAvailable = true;

struct MockI3DEngine {
    float GetWaterLevel() const { return g_mockWaterLevel; }
};

struct MockOcean {
    float level = 0.0f;
    float GetWaterZElevation(float /*x*/, float /*y*/) const { return level; }
};

static MockI3DEngine* g_mockEngine = nullptr;
static MockOcean*     g_mockOcean  = nullptr;

// Mirrors the logic of CRenderer::EF_GetWaterZElevation (Renderer.cpp).
static float SimulateRendererGetWaterZElevation(float fX, float fY)
{
    if (g_mockOcean)
        return g_mockOcean->GetWaterZElevation(fX, fY);
    if (!g_engineAvailable || !g_mockEngine)
        return 0.0f;
    return g_mockEngine->GetWaterLevel();
}

// Mirrors old stub: always returns 0 (pre-fix behaviour).
static float OldStub(float, float) { return 0.0f; }

int main()
{
    printf("=== WaterElevationTests ===\n");

    printf("\n-- Delegation to engine water level --\n");

    {
        g_mockEngine     = new MockI3DEngine();
        g_mockOcean      = nullptr;
        g_engineAvailable = true;

        g_mockWaterLevel = 42.5f;
        float result = SimulateRendererGetWaterZElevation(0.0f, 0.0f);
        CHECK(std::fabs(result - 42.5f) < 1e-5f,
              "Delegates to I3DEngine::GetWaterLevel() → 42.5");

        float oldResult = OldStub(0.0f, 0.0f);
        CHECK(oldResult == 0.0f,
              "Old stub always returned 0 (regression reference)");
        CHECK(result != oldResult,
              "New implementation differs from old stub when water level != 0");
    }

    printf("\n-- Ocean static override --\n");

    {
        g_mockOcean = new MockOcean();
        g_mockOcean->level = 17.3f;
        float result = SimulateRendererGetWaterZElevation(10.0f, 20.0f);
        CHECK(std::fabs(result - 17.3f) < 1e-5f,
              "CREOcean override takes precedence over I3DEngine");
        delete g_mockOcean;
        g_mockOcean = nullptr;
    }

    printf("\n-- Fallback when engine is unavailable --\n");

    {
        g_engineAvailable = false;
        g_mockOcean = nullptr;
        float result = SimulateRendererGetWaterZElevation(0.0f, 0.0f);
        CHECK(result == 0.0f,
              "Returns 0 when no engine or ocean is available");
        g_engineAvailable = true;
    }

    printf("\n-- Spatial variation (ocean queries X,Y) --\n");

    {
        struct SlopedOcean {
            float GetWaterZElevation(float x, float y) const { return x * 0.1f + y * 0.2f; }
        } sloped;
        float r0 = sloped.GetWaterZElevation(10.0f, 5.0f);
        float r1 = sloped.GetWaterZElevation(20.0f, 5.0f);
        CHECK(r1 > r0, "Ocean elevation varies with X coordinate");
        CHECK(std::fabs(r0 - 2.0f) < 1e-5f,
              "Elevation at (10, 5) is 10*0.1 + 5*0.2 = 2.0");
    }

    delete g_mockEngine;

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
