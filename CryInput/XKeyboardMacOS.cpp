////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   XKeyboardMacOS.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS keyboard implementation using Core Graphics
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "XKeyboard.h"
#include "ISystem.h"
#include <CoreGraphics/CoreGraphics.h>
#include <Carbon/Carbon.h>
#include <cstring>

// CXKeyboard implementation for macOS
CXKeyboard::CXKeyboard()
    : m_pInput(nullptr)
    , m_pLog(nullptr)
    , m_pSystem(nullptr)
    , m_bExclusiveMode(false)
{
    memset(m_cKeysState, 0, sizeof(m_cKeysState));
    memset(m_cOldKeysState, 0, sizeof(m_cOldKeysState));
}

CXKeyboard::~CXKeyboard()
{
    ShutDown();
}

bool CXKeyboard::Init(CInput* pInput, ISystem* pSystem, void* &g_pdi, void* hinst, void* hwnd3)
{
    m_pSystem = pSystem;
    return true;
}

void CXKeyboard::Update()
{
    // Update previous key states
    memcpy(m_cOldKeysState, m_cKeysState, sizeof(m_cKeysState));
    
    // Update current key states using Core Graphics
    for (int i = 0; i < 256; i++) {
        m_cKeysState[i] = CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, i) ? 0x80 : 0;
    }
}

void CXKeyboard::ShutDown()
{
    // Cleanup if needed
}

bool CXKeyboard::KeyDown(int p_key)
{
    if (p_key < 0 || p_key >= 256) return false;
    return m_cKeysState[p_key] != 0;
}

bool CXKeyboard::KeyPressed(int p_key)
{
    if (p_key < 0 || p_key >= 256) return false;
    return (m_cKeysState[p_key] != 0) && (m_cOldKeysState[p_key] == 0);
}

bool CXKeyboard::KeyReleased(int p_key)
{
    if (p_key < 0 || p_key >= 256) return false;
    return (m_cKeysState[p_key] == 0) && (m_cOldKeysState[p_key] != 0);
}

void CXKeyboard::ClearKey(int p_key)
{
    if (p_key >= 0 && p_key < 256) {
        m_cKeysState[p_key] = 0;
        m_cOldKeysState[p_key] = 0;
    }
}

int CXKeyboard::GetKeyPressedCode()
{
    for (int i = 0; i < 256; i++) {
        if (KeyPressed(i)) return i;
    }
    return 0;
}

static const char* HIDKeyCodeToName(int hidCode)
{
    static const struct { int hid; const char* name; } kMap[] = {
        { 0,  "a" },  { 1,  "s" },  { 2,  "d" },  { 3,  "f" },
        { 4,  "h" },  { 5,  "g" },  { 6,  "z" },  { 7,  "x" },
        { 8,  "c" },  { 9,  "v" },  { 11, "b" },  { 12, "q" },
        { 13, "w" },  { 14, "e" },  { 15, "r" },  { 16, "y" },
        { 17, "t" },  { 18, "1" },  { 19, "2" },  { 20, "3" },
        { 21, "4" },  { 22, "6" },  { 23, "5" },  { 24, "equals" },
        { 25, "9" },  { 26, "7" },  { 27, "minus" }, { 28, "8" },
        { 29, "0" },  { 30, "rbracket" }, { 31, "o" }, { 32, "u" },
        { 33, "lbracket" }, { 34, "i" }, { 35, "p" }, { 36, "enter" },
        { 37, "l" },  { 38, "j" },  { 39, "apostrophe" }, { 40, "k" },
        { 41, "semicolon" }, { 42, "backslash" }, { 43, "comma" },
        { 44, "slash" }, { 45, "n" }, { 46, "m" },
        { 47, "period" }, { 48, "tab" }, { 49, "space" },
        { 50, "tilde" }, { 51, "backspace" }, { 53, "escape" },
        { 55, "lwindow" },
        { 56, "lshift" }, { 57, "capslock" }, { 58, "lalt" },
        { 59, "lctrl" }, { 60, "rshift" }, { 61, "ralt" },
        { 62, "rctrl" },
        { 71, "numlock" }, { 72, "numenter" },
        { 75, "slash" }, { 76, "numenter" }, { 78, "minus" },
        { 82, "num0" }, { 83, "num1" }, { 84, "num2" },
        { 85, "num3" }, { 86, "num4" }, { 87, "num5" },
        { 88, "num6" }, { 89, "num7" },
        { 91, "num8" }, { 92, "num9" },
        { 96,  "f5"  }, { 97,  "f6"  }, { 98,  "f7"  }, { 99,  "f3"  },
        { 100, "f8"  }, { 101, "f9"  }, { 103, "f11" },
        { 105, "f13" }, { 107, "f14" }, { 109, "f10" }, { 111, "f12" },
        { 113, "f15" }, { 114, "insert" }, { 115, "home" },
        { 116, "pgup" }, { 117, "delete" }, { 118, "f4" },
        { 119, "end" }, { 120, "f2" }, { 121, "pgdn" },
        { 122, "f1" }, { 123, "left" }, { 124, "right" },
        { 125, "down" }, { 126, "up" },
    };
    for (int i = 0; i < (int)(sizeof(kMap)/sizeof(kMap[0])); ++i)
        if (kMap[i].hid == hidCode) return kMap[i].name;
    return "";
}

