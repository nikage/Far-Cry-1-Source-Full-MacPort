////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalShaderManager.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal shader manager implementation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalShaderManager.h"
#include "MetalBaseRenderer.h"
#include "MetalTextureManager.h"
#include "I3DEngine.h"
#include <Cocoa/Cocoa.h>
#include <cassert>
#include <iostream>

// Minimal render element implementations with comprehensive assertions
class CMetalRESky : public CRendElement
{
public:
    CMetalRESky() { 
        mfSetType(eDATA_Sky);
        printf("CMetalRESky: Constructor called\n");
        
        // Initialize sky-specific properties
        m_Flags = 0;
        m_SortId = -1000; // Sky renders first (lowest sort ID)
        m_Color = CFColor(0.5f, 0.7f, 1.0f, 1.0f); // Light blue sky color
    }
    virtual ~CMetalRESky() { 
        printf("CMetalRESky: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalRESky::mfPrepare called\n");
        
        // Set up sky rendering state
        m_Flags |= FCEF_ALLOC_CUST_FLOAT_DATA;
        m_SortId = -1000; // Ensure sky renders first
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalRESky::mfDraw: ef is null");
        printf("CMetalRESky::mfDraw called\n");
        
        // Dummy sky rendering - would set up sky dome rendering here
        return true; 
    }
};

class CMetalREDummy : public CRendElement
{
public:
    CMetalREDummy() { 
        mfSetType(eDATA_Dummy);
        printf("CMetalREDummy: Constructor called\n");
    }
    virtual ~CMetalREDummy() { 
        printf("CMetalREDummy: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalREDummy::mfPrepare called\n");
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalREDummy::mfDraw: ef is null");
        printf("CMetalREDummy::mfDraw called\n");
        return true; 
    }
};

class CMetalRE2DQuad : public CRendElement
{
public:
    CMetalRE2DQuad() { 
        mfSetType(eDATA_2DQuad);
        printf("CMetalRE2DQuad: Constructor called\n");
        
        // Initialize 2D quad properties
        m_Flags = 0;
        m_SortId = 1000; // 2D elements render last (highest sort ID)
        m_Color = CFColor(1.0f, 1.0f, 1.0f, 1.0f); // White color
    }
    virtual ~CMetalRE2DQuad() { 
        printf("CMetalRE2DQuad: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalRE2DQuad::mfPrepare called\n");
        
        // Set up 2D rendering state
        m_Flags |= FCEF_ALLOC_CUST_FLOAT_DATA;
        m_SortId = 1000; // Ensure 2D elements render last
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalRE2DQuad::mfDraw: ef is null");
        printf("CMetalRE2DQuad::mfDraw called\n");
        
        // Dummy 2D quad rendering - would set up screen-space quad here
        return true; 
    }
};

class CMetalREScreenProcess : public CRendElement
{
public:
    CMetalREScreenProcess() { 
        mfSetType(eDATA_ScreenProcess);
        printf("CMetalREScreenProcess: Constructor called\n");
    }
    virtual ~CMetalREScreenProcess() { 
        printf("CMetalREScreenProcess: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalREScreenProcess::mfPrepare called\n");
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalREScreenProcess::mfDraw: ef is null");
        printf("CMetalREScreenProcess::mfDraw called\n");
        return true; 
    }
};

class CMetalREShadowMapGen : public CRendElement
{
public:
    CMetalREShadowMapGen() { 
        mfSetType(eDATA_ShadowMapGen);
        printf("CMetalREShadowMapGen: Constructor called\n");
    }
    virtual ~CMetalREShadowMapGen() { 
        printf("CMetalREShadowMapGen: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalREShadowMapGen::mfPrepare called\n");
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalREShadowMapGen::mfDraw: ef is null");
        printf("CMetalREShadowMapGen::mfDraw called\n");
        return true; 
    }
};

class CMetalRECommon : public CRendElement
{
public:
    CMetalRECommon() { 
        mfSetType(eDATA_TerrainSector);
        printf("CMetalRECommon: Constructor called\n");
    }
    virtual ~CMetalRECommon() { 
        printf("CMetalRECommon: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalRECommon::mfPrepare called\n");
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalRECommon::mfDraw: ef is null");
        printf("CMetalRECommon::mfDraw called\n");
        return true; 
    }
};

class CMetalRETriMeshShadow : public CRendElement
{
public:
    CMetalRETriMeshShadow() { 
        mfSetType(eDATA_TriMeshShadow);
        printf("CMetalRETriMeshShadow: Constructor called\n");
    }
    virtual ~CMetalRETriMeshShadow() { 
        printf("CMetalRETriMeshShadow: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalRETriMeshShadow::mfPrepare called\n");
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalRETriMeshShadow::mfDraw: ef is null");
        printf("CMetalRETriMeshShadow::mfDraw called\n");
        return true; 
    }
};

