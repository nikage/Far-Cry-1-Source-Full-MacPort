////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSInput.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS input system implementation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MacOSInput.h"
#include "ISystem.h"
#include <Foundation/Foundation.h>
#include <AppKit/AppKit.h>

// CMacOSKeyboard implementation
CMacOSKeyboard::CMacOSKeyboard()
    : m_modifiers(0)
    , m_bExclusive(false)
    , m_eventTap(nullptr)
    , m_runLoopSource(nullptr)
{
    memset(m_keyStates, 0, sizeof(m_keyStates));
    memset(m_prevKeyStates, 0, sizeof(m_prevKeyStates));
}

CMacOSKeyboard::~CMacOSKeyboard()
{
    SetExclusive(false, nullptr);
}

bool CMacOSKeyboard::Init()
{
    // Initialize key mapping
    return true;
}

void CMacOSKeyboard::Update()
{
    // Copy current states to previous
    memcpy(m_prevKeyStates, m_keyStates, sizeof(m_keyStates));
    
    // Update modifier keys
    NSUInteger modifierFlags = [NSEvent modifierFlags];
    m_modifiers = 0;
    
    if (modifierFlags & NSEventModifierFlagShift)
        m_modifiers |= 1;  // Shift
    if (modifierFlags & NSEventModifierFlagControl)
        m_modifiers |= 2;  // Ctrl
    if (modifierFlags & NSEventModifierFlagOption)
        m_modifiers |= 4;  // Alt
    if (modifierFlags & NSEventModifierFlagCommand)
        m_modifiers |= 8;  // Cmd
}

bool CMacOSKeyboard::IsKeyDown(int nKey)
{
    if (nKey < 0 || nKey >= 256)
        return false;
    return m_keyStates[nKey];
}

bool CMacOSKeyboard::KeyPressed(int nKey)
{
    if (nKey < 0 || nKey >= 256)
        return false;
    return m_keyStates[nKey] && !m_prevKeyStates[nKey];
}

bool CMacOSKeyboard::KeyReleased(int nKey)
{
    if (nKey < 0 || nKey >= 256)
        return false;
    return !m_keyStates[nKey] && m_prevKeyStates[nKey];
}

int CMacOSKeyboard::ConvertMacOSKeyCode(unsigned short keyCode)
{
    // Map macOS key codes to CryEngine key codes
    // This is a simplified mapping - would need complete key mapping table
    switch (keyCode)
    {
        case 0x00: return 'A';
        case 0x0B: return 'B';
        case 0x08: return 'C';
        case 0x02: return 'D';
        case 0x0E: return 'E';
        case 0x03: return 'F';
        case 0x05: return 'G';
        case 0x04: return 'H';
        case 0x22: return 'I';
        case 0x26: return 'J';
        case 0x28: return 'K';
        case 0x25: return 'L';
        case 0x2E: return 'M';
        case 0x2D: return 'N';
        case 0x1F: return 'O';
        case 0x23: return 'P';
        case 0x0C: return 'Q';
        case 0x0F: return 'R';
        case 0x01: return 'S';
        case 0x11: return 'T';
        case 0x20: return 'U';
        case 0x09: return 'V';
        case 0x0D: return 'W';
        case 0x07: return 'X';
        case 0x10: return 'Y';
        case 0x06: return 'Z';
        
        case 0x24: return 13;  // Return
        case 0x30: return 9;   // Tab
        case 0x31: return 32;  // Space
        case 0x33: return 8;   // Backspace
        case 0x35: return 27;  // Escape
        
        default: return keyCode; // Fallback
    }
}

CGEventRef CMacOSKeyboard::EventTapCallback(CGEventTapProxy proxy, CGEventType type, 
                                           CGEventRef event, void* userInfo)
{
    CMacOSKeyboard* keyboard = static_cast<CMacOSKeyboard*>(userInfo);
    
    if (type == kCGEventKeyDown || type == kCGEventKeyUp)
    {
        CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        int mappedKey = keyboard->ConvertMacOSKeyCode(keyCode);
        
        if (mappedKey >= 0 && mappedKey < 256)
        {
            keyboard->m_keyStates[mappedKey] = (type == kCGEventKeyDown);
        }
    }
    
    return event;
}

void CMacOSKeyboard::SetExclusive(bool value, IInput* pInput)
{
    if (value == m_bExclusive)
        return;
    
    m_bExclusive = value;
    
    if (value)
    {
        // Create event tap for exclusive input
        m_eventTap = CGEventTapCreate(kCGSessionEventTap,
                                     kCGHeadInsertEventTap,
                                     kCGEventTapOptionDefault,
                                     CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp),
                                     EventTapCallback,
                                     this);
        
        if (m_eventTap)
        {
            m_runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, m_eventTap, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), m_runLoopSource, kCFRunLoopCommonModes);
            CGEventTapEnable(m_eventTap, true);
        }
    }
    else
    {
        // Clean up event tap
        if (m_eventTap)
        {
            CGEventTapEnable(m_eventTap, false);
            CFRelease(m_eventTap);
            m_eventTap = nullptr;
        }
        
        if (m_runLoopSource)
        {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), m_runLoopSource, kCFRunLoopCommonModes);
            CFRelease(m_runLoopSource);
            m_runLoopSource = nullptr;
        }
    }
}

