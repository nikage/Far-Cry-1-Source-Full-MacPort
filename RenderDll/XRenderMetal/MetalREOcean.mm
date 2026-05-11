/*=============================================================================
  MetalREOcean.mm : Metal-specific ocean render element.
=============================================================================*/

#include "MetalRenderPCH.h"
#include "RenderPCH.h"
#include "../Common/RendElements/CREOcean.h"
#include "MetalBaseRenderer.m"
#include "MetalDrawDiag.h"
#include <I3DEngine.h>
#include <vector>

// Silhouette vertex traversal table shared by CCamera::IsAABBVisible_hierarchical.
// One copy lives here for the Metal renderer; the OGL/D3D9 renderers have their own.
char BoxSides[0x40*8] = {
	0,0,0,0, 0,0,0,0, //00
		0,4,6,2, 0,0,0,4, //01
		7,5,1,3, 0,0,0,4, //02
		0,0,0,0, 0,0,0,0, //03
		0,1,5,4, 0,0,0,4, //04
		0,1,5,4, 6,2,0,6, //05
		7,5,4,0, 1,3,0,6, //06
		0,0,0,0, 0,0,0,0, //07
		7,3,2,6, 0,0,0,4, //08
		0,4,6,7, 3,2,0,6, //09
		7,5,1,3, 2,6,0,6, //0a
		0,0,0,0, 0,0,0,0, //0b
		0,0,0,0, 0,0,0,0, //0c
		0,0,0,0, 0,0,0,0, //0d
		0,0,0,0, 0,0,0,0, //0e
		0,0,0,0, 0,0,0,0, //0f
		0,2,3,1, 0,0,0,4, //10
		0,4,6,2, 3,1,0,6, //11
		7,5,1,0, 2,3,0,6, //12
		0,0,0,0, 0,0,0,0, //13
		0,2,3,1, 5,4,0,6, //14
		1,5,4,6, 2,3,0,6, //15
		7,5,4,0, 2,3,0,6, //16
		0,0,0,0, 0,0,0,0, //17
		0,2,6,7, 3,1,0,6, //18
		0,4,6,7, 3,1,0,6, //19
		7,5,1,0, 2,6,0,6, //1a
		0,0,0,0, 0,0,0,0, //1b
		0,0,0,0, 0,0,0,0, //1c
		0,0,0,0, 0,0,0,0, //1d
		0,0,0,0, 0,0,0,0, //1e
		0,0,0,0, 0,0,0,0, //1f
		7,6,4,5, 0,0,0,4, //20
		0,4,5,7, 6,2,0,6, //21
		7,6,4,5, 1,3,0,6, //22
		0,0,0,0, 0,0,0,0, //23
		7,6,4,0, 1,5,0,6, //24
		0,1,5,7, 6,2,0,6, //25
		7,6,4,0, 1,3,0,6, //26
		0,0,0,0, 0,0,0,0, //27
		7,3,2,6, 4,5,0,6, //28
		0,4,5,7, 3,2,0,6, //29
		6,4,5,1, 3,2,0,6, //2a
		0,0,0,0, 0,0,0,0, //2b
		0,0,0,0, 0,0,0,0, //2c
		0,0,0,0, 0,0,0,0, //2d
		0,0,0,0, 0,0,0,0, //2e
		0,0,0,0, 0,0,0,0, //2f
		0,0,0,0, 0,0,0,0, //30
		0,0,0,0, 0,0,0,0, //31
		0,0,0,0, 0,0,0,0, //32
		0,0,0,0, 0,0,0,0, //33
		0,0,0,0, 0,0,0,0, //34
		0,0,0,0, 0,0,0,0, //35
		0,0,0,0, 0,0,0,0, //36
		0,0,0,0, 0,0,0,0, //37
		0,0,0,0, 0,0,0,0, //38
		0,0,0,0, 0,0,0,0, //39
		0,0,0,0, 0,0,0,0, //3a
		0,0,0,0, 0,0,0,0, //3b
		0,0,0,0, 0,0,0,0, //3c
		0,0,0,0, 0,0,0,0, //3d
		0,0,0,0, 0,0,0,0, //3e
		0,0,0,0, 0,0,0,0, //3f
};

