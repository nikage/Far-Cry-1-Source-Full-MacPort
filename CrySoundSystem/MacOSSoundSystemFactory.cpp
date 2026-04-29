////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSSoundSystemFactory.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS sound system factory implementation
//               Creates macOS-specific sound system instead of Windows CrySound
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

// Forward declarations to avoid header conflicts
class ISystem;
class ISoundSystem;

// Simple factory function that returns nullptr for now
// This allows the build to complete while we work on the full implementation
extern "C" ISoundSystem* CreateMacOSSoundSystem(ISystem* pSystem)
{
    if (!pSystem)
        return nullptr;
    
    // For now, return nullptr to allow compilation
    // TODO: Implement full macOS sound system
    return nullptr;
}

// Alternative factory function for compatibility
extern "C" ISoundSystem* CreateSoundSystem(ISystem* pSystem)
{
    return CreateMacOSSoundSystem(pSystem);
}