// Standalone C++ unit tests for keyboard name/ID mapping and key-state tracking.
// No game-engine or OS dependency — compiles with plain clang++.
//
// Build & run:
//   clang++ -std=c++17 -o macos_keyboard_input_tests MacOSKeyboardInputTests.cpp && ./macos_keyboard_input_tests
//
#include <cassert>
#include <cstdio>
#include <cstring>
#include <strings.h>

// ---------------------------------------------------------------------------
// Minimal mirror of the XKEY_* constants from CryCommon/IInput.h.
// Keep in sync with the IInput.h enum.
// ---------------------------------------------------------------------------
enum
{
    XKEY_NULL = 0,
    XKEY_ESCAPE = 1,
    XKEY_1 = 2, XKEY_2 = 3, XKEY_3 = 4, XKEY_4 = 5, XKEY_5 = 6,
    XKEY_6 = 7, XKEY_7 = 8, XKEY_8 = 9, XKEY_9 = 10, XKEY_0 = 11,
    XKEY_MINUS = 12, XKEY_EQUALS = 13, XKEY_BACKSPACE = 14,
    XKEY_TAB = 15,
    XKEY_Q = 16, XKEY_W = 17, XKEY_E = 18, XKEY_R = 19, XKEY_T = 20,
    XKEY_Y = 21, XKEY_U = 22, XKEY_I = 23, XKEY_O = 24, XKEY_P = 25,
    XKEY_LBRACKET = 26, XKEY_RBRACKET = 27,
    XKEY_RETURN = 28, XKEY_LCONTROL = 29,
    XKEY_A = 30, XKEY_S = 31, XKEY_D = 32, XKEY_F = 33, XKEY_G = 34,
    XKEY_H = 35, XKEY_J = 36, XKEY_K = 37, XKEY_L = 38,
    XKEY_SEMICOLON = 39, XKEY_APOSTROPHE = 40,
    XKEY_TILDE = 41, XKEY_LSHIFT = 42, XKEY_BACKSLASH = 43,
    XKEY_Z = 44, XKEY_X = 45, XKEY_C = 46, XKEY_V = 47,
    XKEY_B = 48, XKEY_N = 49, XKEY_M = 50,
    XKEY_COMMA = 51, XKEY_PERIOD = 52, XKEY_SLASH = 53, XKEY_RSHIFT = 54,
    XKEY_MULTIPLY = 55, XKEY_LALT = 56, XKEY_SPACE = 57, XKEY_CAPSLOCK = 58,
    XKEY_F1 = 59, XKEY_F2 = 60, XKEY_F3 = 61, XKEY_F4 = 62, XKEY_F5 = 63,
    XKEY_F6 = 64, XKEY_F7 = 65, XKEY_F8 = 66, XKEY_F9 = 67, XKEY_F10 = 68,
    XKEY_NUMLOCK = 69, XKEY_SCROLL = 70,
    XKEY_NUMPAD7 = 71, XKEY_NUMPAD8 = 72, XKEY_NUMPAD9 = 73,
    XKEY_SUBTRACT = 74,
    XKEY_NUMPAD4 = 75, XKEY_NUMPAD5 = 76, XKEY_NUMPAD6 = 77,
    XKEY_ADD = 78,
    XKEY_NUMPAD1 = 79, XKEY_NUMPAD2 = 80, XKEY_NUMPAD3 = 81, XKEY_NUMPAD0 = 82,
    XKEY_DECIMAL = 83,
    XKEY_F11 = 87, XKEY_F12 = 88,
    XKEY_NUMPADENTER = 156, XKEY_RCONTROL = 157, XKEY_DIVIDE = 181,
    XKEY_RALT = 184,
    XKEY_HOME = 199, XKEY_UP = 200, XKEY_PAGE_UP = 201,
    XKEY_LEFT = 203, XKEY_RIGHT = 205,
    XKEY_END = 207, XKEY_DOWN = 208, XKEY_PAGE_DOWN = 209,
    XKEY_INSERT = 210, XKEY_DELETE = 211,
    XKEY_WIN_LWINDOW = 219,
    XKEY_MOUSE1    = 0x00010000,
    XKEY_MOUSE2    = 0x00020000,
    XKEY_MOUSE3    = 0x00030000,
    XKEY_MWHEEL_UP   = 0x000A0000,
    XKEY_MWHEEL_DOWN = 0x000B0000,
    XKEY_MAXIS_X     = 0x000C0000,
    XKEY_MAXIS_Y     = 0x000D0000,
};

