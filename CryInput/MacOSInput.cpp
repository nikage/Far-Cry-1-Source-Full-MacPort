////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSInput.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS input system implementation - minimal stubs
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MacOSInput.h"
#include "MacOSMouseKeyMap.h"
#include "XActionMapManager.h"
#include "ISystem.h"

extern "C" int MacOS_IsKeyDown(unsigned short hidKeyCode);
#include <algorithm>
#include <cassert>
#include <sys/time.h>

static double GetCurrentTimeSeconds()
{
    struct timeval tv;
    gettimeofday(&tv, nullptr);
    return (double)tv.tv_sec + (double)tv.tv_usec * 1e-6;
}

// CMacOSKeyboard implementation - minimal stubs
CMacOSKeyboard::CMacOSKeyboard()
    : m_modifiers(0)
    , m_lastPressedKey(0)
    , m_lastDownKey(0)
    , m_bExclusive(false)
{
    memset(m_keyStates, 0, sizeof(m_keyStates));
    memset(m_prevKeyStates, 0, sizeof(m_prevKeyStates));
}

CMacOSKeyboard::~CMacOSKeyboard()
{
    ShutDown();
}

bool CMacOSKeyboard::Init()
{
    // Stub implementation - no actual initialization needed for now
    return true;
}

void CMacOSKeyboard::Update()
{
    memcpy(m_prevKeyStates, m_keyStates, sizeof(m_keyStates));
    memset(m_keyStates, 0, sizeof(m_keyStates));

    // macOS virtual key codes (kVK_* constants from Carbon/HIToolbox)
    static const struct { unsigned short hid; int xkey; } kMap[] = {
        { 0,  XKEY_A },  { 1,  XKEY_S },  { 2,  XKEY_D },  { 3,  XKEY_F },
        { 4,  XKEY_H },  { 5,  XKEY_G },  { 6,  XKEY_Z },  { 7,  XKEY_X },
        { 8,  XKEY_C },  { 9,  XKEY_V },  { 11, XKEY_B },  { 12, XKEY_Q },
        { 13, XKEY_W },  { 14, XKEY_E },  { 15, XKEY_R },  { 16, XKEY_Y },
        { 17, XKEY_T },  { 18, XKEY_1 },  { 19, XKEY_2 },  { 20, XKEY_3 },
        { 21, XKEY_4 },  { 22, XKEY_6 },  { 23, XKEY_5 },  { 24, XKEY_EQUALS },
        { 25, XKEY_9 },  { 26, XKEY_7 },  { 27, XKEY_MINUS }, { 28, XKEY_8 },
        { 29, XKEY_0 },  { 30, XKEY_RBRACKET }, { 31, XKEY_O }, { 32, XKEY_U },
        { 33, XKEY_LBRACKET }, { 34, XKEY_I }, { 35, XKEY_P }, { 36, XKEY_RETURN },
        { 37, XKEY_L },  { 38, XKEY_J },  { 39, XKEY_APOSTROPHE }, { 40, XKEY_K },
        { 41, XKEY_SEMICOLON }, { 42, XKEY_BACKSLASH }, { 43, XKEY_COMMA },
        { 44, XKEY_SLASH }, { 45, XKEY_N }, { 46, XKEY_M },
        { 47, XKEY_PERIOD }, { 48, XKEY_TAB }, { 49, XKEY_SPACE },
        { 50, XKEY_TILDE }, { 51, XKEY_BACKSPACE }, { 53, XKEY_ESCAPE },
        { 55, XKEY_WIN_LWINDOW }, /* kVK_Command */
        { 56, XKEY_LSHIFT }, { 57, XKEY_CAPSLOCK }, { 58, XKEY_LALT },
        { 59, XKEY_LCONTROL }, { 60, XKEY_RSHIFT }, { 61, XKEY_RALT },
        { 62, XKEY_RCONTROL },
        { 71, XKEY_NUMLOCK }, { 72, XKEY_NUMPADENTER },
        { 75, XKEY_SLASH /* numpad div */ }, { 76, XKEY_NUMPADENTER },
        { 78, XKEY_MINUS /* numpad sub */ },
        { 81, XKEY_EQUALS /* numpad eq */ },
        { 82, XKEY_NUMPAD0 }, { 83, XKEY_NUMPAD1 }, { 84, XKEY_NUMPAD2 },
        { 85, XKEY_NUMPAD3 }, { 86, XKEY_NUMPAD4 }, { 87, XKEY_NUMPAD5 },
        { 88, XKEY_NUMPAD6 }, { 89, XKEY_NUMPAD7 },
        { 91, XKEY_NUMPAD8 }, { 92, XKEY_NUMPAD9 },
        { 96,  XKEY_F5  }, { 97,  XKEY_F6  }, { 98,  XKEY_F7  }, { 99,  XKEY_F3  },
        { 100, XKEY_F8  }, { 101, XKEY_F9  }, { 103, XKEY_F11 },
        { 105, XKEY_F13 }, { 107, XKEY_F14 }, { 109, XKEY_F10 }, { 111, XKEY_F12 },
        { 113, XKEY_F15 }, { 114, XKEY_INSERT }, { 115, XKEY_HOME },
        { 116, XKEY_PAGE_UP }, { 117, XKEY_DELETE }, { 118, XKEY_F4 },
        { 119, XKEY_END }, { 120, XKEY_F2 }, { 121, XKEY_PAGE_DOWN },
        { 122, XKEY_F1 }, { 123, XKEY_LEFT }, { 124, XKEY_RIGHT },
        { 125, XKEY_DOWN }, { 126, XKEY_UP },
    };

    m_lastPressedKey = 0;
    m_lastDownKey    = 0;

    for (int i = 0; i < (int)(sizeof(kMap) / sizeof(kMap[0])); ++i)
    {
        int xkey = kMap[i].xkey;
        if (xkey >= 0 && xkey < 256 && MacOS_IsKeyDown(kMap[i].hid))
        {
            m_keyStates[xkey] = true;
            if (m_lastDownKey == 0)
                m_lastDownKey = xkey;
            if (!m_prevKeyStates[xkey] && m_lastPressedKey == 0)
                m_lastPressedKey = xkey;
        }
    }
}