// CMacOSMouse implementation
CMacOSMouse::CMacOSMouse()
    : m_x(0), m_y(0), m_prevX(0), m_prevY(0)
    , m_wheelDelta(0), m_bHidden(false), m_bExclusive(false)
    , m_eventTap(nullptr), m_runLoopSource(nullptr)
{
    memset(m_buttonStates, 0, sizeof(m_buttonStates));
    memset(m_prevButtonStates, 0, sizeof(m_prevButtonStates));
}

CMacOSMouse::~CMacOSMouse()
{
    SetExclusive(false, nullptr);
}

bool CMacOSMouse::Init()
{
    return true;
}

void CMacOSMouse::Update()
{
    // Copy current states to previous
    memcpy(m_prevButtonStates, m_buttonStates, sizeof(m_buttonStates));
    m_prevX = m_x;
    m_prevY = m_y;
    
    // Get current mouse position
    NSPoint mouseLocation = [NSEvent mouseLocation];
    m_x = (int)mouseLocation.x;
    m_y = (int)mouseLocation.y;
    
    // Reset wheel delta
    m_wheelDelta = 0;
}

void CMacOSMouse::GetPos(int& x, int& y)
{
    x = m_x;
    y = m_y;
}

void CMacOSMouse::SetPos(int x, int y)
{
    CGPoint point = CGPointMake(x, y);
    CGWarpMouseCursorPosition(point);
    m_x = x;
    m_y = y;
}

bool CMacOSMouse::IsButtonDown(int nButton)
{
    if (nButton < 0 || nButton >= 8)
        return false;
    return m_buttonStates[nButton];
}

bool CMacOSMouse::ButtonPressed(int nButton)
{
    if (nButton < 0 || nButton >= 8)
        return false;
    return m_buttonStates[nButton] && !m_prevButtonStates[nButton];
}

bool CMacOSMouse::ButtonReleased(int nButton)
{
    if (nButton < 0 || nButton >= 8)
        return false;
    return !m_buttonStates[nButton] && m_prevButtonStates[nButton];
}

void CMacOSMouse::Hide(bool hide)
{
    m_bHidden = hide;
    
    if (hide)
    {
        CGDisplayHideCursor(kCGDirectMainDisplay);
    }
    else
    {
        CGDisplayShowCursor(kCGDirectMainDisplay);
    }
}

CGEventRef CMacOSMouse::MouseEventTapCallback(CGEventTapProxy proxy, CGEventType type,
                                             CGEventRef event, void* userInfo)
{
    CMacOSMouse* mouse = static_cast<CMacOSMouse*>(userInfo);
    
    switch (type)
    {
        case kCGEventLeftMouseDown:
            mouse->m_buttonStates[0] = true;
            break;
        case kCGEventLeftMouseUp:
            mouse->m_buttonStates[0] = false;
            break;
        case kCGEventRightMouseDown:
            mouse->m_buttonStates[1] = true;
            break;
        case kCGEventRightMouseUp:
            mouse->m_buttonStates[1] = false;
            break;
        case kCGEventOtherMouseDown:
        case kCGEventOtherMouseUp:
        {
            int64_t buttonNumber = CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
            if (buttonNumber >= 2 && buttonNumber < 8)
            {
                mouse->m_buttonStates[buttonNumber] = (type == kCGEventOtherMouseDown);
            }
            break;
        }
        case kCGEventScrollWheel:
        {
            int64_t deltaY = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1);
            mouse->m_wheelDelta += (int)deltaY;
            break;
        }
    }
    
    return event;
}

void CMacOSMouse::SetExclusive(bool value, IInput* pInput)
{
    if (value == m_bExclusive)
        return;
    
    m_bExclusive = value;
    
    if (value)
    {
        // Create event tap for mouse events
        CGEventMask eventMask = CGEventMaskBit(kCGEventLeftMouseDown) |
                               CGEventMaskBit(kCGEventLeftMouseUp) |
                               CGEventMaskBit(kCGEventRightMouseDown) |
                               CGEventMaskBit(kCGEventRightMouseUp) |
                               CGEventMaskBit(kCGEventOtherMouseDown) |
                               CGEventMaskBit(kCGEventOtherMouseUp) |
                               CGEventMaskBit(kCGEventScrollWheel);
        
        m_eventTap = CGEventTapCreate(kCGSessionEventTap,
                                     kCGHeadInsertEventTap,
                                     kCGEventTapOptionDefault,
                                     eventMask,
                                     MouseEventTapCallback,
                                     this);
        
        if (m_eventTap)
        {
            m_runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, m_eventTap, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), m_runLoopSource, kCFRunLoopCommonModes);
            CGEventTapEnable(m_eventTap, true);
        }
    }
    else
    {
        // Clean up event tap
        if (m_eventTap)
        {
            CGEventTapEnable(m_eventTap, false);
            CFRelease(m_eventTap);
            m_eventTap = nullptr;
        }
        
        if (m_runLoopSource)
        {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), m_runLoopSource, kCFRunLoopCommonModes);
            CFRelease(m_runLoopSource);
            m_runLoopSource = nullptr;
        }
    }
}