const char* CXKeyboard::GetKeyPressedName()
{
    int key = GetKeyPressedCode();
    if (key == 0) return "";
    return HIDKeyCodeToName(key);
}

int CXKeyboard::GetKeyDownCode()
{
    for (int i = 0; i < 256; i++) {
        if (KeyDown(i)) return i;
    }
    return 0;
}

const char* CXKeyboard::GetKeyDownName()
{
    int key = GetKeyDownCode();
    if (key == 0) return "";
    return HIDKeyCodeToName(key);
}

void CXKeyboard::SetExclusive(bool value, void* hwnd)
{
    m_bExclusiveMode = value;
}

void CXKeyboard::WaitForKey()
{
    // Stub implementation - would need event loop integration
}

void CXKeyboard::ClearKeyState()
{
    memset(m_cKeysState, 0, sizeof(m_cKeysState));
    memset(m_cOldKeysState, 0, sizeof(m_cOldKeysState));
}

bool CXKeyboard::GetOSKeyName(int nKey, wchar_t* szwKeyName, int iBufSize)
{
    // Stub implementation - would need key code to name mapping
    if (szwKeyName && iBufSize > 0) {
        szwKeyName[0] = L'\0';
    }
    return false;
}

void CXKeyboard::FeedVirtualKey(int nVirtualKey, long lParam, bool bDown)
{
    // Stub implementation - would simulate key press/release
    if (nVirtualKey >= 0 && nVirtualKey < 256) {
        m_cKeysState[nVirtualKey] = bDown ? 0x80 : 0;
    }
}

unsigned char CXKeyboard::GetKeyState(int nKey)
{
    // Return the current key state
    if (nKey >= 0 && nKey < 256) {
        return m_cKeysState[nKey];
    }
    return 0;
}

unsigned char CXKeyboard::XKEY2ASCII(unsigned short nKey, int modifiers)
{
    // Handle modifier keys
    bool shift = (modifiers & 0x01) != 0;  // Shift key
    bool ctrl = (modifiers & 0x02) != 0;   // Ctrl key
    bool alt = (modifiers & 0x04) != 0;    // Alt key
    
    // If Ctrl or Alt is pressed, return 0 (no printable character)
    if (ctrl || alt) {
        return 0;
    }
    
    // Handle special keys
    switch (nKey) {
        case 0x08: return 0x08; // Backspace
        case 0x09: return 0x09; // Tab
        case 0x0D: return 0x0D; // Enter/Return
        case 0x1B: return 0x1B; // Escape
        case 0x20: return 0x20; // Space
        
        // Number keys (0-9)
        case 0x30: return '0';
        case 0x31: return '1';
        case 0x32: return '2';
        case 0x33: return '3';
        case 0x34: return '4';
        case 0x35: return '5';
        case 0x36: return '6';
        case 0x37: return '7';
        case 0x38: return '8';
        case 0x39: return '9';
        
        // Letter keys (A-Z)
        case 0x41: return shift ? 'A' : 'a';
        case 0x42: return shift ? 'B' : 'b';
        case 0x43: return shift ? 'C' : 'c';
        case 0x44: return shift ? 'D' : 'd';
        case 0x45: return shift ? 'E' : 'e';
        case 0x46: return shift ? 'F' : 'f';
        case 0x47: return shift ? 'G' : 'g';
        case 0x48: return shift ? 'H' : 'h';
        case 0x49: return shift ? 'I' : 'i';
        case 0x4A: return shift ? 'J' : 'j';
        case 0x4B: return shift ? 'K' : 'k';
        case 0x4C: return shift ? 'L' : 'l';
        case 0x4D: return shift ? 'M' : 'm';
        case 0x4E: return shift ? 'N' : 'n';
        case 0x4F: return shift ? 'O' : 'o';
        case 0x50: return shift ? 'P' : 'p';
        case 0x51: return shift ? 'Q' : 'q';
        case 0x52: return shift ? 'R' : 'r';
        case 0x53: return shift ? 'S' : 's';
        case 0x54: return shift ? 'T' : 't';
        case 0x55: return shift ? 'U' : 'u';
        case 0x56: return shift ? 'V' : 'v';
        case 0x57: return shift ? 'W' : 'w';
        case 0x58: return shift ? 'X' : 'x';
        case 0x59: return shift ? 'Y' : 'y';
        case 0x5A: return shift ? 'Z' : 'z';
        
        // Symbol keys
        case 0xBA: return shift ? ':' : ';';  // Semicolon/Colon
        case 0xBB: return shift ? '+' : '=';  // Equals/Plus
        case 0xBC: return shift ? '<' : ',';  // Comma/Less than
        case 0xBD: return shift ? '_' : '-';  // Minus/Underscore
        case 0xBE: return shift ? '>' : '.';  // Period/Greater than
        case 0xBF: return shift ? '?' : '/';  // Slash/Question mark
        case 0xC0: return shift ? '~' : '`';  // Grave accent/Tilde
        
        // Bracket keys
        case 0xDB: return shift ? '{' : '[';  // Left bracket
        case 0xDC: return shift ? '|' : '\\'; // Backslash
        case 0xDD: return shift ? '}' : ']';  // Right bracket
        case 0xDE: return shift ? '"' : '\''; // Quote
        
        default:
            // For other keys, return 0 (not printable)
            return 0;
    }
}

#endif // __APPLE__ && __MACH__