void CMacOSKeyboard::ShutDown()
{
    // Stub implementation
}

bool CMacOSKeyboard::KeyDown(int p_key)
{
    return (p_key >= 0 && p_key < 256) ? m_keyStates[p_key] : false;
}

bool CMacOSKeyboard::KeyPressed(int p_key)
{
    if (p_key < 0 || p_key >= 256) return false;
    return m_keyStates[p_key] && !m_prevKeyStates[p_key];
}

bool CMacOSKeyboard::KeyReleased(int p_key)
{
    if (p_key < 0 || p_key >= 256) return false;
    return !m_keyStates[p_key] && m_prevKeyStates[p_key];
}

void CMacOSKeyboard::ClearKey(int p_key)
{
    if (p_key >= 0 && p_key < 256)
        m_keyStates[p_key] = m_prevKeyStates[p_key] = false;
}

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

int CMacOSKeyboard::GetKeyPressedCode()
{
    return m_lastPressedKey;
}

const char* CMacOSKeyboard::GetKeyPressedName()
{
    return XKeyToName(m_lastPressedKey);
}

int CMacOSKeyboard::GetKeyDownCode()
{
    return m_lastDownKey;
}

const char* CMacOSKeyboard::GetKeyDownName()
{
    return XKeyToName(m_lastDownKey);
}

void CMacOSKeyboard::SetExclusive(bool value, void* hwnd)
{
    // Stub implementation
    m_bExclusive = value;
}

void CMacOSKeyboard::WaitForKey()
{
    // Stub implementation
}