class CMetalREFlashBang : public CRendElement
{
public:
    CMetalREFlashBang() { 
        mfSetType(eDATA_FlashBang);
        printf("CMetalREFlashBang: Constructor called\n");
    }
    virtual ~CMetalREFlashBang() { 
        printf("CMetalREFlashBang: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalREFlashBang::mfPrepare called\n");
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalREFlashBang::mfDraw: ef is null");
        printf("CMetalREFlashBang::mfDraw called\n");
        return true; 
    }
};

class CMetalREOcclusionQuery : public CRendElement
{
public:
    CMetalREOcclusionQuery() { 
        mfSetType(eDATA_OcclusionQuery);
        printf("CMetalREOcclusionQuery: Constructor called\n");
    }
    virtual ~CMetalREOcclusionQuery() { 
        printf("CMetalREOcclusionQuery: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalREOcclusionQuery::mfPrepare called\n");
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalREOcclusionQuery::mfDraw: ef is null");
        printf("CMetalREOcclusionQuery::mfDraw called\n");
        return true; 
    }
};

class CMetalREOcLeaf : public CRendElement
{
public:
    CMetalREOcLeaf() { 
        mfSetType(eDATA_OcLeaf);
        printf("CMetalREOcLeaf: Constructor called\n");
    }
    virtual ~CMetalREOcLeaf() { 
        printf("CMetalREOcLeaf: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalREOcLeaf::mfPrepare called\n");
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalREOcLeaf::mfDraw: ef is null");
        printf("CMetalREOcLeaf::mfDraw called\n");
        return true; 
    }
};

class CMetalRETerrainParticles : public CRendElement
{
public:
    CMetalRETerrainParticles() { 
        mfSetType(eDATA_TerrainParticles);
        printf("CMetalRETerrainParticles: Constructor called\n");
    }
    virtual ~CMetalRETerrainParticles() { 
        printf("CMetalRETerrainParticles: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalRETerrainParticles::mfPrepare called\n");
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalRETerrainParticles::mfDraw: ef is null");
        printf("CMetalRETerrainParticles::mfDraw called\n");
        return true; 
    }
};

class CMetalREFarTreeSprites : public CRendElement
{
public:
    CMetalREFarTreeSprites() { 
        mfSetType(eDATA_FarTreeSprites);
        printf("CMetalREFarTreeSprites: Constructor called\n");
    }
    virtual ~CMetalREFarTreeSprites() { 
        printf("CMetalREFarTreeSprites: Destructor called\n");
    }
    virtual void mfPrepare() {
        printf("CMetalREFarTreeSprites::mfPrepare called\n");
    }
    virtual bool mfDraw(SShader *ef, SShaderPass *sfm) { 
        assert(ef != nullptr && "CMetalREFarTreeSprites::mfDraw: ef is null");
        printf("CMetalREFarTreeSprites::mfDraw called\n");
        return true; 
    }
};

// Helper function to get render element type name
const char* GetRenderElementTypeName(EDataType edt) {
    switch(edt) {
        case eDATA_Sky: return "Sky";
        case eDATA_Dummy: return "Dummy";
        case eDATA_2DQuad: return "2DQuad";
        case eDATA_ShadowMapGen: return "ShadowMapGen";
        case eDATA_TriMeshShadow: return "TriMeshShadow";
        case eDATA_OcclusionQuery: return "OcclusionQuery";
        case eDATA_OcLeaf: return "OcLeaf";
        case eDATA_TerrainParticles: return "TerrainParticles";
        case eDATA_FarTreeSprites: return "FarTreeSprites";
        case eDATA_Beam: return "Beam";
        case eDATA_Poly: return "Poly";
        case eDATA_TriMesh: return "TriMesh";
        case eDATA_Prefab: return "Prefab";
        case eDATA_Terrain: return "Terrain";
        case eDATA_Ocean: return "Ocean";
        case eDATA_Glare: return "Glare";
        default: return "Unknown";
    }
}

// CRendElement implementations for Metal renderer - Proper dummy stubs
void CRendElement::mfPrepare() {
    assert(this != nullptr && "CRendElement::mfPrepare: this is null");
    printf("CRendElement::mfPrepare called for type %d\n", (int)m_Type);
    
    // Set up basic render state for dummy implementation
    m_Flags = 0; // Clear any previous flags
    m_SortId = 0; // Default sort order
}

void CRendElement::mfEndFlush() {
    assert(this != nullptr && "CRendElement::mfEndFlush: this is null");
    printf("CRendElement::mfEndFlush called for type %d\n", (int)m_Type);
    
    // Clean up any temporary state
    m_Flags &= ~FCEF_ALLOC_CUST_FLOAT_DATA; // Clear custom data flag
}

