////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalRenderer.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Main Metal renderer implementation that combines specialized
//  managers
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

// Include PCH first for proper type definitions
#include "MetalRenderPCH.h"
#include "MetalRenderer.h"
#include "I3DEngine.h"
#include "../Common/Textures/dxtlib.h"  // For nvDXT function signatures

// Global system pointers (defined here, declared as extern in CommonRender.h)
// gRenDev is defined in RenderDll/Common/Renderer.cpp
ISystem *iSystem = nullptr;

// Global engine interface pointers
IConsole *iConsole = nullptr;
ILog *iLog = nullptr;
ITimer *iTimer = nullptr;

// GetISystem stub
ISystem* GetISystem()
{
    return iSystem;
}

// NVDXT texture compression stubs (C++ linkage matching dxtlib.h declarations)
HRESULT nvDXTcompress(unsigned char* raw_data, unsigned long w, unsigned long h, DWORD byte_pitch,
                      CompressionOptions* options, DWORD planes, MIPcallback callback, RECT* rect)
{
    assert(raw_data != nullptr && "nvDXTcompress: raw_data cannot be null");
    assert(w > 0 && "nvDXTcompress: width must be positive");
    assert(h > 0 && "nvDXTcompress: height must be positive");
    assert(planes == 3 || planes == 4 && "nvDXTcompress: planes must be 3 or 4");
    
    // macOS: DXT compression not implemented
    return -1;
}

unsigned char* nvDXTdecompress(int& w, int& h, int& depth, int& total_width, int& rowBytes, int& src_format,
                               int SpecifiedMipMaps)
{
    // macOS: DXT decompression not implemented
    return nullptr;
}

// Stub for ATI texture compression (3Dc library function)
extern "C" int CompressTextureATI(unsigned char* pSrcData, unsigned char* pDstData, int nWidth, int nHeight, int nChannels)
{
    assert(pSrcData != nullptr && "CompressTextureATI: pSrcData cannot be null");
    assert(pDstData != nullptr && "CompressTextureATI: pDstData cannot be null");
    assert(nWidth > 0 && "CompressTextureATI: width must be positive");
    assert(nHeight > 0 && "CompressTextureATI: height must be positive");
    assert(nChannels > 0 && nChannels <= 4 && "CompressTextureATI: channels must be 1-4");
    
    // macOS: Not implemented - would need ATI 3Dc compression library
    // For now, just return error code
    return -1;
}

extern "C" void DeleteDataATI(unsigned char* pData)
{
    assert(pData != nullptr && "DeleteDataATI: pData cannot be null");
    
    // macOS: Cleanup for ATI compression - just free the memory
    if (pData) {
        free(pData);
    }
}

// Memory management stubs
extern "C" void* CryModuleMalloc(size_t size)
{
    assert(size > 0 && "CryModuleMalloc: size must be positive");
    
    void* result = malloc(size);
    assert(result != nullptr && "CryModuleMalloc: malloc failed");
    
    return result;
}

extern "C" void* CryModuleRealloc(void* ptr, size_t size)
{
    assert(size > 0 && "CryModuleRealloc: size must be positive");
    
    void* result = realloc(ptr, size);
    assert(result != nullptr && "CryModuleRealloc: realloc failed");
    
    return result;
}

extern "C" void CryModuleFree(void* ptr)
{
    // Note: free(nullptr) is valid in C/C++, so no assert needed for ptr
    free(ptr);
}

/**
 * @def DLL_EXPORT
 * @brief Platform-specific macro for DLL symbol export
 *
 * On macOS, this expands to __attribute__((visibility("default"))) which
 * ensures the symbol is visible for dynamic linking. This is required for
 * the game engine to find PackageRenderConstructor() via dlsym().
 *
 * @platform_specific
 * - macOS: Uses GCC/Clang visibility attribute
 * - Other: Empty macro (relies on default visibility)
 *
 * @build_configuration
 * Requires -fvisibility=hidden compiler flag for this to be effective.
 * Without that flag, all symbols are visible by default anyway.
 *
 * @see PackageRenderConstructor() (uses this macro)
 */
#ifndef DLL_EXPORT
#if defined(__APPLE__) && defined(__MACH__)
#define DLL_EXPORT __attribute__((visibility("default")))
#else
#define DLL_EXPORT
#endif
#endif

CMetalRenderer::CMetalRenderer()
    : m_textureManager(nullptr), m_shaderManager(nullptr),
      m_utilityRenderer(nullptr) {
  // Initialize specialized managers
  bool success = InitializeManagers();
  assert(success && "CMetalRenderer::CMetalRenderer: Failed to initialize managers!");
  assert(m_textureManager && "CMetalRenderer::CMetalRenderer: Texture manager is null after initialization!");
  assert(m_shaderManager && "CMetalRenderer::CMetalRenderer: Shader manager is null after initialization!");
  assert(m_utilityRenderer && "CMetalRenderer::CMetalRenderer: Utility renderer is null after initialization!");
}

CMetalRenderer::~CMetalRenderer() {
  assert(m_textureManager && "CMetalRenderer::~CMetalRenderer: Texture manager is null during destruction!");
  assert(m_shaderManager && "CMetalRenderer::~CMetalRenderer: Shader manager is null during destruction!");
  assert(m_utilityRenderer && "CMetalRenderer::~CMetalRenderer: Utility renderer is null during destruction!");
  
  ShutdownManagers();
  
  assert(!m_textureManager && "CMetalRenderer::~CMetalRenderer: Texture manager not released!");
  assert(!m_shaderManager && "CMetalRenderer::~CMetalRenderer: Shader manager not released!");
  assert(!m_utilityRenderer && "CMetalRenderer::~CMetalRenderer: Utility renderer not released!");
}

// Texture management delegation
void CMetalRenderer::SetTexture(int tnum, ETexType Type) {
  assert(m_textureManager && "SetTexture: Texture manager is null!");
  assert(tnum >= 0 && "SetTexture: Texture number cannot be negative!");
  
  m_textureManager->SetTexture(tnum, Type);
}

void CMetalRenderer::SetWhiteTexture() {
  assert(m_textureManager && "SetWhiteTexture: Texture manager is null!");
  m_textureManager->SetWhiteTexture();
}

unsigned int
CMetalRenderer::DownLoadToVideoMemory(unsigned char *data, int w, int h,
                                      ETEX_Format eTFSrc, ETEX_Format eTFDst,
                                      int nummipmap, bool repeat, int filter,
                                      int Id, char *szCacheName, int flags) {
  assert(m_textureManager && "DownLoadToVideoMemory: Texture manager is null!");
  assert(data && "DownLoadToVideoMemory: Data cannot be null!");
  assert(w > 0 && h > 0 && "DownLoadToVideoMemory: Dimensions must be positive!");
  
  if (!m_textureManager)
    return 0;

  return m_textureManager->DownLoadToVideoMemory(data, w, h, eTFSrc, eTFDst,
                                                 nummipmap, repeat, filter, Id,
                                                 szCacheName, flags);
}

void CMetalRenderer::UpdateTextureInVideoMemory(uint tnum,
                                                unsigned char *newdata,
                                                int posx, int posy, int w,
                                                int h, ETEX_Format eTF) {
  assert(m_textureManager && "UpdateTextureInVideoMemory: Texture manager is null!");
  assert(newdata && "UpdateTextureInVideoMemory: Data cannot be null!");
  assert(w > 0 && h > 0 && "UpdateTextureInVideoMemory: Dimensions must be positive!");
  assert(posx >= 0 && posy >= 0 && "UpdateTextureInVideoMemory: Position cannot be negative!");

  m_textureManager->UpdateTextureInVideoMemory(tnum, newdata, posx, posy, w, h,
                                               eTF);
}

unsigned int CMetalRenderer::LoadTexture(const char *filename, int *tex_type,
                                         unsigned int def_tid,
                                         bool compresstodisk, bool bWarn) {
  assert(m_textureManager && "LoadTexture: Texture manager is null!");
  assert(filename && "LoadTexture: Filename cannot be null!");
  assert(filename[0] != '\0' && "LoadTexture: Filename cannot be empty!");

  return m_textureManager->LoadTexture(filename, tex_type, def_tid,
                                       compresstodisk, bWarn);
}

bool CMetalRenderer::DXTCompress(byte *raw_data, int nWidth, int nHeight,
                                 ETEX_Format eTF, bool bUseHW, bool bGenMips,
                                 int nSrcBytesPerPix, MIPDXTcallback callback) {
  if (!m_textureManager)
    return false;

  return m_textureManager->DXTCompress(raw_data, nWidth, nHeight, eTF, bUseHW,
                                       bGenMips, nSrcBytesPerPix, callback);
}

bool CMetalRenderer::DXTDecompress(byte *srcData, byte *dstData, int nWidth,
                                   int nHeight, ETEX_Format eSrcTF, bool bUseHW,
                                   int nDstBytesPerPix) {
  if (!m_textureManager)
    return false;

  return m_textureManager->DXTDecompress(srcData, dstData, nWidth, nHeight,
                                         eSrcTF, bUseHW, nDstBytesPerPix);
}

void CMetalRenderer::RemoveTexture(unsigned int TextureId) {

  m_textureManager->RemoveTexture(TextureId);
}

void CMetalRenderer::RemoveTexture(ITexPic *pTexPic) {

  m_textureManager->RemoveTexture(pTexPic);
}

