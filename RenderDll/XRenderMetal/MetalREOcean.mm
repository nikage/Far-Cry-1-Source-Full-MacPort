/*=============================================================================
  MetalREOcean.mm : Metal-specific ocean render element.
=============================================================================*/

#include "RenderPCH.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#include "../Common/RendElements/CREOcean.h"
#include "MetalRenderPCH.h"
#include "MetalBaseRenderer.m"

static CMetalBaseRenderer* MetalRend()
{
    return checked_cast<CMetalBaseRenderer>(gRenDev);
}

#pragma mark - InitVB / GetVBPtr / UnlockVBPtr

void CREOcean::InitVB()
{
    CMetalBaseRenderer* r = MetalRend();
    assert(r && r->m_device);

    m_nNumVertsInPool = (OCEANGRID + 1) * (OCEANGRID + 1);
    NSUInteger bufSize = (NSUInteger)m_nNumVertsInPool * sizeof(struct_VERTEX_FORMAT_TEX2F);

    for (int i = 0; i < NUM_OCEANVBS; ++i)
    {
        if (m_pVertsPool[i])
        {
            CFBridgingRelease(m_pVertsPool[i]);
            m_pVertsPool[i] = nullptr;
        }
        id<MTLBuffer> buf = [r->m_device newBufferWithLength:bufSize
                                                     options:MTLResourceStorageModeShared];
        if (!buf)
        {
            iLog->Log("CREOcean::InitVB: failed to create pool buffer %d\n", i);
            continue;
        }
        [buf setLabel:[NSString stringWithFormat:@"OceanVBPool[%d]", i]];
        m_pVertsPool[i] = (void*)CFBridgingRetain(buf);
    }
    m_nCurVB = 0;
    m_bLockedVB = false;
}

struct_VERTEX_FORMAT_TEX2F* CREOcean::GetVBPtr(int nVerts)
{
    if (nVerts > m_nNumVertsInPool)
    {
        assert(false && "CREOcean::GetVBPtr: requested more verts than pool size");
        return nullptr;
    }
    if (m_bLockedVB)
        UnlockVBPtr();

    m_nCurVB = (m_nCurVB + 1) % NUM_OCEANVBS;
    if (!m_pVertsPool[m_nCurVB])
        return nullptr;

    id<MTLBuffer> buf = (__bridge id<MTLBuffer>)m_pVertsPool[m_nCurVB];
    m_bLockedVB = true;
    return (struct_VERTEX_FORMAT_TEX2F*)buf.contents;
}

void CREOcean::UnlockVBPtr()
{
    m_bLockedVB = false;
}

#pragma mark - DrawOceanSector

void CREOcean::DrawOceanSector(SOceanIndicies* oi)
{
    if (!oi || !oi->m_Inds || oi->m_nInds == 0)
        return;

    CMetalBaseRenderer* r = MetalRend();
    id<MTLRenderCommandEncoder> enc = r->m_renderEncoder;
    if (!enc || !m_pBuffer) return;

    const int nVerts = (OCEANGRID + 1) * (OCEANGRID + 1);
    struct_VERTEX_FORMAT_P3F_N* pPos =
        (struct_VERTEX_FORMAT_P3F_N*)m_pBuffer->m_VS[VSF_GENERAL].m_VData;
    if (!pPos) return;

    id<MTLBuffer> posBuf =
        [r->m_device newBufferWithBytes:pPos
                                 length:(NSUInteger)nVerts * sizeof(struct_VERTEX_FORMAT_P3F_N)
                                options:MTLResourceStorageModeShared];
    id<MTLBuffer> idxBuf =
        [r->m_device newBufferWithBytes:oi->m_Inds
                                 length:(NSUInteger)oi->m_nInds * sizeof(ushort)
                                options:MTLResourceStorageModeShared];

    [enc setVertexBuffer:posBuf offset:0 atIndex:0];
    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                    indexCount:(NSUInteger)oi->m_nInds
                     indexType:MTLIndexTypeUInt16
                   indexBuffer:idxBuf
             indexBufferOffset:0];
}

#pragma mark - mfDrawOceanSectors