bool CRendElement::mfDraw(SShader *ef, SShaderPass *sfm) {
    assert(this != nullptr && "CRendElement::mfDraw: this is null");
    assert(ef != nullptr && "CRendElement::mfDraw: ef is null");
    assert(sfm != nullptr && "CRendElement::mfDraw: sfm is null");
    printf("CRendElement::mfDraw called for type %d\n", (int)m_Type);
    
    // Dummy implementation - just return success
    // In a real implementation, this would set up rendering state
    return true;
}

int CRendElement::mfGetMatId() { 
    assert(this != nullptr && "CRendElement::mfGetMatId: this is null");
    printf("CRendElement::mfGetMatId called for type %d\n", (int)m_Type);
    
    // Return a default material ID based on render element type
    switch(m_Type) {
        case eDATA_Sky: return 1;
        case eDATA_2DQuad: return 2;
        case eDATA_Dummy: return 0;
        default: return 0;
    }
}

void CRendElement::mfGetPlane(Plane& pl) { 
    assert(this != nullptr && "CRendElement::mfGetPlane: this is null");
    printf("CRendElement::mfGetPlane called for type %d\n", (int)m_Type);
    
    // Set up a default plane (horizontal at origin)
    pl.n = Vec3d(0, 0, 1); // Normal pointing up
    pl.d = 0.0f; // Distance from origin
}

int CRendElement::mfTransform(Matrix44& ViewMatr, Matrix44& ProjMatr, vec4_t *verts, vec4_t *vertsp, int Num) { 
    assert(this != nullptr && "CRendElement::mfTransform: this is null");
    assert(verts != nullptr && "CRendElement::mfTransform: verts is null");
    assert(vertsp != nullptr && "CRendElement::mfTransform: vertsp is null");
    assert(Num >= 0 && "CRendElement::mfTransform: Num is negative");
    printf("CRendElement::mfTransform called with Num=%d for type %d\n", Num, (int)m_Type);
    
    // Dummy transform - just copy vertices without transformation
    for(int i = 0; i < Num; i++) {
        vertsp[i][0] = verts[i][0];
        vertsp[i][1] = verts[i][1];
        vertsp[i][2] = verts[i][2];
        vertsp[i][3] = verts[i][3];
    }
    return Num; // Return number of transformed vertices
}

CMatInfo* CRendElement::mfGetMatInfo() { 
    assert(this != nullptr && "CRendElement::mfGetMatInfo: this is null");
    printf("CRendElement::mfGetMatInfo called for type %d\n", (int)m_Type);
    
    // Return nullptr for dummy implementation
    // In a real implementation, this would return material information
    return nullptr; 
}

void* CRendElement::mfGetPointer(ESrcPointer ePT, int *Stride, int Type, ESrcPointer Dst, int Flags) { 
    assert(this != nullptr && "CRendElement::mfGetPointer: this is null");
    assert(Stride != nullptr && "CRendElement::mfGetPointer: Stride is null");
    assert(static_cast<int>(ePT) >= 0 && "CRendElement::mfGetPointer: invalid ePT");
    assert(static_cast<int>(Dst) >= 0 && "CRendElement::mfGetPointer: invalid Dst");
    printf("CRendElement::mfGetPointer called\n");
    return nullptr; 
}

bool CRendElement::mfIsValidTime(SShader *ef, CCObject *obj, float curtime) { 
    assert(this != nullptr && "CRendElement::mfIsValidTime: this is null");
    assert(ef != nullptr && "CRendElement::mfIsValidTime: ef is null");
    assert(obj != nullptr && "CRendElement::mfIsValidTime: obj is null");
    assert(curtime >= 0.0f && "CRendElement::mfIsValidTime: curtime is negative");
    printf("CRendElement::mfIsValidTime called with curtime=%f\n", curtime);
    return true; 
}

void CRendElement::mfBuildGeometry(SShader *ef) {
    assert(this != nullptr && "CRendElement::mfBuildGeometry: this is null");
    assert(ef != nullptr && "CRendElement::mfBuildGeometry: ef is null");
    printf("CRendElement::mfBuildGeometry called\n");
}

CRendElement* CRendElement::mfCopyConstruct() { 
    assert(this != nullptr && "CRendElement::mfCopyConstruct: this is null");
    printf("CRendElement::mfCopyConstruct called\n");
    return new CMetalREDummy; 
}

CRendElement* CRendElement::mfCreateWorldRE(SShader *ef, SInpData *ds) { 
    assert(this != nullptr && "CRendElement::mfCreateWorldRE: this is null");
    assert(ef != nullptr && "CRendElement::mfCreateWorldRE: ef is null");
    assert(ds != nullptr && "CRendElement::mfCreateWorldRE: ds is null");
    printf("CRendElement::mfCreateWorldRE called\n");
    return nullptr; 
}

