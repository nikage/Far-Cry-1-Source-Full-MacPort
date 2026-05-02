// Standalone unit tests for the ScreenProcess render element fixes.
//
// Covers:
//  1. Null-guard — CScreenVars::Create() must not crash when ICVar pointers
//     returned by IConsole::GetCVar() are null (CVars absent on macOS Metal).
//  2. Correct type tag — the object allocated via EF_CreateRE(eDATA_ScreenProcess)
//     must carry eDATA_ScreenProcess, not the base CRendElement default.
//  3. mfSetParameter round-trip for SCREENPROCESS_FADE / SCREENPROCESS_ACTIVE.
//
// Build:
//   clang++ -std=c++17 -o screen_effect_tests ScreenEffectTests.cpp && ./screen_effect_tests

#include <cassert>
#include <cstdio>
#include <cstring>

// ---------------------------------------------------------------------------
// Minimal test harness (same style as RendererLogicTests.cpp)
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); \
            ++g_failed; \
        } else { \
            ++g_passed; \
        } \
    } while (0)

#define CHECK_EQ(a, b) \
    do { \
        auto _a = (a); auto _b = (b); \
        if (!(_a == _b)) { \
            fprintf(stderr, "FAIL %s:%d  expected %lld got %lld\n", \
                    __FILE__, __LINE__, (long long)(_b), (long long)(_a)); \
            ++g_failed; \
        } else { \
            ++g_passed; \
        } \
    } while (0)

// ---------------------------------------------------------------------------
// Minimal stub types — enough to compile the logic under test
// ---------------------------------------------------------------------------

struct ICVar {
    int   m_iVal  = 0;
    float m_fVal  = 0.0f;
    int   GetIVal() const { return m_iVal; }
    float GetFVal() const { return m_fVal; }
    void  Set(int v)   { m_iVal = v; }
    void  Set(float v) { m_fVal = v; }
};

struct IConsole {
    virtual ~IConsole() = default;
    virtual ICVar *GetCVar(const char *) { return nullptr; }
};

enum EDataType { eDATA_Base = 0, eDATA_ScreenProcess = 5 };

// CRendElement base — simplified vtable mirror
class CRendElement {
public:
    int m_type = eDATA_Base;
    virtual ~CRendElement() = default;
    void  mfSetType(int t) { m_type = t; }
    int   mfGetType() const { return m_type; }
    // Not virtual in the real base — matches RendElement.h
    int mfSetParameter(int, int, void*) { return -999; }
};

// ---------------------------------------------------------------------------
// Inline mirror of the logic under test
// (Mirrors CScreenVars::Create() null-guard logic without engine headers)
// ---------------------------------------------------------------------------

struct TestableScreenVars {
    ICVar *m_pCVStencilShadows = nullptr;
    int    m_iPrevStencilShadows = 0;

    ICVar *m_pCVShadowMaps = nullptr;
    int    m_iPrevShadowMaps = 0;

    ICVar *m_pCVVolFog = nullptr;
    int    m_iPrevVolFog = 0;

    ICVar *m_pCVFog = nullptr;
    int    m_iPrevFog = 0;

    ICVar *m_pCVMaxTexLodBias = nullptr;
    float  m_fPrevMaxTexLodBias = 0.0f;

    ICVar *m_pCVHeatVision = nullptr;
    int    m_iHeatVisionActive = 0;

    // Mirrors the fixed CScreenVars::Create() null-guard block
    void Create(IConsole *iConsole) {
        if (iConsole) {
            m_pCVStencilShadows = iConsole->GetCVar("e_stencil_shadows");
            m_iPrevStencilShadows = m_pCVStencilShadows ? m_pCVStencilShadows->GetIVal() : 0;

            m_pCVShadowMaps = iConsole->GetCVar("e_shadow_maps");
            m_iPrevShadowMaps = m_pCVShadowMaps ? m_pCVShadowMaps->GetIVal() : 0;

            m_pCVVolFog = iConsole->GetCVar("r_VolumetricFog");
            m_iPrevVolFog = m_pCVVolFog ? m_pCVVolFog->GetIVal() : 0;

            m_pCVFog = iConsole->GetCVar("e_fog");
            m_iPrevFog = m_pCVFog ? m_pCVFog->GetIVal() : 0;

            m_pCVMaxTexLodBias = iConsole->GetCVar("r_MaxTexLodBias");
            m_fPrevMaxTexLodBias = m_pCVMaxTexLodBias ? m_pCVMaxTexLodBias->GetFVal() : 0.0f;

            m_pCVHeatVision = iConsole->GetCVar("r_Cryvision");
            m_iHeatVisionActive = m_pCVHeatVision ? m_pCVHeatVision->GetIVal() : 0;
        }
    }
};

