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
#include "Cry_Math.h"  // For Vec3
#include <cassert>

// Forward declarations

// macOS-specific keyboard implementation
class CMacOSKeyboard : public IKeyboard
{
public:
    CMacOSKeyboard();
    virtual ~CMacOSKeyboard();
    
    // IKeyboard interface
    virtual void ShutDown() override;
    virtual bool KeyDown(int p_key) override;
    virtual bool KeyPressed(int p_key) override;
    virtual bool KeyReleased(int p_key) override;
    virtual void ClearKey(int p_key) override;
    virtual int GetKeyPressedCode() override;
    virtual const char* GetKeyPressedName() override;
    virtual int GetKeyDownCode() override;
    virtual const char* GetKeyDownName() override;
    virtual void SetExclusive(bool value, void* hwnd = 0) override;
    virtual void WaitForKey() override;
    virtual void ClearKeyState() override;
    
    // Additional methods not in interface
    bool Init();
    void Update();
    
protected:
    bool m_keyStates[256];
    bool m_prevKeyStates[256];
    int m_modifiers;
    
    // Convert macOS key codes to CryEngine key codes
    int ConvertMacOSKeyCode(unsigned short keyCode);
    
    // Event handling
    void ProcessKeyEvent(void* event, bool isKeyDown);
    
private:
    bool m_bExclusive;
    void* m_eventTap;  // CFMachPortRef
    void* m_runLoopSource;  // CFRunLoopSourceRef
    
    static void* EventTapCallback(void* proxy, int type, void* event, void* userInfo);
};

// macOS-specific mouse implementation  
class CMacOSMouse : public IMouse
{
public:
    CMacOSMouse();
    virtual ~CMacOSMouse();
    
    // IMouse interface
    virtual bool Init(); // Not in base interface
    virtual void Update(); // Not in base interface
    virtual bool SetExclusive(bool value, void* hwnd = 0) override;
    virtual void GetPos(int& x, int& y); // Not in base interface
    virtual void SetPos(int x, int y); // Not in base interface
    virtual bool IsButtonDown(int nButton); // Not in base interface
    virtual bool ButtonPressed(int nButton); // Not in base interface
    virtual bool ButtonReleased(int nButton); // Not in base interface
    virtual int GetWheelDelta(); // Not in base interface
    virtual void Hide(bool hide); // Not in base interface
    
    // Actual IMouse interface methods
    virtual void Shutdown() override;
    virtual bool MouseDown(int p_numButton) override;
    virtual bool MousePressed(int p_numButton) override;
    virtual bool MouseReleased(int p_numButton) override;
    virtual void SetMouseWheelRotation(int value) override;
    virtual float GetDeltaX() override;
    virtual float GetDeltaY() override;
    virtual float GetDeltaZ() override;
    virtual void SetInertia(float) override;
    virtual void SetVScreenX(float fX) override;
    virtual void SetVScreenY(float fY) override;
    virtual float GetVScreenX() override;
    virtual float GetVScreenY() override;
    virtual void SetSensitvity(float fSensitivity) override;
    virtual float GetSensitvity() override;
    virtual void SetSensitvityScale(float fSensScale) override;
    virtual float GetSensitvityScale() override;
    virtual void ClearKeyState() override;
    
protected:
    int m_x, m_y;
    int m_prevX, m_prevY;
    bool m_buttonStates[8];
    bool m_prevButtonStates[8];
    int m_wheelDelta;
    bool m_bHidden;
    bool m_bExclusive;
    float m_fVScreenX;
    float m_fVScreenY;
    float m_screenWidth;
    float m_screenHeight;
    
    void ProcessMouseEvent(void* event);
    int ConvertMacOSButton(int button);
    
private:
    void* m_eventTap;  // CFMachPortRef
    void* m_runLoopSource;  // CFRunLoopSourceRef
    
    static void* MouseEventTapCallback(void* proxy, int type, void* event, void* userInfo);
};

// Simple joystick interface for compatibility
struct IJoystick
{
    virtual ~IJoystick() = default;
    virtual bool Init() = 0;
    virtual void Update() = 0;
    virtual void Shutdown() = 0;
};