static _inline int Compare(SOceanSector*& p1, SOceanSector*& p2)
{
    if (p1->m_Flags > p2->m_Flags) return 1;
    if (p1->m_Flags < p2->m_Flags) return -1;
    return 0;
}

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
    if (!oi || !oi->m_pIndicies || oi->m_nInds == 0)
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
        [r->m_device newBufferWithBytes:oi->m_pIndicies
                                 length:(NSUInteger)oi->m_nInds * sizeof(ushort)
                                options:MTLResourceStorageModeShared];

    [enc setVertexBuffer:posBuf offset:0 atIndex:0];
    MetalDrawDiag::OnDrawCall("REOcean::ScreenLodSetup", enc, nil,
                              MTLPrimitiveTypeTriangle, 0, (NSUInteger)oi->m_nInds);
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
        if (!oi || !oi->m_pIndicies || oi->m_nInds == 0)
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
            [r->m_device newBufferWithBytes:oi->m_pIndicies
                                     length:(NSUInteger)oi->m_nInds * sizeof(ushort)
                                    options:MTLResourceStorageModeShared];

        MetalDrawDiag::OnDrawCall("REOcean::Sector", enc, nil,
                                  MTLPrimitiveTypeTriangle, 0, (NSUInteger)oi->m_nInds);
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
    if (!oi || !oi->m_pIndicies || oi->m_nInds == 0)
        return;

    id<MTLBuffer> idxBuf =
        [r->m_device newBufferWithBytes:oi->m_pIndicies
                                 length:(NSUInteger)oi->m_nInds * sizeof(ushort)
                                options:MTLResourceStorageModeShared];

    MetalDrawDiag::OnDrawCall("REOcean::ScreenLodFinal", enc, nil,
                              MTLPrimitiveTypeTriangle, 0, (NSUInteger)oi->m_nInds);
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

#pragma mark - Static members (previously in CREOcean.cpp, excluded from Apple build)

SREOceanStats CREOcean::m_RS;
CREOcean*     CREOcean::m_pStaticOcean = nullptr;

DEFINE_ALIGNED_DATA(float, CREOcean::m_HX[OCEANGRID][OCEANGRID], 16);
DEFINE_ALIGNED_DATA(float, CREOcean::m_HY[OCEANGRID][OCEANGRID], 16);
DEFINE_ALIGNED_DATA(float, CREOcean::m_NX[OCEANGRID][OCEANGRID], 16);
DEFINE_ALIGNED_DATA(float, CREOcean::m_NY[OCEANGRID][OCEANGRID], 16);
DEFINE_ALIGNED_DATA(float, CREOcean::m_DX[OCEANGRID][OCEANGRID], 16);
DEFINE_ALIGNED_DATA(float, CREOcean::m_DY[OCEANGRID][OCEANGRID], 16);

#pragma mark - Missing methods — ported from CREOcean.cpp / stubs for Metal

CREOcean::~CREOcean()
{
    m_pStaticOcean = nullptr;
    mfReset();
    for (int i = 0; i < (1 << (LOD_BOTTOMSHIFT + 1)); ++i)
    {
        if (m_OceanIndicies[i])
        {
            delete[] m_OceanIndicies[i]->m_pIndicies;
            delete m_OceanIndicies[i];
            m_OceanIndicies[i] = nullptr;
        }
    }
    for (int i = 0; i < NUM_LODS; ++i)
        m_pIndices[i].Free();
    if (m_pBuffer)
    {
        gRenDev->ReleaseBuffer(m_pBuffer);
        m_pBuffer = nullptr;
    }
    SAFE_DELETE_ARRAY(m_HMap);
}

void CREOcean::GenerateGeometry()
{
    const int gridSize = OCEANGRID + 1;
    for (int y = 0; y < gridSize; ++y)
    {
        for (int x = 0; x < gridSize; ++x)
        {
            m_Pos[x][y][0] = (float)x / OCEANGRID;
            m_Pos[x][y][1] = (float)y / OCEANGRID;
            m_Normals[x][y] = Vec3d(0.f, 0.f, 1.f);
        }
    }
    m_MinBound = Vec3d(-0.5f, -0.5f, -1.f);
    m_MaxBound = Vec3d( 0.5f,  0.5f,  1.f);
    memset(m_OceanIndicies, 0, sizeof(m_OceanIndicies));
    m_fSectorSize = 0.f;
}

