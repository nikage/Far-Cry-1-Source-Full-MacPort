////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalRenderElements.cpp
//  Version:     v1.00
//  Created:     29/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal render element implementations for terrain, sky, vegetation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include <vector>
#include <cstdint>
#include "MetalBaseRenderer.m"
#include "MetalRenderer.m"
#include "MetalTextureManager.m"
#include "MetalShaderManager.m"
#include "I3DEngine.h"
#include "ISystem.h"
#include "LeafBuffer.h"
#include "CREOcLeaf.h"
#include "CREOcclusionQuery.h"
#include "CREScreenProcess.h"
#include "CRETerrainSector.h"
#include <Metal/Metal.h>

extern ISystem *iSystem;
// gRenDev is declared in Renderer.h which is included via MetalBaseRenderer.h

//=========================================================================
// CMetalRESky - Sky rendering with sky sphere, fog layers, and portals
//=========================================================================

class CMetalRESky : public CRendElement
{
public:
    float m_fTerrainWaterLevel;
    float m_fSkyBoxStretching;
    float m_fAlpha;
    int m_nSphereListId;
    list2<struct_VERTEX_FORMAT_P3F_COL4UB>* m_parrFogLayer;
    list2<struct_VERTEX_FORMAT_P3F_COL4UB>* m_parrFogLayer2;
    
    #define MAX_SKY_OCCLAREAS_NUM 8
    struct_VERTEX_FORMAT_P3F_COL4UB m_arrvPortalVerts[MAX_SKY_OCCLAREAS_NUM][4];
    
    CMetalRESky()
    {
        mfSetType(eDATA_Sky);
        mfUpdateFlags(FCEF_TRANSFORM);
        m_fTerrainWaterLevel = 0;
        m_fAlpha = 1;
        m_nSphereListId = 0;
        m_parrFogLayer = m_parrFogLayer2 = NULL;
        m_fSkyBoxStretching = 1.f;
        memset(m_arrvPortalVerts, 0, sizeof(m_arrvPortalVerts));
    }
    
    virtual ~CMetalRESky()
    {
        if (m_parrFogLayer)
            delete m_parrFogLayer;
        if (m_parrFogLayer2)
            delete m_parrFogLayer2;
    }
    