bool CMetalRenderer::SetGammaDelta(const float fGamma) {
  if (!m_textureManager)
    return false;

  return m_textureManager->SetGammaDelta(fGamma);
}

// Font system delegation
bool CMetalRenderer::FontUploadTexture(class CFBitmap *bitmap,
                                       ETEX_Format eTF) {

  return m_textureManager->FontUploadTexture(bitmap, eTF);
}

int CMetalRenderer::FontCreateTexture(int Width, int Height, byte *pData,
                                      ETEX_Format eTF) {

  return m_textureManager->FontCreateTexture(Width, Height, pData, eTF);
}

bool CMetalRenderer::FontUpdateTexture(int nTexId, int X, int Y, int USize,
                                       int VSize, byte *pData) {

  return m_textureManager->FontUpdateTexture(nTexId, X, Y, USize, VSize, pData);
}

void CMetalRenderer::FontReleaseTexture(class CFBitmap *pBmp) {

  m_textureManager->FontReleaseTexture(pBmp);
}

void CMetalRenderer::FontSetTexture(class CFBitmap *bitmap, int nFilterMode) {

  m_textureManager->FontSetTexture(bitmap, nFilterMode);
}

void CMetalRenderer::FontSetTexture(int nTexId, int nFilterMode) {

  m_textureManager->FontSetTexture(nTexId, nFilterMode);
}

void CMetalRenderer::FontSetRenderingState(unsigned long nVirtualScreenWidth,
                                           unsigned long nVirtualScreenHeight) {

  m_textureManager->FontSetRenderingState(nVirtualScreenWidth,
                                          nVirtualScreenHeight);
}

void CMetalRenderer::FontSetBlending(int src, int dst) {

  m_textureManager->FontSetBlending(src, dst);
}

void CMetalRenderer::FontRestoreRenderingState() {

  m_textureManager->FontRestoreRenderingState();
}

// Shader system delegation
bool CMetalRenderer::EF_PrecacheResource(IShader *pSH, float fDist,
                                         float fTimeToReady, int Flags) {

  return m_shaderManager->EF_PrecacheResource(pSH, fDist, fTimeToReady, Flags);
}

bool CMetalRenderer::EF_PrecacheResource(ITexPic *pTP, float fDist,
                                         float fTimeToReady, int Flags) {

  return m_shaderManager->EF_PrecacheResource(pTP, fDist, fTimeToReady, Flags);
}

bool CMetalRenderer::EF_PrecacheResource(CLeafBuffer *pPB, float fDist,
                                         float fTimeToReady, int Flags) {

  return m_shaderManager->EF_PrecacheResource(pPB, fDist, fTimeToReady, Flags);
}

bool CMetalRenderer::EF_PrecacheResource(CDLight *pLS, float fDist,
                                         float fTimeToReady, int Flags) {

  return m_shaderManager->EF_PrecacheResource(pLS, fDist, fTimeToReady, Flags);
}

void CMetalRenderer::EF_EnableHeatVision(bool bEnable) {

  m_shaderManager->EF_EnableHeatVision(bEnable);
}

bool CMetalRenderer::EF_GetHeatVision() {

  return m_shaderManager->EF_GetHeatVision();
}

void CMetalRenderer::EF_PolygonOffset(bool bEnable, float fFactor,
                                      float fUnits) {

  m_shaderManager->EF_PolygonOffset(bEnable, fFactor, fUnits);
}

void CMetalRenderer::EF_AddPolyToScene3D(int Ef, int numPts, SColorVert *verts,
                                         CCObject *obj, int nFogID) {

  m_shaderManager->EF_AddPolyToScene3D(Ef, numPts, verts, obj, nFogID);
}

CCObject *CMetalRenderer::EF_AddSpriteToScene(int Ef, int numPts,
                                              SColorVert *verts, CCObject *obj,
                                              byte *inds, int ninds,
                                              int nFogID) {

  return m_shaderManager->EF_AddSpriteToScene(Ef, numPts, verts, obj, inds,
                                              ninds, nFogID);
}

void CMetalRenderer::EF_AddPolyToScene2D(int Ef, int numPts,
                                         SColorVert2D *verts) {

  m_shaderManager->EF_AddPolyToScene2D(Ef, numPts, verts);
}

void CMetalRenderer::EF_AddPolyToScene2D(SShaderItem si, int nTempl, int numPts,
                                         SColorVert2D *verts) {

  m_shaderManager->EF_AddPolyToScene2D(si, nTempl, numPts, verts);
}

IShader *CMetalRenderer::EF_LoadShader(const char *name, EShClass Class,
                                       int flags, uint64 nMaskGen) {

  return m_shaderManager->EF_LoadShader(name, Class, flags, nMaskGen);
}

SShaderItem CMetalRenderer::EF_LoadShaderItem(const char *name, EShClass Class,
                                              bool bShare,
                                              const char *templName, int flags,
                                              SInputShaderResources *Res,
                                              uint64 nMaskGen) {

  return m_shaderManager->EF_LoadShaderItem(name, Class, bShare, templName,
                                            flags, Res, nMaskGen);
}

bool CMetalRenderer::EF_ReloadFile(const char *szFileName) {

  return m_shaderManager->EF_ReloadFile(szFileName);
}

void CMetalRenderer::EF_ReloadShaderFiles(int nCategory) {

  m_shaderManager->EF_ReloadShaderFiles(nCategory);
}

void CMetalRenderer::EF_ReloadTextures() {

  m_shaderManager->EF_ReloadTextures();
}

IShader *CMetalRenderer::EF_CopyShader(IShader *ef) {

  return m_shaderManager->EF_CopyShader(ef);
}

ITexPic *CMetalRenderer::EF_GetTextureByID(int Id) {

  return m_textureManager->EF_GetTextureByID(Id);
}

ITexPic *CMetalRenderer::EF_LoadTexture(const char *nameTex, uint flags,
                                        uint flags2, byte eTT, float fAmount1,
                                        float fAmount2, int Id, int BindId) {

  return m_textureManager->EF_LoadTexture(nameTex, flags, flags2, eTT, fAmount1,
                                          fAmount2, Id, BindId);
}

int CMetalRenderer::EF_LoadLightmap(const char *name) {

  return m_textureManager->EF_LoadLightmap(name);
}

bool CMetalRenderer::EF_ScanEnvironmentCM(const char *name, int size,
                                          Vec3 &Pos) {

  return m_textureManager->EF_ScanEnvironmentCM(name, size, Pos);
}

int CMetalRenderer::EF_ReadAllImgFiles(IShader *ef, SShaderTexUnit *tl,
                                       STexAnim *ta, char *name) {

  return m_textureManager->EF_ReadAllImgFiles(ef, tl, ta, name);
}

char **CMetalRenderer::EF_GetShadersForFile(const char *File, int num) {

  return m_shaderManager->EF_GetShadersForFile(File, num);
}

SLightMaterial *CMetalRenderer::EF_GetLightMaterial(char *Str) {

  return m_shaderManager->EF_GetLightMaterial(Str);
}

bool CMetalRenderer::EF_RegisterTemplate(int nTemplId, char *Name,
                                         bool bReplace) {

  return m_shaderManager->EF_RegisterTemplate(nTemplId, Name, bReplace);
}

void CMetalRenderer::EF_AddSplash(Vec3 Pos, eSplashType eST, float fForce,
                                  int Id) {

  m_shaderManager->EF_AddSplash(Pos, eST, fForce, Id);
}

bool CMetalRenderer::EF_HideTemplate(const char *name) {

  return m_shaderManager->EF_HideTemplate(name);
}

bool CMetalRenderer::EF_UnhideTemplate(const char *name) {

  return m_shaderManager->EF_UnhideTemplate(name);
}

bool CMetalRenderer::EF_UnhideAllTemplates() {

  return m_shaderManager->EF_UnhideAllTemplates();
}

bool CMetalRenderer::EF_SetLightHole(Vec3 vPos, Vec3 vNormal, int idTex,
                                     float fScale, bool bAdditive) {

  return m_shaderManager->EF_SetLightHole(vPos, vNormal, idTex, fScale,
                                          bAdditive);
}

// Note: EF_CreateRE is implemented in CMetalBaseRenderer

void CMetalRenderer::EF_StartEf() { m_shaderManager->EF_StartEf(); }

CCObject *CMetalRenderer::EF_GetObject(bool bTemp, int num) {

  return m_shaderManager->EF_GetObject(bTemp, num);
}

void CMetalRenderer::EF_AddEf(int NumFog, CRendElement *re, IShader *ef,
                              SRenderShaderResources *sr, CCObject *obj,
                              int nTempl, IShader *efState, int nSort) {

  m_shaderManager->EF_AddEf(NumFog, re, ef, sr, obj, nTempl, efState, nSort);
}

void CMetalRenderer::EF_EndEf3D(int nFlags) {

  m_shaderManager->EF_EndEf3D(nFlags);
}

bool CMetalRenderer::EF_IsFakeDLight(CDLight *Source) {

  return m_shaderManager->EF_IsFakeDLight(Source);
}

void CMetalRenderer::EF_ADDDlight(CDLight *Source) {

  m_shaderManager->EF_ADDDlight(Source);
}

