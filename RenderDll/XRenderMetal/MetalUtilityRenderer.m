////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalUtilityRenderer.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal utility renderer class
//               Handles debug, UI, and utility rendering methods
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_UTILITY_RENDERER_H
#define METAL_UTILITY_RENDERER_H

#if defined(__APPLE__) && defined(__MACH__)

#include <Metal/Metal.h>
#include <MetalKit/MetalKit.h>
#include <vector>
#include <list>

// Include CryEngine interfaces
#include "IRenderer.h"
#include "Cry_Math.h"

// Forward declarations
class CMetalBaseRenderer;
class CMetalTextureManager;
class CMetalShaderManager;

// Metal utility renderer class for debug/UI/utility methods
class CMetalUtilityRenderer
{
public:
    CMetalUtilityRenderer(CMetalBaseRenderer* renderer, 
                         CMetalTextureManager* textureManager,
                         CMetalShaderManager* shaderManager);
    virtual ~CMetalUtilityRenderer();

    // Text and UI Rendering
    void WriteXY(CXFont* currfont, int x, int y, float xscale, float yscale, 
                float r, float g, float b, float a, const char* message, ...);
    void Draw2dText(float posX, float posY, const char* szText, SDrawTextInfo& info);
    void Draw2dImage(float xpos, float ypos, float w, float h, int texture_id, 
                    float s0 = 0, float t0 = 0, float s1 = 1, float t1 = 1, 
                    float angle = 0, float r = 1, float g = 1, float b = 1, 
                    float a = 1, float z = 1);
    void DrawImage(float xpos, float ypos, float w, float h, int texture_id, 
                  float s0, float t0, float s1, float t1, float r, float g, float b, float a);
    int SetPolygonMode(int mode);
    
    // Debug Drawing
    void Draw2dLine(float x1, float y1, float x2, float y2);
    void SetLineWidth(float fWidth);
    void DrawLine(const Vec3& vPos1, const Vec3& vPos2);
    void DrawLineColor(const Vec3& vPos1, const CFColor& vColor1, 
                      const Vec3& vPos2, const CFColor& vColor2);
    void Graph(byte* g, int x, int y, int wdt, int hgt, int nC, int type, char* text, 
              CFColor& color, float fScale);
    void DrawBall(float x, float y, float z, float radius);
    void DrawBall(const Vec3& pos, float radius);
    void DrawPoint(float x, float y, float z, float fSize = 0.0f);
    void FlushTextMessages();
    void DrawObjSprites(list2<CStatObjInst*>* pList, float fMaxViewDist, 
                       CObjManager* pObjMan);
    void DrawQuad(const Vec3& right, const Vec3& up, const Vec3& origin, int nFlipMode = 0);
    void DrawQuad(float dy, float dx, float dz, float x, float y, float z);
    void ClearDepthBuffer();
    void ClearColorBuffer(const Vec3 vColor);
    void ReadFrameBuffer(unsigned char* pRGB, int nSizeX, int nSizeY, 
                        bool bBackBuffer, bool bRGBA, int nScaledX = -1, int nScaledY = -1);
    void SetFogColor(float* color);
    void TransformTextureMatrix(float x, float y, float angle, float scale);
    void ResetTextureMatrix();
    
    // Label and Text Drawing
    void DrawLabelImage(const Vec3& vPos, float fSize, int nTextureId);
    void DrawLabel(Vec3 pos, float font_size, const char* label_text, ...);
    void DrawLabelEx(Vec3 pos, float font_size, float* pfColor, bool bFixedSize, 
                    bool bCenter, const char* label_text, ...);
    void Draw2dLabel(float x, float y, float font_size, float* pfColor, bool bCenter, 
                    const char* label_text, ...);
    
    // Utility Methods
    void TextToScreen(float x, float y, const char* format, ...);
    void TextToScreenColor(int x, int y, float r, float g, float b, float a, 
                           const char* format, ...);
    void ResetToDefault();
    int GenerateAlphaGlowTexture(float k);
    void SetMaterialColor(float r, float g, float b, float a);
    int LoadAnimatedTexture(const char* format, const int nCount);
    void RemoveAnimatedTexture(AnimTexInfo* pInfo);
    AnimTexInfo* GetAnimTexInfoFromId(int nId);
    