list2<CMatInfo>* CRendElement::mfGetMatInfoList() { 
    assert(this != nullptr && "CRendElement::mfGetMatInfoList: this is null");
    printf("CRendElement::mfGetMatInfoList called\n");
    return nullptr; 
}

bool CRendElement::mfCullByClipPlane(CCObject *pObj) { 
    assert(this != nullptr && "CRendElement::mfCullByClipPlane: this is null");
    assert(pObj != nullptr && "CRendElement::mfCullByClipPlane: pObj is null");
    printf("CRendElement::mfCullByClipPlane called for type %d\n", (int)m_Type);
    
    // Dummy culling - always visible for most types
    switch(m_Type) {
        case eDATA_Sky: return false; // Sky is always visible
        case eDATA_2DQuad: return false; // 2D quads are always visible
        default: return false; // Default to visible
    }
}

float CRendElement::mfDistanceToCameraSquared(const CCObject & thisObject) { 
    assert(this != nullptr && "CRendElement::mfDistanceToCameraSquared: this is null");
    printf("CRendElement::mfDistanceToCameraSquared called for type %d\n", (int)m_Type);
    
    // Return different distances based on render element type
    switch(m_Type) {
        case eDATA_Sky: return 1000.0f; // Sky is far away
        case eDATA_2DQuad: return 0.1f; // 2D quads are close
        default: return 1.0f; // Default distance
    }
}

bool CRendElement::mfCull(CCObject *pObj) { 
    assert(this != nullptr && "CRendElement::mfCull: this is null");
    assert(pObj != nullptr && "CRendElement::mfCull: pObj is null");
    printf("CRendElement::mfCull called for type %d\n", (int)m_Type);
    
    // Dummy culling logic - most elements are visible
    return false; // Not culled (visible)
}

bool CRendElement::mfCull(CCObject *pObj, SShader *ef) { 
    assert(this != nullptr && "CRendElement::mfCull: this is null");
    assert(pObj != nullptr && "CRendElement::mfCull: pObj is null");
    assert(ef != nullptr && "CRendElement::mfCull: ef is null");
    printf("CRendElement::mfCull called for type %d with shader\n", (int)m_Type);
    
    // Dummy culling with shader consideration
    return false; // Not culled (visible)
}

void CRendElement::Release() { 
    assert(this != nullptr && "CRendElement::Release: this is null");
    printf("CRendElement::Release called\n");
    delete this; 
}

void CRendElement::mfReset() {
    assert(this != nullptr && "CRendElement::mfReset: this is null");
    printf("CRendElement::mfReset called\n");
}

void CRendElement::mfCenter(Vec3d& centr, CCObject *pObj) { 
    assert(this != nullptr && "CRendElement::mfCenter: this is null");
    assert(pObj != nullptr && "CRendElement::mfCenter: pObj is null");
    printf("CRendElement::mfCenter called\n");
    centr(0,0,0); 
}

bool CRendElement::mfCompile(SShader *ef, char *scr) { 
    assert(this != nullptr && "CRendElement::mfCompile: this is null");
    assert(ef != nullptr && "CRendElement::mfCompile: ef is null");
    assert(scr != nullptr && "CRendElement::mfCompile: scr is null");
    printf("CRendElement::mfCompile called\n");
    return true; 
}

// Define missing static member
CRendElement CRendElement::m_RootGlobal;

CMetalShaderManager::CMetalShaderManager(CMetalBaseRenderer* renderer, CMetalTextureManager* textureManager)
    : m_renderer(renderer)
    , m_textureManager(textureManager)
    , m_nextShaderId(1)
    , m_currentShaderId(-1)
    , m_currentPipelineState(nil)
    , m_globalShaderTemplateId(0)
{
    // Assert constructor parameters
    assert(m_renderer != nullptr && "CMetalShaderManager: Renderer cannot be null");
    assert(m_textureManager != nullptr && "CMetalShaderManager: TextureManager cannot be null");
    assert(m_nextShaderId > 0 && "CMetalShaderManager: NextShaderId must be positive");
    assert(m_currentShaderId == -1 && "CMetalShaderManager: CurrentShaderId should be -1 initially");
    
    printf("CMetalShaderManager: Constructor called with renderer=%p, textureManager=%p\n", m_renderer, m_textureManager);
    
    // Initialize additional members
    m_heatVisionEnabled = false;
    
    printf("CMetalShaderManager: Constructor completed successfully\n");
}

CMetalShaderManager::~CMetalShaderManager()
{
    printf("CMetalShaderManager: Destructor called\n");
    
    // Assert state before cleanup
    assert(m_renderer != nullptr && "CMetalShaderManager: Renderer should not be null in destructor");
    assert(m_textureManager != nullptr && "CMetalShaderManager: TextureManager should not be null in destructor");
    
    ClearAllShaders();
    
    printf("CMetalShaderManager: Destructor completed\n");
}