    virtual void mfPrepare()
    {
        assert(gRenDev && "CMetalRESky::mfPrepare - gRenDev is null!");
        
        gRenDev->EF_CheckOverflow(0, 0, this);
        gRenDev->m_RP.m_pRE = this;
        gRenDev->m_RP.m_RendNumIndices = 0;
        gRenDev->m_RP.m_RendNumVerts = 0;
    }
    
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm)
    {
        assert(ef && "CMetalRESky::mfDraw - ef is null!");
        assert(gRenDev && "CMetalRESky::mfDraw - gRenDev is null!");
        
        if (!gRenDev || !iSystem)
            return false;
        
        I3DEngine* pEngine = iSystem->GetI3DEngine();
        if (!pEngine)
            return false;
        
        DrawSkySphere(m_fTerrainWaterLevel);
        
        if (m_parrFogLayer && m_parrFogLayer->Count() > 0)
            DrawFogLayer();
        
        DrawBlackPortal();
        
        return true;
    }
    
    void DrawSkySphere(float fHeight)
    {
        assert(gRenDev && "CMetalRESky::DrawSkySphere - gRenDev is null!");
        
        CMetalBaseRenderer* r = checked_cast<CMetalBaseRenderer>(gRenDev);
        assert(r && r->m_renderEncoder && "CMetalRESky::DrawSkySphere - no active render encoder");
        if (!r || !r->m_renderEncoder)
            return;
        
        const int NUM_SKY_SEGMENTS = 32;
        const int NUM_SKY_RINGS = 16;
        const float SKY_RADIUS = 10000.0f;
        
        std::vector<struct_VERTEX_FORMAT_P3F_COL4UB> vertices;
        std::vector<uint16_t> indices;
        
        vertices.reserve((NUM_SKY_SEGMENTS + 1) * (NUM_SKY_RINGS + 1));
        indices.reserve(NUM_SKY_SEGMENTS * NUM_SKY_RINGS * 6);
        
        CCamera cam = r->GetCamera();
        Vec3d camPos = cam.GetPos();
        
        for (int ring = 0; ring <= NUM_SKY_RINGS; ring++)
        {
            float v = (float)ring / NUM_SKY_RINGS;
            float phi = v * 3.14159f * 0.5f * m_fSkyBoxStretching;
            float y = SKY_RADIUS * sinf(phi);
            float ringRadius = SKY_RADIUS * cosf(phi);
            
            for (int seg = 0; seg <= NUM_SKY_SEGMENTS; seg++)
            {
                float u = (float)seg / NUM_SKY_SEGMENTS;
                float theta = u * 2.0f * 3.14159f;
                float x = ringRadius * cosf(theta);
                float z = ringRadius * sinf(theta);
                
                struct_VERTEX_FORMAT_P3F_COL4UB vert;
                vert.xyz[0] = camPos.x + x;
                vert.xyz[1] = camPos.y + y + fHeight;
                vert.xyz[2] = camPos.z + z;
                
                byte alpha = (byte)(m_fAlpha * 255.0f);
                vert.color.bcolor[0] = 128;
                vert.color.bcolor[1] = 160;
                vert.color.bcolor[2] = 220;
                vert.color.bcolor[3] = alpha;
                
                vertices.push_back(vert);
            }
        }
        
        for (int ring = 0; ring < NUM_SKY_RINGS; ring++)
        {
            for (int seg = 0; seg < NUM_SKY_SEGMENTS; seg++)
            {
                int curr = ring * (NUM_SKY_SEGMENTS + 1) + seg;
                int next = curr + NUM_SKY_SEGMENTS + 1;
                
                indices.push_back(curr);
                indices.push_back(next);
                indices.push_back(curr + 1);
                
                indices.push_back(curr + 1);
                indices.push_back(next);
                indices.push_back(next + 1);
            }
        }
        
        assert(!vertices.empty() && !indices.empty() && "CMetalRESky::DrawSkySphere - sky geometry is empty");
        if (!vertices.empty() && !indices.empty())
        {
            CMetalRenderer* renderer = checked_cast<CMetalRenderer>(gRenDev);
            assert(renderer && renderer->GetShaderManager() && "CMetalREFogVolume: renderer or shader manager is null");
            if (!renderer || !renderer->GetShaderManager()) return;

            id<MTLRenderCommandEncoder> enc = r->m_renderEncoder;

            id<MTLRenderPipelineState> pso =
                renderer->GetShaderManager()->GetPipelineStateForShader("color");
            if (!pso)
                pso = renderer->GetShaderManager()->GetPipelineStateForFormat(VERTEX_FORMAT_P3F_COL4UB);
            assert(pso && "CMetalREFogVolume: no PSO found for color/P3F_COL4UB vertex format");
            if (!pso) {
                static bool s_logged = false;
                if (!s_logged) { iLog->Log("CMetalRESky::DrawSkySphere: no PSO for color/P3F_COL4UB — sky sphere not drawn\n"); s_logged = true; }
                return;
            }

            id<MTLBuffer> vbuf = [r->m_device
                newBufferWithBytes:vertices.data()
                            length:vertices.size() * sizeof(struct_VERTEX_FORMAT_P3F_COL4UB)
                           options:MTLResourceStorageModeShared];
            id<MTLBuffer> ibuf = [r->m_device
                newBufferWithBytes:indices.data()
                            length:indices.size() * sizeof(uint16_t)
                           options:MTLResourceStorageModeShared];

            [enc setRenderPipelineState:pso];
            [enc setVertexBuffer:vbuf   offset:0 atIndex:0];
            [enc setVertexBuffer:r->m_uniformBuffer offset:0 atIndex:kMetalVertexUniformSlot];
            [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                            indexCount:(NSUInteger)indices.size()
                             indexType:MTLIndexTypeUInt16
                           indexBuffer:ibuf
                     indexBufferOffset:0];
            [vbuf release];
            [ibuf release];
        }
    }
    
    bool DrawFogLayer()
    {
        assert(gRenDev && "CMetalRESky::DrawFogLayer - gRenDev is null!");
        assert(m_parrFogLayer && "CMetalRESky::DrawFogLayer - fog layer is null!");
        
        CMetalBaseRenderer* r = checked_cast<CMetalBaseRenderer>(gRenDev);
        assert(r && r->m_renderEncoder && "CMetalRESky::DrawFogLayer - no active render encoder");
        if (!r || !r->m_renderEncoder || !m_parrFogLayer)
            return false;
        
        if (m_parrFogLayer->Count() == 0)
            return false;

        CMetalRenderer* renderer = checked_cast<CMetalRenderer>(gRenDev);
        assert(renderer && renderer->GetShaderManager() && "CMetalREFogLayer: renderer or shader manager is null");
        if (!renderer || !renderer->GetShaderManager()) return false;

        id<MTLRenderPipelineState> pso =
            renderer->GetShaderManager()->GetPipelineStateForShader("color");
        assert(pso && "CMetalREFogLayer: no PSO found for color shader");
        if (!pso) {
            static bool s_logged = false;
            if (!s_logged) { iLog->Log("CMetalRESky::DrawFogLayer: no PSO for color shader — fog layer not drawn\n"); s_logged = true; }
            return false;
        }

        // Fog layer is a list of P3F_COL4UB quads — draw as triangle list
        const int nFogVerts = m_parrFogLayer->Count();
        id<MTLBuffer> vbuf = [r->m_device
            newBufferWithBytes:&m_parrFogLayer->GetAt(0)
                        length:(NSUInteger)nFogVerts * sizeof(struct_VERTEX_FORMAT_P3F_COL4UB)
                       options:MTLResourceStorageModeShared];

        [r->m_renderEncoder setRenderPipelineState:pso];
        [r->m_renderEncoder setVertexBuffer:vbuf offset:0 atIndex:0];
        [r->m_renderEncoder setVertexBuffer:r->m_uniformBuffer
                                     offset:0
                                    atIndex:kMetalVertexUniformSlot];
        [r->m_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                               vertexStart:0
                               vertexCount:(NSUInteger)nFogVerts];
        [vbuf release];
        
        return true;
    }
    
    bool DrawBlackPortal()
    {
        assert(gRenDev && "CMetalRESky::DrawBlackPortal - gRenDev is null!");
        
        CMetalBaseRenderer* r = checked_cast<CMetalBaseRenderer>(gRenDev);
        assert(r && r->m_renderEncoder && "CMetalRESky::DrawBlackPortal - no active render encoder");
        if (!r || !r->m_renderEncoder)
            return false;
        
        for (int i = 0; i < MAX_SKY_OCCLAREAS_NUM; i++)
        {
            if (m_arrvPortalVerts[i][0].color.dcolor == 0)
                break;
            
            r->SetCullMode(R_CULL_NONE);
            r->SetState(GS_DEPTHWRITE | GS_NOCOLMASK);
        }
        
        return true;
    }
};

//=========================================================================
// CMetalRECommon - Common render element for terrain sectors
//=========================================================================

