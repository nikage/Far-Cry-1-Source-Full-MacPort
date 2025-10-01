////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalRenderer.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Main Metal renderer implementation that combines specialized managers
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalRenderer.h"
#include "I3DEngine.h"
#include <Cocoa/Cocoa.h>

CMetalRenderer::CMetalRenderer()
    : m_textureManager(nullptr)
    , m_shaderManager(nullptr)
    , m_utilityRenderer(nullptr)
{
    // Initialize specialized managers
    InitializeManagers();
}

CMetalRenderer::~CMetalRenderer()
{
    ShutdownManagers();
}

// Texture management delegation
void CMetalRenderer::SetTexture(int tnum, ETexType Type)
{
    if (m_textureManager)
        m_textureManager->SetTexture(tnum, Type);
}

void CMetalRenderer::SetWhiteTexture()
{
    if (m_textureManager)
        m_textureManager->SetWhiteTexture();
}

unsigned int CMetalRenderer::DownLoadToVideoMemory(unsigned char* data, int w, int h, 
                                                 ETEX_Format eTFSrc, ETEX_Format eTFDst, 
                                                 int nummipmap, bool repeat, 
                                                 int filter, int Id, 
                                                 char* szCacheName, int flags)
{
    if (m_textureManager)
        return m_textureManager->DownLoadToVideoMemory(data, w, h, eTFSrc, eTFDst, nummipmap, repeat, filter, Id, szCacheName, flags);
    return 0;
}

void CMetalRenderer::UpdateTextureInVideoMemory(uint tnum, unsigned char* newdata, int posx, int posy, 
                                               int w, int h, ETEX_Format eTF)
{
    if (m_textureManager)
        m_textureManager->UpdateTextureInVideoMemory(tnum, newdata, posx, posy, w, h, eTF);
}

unsigned int CMetalRenderer::LoadTexture(const char* filename, int* tex_type, 
                                        unsigned int def_tid, bool compresstodisk, 
                                        bool bWarn)
{
    if (m_textureManager)
        return m_textureManager->LoadTexture(filename, tex_type, def_tid, compresstodisk, bWarn);
    return 0;
}

bool CMetalRenderer::DXTCompress(byte* raw_data, int nWidth, int nHeight, ETEX_Format eTF, 
                                bool bUseHW, bool bGenMips, int nSrcBytesPerPix, 
                                MIPDXTcallback callback)
{
    if (m_textureManager)
        return m_textureManager->DXTCompress(raw_data, nWidth, nHeight, eTF, bUseHW, bGenMips, nSrcBytesPerPix, callback);
    return false;
}

bool CMetalRenderer::DXTDecompress(byte* srcData, byte* dstData, int nWidth, int nHeight, 
                                  ETEX_Format eSrcTF, bool bUseHW, int nDstBytesPerPix)
{
    if (m_textureManager)
        return m_textureManager->DXTDecompress(srcData, dstData, nWidth, nHeight, eSrcTF, bUseHW, nDstBytesPerPix);
    return false;
}

void CMetalRenderer::RemoveTexture(unsigned int TextureId)
{
    if (m_textureManager)
        m_textureManager->RemoveTexture(TextureId);
}

void CMetalRenderer::RemoveTexture(ITexPic* pTexPic)
{
    if (m_textureManager)
        m_textureManager->RemoveTexture(pTexPic);
}

bool CMetalRenderer::SetGammaDelta(const float fGamma)
{
    if (m_textureManager)
        return m_textureManager->SetGammaDelta(fGamma);
    return false;
}

// Font system delegation
bool CMetalRenderer::FontUploadTexture(class CFBitmap* bitmap, ETEX_Format eTF)
{
    if (m_textureManager)
        return m_textureManager->FontUploadTexture(bitmap, eTF);
    return false;
}

int CMetalRenderer::FontCreateTexture(int Width, int Height, byte* pData, ETEX_Format eTF)
{
    if (m_textureManager)
        return m_textureManager->FontCreateTexture(Width, Height, pData, eTF);
    return 0;
}

bool CMetalRenderer::FontUpdateTexture(int nTexId, int X, int Y, int USize, int VSize, byte* pData)
{
    if (m_textureManager)
        return m_textureManager->FontUpdateTexture(nTexId, X, Y, USize, VSize, pData);
    return false;
}

void CMetalRenderer::FontReleaseTexture(class CFBitmap* pBmp)
{
    if (m_textureManager)
        m_textureManager->FontReleaseTexture(pBmp);
}