// Shader System Interface (EF_ methods)
bool CMetalShaderManager::EF_PrecacheResource(IShader* pSH, float fDist, float fTimeToReady, int Flags)
{
    if (!pSH)
        return false;
        
    // Precache shader resources
    return true;
}

bool CMetalShaderManager::EF_PrecacheResource(ITexPic* pTP, float fDist, float fTimeToReady, int Flags)
{
    if (!pTP)
        return false;
        
    // Precache texture resources
    return true;
}

bool CMetalShaderManager::EF_PrecacheResource(CLeafBuffer* pPB, float fDist, float fTimeToReady, int Flags)
{
    if (!pPB)
        return false;
        
    // Precache geometry resources
    return true;
}

bool CMetalShaderManager::EF_PrecacheResource(CDLight* pLS, float fDist, float fTimeToReady, int Flags)
{
    if (!pLS)
        return false;
        
    // Precache light resources
    return true;
}

void CMetalShaderManager::EF_EnableHeatVision(bool bEnable)
{
    m_heatVisionEnabled = bEnable;
}

bool CMetalShaderManager::EF_GetHeatVision()
{
    return m_heatVisionEnabled;
}

void CMetalShaderManager::EF_PolygonOffset(bool bEnable, float fFactor, float fUnits)
{
    // Set polygon offset for Metal
    // This would be handled by the Metal render pipeline state
}

void CMetalShaderManager::EF_AddPolyToScene3D(int Ef, int numPts, SColorVert* verts, CCObject* obj, int nFogID)
{
    // Add 3D polygon to scene
    // This would queue the polygon for rendering
}

CCObject* CMetalShaderManager::EF_AddSpriteToScene(int Ef, int numPts, SColorVert* verts, CCObject* obj, byte* inds, int ninds, int nFogID)
{
    // Add sprite to scene
    // This would create and return a CCObject for the sprite
    return nullptr;
}

void CMetalShaderManager::EF_AddPolyToScene2D(int Ef, int numPts, SColorVert2D* verts)
{
    // Add 2D polygon to scene
    // This would queue the 2D polygon for rendering
}

void CMetalShaderManager::EF_AddPolyToScene2D(SShaderItem si, int nTempl, int numPts, SColorVert2D* verts)
{
    // Add 2D polygon to scene with shader item
    // This would queue the 2D polygon for rendering with specific shader
}

// Shader Management
IShader* CMetalShaderManager::EF_LoadShader(const char* name, EShClass Class, int flags, uint64 nMaskGen)
{
    if (!name)
        return nullptr;
        
    // Check if shader is already loaded
    std::string nameStr(name);
    auto nameIt = m_shaderNameMap.find(nameStr);
    if (nameIt != m_shaderNameMap.end())
    {
        auto shaderIt = m_shaders.find(nameIt->second);
        if (shaderIt != m_shaders.end())
        {
            // Return existing shader interface
            return nullptr; // Would need to implement IShader interface
        }
    }
    
    // Load shader from file
    std::string source;
    if (!LoadShaderFromFile(name, source))
    {
        printf("Error: Failed to load shader: %s", name);
        return nullptr;
    }
    
    // Compile shader
    id<MTLFunction> vertexFunction = nil;
    id<MTLFunction> fragmentFunction = nil;
    
    if (!CompileShader(source, vertexFunction) || !CompileShader(source, fragmentFunction))
    {
        printf("Error: Failed to compile shader: %s", name);
        return nullptr;
    }
    
    // Create pipeline state
    id<MTLRenderPipelineState> pipelineState = CreatePipelineState(vertexFunction, fragmentFunction, nil);
    if (!pipelineState)
    {
        printf("Error: Failed to create pipeline state for shader: %s", name);
        return nullptr;
    }
    
    // Store shader
    int shaderId = AllocateShaderId();
    if (shaderId == -1)
        return nullptr;
        
    ShaderInfo info;
    info.vertexFunction = vertexFunction;
    info.fragmentFunction = fragmentFunction;
    info.pipelineState = pipelineState;
    info.name = name;
    info.shaderClass = Class;
    info.isLoaded = true;
    
    m_shaders[shaderId] = info;
    m_shaderNameMap[nameStr] = shaderId;
    
    return nullptr; // Would need to implement IShader interface
}

SShaderItem CMetalShaderManager::EF_LoadShaderItem(const char* name, EShClass Class, bool bShare, const char* templName, int flags, SInputShaderResources* Res, uint64 nMaskGen)
{
    // Load shader item
    SShaderItem item;
    // Initialize shader item
    return item;
}

bool CMetalShaderManager::EF_ReloadFile(const char* szFileName)
{
    if (!szFileName)
        return false;
        
    // Reload shader file
    return true;
}