void CMacOSKeyboard::ClearKeyState()
{
    // Stub implementation
    memset(m_keyStates, 0, sizeof(m_keyStates));
    memset(m_prevKeyStates, 0, sizeof(m_prevKeyStates));
}

int CMacOSKeyboard::ConvertMacOSKeyCode(unsigned short keyCode)
{
    static const struct { unsigned short hid; int xkey; } kMap[] = {
        { 0,  XKEY_A },  { 1,  XKEY_S },  { 2,  XKEY_D },  { 3,  XKEY_F },
        { 4,  XKEY_H },  { 5,  XKEY_G },  { 6,  XKEY_Z },  { 7,  XKEY_X },
        { 8,  XKEY_C },  { 9,  XKEY_V },  { 11, XKEY_B },  { 12, XKEY_Q },
        { 13, XKEY_W },  { 14, XKEY_E },  { 15, XKEY_R },  { 16, XKEY_Y },
        { 17, XKEY_T },  { 18, XKEY_1 },  { 19, XKEY_2 },  { 20, XKEY_3 },
        { 21, XKEY_4 },  { 22, XKEY_6 },  { 23, XKEY_5 },  { 24, XKEY_EQUALS },
        { 25, XKEY_9 },  { 26, XKEY_7 },  { 27, XKEY_MINUS }, { 28, XKEY_8 },
        { 29, XKEY_0 },  { 30, XKEY_RBRACKET }, { 31, XKEY_O }, { 32, XKEY_U },
        { 33, XKEY_LBRACKET }, { 34, XKEY_I }, { 35, XKEY_P }, { 36, XKEY_RETURN },
        { 37, XKEY_L },  { 38, XKEY_J },  { 39, XKEY_APOSTROPHE }, { 40, XKEY_K },
        { 41, XKEY_SEMICOLON }, { 42, XKEY_BACKSLASH }, { 43, XKEY_COMMA },
        { 44, XKEY_SLASH }, { 45, XKEY_N }, { 46, XKEY_M },
        { 47, XKEY_PERIOD }, { 48, XKEY_TAB }, { 49, XKEY_SPACE },
        { 50, XKEY_TILDE }, { 51, XKEY_BACKSPACE }, { 53, XKEY_ESCAPE },
        { 56, XKEY_LSHIFT }, { 57, XKEY_CAPSLOCK }, { 58, XKEY_LALT },
        { 59, XKEY_LCONTROL }, { 60, XKEY_RSHIFT }, { 61, XKEY_RALT },
        { 62, XKEY_RCONTROL },
        { 82, XKEY_NUMPAD0 }, { 83, XKEY_NUMPAD1 }, { 84, XKEY_NUMPAD2 },
        { 85, XKEY_NUMPAD3 }, { 86, XKEY_NUMPAD4 }, { 87, XKEY_NUMPAD5 },
        { 88, XKEY_NUMPAD6 }, { 89, XKEY_NUMPAD7 },
        { 91, XKEY_NUMPAD8 }, { 92, XKEY_NUMPAD9 },
        { 96,  XKEY_F5  }, { 97,  XKEY_F6  }, { 98,  XKEY_F7  }, { 99,  XKEY_F3  },
        { 100, XKEY_F8  }, { 101, XKEY_F9  }, { 103, XKEY_F11 },
        { 109, XKEY_F10 }, { 111, XKEY_F12 },
        { 114, XKEY_INSERT }, { 115, XKEY_HOME },
        { 116, XKEY_PAGE_UP }, { 117, XKEY_DELETE }, { 118, XKEY_F4 },
        { 119, XKEY_END }, { 120, XKEY_F2 }, { 121, XKEY_PAGE_DOWN },
        { 122, XKEY_F1 }, { 123, XKEY_LEFT }, { 124, XKEY_RIGHT },
        { 125, XKEY_DOWN }, { 126, XKEY_UP },
    };
    for (int i = 0; i < (int)(sizeof(kMap) / sizeof(kMap[0])); ++i)
        if (kMap[i].hid == keyCode) return kMap[i].xkey;
    return XKEY_NULL;
}

