// Standalone C++ unit tests for CMacOSMouse key mapping and state logic.
// No game-engine or framework dependencies — compiles with plain clang++.
//
// Build & run:
//   clang++ -std=c++17 -o macos_mouse_input_tests MacOSMouseInputTests.cpp && ./macos_mouse_input_tests
//
#include <cassert>
#include <cstdio>
#include <cstring>

// ---------------------------------------------------------------------------
// Minimal mirror of the XKEY_MOUSE* constants from CryCommon/IInput.h.
// Must stay in sync with the enum there.
// ---------------------------------------------------------------------------
enum
{
    XKEY_MOUSE1 = 0x00010000,
    XKEY_MOUSE2 = 0x00020000,
    XKEY_MOUSE3 = 0x00030000,
    XKEY_MOUSE4 = 0x00040000,
    XKEY_MOUSE5 = 0x00050000,
    XKEY_MOUSE6 = 0x00060000,
    XKEY_MOUSE7 = 0x00070000,
    XKEY_MOUSE8 = 0x00080000,
    XKEY_MWHEEL_UP = 0x00090000,
    XKEY_MWHEEL_DOWN = 0x000A0000,
    XKEY_MAXIS_X = 0x000B0000,
    XKEY_MAXIS_Y = 0x000C0000,
};

// ---------------------------------------------------------------------------
// Copy of XKeyToMouseIndex from CryInput/MacOSMouseKeyMap.h.
// Kept in sync manually; the test validates the contract, not the header file.
// ---------------------------------------------------------------------------
static int XKeyToMouseIndex(int key)
{
    switch (key)
    {
    case XKEY_MOUSE1: return 0;
    case XKEY_MOUSE2: return 1;
    case XKEY_MOUSE3: return 2;
    case XKEY_MOUSE4: return 3;
    case XKEY_MOUSE5: return 4;
    case XKEY_MOUSE6: return 5;
    case XKEY_MOUSE7: return 6;
    case XKEY_MOUSE8: return 7;
    case XKEY_MWHEEL_UP: return 8;
    case XKEY_MWHEEL_DOWN: return 9;
    case XKEY_MAXIS_X: return 10;
    case XKEY_MAXIS_Y: return 11;
    default: return -1;
    }
}

// ---------------------------------------------------------------------------
// Minimal stub of CMacOSMouse that exercises the fixed lookup path without
// any OS / framework dependency.
// ---------------------------------------------------------------------------
static const int kMaxButtons = 12;

struct TestMouse
{
    bool m_buttonStates[kMaxButtons];
    bool m_prevButtonStates[kMaxButtons];

    TestMouse()
    {
        memset(m_buttonStates,     0, sizeof(m_buttonStates));
        memset(m_prevButtonStates, 0, sizeof(m_prevButtonStates));
    }

    bool MouseDown(int p_numButton)
    {
        const int idx = XKeyToMouseIndex(p_numButton);
        if (idx < 0 || idx >= kMaxButtons)
            return false;
        return m_buttonStates[idx];
    }

    bool MousePressed(int p_numButton)
    {
        const int idx = XKeyToMouseIndex(p_numButton);
        if (idx < 0 || idx >= kMaxButtons)
            return false;
        return m_buttonStates[idx] && !m_prevButtonStates[idx];
    }

    bool MouseReleased(int p_numButton)
    {
        const int idx = XKeyToMouseIndex(p_numButton);
        if (idx < 0 || idx >= kMaxButtons)
            return false;
        return !m_buttonStates[idx] && m_prevButtonStates[idx];
    }
};

// ---------------------------------------------------------------------------
// Minimal test harness (mirrors RendererLogicTests.cpp)
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond)                                                           \
    do {                                                                      \
        if (!(cond)) {                                                        \
            fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);  \
            ++g_failed;                                                       \
        } else {                                                              \
            ++g_passed;                                                       \
        }                                                                     \
    } while (0)