// macOS-specific joystick/gamepad implementation using HID
// Note: Joystick functionality is optional and commented out for now
/*
class CMacOSJoystick : public IJoystick
{
public:
    CMacOSJoystick();
    virtual ~CMacOSJoystick();
    
    // IJoystick interface
    virtual bool Init() override;
    virtual void Update() override;
    virtual void Shutdown() override;
    
    // Additional joystick methods (not in base interface)
    virtual bool IsButtonDown(int nButton);
    virtual bool ButtonPressed(int nButton);
    virtual bool ButtonReleased(int nButton);
    virtual float GetAxisValue(int nAxis);
    virtual int GetAxisValueRaw(int nAxis);
    virtual void SetDeadZone(int nAxis, float fThreshold);
    virtual void SetForceFeedback(void* ffparams); // IFFParams not defined, using void*
    
protected:
    void* m_hidManager;  // IOHIDManagerRef
    void* m_devices;     // CFMutableArrayRef
    
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
*/

// Main macOS input system
class CMacOSInput : public IInput
{
public:
    CMacOSInput();
    virtual ~CMacOSInput();
    
    // IInput interface
    virtual void Update(bool bFocus) override;
    virtual void ShutDown() override;
    virtual void SetMouseExclusive(bool exclusive, void* hwnd = 0) override;
    virtual void SetKeyboardExclusive(bool exclusive, void* hwnd = 0) override;
    virtual IKeyboard* GetIKeyboard() override;
    virtual IMouse* GetIMouse() override;
    virtual void AddEventListener(IInputEventListener* pListener) override;
    virtual void RemoveEventListener(IInputEventListener* pListener) override;
    virtual void EnableEventPosting(bool bEnable) override;
    virtual void AddConsoleEventListener(IInputEventListener* pListener) override;
    virtual void RemoveConsoleEventListener(IInputEventListener* pListener) override;
    virtual void SetExclusiveListener(IInputEventListener* pListener) override;
    virtual IInputEventListener* GetExclusiveListener() override;
    
    // Key methods
    virtual bool KeyDown(int p_key) override;
    virtual bool KeyPressed(int p_key) override;
    virtual bool KeyReleased(int p_key) override;
    
    // Mouse methods
    virtual bool MouseDown(int p_numButton) override;
    virtual bool MousePressed(int p_numButton) override;
    virtual bool MouseDblClick(int p_numButton) override;
    virtual bool MouseReleased(int p_numButton) override;
    virtual float MouseGetDeltaX() override;
    virtual float MouseGetDeltaY() override;
    virtual float MouseGetDeltaZ() override;
    virtual float MouseGetVScreenX() override;
    virtual float MouseGetVScreenY() override;
    
    // Joystick methods
    virtual bool JoyButtonPressed(int p_numButton) override;
    virtual int JoyGetDir() override;
    virtual int JoyGetHatDir() override;
    virtual Vec3 JoyGetAnalog1Dir(unsigned int joystickID) const override;
    virtual Vec3 JoyGetAnalog2Dir(unsigned int joystickID) const override;
    
    // Other methods
    virtual int GetKeyID(const char* sName) override;
    virtual void EnableBufferedInput(bool bEnable) override;
    virtual void FeedVirtualKey(int nVirtualKey, long lParam, bool bDown) override;
    virtual int GetBufferedKey() override;
    virtual const char* GetBufferedKeyName() override;
    virtual void PopBufferedKey() override;
    virtual void SetMouseInertia(float) override;
    virtual const char* GetKeyName(int nKey, int modifiers = 0, bool bGUI = 0) override;
    virtual bool GetOSKeyName(int nKey, wchar_t* szwKeyName, int iBufSize) override;
    virtual int GetKeyPressedCode() override;
    virtual const char* GetKeyPressedName() override;
    virtual int GetKeyDownCode() override;
    virtual const char* GetKeyDownName() override;
    virtual void WaitForKey() override;
    virtual struct IActionMapManager* CreateActionMapManager() override;
    virtual const char* GetXKeyPressedName() override;
    virtual void ClearKeyState() override;
    virtual unsigned char GetKeyState(int nKey) override;
    
protected:
    CMacOSKeyboard* m_pKeyboard;
    CMacOSMouse* m_pMouse;
    // CMacOSJoystick* m_pJoystick; // Joystick disabled
    
    std::vector<IInputEventListener*> m_listeners;
    std::vector<IInputEventListener*> m_consoleListeners;
    
    bool m_bExclusiveMode;
    bool m_bEventPostingEnabled;
    
    void PostEvent(const SInputEvent& event);
    
private:
    ISystem* m_pSystem;
    void* m_window;  // NSWindow* but using void* to avoid Objective-C conflicts
};

#endif // __APPLE__ && __MACH__

#endif // MACOS_INPUT_H