void CREOcean::mfDrawOceanSectors()
{
    CMetalBaseRenderer* r = MetalRend();
    id<MTLRenderCommandEncoder> enc = r->m_renderEncoder;
    if (!enc) return;

    m_RS.m_StatsNumRendOceanSectors = 0;

    I3DEngine* eng = (I3DEngine*)iSystem->GetI3DEngine();
    const float fMaxDistRaw = eng->GetMaxViewDistance();
    CCamera cam = gRenDev->GetCamera();
    const Vec3d cameraPos = cam.GetPos();
    const float fSize = (float)CRenderer::CV_r_oceansectorsize;
    const float fHeightScale = (float)CRenderer::CV_r_oceanheightscale;
    const float fWaterLevel = eng->GetWaterLevel();
    const int nMaxSplashes = CLAMP(CRenderer::CV_r_oceanmaxsplashes, 0, 16);

    float fCurX = (float)((int)cameraPos[0] & ~255) + 128.0f;
    float fCurY = (float)((int)cameraPos[1] & ~255) + 128.0f;
    float fMaxDist = (float)((int)(fMaxDistRaw / fSize + 1.0f)) * fSize;

    if (fSize != m_fSectorSize)
    {
        m_fSectorSize = fSize;
        for (int i = 0; i < 256; ++i)
            m_OceanSectorsHash[i].Free();
    }

    m_VisOceanSectors.SetUse(0);

    for (float y = fCurY - fMaxDist; y < fCurY + fMaxDist; y += fSize)
    {
        for (float x = fCurX - fMaxDist; x < fCurX + fMaxDist; x += fSize)
        {
            SOceanSector* os = GetSectorByPos(x, y);
            if (!(os->m_Flags & (OSF_FIRSTTIME | OSF_VISIBLE)))
                continue;

            Vec3d mins(x + m_MinBound.x * fSize,
                       y + m_MinBound.y * fSize,
                       fWaterLevel + m_MinBound.z * fHeightScale);
            Vec3d maxs(x + fSize + m_MaxBound.x * fSize,
                       y + fSize + m_MaxBound.y * fSize,
                       fWaterLevel + m_MaxBound.z * fHeightScale);

            if (cam.IsAABBVisible_hierarchical(AABB(mins, maxs)) != CULL_EXCLUSION)
            {
                Vec3d vCenter = (mins + maxs) * 0.5f;
                os->nLod = GetLOD(cameraPos, vCenter);
                os->m_Frame = gRenDev->m_cEF.m_Frame;
                os->m_Flags &= ~OSF_LODUPDATED;
                m_VisOceanSectors.AddElem(os);
            }
        }
    }

    if (m_VisOceanSectors.Num())
    {
        LinkVisSectors(fSize);
        ::Sort(&m_VisOceanSectors[0], m_VisOceanSectors.Num());
    }

    if (!m_pBuffer) return;
    const int nVerts = (OCEANGRID + 1) * (OCEANGRID + 1);
    struct_VERTEX_FORMAT_P3F_N* pPos =
        (struct_VERTEX_FORMAT_P3F_N*)m_pBuffer->m_VS[VSF_GENERAL].m_VData;
    if (!pPos) return;

    id<MTLBuffer> posBuf =
        [r->m_device newBufferWithBytes:pPos
                                 length:(NSUInteger)nVerts * sizeof(struct_VERTEX_FORMAT_P3F_N)
                                options:MTLResourceStorageModeShared];
    [posBuf setLabel:@"OceanPositions"];
    [enc setVertexBuffer:posBuf offset:0 atIndex:0];

    for (int i = 0; i < m_VisOceanSectors.Num(); ++i)
    {
        SOceanSector* os = m_VisOceanSectors[i];
        bool bL = (os->nLod < GetSectorByPos(os->x - fSize, os->y)->nLod);
        bool bR = (os->nLod < GetSectorByPos(os->x + fSize, os->y)->nLod);
        bool bT = (os->nLod < GetSectorByPos(os->x, os->y + fSize)->nLod);
        bool bB = (os->nLod < GetSectorByPos(os->x, os->y - fSize)->nLod);
        int nLodCode = os->nLod
                     + (bL << LOD_LEFTSHIFT)
                     + (bR << LOD_RIGHTSHIFT)
                     + (bT << LOD_TOPSHIFT)
                     + (bB << LOD_BOTTOMSHIFT);

        if (!m_OceanIndicies[nLodCode])
            GenerateIndices(nLodCode);

        SOceanIndicies* oi = m_OceanIndicies[nLodCode];
        if (!oi || !oi->m_Inds || oi->m_nInds == 0)
            continue;

        int nDummy = 0;
        int nSplashes = 0;
        SSplash* pSplashes[16] = {};
        for (int s = 0; s < gRenDev->m_RP.m_Splashes.Num() && nSplashes < nMaxSplashes; ++s)
        {
            SSplash* spl = &gRenDev->m_RP.m_Splashes[s];
            float cr = spl->m_fCurRadius;
            if (spl->m_Pos[0] - cr > os->x + fSize ||
                spl->m_Pos[1] - cr > os->y + fSize ||
                spl->m_Pos[0] + cr < os->x ||
                spl->m_Pos[1] + cr < os->y)
                continue;
            pSplashes[nSplashes++] = spl;
        }

        mfFillAdditionalBuffer(os, nSplashes, pSplashes, nDummy, os->nLod, fSize);

        if (m_pVertsPool[m_nCurVB])
        {
            id<MTLBuffer> addBuf = (__bridge id<MTLBuffer>)m_pVertsPool[m_nCurVB];
            [enc setVertexBuffer:addBuf offset:0 atIndex:1];
        }

        id<MTLBuffer> idxBuf =
            [r->m_device newBufferWithBytes:oi->m_Inds
                                     length:(NSUInteger)oi->m_nInds * sizeof(ushort)
                                    options:MTLResourceStorageModeShared];

        [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                        indexCount:(NSUInteger)oi->m_nInds
                         indexType:MTLIndexTypeUInt16
                       indexBuffer:idxBuf
                 indexBufferOffset:0];

        m_RS.m_StatsNumRendOceanSectors++;
    }
}