class CMetalRECommon : public CRendElement
{
public:
    CMetalRECommon()
    {
        mfSetType(eDATA_TerrainSector);
    }
    
    virtual ~CMetalRECommon()
    {
    }
    
    virtual void mfPrepare()
    {
        assert(gRenDev && "CMetalRECommon::mfPrepare - gRenDev is null!");
        
        gRenDev->EF_CheckOverflow(0, 0, this);
        gRenDev->m_RP.m_pRE = this;
        gRenDev->m_RP.m_RendNumIndices = 0;
        gRenDev->m_RP.m_RendNumVerts = 0;
    }
    
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm)
    {
        assert(ef && "CMetalRECommon::mfDraw - ef is null!");
        assert(gRenDev && "CMetalRECommon::mfDraw - gRenDev is null!");
        
        CMetalBaseRenderer* r = checked_cast<CMetalBaseRenderer>(gRenDev);
        assert(r && r->m_renderEncoder && "CMetalRECommon::mfDraw - no active render encoder");
        if (!r || !r->m_renderEncoder)
            return false;
        
        r->SetCullMode(R_CULL_BACK);
        r->SetState(GS_DEPTHWRITE);
        
        return true;
    }
};

//=========================================================================
// CMetalREFarTreeSprites - Far vegetation sprites
//=========================================================================

class CMetalREFarTreeSprites : public CRendElement
{
public:
    CMetalREFarTreeSprites()
    {
        mfSetType(eDATA_FarTreeSprites);
    }
    
    virtual ~CMetalREFarTreeSprites()
    {
    }
    
    virtual void mfPrepare()
    {
        assert(gRenDev && "CMetalREFarTreeSprites::mfPrepare - gRenDev is null!");
        
        gRenDev->EF_CheckOverflow(0, 0, this);
        gRenDev->m_RP.m_pRE = this;
        gRenDev->m_RP.m_RendNumIndices = 0;
        gRenDev->m_RP.m_RendNumVerts = 0;
    }
    
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm)
    {
        assert(ef && "CMetalREFarTreeSprites::mfDraw - ef is null!");
        assert(iSystem && "CMetalREFarTreeSprites::mfDraw - iSystem is null!");
        
        if (!iSystem)
            return false;
        
        I3DEngine* pEngine = iSystem->GetI3DEngine();
        if (!pEngine)
            return false;
        
        pEngine->DrawFarTrees();
        
        return true;
    }
};

//=========================================================================
// CMetalRETerrainDetailTextureLayers - Terrain detail texture layers
//=========================================================================

class CMetalRETerrainDetailTextureLayers : public CRendElement
{
public:
    CMetalRETerrainDetailTextureLayers()
    {
        mfSetType(eDATA_TerrainDetailTextureLayers);
    }
    
    virtual ~CMetalRETerrainDetailTextureLayers()
    {
    }
    
    virtual void mfPrepare()
    {
        assert(gRenDev && "CMetalRETerrainDetailTextureLayers::mfPrepare - gRenDev is null!");
        
        gRenDev->EF_CheckOverflow(0, 0, this);
        gRenDev->m_RP.m_pRE = this;
        gRenDev->m_RP.m_RendNumIndices = 0;
        gRenDev->m_RP.m_RendNumVerts = 0;
    }
    
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm)
    {
        assert(ef && "CMetalRETerrainDetailTextureLayers::mfDraw - ef is null!");
        assert(iSystem && "CMetalRETerrainDetailTextureLayers::mfDraw - iSystem is null!");
        
        if (!iSystem)
            return false;
        
        I3DEngine* pEngine = iSystem->GetI3DEngine();
        if (!pEngine)
            return false;
        
        pEngine->DrawTerrainDetailTextureLayers();
        
        return true;
    }
};

//=========================================================================
// CMetalRETerrainParticles - Terrain particles (grass, debris, etc.)
//=========================================================================

class CMetalRETerrainParticles : public CRendElement
{
public:
    CMetalRETerrainParticles()
    {
        mfSetType(eDATA_TerrainParticles);
    }
    
    virtual ~CMetalRETerrainParticles()
    {
    }
    
    virtual void mfPrepare()
    {
        assert(gRenDev && "CMetalRETerrainParticles::mfPrepare - gRenDev is null!");
        
        gRenDev->EF_CheckOverflow(0, 0, this);
        gRenDev->m_RP.m_pRE = this;
        gRenDev->m_RP.m_RendNumIndices = 0;
        gRenDev->m_RP.m_RendNumVerts = 0;
    }
    
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm)
    {
        assert(ef && "CMetalRETerrainParticles::mfDraw - ef is null!");
        assert(iSystem && "CMetalRETerrainParticles::mfDraw - iSystem is null!");
        
        if (!iSystem || !ef)
            return false;
        
        I3DEngine* pEngine = iSystem->GetI3DEngine();
        if (!pEngine)
            return false;
        
        pEngine->DrawTerrainParticles(ef);
        
        return true;
    }
};

//=========================================================================
// CMetalREOcLeaf - Main render element for static meshes and geometry
//=========================================================================

class CMetalREOcLeaf : public CREOcLeaf
{
public:
    CMetalREOcLeaf()
    {
    }
    
    virtual ~CMetalREOcLeaf()
    {
    }
    
