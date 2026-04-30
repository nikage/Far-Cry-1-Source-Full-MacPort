// Unit tests for CUIVideoPanel::SetVolume Lua binding logic.
// Tests the nil-tolerance fix without requiring CryEngine runtime.
//
// Build: clang++ -std=c++17 -o ui_video_panel_tests UIVideoPanelTests.cpp && ./ui_video_panel_tests
//
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// Minimal test harness
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);   \
            ++g_failed;                                                        \
        } else {                                                               \
            ++g_passed;                                                        \
        }                                                                      \
    } while (0)

#define CHECK_EQ(a, b) CHECK((a) == (b))
#define CHECK_FLOAT_EQ(a, b) CHECK(std::abs((a) - (b)) < 1e-5f)
#define SECTION(name) fprintf(stdout, "\n--- %s ---\n", (name))

// ---------------------------------------------------------------------------
// Minimal mock of the IFunctionHandler / script-value types used by SetVolume
// ---------------------------------------------------------------------------

enum MockSVType { svtNull = 0, svtNumber, svtString, svtBool };

struct MockFunctionHandler {
    std::vector<std::pair<MockSVType, float>> params;

    int  GetParamCount() const { return static_cast<int>(params.size()); }
    MockSVType GetParamType(int idx) const {
        if (idx < 1 || idx > static_cast<int>(params.size())) return svtNull;
        return params[idx - 1].first;
    }
    bool GetParam(int idx, float& out) const {
        if (idx < 1 || idx > static_cast<int>(params.size())) return false;
        if (params[idx - 1].first != svtNumber) return false;
        out = params[idx - 1].second;
        return true;
    }
};

// ---------------------------------------------------------------------------
// Pure-C++ model of the fixed SetVolume Lua handler.
// Mirrors CUIVideoPanel::SetVolume after the nil-tolerance fix.
// ---------------------------------------------------------------------------

struct MockVideoPanel {
    float lastVolume = -1.0f;
    bool  called     = false;
    bool  errored    = false;

    bool SetVolumeLua(const MockFunctionHandler& pH) {
        if (pH.GetParamCount() > 1) {
            errored = true;
            return false;
        }

        float fVolume = 0.0f;
        if (pH.GetParamCount() >= 1 && pH.GetParamType(1) == svtNumber)
            pH.GetParam(1, fVolume);

        lastVolume = fVolume;
        called     = true;
        return true;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static void testSetVolume_NilParam_DefaultsToZero() {
    SECTION("SetVolume — nil/absent param defaults to 0.0 (no error)");
    MockFunctionHandler h;
    MockVideoPanel panel;
    bool ok = panel.SetVolumeLua(h);
    CHECK(ok);
    CHECK(!panel.errored);
    CHECK(panel.called);
    CHECK_FLOAT_EQ(panel.lastVolume, 0.0f);
}

static void testSetVolume_NullTypedParam_DefaultsToZero() {
    SECTION("SetVolume — svtNull typed param treated as absent (defaults to 0.0)");
    MockFunctionHandler h;
    h.params.push_back({svtNull, 0.0f});
    MockVideoPanel panel;
    bool ok = panel.SetVolumeLua(h);
    CHECK(ok);
    CHECK(!panel.errored);
    CHECK_FLOAT_EQ(panel.lastVolume, 0.0f);
}

static void testSetVolume_ValidFloat_UsesValue() {
    SECTION("SetVolume — valid float param is forwarded correctly");
    MockFunctionHandler h;
    h.params.push_back({svtNumber, 0.75f});
    MockVideoPanel panel;
    bool ok = panel.SetVolumeLua(h);
    CHECK(ok);
    CHECK(!panel.errored);
    CHECK_FLOAT_EQ(panel.lastVolume, 0.75f);
}

static void testSetVolume_ZeroFloat_Accepted() {
    SECTION("SetVolume — explicit 0.0 param is accepted");
    MockFunctionHandler h;
    h.params.push_back({svtNumber, 0.0f});
    MockVideoPanel panel;
    bool ok = panel.SetVolumeLua(h);
    CHECK(ok);
    CHECK_FLOAT_EQ(panel.lastVolume, 0.0f);
}

static void testSetVolume_MaxFloat_Accepted() {
    SECTION("SetVolume — explicit 1.0 param is accepted");
    MockFunctionHandler h;
    h.params.push_back({svtNumber, 1.0f});
    MockVideoPanel panel;
    bool ok = panel.SetVolumeLua(h);
    CHECK(ok);
    CHECK_FLOAT_EQ(panel.lastVolume, 1.0f);
}

static void testSetVolume_TooManyParams_Errors() {
    SECTION("SetVolume — more than 1 param produces an error");
    MockFunctionHandler h;
    h.params.push_back({svtNumber, 0.5f});
    h.params.push_back({svtNumber, 0.5f});
    MockVideoPanel panel;
    bool ok = panel.SetVolumeLua(h);
    CHECK(!ok);
    CHECK(panel.errored);
}

static void testSetVolume_FiveNilCalls_NoError() {
    SECTION("SetVolume — 5 nil-param calls (cutsceneplayer.lua pattern) produce no errors");
    int errors = 0;
    for (int i = 0; i < 5; ++i) {
        MockFunctionHandler h;
        MockVideoPanel panel;
        bool ok = panel.SetVolumeLua(h);
        if (!ok || panel.errored) ++errors;
    }
    CHECK_EQ(errors, 0);
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main() {
    testSetVolume_NilParam_DefaultsToZero();
    testSetVolume_NullTypedParam_DefaultsToZero();
    testSetVolume_ValidFloat_UsesValue();
    testSetVolume_ZeroFloat_Accepted();
    testSetVolume_MaxFloat_Accepted();
    testSetVolume_TooManyParams_Errors();
    testSetVolume_FiveNilCalls_NoError();

    fprintf(stdout, "\nResults: %d passed, %d failed\n", g_passed, g_failed);
    return g_failed > 0 ? 1 : 0;
}