void CMetalShaderManager::EF_ReloadShaderFiles(int nCategory)
{
    // Reload all shader files in category
}

void CMetalShaderManager::EF_ReloadTextures()
{
    // Reload all textures
}

IShader* CMetalShaderManager::EF_CopyShader(IShader* ef)
{
    if (!ef)
        return nullptr;
        
    // Copy shader
    return nullptr;
}

char** CMetalShaderManager::EF_GetShadersForFile(const char* File, int num)
{
    if (!File)
        return nullptr;
        
    // Get shaders for file
    return nullptr;
}

SLightMaterial* CMetalShaderManager::EF_GetLightMaterial(char* Str)
{
    if (!Str)
        return nullptr;
        
    // Get light material
    return nullptr;
}

bool CMetalShaderManager::EF_RegisterTemplate(int nTemplId, char* Name, bool bReplace)
{
    if (!Name)
        return false;
        
    // Register shader template
    return true;
}

void CMetalShaderManager::EF_AddSplash(Vec3 Pos, eSplashType eST, float fForce, int Id)
{
    // Add splash effect
}

bool CMetalShaderManager::EF_HideTemplate(const char* name)
{
    if (!name)
        return false;
        
    // Hide shader template
    return true;
}

bool CMetalShaderManager::EF_UnhideTemplate(const char* name)
{
    if (!name)
        return false;
        
    // Unhide shader template
    return true;
}

bool CMetalShaderManager::EF_UnhideAllTemplates()
{
    // Unhide all shader templates
    return true;
}

bool CMetalShaderManager::EF_SetLightHole(Vec3 vPos, Vec3 vNormal, int idTex, float fScale, bool bAdditive)
{
    // Set light hole
    return true;
}

CRendElement* CMetalShaderManager::EF_CreateRE(EDataType edt)
{
    // Assert input validation
    assert(static_cast<int>(edt) >= 0 && "CMetalShaderManager::EF_CreateRE: Invalid negative EDataType");
    assert(static_cast<int>(edt) < 100 && "CMetalShaderManager::EF_CreateRE: EDataType value too large");
    
    printf("CMetalShaderManager::EF_CreateRE: Creating render element type %d (%s)\n", 
           (int)edt, GetRenderElementTypeName(edt));
    
    CRendElement* re = nullptr;
    
    try {
        switch(edt)
        {
            case eDATA_Sky:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalRESky for sky rendering\n");
                re = new CMetalRESky;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalRESky creation failed");
                // Initialize sky-specific properties
                re->m_SortId = -1000; // Sky renders first
                re->m_Color = CFColor(0.5f, 0.7f, 1.0f, 1.0f); // Light blue
                break;
                
            case eDATA_Dummy:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalREDummy\n");
                re = new CMetalREDummy;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalREDummy creation failed");
                break;
                
            case eDATA_2DQuad:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalRE2DQuad\n");
                re = new CMetalRE2DQuad;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalRE2DQuad creation failed");
                break;
                
            case eDATA_ScreenProcess:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalREScreenProcess\n");
                re = new CMetalREScreenProcess;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalREScreenProcess creation failed");
                break;
                
            case eDATA_ShadowMapGen:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalREShadowMapGen\n");
                re = new CMetalREShadowMapGen;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalREShadowMapGen creation failed");
                break;
                
            case eDATA_TerrainSector:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalRECommon\n");
                re = new CMetalRECommon;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalRECommon creation failed");
                break;
                
            case eDATA_TriMeshShadow:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalRETriMeshShadow\n");
                re = new CMetalRETriMeshShadow;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalRETriMeshShadow creation failed");
                break;
                
            case eDATA_FlashBang:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalREFlashBang\n");
                re = new CMetalREFlashBang;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalREFlashBang creation failed");
                break;
                
            case eDATA_OcclusionQuery:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalREOcclusionQuery\n");
                re = new CMetalREOcclusionQuery;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalREOcclusionQuery creation failed");
                break;
                
            case eDATA_OcLeaf:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalREOcLeaf\n");
                re = new CMetalREOcLeaf;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalREOcLeaf creation failed");
                break;
                
            case eDATA_TerrainParticles:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalRETerrainParticles\n");
                re = new CMetalRETerrainParticles;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalRETerrainParticles creation failed");
                break;
                
            case eDATA_FarTreeSprites:
                printf("CMetalShaderManager::EF_CreateRE: Creating CMetalREFarTreeSprites\n");
                re = new CMetalREFarTreeSprites;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalREFarTreeSprites creation failed");
                break;
                
            case eDATA_Ocean:
            case eDATA_Beam:
            case eDATA_Glare:
            case eDATA_Prefab:
            case eDATA_HDRProcess:
                printf("CMetalShaderManager::EF_CreateRE: Unsupported render element type %d, using dummy\n", (int)edt);
                re = new CMetalREDummy;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalREDummy fallback creation failed");
                break;
                
            default:
                printf("CMetalShaderManager::EF_CreateRE: Unknown render element type %d, using dummy\n", (int)edt);
                re = new CMetalREDummy;
                assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: CMetalREDummy fallback creation failed");
                break;
        }
    }
    catch (const std::exception& e) {
        std::cerr << "CMetalShaderManager::EF_CreateRE: Exception creating render element type " << (int)edt << ": " << e.what() << std::endl;
        assert(false && "CMetalShaderManager::EF_CreateRE: Exception during render element creation");
        re = nullptr;
    }
    catch (...) {
        std::cerr << "CMetalShaderManager::EF_CreateRE: Unknown exception creating render element type " << (int)edt << std::endl;
        assert(false && "CMetalShaderManager::EF_CreateRE: Unknown exception during render element creation");
        re = nullptr;
    }
    
    // Final validation
    assert(re != nullptr && "CMetalShaderManager::EF_CreateRE: Final render element validation failed");
    assert(re->m_Type == edt && "CMetalShaderManager::EF_CreateRE: Render element type mismatch");
    
    printf("CMetalShaderManager::EF_CreateRE: Successfully created render element type %d at %p\n", (int)edt, re);
    
    return re;
}