#pragma mark - mfDrawOceanScreenLod

void CREOcean::mfDrawOceanScreenLod()
{
    CMetalBaseRenderer* r = MetalRend();
    id<MTLRenderCommandEncoder> enc = r->m_renderEncoder;
    if (!enc || !m_pBuffer) return;

    const int nVerts = (OCEANGRID + 1) * (OCEANGRID + 1);
    struct_VERTEX_FORMAT_P3F_N* pPos =
        (struct_VERTEX_FORMAT_P3F_N*)m_pBuffer->m_VS[VSF_GENERAL].m_VData;
    if (!pPos) return;

    id<MTLBuffer> posBuf =
        [r->m_device newBufferWithBytes:pPos
                                 length:(NSUInteger)nVerts * sizeof(struct_VERTEX_FORMAT_P3F_N)
                                options:MTLResourceStorageModeShared];
    [enc setVertexBuffer:posBuf offset:0 atIndex:0];

    if (!m_OceanIndicies[0])
        GenerateIndices(0);

    SOceanIndicies* oi = m_OceanIndicies[0];
    if (!oi || !oi->m_Inds || oi->m_nInds == 0)
        return;

    id<MTLBuffer> idxBuf =
        [r->m_device newBufferWithBytes:oi->m_Inds
                                 length:(NSUInteger)oi->m_nInds * sizeof(ushort)
                                options:MTLResourceStorageModeShared];

    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                    indexCount:(NSUInteger)oi->m_nInds
                     indexType:MTLIndexTypeUInt16
                   indexBuffer:idxBuf
             indexBufferOffset:0];
}

#pragma mark - mfDraw / mfPreDraw / mfReset / UpdateTexture

bool CREOcean::mfDraw(SShader* ef, SShaderPass* sfm)
{
    double time0 = 0;
    ticks(time0);

    if (!m_pVertsPool[0])
        InitVB();

    if (!m_pBuffer)
        m_pBuffer = gRenDev->CreateBuffer(
            (OCEANGRID + 1) * (OCEANGRID + 1),
            VERTEX_FORMAT_P3F_N,
            "Ocean",
            /*bDynamic=*/true);

    if (CRenderer::CV_r_oceanrendtype == 0)
        mfDrawOceanSectors();
    else
        mfDrawOceanScreenLod();

    unticks(time0);
    m_RS.m_StatsTimeRendOcean = (float)(time0 * 1000.0 * g_SecondsPerCycle);

    return true;
}

bool CREOcean::mfPreDraw(SShaderPass* sl)
{
    return true;
}

void CREOcean::mfReset()
{
    for (int i = 0; i < NUM_OCEANVBS; ++i)
    {
        if (m_pVertsPool[i])
        {
            CFBridgingRelease(m_pVertsPool[i]);
            m_pVertsPool[i] = nullptr;
        }
    }
    m_bLockedVB = false;
}

void CREOcean::UpdateTexture()
{
}