void CMacOSKeyboard::ProcessKeyEvent(void* event, bool isKeyDown)
{
    // Stub implementation - no actual processing
}

// CMacOSMouse implementation - minimal stubs
CMacOSMouse::CMacOSMouse()
    : m_x(0), m_y(0)
    , m_prevX(0), m_prevY(0)
    , m_dx(0.f), m_dy(0.f)
    , m_wheelDelta(0)
    , m_bHidden(false)
    , m_bExclusive(false)
    , m_fVScreenX(0.f)
    , m_fVScreenY(0.f)
    , m_screenWidth(0.f)
    , m_screenHeight(0.f)
{
    memset(m_buttonStates, 0, sizeof(m_buttonStates));
    memset(m_prevButtonStates, 0, sizeof(m_prevButtonStates));
    memset(m_lastClickTime, 0, sizeof(m_lastClickTime));
    memset(m_prevClickTime, 0, sizeof(m_prevClickTime));
}

CMacOSMouse::~CMacOSMouse()
{
    Shutdown();
}

bool CMacOSMouse::Init()
{
    MacOS_GetScreenDimensions(&m_screenWidth, &m_screenHeight);
    assert(m_screenWidth  > 0 && "CMacOSMouse::Init: could not determine display width");
    assert(m_screenHeight > 0 && "CMacOSMouse::Init: could not determine display height");
    MacOS_SetSystemCursorVisible(0);
    m_bHidden = true;
    return true;
}

void CMacOSMouse::Update()
{
    memcpy(m_prevButtonStates, m_buttonStates, sizeof(m_buttonStates));

    int left = 0, right = 0, middle = 0;
    MacOS_GetMouseButtons(&left, &right, &middle);
    m_buttonStates[0] = (left   != 0);
    m_buttonStates[1] = (right  != 0);
    m_buttonStates[2] = (middle != 0);

    const double now = GetCurrentTimeSeconds();
    for (int i = 0; i < 3; ++i)
    {
        if (m_buttonStates[i] && !m_prevButtonStates[i])
        {
            m_prevClickTime[i] = m_lastClickTime[i];
            m_lastClickTime[i] = now;
        }
    }

    MacOS_GetMouseVScreenXY(m_screenWidth, m_screenHeight, &m_fVScreenX, &m_fVScreenY);

    MacOS_GetRawMouseDelta(&m_dx, &m_dy);

    m_wheelDelta = 0;
}

void CMacOSMouse::Shutdown()
{
    MacOS_SetSystemCursorVisible(1);
    m_bHidden = false;
}

bool CMacOSMouse::MouseDown(int p_numButton)
{
    const int idx = XKeyToMouseIndex(p_numButton);
    assert(idx >= 0 && "CMacOSMouse::MouseDown: unknown mouse key");
    if (idx < 0 || idx >= 8) return false;
    return m_buttonStates[idx];
}

bool CMacOSMouse::MousePressed(int p_numButton)
{
    const int idx = XKeyToMouseIndex(p_numButton);
    assert(idx >= 0 && "CMacOSMouse::MousePressed: unknown mouse key");
    if (idx < 0 || idx >= 8) return false;
    return m_buttonStates[idx] && !m_prevButtonStates[idx];
}

bool CMacOSMouse::MouseReleased(int p_numButton)
{
    const int idx = XKeyToMouseIndex(p_numButton);
    assert(idx >= 0 && "CMacOSMouse::MouseReleased: unknown mouse key");
    if (idx < 0 || idx >= 8) return false;
    return !m_buttonStates[idx] && m_prevButtonStates[idx];
}

void CMacOSMouse::SetMouseWheelRotation(int value)
{
    // Stub implementation
    m_wheelDelta = value;
}