    // Sprite and Object Rendering
    unsigned int MakeSprite(float object_scale, int tex_size, float angle, 
                           IStatObj* pStatObj, uchar* pTmpBuffer, uint def_tid);
    unsigned int Make3DSprite(int nTexSize, float fAngleStep, IStatObj* pStatObj);
    ShadowMapFrustum* MakeShadowMapFrustum(ShadowMapFrustum* lof, 
                                          ShadowMapLightSource* pLs, const Vec3& obj_pos, 
                                          list2<IStatObj*>* pStatObjects, int shadow_type);
    void Set2DMode(bool enable, int ortox, int ortoy);
    int ScreenToTexture();
    void SetTexClampMode(bool clamp);
    
    // File I/O
    void WriteDDS(byte* dat, int wdt, int hgt, int Size, const char* name, EImFormat eF, int NumMips);
    void WriteTGA(byte* dat, int wdt, int hgt, const char* name, int bits);
    void WriteJPG(byte* dat, int wdt, int hgt, char* name);
    
    // Additional utility methods
    void OnEntityDeleted(IEntityRender* pEntityRender);
    void SetGlobalShaderTemplateId(int nTemplateId);
    int GetGlobalShaderTemplateId();
    int EnumAAFormats(TArray<SAAFormat>& Formats, bool bReset);
    int CreateRenderTarget(int nWidth, int nHeight, ETEX_Format eTF);
    bool DestroyRenderTarget(int nHandle);
    bool SetRenderTarget(int nHandle);
    id<MTLTexture> GetRenderTargetDepthTexture(int nHandle) const;
    id<MTLTexture> GetRenderTargetColorTexture(int nHandle) const;
    float EF_GetWaterZElevation(float fX, float fY);
    id<MTLRenderPipelineState> GetSpritePSO() {
        if (!m_spritePipelineState) CreateSpritePipelineState();
        return m_spritePipelineState;
    }
    id<MTLRenderPipelineState> GetFontPipeline() {
        if (!m_fontPipelineState) CreateFontPipelineState();
        return m_fontPipelineState;
    }

protected:
    // Metal-specific utility rendering
    void CreateDebugPipelineState();
    void CreateTextPipelineState();
    void CreateSpritePipelineState();
    void CreateFontPipelineState();
    
    // Text rendering
    struct TextMessage
    {
        std::string text;
        Vec3 position;
        float fontSize;
        float color[4];
        bool fixedSize;
        bool center;
        bool is2D;
        int textureId;
    };
    
    std::list<TextMessage> m_textMessages;
    id<MTLRenderPipelineState> m_textPipelineState;
    id<MTLRenderPipelineState> m_debugPipelineState;
    id<MTLRenderPipelineState> m_spritePipelineState;
    id<MTLRenderPipelineState> m_solidColorPipelineState;
    id<MTLRenderPipelineState> m_fontPipelineState;
    
    // Current rendering state
    bool m_2DMode;
    int m_2DOriginX, m_2DOriginY;
    float m_lineWidth;
    int m_polygonMode;
    
    // Animated textures
    std::vector<AnimTexInfo*> m_animatedTextures;
    int m_nextAnimTextureId;
    
    // Global shader template
    int m_globalShaderTemplateId;
    
    struct RenderTargetInfo
    {
        id<MTLTexture> colorTexture;
        id<MTLTexture> depthTexture;
        int width;
        int height;
        ETEX_Format format;
        bool inUse;
        bool needsClear;
        
        RenderTargetInfo()
            : colorTexture(nil)
            , depthTexture(nil)
            , width(0)
            , height(0)
            , format(eTF_Unknown)
            , inUse(false)
            , needsClear(true)
        {}
    };
    
    std::vector<RenderTargetInfo> m_renderTargets;
    int m_nextRenderTargetId;
    
    // Reference to other managers
    CMetalBaseRenderer* m_renderer;
    CMetalTextureManager* m_textureManager;
    CMetalShaderManager* m_shaderManager;
    
    // Internal methods
    void RenderTextMessage(const TextMessage& message);
    void CreateTextVertexBuffer(const std::string& text, const Vec3& pos, 
                               float fontSize, const float* color, 
                               std::vector<float>& vertices);
    void DrawDebugPrimitive(MTLPrimitiveType type, const std::vector<Vec3>& vertices, 
                           const CFColor& color);
    void DrawSprite(const Vec3& pos, float size, int textureId, const CFColor& color);
    int AllocateRenderTargetId();
    void ReleaseRenderTargetId(int id);
};

#endif // __APPLE__ && __MACH__

#endif // METAL_UTILITY_RENDERER_H
