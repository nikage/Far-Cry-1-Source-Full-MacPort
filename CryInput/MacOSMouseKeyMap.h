#pragma once

#include "IInput.h"

// Maps XKEY_MOUSE* constants (e.g. XKEY_MOUSE1 = 0x00010000) to 0-based
// indices into CMacOSMouse::m_buttonStates[].
// Returns -1 for any key that is not a supported mouse button.
// Contract mirror of CXMouse::XKEY2IDX — keep in sync if that changes.
static inline int XKeyToMouseIndex(int key)
{
    switch (key)
    {
    case XKEY_MOUSE1: return 0;
    case XKEY_MOUSE2: return 1;
    case XKEY_MOUSE3: return 2;
    default:          return -1;
    }
}