bool CMacOSMouse::SetExclusive(bool value, void* hwnd)
{
    // Stub implementation
    m_bExclusive = value;
    return true;
}

float CMacOSMouse::GetDeltaX()
{
    return m_dx;
}

float CMacOSMouse::GetDeltaY()
{
    return m_dy;
}

float CMacOSMouse::GetDeltaZ()
{
    return (float)m_wheelDelta;
}

void CMacOSMouse::SetInertia(float)
{
    // Stub implementation
}

void CMacOSMouse::SetVScreenX(float fX)
{
    m_fVScreenX = fX;
}

void CMacOSMouse::SetVScreenY(float fY)
{
    m_fVScreenY = fY;
}

float CMacOSMouse::GetVScreenX()
{
    return m_fVScreenX;
}

float CMacOSMouse::GetVScreenY()
{
    return m_fVScreenY;
}

void CMacOSMouse::SetSensitvity(float fSensitivity)
{
    // Stub implementation
}

float CMacOSMouse::GetSensitvity()
{
    // Stub implementation - return 1.0
    return 1.0f;
}

void CMacOSMouse::SetSensitvityScale(float fSensScale)
{
    // Stub implementation
}

float CMacOSMouse::GetSensitvityScale()
{
    // Stub implementation - return 1.0
    return 1.0f;
}

void CMacOSMouse::ClearKeyState()
{
    // Stub implementation
    memset(m_buttonStates, 0, sizeof(m_buttonStates));
    memset(m_prevButtonStates, 0, sizeof(m_prevButtonStates));
}

void CMacOSMouse::GetPos(int& x, int& y)
{
    x = m_x;
    y = m_y;
}

void CMacOSMouse::SetPos(int x, int y)
{
    m_x = x;
    m_y = y;
    m_prevX = x;
    m_prevY = y;
}

bool CMacOSMouse::ButtonPressed(int nButton)
{
    // Check if button was just pressed (down this frame but not last frame)
    if (nButton >= 0 && nButton < 8) {
        return m_buttonStates[nButton] && !m_prevButtonStates[nButton];
    }
    return false;
}

bool CMacOSMouse::ButtonReleased(int nButton)
{
    // Check if button was just released (up this frame but down last frame)
    if (nButton >= 0 && nButton < 8) {
        return !m_buttonStates[nButton] && m_prevButtonStates[nButton];
    }
    return false;
}

bool CMacOSMouse::IsButtonDown(int nButton)
{
    // Check if button is currently down
    if (nButton >= 0 && nButton < 8) {
        return m_buttonStates[nButton];
    }
    return false;
}

int CMacOSMouse::GetWheelDelta()
{
    return m_wheelDelta;
}

void CMacOSMouse::Hide(bool hide)
{
    if (hide == m_bHidden)
        return;
    m_bHidden = hide;
    MacOS_SetSystemCursorVisible(hide ? 0 : 1);
}

void CMacOSMouse::ProcessMouseEvent(void* event)
{
    // Stub implementation - no actual processing
}

int CMacOSMouse::ConvertMacOSButton(int button)
{
    // Stub implementation - return button as-is
    return button;
}

// CMacOSInput implementation - minimal stubs
CMacOSInput::CMacOSInput()
    : m_pSystem(nullptr)
    , m_window(nullptr)
    , m_bExclusiveMode(false)
    , m_bEventPostingEnabled(true)
{
    m_pKeyboard = new CMacOSKeyboard();
    m_pMouse = new CMacOSMouse();
    m_pKeyboard->Init();
    m_pMouse->Init();
}

CMacOSInput::~CMacOSInput()
{
    delete m_pKeyboard;
    delete m_pMouse;
}