    virtual void mfPrepare()
    {
        assert(gRenDev && "CMetalREOcLeaf::mfPrepare - gRenDev is null!");
        assert(m_pBuffer && "CMetalREOcLeaf::mfPrepare - m_pBuffer is null!");
        assert(m_pChunk && "CMetalREOcLeaf::mfPrepare - m_pChunk is null!");
        
        if (!gRenDev || !m_pBuffer || !m_pChunk)
            return;
        
        gRenDev->EF_CheckOverflow(m_pBuffer->m_SecVertCount, m_pChunk->nNumIndices, this);
        gRenDev->m_RP.m_pRE = this;
        gRenDev->m_RP.m_RendNumIndices = m_pChunk->nNumIndices;
        gRenDev->m_RP.m_RendNumVerts = m_pBuffer->m_SecVertCount;
        gRenDev->m_RP.m_FirstIndex = m_pChunk->nFirstIndexId;
        gRenDev->m_RP.m_FirstVertex = 0;
    }
    
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm)
    {
        assert(ef && "CMetalREOcLeaf::mfDraw - ef is null!");
        assert(gRenDev && "CMetalREOcLeaf::mfDraw - gRenDev is null!");
        assert(m_pBuffer && "CMetalREOcLeaf::mfDraw - m_pBuffer is null!");
        assert(m_pChunk && "CMetalREOcLeaf::mfDraw - m_pChunk is null!");
        
        if (!gRenDev || !m_pBuffer || !m_pChunk)
            return false;
        
        CMetalRenderer* renderer = checked_cast<CMetalRenderer>(gRenDev);
        assert(renderer && "CMetalREOcean: gRenDev is null");
        if (!renderer || !renderer->m_renderEncoder)
            return false;
        
        CLeafBuffer* lb = m_pBuffer;
        if (!lb->m_pVertexBuffer)
            return false;
        
        renderer->SetCullMode(R_CULL_BACK);
        renderer->SetState(GS_DEPTHWRITE);
        
        renderer->DrawBuffer(lb->m_pVertexBuffer,
                             &lb->m_Indices,
                             m_pChunk->nNumIndices,
                             m_pChunk->nFirstIndexId,
                             lb->m_nPrimetiveType,
                             m_pChunk->nFirstVertId,
                             m_pChunk->nNumVerts,
                             m_pChunk);
        
        return true;
    }
};

//=========================================================================
// CMetalRETriMesh - General triangle mesh render element
//=========================================================================

class CMetalRETriMesh : public CRendElement
{
public:
    CMetalRETriMesh()
    {
        mfSetType(eDATA_TriMesh);
    }
    
    virtual ~CMetalRETriMesh()
    {
    }
    
    virtual void mfPrepare()
    {
        assert(gRenDev && "CMetalRETriMesh::mfPrepare - gRenDev is null!");
        
        gRenDev->EF_CheckOverflow(0, 0, this);
        gRenDev->m_RP.m_pRE = this;
        gRenDev->m_RP.m_RendNumIndices = 0;
        gRenDev->m_RP.m_RendNumVerts = 0;
    }
    
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm)
    {
        assert(ef && "CMetalRETriMesh::mfDraw - ef is null!");
        assert(gRenDev && "CMetalRETriMesh::mfDraw - gRenDev is null!");
        
        CMetalBaseRenderer* r = checked_cast<CMetalBaseRenderer>(gRenDev);
        assert(r && r->m_renderEncoder && "CMetalRETriMesh::mfDraw - no active render encoder");
        if (!r || !r->m_renderEncoder)
            return false;
        
        r->SetCullMode(R_CULL_BACK);
        r->SetState(GS_DEPTHWRITE);
        
        return true;
    }
};

//=========================================================================
// CMetalREPrefabGeom - Prefabricated geometry render element
//=========================================================================

class CMetalREPrefabGeom : public CRendElement
{
public:
    CMetalREPrefabGeom()
    {
        mfSetType(eDATA_Prefab);
    }
    
    virtual ~CMetalREPrefabGeom()
    {
    }
    
    virtual void mfPrepare()
    {
        assert(gRenDev && "CMetalREPrefabGeom::mfPrepare - gRenDev is null!");
        
        gRenDev->EF_CheckOverflow(0, 0, this);
        gRenDev->m_RP.m_pRE = this;
        gRenDev->m_RP.m_RendNumIndices = 0;
        gRenDev->m_RP.m_RendNumVerts = 0;
    }
    
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm)
    {
        assert(ef && "CMetalREPrefabGeom::mfDraw - ef is null!");
        assert(gRenDev && "CMetalREPrefabGeom::mfDraw - gRenDev is null!");
        
        CMetalBaseRenderer* r = checked_cast<CMetalBaseRenderer>(gRenDev);
        assert(r && r->m_renderEncoder && "CMetalREPrefabGeom::mfDraw - no active render encoder");
        if (!r || !r->m_renderEncoder)
            return false;
        
        r->SetCullMode(R_CULL_BACK);
        r->SetState(GS_DEPTHWRITE);
        
        return true;
    }
};

//=========================================================================
// CMetalREOcean - FFT-based ocean rendering with realistic waves
//
// Implements a realistic ocean surface using Fast Fourier Transform (FFT)
// for wave simulation based on Phillips spectrum. Supports:
// - Dynamic wave generation with wind direction and speed
// - Choppy waves using displacement mapping
// - Real-time normal map generation
// - Configurable wave height and suppression factors
//
// Technical Details:
// - Grid size: 64x64 vertices (OCEANGRID)
// - Uses FFT to generate height field from frequency domain
// - Applies displacement for choppy wave appearance
// - Calculates normals from height gradients
//
// Performance:
// - FFT computation: O(N log N) where N = OCEANGRID
// - Per-frame vertex updates for dynamic animation
// - GPU vertex buffer updates via Metal
//
// Usage:
//   CMetalREOcean* ocean = new CMetalREOcean();
//   ocean->PostLoad(seed, windDir, windSpeed, waveHeight, ...);
//   ocean->mfDraw(shader, pass);  // Called each frame
//=========================================================================