void CREOcean::GenerateIndices(int nLodCode)
{
    if (m_OceanIndicies[nLodCode])
        return;

    SOceanIndicies* oi = new SOceanIndicies();
    oi->m_fLastAccess = 0.f;

    const int step = 1 << (nLodCode & LOD_MASK);
    const int dim  = OCEANGRID / step;

    std::vector<ushort> inds;
    inds.reserve((size_t)dim * dim * 6);

    for (int y = 0; y < dim; ++y)
    {
        for (int x = 0; x < dim; ++x)
        {
            int x0 = x * step;
            int y0 = y * step;
            int x1 = x0 + step;
            int y1 = y0 + step;

            auto idx = [](int px, int py) -> ushort
            {
                return (ushort)(py * (OCEANGRID + 1) + px);
            };

            inds.push_back(idx(x0, y0));
            inds.push_back(idx(x1, y0));
            inds.push_back(idx(x1, y1));
            inds.push_back(idx(x0, y0));
            inds.push_back(idx(x1, y1));
            inds.push_back(idx(x0, y1));
        }
    }

    oi->m_nInds    = (int)inds.size();
    oi->m_pIndicies = new ushort[oi->m_nInds];
    memcpy(oi->m_pIndicies, inds.data(), (size_t)oi->m_nInds * sizeof(ushort));

    m_OceanIndicies[nLodCode] = oi;
}

void CREOcean::SmoothLods_r(SOceanSector* os, float fSize, int minLod)
{
    if (!os || os->nLod <= minLod)
        return;
    os->nLod = minLod;
}

void CREOcean::LinkVisSectors(float fSize)
{
    for (int i = 0; i < m_VisOceanSectors.Num(); ++i)
    {
        SOceanSector* os = m_VisOceanSectors[i];
        if (!os) continue;
        SOceanSector* left  = GetSectorByPos(os->x - fSize, os->y, false);
        SOceanSector* right = GetSectorByPos(os->x + fSize, os->y, false);
        SOceanSector* top   = GetSectorByPos(os->x, os->y + fSize, false);
        SOceanSector* bot   = GetSectorByPos(os->x, os->y - fSize, false);
        int minLod = os->nLod - 1;
        if (minLod < 0) minLod = 0;
        if (left)  SmoothLods_r(left,  fSize, minLod);
        if (right) SmoothLods_r(right, fSize, minLod);
        if (top)   SmoothLods_r(top,   fSize, minLod);
        if (bot)   SmoothLods_r(bot,   fSize, minLod);
    }
}

float CREOcean::GetWaterZElevation(float fX, float fY)
{
    if (!m_HMap)
        return 0.f;
    I3DEngine* eng = (I3DEngine*)iSystem->GetI3DEngine();
    float fWaterLevel = eng ? eng->GetWaterLevel() : 0.f;
    float fZH = GetHMap(fX, fY);
    return (fZH >= fWaterLevel) ? fWaterLevel : fZH;
}

void CREOcean::PostLoad(unsigned long ulSeed, float fWindDirection, float fWindSpeed,
                        float fWaveHeight, float fDirectionalDependence,
                        float fChoppyWavesFactor, float fSuppressSmallWavesFactor)
{
    m_fWindX                  = cry_cosf(fWindDirection);
    m_fWindY                  = cry_sinf(fWindDirection);
    m_fWindSpeed              = fWindSpeed;
    m_fWaveHeight             = fWaveHeight;
    m_fDirectionalDependence  = fDirectionalDependence;
    m_fChoppyWaveFactor       = fChoppyWavesFactor;
    m_fSuppressSmallWavesFactor = fSuppressSmallWavesFactor;
    m_fLargestPossibleWave    = fWindSpeed * fWindSpeed / 9.81f;
    m_fSuppressSmallWaves     = fSuppressSmallWavesFactor * 0.001f;
}

void CREOcean::Update(float fTime)
{
}

void CREOcean::PrepareHMap()
{
}

float* CREOcean::mfFillAdditionalBuffer(SOceanSector* os, int nSplashes, SSplash* pSplashes[],
                                         int& nCurSize, int nLod, float fSize)
{
    assert(m_nCurVB >= 0 && m_nCurVB < NUM_OCEANVBS);
    if (!m_pVertsPool[m_nCurVB])
        return nullptr;
    id<MTLBuffer> buf = (__bridge id<MTLBuffer>)m_pVertsPool[m_nCurVB];
    return (float*)buf.contents;
}

void CREOcean::mfPrepare()
{
}

bool CREOcean::mfCompile(SShader* ef, char* scr)
{
    return true;
}

void* CREOcean::mfGetPointer(ESrcPointer ePT, int* Stride, int Type, ESrcPointer Dst, int Flags)
{
    return nullptr;
}

int CREOcean::GetLOD(Vec3d camera, Vec3d pos)
{
    float dist = (camera - pos).len();
    if (dist < 64.f)  return 0;
    if (dist < 128.f) return 1;
    if (dist < 256.f) return 2;
    if (dist < 512.f) return 3;
    return NUM_LODS - 1;
}
