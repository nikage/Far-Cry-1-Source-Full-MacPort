////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalREClearStencil.mm
//  Description: Metal port of CREClearStencil::mfDraw
//
//  Metal cannot clear stencil in the middle of a render pass. We end the
//  current encoder, begin a new render pass with stencilLoadAction =
//  MTLLoadActionClear (preserving color/depth via Load), and continue.
//  Matches the semantics of glClearStencil(0); glClear(GL_STENCIL_BUFFER_BIT)
//  in the OGL backend.
// -------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalBaseRenderer.m"

bool CREClearStencil::mfDraw(SShader* ef, SShaderPass* sfm)
{
    CMetalBaseRenderer* r = checked_cast<CMetalBaseRenderer>(gRenDev);
    if (!r)
        return false;

    r->ClearStencilBuffer();
    return true;
}

#endif // __APPLE__ && __MACH__
