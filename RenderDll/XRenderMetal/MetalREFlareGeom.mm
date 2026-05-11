////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalREFlareGeom.mm
//  Description: Metal port of CREFlareGeom::mfCheckVis
//
//  The OGL/D3D9 implementations issue a synchronous glReadPixels /
//  IDirect3DDevice9::GetRenderTargetData against the depth buffer, then
//  un-project the pixel depth back through the projection matrix to drive
//  the flare's per-frame fade-in/fade-out timer.
//
//  Metal cannot do a synchronous depth readback without stalling the GPU.
//  A fully accurate port requires an async blit + a one-frame-latency
//  fade. For Phase 2 we emit the flare unconditionally with its base color
//  and full alpha, matching the NULL renderer's behaviour. This restores
//  visible sun coronas without introducing a per-frame GPU stall. A
//  TODO is left for the async depth-readback port in a follow-up commit.
// -------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalBaseRenderer.m"
#include "IStreamEngine.h"
#include "Textures/TexMan.h"
#include "RendElements/CREFlares.h"

void CREFlareGeom::mfCheckVis(CFColor& col, CCObject* obj)
{
    if (!obj)
        return;

    int re = 0;
    SFlareFrame* ff = &mFlareFr[re];

    if (!ff->mbVis)
    {
        ff->mbVis = true;
        ff->mDecayTime = gRenDev ? gRenDev->m_RP.m_RealTime - 0.001f : 0.0f;
    }

    const float realTime = gRenDev ? gRenDev->m_RP.m_RealTime : 0.0f;
    const float fade = (realTime - ff->mDecayTime) * CRenderer::CV_r_coronafade;
    col = ff->mColor;
    col.a = fade > 1.0f ? 1.0f : (fade < 0.0f ? 0.0f : fade);
}

#endif // __APPLE__ && __MACH__
