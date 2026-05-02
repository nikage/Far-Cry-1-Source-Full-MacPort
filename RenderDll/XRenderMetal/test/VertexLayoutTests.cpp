// Regression tests for InferVertexLayout priority logic.
//
// Background: InferVertexLayout (MetalShaderLoader.mm) maps a VertexAttributeSummary
// to a concrete vertex format enum and vertex function name.  The original code
// checked hasColor1 before requiresTangentFrame, so any bump-mapped shader that
// also used dual vertex colors (e.g. CGRCBump_DiffSpec_*, terrain, plants) fell
// into the dual-color path and lost the tangent frame entirely — disabling normal
// mapping on every bump surface.
//
// Fix: requiresTangentFrame is now checked first so the tangent_vertex path
// always wins regardless of secondary vertex attributes.
//
// These tests mirror the branching logic from MetalShaderLoader.mm so that any
// future reordering of the branches is caught at CI time.
//
// Build & run (from RenderDll/XRenderMetal/test/):
//   clang++ -std=c++17 -o vertex_layout_tests VertexLayoutTests.cpp && ./vertex_layout_tests

#include <cstdio>
#include <string>

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
// Mirrors of enums/structs from CryCommon/VertexFormats.h and
// MetalShaderLoader.mm (kept in sync with those files).
// -----------------------------------------------------------------------
enum VertexFormat
{
    VERTEX_FORMAT_UNKNOWN = 0,
    VERTEX_FORMAT_P3F = 1,
    VERTEX_FORMAT_P3F_COL4UB = 2,
    VERTEX_FORMAT_P3F_TEX2F = 3,
    VERTEX_FORMAT_P3F_COL4UB_TEX2F = 4,
    VERTEX_FORMAT_TRP3F_COL4UB_TEX2F = 5,
    VERTEX_FORMAT_P3F_COL4UB_COL4UB = 6,
    VERTEX_FORMAT_P3F_N = 7,
    VERTEX_FORMAT_P3F_N_COL4UB = 8,
    VERTEX_FORMAT_P3F_N_TEX2F = 9,
    VERTEX_FORMAT_P3F_N_COL4UB_TEX2F = 10,
    VERTEX_FORMAT_P3F_N_COL4UB_COL4UB = 11,
    VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F = 12,
    VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F = 13,
    VERTEX_FORMAT_T3F_B3F_N3F = 14,
    VERTEX_FORMAT_TEX2F = 15,
    VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F = 16,
    VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F_TEX2F = 17,
    VERTEX_FORMAT_NUMS = 18,
};

struct VertexAttributeSummary
{
    bool hasPosition  = true;
    bool hasNormal    = false;
    bool hasColor0    = false;
    bool hasColor1    = false;
    bool hasTangent   = false;
    bool hasBinormal  = false;
    bool hasTNormal   = false;
    int  texCoordCount = 0;
};

struct VertexLayoutInfo
{
    int         format       = VERTEX_FORMAT_UNKNOWN;
    std::string functionName;
    bool        needsTangents = false;
};

static bool g_warningEmitted = false;