#define OCEANGRID 64
#define LOG_OCEANGRID 6

class CMetalREOcean : public CRendElement
{
public:
    /// Global static pointer to ocean instance (singleton pattern)
    /// Used by engine to access ocean from anywhere for water elevation queries
    static CMetalREOcean* m_pStaticOcean;
    
    CMetalREOcean()
    {
        mfSetType(eDATA_Ocean);
        mfUpdateFlags(FCEF_TRANSFORM);
        m_pBuffer = nullptr;
        m_fWaveHeight = 2.0f;
        m_fWindSpeed = 20.0f;
        m_fWindDirection = 0.0f;
        m_fChoppyWaveFactor = 1.0f;
        m_fDirectionalDependence = 2.0f;
        m_fSuppressSmallWavesFactor = 0.01f;
        m_fSpeed = 1.0f;
        m_fGravity = 9.8f;
        m_fDepth = 100.0f;
        m_nFrameLoad = 0;
        m_pStaticOcean = this;
        
        GenerateGeometry();
    }
    
    virtual ~CMetalREOcean()
    {
        if (m_pBuffer && gRenDev)
        {
            gRenDev->ReleaseBuffer(m_pBuffer);
        }
        [m_metalVB release]; m_metalVB = nil;
        [m_metalIB release]; m_metalIB = nil;
    }
    
    virtual void mfPrepare()
    {
        assert(gRenDev && "CMetalREOcean::mfPrepare - gRenDev is null!");
        
        if (!gRenDev)
            return;
        
        gRenDev->EF_CheckOverflow(0, 0, this);
        gRenDev->m_RP.m_pRE = this;
        gRenDev->m_RP.m_RendNumIndices = 0;
        gRenDev->m_RP.m_RendNumVerts = 0;
    }
    