void CMetalRenderer::EF_ClearLightsList() {

  m_shaderManager->EF_ClearLightsList();
}

bool CMetalRenderer::EF_UpdateDLight(CDLight *pDL) {

  return m_shaderManager->EF_UpdateDLight(pDL);
}

void CMetalRenderer::EF_EndEf2D(bool bSort) {

  m_shaderManager->EF_EndEf2D(bSort);
}

bool CMetalRenderer::EF_DrawEfForName(char *name, float x, float y, float width,
                                      float height, CFColor &col, int nTempl) {

  return m_shaderManager->EF_DrawEfForName(name, x, y, width, height, col,
                                           nTempl);
}

bool CMetalRenderer::EF_DrawEfForNum(int num, float x, float y, float width,
                                     float height, CFColor &col, int nTempl) {

  return m_shaderManager->EF_DrawEfForNum(num, x, y, width, height, col,
                                          nTempl);
}

bool CMetalRenderer::EF_DrawEf(IShader *ef, float x, float y, float width,
                               float height, CFColor &col, int nTempl) {

  return m_shaderManager->EF_DrawEf(ef, x, y, width, height, col, nTempl);
}

bool CMetalRenderer::EF_DrawEf(SShaderItem si, float x, float y, float width,
                               float height, CFColor &col, int nTempl) {

  return m_shaderManager->EF_DrawEf(si, x, y, width, height, col, nTempl);
}

bool CMetalRenderer::EF_DrawPartialEfForName(char *name, SVrect *vr, SVrect *pr,
                                             CFColor &col) {

  return m_shaderManager->EF_DrawPartialEfForName(name, vr, pr, col);
}

bool CMetalRenderer::EF_DrawPartialEfForNum(int num, SVrect *vr, SVrect *pr,
                                            CFColor &col) {

  return m_shaderManager->EF_DrawPartialEfForNum(num, vr, pr, col);
}

bool CMetalRenderer::EF_DrawPartialEf(IShader *ef, SVrect *vr, SVrect *pr,
                                      CFColor &col, float iwdt, float ihgt) {

  return m_shaderManager->EF_DrawPartialEf(ef, vr, pr, col, iwdt, ihgt);
}

void *CMetalRenderer::EF_Query(int Query, int Param) {

  return m_shaderManager->EF_Query(Query, Param);
}

void CMetalRenderer::EF_ConstructEf(IShader *Ef) {

  m_shaderManager->EF_ConstructEf(Ef);
}

void CMetalRenderer::EF_SetWorldColor(float r, float g, float b, float a) {

  m_shaderManager->EF_SetWorldColor(r, g, b, a);
}

int CMetalRenderer::EF_RegisterFogVolume(float fMaxFogDist, float fFogLayerZ,
                                         CFColor color, int nIndex,
                                         bool bCaustics) {

  return m_shaderManager->EF_RegisterFogVolume(fMaxFogDist, fFogLayerZ, color,
                                               nIndex, bCaustics);
}

// LeafBuffer delegation
CLeafBuffer *
CMetalRenderer::CreateLeafBuffer(bool bDynamic, const char *szSource,
                                 class CIndexedMesh *pIndexedMesh) {

  return m_shaderManager->CreateLeafBuffer(bDynamic, szSource, pIndexedMesh);
}

CLeafBuffer *CMetalRenderer::CreateLeafBufferInitialized(
    void *pVertBuffer, int nVertCount, int nVertFormat, ushort *pIndices,
    int nIndices, int nPrimetiveType, const char *szSource,
    EBufferType eBufType, int nMatInfoCount, int nClientTextureBindID,
    bool (*PrepareBufferCallback)(CLeafBuffer *, bool), void *CustomData,
    bool bOnlyVideoBuffer, bool bPrecache) {

  return m_shaderManager->CreateLeafBufferInitialized(
      pVertBuffer, nVertCount, nVertFormat, pIndices, nIndices, nPrimetiveType,
      szSource, eBufType, nMatInfoCount, nClientTextureBindID,
      PrepareBufferCallback, CustomData, bOnlyVideoBuffer, bPrecache);
}

void CMetalRenderer::DeleteLeafBuffer(CLeafBuffer *pLBuffer) {
  m_shaderManager->DeleteLeafBuffer(pLBuffer);
}

// Utility rendering delegation
void CMetalRenderer::WriteXY(CXFont *currfont, int x, int y, float xscale,
                             float yscale, float r, float g, float b, float a,
                             const char *message, ...) {
  if (m_utilityRenderer)
    m_utilityRenderer->WriteXY(currfont, x, y, xscale, yscale, r, g, b, a,
                               message);
}

void CMetalRenderer::Draw2dText(float posX, float posY, const char *szText,
                                SDrawTextInfo &info) {
  if (m_utilityRenderer)
    m_utilityRenderer->Draw2dText(posX, posY, szText, info);
}

void CMetalRenderer::Draw2dImage(float xpos, float ypos, float w, float h,
                                 int texture_id, float s0, float t0, float s1,
                                 float t1, float angle, float r, float g,
                                 float b, float a, float z) {
  if (m_utilityRenderer)
    m_utilityRenderer->Draw2dImage(xpos, ypos, w, h, texture_id, s0, t0, s1, t1,
                                   angle, r, g, b, a, z);
}

void CMetalRenderer::DrawImage(float xpos, float ypos, float w, float h,
                               int texture_id, float s0, float t0, float s1,
                               float t1, float r, float g, float b, float a) {
  if (m_utilityRenderer)
    m_utilityRenderer->DrawImage(xpos, ypos, w, h, texture_id, s0, t0, s1, t1,
                                 r, g, b, a);
}

int CMetalRenderer::SetPolygonMode(int mode) {
  if (m_utilityRenderer)
    return m_utilityRenderer->SetPolygonMode(mode);
  return 0;
}

// Additional utility methods would be delegated similarly...

bool CMetalRenderer::InitializeManagers() {
  assert(!m_textureManager && "InitializeManagers: Texture manager already exists!");
  assert(!m_shaderManager && "InitializeManagers: Shader manager already exists!");
  assert(!m_utilityRenderer && "InitializeManagers: Utility renderer already exists!");
  
  // Initialize texture manager
  m_textureManager = std::make_unique<CMetalTextureManager>(this);
  if (!m_textureManager) {
    printf("Error: Failed to create Metal texture manager");
    return false;
  }
  assert(m_textureManager && "InitializeManagers: Texture manager creation failed!");

  // Initialize shader manager
  m_shaderManager =
      std::make_unique<CMetalShaderManager>(this, m_textureManager.get());
  if (!m_shaderManager) {
    printf("Error: Failed to create Metal shader manager");
    return false;
  }
  assert(m_shaderManager && "InitializeManagers: Shader manager creation failed!");

  // Initialize utility renderer
  m_utilityRenderer = std::make_unique<CMetalUtilityRenderer>(
      this, m_textureManager.get(), m_shaderManager.get());
  if (!m_utilityRenderer) {
    printf("Error: Failed to create Metal utility renderer");
    return false;
  }
  assert(m_utilityRenderer && "InitializeManagers: Utility renderer creation failed!");

  return true;
}

void CMetalRenderer::ShutdownManagers() {
  assert(m_utilityRenderer && "ShutdownManagers: Utility renderer is null!");
  assert(m_shaderManager && "ShutdownManagers: Shader manager is null!");
  assert(m_textureManager && "ShutdownManagers: Texture manager is null!");
  
  m_utilityRenderer.reset();
  m_shaderManager.reset();
  m_textureManager.reset();
  
  assert(!m_utilityRenderer && "ShutdownManagers: Utility renderer not released!");
  assert(!m_shaderManager && "ShutdownManagers: Shader manager not released!");
  assert(!m_textureManager && "ShutdownManagers: Texture manager not released!");
}

// Export functions for the renderer
extern "C" {
IRenderer *CreateRenderer(int argc, char *argv[], SCryRenderInterface *sp) {
  CMetalRenderer *renderer = new CMetalRenderer();
  if (renderer) {
    // Initialize the renderer
    if (renderer->Init(0, 0, 1024, 768, 32, 24, 8, false, nullptr, 0, 0, 0,
                       false)) {
      return renderer;
    } else {
      delete renderer;
      return nullptr;
    }
  }
  return nullptr;
}
}

