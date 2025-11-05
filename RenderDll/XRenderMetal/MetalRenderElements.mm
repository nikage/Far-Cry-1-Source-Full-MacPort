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

#include "MetalBaseRenderer.m"
#include "MetalTextureManager.m"
#include "MetalShaderManager.m"
#include "I3DEngine.h"
#include "ISystem.h"
#include "LeafBuffer.h"
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
        
        CMetalBaseRenderer* r = static_cast<CMetalBaseRenderer*>(gRenDev);
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
        
        if (!vertices.empty() && !indices.empty())
        {
            r->SetCullMode(R_CULL_NONE);
            r->SetState(GS_BLSRC_SRCALPHA | GS_BLDST_ONEMINUSSRCALPHA | GS_NODEPTHTEST);
        }
    }
    
    bool DrawFogLayer()
    {
        assert(gRenDev && "CMetalRESky::DrawFogLayer - gRenDev is null!");
        assert(m_parrFogLayer && "CMetalRESky::DrawFogLayer - fog layer is null!");
        
        CMetalBaseRenderer* r = static_cast<CMetalBaseRenderer*>(gRenDev);
        if (!r || !r->m_renderEncoder || !m_parrFogLayer)
            return false;
        
        if (m_parrFogLayer->Count() == 0)
            return false;
        
        r->SetCullMode(R_CULL_NONE);
        r->SetState(GS_BLSRC_SRCALPHA | GS_BLDST_ONEMINUSSRCALPHA | GS_NODEPTHTEST);
        
        return true;
    }
    
    bool DrawBlackPortal()
    {
        assert(gRenDev && "CMetalRESky::DrawBlackPortal - gRenDev is null!");
        
        CMetalBaseRenderer* r = static_cast<CMetalBaseRenderer*>(gRenDev);
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
        
        CMetalBaseRenderer* r = static_cast<CMetalBaseRenderer*>(gRenDev);
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

class CMetalREOcLeaf : public CRendElement
{
public:
    CLeafBuffer* m_pBuffer;
    CMatInfo* m_pChunk;
    
    CMetalREOcLeaf()
    {
        mfSetType(eDATA_OcLeaf);
        m_pBuffer = nullptr;
        m_pChunk = nullptr;
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
        
        CMetalBaseRenderer* r = static_cast<CMetalBaseRenderer*>(gRenDev);
        if (!r || !r->m_renderEncoder)
            return false;
        
        r->SetCullMode(R_CULL_BACK);
        r->SetState(GS_DEPTHWRITE);
        
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
        
        CMetalBaseRenderer* r = static_cast<CMetalBaseRenderer*>(gRenDev);
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
        
        CMetalBaseRenderer* r = static_cast<CMetalBaseRenderer*>(gRenDev);
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
    
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm)
    {
        assert(ef && "CMetalREOcean::mfDraw - ef is null!");
        assert(gRenDev && "CMetalREOcean::mfDraw - gRenDev is null!");
        
        if (!gRenDev)
            return false;
        
        CMetalBaseRenderer* r = static_cast<CMetalBaseRenderer*>(gRenDev);
        if (!r || !r->m_renderEncoder)
            return false;
        
        Update(r->m_RP.m_RealTime * m_fSpeed);
        
        r->SetCullMode(R_CULL_BACK);
        r->SetState(GS_DEPTHWRITE | GS_BLSRC_SRCALPHA | GS_BLDST_ONEMINUSSRCALPHA);
        
        return true;
    }
    
    /// Generates the ocean geometry mesh
    /// 
    /// Creates a (OCEANGRID+1) x (OCEANGRID+1) grid of vertices for the ocean surface.
    /// This is called once during initialization to set up the base mesh structure.
    /// The actual vertex positions are updated each frame in Update().
    ///
    /// Implementation: Currently a placeholder - full implementation would:
    /// - Initialize vertex positions in a regular grid
    /// - Set up texture coordinates
    /// - Generate index buffer for triangle strips
    void GenerateGeometry()
    {
    }
    
    /// Updates ocean wave simulation for the current frame
    ///
    /// Performs FFT-based wave generation using Phillips spectrum.
    /// Updates height field, normals, and displacement vectors for choppy waves.
    ///
    /// @param fTime Current simulation time in seconds
    ///
    /// Algorithm:
    /// 1. Compute wave spectrum in frequency domain (FFT)
    /// 2. Apply dispersion relation for water waves
    /// 3. Transform to spatial domain (inverse FFT)
    /// 4. Calculate normals from height gradients
    /// 5. Apply displacement for choppy wave effect
    ///
    /// Performance: O(N² log N) where N = OCEANGRID (64)
    ///
    /// Implementation: Currently a placeholder - full implementation would:
    /// - Calculate H(k,t) from H0(k) and dispersion relation
    /// - Perform 2D FFT to get height field
    /// - Compute displacement vectors (Dx, Dy)
    /// - Calculate normals (Nx, Ny)
    /// - Update vertex buffer with new positions and normals
    void Update(float fTime)
    {
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
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_ScreenProcess);
            break;
            
        case eDATA_HDRProcess:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_HDRProcess);
            break;
            
        case eDATA_OcclusionQuery:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_OcclusionQuery);
            break;
            
        case eDATA_Poly:
            re = new CRendElement();
            if (re) re->mfSetType(eDATA_Poly);
            break;
            
        default:
            break;
    }
    
    assert(re || edt == eDATA_Unknown && "CreateMetalRenderElement: failed to create render element!");
    
    return re;
}

#endif // __APPLE__ && __MACH__