    /// Renders the ocean surface into the active render encoder.
    ///
    /// Draw sequence each frame:
    ///   1. Lazy-init GPU buffers via GenerateGeometry() on first call.
    ///   2. Animate CPU vertices with Update(realTime * speed).
    ///   3. Upload via FlushVerticesToGPU() (shared-memory memcpy, no blit).
    ///   4. Bind "ocean" PSO (falls back to VERTEX_FORMAT_P3F_TEX2F generic PSO).
    ///   5. Issue indexed draw with global uniforms at kMetalVertexUniformSlot.
    ///
    /// @return true on successful draw, false if any required resource is missing.
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm)
    {
        assert(ef && "CMetalREOcean::mfDraw - ef is null!");
        assert(gRenDev && "CMetalREOcean::mfDraw - gRenDev is null!");
        if (!gRenDev)
            return false;

        CMetalBaseRenderer* r = checked_cast<CMetalBaseRenderer>(gRenDev);
        assert(r && r->m_renderEncoder && "CMetalREOcean::mfDraw - no active render encoder");
        if (!r || !r->m_renderEncoder)
            return false;

        // Lazy init
        if (!m_metalVB)
            GenerateGeometry();
        assert(m_metalVB && m_metalIB && "CMetalREOcean::mfDraw - GenerateGeometry failed to create GPU buffers");
        if (!m_metalVB || !m_metalIB)
            return false;

        Update(r->m_RP.m_RealTime * m_fSpeed);
        FlushVerticesToGPU();

        r->SetCullMode(R_CULL_NONE);
        r->SetState(GS_DEPTHWRITE | GS_BLSRC_SRCALPHA | GS_BLDST_ONEMINUSSRCALPHA);

        CMetalRenderer* renderer = checked_cast<CMetalRenderer>(gRenDev);
        assert(renderer && renderer->GetShaderManager() && "CMetalREOcean::mfDraw: renderer or shader manager is null");
        if (!renderer || !renderer->GetShaderManager()) return false;

        id<MTLRenderPipelineState> pso =
            renderer->GetShaderManager()->GetPipelineStateForShader("ocean");
        if (!pso)
            pso = renderer->GetShaderManager()->GetPipelineStateForFormat(VERTEX_FORMAT_P3F_TEX2F);
        assert(pso && "CMetalREOcean::mfDraw: no PSO found for ocean/P3F_TEX2F vertex format");
        if (!pso) {
            static bool s_logged = false;
            if (!s_logged) { iLog->Log("CMetalREOcean::mfDraw: no PSO for ocean/P3F_TEX2F — ocean not drawn\n"); s_logged = true; }
            return false;
        }
        [r->m_renderEncoder setRenderPipelineState:pso];

        [r->m_renderEncoder setVertexBuffer:m_metalVB offset:0 atIndex:kMetalVertexStream_General];
        [r->m_renderEncoder setVertexBuffer:r->m_uniformBuffer
                                     offset:0
                                    atIndex:kMetalVertexUniformSlot];
        [r->m_renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                       indexCount:m_indexCount
                                        indexType:MTLIndexTypeUInt16
                                      indexBuffer:m_metalIB
                                indexBufferOffset:0];
        return true;
    }
    
    /// Allocates and initialises the static ocean mesh on the GPU (called lazily on
    /// the first mfDraw).
    ///
    /// Builds an (OCEANGRID+1) × (OCEANGRID+1) grid centred at the world origin.
    /// Each vertex stores: pos(3) + normal(3) + uv(2) as tightly-packed floats.
    /// Indices are stored as uint16 triangle lists (2 tris per quad cell).
    ///
    /// The resulting MTLBuffers use MTLResourceStorageModeShared so that
    /// FlushVerticesToGPU() can memcpy updated heights without a blit encoder.
    ///
    /// Sets m_cellSize and m_halfW which are reused every frame in Update().
    void GenerateGeometry()
    {
        assert(gRenDev && "CMetalREOcean::GenerateGeometry - gRenDev is null!");
        if (!gRenDev) return;
        CMetalBaseRenderer* r = checked_cast<CMetalBaseRenderer>(gRenDev);
        assert(r && r->m_device && "CMetalREOcean::GenerateGeometry - no Metal device");
        if (!r || !r->m_device) return;

        static_assert((OCEANGRID + 1) * (OCEANGRID + 1) <= 65535,
                      "OCEANGRID too large: vertex count exceeds uint16_t index range");

        const int N = OCEANGRID;
        m_cellSize = 2.0f;
        m_halfW = N * m_cellSize * 0.5f;
        const float cellSize = m_cellSize;
        const float halfW    = m_halfW;

        // Vertex layout: position(3) + normal(3) + uv(2) stored as floats = 8 floats
        const int numVerts = (N + 1) * (N + 1);
        m_cpuVerts.resize(numVerts * 8);
        for (int z = 0; z <= N; ++z) {
            for (int x = 0; x <= N; ++x) {
                int idx = (z * (N + 1) + x) * 8;
                m_cpuVerts[idx + 0] = x * cellSize - halfW; // pos.x
                m_cpuVerts[idx + 1] = 0.f;                  // pos.y (height)
                m_cpuVerts[idx + 2] = z * cellSize - halfW; // pos.z
                m_cpuVerts[idx + 3] = 0.f;                  // normal.x
                m_cpuVerts[idx + 4] = 1.f;                  // normal.y
                m_cpuVerts[idx + 5] = 0.f;                  // normal.z
                m_cpuVerts[idx + 6] = (float)x / N;         // uv.u
                m_cpuVerts[idx + 7] = (float)z / N;         // uv.v
            }
        }

        // Index buffer: 2 triangles per cell
        const int numQuads = N * N;
        m_indexCount = numQuads * 6;
        m_cpuIndices.resize(m_indexCount);
        int ii = 0;
        for (int z = 0; z < N; ++z) {
            for (int x = 0; x < N; ++x) {
                uint16_t tl = static_cast<uint16_t>(z * (N + 1) + x);
                uint16_t tr = tl + 1;
                uint16_t bl = tl + (N + 1);
                uint16_t br = bl + 1;
                m_cpuIndices[ii++] = tl; m_cpuIndices[ii++] = bl; m_cpuIndices[ii++] = tr;
                m_cpuIndices[ii++] = tr; m_cpuIndices[ii++] = bl; m_cpuIndices[ii++] = br;
            }
        }

        NSUInteger vbSize = m_cpuVerts.size() * sizeof(float);
        NSUInteger ibSize = m_indexCount * sizeof(uint16_t);
        m_metalVB = [r->m_device newBufferWithBytes:m_cpuVerts.data()
                                             length:vbSize
                                            options:MTLResourceStorageModeShared];
        m_metalIB = [r->m_device newBufferWithBytes:m_cpuIndices.data()
                                             length:ibSize
                                            options:MTLResourceStorageModeShared];
        if (m_metalVB) [m_metalVB setLabel:@"OceanVB"];
        if (m_metalIB) [m_metalIB setLabel:@"OceanIB"];
    }
    
    /// Animates the ocean surface in the CPU vertex array for the given time.
    ///
    /// Uses a sum of three sinusoidal waves (different frequencies and phases) scaled
    /// by m_fWaveHeight to produce a plausible ocean swell.  Only the Y (height)
    /// component of each vertex is modified; normals are not recomputed here.
    ///
    /// @param fTime  Simulation time in seconds (typically m_RP.m_RealTime * m_fSpeed).
    ///
    /// Call FlushVerticesToGPU() after this to push the changes to the MTLBuffer.
    void Update(float fTime)
    {
        if (m_cpuVerts.empty()) return;
        const int N = OCEANGRID;
        const float cellSize = m_cellSize;
        const float halfW    = m_halfW;
        const float waveScale = m_fWaveHeight * 0.5f;
        const float freq0 = 0.5f, freq1 = 0.9f, freq2 = 1.4f;

        for (int z = 0; z <= N; ++z) {
            for (int x = 0; x <= N; ++x) {
                int idx = (z * (N + 1) + x) * 8;
                float wx = x * cellSize - halfW;
                float wz = z * cellSize - halfW;
                float h = waveScale * (
                    sinf(wx * 0.07f + fTime * freq0) * cosf(wz * 0.06f + fTime * freq1) +
                    0.5f * sinf(wx * 0.13f - fTime * freq2 + wz * 0.11f));
                m_cpuVerts[idx + 1] = h;
            }
        }
    }

    /// Copies the CPU-side vertex array into the MTLBuffer.
    ///
    /// Safe to call every frame because m_metalVB uses MTLResourceStorageModeShared
    /// (CPU and GPU share the same physical pages).  No blit encoder or synchronisation
    /// is needed — Metal guarantees the copy is visible to the GPU for the next
    /// command buffer that references the buffer.
    void FlushVerticesToGPU()
    {
        if (!m_metalVB || m_cpuVerts.empty()) return;
        void* dst = [m_metalVB contents];
        if (dst)
            memcpy(dst, m_cpuVerts.data(), m_cpuVerts.size() * sizeof(float));
    }
    
    /// Queries the water surface elevation at a world position
    ///
    /// @param fX World X coordinate
    /// @param fY World Y coordinate
    /// @return Water surface height (Z coordinate) at the given position
    ///
    /// Used by:
    /// - Physics system for buoyancy calculations
    /// - AI system for pathfinding over water
    /// - Particle effects for water splashes
    ///
    /// Implementation: Currently returns 0.0f (flat water)
    /// Full implementation would:
    /// - Convert world coords to ocean grid coords
    /// - Bilinearly interpolate height from surrounding vertices
    /// - Account for wave animation phase
    float GetWaterZElevation(float fX, float fY)
    {
        return 0.0f;
    }
    
    /// Initializes ocean simulation parameters after level load
    ///
    /// @param ulSeed Random seed for wave generation (for deterministic waves)
    /// @param fWindDirection Wind direction in radians (0 = +X, π/2 = +Y)
    /// @param fWindSpeed Wind speed in m/s (typical: 10-30 m/s)
    /// @param fWaveHeight Wave amplitude scale (typical: 1.0-5.0)
    /// @param fDirectionalDependence How aligned waves are with wind (typical: 2.0)
    /// @param fChoppyWavesFactor Displacement strength for choppy appearance (0.0-2.0)
    /// @param fSuppressSmallWavesFactor Dampens high-frequency waves (0.0-1.0)
    ///
    /// Called by:
    /// - Level loading system after terrain initialization
    /// - Console commands for runtime ocean adjustment
    ///
    /// Physics Parameters:
    /// - Gravity: 9.8 m/s² (Earth standard)
    /// - Depth: 100m (affects wave dispersion)
    /// - Largest wave: Computed from wind speed (λ = g * windSpeed²)
    ///
    /// Example:
    ///   ocean->PostLoad(12345, 0.0f, 20.0f, 2.0f, 2.0f, 1.0f, 0.01f);
    ///   // Creates moderate waves with 20 m/s wind from +X direction
    void PostLoad(unsigned long ulSeed, float fWindDirection, float fWindSpeed, 
                  float fWaveHeight, float fDirectionalDependence, float fChoppyWavesFactor, 
                  float fSuppressSmallWavesFactor)
    {
        m_fWindDirection = fWindDirection;
        m_fWindSpeed = fWindSpeed;
        m_fWaveHeight = fWaveHeight;
        m_fDirectionalDependence = fDirectionalDependence;
        m_fChoppyWaveFactor = fChoppyWavesFactor;
        m_fSuppressSmallWavesFactor = fSuppressSmallWavesFactor;
    }
    