void CMetalRenderer::FontSetTexture(class CFBitmap* bitmap, int nFilterMode)
{
    if (m_textureManager)
        m_textureManager->FontSetTexture(bitmap, nFilterMode);
}

void CMetalRenderer::FontSetTexture(int nTexId, int nFilterMode)
{
    if (m_textureManager)
        m_textureManager->FontSetTexture(nTexId, nFilterMode);
}

void CMetalRenderer::FontSetRenderingState(unsigned long nVirtualScreenWidth, unsigned long nVirtualScreenHeight)
{
    if (m_textureManager)
        m_textureManager->FontSetRenderingState(nVirtualScreenWidth, nVirtualScreenHeight);
}

void CMetalRenderer::FontSetBlending(int src, int dst)
{
    if (m_textureManager)
        m_textureManager->FontSetBlending(src, dst);
}

void CMetalRenderer::FontRestoreRenderingState()
{
    if (m_textureManager)
        m_textureManager->FontRestoreRenderingState();
}

// Shader system delegation
bool CMetalRenderer::EF_PrecacheResource(IShader* pSH, float fDist, float fTimeToReady, int Flags)
{
    if (m_shaderManager)
        return m_shaderManager->EF_PrecacheResource(pSH, fDist, fTimeToReady, Flags);
    return false;
}

bool CMetalRenderer::EF_PrecacheResource(ITexPic* pTP, float fDist, float fTimeToReady, int Flags)
{
    if (m_shaderManager)
        return m_shaderManager->EF_PrecacheResource(pTP, fDist, fTimeToReady, Flags);
    return false;
}

bool CMetalRenderer::EF_PrecacheResource(CLeafBuffer* pPB, float fDist, float fTimeToReady, int Flags)
{
    if (m_shaderManager)
        return m_shaderManager->EF_PrecacheResource(pPB, fDist, fTimeToReady, Flags);
    return false;
}

bool CMetalRenderer::EF_PrecacheResource(CDLight* pLS, float fDist, float fTimeToReady, int Flags)
{
    if (m_shaderManager)
        return m_shaderManager->EF_PrecacheResource(pLS, fDist, fTimeToReady, Flags);
    return false;
}

void CMetalRenderer::EF_EnableHeatVision(bool bEnable)
{
    if (m_shaderManager)
        m_shaderManager->EF_EnableHeatVision(bEnable);
}

bool CMetalRenderer::EF_GetHeatVision()
{
    if (m_shaderManager)
        return m_shaderManager->EF_GetHeatVision();
    return false;
}

void CMetalRenderer::EF_PolygonOffset(bool bEnable, float fFactor, float fUnits)
{
    if (m_shaderManager)
        m_shaderManager->EF_PolygonOffset(bEnable, fFactor, fUnits);
}

void CMetalRenderer::EF_AddPolyToScene3D(int Ef, int numPts, SColorVert* verts, CCObject* obj, int nFogID)
{
    if (m_shaderManager)
        m_shaderManager->EF_AddPolyToScene3D(Ef, numPts, verts, obj, nFogID);
}

CCObject* CMetalRenderer::EF_AddSpriteToScene(int Ef, int numPts, SColorVert* verts, CCObject* obj, byte* inds, int ninds, int nFogID)
{
    if (m_shaderManager)
        return m_shaderManager->EF_AddSpriteToScene(Ef, numPts, verts, obj, inds, ninds, nFogID);
    return nullptr;
}

void CMetalRenderer::EF_AddPolyToScene2D(int Ef, int numPts, SColorVert2D* verts)
{
    if (m_shaderManager)
        m_shaderManager->EF_AddPolyToScene2D(Ef, numPts, verts);
}

void CMetalRenderer::EF_AddPolyToScene2D(SShaderItem si, int nTempl, int numPts, SColorVert2D* verts)
{
    if (m_shaderManager)
        m_shaderManager->EF_AddPolyToScene2D(si, nTempl, numPts, verts);
}

IShader* CMetalRenderer::EF_LoadShader(const char* name, EShClass Class, int flags, uint64 nMaskGen)
{
    if (m_shaderManager)
        return m_shaderManager->EF_LoadShader(name, Class, flags, nMaskGen);
    return nullptr;
}