// ---------------------------------------------------------------------------
// Copy of XKeyToName and GetKeyID logic from MacOSInput.cpp.
// Kept in sync manually; these tests validate the contract.
// ---------------------------------------------------------------------------
static const char* XKeyToName(int xkey)
{
    static const struct { int xkey; const char* name; } kNameMap[] = {
        { XKEY_A, "a" }, { XKEY_B, "b" }, { XKEY_C, "c" }, { XKEY_D, "d" },
        { XKEY_E, "e" }, { XKEY_F, "f" }, { XKEY_G, "g" }, { XKEY_H, "h" },
        { XKEY_I, "i" }, { XKEY_J, "j" }, { XKEY_K, "k" }, { XKEY_L, "l" },
        { XKEY_M, "m" }, { XKEY_N, "n" }, { XKEY_O, "o" }, { XKEY_P, "p" },
        { XKEY_Q, "q" }, { XKEY_R, "r" }, { XKEY_S, "s" }, { XKEY_T, "t" },
        { XKEY_U, "u" }, { XKEY_V, "v" }, { XKEY_W, "w" }, { XKEY_X, "x" },
        { XKEY_Y, "y" }, { XKEY_Z, "z" },
        { XKEY_0, "0" }, { XKEY_1, "1" }, { XKEY_2, "2" }, { XKEY_3, "3" },
        { XKEY_4, "4" }, { XKEY_5, "5" }, { XKEY_6, "6" }, { XKEY_7, "7" },
        { XKEY_8, "8" }, { XKEY_9, "9" },
        { XKEY_F1,  "f1"  }, { XKEY_F2,  "f2"  }, { XKEY_F3,  "f3"  },
        { XKEY_F4,  "f4"  }, { XKEY_F5,  "f5"  }, { XKEY_F6,  "f6"  },
        { XKEY_F7,  "f7"  }, { XKEY_F8,  "f8"  }, { XKEY_F9,  "f9"  },
        { XKEY_F10, "f10" }, { XKEY_F11, "f11" }, { XKEY_F12, "f12" },
        { XKEY_ESCAPE,    "escape"     }, { XKEY_RETURN,    "enter"      },
        { XKEY_SPACE,     "space"      }, { XKEY_BACKSPACE, "backspace"  },
        { XKEY_TAB,       "tab"        }, { XKEY_CAPSLOCK,  "capslock"   },
        { XKEY_LSHIFT,    "lshift"     }, { XKEY_RSHIFT,    "rshift"     },
        { XKEY_LCONTROL,  "lctrl"      }, { XKEY_RCONTROL,  "rctrl"      },
        { XKEY_LALT,      "lalt"       }, { XKEY_RALT,      "ralt"       },
        { XKEY_UP,        "up"         }, { XKEY_DOWN,      "down"       },
        { XKEY_LEFT,      "left"       }, { XKEY_RIGHT,     "right"      },
        { XKEY_INSERT,    "insert"     }, { XKEY_DELETE,    "delete"     },
        { XKEY_HOME,      "home"       }, { XKEY_END,       "end"        },
        { XKEY_PAGE_UP,   "pgup"       }, { XKEY_PAGE_DOWN, "pgdn"       },
        { XKEY_MINUS,     "minus"      }, { XKEY_EQUALS,    "equals"     },
        { XKEY_LBRACKET,  "lbracket"   }, { XKEY_RBRACKET,  "rbracket"   },
        { XKEY_SEMICOLON, "semicolon"  }, { XKEY_APOSTROPHE,"apostrophe" },
        { XKEY_COMMA,     "comma"      }, { XKEY_PERIOD,    "period"     },
        { XKEY_SLASH,     "slash"      }, { XKEY_BACKSLASH, "backslash"  },
        { XKEY_TILDE,     "tilde"      },
        { XKEY_NUMPAD0, "num0" }, { XKEY_NUMPAD1, "num1" }, { XKEY_NUMPAD2, "num2" },
        { XKEY_NUMPAD3, "num3" }, { XKEY_NUMPAD4, "num4" }, { XKEY_NUMPAD5, "num5" },
        { XKEY_NUMPAD6, "num6" }, { XKEY_NUMPAD7, "num7" }, { XKEY_NUMPAD8, "num8" },
        { XKEY_NUMPAD9, "num9" }, { XKEY_NUMPADENTER, "numenter" },
        { XKEY_NUMLOCK, "numlock" },
    };
    for (int i = 0; i < (int)(sizeof(kNameMap) / sizeof(kNameMap[0])); ++i)
        if (kNameMap[i].xkey == xkey) return kNameMap[i].name;
    return "";
}