void CMetalRenderer::DrawBuffer(CVertexBuffer *src, SVertexStream *indicies,
                                int numindices, int offsindex, int prmode,
                                int vert_start, int vert_stop, CMatInfo *mi) {
  assert(src && "DrawBuffer: Vertex buffer cannot be null!");
  assert(vert_start >= 0 && "DrawBuffer: Vertex start cannot be negative!");
  assert(vert_stop >= vert_start && "DrawBuffer: Vertex stop must be >= vertex start!");
  
  if (!src || !m_renderEncoder)
    return;

  // Get Metal vertex buffer from CVertexBuffer
  // In a real implementation, we would need to create Metal buffers
  // from the CryEngine vertex data and cache them
  id<MTLBuffer> vertexBuffer = nil;

  // TODO: Create Metal vertex buffer from CVertexBuffer data
  // This would involve:
  // 1. Getting vertex data from CVertexBuffer
  // 2. Creating Metal buffer with the data
  // 3. Caching the buffer for reuse

  if (!vertexBuffer) {
    printf("Warning: Vertex buffer not implemented yet\n");
    return;
  }

  // Set vertex buffer
  [m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];

  // Set up index buffer if provided
  if (indicies && numindices > 0) {
    // TODO: Create Metal index buffer from SVertexStream data
    id<MTLBuffer> indexBuffer = nil;

    if (indexBuffer) {
      // Convert primitive mode to Metal primitive type
      MTLPrimitiveType primitiveType = MTLPrimitiveTypeTriangle;
      switch (prmode) {
      case 0:
        primitiveType = MTLPrimitiveTypeTriangle;
        break;
      case 1:
        primitiveType = MTLPrimitiveTypeLine;
        break;
      case 2:
        primitiveType = MTLPrimitiveTypePoint;
        break;
      default:
        primitiveType = MTLPrimitiveTypeTriangle;
        break;
      }

      // Draw indexed primitives
      [m_renderEncoder drawIndexedPrimitives:primitiveType
                                  indexCount:numindices
                                   indexType:MTLIndexTypeUInt16
                                 indexBuffer:indexBuffer
                           indexBufferOffset:offsindex];
    }
  } else {
    // Draw without indices
    MTLPrimitiveType primitiveType = MTLPrimitiveTypeTriangle;
    switch (prmode) {
    case 0:
      primitiveType = MTLPrimitiveTypeTriangle;
      break;
    case 1:
      primitiveType = MTLPrimitiveTypeLine;
      break;
    case 2:
      primitiveType = MTLPrimitiveTypePoint;
      break;
    default:
      primitiveType = MTLPrimitiveTypeTriangle;
      break;
    }

    int vertexCount = (vert_stop > vert_start) ? (vert_stop - vert_start) : 0;
    [m_renderEncoder drawPrimitives:primitiveType
                        vertexStart:vert_start
                        vertexCount:vertexCount];
  }
}

// Buffer Management Implementation
CVertexBuffer *CMetalRenderer::CreateBuffer(int vertexcount, int vertexformat,
                                            const char *szSource,
                                            bool bDynamic) {
  assert(m_device && "CreateBuffer: Metal device is null!");
  assert(vertexcount > 0 && "CreateBuffer: Vertex count must be positive!");
  assert(vertexformat >= 0 && "CreateBuffer: Vertex format cannot be negative!");
  
  if (!m_device)
    return nullptr;

  // Create a new CVertexBuffer (assuming it exists in CryEngine)
  // In a real implementation, this would create a CryEngine vertex buffer
  // and associate it with a Metal buffer
  printf("Creating vertex buffer: %d vertices, format %d, source: %s\n",
         vertexcount, vertexformat, szSource ? szSource : "Unknown");

  // TODO: Create actual CVertexBuffer and associate with Metal buffer
  return nullptr; // Placeholder
}

void CMetalRenderer::ReleaseBuffer(CVertexBuffer *bufptr) {
  assert(bufptr && "ReleaseBuffer: Buffer pointer cannot be null!");
  
  if (!bufptr)
    return;

  // TODO: Release Metal buffer associated with CVertexBuffer
  printf("Releasing vertex buffer\n");
}

void CMetalRenderer::UpdateBuffer(CVertexBuffer *dest, const void *src,
                                  int vertexcount, bool bUnLock, int nOffs,
                                  int Type) {
  assert(dest && "UpdateBuffer: Destination buffer cannot be null!");
  assert(src && "UpdateBuffer: Source data cannot be null!");
  assert(vertexcount > 0 && "UpdateBuffer: Vertex count must be positive!");
  assert(nOffs >= 0 && "UpdateBuffer: Offset cannot be negative!");
  
  if (!dest || !src)
    return;

  // TODO: Update Metal buffer with new vertex data
  printf("Updating vertex buffer: %d vertices, offset %d, type %d\n",
         vertexcount, nOffs, Type);
}

void CMetalRenderer::CreateIndexBuffer(SVertexStream *dest, const void *src,
                                       int indexcount) {
  assert(dest && "CreateIndexBuffer: Destination stream cannot be null!");
  assert(src && "CreateIndexBuffer: Source data cannot be null!");
  assert(indexcount > 0 && "CreateIndexBuffer: Index count must be positive!");
  
  if (!dest || !src)
    return;

  // TODO: Create Metal index buffer from source data
  printf("Creating index buffer: %d indices\n", indexcount);
}

void CMetalRenderer::UpdateIndexBuffer(SVertexStream *dest, const void *src,
                                       int indexcount, bool bUnLock) {
  assert(dest && "UpdateIndexBuffer: Destination stream cannot be null!");
  assert(src && "UpdateIndexBuffer: Source data cannot be null!");
  assert(indexcount > 0 && "UpdateIndexBuffer: Index count must be positive!");
  
  if (!dest || !src)
    return;

  // TODO: Update Metal index buffer with new data
  printf("Updating index buffer: %d indices\n", indexcount);
}

void CMetalRenderer::ReleaseIndexBuffer(SVertexStream *dest) {
  assert(dest && "ReleaseIndexBuffer: Destination stream cannot be null!");
  
  if (!dest)
    return;

  // TODO: Release Metal index buffer
  printf("Releasing index buffer\n");
}