SShaderItem CMetalRenderer::EF_LoadShaderItem(const char* name, EShClass Class, bool bShare, const char* templName, int flags, SInputShaderResources* Res, uint64 nMaskGen)
{
    if (m_shaderManager)
        return m_shaderManager->EF_LoadShaderItem(name, Class, bShare, templName, flags, Res, nMaskGen);
    return SShaderItem();
}

bool CMetalRenderer::EF_ReloadFile(const char* szFileName)
{
    if (m_shaderManager)
        return m_shaderManager->EF_ReloadFile(szFileName);
    return false;
}

void CMetalRenderer::EF_ReloadShaderFiles(int nCategory)
{
    if (m_shaderManager)
        m_shaderManager->EF_ReloadShaderFiles(nCategory);
}

void CMetalRenderer::EF_ReloadTextures()
{
    if (m_shaderManager)
        m_shaderManager->EF_ReloadTextures();
}

IShader* CMetalRenderer::EF_CopyShader(IShader* ef)
{
    if (m_shaderManager)
        return m_shaderManager->EF_CopyShader(ef);
    return nullptr;
}

ITexPic* CMetalRenderer::EF_GetTextureByID(int Id)
{
    if (m_textureManager)
        return m_textureManager->EF_GetTextureByID(Id);
    return nullptr;
}

ITexPic* CMetalRenderer::EF_LoadTexture(const char* nameTex, uint flags, uint flags2, byte eTT, float fAmount1, float fAmount2, int Id, int BindId)
{
    if (m_textureManager)
        return m_textureManager->EF_LoadTexture(nameTex, flags, flags2, eTT, fAmount1, fAmount2, Id, BindId);
    return nullptr;
}

int CMetalRenderer::EF_LoadLightmap(const char* name)
{
    if (m_textureManager)
        return m_textureManager->EF_LoadLightmap(name);
    return 0;
}

bool CMetalRenderer::EF_ScanEnvironmentCM(const char* name, int size, Vec3& Pos)
{
    if (m_textureManager)
        return m_textureManager->EF_ScanEnvironmentCM(name, size, Pos);
    return false;
}

int CMetalRenderer::EF_ReadAllImgFiles(IShader* ef, SShaderTexUnit* tl, STexAnim* ta, char* name)
{
    if (m_textureManager)
        return m_textureManager->EF_ReadAllImgFiles(ef, tl, ta, name);
    return 0;
}

char** CMetalRenderer::EF_GetShadersForFile(const char* File, int num)
{
    if (m_shaderManager)
        return m_shaderManager->EF_GetShadersForFile(File, num);
    return nullptr;
}

SLightMaterial* CMetalRenderer::EF_GetLightMaterial(char* Str)
{
    if (m_shaderManager)
        return m_shaderManager->EF_GetLightMaterial(Str);
    return nullptr;
}

bool CMetalRenderer::EF_RegisterTemplate(int nTemplId, char* Name, bool bReplace)
{
    if (m_shaderManager)
        return m_shaderManager->EF_RegisterTemplate(nTemplId, Name, bReplace);
    return false;
}

void CMetalRenderer::EF_AddSplash(Vec3 Pos, eSplashType eST, float fForce, int Id)
{
    if (m_shaderManager)
        m_shaderManager->EF_AddSplash(Pos, eST, fForce, Id);
}

bool CMetalRenderer::EF_HideTemplate(const char* name)
{
    if (m_shaderManager)
        return m_shaderManager->EF_HideTemplate(name);
    return false;
}

bool CMetalRenderer::EF_UnhideTemplate(const char* name)
{
    if (m_shaderManager)
        return m_shaderManager->EF_UnhideTemplate(name);
    return false;
}

bool CMetalRenderer::EF_UnhideAllTemplates()
{
    if (m_shaderManager)
        return m_shaderManager->EF_UnhideAllTemplates();
    return false;
}

bool CMetalRenderer::EF_SetLightHole(Vec3 vPos, Vec3 vNormal, int idTex, float fScale, bool bAdditive)
{
    if (m_shaderManager)
        return m_shaderManager->EF_SetLightHole(vPos, vNormal, idTex, fScale, bAdditive);
    return false;
}

CRendElement* CMetalRenderer::EF_CreateRE(EDataType edt)
{
    if (m_shaderManager)
        return m_shaderManager->EF_CreateRE(edt);
    return nullptr;
}

void CMetalRenderer::EF_StartEf()
{
    if (m_shaderManager)
        m_shaderManager->EF_StartEf();
}