#define CHECK_EQ(a, b)                                                        \
    do {                                                                      \
        auto _a = (a); auto _b = (b);                                         \
        if (!(_a == _b)) {                                                    \
            fprintf(stderr, "FAIL %s:%d  %s == %s  (%d != %d)\n",            \
                __FILE__, __LINE__, #a, #b, (int)_a, (int)_b);               \
            ++g_failed;                                                       \
        } else {                                                              \
            ++g_passed;                                                       \
        }                                                                     \
    } while (0)

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static void Test_XKeyToMouseIndex_KnownButtons()
{
    CHECK_EQ(XKeyToMouseIndex(XKEY_MOUSE1), 0);
    CHECK_EQ(XKeyToMouseIndex(XKEY_MOUSE2), 1);
    CHECK_EQ(XKeyToMouseIndex(XKEY_MOUSE3), 2);
    CHECK_EQ(XKeyToMouseIndex(XKEY_MOUSE4), 3);
    CHECK_EQ(XKeyToMouseIndex(XKEY_MAXIS_X), 10);
    CHECK_EQ(XKeyToMouseIndex(XKEY_MAXIS_Y), 11);
}

static void Test_XKeyToMouseIndex_UnknownReturnsNegative()
{
    CHECK_EQ(XKeyToMouseIndex(0xDEAD), -1);
    CHECK_EQ(XKeyToMouseIndex(0), -1);
    CHECK_EQ(XKeyToMouseIndex(-1), -1);
}

static void Test_MouseDown_MaxisXReflectsSlot10()
{
    TestMouse m;
    m.m_buttonStates[10] = true;
    CHECK(m.MouseDown(XKEY_MAXIS_X));
    CHECK(!m.MouseDown(XKEY_MAXIS_Y));
}

static void Test_MouseDown_ReturnsFalseWhenNotPressed()
{
    TestMouse m;
    CHECK(!m.MouseDown(XKEY_MOUSE1));
    CHECK(!m.MouseDown(XKEY_MOUSE2));
    CHECK(!m.MouseDown(XKEY_MOUSE3));
}

static void Test_MouseDown_ReturnsTrueWhenPressed()
{
    TestMouse m;
    m.m_buttonStates[0] = true;
    CHECK(m.MouseDown(XKEY_MOUSE1));
    CHECK(!m.MouseDown(XKEY_MOUSE2));
}

static void Test_MouseDown_IgnoresRawLargeIndex()
{
    TestMouse m;
    // Before the fix, passing XKEY_MOUSE1 (65536) directly as index would
    // exceed kMaxButtons and return false even if the button was held.
    // After the fix the mapping converts it to 0.
    m.m_buttonStates[0] = true;
    CHECK(m.MouseDown(XKEY_MOUSE1));
}

static void Test_MousePressed_OnlyTrueOnTransitionDown()
{
    TestMouse m;
    m.m_prevButtonStates[0] = false;
    m.m_buttonStates[0]     = true;
    CHECK(m.MousePressed(XKEY_MOUSE1));

    m.m_prevButtonStates[0] = true;
    m.m_buttonStates[0]     = true;
    CHECK(!m.MousePressed(XKEY_MOUSE1));

    m.m_prevButtonStates[0] = false;
    m.m_buttonStates[0]     = false;
    CHECK(!m.MousePressed(XKEY_MOUSE1));
}

static void Test_MouseReleased_OnlyTrueOnTransitionUp()
{
    TestMouse m;
    m.m_prevButtonStates[0] = true;
    m.m_buttonStates[0]     = false;
    CHECK(m.MouseReleased(XKEY_MOUSE1));

    m.m_prevButtonStates[0] = false;
    m.m_buttonStates[0]     = false;
    CHECK(!m.MouseReleased(XKEY_MOUSE1));

    m.m_prevButtonStates[0] = true;
    m.m_buttonStates[0]     = true;
    CHECK(!m.MouseReleased(XKEY_MOUSE1));
}

static void Test_InvalidKey_AlwaysFalse()
{
    TestMouse m;
    memset(m.m_buttonStates,     0xFF, sizeof(m.m_buttonStates));
    memset(m.m_prevButtonStates, 0xFF, sizeof(m.m_prevButtonStates));
    CHECK(!m.MouseDown(0xDEAD));
    CHECK(!m.MousePressed(0xDEAD));
    CHECK(!m.MouseReleased(0xDEAD));
}

int main()
{
    Test_XKeyToMouseIndex_KnownButtons();
    Test_XKeyToMouseIndex_UnknownReturnsNegative();
    Test_MouseDown_MaxisXReflectsSlot10();
    Test_MouseDown_ReturnsFalseWhenNotPressed();
    Test_MouseDown_ReturnsTrueWhenPressed();
    Test_MouseDown_IgnoresRawLargeIndex();
    Test_MousePressed_OnlyTrueOnTransitionDown();
    Test_MouseReleased_OnlyTrueOnTransitionUp();
    Test_InvalidKey_AlwaysFalse();

    fprintf(stdout, "\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