// CMacOSInput implementation
CMacOSInput::CMacOSInput()
    : m_pKeyboard(nullptr)
    , m_pMouse(nullptr)
    , m_pJoystick(nullptr)
    , m_bExclusiveMode(false)
    , m_bEventPostingEnabled(true)
    , m_pSystem(nullptr)
    , m_window(nil)
{
}

CMacOSInput::~CMacOSInput()
{
    ShutDown();
}

bool CMacOSInput::Init(ISystem* pSystem)
{
    if (!pSystem)
        return false;
    
    m_pSystem = pSystem;
    
    // Create input devices
    m_pKeyboard = new CMacOSKeyboard();
    m_pMouse = new CMacOSMouse();
    m_pJoystick = new CMacOSJoystick();
    
    if (!m_pKeyboard->Init() || !m_pMouse->Init() || !m_pJoystick->Init())
    {
        pSystem->GetILog()->Log("Error: Failed to initialize macOS input devices");
        ShutDown();
        return false;
    }
    
    pSystem->GetILog()->Log("macOS input system initialized successfully");
    return true;
}

void CMacOSInput::Update()
{
    if (m_pKeyboard) m_pKeyboard->Update();
    if (m_pMouse) m_pMouse->Update();
    if (m_pJoystick) m_pJoystick->Update();
}

void CMacOSInput::ShutDown()
{
    if (m_pKeyboard)
    {
        delete m_pKeyboard;
        m_pKeyboard = nullptr;
    }
    
    if (m_pMouse)
    {
        delete m_pMouse;
        m_pMouse = nullptr;
    }
    
    if (m_pJoystick)
    {
        delete m_pJoystick;
        m_pJoystick = nullptr;
    }
    
    m_listeners.clear();
    m_consoleListeners.clear();
}

// Stub implementations for remaining interface methods
void CMacOSInput::SetExclusiveMode(bool value) { m_bExclusiveMode = value; }
IKeyboard* CMacOSInput::GetKeyboard() { return m_pKeyboard; }
IMouse* CMacOSInput::GetMouse() { return m_pMouse; }
IJoystick* CMacOSInput::GetJoystick() { return m_pJoystick; }
bool CMacOSInput::AddEventListener(IInputEventListener* pListener) { return true; }
bool CMacOSInput::RemoveEventListener(IInputEventListener* pListener) { return true; }
void CMacOSInput::AddConsoleEventListener(IInputEventListener* pListener) {}
void CMacOSInput::RemoveConsoleEventListener(IInputEventListener* pListener) {}
void CMacOSInput::SetMouseExclusive(bool value, const char* cause) {}
void CMacOSInput::GetMousePos(int& x, int& y) { if (m_pMouse) m_pMouse->GetPos(x, y); }
void CMacOSInput::SetMousePos(int x, int y) { if (m_pMouse) m_pMouse->SetPos(x, y); }
bool CMacOSInput::GetInputChar(SInputKeyData& rKeyData) { return false; }
void CMacOSInput::EnableEventPosting(bool bEnable) { m_bEventPostingEnabled = bEnable; }
bool CMacOSInput::IsEventPostingEnabled() { return m_bEventPostingEnabled; }
void CMacOSInput::PostInputEvent(SInputKeyData& rKeyData) {}

// CMacOSJoystick stub implementation
CMacOSJoystick::CMacOSJoystick() : m_hidManager(nullptr), m_devices(nullptr)
{
    memset(&m_state, 0, sizeof(m_state));
}

CMacOSJoystick::~CMacOSJoystick() {}
bool CMacOSJoystick::Init() { return true; }
void CMacOSJoystick::Update() {}
bool CMacOSJoystick::IsButtonDown(int nButton) { return false; }
bool CMacOSJoystick::ButtonPressed(int nButton) { return false; }
bool CMacOSJoystick::ButtonReleased(int nButton) { return false; }
float CMacOSJoystick::GetAxisValue(int nAxis) { return 0.0f; }
int CMacOSJoystick::GetAxisValueRaw(int nAxis) { return 0; }
void CMacOSJoystick::SetDeadZone(int nAxis, float fThreshold) {}
void CMacOSJoystick::SetForceFeedback(IFFParams& ffparams) {}

#endif // __APPLE__ && __MACH__