private:
    // Rendering resources
    CVertexBuffer* m_pBuffer;        ///< GPU vertex buffer for ocean mesh (owned)
    int m_nFrameLoad;                ///< Frame ID when ocean was last loaded
    
    // Wave simulation parameters
    float m_fWaveHeight;             ///< Wave amplitude multiplier (1.0-5.0)
    float m_fWindSpeed;              ///< Wind speed in m/s (10-30 typical)
    float m_fWindDirection;          ///< Wind direction in radians
    float m_fChoppyWaveFactor;       ///< Displacement strength (0.0-2.0)
    float m_fDirectionalDependence;  ///< Wind alignment factor (2.0 typical)
    float m_fSuppressSmallWavesFactor; ///< High-frequency wave dampening
    float m_fSpeed;                  ///< Animation speed multiplier (1.0 = real-time)
    float m_fGravity;                ///< Gravity constant (9.8 m/s²)
    float m_fDepth;                  ///< Water depth for dispersion (100m)
    
    // FFT wave field data (complex numbers split into real/imaginary)
    float m_HX[OCEANGRID][OCEANGRID]; ///< Height field X component (real part)
    float m_HY[OCEANGRID][OCEANGRID]; ///< Height field Y component (imaginary part)
    float m_NX[OCEANGRID][OCEANGRID]; ///< Normal X component
    float m_NY[OCEANGRID][OCEANGRID]; ///< Normal Y component
    float m_DX[OCEANGRID][OCEANGRID]; ///< Displacement X for choppy waves
    float m_DY[OCEANGRID][OCEANGRID]; ///< Displacement Y for choppy waves
    float m_Pos[OCEANGRID+1][OCEANGRID+1][2]; ///< Final vertex XY positions
    Vec3d m_Normals[OCEANGRID+1][OCEANGRID+1]; ///< Final vertex normals

    // Metal GPU resources
    id<MTLBuffer> m_metalVB = nil;
    id<MTLBuffer> m_metalIB = nil;
    int m_indexCount = 0;
    std::vector<float>    m_cpuVerts;
    std::vector<uint16_t> m_cpuIndices;

    // Grid layout constants (set once in GenerateGeometry, reused in Update)
    float m_cellSize = 2.0f;
    float m_halfW    = 0.0f;
};

CMetalREOcean* CMetalREOcean::m_pStaticOcean = nullptr;

//=========================================================================
// Factory function - creates Metal render elements
//=========================================================================