void CMacOSInput::Update(bool bFocus)
{
    if (m_pKeyboard) m_pKeyboard->Update();
    if (m_pMouse) m_pMouse->Update();

    if (!m_bEventPostingEnabled)
        return;

    if (m_pKeyboard)
    {
        for (int k = 1; k < 256; ++k)
        {
            bool cur  = m_pKeyboard->KeyDown(k);
            bool prev = m_pKeyboard->KeyDown(k) || m_pKeyboard->KeyReleased(k);
            bool wasDown = cur || m_pKeyboard->KeyReleased(k);
            if (m_pKeyboard->KeyPressed(k))
            {
                SInputEvent ev;
                ev.type      = SInputEvent::KEY_PRESS;
                ev.key       = k;
                ev.keyname   = XKeyToName(k);
                ev.timestamp = 0;
                PostEvent(ev);
            }
            else if (m_pKeyboard->KeyReleased(k))
            {
                SInputEvent ev;
                ev.type      = SInputEvent::KEY_RELEASE;
                ev.key       = k;
                ev.keyname   = XKeyToName(k);
                ev.timestamp = 0;
                PostEvent(ev);
            }
        }
    }

    if (m_pMouse)
    {
        float dx = m_pMouse->GetDeltaX();
        float dy = m_pMouse->GetDeltaY();
        if (dx != 0.f || dy != 0.f)
        {
            SInputEvent ev;
            ev.type    = SInputEvent::MOUSE_MOVE;
            ev.key     = XKEY_MAXIS_X;
            ev.value   = dx;
            ev.keyname = "maxis_x";
            PostEvent(ev);
            ev.key     = XKEY_MAXIS_Y;
            ev.value   = dy;
            ev.keyname = "maxis_y";
            PostEvent(ev);
        }
    }
}

void CMacOSInput::ShutDown()
{
    // Stub implementation
}

void CMacOSInput::SetMouseExclusive(bool exclusive, void* hwnd)
{
    // Stub implementation
    if (m_pMouse) m_pMouse->SetExclusive(exclusive, hwnd);
}

void CMacOSInput::SetKeyboardExclusive(bool exclusive, void* hwnd)
{
    // Stub implementation
    if (m_pKeyboard) m_pKeyboard->SetExclusive(exclusive, hwnd);
}

IKeyboard* CMacOSInput::GetIKeyboard()
{
    return m_pKeyboard;
}

IMouse* CMacOSInput::GetIMouse()
{
    return m_pMouse;
}

void CMacOSInput::AddEventListener(IInputEventListener* pListener)
{
    if (std::find(m_listeners.begin(), m_listeners.end(), pListener) == m_listeners.end())
        m_listeners.push_back(pListener);
}

void CMacOSInput::RemoveEventListener(IInputEventListener* pListener)
{
    auto it = std::find(m_listeners.begin(), m_listeners.end(), pListener);
    if (it != m_listeners.end())
        m_listeners.erase(it);
}

void CMacOSInput::EnableEventPosting(bool bEnable)
{
    // Stub implementation
    m_bEventPostingEnabled = bEnable;
}

void CMacOSInput::AddConsoleEventListener(IInputEventListener* pListener)
{
    if (std::find(m_consoleListeners.begin(), m_consoleListeners.end(), pListener) == m_consoleListeners.end())
        m_consoleListeners.push_back(pListener);
}

void CMacOSInput::RemoveConsoleEventListener(IInputEventListener* pListener)
{
    auto it = std::find(m_consoleListeners.begin(), m_consoleListeners.end(), pListener);
    if (it != m_consoleListeners.end())
        m_consoleListeners.erase(it);
}

void CMacOSInput::SetExclusiveListener(IInputEventListener* pListener)
{
    // Stub implementation
}

IInputEventListener* CMacOSInput::GetExclusiveListener()
{
    // Stub implementation - return nullptr
    return nullptr;
}

// Key methods - stub implementations
bool CMacOSInput::KeyDown(int p_key)
{
    return m_pKeyboard ? m_pKeyboard->KeyDown(p_key) : false;
}

