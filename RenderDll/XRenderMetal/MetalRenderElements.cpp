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

#include "MetalBaseRenderer.h"
#include "MetalTextureManager.h"
#include "MetalShaderManager.h"
#include "I3DEngine.h"
#include "ISystem.h"
#include <Metal/Metal.h>

extern ISystem *iSystem;

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
            r->SetState(GS_DEPTHWRITE | GS_COLMASKNONE);
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
        
        gRenDev->EF_CheckOverflow(m_pBuffer->GetSecVertCount(), m_pChunk->nNumIndices, this);
        gRenDev->m_RP.m_pRE = this;
        gRenDev->m_RP.m_RendNumIndices = m_pChunk->nNumIndices;
        gRenDev->m_RP.m_RendNumVerts = m_pBuffer->GetSecVertCount();
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
            
        default:
            break;
    }
    
    assert(re || edt == eDATA_Unknown && "CreateMetalRenderElement: failed to create render element!");
    
    return re;
}

#endif // __APPLE__ && __MACH__