// CREScreenProcess stub — mirrors the real class structure and the fix
class TestCREScreenProcess : public CRendElement {
public:
    bool  m_bFadeActive = false;
    float m_fFadeTime   = 0.0f;
    TestableScreenVars *m_pVars = nullptr;

    explicit TestCREScreenProcess(IConsole *con) {
        mfSetType(eDATA_ScreenProcess);
        m_pVars = new TestableScreenVars();
        m_pVars->Create(con);
    }

    ~TestCREScreenProcess() override { delete m_pVars; }

    // Mirrors the real mfSetParameter (SCREENPROCESS_FADE / SCREENPROCESS_ACTIVE path)
    virtual int mfSetParameter(int iProcess, int iParams, void *dwValue) {
        if (iProcess == 0 /*SCREENPROCESS_FADE*/ && iParams == 30 /*SCREENPROCESS_ACTIVE*/) {
            m_bFadeActive = *static_cast<bool*>(dwValue);
            return 1;
        }
        return 0;
    }
};

// ---------------------------------------------------------------------------
// Factory that mirrors EF_CreateRE logic — the fix under test
// ---------------------------------------------------------------------------

enum EDataTypeFactory { eDATA_ScreenProcess_F = 5 };

CRendElement *createRenderElement(int type) {
    switch (type) {
    case eDATA_ScreenProcess_F: {
        auto *re = new TestCREScreenProcess(nullptr);
        return re;
    }
    default:
        return new CRendElement();
    }
}

// ---------------------------------------------------------------------------
// Test cases
// ---------------------------------------------------------------------------

static void test_null_guard_with_null_console() {
    IConsole con;  // GetCVar always returns nullptr
    TestableScreenVars vars;
    vars.Create(&con);

    CHECK_EQ(vars.m_pCVStencilShadows, nullptr);
    CHECK_EQ(vars.m_iPrevStencilShadows, 0);

    CHECK_EQ(vars.m_pCVShadowMaps, nullptr);
    CHECK_EQ(vars.m_iPrevShadowMaps, 0);

    CHECK_EQ(vars.m_pCVVolFog, nullptr);
    CHECK_EQ(vars.m_iPrevVolFog, 0);

    CHECK_EQ(vars.m_pCVFog, nullptr);
    CHECK_EQ(vars.m_iPrevFog, 0);

    CHECK_EQ(vars.m_pCVMaxTexLodBias, nullptr);
    CHECK(vars.m_fPrevMaxTexLodBias == 0.0f);

    CHECK_EQ(vars.m_pCVHeatVision, nullptr);
    CHECK_EQ(vars.m_iHeatVisionActive, 0);
}

static void test_null_guard_with_null_iConsole_pointer() {
    // iConsole == nullptr — the outer if(iConsole) guard skips the block entirely
    TestableScreenVars vars;
    vars.Create(nullptr);

    CHECK_EQ(vars.m_iPrevStencilShadows, 0);
    CHECK_EQ(vars.m_iPrevShadowMaps, 0);
    CHECK_EQ(vars.m_iPrevVolFog, 0);
    CHECK_EQ(vars.m_iPrevFog, 0);
    CHECK(vars.m_fPrevMaxTexLodBias == 0.0f);
    CHECK_EQ(vars.m_iHeatVisionActive, 0);
}