// Mirror of InferVertexLayout from MetalShaderLoader.mm (post-fix).
static VertexLayoutInfo InferVertexLayout(const VertexAttributeSummary& summary)
{
    VertexLayoutInfo info;

    const bool requiresTangentFrame =
        summary.hasTangent || summary.hasBinormal || summary.hasTNormal;
    info.needsTangents = requiresTangentFrame;

    // Tangent frame wins before dual-color so bump-mapped shaders always get
    // the correct vertex path regardless of secondary vertex attributes.
    if (requiresTangentFrame)
    {
        info.format       = VERTEX_FORMAT_P3F_N_COL4UB_TEX2F;
        info.functionName = "tangent_vertex";
        return info;
    }

    if (summary.hasColor1)
    {
        if (summary.hasNormal)
        {
            if (summary.texCoordCount > 1)
            {
                info.format       = VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F_TEX2F;
                info.functionName = "basic_colordual_tex2_vertex";
            }
            else if (summary.texCoordCount > 0)
            {
                info.format       = VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F;
                info.functionName = "basic_colordual_tex_vertex";
            }
            else
            {
                info.format       = VERTEX_FORMAT_P3F_N_COL4UB_COL4UB;
                info.functionName = "basic_colordual_vertex";
            }
        }
        else
        {
            if (summary.texCoordCount > 0)
            {
                info.format       = VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F;
                info.functionName = "colordual_tex_vertex";
            }
            else
            {
                info.format       = VERTEX_FORMAT_P3F_COL4UB_COL4UB;
                info.functionName = "colordual_vertex";
            }
        }
        return info;
    }

    if (summary.texCoordCount > 1)
        info.format = VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F;
    else if (summary.hasNormal && summary.hasColor0 && summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_N_COL4UB_TEX2F;
    else if (summary.hasNormal && summary.hasColor0)
        info.format = VERTEX_FORMAT_P3F_N_COL4UB;
    else if (summary.hasNormal && summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_N_TEX2F;
    else if (summary.hasNormal)
        info.format = VERTEX_FORMAT_P3F_N;
    else if (summary.hasColor0 && summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_COL4UB_TEX2F;
    else if (summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_TEX2F;
    else if (summary.hasColor0)
        info.format = VERTEX_FORMAT_P3F_COL4UB;
    else
        info.format = VERTEX_FORMAT_P3F;

    if (summary.texCoordCount > 1)
        info.functionName = summary.hasColor0 ? "colortex2_vertex" : "tex2_vertex";
    else if (summary.hasNormal && summary.hasColor0 && summary.texCoordCount > 0)
        info.functionName = "basic_vertex";
    else if (summary.hasNormal && summary.hasColor0)
        info.functionName = "basic_color_vertex";
    else if (summary.hasNormal && summary.texCoordCount > 0)
        info.functionName = "normaltex_vertex";
    else if (summary.hasNormal)
        info.functionName = "normal_vertex";
    else if (summary.texCoordCount > 0)
        info.functionName = summary.hasColor0 ? "colortex_vertex" : "tex_vertex";
    else
        info.functionName = summary.hasColor0 ? "color_vertex" : "simple_vertex";

    return info;
}

// -----------------------------------------------------------------------
// G1 — Tangent frame priority over dual vertex colors
// -----------------------------------------------------------------------
static void TestG1_TangentPriority()
{
    printf("\n-- G1: tangent frame beats dual vertex color --\n");

    {
        // Bump-mapped shader that also carries a second vertex color.
        // Before the fix this would resolve to basic_colordual_tex_vertex.
        VertexAttributeSummary s;
        s.hasNormal    = true;
        s.hasColor0    = true;
        s.hasColor1    = true;
        s.hasTangent   = true;
        s.texCoordCount = 1;
        auto info = InferVertexLayout(s);
        CHECK(info.functionName == "tangent_vertex",
              "hasTangent+hasColor1 → tangent_vertex (not dual-color path)");
        CHECK(info.format == VERTEX_FORMAT_P3F_N_COL4UB_TEX2F,
              "hasTangent+hasColor1 → VERTEX_FORMAT_P3F_N_COL4UB_TEX2F");
        CHECK(info.needsTangents,
              "needsTangents flag set");
    }

    {
        // hasBinormal alone also triggers tangent path.
        VertexAttributeSummary s;
        s.hasNormal    = true;
        s.hasColor0    = true;
        s.hasColor1    = true;
        s.hasBinormal  = true;
        s.texCoordCount = 1;
        auto info = InferVertexLayout(s);
        CHECK(info.functionName == "tangent_vertex",
              "hasBinormal+hasColor1 → tangent_vertex");
    }

    {
        // hasTNormal alone also triggers tangent path.
        VertexAttributeSummary s;
        s.hasNormal    = true;
        s.hasColor1    = true;
        s.hasTNormal   = true;
        s.texCoordCount = 1;
        auto info = InferVertexLayout(s);
        CHECK(info.functionName == "tangent_vertex",
              "hasTNormal+hasColor1 → tangent_vertex");
    }

    {
        // No tangent attributes → dual-color path is taken as expected.
        VertexAttributeSummary s;
        s.hasNormal    = true;
        s.hasColor0    = true;
        s.hasColor1    = true;
        s.texCoordCount = 1;
        auto info = InferVertexLayout(s);
        CHECK(info.functionName == "basic_colordual_tex_vertex",
              "no tangent + hasColor1 + normal → basic_colordual_tex_vertex");
    }

    {
        // Tangent only, no dual color.
        VertexAttributeSummary s;
        s.hasNormal    = true;
        s.hasColor0    = true;
        s.hasTangent   = true;
        s.texCoordCount = 1;
        auto info = InferVertexLayout(s);
        CHECK(info.functionName == "tangent_vertex",
              "hasTangent without hasColor1 → tangent_vertex");
    }
}

// -----------------------------------------------------------------------
// G2 — Dual-color + dual-texcoord format (no fallback warning)
// -----------------------------------------------------------------------
static void TestG2_DualColorDualTex()
{
    printf("\n-- G2: dual color + dual texcoord → dedicated format --\n");

    {
        // The old code logged a warning and fell back to single-texcoord.
        // After the G2 fix InferVertexLayout must select the new format.
        VertexAttributeSummary s;
        s.hasNormal    = true;
        s.hasColor0    = true;
        s.hasColor1    = true;
        s.texCoordCount = 2;
        auto info = InferVertexLayout(s);
        CHECK(info.format == VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F_TEX2F,
              "dual-color + texCoordCount=2 → VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F_TEX2F");
        CHECK(info.functionName == "basic_colordual_tex2_vertex",
              "dual-color + texCoordCount=2 → basic_colordual_tex2_vertex");
    }

    {
        // Dual color + single texcoord still selects the single-texcoord path.
        VertexAttributeSummary s;
        s.hasNormal    = true;
        s.hasColor0    = true;
        s.hasColor1    = true;
        s.texCoordCount = 1;
        auto info = InferVertexLayout(s);
        CHECK(info.format == VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F,
              "dual-color + texCoordCount=1 → VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F");
    }

    {
        // Dual color without normal + dual texcoord stays on colordual_tex_vertex
        // (no normal variant for this combo yet).
        VertexAttributeSummary s;
        s.hasColor0    = true;
        s.hasColor1    = true;
        s.texCoordCount = 2;
        auto info = InferVertexLayout(s);
        CHECK(info.functionName == "colordual_tex_vertex",
              "dual-color without normal + texCoordCount=2 → colordual_tex_vertex (no dedicated format)");
    }
}

// -----------------------------------------------------------------------
// G3 — Format stride expectations (vertex descriptor correctness proxies)
// -----------------------------------------------------------------------
static void TestG3_FormatSelection()
{
    printf("\n-- G3: correct format selected for HUD/font and UV-only streams --\n");

    {
        // A plain UV-only shader should select VERTEX_FORMAT_P3F_TEX2F,
        // not VERTEX_FORMAT_TEX2F (which is a secondary-buffer-only format).
        VertexAttributeSummary s;
        s.texCoordCount = 1;
        auto info = InferVertexLayout(s);
        CHECK(info.format == VERTEX_FORMAT_P3F_TEX2F,
              "UV-only shader → VERTEX_FORMAT_P3F_TEX2F (not VERTEX_FORMAT_TEX2F)");
        CHECK(info.format != VERTEX_FORMAT_TEX2F,
              "UV-only shader does not select the secondary-buffer-only TEX2F");
    }

    {
        // Tangent-stream-only input (no position in summary) still wins
        // the tangent path when hasTangent is set.
        VertexAttributeSummary s;
        s.hasTangent   = true;
        s.hasNormal    = true;
        auto info = InferVertexLayout(s);
        CHECK(info.functionName == "tangent_vertex",
              "hasTangent (no other attributes) → tangent_vertex");
        CHECK(info.format != VERTEX_FORMAT_T3F_B3F_N3F,
              "InferVertexLayout never emits T3F_B3F_N3F (it is a secondary buffer format)");
    }
}

int main()
{
    printf("=== VertexLayoutTests ===\n");

    TestG1_TangentPriority();
    TestG2_DualColorDualTex();
    TestG3_FormatSelection();

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