static int GetKeyID(const char* sName)
{
    if (!sName || !sName[0]) return 0;
    static const struct { const char* name; int xkey; } kIdMap[] = {
        { "a", XKEY_A }, { "b", XKEY_B }, { "c", XKEY_C }, { "d", XKEY_D },
        { "e", XKEY_E }, { "f", XKEY_F }, { "g", XKEY_G }, { "h", XKEY_H },
        { "i", XKEY_I }, { "j", XKEY_J }, { "k", XKEY_K }, { "l", XKEY_L },
        { "m", XKEY_M }, { "n", XKEY_N }, { "o", XKEY_O }, { "p", XKEY_P },
        { "q", XKEY_Q }, { "r", XKEY_R }, { "s", XKEY_S }, { "t", XKEY_T },
        { "u", XKEY_U }, { "v", XKEY_V }, { "w", XKEY_W }, { "x", XKEY_X },
        { "y", XKEY_Y }, { "z", XKEY_Z },
        { "0", XKEY_0 }, { "1", XKEY_1 }, { "2", XKEY_2 }, { "3", XKEY_3 },
        { "4", XKEY_4 }, { "5", XKEY_5 }, { "6", XKEY_6 }, { "7", XKEY_7 },
        { "8", XKEY_8 }, { "9", XKEY_9 },
        { "f1",  XKEY_F1  }, { "f2",  XKEY_F2  }, { "f3",  XKEY_F3  },
        { "f4",  XKEY_F4  }, { "f5",  XKEY_F5  }, { "f6",  XKEY_F6  },
        { "f7",  XKEY_F7  }, { "f8",  XKEY_F8  }, { "f9",  XKEY_F9  },
        { "f10", XKEY_F10 }, { "f11", XKEY_F11 }, { "f12", XKEY_F12 },
        { "escape",    XKEY_ESCAPE    }, { "enter",     XKEY_RETURN    },
        { "return",    XKEY_RETURN    }, { "space",     XKEY_SPACE     },
        { "backspace", XKEY_BACKSPACE }, { "tab",       XKEY_TAB       },
        { "capslock",  XKEY_CAPSLOCK  }, { "lshift",    XKEY_LSHIFT    },
        { "rshift",    XKEY_RSHIFT    }, { "lctrl",     XKEY_LCONTROL  },
        { "rctrl",     XKEY_RCONTROL  }, { "lalt",      XKEY_LALT      },
        { "ralt",      XKEY_RALT      }, { "up",        XKEY_UP        },
        { "down",      XKEY_DOWN      }, { "left",      XKEY_LEFT      },
        { "right",     XKEY_RIGHT     }, { "insert",    XKEY_INSERT    },
        { "delete",    XKEY_DELETE    }, { "home",      XKEY_HOME      },
        { "end",       XKEY_END       }, { "pgup",      XKEY_PAGE_UP   },
        { "pgdn",      XKEY_PAGE_DOWN },
        { "mouse1", XKEY_MOUSE1 }, { "mouse2", XKEY_MOUSE2 },
        { "mouse3", XKEY_MOUSE3 },
        { "maxis_x", XKEY_MAXIS_X }, { "maxis_y", XKEY_MAXIS_Y },
    };
    for (int i = 0; i < (int)(sizeof(kIdMap) / sizeof(kIdMap[0])); ++i)
        if (strcasecmp(kIdMap[i].name, sName) == 0) return kIdMap[i].xkey;
    return 0;
}