bool CMacOSInput::KeyPressed(int p_key)
{
    return m_pKeyboard ? m_pKeyboard->KeyPressed(p_key) : false;
}

bool CMacOSInput::KeyReleased(int p_key)
{
    return m_pKeyboard ? m_pKeyboard->KeyReleased(p_key) : false;
}

// Mouse methods - stub implementations
bool CMacOSInput::MouseDown(int p_numButton)
{
    return m_pMouse ? m_pMouse->MouseDown(p_numButton) : false;
}

bool CMacOSInput::MousePressed(int p_numButton)
{
    return m_pMouse ? m_pMouse->MousePressed(p_numButton) : false;
}

bool CMacOSInput::MouseReleased(int p_numButton)
{
    return m_pMouse ? m_pMouse->MouseReleased(p_numButton) : false;
}

bool CMacOSInput::MouseDblClick(int p_numButton)
{
    if (!m_pMouse) return false;
    const int idx = XKeyToMouseIndex(p_numButton);
    if (idx < 0 || idx >= 8) return false;
    const double kDblClickThreshold = 0.5;
    return m_pMouse->m_buttonStates[idx] && !m_pMouse->m_prevButtonStates[idx]
        && (m_pMouse->m_lastClickTime[idx] - m_pMouse->m_prevClickTime[idx]) < kDblClickThreshold
        && m_pMouse->m_prevClickTime[idx] > 0.0;
}

float CMacOSInput::MouseGetDeltaX()
{
    return m_pMouse ? m_pMouse->GetDeltaX() : 0.0f;
}

float CMacOSInput::MouseGetDeltaY()
{
    return m_pMouse ? m_pMouse->GetDeltaY() : 0.0f;
}

float CMacOSInput::MouseGetDeltaZ()
{
    return m_pMouse ? m_pMouse->GetDeltaZ() : 0.0f;
}

float CMacOSInput::MouseGetVScreenX()
{
    return m_pMouse ? m_pMouse->GetVScreenX() : 0.0f;
}

float CMacOSInput::MouseGetVScreenY()
{
    return m_pMouse ? m_pMouse->GetVScreenY() : 0.0f;
}

// Joystick methods - stub implementations (joystick disabled)
bool CMacOSInput::JoyButtonPressed(int p_numButton)
{
    // Joystick functionality disabled
    return false;
}

int CMacOSInput::JoyGetDir()
{
    // Joystick functionality disabled
    return 0;
}

int CMacOSInput::JoyGetHatDir()
{
    // Joystick functionality disabled
    return 0;
}

Vec3 CMacOSInput::JoyGetAnalog1Dir(unsigned int joystickID) const
{
    // Joystick functionality disabled
    return Vec3(0, 0, 0);
}

Vec3 CMacOSInput::JoyGetAnalog2Dir(unsigned int joystickID) const
{
    // Joystick functionality disabled
    return Vec3(0, 0, 0);
}

// Other methods
int CMacOSInput::GetKeyID(const char* sName)
{
    if (!sName || !sName[0])
        return 0;
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
        { "pgdn",      XKEY_PAGE_DOWN }, { "minus",     XKEY_MINUS     },
        { "equals",    XKEY_EQUALS    }, { "lbracket",  XKEY_LBRACKET  },
        { "rbracket",  XKEY_RBRACKET  }, { "semicolon", XKEY_SEMICOLON },
        { "apostrophe",XKEY_APOSTROPHE}, { "comma",     XKEY_COMMA     },
        { "period",    XKEY_PERIOD    }, { "slash",     XKEY_SLASH     },
        { "backslash", XKEY_BACKSLASH }, { "tilde",     XKEY_TILDE     },
        { "num0", XKEY_NUMPAD0 }, { "num1", XKEY_NUMPAD1 }, { "num2", XKEY_NUMPAD2 },
        { "num3", XKEY_NUMPAD3 }, { "num4", XKEY_NUMPAD4 }, { "num5", XKEY_NUMPAD5 },
        { "num6", XKEY_NUMPAD6 }, { "num7", XKEY_NUMPAD7 }, { "num8", XKEY_NUMPAD8 },
        { "num9", XKEY_NUMPAD9 }, { "numenter", XKEY_NUMPADENTER },
        { "numlock", XKEY_NUMLOCK },
        { "mouse1", XKEY_MOUSE1 }, { "mouse2", XKEY_MOUSE2 },
        { "mouse3", XKEY_MOUSE3 }, { "mwheel_up", XKEY_MWHEEL_UP },
        { "mwheel_dn", XKEY_MWHEEL_DOWN }, { "maxis_x", XKEY_MAXIS_X },
        { "maxis_y", XKEY_MAXIS_Y },
    };
    for (int i = 0; i < (int)(sizeof(kIdMap) / sizeof(kIdMap[0])); ++i)
        if (strcasecmp(kIdMap[i].name, sName) == 0) return kIdMap[i].xkey;
    return 0;
}