CCObject* CMetalRenderer::EF_GetObject(bool bTemp, int num)
{
    if (m_shaderManager)
        return m_shaderManager->EF_GetObject(bTemp, num);
    return nullptr;
}

void CMetalRenderer::EF_AddEf(int NumFog, CRendElement* re, IShader* ef, SRenderShaderResources* sr, CCObject* obj, int nTempl, IShader* efState, int nSort)
{
    if (m_shaderManager)
        m_shaderManager->EF_AddEf(NumFog, re, ef, sr, obj, nTempl, efState, nSort);
}

void CMetalRenderer::EF_EndEf3D(int nFlags)
{
    if (m_shaderManager)
        m_shaderManager->EF_EndEf3D(nFlags);
}

bool CMetalRenderer::EF_IsFakeDLight(CDLight* Source)
{
    if (m_shaderManager)
        return m_shaderManager->EF_IsFakeDLight(Source);
    return false;
}

void CMetalRenderer::EF_ADDDlight(CDLight* Source)
{
    if (m_shaderManager)
        m_shaderManager->EF_ADDDlight(Source);
}

void CMetalRenderer::EF_ClearLightsList()
{
    if (m_shaderManager)
        m_shaderManager->EF_ClearLightsList();
}

bool CMetalRenderer::EF_UpdateDLight(CDLight* pDL)
{
    if (m_shaderManager)
        return m_shaderManager->EF_UpdateDLight(pDL);
    return false;
}

void CMetalRenderer::EF_EndEf2D(bool bSort)
{
    if (m_shaderManager)
        m_shaderManager->EF_EndEf2D(bSort);
}

bool CMetalRenderer::EF_DrawEfForName(char* name, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    if (m_shaderManager)
        return m_shaderManager->EF_DrawEfForName(name, x, y, width, height, col, nTempl);
    return false;
}

bool CMetalRenderer::EF_DrawEfForNum(int num, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    if (m_shaderManager)
        return m_shaderManager->EF_DrawEfForNum(num, x, y, width, height, col, nTempl);
    return false;
}

bool CMetalRenderer::EF_DrawEf(IShader* ef, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    if (m_shaderManager)
        return m_shaderManager->EF_DrawEf(ef, x, y, width, height, col, nTempl);
    return false;
}

bool CMetalRenderer::EF_DrawEf(SShaderItem si, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    if (m_shaderManager)
        return m_shaderManager->EF_DrawEf(si, x, y, width, height, col, nTempl);
    return false;
}

bool CMetalRenderer::EF_DrawPartialEfForName(char* name, SVrect* vr, SVrect* pr, CFColor& col)
{
    if (m_shaderManager)
        return m_shaderManager->EF_DrawPartialEfForName(name, vr, pr, col);
    return false;
}

bool CMetalRenderer::EF_DrawPartialEfForNum(int num, SVrect* vr, SVrect* pr, CFColor& col)
{
    if (m_shaderManager)
        return m_shaderManager->EF_DrawPartialEfForNum(num, vr, pr, col);
    return false;
}

bool CMetalRenderer::EF_DrawPartialEf(IShader* ef, SVrect* vr, SVrect* pr, CFColor& col, float iwdt, float ihgt)
{
    if (m_shaderManager)
        return m_shaderManager->EF_DrawPartialEf(ef, vr, pr, col, iwdt, ihgt);
    return false;
}

void* CMetalRenderer::EF_Query(int Query, int Param)
{
    if (m_shaderManager)
        return m_shaderManager->EF_Query(Query, Param);
    return nullptr;
}

void CMetalRenderer::EF_ConstructEf(IShader* Ef)
{
    if (m_shaderManager)
        m_shaderManager->EF_ConstructEf(Ef);
}

void CMetalRenderer::EF_SetWorldColor(float r, float g, float b, float a)
{
    if (m_shaderManager)
        m_shaderManager->EF_SetWorldColor(r, g, b, a);
}

int CMetalRenderer::EF_RegisterFogVolume(float fMaxFogDist, float fFogLayerZ, CFColor color, int nIndex, bool bCaustics)
{
    if (m_shaderManager)
        return m_shaderManager->EF_RegisterFogVolume(fMaxFogDist, fFogLayerZ, color, nIndex, bCaustics);
    return 0;
}