void CMetalShaderManager::EF_StartEf()
{
    // Start shader effects
}

CCObject* CMetalShaderManager::EF_GetObject(bool bTemp, int num)
{
    // Get CCObject for rendering
    return nullptr;
}

void CMetalShaderManager::EF_AddEf(int NumFog, CRendElement* re, IShader* ef, SRenderShaderResources* sr, CCObject* obj, int nTempl, IShader* efState, int nSort)
{
    // Add shader effect to render list
}

void CMetalShaderManager::EF_EndEf3D(int nFlags)
{
    // End 3D shader effects
}

bool CMetalShaderManager::EF_IsFakeDLight(CDLight* Source)
{
    if (!Source)
        return false;
        
    // Check if light is fake
    return false;
}

void CMetalShaderManager::EF_ADDDlight(CDLight* Source)
{
    if (!Source)
        return;
        
    // Add dynamic light
}

void CMetalShaderManager::EF_ClearLightsList()
{
    // Clear dynamic lights list
}

bool CMetalShaderManager::EF_UpdateDLight(CDLight* pDL)
{
    if (!pDL)
        return false;
        
    // Update dynamic light
    return true;
}

void CMetalShaderManager::EF_EndEf2D(bool bSort)
{
    // End 2D shader effects
}

bool CMetalShaderManager::EF_DrawEfForName(char* name, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    if (!name)
        return false;
        
    // Draw shader effect by name
    return true;
}

bool CMetalShaderManager::EF_DrawEfForNum(int num, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    // Draw shader effect by number
    return true;
}

bool CMetalShaderManager::EF_DrawEf(IShader* ef, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    if (!ef)
        return false;
        
    // Draw shader effect
    return true;
}

bool CMetalShaderManager::EF_DrawEf(SShaderItem si, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    // Draw shader effect with shader item
    return true;
}

bool CMetalShaderManager::EF_DrawPartialEfForName(char* name, SVrect* vr, SVrect* pr, CFColor& col)
{
    if (!name)
        return false;
        
    // Draw partial shader effect by name
    return true;
}

bool CMetalShaderManager::EF_DrawPartialEfForNum(int num, SVrect* vr, SVrect* pr, CFColor& col)
{
    // Draw partial shader effect by number
    return true;
}

bool CMetalShaderManager::EF_DrawPartialEf(IShader* ef, SVrect* vr, SVrect* pr, CFColor& col, float iwdt, float ihgt)
{
    if (!ef)
        return false;
        
    // Draw partial shader effect
    return true;
}

void* CMetalShaderManager::EF_Query(int Query, int Param)
{
    // Query shader system
    return nullptr;
}

void CMetalShaderManager::EF_ConstructEf(IShader* Ef)
{
    if (!Ef)
        return;
        
    // Construct shader effect
}

void CMetalShaderManager::EF_SetWorldColor(float r, float g, float b, float a)
{
    // Set world color for shaders
}

int CMetalShaderManager::EF_RegisterFogVolume(float fMaxFogDist, float fFogLayerZ, CFColor color, int nIndex, bool bCaustics)
{
    // Register fog volume
    return 0;
}

// LeafBuffer Management
CLeafBuffer* CMetalShaderManager::CreateLeafBuffer(bool bDynamic, const char* szSource, class CIndexedMesh* pIndexedMesh)
{
    if (!szSource)
        return nullptr;
        
    // Create leaf buffer
    return nullptr;
}