void CMacOSInput::EnableBufferedInput(bool bEnable)
{
    // Stub implementation
}

void CMacOSInput::FeedVirtualKey(int nVirtualKey, long lParam, bool bDown)
{
    // Stub implementation
}

int CMacOSInput::GetBufferedKey()
{
    // Stub implementation - return 0
    return 0;
}

const char* CMacOSInput::GetBufferedKeyName()
{
    // Stub implementation - return empty string
    return "";
}

void CMacOSInput::PopBufferedKey()
{
    // Stub implementation
}

void CMacOSInput::SetMouseInertia(float)
{
    // Stub implementation
}

const char* CMacOSInput::GetKeyName(int nKey, int modifiers, bool bGUI)
{
    return m_pKeyboard ? XKeyToName(nKey) : "";
}

bool CMacOSInput::GetOSKeyName(int nKey, wchar_t* szwKeyName, int iBufSize)
{
    if (!szwKeyName || iBufSize <= 0)
        return false;
    const char* name = XKeyToName(nKey);
    if (!name || !name[0])
        return false;
    mbstowcs(szwKeyName, name, (size_t)iBufSize);
    szwKeyName[iBufSize - 1] = L'\0';
    return true;
}

int CMacOSInput::GetKeyPressedCode()
{
    return m_pKeyboard ? m_pKeyboard->GetKeyPressedCode() : 0;
}

const char* CMacOSInput::GetKeyPressedName()
{
    return m_pKeyboard ? m_pKeyboard->GetKeyPressedName() : "";
}

int CMacOSInput::GetKeyDownCode()
{
    return m_pKeyboard ? m_pKeyboard->GetKeyDownCode() : 0;
}

const char* CMacOSInput::GetKeyDownName()
{
    return m_pKeyboard ? m_pKeyboard->GetKeyDownName() : "";
}

void CMacOSInput::WaitForKey()
{
    if (m_pKeyboard) m_pKeyboard->WaitForKey();
}

struct IActionMapManager* CMacOSInput::CreateActionMapManager()
{
    return new CXActionMapManager(this);
}

const char* CMacOSInput::GetXKeyPressedName()
{
    // Stub implementation - return empty string
    return "";
}

void CMacOSInput::ClearKeyState()
{
    if (m_pKeyboard) m_pKeyboard->ClearKeyState();
    if (m_pMouse) m_pMouse->ClearKeyState();
}

unsigned char CMacOSInput::GetKeyState(int nKey)
{
    return (m_pKeyboard && m_pKeyboard->KeyDown(nKey)) ? 1 : 0;
}

void CMacOSInput::PostEvent(const SInputEvent& event)
{
    if (!m_bEventPostingEnabled)
        return;
    for (auto* l : m_consoleListeners)
        if (l->OnInputEvent(event)) return;
    for (auto* l : m_listeners)
        if (l->OnInputEvent(event)) return;
}

#endif // __APPLE__ && __MACH__