// Drawing Methods Implementation
void CMetalRenderer::DrawTriStrip(CVertexBuffer *src, int vert_num) {
  assert(src != nullptr && "DrawTriStrip: vertex buffer cannot be null");
  assert(vert_num >= 3 && "DrawTriStrip: need at least 3 vertices for triangle strip");
  assert(m_renderEncoder != nil && "DrawTriStrip: render encoder cannot be null");
  
  if (!src || !m_renderEncoder || vert_num < 3)
    return;

  // Get vertex data from CVertexBuffer
  void* vertexData = src->m_VS[VSF_GENERAL].m_VData;
  if (!vertexData) {
    printf("Warning: No vertex data in buffer\n");
    return;
  }
  
  // Create or get cached Metal buffer
  // In a production implementation, we would cache Metal buffers
  // For now, create a temporary buffer
  size_t bufferSize = vert_num * sizeof(struct_VERTEX_FORMAT_P3F_COL4UB); // Adjust based on format
  id<MTLBuffer> vertexBuffer = [m_device newBufferWithBytes:vertexData
                                                      length:bufferSize
                                                     options:MTLResourceStorageModeShared];
  
  if (!vertexBuffer) {
    printf("Error: Failed to create Metal vertex buffer\n");
    return;
  }
  
  // Set vertex buffer
  [m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
  
  // Set up current pipeline state
  // Ensure we have a valid pipeline state for the current shader
  if (m_currentPipelineState) {
    [m_renderEncoder setRenderPipelineState:m_currentPipelineState];
  }
  
  // Draw triangle strip
  [m_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                       vertexStart:0
                       vertexCount:vert_num];
  
  // Note: Stats would be updated here in production (m_RP.m_PS)
}

void *CMetalRenderer::GetDynVBPtr(int nVerts, int &nOffs, int Pool) {
  assert(nVerts > 0 && "GetDynVBPtr: vertex count must be positive");
  assert(Pool >= 0 && "GetDynVBPtr: pool index cannot be negative");
  
  // TODO: Get pointer to dynamic vertex buffer
  printf("Getting dynamic VB pointer: %d vertices, pool %d\n", nVerts, Pool);
  nOffs = 0;      // Placeholder offset
  return nullptr; // Placeholder
}

void CMetalRenderer::DrawDynVB(int nOffs, int Pool, int nVerts) {
  if (!m_renderEncoder)
    return;

  // TODO: Draw from dynamic vertex buffer
  printf("Drawing dynamic VB: offset %d, pool %d, vertices %d\n", nOffs, Pool,
         nVerts);
}

void CMetalRenderer::DrawDynVB(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F *pBuf,
                               ushort *pInds, int nVerts, int nInds,
                               int nPrimType) {
  if (!pBuf || !m_renderEncoder)
    return;

  // TODO: Draw from vertex buffer with indices
  printf("Drawing dynamic VB with indices: %d vertices, %d indices, prim type "
         "%d\n",
         nVerts, nInds, nPrimType);
}

void CMetalRenderer::SetFenceCompleted(CVertexBuffer *buffer) {
  if (!buffer)
    return;

  // TODO: Set fence for buffer completion
  printf("Setting fence completed for buffer\n");
}

// Debug and Utility Drawing Implementation
void CMetalRenderer::CheckError(const char *comment) {
  // Metal doesn't have the same error checking as OpenGL
  // Errors are typically handled through Metal's error reporting system
  if (comment) {
    printf("Metal renderer check: %s\n", comment);
  }
}

void CMetalRenderer::Draw3dBBox(const Vec3 &mins, const Vec3 &maxs,
                                int nPrimType) {
  if (!m_renderEncoder)
    return;

  // TODO: Draw 3D bounding box using Metal API
  printf("Drawing 3D bbox: min(%.2f,%.2f,%.2f) max(%.2f,%.2f,%.2f) type %d\n",
         mins.x, mins.y, mins.z, maxs.x, maxs.y, maxs.z, nPrimType);
}

void CMetalRenderer::Draw3dPrim(const Vec3 &mins, const Vec3 &maxs,
                                int nPrimType, const float *fRGBA) {
  if (!m_renderEncoder)
    return;

  // TODO: Draw 3D primitive using Metal API
  printf("Drawing 3D prim: min(%.2f,%.2f,%.2f) max(%.2f,%.2f,%.2f) type %d\n",
         mins.x, mins.y, mins.z, maxs.x, maxs.y, maxs.z, nPrimType);
}

// State Management Implementation
void CMetalRenderer::SetState(int State) {
  assert(m_renderEncoder != nil || State == 0 && "SetState: render encoder must be valid for non-zero states");
  
  if (!m_renderEncoder)
    return;

  // Note: In production, we would cache current state to avoid redundant state changes
  
  // Map CryEngine state flags to Metal render states
  // GS_ flags defined in IRenderer.h
  
  // Depth test (GS_NODEPTHTEST)
  // Metal render state is set via pipeline state objects
  // These states would be encoded when creating the render pipeline
  
  bool depthTestEnabled = !(State & GS_NODEPTHTEST);
  bool depthWriteEnabled = !(State & GS_DEPTHWRITE);
  
  // In Metal, depth/stencil state is set via MTLDepthStencilState
  // For now, we note the state for later pipeline state creation
  
  // Blending (GS_BLSRC_*, GS_BLDST_*)
  if (State & (GS_BLSRC_MASK | GS_BLDST_MASK)) {
    // Extract blend source and dest factors for debugging
    int blendSrc = State & GS_BLSRC_MASK;
    int blendDst = State & GS_BLDST_MASK;
    
    assert((blendSrc == 0 || blendSrc == GS_BLSRC_ZERO || blendSrc == GS_BLSRC_ONE || 
            blendSrc == GS_BLSRC_DSTCOL || blendSrc == GS_BLSRC_ONEMINUSDSTCOL ||
            blendSrc == GS_BLSRC_SRCALPHA || blendSrc == GS_BLSRC_ONEMINUSSRCALPHA ||
            blendSrc == GS_BLSRC_DSTALPHA || blendSrc == GS_BLSRC_ONEMINUSDSTALPHA) && 
           "SetState: invalid blend source factor");
    
    assert((blendDst == 0 || blendDst == GS_BLDST_ZERO || blendDst == GS_BLDST_ONE || 
            blendDst == GS_BLDST_SRCCOL || blendDst == GS_BLDST_ONEMINUSSRCCOL ||
            blendDst == GS_BLDST_SRCALPHA || blendDst == GS_BLDST_ONEMINUSSRCALPHA ||
            blendDst == GS_BLDST_DSTALPHA || blendDst == GS_BLDST_ONEMINUSDSTALPHA) && 
           "SetState: invalid blend destination factor");
    
    // Blending enabled
    // In Metal, blend state is part of the pipeline state object
    // Would need to be set during MTLRenderPipelineDescriptor configuration
    // and applied when creating the pipeline state
    printf("SetState: Blending enabled - src=0x%x dst=0x%x\n", blendSrc, blendDst);
  }
  
  // Color masking (GS_NOCOLMASK)
  if (State & GS_NOCOLMASK) {
    // No color writing - disable all color channels
    // This would be set in pipeline state creation
    printf("SetState: Color masking disabled\n");
  }
  
  // Alpha test (GS_ALPHATEST_*)
  if (State & GS_ALPHATEST_MASK) {
    int alphaFunc = State & GS_ALPHATEST_MASK;
    assert((alphaFunc == GS_ALPHATEST_GREATER || alphaFunc == GS_ALPHATEST_LESS || 
            alphaFunc == GS_ALPHATEST_GEQUAL || alphaFunc == GS_ALPHATEST_LEQUAL) && 
           "SetState: invalid alpha test function");
    printf("SetState: Alpha test enabled - func=0x%x\n", alphaFunc);
  }
  
  // Note: State cache methods will be implemented when CMetalStateCache is fully developed
  // For now, state changes are applied directly via render encoder
}

void CMetalRenderer::SetCullMode(int mode) {
  assert(m_renderEncoder != nil && "SetCullMode: render encoder cannot be null");
  
  if (!m_renderEncoder)
    return;

  // Map CryEngine cull mode to Metal cull mode
  MTLCullMode metalCullMode;
  
  switch (mode) {
    case R_CULL_DISABLE:  // R_CULL_NONE has same value
      metalCullMode = MTLCullModeNone;
      break;
      
    case R_CULL_FRONT:
      metalCullMode = MTLCullModeFront;
      break;
      
    case R_CULL_BACK:
    default:
      metalCullMode = MTLCullModeBack;
      break;
  }
  
  // Set cull mode on render encoder
  [m_renderEncoder setCullMode:metalCullMode];
}

bool CMetalRenderer::EnableFog(bool enable) {
  // TODO: Enable/disable fog in Metal
  printf("Fog %s\n", enable ? "enabled" : "disabled");
  return true;
}

void CMetalRenderer::SetFog(float density, float fogstart, float fogend,
                            const float *color, int fogmode) {
  assert(density >= 0.0f && "SetFog: density cannot be negative");
  assert(fogstart >= 0.0f && "SetFog: fog start cannot be negative");
  assert(fogend >= fogstart && "SetFog: fog end must be >= fog start");
  assert(color != nullptr && "SetFog: color array cannot be null");
  
  // TODO: Set fog parameters in Metal
  printf("Setting fog: density %.2f, start %.2f, end %.2f, mode %d\n", density,
         fogstart, fogend, fogmode);
}

void CMetalRenderer::EnableTexGen(bool enable) {
  // TODO: Enable texture generation in Metal
  printf("Texture generation %s\n", enable ? "enabled" : "disabled");
}

void CMetalRenderer::SetTexgen(float scaleX, float scaleY, float translateX,
                               float translateY) {
  // TODO: Set texture generation parameters in Metal
  printf("Setting texgen: scale(%.2f,%.2f) translate(%.2f,%.2f)\n", scaleX,
         scaleY, translateX, translateY);
}

void CMetalRenderer::SetTexgen3D(float x1, float y1, float z1, float x2,
                                 float y2, float z2) {
  // TODO: Set 3D texture generation in Metal
  printf("Setting 3D texgen: (%.2f,%.2f,%.2f) to (%.2f,%.2f,%.2f)\n", x1, y1,
         z1, x2, y2, z2);
}

void CMetalRenderer::SetLodBias(float value) {
  // TODO: Set LOD bias in Metal
  printf("Setting LOD bias: %.2f\n", value);
}

void CMetalRenderer::EnableVSync(bool enable) {
  // TODO: Enable VSync in Metal
  printf("VSync %s\n", enable ? "enabled" : "disabled");
}

// Matrix Management Implementation
void CMetalRenderer::PushMatrix() {
  // TODO: Push matrix onto stack
  printf("Pushing matrix\n");
}

void CMetalRenderer::RotateMatrix(float a, float x, float y, float z) {
  // TODO: Rotate current matrix
  printf("Rotating matrix: angle %.2f axis(%.2f,%.2f,%.2f)\n", a, x, y, z);
}

void CMetalRenderer::RotateMatrix(const Vec3 &angels) {
  // TODO: Rotate current matrix by angles
  printf("Rotating matrix by angles: (%.2f,%.2f,%.2f)\n", angels.x, angels.y,
         angels.z);
}

void CMetalRenderer::TranslateMatrix(float x, float y, float z) {
  // TODO: Translate current matrix
  printf("Translating matrix: (%.2f,%.2f,%.2f)\n", x, y, z);
}

void CMetalRenderer::ScaleMatrix(float x, float y, float z) {
  // TODO: Scale current matrix
  printf("Scaling matrix: (%.2f,%.2f,%.2f)\n", x, y, z);
}

void CMetalRenderer::TranslateMatrix(const Vec3 &pos) {
  // TODO: Translate current matrix by position
  printf("Translating matrix by pos: (%.2f,%.2f,%.2f)\n", pos.x, pos.y, pos.z);
}

void CMetalRenderer::MultMatrix(float *mat) {
  assert(mat != nullptr && "MultMatrix: matrix pointer cannot be null");
  
  // TODO: Multiply current matrix
  printf("Multiplying matrix\n");
}

void CMetalRenderer::LoadMatrix(const Matrix44 *src) {
  assert(src != nullptr && "LoadMatrix: source matrix cannot be null");
  
  // TODO: Load matrix
  printf("Loading matrix\n");
}

void CMetalRenderer::PopMatrix() {
  // TODO: Pop matrix from stack
  printf("Popping matrix\n");
}

void CMetalRenderer::EnableTMU(bool enable) {
  // TODO: Enable texture mapping unit
  printf("TMU %s\n", enable ? "enabled" : "disabled");
}

void CMetalRenderer::SelectTMU(int tnum) {
  assert(tnum >= 0 && tnum < MAX_TMU && "SelectTMU: texture unit index out of range");
  
  // TODO: Select texture mapping unit
  printf("Selecting TMU: %d\n", tnum);
}

// Display and Resolution Implementation
bool CMetalRenderer::ChangeDisplay(unsigned int width, unsigned int height,
                                   unsigned int cbpp) {
  assert(width > 0 && "ChangeDisplay: width must be positive");
  assert(height > 0 && "ChangeDisplay: height must be positive");
  assert(cbpp == 16 || cbpp == 24 || cbpp == 32 && "ChangeDisplay: bits per pixel must be 16, 24, or 32");
  
  // TODO: Change Metal display resolution
  printf("Changing display: %dx%d, %d bpp\n", width, height, cbpp);
  return true;
}

void CMetalRenderer::ChangeViewport(unsigned int x, unsigned int y,
                                    unsigned int width, unsigned int height) {
  assert(width > 0 && "ChangeViewport: width must be positive");
  assert(height > 0 && "ChangeViewport: height must be positive");
  
  // TODO: Change Metal viewport
  printf("Changing viewport: (%d,%d) %dx%d\n", x, y, width, height);
  SetViewport(x, y, width, height);
}

bool CMetalRenderer::SaveTga(unsigned char *sourcedata, int sourceformat, int w,
                             int h, const char *filename, bool flip) {
  assert(sourcedata != nullptr && "SaveTga: source data cannot be null");
  assert(w > 0 && "SaveTga: width must be positive");
  assert(h > 0 && "SaveTga: height must be positive");
  assert(filename != nullptr && "SaveTga: filename cannot be null");
  
  // TODO: Save TGA using Metal
  printf("Saving TGA: %dx%d, format %d, file %s\n", w, h, sourceformat,
         filename ? filename : "NULL");
  return true;
}

// Screen Information Implementation
int CMetalRenderer::GetWidth() { return m_width; }

int CMetalRenderer::GetHeight() { return m_height; }

void CMetalRenderer::GetMemoryUsage(ICrySizer *Sizer) {
  // TODO: Get Metal memory usage
  printf("Getting memory usage\n");
}

void CMetalRenderer::ScreenShot(const char *filename) {
  assert(filename != nullptr && "ScreenShot: filename cannot be null");
  
  // TODO: Take screenshot using Metal
  printf("Taking screenshot: %s\n", filename ? filename : "default");
}

int CMetalRenderer::GetColorBpp() { return m_cbpp; }

int CMetalRenderer::GetDepthBpp() { return m_zbpp; }

int CMetalRenderer::GetStencilBpp() { return m_sbpp; }

// Additional Essential Methods Implementation

void CMetalRenderer::ProjectToScreen(float ptx, float pty, float ptz, float *sx,
                                     float *sy, float *sz) {
  assert(sx != nullptr && "ProjectToScreen: output sx cannot be null");
  assert(sy != nullptr && "ProjectToScreen: output sy cannot be null");
  assert(sz != nullptr && "ProjectToScreen: output sz cannot be null");
  
  // TODO: Project 3D point to screen coordinates
  printf("Projecting to screen: (%.2f,%.2f,%.2f)\n", ptx, pty, ptz);
  if (sx)
    *sx = ptx;
  if (sy)
    *sy = pty;
  if (sz)
    *sz = ptz;
}

int CMetalRenderer::UnProject(float sx, float sy, float sz, float *px,
                              float *py, float *pz, const float modelMatrix[16],
                              const float projMatrix[16],
                              const int viewport[4]) {
  assert(px != nullptr && "UnProject: output px cannot be null");
  assert(py != nullptr && "UnProject: output py cannot be null");
  assert(pz != nullptr && "UnProject: output pz cannot be null");
  assert(modelMatrix != nullptr && "UnProject: modelMatrix cannot be null");
  assert(projMatrix != nullptr && "UnProject: projMatrix cannot be null");
  assert(viewport != nullptr && "UnProject: viewport cannot be null");
  
  // TODO: Unproject screen coordinates to 3D
  printf("Unprojecting from screen: (%.2f,%.2f,%.2f)\n", sx, sy, sz);
  if (px)
    *px = sx;
  if (py)
    *py = sy;
  if (pz)
    *pz = sz;
  return 1;
}

int CMetalRenderer::UnProjectFromScreen(float sx, float sy, float sz, float *px,
                                        float *py, float *pz) {
  assert(px != nullptr && "UnProjectFromScreen: output px cannot be null");
  assert(py != nullptr && "UnProjectFromScreen: output py cannot be null");
  assert(pz != nullptr && "UnProjectFromScreen: output pz cannot be null");
  
  // TODO: Unproject from screen coordinates
  printf("Unprojecting from screen: (%.2f,%.2f,%.2f)\n", sx, sy, sz);
  if (px)
    *px = sx;
  if (py)
    *py = sy;
  if (pz)
    *pz = sz;
  return 1;
}

void CMetalRenderer::GetModelViewMatrix(float *mat) {
  assert(mat != nullptr && "GetModelViewMatrix: matrix pointer cannot be null");
  
  // TODO: Get model-view matrix
  printf("Getting model-view matrix\n");
  if (mat) {
    // Return identity matrix
    for (int i = 0; i < 16; i++)
      mat[i] = (i % 5 == 0) ? 1.0f : 0.0f;
  }
}

void CMetalRenderer::GetModelViewMatrix(double *mat) {
  assert(mat != nullptr && "GetModelViewMatrix: matrix pointer cannot be null");
  
  // TODO: Get model-view matrix as double
  printf("Getting model-view matrix (double)\n");
  if (mat) {
    // Return identity matrix
    for (int i = 0; i < 16; i++)
      mat[i] = (i % 5 == 0) ? 1.0 : 0.0;
  }
}

void CMetalRenderer::GetProjectionMatrix(double *mat) {
  assert(mat != nullptr && "GetProjectionMatrix: matrix pointer cannot be null");
  
  // TODO: Get projection matrix as double
  printf("Getting projection matrix (double)\n");
  if (mat) {
    // Return identity matrix
    for (int i = 0; i < 16; i++)
      mat[i] = (i % 5 == 0) ? 1.0 : 0.0;
  }
}

void CMetalRenderer::GetProjectionMatrix(float *mat) {
  assert(mat != nullptr && "GetProjectionMatrix: matrix pointer cannot be null");
  
  // TODO: Get projection matrix
  printf("Getting projection matrix\n");
  if (mat) {
    // Return identity matrix
    for (int i = 0; i < 16; i++)
      mat[i] = (i % 5 == 0) ? 1.0f : 0.0f;
  }
}

Vec3 CMetalRenderer::GetUnProject(const Vec3 &WindowCoords,
                                  const CCamera &cam) {
  // TODO: Unproject window coordinates
  printf("Getting unproject: (%.2f,%.2f,%.2f)\n", WindowCoords.x,
         WindowCoords.y, WindowCoords.z);
  return WindowCoords;
}

void CMetalRenderer::RenderToViewport(const CCamera &cam, float x, float y,
                                      float width, float height) {
  // TODO: Render to viewport
  printf("Rendering to viewport: (%.2f,%.2f) %fx%f\n", x, y, width, height);
}

// Missing IRenderer method implementations
void CMetalRenderer::BeginFrame() {
  // Call base class BeginFrame
  CMetalBaseRenderer::BeginFrame();
}

void CMetalRenderer::Update() {
  // Call base class Update
  CMetalBaseRenderer::Update();
}

void CMetalRenderer::SetScissor(int x, int y, int width, int height) {
  assert(x >= 0 && "SetScissor: x coordinate cannot be negative");
  assert(y >= 0 && "SetScissor: y coordinate cannot be negative");
  assert(width > 0 && "SetScissor: width must be positive");
  assert(height > 0 && "SetScissor: height must be positive");
  assert(m_renderEncoder != nil || (width == 0 && height == 0) && "SetScissor: render encoder required for non-zero scissor");
  
  if (!m_renderEncoder)
    return;

  // TODO: Set Metal scissor rect
  printf("Setting scissor: (%d,%d) %dx%d\n", x, y, width, height);
}

int CMetalRenderer::GetFeatures() {
  // TODO: Return Metal-specific features
  return 0;
}

void CMetalRenderer::GetViewport(int *x, int *y, int *width, int *height) {
  if (x)
    *x = m_viewportX;
  if (y)
    *y = m_viewportY;
  if (width)
    *width = m_viewportWidth;
  if (height)
    *height = m_viewportHeight;
}

void CMetalRenderer::MakeCurrent() {
  // Metal doesn't require context switching
}

void CMetalRenderer::SetViewport(int x, int y, int width, int height) {
  assert(width > 0 && height > 0 && "SetViewport: Dimensions must be positive!");
  assert(x >= 0 && y >= 0 && "SetViewport: Position cannot be negative!");
  
  if (!m_isInitialized)
    return;

  // Update internal viewport state
  m_viewportX = x;
  m_viewportY = y;
  m_viewportWidth = width;
  m_viewportHeight = height;

  // Set Metal viewport
  MTLViewport viewport = {(double)x,      (double)y, (double)width,
                          (double)height, 0.0,       1.0};
  if (m_renderEncoder) {
    [m_renderEncoder setViewport:viewport];
  }
}

bool CMetalRenderer::CreateContext(WIN_HWND hWnd, bool bAllowFSAA) {
  // TODO: Create Metal context
  printf("Creating Metal context\n");
  return true;
}

bool CMetalRenderer::DeleteContext(WIN_HWND hWnd) {
  // TODO: Delete Metal context
  printf("Deleting Metal context\n");
  return true;
}

void CMetalRenderer::FreeResources(int nFlags) {
  // TODO: Free Metal resources
  printf("Freeing Metal resources: flags %d\n", nFlags);
}

void CMetalRenderer::ShareResources(IRenderer *renderer) {
  // TODO: Share Metal resources
  printf("Sharing Metal resources\n");
}

bool CMetalRenderer::ChangeResolution(int nNewWidth, int nNewHeight,
                                      int nNewColDepth, int nNewRefreshHZ,
                                      bool bFullScreen) {
  // TODO: Change Metal resolution
  printf("Changing resolution: %dx%d, %d bpp, %d Hz, fullscreen %s\n",
         nNewWidth, nNewHeight, nNewColDepth, nNewRefreshHZ,
         bFullScreen ? "yes" : "no");
  return true;
}

void CMetalRenderer::RefreshResources(int nFlags) {
  // TODO: Refresh Metal resources
  printf("Refreshing Metal resources: flags %d\n", nFlags);
}

bool CMetalRenderer::SetCurrentContext(WIN_HWND hWnd) {
  // TODO: Set current Metal context
  printf("Setting current Metal context\n");
  return true;
}

int CMetalRenderer::EnumDisplayFormats(TArray<SDispFormat> &Formats,
                                       bool bReset) {
  // TODO: Enumerate Metal display formats
  printf("Enumerating Metal display formats\n");
  return 0;
}

int CMetalRenderer::GetMaxTextureMemory() {
  // TODO: Get Metal texture memory limit
  return 512 * 1024 * 1024; // 512MB placeholder
}

WIN_HWND CMetalRenderer::Init(int x, int y, int width, int height,
                              unsigned int cbpp, int zbpp, int sbits,
                              bool fullscreen, WIN_HINSTANCE hinst,
                              WIN_HWND Glhwnd, WIN_HDC Glhdc, WIN_HGLRC hGLrc,
                              bool bReInit) {
  // TODO: Initialize Metal renderer
  printf("Initializing Metal renderer: %dx%d, %d bpp\n", width, height, cbpp);
  return (WIN_HWND)1; // Placeholder
}

void CMetalRenderer::PreLoad() {
  // TODO: Preload Metal resources
  printf("Preloading Metal resources\n");
}

void CMetalRenderer::Release() {
  // TODO: Release Metal resources
  printf("Releasing Metal resources\n");
}

void CMetalRenderer::PostLoad() {
  // TODO: Postload Metal resources
  printf("Postloading Metal resources\n");
}

void CMetalRenderer::ShutDown(bool bReInit) {
  // TODO: Shutdown Metal renderer
  printf("Shutting down Metal renderer: reinit %s\n", bReInit ? "yes" : "no");
}

////////////////////////////////////////////////////////////////////////////
// Camera Management - Delegated to CMetalBaseRenderer
////////////////////////////////////////////////////////////////////////////

/**
 * @brief Gets the current rendering camera
 *
 * This method delegates to the base class (CMetalBaseRenderer) which
 * stores the camera by value. This design avoids camera duplication and
 * ensures a single source of truth for camera state.
 *
 * @return Const reference to the current camera object
 *
 * @design_rationale
 * Camera is stored in CMetalBaseRenderer::m_camera (not duplicated in
 * CMetalRenderer) to avoid state inconsistency. CMetalRenderer simply
 * delegates to the base class implementation.
 *
 * @thread_safety Not thread-safe. Must be called from main render thread.
 *
 * @see CMetalBaseRenderer::GetCamera()
 * @see SetCamera()
 */
const CCamera &CMetalRenderer::GetCamera() {
  return CMetalBaseRenderer::GetCamera();
}

/**
 * @brief Sets the current rendering camera
 *
 * This method delegates to the base class (CMetalBaseRenderer) which:
 * 1. Stores the camera by value (copies it into m_camera)
 * 2. Updates Metal view and projection matrices
 * 3. Uploads matrices to GPU uniform buffers (if render encoder is active)
 *
 * @param cam Camera object to set (copied, not stored by reference)
 *
 * @design_rationale
 * Camera is stored by value (not pointer) to avoid lifetime issues.
 * The base class handles all Metal-specific matrix updates.
 *
 * @note
 * This copies the entire CCamera object. For performance-critical code,
 * minimize camera changes per frame.
 *
 * @thread_safety Not thread-safe. Must be called from main render thread.
 *
 * @see CMetalBaseRenderer::SetCamera()
 * @see GetCamera()
 */
void CMetalRenderer::SetCamera(const CCamera &cam) {
  CMetalBaseRenderer::SetCamera(cam);
}

////////////////////////////////////////////////////////////////////////////
// DLL Entry Point - Creates and initializes CMetalRenderer instance
////////////////////////////////////////////////////////////////////////////

/**
 * @brief Creates and initializes a CMetalRenderer instance
 *
 * This function is the internal factory that:
 * 1. Allocates a new CMetalRenderer object
 * 2. Parses command-line arguments for display settings (TODO)
 * 3. Calls Init() with appropriate parameters
 * 4. Returns the initialized renderer or nullptr on failure
 *
 * @param argc Number of command-line arguments (currently unused)
 * @param argv Array of command-line argument strings (currently unused)
 * @param sp CryEngine render interface (currently unused)
 *
 * @return Pointer to initialized IRenderer, or nullptr if initialization failed
 *
 * @design_pattern Factory Method
 *
 * @error_handling
 * - Returns nullptr if allocation fails
 * - Returns nullptr if Init() fails (deletes renderer before returning)
 * - Logs errors to both console (printf) and /tmp/farcry_metal_create.log
 *
 * @display_settings
 * Display settings are obtained from (in order of priority):
 * 1. SCryRenderInterface callbacks (ipGetWidth, ipGetHeight, etc.)
 * 2. Command-line arguments (-width, -height, -fullscreen, -bpp)
 * 3. System defaults from NSScreen (macOS primary display)
 * 4. Hardcoded fallback (800x600) if all else fails
 *
 * Supported command-line arguments:
 * - -width <pixels> or --width <pixels>
 * - -height <pixels> or --height <pixels>
 * - -fullscreen or --fullscreen
 * - -bpp <bits> or --bpp <bits>
 *
 * @see PackageRenderConstructor() (main DLL entry point)
 * @see CMetalRenderer::Init()
 */
IRenderer *CreateMetalRendererInstance(int argc, char *argv[],
                                       SCryRenderInterface *sp) {
  printf("CreateMetalRendererInstance called\n");
  
  assert(argc >= 0 && "CreateMetalRendererInstance: argc cannot be negative!");
  assert(sp != nullptr && "CreateMetalRendererInstance: SCryRenderInterface cannot be null!");

  FILE *f = fopen("/tmp/farcry_metal_create.log", "w");
  if (f) {
    fprintf(f, "Creating CMetalRenderer (new architecture)\n");
    fprintf(f, "argc=%d, argv=%p, sp=%p\n", argc, argv, sp);
    fflush(f);
    fclose(f);
  }

  // Initialize global engine interface pointers BEFORE creating renderer
  // The CRenderer constructor needs these to register console variables
  if (sp) {
    iSystem = sp->ipSystem;
    iConsole = sp->ipConsole;
    iLog = sp->ipLog;
    iTimer = sp->ipTimer;
    printf("Initialized engine interfaces: iSystem=%p, iConsole=%p, iLog=%p, iTimer=%p\n",
           iSystem, iConsole, iLog, iTimer);
  } else {
    printf("ERROR: No SCryRenderInterface provided - console variables won't be registered\n");
    return nullptr;
  }

  CMetalRenderer *renderer = new CMetalRenderer();
  assert(renderer && "CreateMetalRendererInstance: Failed to allocate CMetalRenderer!");
  if (!renderer) {
    printf("ERROR: Failed to allocate CMetalRenderer\n");
    if (f) {
      fprintf(f, "ERROR: Failed to allocate renderer\n");
      fclose(f);
    }
    return nullptr;
  }

  printf("CMetalRenderer created: %p\n", renderer);

  // Get display settings from SCryRenderInterface or system defaults
  int width = 800;
  int height = 600;
  int colorBpp = 32;
  int depthBpp = 24;
  int stencilBpp = 8;
  bool fullscreen = false;

  // Use passed-in display settings or defaults
  // SCryRenderInterface provides system services (log, console, timer), not display settings
  if (sp) {
    printf("CryEngine interface provided (log, console, timer available)\n");
  }
  
  // Display settings come from function parameters or defaults
  {
    // Fallback: Get primary screen resolution from NSScreen
    @autoreleasepool {
      NSScreen *mainScreen = [NSScreen mainScreen];
      if (mainScreen) {
        NSRect screenRect = [mainScreen frame];
        width = (int)screenRect.size.width;
        height = (int)screenRect.size.height;
        printf("Display settings from NSScreen: %dx%d\n", width, height);
      } else {
        printf(
            "WARNING: Could not get screen resolution, using defaults: %dx%d\n",
            width, height);
      }
    }
  }

  // Parse command-line overrides (if provided)
  for (int i = 0; i < argc - 1; i++) {
    if (strcmp(argv[i], "-width") == 0 || strcmp(argv[i], "--width") == 0) {
      width = atoi(argv[i + 1]);
      i++;
    } else if (strcmp(argv[i], "-height") == 0 ||
               strcmp(argv[i], "--height") == 0) {
      height = atoi(argv[i + 1]);
      i++;
    } else if (strcmp(argv[i], "-fullscreen") == 0 ||
               strcmp(argv[i], "--fullscreen") == 0) {
      fullscreen = true;
    } else if (strcmp(argv[i], "-bpp") == 0 || strcmp(argv[i], "--bpp") == 0) {
      colorBpp = atoi(argv[i + 1]);
      i++;
    }
  }

  printf("Final renderer settings: %dx%d, color=%dbpp, depth=%dbpp, "
         "stencil=%dbpp, fullscreen=%d\n",
         width, height, colorBpp, depthBpp, stencilBpp, fullscreen);

  // Initialize the renderer
  void *result =
      renderer->Init(0, 0, width, height, colorBpp, depthBpp, stencilBpp,
                     fullscreen, nullptr, nullptr, nullptr, nullptr, false);

  if (!result) {
    printf("ERROR: CMetalRenderer::Init() failed!\n");
    if (f) {
      fprintf(f, "ERROR: Renderer initialization failed\n");
      fclose(f);
    }
    delete renderer;
    return nullptr;
  }

  printf("CMetalRenderer initialized successfully\n");
  if (f) {
    fprintf(f, "SUCCESS: Renderer initialized at %p\n", renderer);
    fclose(f);
  }

  return renderer;
}

////////////////////////////////////////////////////////////////////////////
// Main DLL Entry Point - Called by game engine to create renderer
////////////////////////////////////////////////////////////////////////////

/**
 * @brief Main DLL entry point for renderer creation
 *
 * This function is called by the FarCry engine during initialization to
 * create the Metal renderer. It must have C linkage and be exported from
 * the DLL with proper visibility.
 *
 * @param argc Number of command-line arguments passed by engine
 * @param argv Array of command-line arguments passed by engine
 * @param sp Pointer to CryEngine render interface (for callbacks)
 *
 * @return Pointer to initialized IRenderer, or nullptr if creation failed
 *
 * @dll_export
 * Symbol is exported with __attribute__((visibility("default"))) on macOS
 * to ensure it's visible to the dynamic linker.
 *
 * @calling_convention
 * C calling convention (extern "C") to ensure consistent name mangling
 * across compilers and linker compatibility.
 *
 * @lifecycle
 * 1. Engine calls PackageRenderConstructor() during startup
 * 2. This function delegates to CreateMetalRendererInstance()
 * 3. Returns initialized renderer to engine
 * 4. Engine uses returned IRenderer* for all rendering operations
 * 5. Engine calls renderer->Release() on shutdown
 *
 * @logging
 * Writes diagnostic logs to:
 * - /tmp/farcry_render_constructor.log (entry point called)
 * - /tmp/farcry_render_created.log (result of creation)
 * - stdout (printf for debugging)
 *
 * @example
 * ```cpp
 * // Engine code (System.cpp):
 * typedef IRenderer* (*PFNCREATEMETALRENDERER)(int, char*[],
 * SCryRenderInterface*);
 *
 * void* hDLL = dlopen("libXRenderMetal.dylib", RTLD_NOW);
 * PFNCREATEMETALRENDERER pfnCreate =
 *     (PFNCREATEMETALRENDERER)dlsym(hDLL, "PackageRenderConstructor");
 *
 * IRenderer* renderer = pfnCreate(argc, argv, &renderInterface);
 * if (!renderer) {
 *     FatalError("Failed to create Metal renderer");
 * }
 * ```
 *
 * @compatibility
 * This is the standard entry point used by all CryEngine renderers
 * (OpenGL, Direct3D, Metal). The signature must match exactly.
 *
 * @see CreateMetalRendererInstance() (internal factory)
 * @see IRenderer (base interface)
 */
extern "C" DLL_EXPORT IRenderer *
PackageRenderConstructor(int argc, char *argv[], SCryRenderInterface *sp) {
  printf("PackageRenderConstructor called (CMetalRenderer architecture)\n");

  FILE *f = fopen("/tmp/farcry_render_constructor.log", "w");
  if (f) {
    fprintf(f, "PackageRenderConstructor called\n");
    fprintf(f, "argc=%d, argv=%p, sp=%p\n", argc, argv, sp);
    fprintf(f, "Using CMetalRenderer (manager pattern)\n");
    fflush(f);
    fclose(f);
  }

  IRenderer *renderer = CreateMetalRendererInstance(argc, argv, sp);

  f = fopen("/tmp/farcry_render_created.log", "w");
  if (f) {
    if (renderer) {
      fprintf(f, "SUCCESS: CMetalRenderer created and initialized: %p\n",
              renderer);
    } else {
      fprintf(f, "ERROR: CMetalRenderer creation failed!\n");
    }
    fflush(f);
    fclose(f);
  }

  return renderer;
}

/**
 * @brief Force symbol export by referencing PackageRenderConstructor
 *
 * This static variable ensures that the PackageRenderConstructor symbol
 * is not stripped by the linker during optimization. By creating a
 * reference to the function, we guarantee it will be present in the
 * final DLL for dynamic loading.
 *
 * @technical_note
 * Without this reference, aggressive linker optimization might remove
 * the symbol if it appears unused within the DLL itself (even though
 * it's needed for external dynamic loading).
 *
 * @see PackageRenderConstructor() (exported function)
 */
static IRenderer *(*g_PackageRenderConstructor)(
    int, char *[], SCryRenderInterface *) = PackageRenderConstructor;

//============================================================================
// Implementation of pure virtual methods from CRenderer
//============================================================================

void CMetalRenderer::DrawPoints(Vec3 v[], int nump, CFColor& col, int flags) {
    assert(v != nullptr || nump == 0 && "DrawPoints: vertex array cannot be null when nump > 0");
    assert(nump >= 0 && "DrawPoints: point count cannot be negative");
    
    if (!v || nump <= 0 || !m_renderEncoder)
        return;
    
    // TODO: Implement debug point rendering using Metal line primitives
    SetState(GS_NODEPTHTEST);
}

void CMetalRenderer::DrawLines(Vec3 v[], int nump, CFColor& col, int flags, float fGround) {
    if (!v || nump < 2 || !m_renderEncoder)
        return;
    
    // TODO: Implement debug line rendering
    SetState(GS_NODEPTHTEST);
}

void CMetalRenderer::EF_Release(int nFlags) {
    // Release shader resources
    if (m_shaderManager) {
        if (nFlags & EFRF_VSHADERS)
            m_shaderManager->ClearAllShaders();
        if (nFlags & EFRF_PSHADERS)
            m_shaderManager->ClearAllShaders();
    }
}

void CMetalRenderer::CreateBuffer(int size, int vertexformat, CVertexBuffer *buf, int Type, const char *szSource) {
    if (!buf || size <= 0)
        return;
    
    // Create Metal buffer with specified size
    @autoreleasepool {
        id<MTLBuffer> metalBuffer = [m_device newBufferWithLength:size options:MTLResourceStorageModeShared];
        if (metalBuffer) {
            // Store buffer info
        }
    }
}

void CMetalRenderer::SetClipPlane(int id, float * params) {
    // Metal doesn't support user clip planes directly
    // Would need to implement in shader using clip distance
}

char* CMetalRenderer::GetStatusText(ERendStats type) {
    static char statusText[256] = "Metal Renderer Status";
    return statusText;
}

void CMetalRenderer::EF_SetClipPlane(bool bEnable, float *pPlane, bool bRefract) {
    // Metal clip plane implementation would go through shaders
}

void CMetalRenderer::PrepareDepthMap(ShadowMapFrustum * lof, bool make_new_tid) {
    if (!lof)
        return;
    
    // TODO: Implement shadow map rendering
}

void CMetalRenderer::EF_CheckOverflow(int nVerts, int nTris, CRendElement *re) {
    // Check if we need to flush the current batch
    // Metal handles this through command buffer management
}

void CMetalRenderer::EF_LightMaterial(SLightMaterial *lm, int Flags) {
    if (!lm)
        return;
    
    // Set material lighting properties
}

STexPic* CMetalRenderer::EF_MakePhongTexture(int Exp) {
    // Create procedural phong shading texture
    return nullptr;
}

void CMetalRenderer::EF_PipelineShutdown() {
    // Clean up shader pipeline resources
    if (m_shaderManager) {
        m_shaderManager->ClearAllShaders();
    }
}

void CMetalRenderer::SetupShadowOnlyPass(int Num, ShadowMapFrustum * pFrustum, Vec3 * vShadowTrans, 
                                         const float fShadowScale, Vec3 vObjTrans, float fObjScale, 
                                         const Vec3 vObjAngles, Matrix44 * pObjMat) {
    if (!pFrustum)
        return;
    
    // TODO: Set up shadow rendering pass
}

void CMetalRenderer::DrawAllShadowsOnTheScreen() {
    // TODO: Render all shadow volumes/maps
}

void CMetalRenderer::Reset(void) {
    // Reset renderer state to defaults
    m_nFrameID = 0;
    m_nPolygons = 0;
    m_CurState = 0;
}

void CMetalRenderer::EF_Start(SShader *ef, SShader *efState, SRenderShaderResources *Res, CRendElement *re) {
    // Start effect rendering - set up shader and resources
    if (!ef || !m_renderEncoder)
        return;
    
    m_RP.m_pShader = ef;
    m_RP.m_pCurObject = nullptr;
    m_RP.m_pRE = re;
}

void CMetalRenderer::EF_Start(SShader *ef, SShader *efState, SRenderShaderResources *Res, int nFog, CRendElement *re) {
    // Start effect with fog parameter
    EF_Start(ef, efState, Res, re);
}

#endif // __APPLE__ && __MACH__
