////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   JoystickMacOS.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS joystick stub implementation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "Joystick.h"

// CJoystick stub implementation for macOS
CJoystick::CJoystick()
    : m_initialized(false)
    , m_hatswitch(false)
    , m_numbuttons(0)
    , m_joytime(0.0f)
    , m_numjoysticks(0)
    , m_vAnalog1Dir(nullptr)
    , m_vAnalog2Dir(nullptr)
    , m_pLog(nullptr)
{
    memset(m_buttons, 0, sizeof(m_buttons));
    memset(m_dirs, 0, sizeof(m_dirs));
    memset(m_hatdirs, 0, sizeof(m_hatdirs));
}

CJoystick::~CJoystick()
{
    ShutDown();
}

bool CJoystick::Init(ILog *pLog)
{
    // Stub implementation - joystick functionality disabled on macOS
    m_pLog = pLog;
    m_initialized = true;
    return true;
}

void CJoystick::Update()
{
    // Stub implementation - no actual update needed
}

void CJoystick::ShutDown()
{
    // Stub implementation
    if (m_vAnalog1Dir) {
        delete[] m_vAnalog1Dir;
        m_vAnalog1Dir = nullptr;
    }
    if (m_vAnalog2Dir) {
        delete[] m_vAnalog2Dir;
        m_vAnalog2Dir = nullptr;
    }
    m_initialized = false;
}

int CJoystick::GetNumButtons()
{
    // Stub implementation - return 0 (no buttons)
    return 0;
}

bool CJoystick::IsButtonPressed(int buttonnum)
{
    // Stub implementation - always return false (no buttons pressed)
    return false;
}

int CJoystick::GetDir()
{
    // Stub implementation - return JOY_DIR_NONE (no direction)
    return JOY_DIR_NONE;
}

int CJoystick::GetHatDir()
{
    // Stub implementation - return JOY_DIR_NONE (no hat direction)
    return JOY_DIR_NONE;
}

Vec3 CJoystick::GetAnalog1Dir(unsigned int joystickID) const
{
    // Stub implementation - return zero vector (no analog input)
    return Vec3(0, 0, 0);
}

Vec3 CJoystick::GetAnalog2Dir(unsigned int joystickID) const
{
    // Stub implementation - return zero vector (no analog input)
    return Vec3(0, 0, 0);
}

#endif // __APPLE__ && __MACH__