// ---------------------------------------------------------------------------
// Minimal stub of CMacOSKeyboard state-tracking logic
// ---------------------------------------------------------------------------
static const int kMaxKeys = 256;

struct TestKeyboard
{
    bool m_keyStates[kMaxKeys];
    bool m_prevKeyStates[kMaxKeys];
    int  m_lastPressedKey;
    int  m_lastDownKey;

    TestKeyboard() : m_lastPressedKey(0), m_lastDownKey(0)
    {
        memset(m_keyStates,     0, sizeof(m_keyStates));
        memset(m_prevKeyStates, 0, sizeof(m_prevKeyStates));
    }

    void SimulateUpdate(const bool newStates[kMaxKeys])
    {
        memcpy(m_prevKeyStates, m_keyStates, sizeof(m_keyStates));
        memcpy(m_keyStates,     newStates,   sizeof(m_keyStates));
        m_lastPressedKey = 0;
        m_lastDownKey    = 0;
        for (int k = 1; k < kMaxKeys; ++k)
        {
            if (m_keyStates[k])
            {
                if (m_lastDownKey == 0) m_lastDownKey = k;
                if (!m_prevKeyStates[k] && m_lastPressedKey == 0)
                    m_lastPressedKey = k;
            }
        }
    }

    bool KeyPressed(int k)  const { return (k>=0&&k<kMaxKeys) && m_keyStates[k]  && !m_prevKeyStates[k]; }
    bool KeyReleased(int k) const { return (k>=0&&k<kMaxKeys) && !m_keyStates[k] &&  m_prevKeyStates[k]; }
    bool KeyDown(int k)     const { return (k>=0&&k<kMaxKeys) && m_keyStates[k]; }
};

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); ++g_failed; } \
        else { ++g_passed; } \
    } while (0)

#define CHECK_STR_EQ(a, b) \
    do { \
        const char* _a = (a); const char* _b = (b); \
        if (strcmp(_a, _b) != 0) { \
            fprintf(stderr, "FAIL %s:%d  \"%s\" != \"%s\"\n", __FILE__, __LINE__, _a, _b); \
            ++g_failed; \
        } else { ++g_passed; } \
    } while (0)

// ---------------------------------------------------------------------------
// Tests: XKeyToName round-trip
// ---------------------------------------------------------------------------
static void Test_XKeyToName_AllLetters()
{
    const char* letters = "abcdefghijklmnopqrstuvwxyz";
    const int keys[] = {
        XKEY_A, XKEY_B, XKEY_C, XKEY_D, XKEY_E, XKEY_F, XKEY_G,
        XKEY_H, XKEY_I, XKEY_J, XKEY_K, XKEY_L, XKEY_M, XKEY_N,
        XKEY_O, XKEY_P, XKEY_Q, XKEY_R, XKEY_S, XKEY_T, XKEY_U,
        XKEY_V, XKEY_W, XKEY_X, XKEY_Y, XKEY_Z
    };
    for (int i = 0; i < 26; ++i)
    {
        char expected[2] = { letters[i], '\0' };
        CHECK_STR_EQ(XKeyToName(keys[i]), expected);
    }
}

static void Test_XKeyToName_UnknownReturnsEmpty()
{
    CHECK_STR_EQ(XKeyToName(XKEY_NULL), "");
    CHECK_STR_EQ(XKeyToName(254),       "");
}

static void Test_XKeyToName_SpecialKeys()
{
    CHECK_STR_EQ(XKeyToName(XKEY_ESCAPE),    "escape");
    CHECK_STR_EQ(XKeyToName(XKEY_RETURN),    "enter");
    CHECK_STR_EQ(XKeyToName(XKEY_SPACE),     "space");
    CHECK_STR_EQ(XKeyToName(XKEY_LSHIFT),    "lshift");
    CHECK_STR_EQ(XKeyToName(XKEY_UP),        "up");
    CHECK_STR_EQ(XKeyToName(XKEY_F1),        "f1");
    CHECK_STR_EQ(XKeyToName(XKEY_F12),       "f12");
}

