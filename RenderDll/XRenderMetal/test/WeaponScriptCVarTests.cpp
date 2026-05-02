// Regression tests for the r_TexResolution CVar → Lua bridge.
//
// Root cause: CRenderer::InitRenderer() registers r_TexResolution via
// iConsole->Register() before InitConsole() links the script system to the
// console.  CreateTaggedValue is therefore never called and getglobal()
// returns nil, breaking rl.lua:275 and sniperrifle.lua:335.
//
// Fix: CWeaponSystemEx::RegisterScriptConstants() injects the CVar value as a
// plain Lua global before any weapon scripts are executed.
//
// These tests verify the logic of the injection and the guard conditions.

#include <cstdio>
#include <cstring>

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

// ---------------------------------------------------------------------------
// Minimal stubs that mirror the injection logic without linking the engine.
// ---------------------------------------------------------------------------

struct MockCVar {
    int value;
    int GetIVal() const { return value; }
};

struct MockConsole {
    MockCVar texRes;
    bool hasTexRes;

    MockCVar* GetCVar(const char* name) {
        if (strcmp(name, "r_TexResolution") == 0 && hasTexRes)
            return &texRes;
        return nullptr;
    }
};

struct MockScriptSystem {
    bool valueSet;
    const char* lastName;
    int lastValue;

    void SetGlobalValue(const char* name, int val) {
        valueSet = true;
        lastName = name;
        lastValue = val;
    }
};

// Mirrors the logic added to CWeaponSystemEx::RegisterScriptConstants()
static void injectRendererCVars(MockConsole* pConsole, MockScriptSystem* pScript) {
    if (!pConsole || !pScript) return;
    if (MockCVar* pCVar = pConsole->GetCVar("r_TexResolution"))
        pScript->SetGlobalValue("r_TexResolution", pCVar->GetIVal());
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static void testInjectsDefaultZero() {
    MockConsole console = { {0}, true };
    MockScriptSystem script = { false, nullptr, -1 };
    injectRendererCVars(&console, &script);
    CHECK(script.valueSet, "SetGlobalValue called when CVar exists");
    CHECK(strcmp(script.lastName, "r_TexResolution") == 0, "global name is r_TexResolution");
    CHECK(script.lastValue == 0, "value 0 is injected (default)");
}

static void testInjectsHighResValue() {
    MockConsole console = { {2}, true };
    MockScriptSystem script = { false, nullptr, -1 };
    injectRendererCVars(&console, &script);
    CHECK(script.valueSet, "SetGlobalValue called for value 2");
    CHECK(script.lastValue == 2, "value 2 is injected");
}

static void testSkipsWhenCVarAbsent() {
    MockConsole console = { {0}, false };
    MockScriptSystem script = { false, nullptr, -1 };
    injectRendererCVars(&console, &script);
    CHECK(!script.valueSet, "SetGlobalValue NOT called when CVar is absent");
}

static void testSkipsWhenConsoleNull() {
    MockScriptSystem script = { false, nullptr, -1 };
    injectRendererCVars(nullptr, &script);
    CHECK(!script.valueSet, "SetGlobalValue NOT called when console is null");
}

static void testSkipsWhenScriptNull() {
    MockConsole console = { {0}, true };
    injectRendererCVars(&console, nullptr);
    CHECK(true, "no crash when script system is null");
}

// Verify that the injected value is a number (not nil) — simulates the
// Lua comparison that was failing in rl.lua:275 and sniperrifle.lua:335.
static void testInjectedValueIsNumeric() {
    MockConsole console = { {0}, true };
    MockScriptSystem script = { false, nullptr, -1 };
    injectRendererCVars(&console, &script);
    // After injection, any integer comparison succeeds (value <= 1 etc.)
    CHECK(script.valueSet && script.lastValue >= 0, "injected value is a non-negative integer");
}

int main() {
    printf("=== WeaponScriptCVarTests ===\n");
    testInjectsDefaultZero();
    testInjectsHighResValue();
    testSkipsWhenCVarAbsent();
    testSkipsWhenConsoleNull();
    testSkipsWhenScriptNull();
    testInjectedValueIsNumeric();
    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