static void test_null_guard_with_live_cvars() {
    // Subclass that returns real ICVar objects
    struct RealConsole : IConsole {
        ICVar m_stencil{};
        ICVar m_shadowMaps{};
        ICVar m_volFog{};
        ICVar m_fog{};
        ICVar m_maxTexLodBias{};
        ICVar m_heatVision{};

        RealConsole() {
            m_stencil.m_iVal     = 1;
            m_shadowMaps.m_iVal  = 2;
            m_volFog.m_iVal      = 3;
            m_fog.m_iVal         = 4;
            m_maxTexLodBias.m_fVal = 1.5f;
            m_heatVision.m_iVal  = 0;
        }

        ICVar *GetCVar(const char *name) {
            if (strcmp(name, "e_stencil_shadows") == 0)  return &m_stencil;
            if (strcmp(name, "e_shadow_maps") == 0)      return &m_shadowMaps;
            if (strcmp(name, "r_VolumetricFog") == 0)    return &m_volFog;
            if (strcmp(name, "e_fog") == 0)              return &m_fog;
            if (strcmp(name, "r_MaxTexLodBias") == 0)    return &m_maxTexLodBias;
            if (strcmp(name, "r_Cryvision") == 0)        return &m_heatVision;
            return nullptr;
        }
    };

    RealConsole con;
    TestableScreenVars vars;
    vars.Create(&con);

    CHECK_EQ(vars.m_iPrevStencilShadows, 1);
    CHECK_EQ(vars.m_iPrevShadowMaps, 2);
    CHECK_EQ(vars.m_iPrevVolFog, 3);
    CHECK_EQ(vars.m_iPrevFog, 4);
    CHECK(vars.m_fPrevMaxTexLodBias == 1.5f);
    CHECK_EQ(vars.m_iHeatVisionActive, 0);
}

static void test_crescreenprocess_type_tag() {
    // Verifies the factory allocates the correct derived type (the vtable fix)
    CRendElement *re = createRenderElement(eDATA_ScreenProcess_F);
    CHECK_EQ(re->mfGetType(), (int)eDATA_ScreenProcess);

    // Also confirm downcasting is valid (would be UB for plain CRendElement)
    auto *sp = dynamic_cast<TestCREScreenProcess*>(re);
    CHECK(sp != nullptr);

    delete re;
}

static void test_crescreenprocess_type_tag_base_mismatch() {
    // A plain CRendElement must NOT carry eDATA_ScreenProcess — confirms the
    // old bug path would have produced the wrong type.
    CRendElement *re = new CRendElement();
    CHECK(re->mfGetType() != (int)eDATA_ScreenProcess);
    delete re;
}

static void test_mfSetParameter_fade_active() {
    TestCREScreenProcess sp(nullptr);
    CHECK(sp.m_bFadeActive == false);

    bool active = true;
    int result = sp.mfSetParameter(0 /*SCREENPROCESS_FADE*/, 30 /*SCREENPROCESS_ACTIVE*/, &active);
    CHECK_EQ(result, 1);
    CHECK(sp.m_bFadeActive == true);
}

static void test_mfSetParameter_fade_deactivate() {
    TestCREScreenProcess sp(nullptr);
    bool active = true;
    sp.mfSetParameter(0, 30, &active);
    CHECK(sp.m_bFadeActive == true);

    active = false;
    sp.mfSetParameter(0, 30, &active);
    CHECK(sp.m_bFadeActive == false);
}

static void test_crescreenprocess_vars_allocated() {
    TestCREScreenProcess sp(nullptr);
    CHECK(sp.m_pVars != nullptr);
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main() {
    test_null_guard_with_null_console();
    test_null_guard_with_null_iConsole_pointer();
    test_null_guard_with_live_cvars();
    test_crescreenprocess_type_tag();
    test_crescreenprocess_type_tag_base_mismatch();
    test_mfSetParameter_fade_active();
    test_mfSetParameter_fade_deactivate();
    test_crescreenprocess_vars_allocated();

    printf("%s  passed=%d  failed=%d\n",
           g_failed == 0 ? "ALL PASSED" : "FAILURES DETECTED",
           g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
