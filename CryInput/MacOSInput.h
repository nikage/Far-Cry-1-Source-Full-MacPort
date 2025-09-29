////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSInput.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS-specific input system using HID and Core Input
//               Replaces DirectInput functionality for cross-platform support
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef MACOS_INPUT_H
#define MACOS_INPUT_H

#if defined(__APPLE__) && defined(__MACH__)

#include "IInput.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDLib.h>
#include <Carbon/Carbon.h>

// Forward declarations
@class NSEvent;
@class NSWindow;

// macOS-specific keyboard implementation
class CMacOSKeyboard : public IKeyboard
{
public:
    CMacOSKeyboard();
    virtual ~CMacOSKeyboard();
    
    // IKeyboard interface
    virtual bool Init() override;
    virtual void Update() override;
    virtual void SetExclusive(bool value, IInput* pInput) override;
    virtual bool IsKeyDown(int nKey) override;
    virtual bool KeyPressed(int nKey) override;
    virtual bool KeyReleased(int nKey) override;
    virtual int GetModifiers() override;
    virtual void ClearKey(int nKey) override;
    virtual const char* GetKeyName(int nKey) override;
    virtual wchar_t GetInputCharAscii() override;
    virtual unsigned int GetKeyboardChar() override;
    
protected:
    bool m_keyStates[256];
    bool m_prevKeyStates[256];
    int m_modifiers;
    
    // Convert macOS key codes to CryEngine key codes
    int ConvertMacOSKeyCode(unsigned short keyCode);
    
    // Event handling
    void ProcessKeyEvent(NSEvent* event, bool isKeyDown);
    
private:
    bool m_bExclusive;
    CFMachPortRef m_eventTap;
    CFRunLoopSourceRef m_runLoopSource;
    
    static CGEventRef EventTapCallback(CGEventTapProxy proxy, CGEventType type, 
                                      CGEventRef event, void* userInfo);
};

// macOS-specific mouse implementation  
class CMacOSMouse : public IMouse
{
public:
    CMacOSMouse();
    virtual ~CMacOSMouse();
    
    // IMouse interface
    virtual bool Init() override;
    virtual void Update() override;
    virtual void SetExclusive(bool value, IInput* pInput) override;
    virtual void GetPos(int& x, int& y) override;
    virtual void SetPos(int x, int y) override;
    virtual bool IsButtonDown(int nButton) override;
    virtual bool ButtonPressed(int nButton) override;
    virtual bool ButtonReleased(int nButton) override;
    virtual int GetWheelDelta() override;
    virtual void Hide(bool hide) override;
    
protected:
    int m_x, m_y;
    int m_prevX, m_prevY;
    bool m_buttonStates[8];
    bool m_prevButtonStates[8];
    int m_wheelDelta;
    bool m_bHidden;
    bool m_bExclusive;
    
    void ProcessMouseEvent(NSEvent* event);
    int ConvertMacOSButton(int button);
    
private:
    CFMachPortRef m_eventTap;
    CFRunLoopSourceRef m_runLoopSource;
    
    static CGEventRef MouseEventTapCallback(CGEventTapProxy proxy, CGEventType type,
                                           CGEventRef event, void* userInfo);
};

// macOS-specific joystick/gamepad implementation using HID
class CMacOSJoystick : public IJoystick
{
public:
    CMacOSJoystick();
    virtual ~CMacOSJoystick();
    
    // IJoystick interface
    virtual bool Init() override;
    virtual void Update() override;
    virtual bool IsButtonDown(int nButton) override;
    virtual bool ButtonPressed(int nButton) override;
    virtual bool ButtonReleased(int nButton) override;
    virtual float GetAxisValue(int nAxis) override;
    virtual int GetAxisValueRaw(int nAxis) override;
    virtual void SetDeadZone(int nAxis, float fThreshold) override;
    virtual void SetForceFeedback(IFFParams& ffparams) override;
    
protected:
    IOHIDManagerRef m_hidManager;
    CFMutableArrayRef m_devices;
    
    struct JoystickState
    {
        bool buttons[32];
        bool prevButtons[32];
        float axes[8];
        float deadZones[8];
    } m_state;
    
    void EnumerateDevices();
    void ProcessHIDInput(IOHIDDeviceRef device, IOHIDValueRef value);
    
private:
    static void HIDInputCallback(void* context, IOReturn result, void* sender, IOHIDValueRef value);
    static void HIDDeviceMatchingCallback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device);
    static void HIDDeviceRemovalCallback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device);
};

// Main macOS input system
class CMacOSInput : public IInput
{
public:
    CMacOSInput();
    virtual ~CMacOSInput();
    
    // IInput interface
    virtual bool Init(ISystem* pSystem) override;
    virtual void Update() override;
    virtual void ShutDown() override;
    virtual void SetExclusiveMode(bool value) override;
    virtual IKeyboard* GetKeyboard() override;
    virtual IMouse* GetMouse() override;
    virtual IJoystick* GetJoystick() override;
    virtual bool AddEventListener(IInputEventListener* pListener) override;
    virtual bool RemoveEventListener(IInputEventListener* pListener) override;
    virtual void AddConsoleEventListener(IInputEventListener* pListener) override;
    virtual void RemoveConsoleEventListener(IInputEventListener* pListener) override;
    virtual void SetMouseExclusive(bool value, const char* cause) override;
    virtual void GetMousePos(int& x, int& y) override;
    virtual void SetMousePos(int x, int y) override;
    virtual bool GetInputChar(SInputKeyData& rKeyData) override;
    virtual void EnableEventPosting(bool bEnable) override;
    virtual bool IsEventPostingEnabled() override;
    virtual void PostInputEvent(SInputKeyData& rKeyData) override;
    
protected:
    CMacOSKeyboard* m_pKeyboard;
    CMacOSMouse* m_pMouse;
    CMacOSJoystick* m_pJoystick;
    
    std::vector<IInputEventListener*> m_listeners;
    std::vector<IInputEventListener*> m_consoleListeners;
    
    bool m_bExclusiveMode;
    bool m_bEventPostingEnabled;
    
    void PostEvent(const SInputKeyData& event);
    
private:
    ISystem* m_pSystem;
    NSWindow* m_window;
};

#endif // __APPLE__ && __MACH__

#endif // MACOS_INPUT_H
