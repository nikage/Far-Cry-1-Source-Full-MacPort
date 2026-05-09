#pragma once

#include "IInput.h"

// Maps XKEY_MOUSE* / wheel / axis codes to 0-based indices into
// CMacOSMouse::m_buttonStates[12] (slots 0-7 buttons, 8-9 wheel, 10-11 axes).
// Returns -1 for keys outside that set.
// Contract mirror of CXMouse::XKEY2IDX — keep in sync if that changes.
static inline int XKeyToMouseIndex(int key)
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