// LeafBuffer delegation
CLeafBuffer* CMetalRenderer::CreateLeafBuffer(bool bDynamic, const char* szSource, class CIndexedMesh* pIndexedMesh)
{
    if (m_shaderManager)
        return m_shaderManager->CreateLeafBuffer(bDynamic, szSource, pIndexedMesh);
    return nullptr;
}

CLeafBuffer* CMetalRenderer::CreateLeafBufferInitialized(void* pVertBuffer, int nVertCount, int nVertFormat, ushort* pIndices, int nIndices, int nPrimetiveType, const char* szSource, EBufferType eBufType, int nMatInfoCount, int nClientTextureBindID, bool (*PrepareBufferCallback)(CLeafBuffer*, bool), void* CustomData, bool bOnlyVideoBuffer, bool bPrecache)
{
    if (m_shaderManager)
        return m_shaderManager->CreateLeafBufferInitialized(pVertBuffer, nVertCount, nVertFormat, pIndices, nIndices, nPrimetiveType, szSource, eBufType, nMatInfoCount, nClientTextureBindID, PrepareBufferCallback, CustomData, bOnlyVideoBuffer, bPrecache);
    return nullptr;
}

void CMetalRenderer::DeleteLeafBuffer(CLeafBuffer* pLBuffer)
{
    if (m_shaderManager)
        m_shaderManager->DeleteLeafBuffer(pLBuffer);
}

// Utility rendering delegation
void CMetalRenderer::WriteXY(CXFont* currfont, int x, int y, float xscale, float yscale, 
                            float r, float g, float b, float a, const char* message, ...)
{
    if (m_utilityRenderer)
        m_utilityRenderer->WriteXY(currfont, x, y, xscale, yscale, r, g, b, a, message);
}

void CMetalRenderer::Draw2dText(float posX, float posY, const char* szText, SDrawTextInfo& info)
{
    if (m_utilityRenderer)
        m_utilityRenderer->Draw2dText(posX, posY, szText, info);
}

void CMetalRenderer::Draw2dImage(float xpos, float ypos, float w, float h, int texture_id, 
                                float s0, float t0, float s1, float t1, 
                                float angle, float r, float g, float b, 
                                float a, float z)
{
    if (m_utilityRenderer)
        m_utilityRenderer->Draw2dImage(xpos, ypos, w, h, texture_id, s0, t0, s1, t1, angle, r, g, b, a, z);
}

void CMetalRenderer::DrawImage(float xpos, float ypos, float w, float h, int texture_id, 
                              float s0, float t0, float s1, float t1, float r, float g, float b, float a)
{
    if (m_utilityRenderer)
        m_utilityRenderer->DrawImage(xpos, ypos, w, h, texture_id, s0, t0, s1, t1, r, g, b, a);
}

int CMetalRenderer::SetPolygonMode(int mode)
{
    if (m_utilityRenderer)
        return m_utilityRenderer->SetPolygonMode(mode);
    return 0;
}

// Additional utility methods would be delegated similarly...

bool CMetalRenderer::InitializeManagers()
{
    // Initialize texture manager
    m_textureManager = std::make_unique<CMetalTextureManager>(this);
    if (!m_textureManager)
    {
        iLog->Log("Error: Failed to create Metal texture manager");
        return false;
    }
    
    // Initialize shader manager
    m_shaderManager = std::make_unique<CMetalShaderManager>(this, m_textureManager.get());
    if (!m_shaderManager)
    {
        iLog->Log("Error: Failed to create Metal shader manager");
        return false;
    }
    
    // Initialize utility renderer
    m_utilityRenderer = std::make_unique<CMetalUtilityRenderer>(this, m_textureManager.get(), m_shaderManager.get());
    if (!m_utilityRenderer)
    {
        iLog->Log("Error: Failed to create Metal utility renderer");
        return false;
    }
    
    return true;
}

void CMetalRenderer::ShutdownManagers()
{
    m_utilityRenderer.reset();
    m_shaderManager.reset();
    m_textureManager.reset();
}

// Export functions for the renderer
extern "C" {
    IRenderer* CreateRenderer(int argc, char* argv[], SCryRenderInterface* sp)
    {
        CMetalRenderer* renderer = new CMetalRenderer();
        if (renderer)
        {
            // Initialize the renderer
            if (renderer->Init(0, 0, 1024, 768, 32, 24, 8, false, nullptr, 0, 0, 0, false))
            {
                return renderer;
            }
            else
            {
                delete renderer;
                return nullptr;
            }
        }
        return nullptr;
    }
}

#endif // __APPLE__ && __MACH__