////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalRETempMesh.mm
//  Description: Metal port of CRETempMesh (dynamic vertex stream draws)
//
//  Ported from RenderDll/XRenderOGL/GLRERender.cpp (mfPreDraw / mfDraw)
//  and RenderDll/Common/RendElements/CRETempMesh.cpp (mfPrepare / mfGetPointer).
//  Both are excluded from the macOS build by RenderDll/Common/CMakeLists.txt
//  so the symbols must be provided here.
// -------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalBaseRenderer.m"
#include "MetalRenderer.m"
#include "VertexFormats.h"
#include "RendElements/CRETempMesh.h"
#include "../Common/StubTelemetry.h"

void CRETempMesh::mfPrepare()
{
    gRenDev->EF_CheckOverflow(0, 0, this);

    gRenDev->m_RP.m_pRE = this;
    gRenDev->m_RP.m_RendNumIndices = 6;
    gRenDev->m_RP.m_RendNumVerts = 4;
    gRenDev->m_RP.m_FirstVertex = 0;
    gRenDev->m_RP.m_FirstIndex = 0;
}

void* CRETempMesh::mfGetPointer(ESrcPointer ePT, int* Stride, int Type, ESrcPointer Dst, int Flags)
{
    if (!Stride)
        return nullptr;
    if (!m_VBuffer)
    {
        *Stride = 0;
        return nullptr;
    }

    *Stride = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
    struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F* pVertices =
        (struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F*)m_VBuffer->m_VS[VSF_GENERAL].m_VData;
    gRenDev->m_RP.m_nCurBufferID = m_VBuffer->m_VS[VSF_GENERAL].m_VertBuf.m_nID;
    SBufInfoTable* pOffs = &gBufInfoTable[m_VBuffer->m_vertexformat];

    if (!pVertices)
        return nullptr;

    switch (ePT)
    {
        case eSrcPointer_Vert:
            gRenDev->m_RP.m_nCurBufferOffset = 0;
            return &pVertices->xyz.x;
        case eSrcPointer_Tex:
            gRenDev->m_RP.m_nCurBufferOffset = pOffs->OffsTC;
            return &pVertices->st[0];
        case eSrcPointer_Color:
            gRenDev->m_RP.m_nCurBufferOffset = pOffs->OffsColor;
            return &pVertices->color.dcolor;
        default:
            break;
    }
    return nullptr;
}

bool CRETempMesh::mfPreDraw(SShaderPass* sl)
{
    return true;
}

void CRETempMesh::mfReset()
{
}

bool CRETempMesh::mfDraw(SShader* ef, SShaderPass* sl)
{
    CMetalBaseRenderer* r = checked_cast<CMetalBaseRenderer>(gRenDev);
    if (!r || !r->m_renderEncoder)
    {
        METAL_STUB_TRACE_BARE("CRETempMesh::mfDraw::no-encoder");
        return false;
    }

    CVertexBuffer* vb = m_VBuffer;
    if (!vb)
    {
        METAL_STUB_TRACE_BARE("CRETempMesh::mfDraw::null-vbuffer");
        return false;
    }

    const int numIndices = gRenDev->m_RP.m_RendNumIndices;
    const int firstIndex = gRenDev->m_RP.m_FirstIndex;
    const int firstVert  = gRenDev->m_RP.m_FirstVertex;
    const int numVerts   = gRenDev->m_RP.m_RendNumVerts;

    r->DrawBuffer(vb,
                  &m_Inds,
                  numIndices,
                  firstIndex,
                  R_PRIMV_TRIANGLES,
                  firstVert,
                  firstVert + numVerts,
                  nullptr);

    gRenDev->m_RP.m_RendNumIndices = 0;
    return true;
}

#endif // __APPLE__ && __MACH__