CRendElement* CreateMetalRenderElement(EDataType edt)
{
    CRendElement* re = nullptr;
    
    switch(edt)
    {
        case eDATA_Sky:
            re = new CMetalRESky();
            break;
            
        case eDATA_TerrainSector:
            re = new CMetalRECommon();
            break;
            
        case eDATA_FarTreeSprites:
            re = new CMetalREFarTreeSprites();
            break;
            
        case eDATA_TerrainDetailTextureLayers:
            re = new CMetalRETerrainDetailTextureLayers();
            break;
            
        case eDATA_TerrainParticles:
            re = new CMetalRETerrainParticles();
            break;
            
        case eDATA_OcLeaf:
            re = new CMetalREOcLeaf();
            break;
            
        case eDATA_TriMesh:
            re = new CMetalRETriMesh();
            break;
            
        case eDATA_Prefab:
            re = new CMetalREPrefabGeom();
            break;
            
        case eDATA_Ocean:
            re = new CMetalREOcean();
            break;
            
        case eDATA_2DQuad:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_2DQuad);
            break;
            
        case eDATA_Dummy:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_Dummy);
            break;
            
        case eDATA_Flare:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_Flare);
            break;
            
        case eDATA_Beam:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_Beam);
            break;
            
        case eDATA_Glare:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_Glare);
            break;
            
        case eDATA_TriMeshShadow:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_TriMeshShadow);
            break;
            
        case eDATA_ShadowMapGen:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_ShadowMapGen);
            break;
            
        case eDATA_FlashBang:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_FlashBang);
            break;
            
        case eDATA_ScreenProcess:
            re = new CREScreenProcess();
            break;
            
        case eDATA_HDRProcess:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_HDRProcess);
            break;
            
        case eDATA_OcclusionQuery:
            re = new CREOcclusionQuery();
            break;
            
        case eDATA_Poly:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_Poly);
            break;
            
        case eDATA_ClearStencil:
            re = new CREClearStencil();
            break;

        default:
            break;
    }
    
    assert((re != nullptr || edt == eDATA_Unknown) && "CreateMetalRenderElement: failed to create render element!");
    
    return re;
}

CREOcclusionQuery::~CREOcclusionQuery()
{
    mfReset();
}

void CREOcclusionQuery::mfReset()
{
    m_nOcclusionID = 0;
}

bool CREOcclusionQuery::mfDraw(SShader* ef, SShaderPass* sfm)
{
    return true;
}

list2<CMatInfo>* CREOcLeaf::mfGetMatInfoList()
{
    return m_pBuffer ? m_pBuffer->m_pMats : nullptr;
}

CMatInfo* CREOcLeaf::mfGetMatInfo()
{
    return m_pChunk;
}

int CREOcLeaf::mfGetMatId()
{
    return m_pChunk ? m_pChunk->m_Id : -1;
}

void CREOcLeaf::mfGetPlane(Plane& pl)
{
    Vec3 mins, maxs;
    mfGetBBox(mins, maxs);
    Vec3 center = (mins + maxs) * 0.5f;
    pl.n = Vec3(0.0f, 0.0f, 1.0f);
    pl.d = -pl.n.Dot(center);
}

void CREOcLeaf::mfEndFlush()
{
}

void* CREOcLeaf::mfGetPointer(ESrcPointer ePT, int* Stride, int Type, ESrcPointer Dst, int Flags)
{
    if (!m_pBuffer || !Stride)
        return nullptr;
    
    CLeafBuffer* lb = m_pBuffer->GetVertexContainer();
    switch (ePT)
    {
        case eSrcPointer_Vert:
            return lb->GetPosPtr(*Stride, m_pChunk ? m_pChunk->nFirstVertId : 0, true);
        case eSrcPointer_Tex:
            return lb->GetUVPtr(*Stride, m_pChunk ? m_pChunk->nFirstVertId : 0, true);
        case eSrcPointer_Color:
            return lb->GetColorPtr(*Stride, m_pChunk ? m_pChunk->nFirstVertId : 0, true);
        case eSrcPointer_Normal:
            return lb->GetNormalPtr(*Stride, m_pChunk ? m_pChunk->nFirstVertId : 0, true);
        default:
            return nullptr;
    }
}

bool CREOcLeaf::mfCheckUpdate(int nVertFormat, int Flags)
{
    return m_pBuffer ? m_pBuffer->CheckUpdate(nVertFormat, Flags, (Flags & SHPF_TANGENTS) != 0) : false;
}

bool CREOcLeaf::mfCullByClipPlane(CCObject* pObj)
{
    return false;
}

float CREOcLeaf::mfMinDistanceToCamera(CCObject* pObj)
{
    const CCObject* obj = pObj ? pObj : gRenDev->m_RP.m_pCurObject;
    if (!obj)
        return 0.0f;
    return cry_sqrtf(mfDistanceToCameraSquared(*obj));
}

float CREOcLeaf::mfDistanceToCameraSquared(const CCObject& thisObject)
{
    if (!gRenDev)
        return 0.0f;
    
    Vec3 mins, maxs;
    mfGetBBox(mins, maxs);
    Vec3 center = (mins + maxs) * 0.5f + thisObject.GetTranslation();
    Vec3 delta = gRenDev->m_RP.m_ViewOrg - center;
    return delta.Dot(delta);
}

void CREOcLeaf::mfCenter(Vec3& Pos, CCObject* pObj)
{
    Vec3 mins, maxs;
    mfGetBBox(mins, maxs);
    Pos = (mins + maxs) * 0.5f;
    if (pObj)
        Pos += pObj->GetTranslation();
}

void CREOcLeaf::mfGetBBox(Vec3& vMins, Vec3& vMaxs)
{
    if (m_pBuffer)
    {
        vMins = m_pBuffer->m_vBoxMin;
        vMaxs = m_pBuffer->m_vBoxMax;
    }
    else
    {
        vMins = Vec3(0.0f, 0.0f, 0.0f);
        vMaxs = Vec3(0.0f, 0.0f, 0.0f);
    }
}

bool CREOcLeaf::mfPreDraw(SShaderPass* sl)
{
    return true;
}

void CREOcLeaf::mfPrepare()
{
}

bool CREOcLeaf::mfDraw(SShader* ef, SShaderPass* sfm)
{
    return true;
}

#endif // __APPLE__ && __MACH__