CLeafBuffer* CMetalShaderManager::CreateLeafBufferInitialized(void* pVertBuffer, int nVertCount, int nVertFormat, ushort* pIndices, int nIndices, int nPrimetiveType, const char* szSource, EBufferType eBufType, int nMatInfoCount, int nClientTextureBindID, bool (*PrepareBufferCallback)(CLeafBuffer*, bool), void* CustomData, bool bOnlyVideoBuffer, bool bPrecache)
{
    if (!pVertBuffer || !szSource)
        return nullptr;
        
    // Create initialized leaf buffer
    return nullptr;
}

void CMetalShaderManager::DeleteLeafBuffer(CLeafBuffer* pLBuffer)
{
    if (!pLBuffer)
        return;
        
    // Delete leaf buffer
}

// Utility methods
void CMetalShaderManager::ClearAllShaders()
{
    m_shaders.clear();
    m_shaderNameMap.clear();
    m_nextShaderId = 1;
}

int CMetalShaderManager::GetShaderCount() const
{
    return (int)m_shaders.size();
}

void CMetalShaderManager::SetGlobalShaderTemplateId(int nTemplateId)
{
    m_globalShaderTemplateId = nTemplateId;
}

int CMetalShaderManager::GetGlobalShaderTemplateId()
{
    return m_globalShaderTemplateId;
}

// Protected methods
id<MTLFunction> CMetalShaderManager::LoadMetalShader(const char* name, const char* source)
{
    if (!m_renderer || !m_renderer->m_device || !source)
        return nil;
        
    NSError* error = nil;
    id<MTLLibrary> library = [m_renderer->m_device newLibraryWithSource:@(source) options:nil error:&error];
    if (!library)
    {
        printf("Error: Failed to create Metal library: %s\n", error ? [[error localizedDescription] UTF8String] : "Unknown error");
        return nil;
    }
    
    id<MTLFunction> function = [library newFunctionWithName:@(name)];
    return function;
}

id<MTLRenderPipelineState> CMetalShaderManager::CreatePipelineState(id<MTLFunction> vertexFunction, 
                                                                     id<MTLFunction> fragmentFunction,
                                                                     MTLVertexDescriptor* vertexDescriptor)
{
    if (!m_renderer || !m_renderer->m_device)
        return nil;
        
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.vertexDescriptor = vertexDescriptor;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    
    NSError* error = nil;
    id<MTLRenderPipelineState> pipelineState = [m_renderer->m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!pipelineState)
    {
        printf("Error: Failed to create Metal render pipeline state: %s", error ? [[error localizedDescription] UTF8String] : "Unknown error");
        return nil;
    }
    
    return pipelineState;
}

void CMetalShaderManager::SetShaderUniforms(id<MTLRenderCommandEncoder> encoder, const SShaderParam& params)
{
    if (!encoder)
        return;
        
    // Set shader uniforms
}

int CMetalShaderManager::AllocateShaderId()
{
    return m_nextShaderId++;
}

void CMetalShaderManager::ReleaseShaderId(int id)
{
    // Release shader ID for reuse
}

bool CMetalShaderManager::LoadShaderFromFile(const char* filename, std::string& source)
{
    if (!filename)
        return false;
        
    // Try to load shader source from file
    // For now, we'll create a basic Metal shader template
    // In a real implementation, this would load from .metal files or other formats
    
    std::string shaderName = filename;
    if (shaderName.find(".metal") == std::string::npos)
    {
        shaderName += ".metal";
    }
    
    // Create a basic Metal shader template
    source = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float2 texCoord;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]])
{
    VertexOut out;
    out.position = float4(in.position, 1.0);
    out.normal = in.normal;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                             texture2d<float> baseTexture [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float4 color = baseTexture.sample(textureSampler, in.texCoord);
    return color;
}
)";
    
    return true;
}

bool CMetalShaderManager::CompileShader(const std::string& source, id<MTLFunction>& function)
{
    if (!m_renderer || !m_renderer->m_device)
        return false;
        
    NSError* error = nil;
    id<MTLLibrary> library = [m_renderer->m_device newLibraryWithSource:@(source.c_str()) options:nil error:&error];
    if (!library)
    {
        printf("Error: Failed to create Metal library: %s\n", error ? [[error localizedDescription] UTF8String] : "Unknown error");
        return false;
    }
    
    // Get the main function
    function = [library newFunctionWithName:@"main"];
    return function != nil;
}

void CMetalShaderManager::SetShaderParameters(id<MTLRenderCommandEncoder> encoder, IShader* shader)
{
    if (!encoder || !shader)
        return;
        
    // Set shader parameters
}

void CMetalShaderManager::BindShaderTextures(id<MTLRenderCommandEncoder> encoder, IShader* shader)
{
    if (!encoder || !shader)
        return;
        
    // Bind shader textures
}

#endif // __APPLE__ && __MACH__