// ---------------------------------------------------------------------------
// Tests: GetKeyID round-trip
// ---------------------------------------------------------------------------
static void Test_GetKeyID_RoundTrip()
{
    const int keys[] = {
        XKEY_W, XKEY_A, XKEY_S, XKEY_D,
        XKEY_ESCAPE, XKEY_RETURN, XKEY_SPACE,
        XKEY_F1, XKEY_F12, XKEY_LSHIFT, XKEY_LCONTROL
    };
    for (int k : keys)
    {
        const char* name = XKeyToName(k);
        if (name && name[0])
        {
            int id = GetKeyID(name);
            CHECK(id == k);
        }
    }
}

static void Test_GetKeyID_CaseInsensitive()
{
    CHECK(GetKeyID("W")      == XKEY_W);
    CHECK(GetKeyID("ESCAPE") == XKEY_ESCAPE);
    CHECK(GetKeyID("Space")  == XKEY_SPACE);
}

static void Test_GetKeyID_UnknownReturnsZero()
{
    CHECK(GetKeyID("unknown_key") == 0);
    CHECK(GetKeyID("")            == 0);
    CHECK(GetKeyID(nullptr)       == 0);
}

static void Test_GetKeyID_MouseKeys()
{
    CHECK(GetKeyID("mouse1")   == XKEY_MOUSE1);
    CHECK(GetKeyID("mouse2")   == XKEY_MOUSE2);
    CHECK(GetKeyID("maxis_x")  == XKEY_MAXIS_X);
    CHECK(GetKeyID("maxis_y")  == XKEY_MAXIS_Y);
}

// ---------------------------------------------------------------------------
// Tests: keyboard state tracking
// ---------------------------------------------------------------------------
static void Test_KeyPressed_OnlyOnTransitionDown()
{
    TestKeyboard kb;
    bool next[kMaxKeys] = {};
    next[XKEY_W] = true;
    kb.SimulateUpdate(next);
    CHECK(kb.KeyPressed(XKEY_W));
    CHECK(!kb.KeyReleased(XKEY_W));
    CHECK(kb.KeyDown(XKEY_W));
    CHECK(kb.m_lastPressedKey == XKEY_W);
    CHECK(kb.m_lastDownKey    == XKEY_W);

    kb.SimulateUpdate(next);
    CHECK(!kb.KeyPressed(XKEY_W));
    CHECK(kb.KeyDown(XKEY_W));
    CHECK(kb.m_lastPressedKey == 0);
    CHECK(kb.m_lastDownKey    == XKEY_W);
}

static void Test_KeyReleased_OnlyOnTransitionUp()
{
    TestKeyboard kb;
    bool next[kMaxKeys] = {};
    next[XKEY_S] = true;
    kb.SimulateUpdate(next);

    bool released[kMaxKeys] = {};
    kb.SimulateUpdate(released);
    CHECK(kb.KeyReleased(XKEY_S));
    CHECK(!kb.KeyDown(XKEY_S));
}

static void Test_GetKeyPressedCode_ReturnsFirstNewKey()
{
    TestKeyboard kb;
    bool next[kMaxKeys] = {};
    next[XKEY_A] = true;
    next[XKEY_D] = true;
    kb.SimulateUpdate(next);
    CHECK(kb.m_lastPressedKey != 0);
    const char* name = XKeyToName(kb.m_lastPressedKey);
    CHECK(name && name[0]);
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main()
{
    Test_XKeyToName_AllLetters();
    Test_XKeyToName_UnknownReturnsEmpty();
    Test_XKeyToName_SpecialKeys();
    Test_GetKeyID_RoundTrip();
    Test_GetKeyID_CaseInsensitive();
    Test_GetKeyID_UnknownReturnsZero();
    Test_GetKeyID_MouseKeys();
    Test_KeyPressed_OnlyOnTransitionDown();
    Test_KeyReleased_OnlyOnTransitionUp();
    Test_GetKeyPressedCode_ReturnsFirstNewKey();

    fprintf(stdout, "\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
