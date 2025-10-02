////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalUtilityRenderer.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal utility renderer implementation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalUtilityRenderer.h"
#include "MetalBaseRenderer.h"
#include "MetalTextureManager.h"
#include "MetalShaderManager.h"
#include "I3DEngine.h"
#include <Cocoa/Cocoa.h>

CMetalUtilityRenderer::CMetalUtilityRenderer(CMetalBaseRenderer* renderer, 
                                             CMetalTextureManager* textureManager,
                                             CMetalShaderManager* shaderManager)
    : m_renderer(renderer)
    , m_textureManager(textureManager)
    , m_shaderManager(shaderManager)
    , m_textPipelineState(nil)
    , m_debugPipelineState(nil)
    , m_spritePipelineState(nil)
    , m_2DMode(false)
    , m_2DOriginX(0)
    , m_2DOriginY(0)
    , m_lineWidth(1.0f)
    , m_polygonMode(0)
    , m_nextAnimTextureId(1)
    , m_globalShaderTemplateId(0)
    , m_nextRenderTargetId(1)
{
    // Initialize utility renderer
    CreateDebugPipelineState();
    CreateTextPipelineState();
    CreateSpritePipelineState();
}

CMetalUtilityRenderer::~CMetalUtilityRenderer()
{
    // Clean up resources
}

// Text and UI Rendering
void CMetalUtilityRenderer::WriteXY(CXFont* currfont, int x, int y, float xscale, float yscale, 
                                  float r, float g, float b, float a, const char* message, ...)
{
    if (!message)
        return;
        
    // Format message
    char buffer[1024];
    va_list args;
    va_start(args, message);
    vsnprintf(buffer, sizeof(buffer), message, args);
    va_end(args);
    
    // Create text message
    TextMessage textMsg;
    textMsg.text = buffer;
    textMsg.position = Vec3(x, y, 0);
    textMsg.fontSize = 1.0f;
    textMsg.color[0] = r;
    textMsg.color[1] = g;
    textMsg.color[2] = b;
    textMsg.color[3] = a;
    textMsg.fixedSize = false;
    textMsg.center = false;
    textMsg.is2D = true;
    textMsg.textureId = 0;
    
    m_textMessages.push_back(textMsg);
}

void CMetalUtilityRenderer::Draw2dText(float posX, float posY, const char* szText, SDrawTextInfo& info)
{
    if (!szText)
        return;
        
    // Create text message
    TextMessage textMsg;
    textMsg.text = szText;
    textMsg.position = Vec3(posX, posY, 0);
    textMsg.fontSize = 1.0f; // info.fSize not available
    textMsg.color[0] = info.color[0];
    textMsg.color[1] = info.color[1];
    textMsg.color[2] = info.color[2];
    textMsg.color[3] = info.color[3];
    textMsg.fixedSize = false; // info.bFixedSize not available
    textMsg.center = false; // info.bCenter not available
    textMsg.is2D = true;
    textMsg.textureId = 0;
    
    m_textMessages.push_back(textMsg);
}

void CMetalUtilityRenderer::Draw2dImage(float xpos, float ypos, float w, float h, int texture_id, 
                                       float s0, float t0, float s1, float t1, 
                                       float angle, float r, float g, float b, 
                                       float a, float z)
{
    if (!m_renderer || !m_renderer->m_renderEncoder)
        return;
        
    // Get texture from texture manager
    id<MTLTexture> texture = nil;
    if (m_textureManager && texture_id >= 0)
    {
        // TODO: Get texture from texture manager by ID
        // texture = m_textureManager->GetTexture(texture_id);
    }
    
    if (!texture)
        return;
        
    // Set up 2D rendering state
    if (m_spritePipelineState)
    {
        [m_renderer->m_renderEncoder setRenderPipelineState:m_spritePipelineState];
    }
    
    // Bind texture
    [m_renderer->m_renderEncoder setFragmentTexture:texture atIndex:0];
    
    // Create quad vertices for 2D image
    struct QuadVertex {
        float position[2];
        float texCoord[2];
        float color[4];
    };
    
    QuadVertex vertices[4] = {
        {{xpos, ypos}, {s0, t0}, {r, g, b, a}},
        {{xpos + w, ypos}, {s1, t0}, {r, g, b, a}},
        {{xpos, ypos + h}, {s0, t1}, {r, g, b, a}},
        {{xpos + w, ypos + h}, {s1, t1}, {r, g, b, a}}
    };
    
    // TODO: Create vertex buffer and draw quad
    // This would involve creating a vertex buffer with the quad data
    // and calling drawPrimitives on the render encoder
}

void CMetalUtilityRenderer::DrawImage(float xpos, float ypos, float w, float h, int texture_id, 
                                     float s0, float t0, float s1, float t1, float r, float g, float b, float a)
{
    // Draw image
    // This would queue the image for rendering
}

int CMetalUtilityRenderer::SetPolygonMode(int mode)
{
    int oldMode = m_polygonMode;
    m_polygonMode = mode;
    return oldMode;
}

// Debug Drawing
void CMetalUtilityRenderer::Draw2dLine(float x1, float y1, float x2, float y2)
{
    // Draw 2D line
    // This would queue the line for rendering
}

void CMetalUtilityRenderer::SetLineWidth(float fWidth)
{
    m_lineWidth = fWidth;
}

void CMetalUtilityRenderer::DrawLine(const Vec3& vPos1, const Vec3& vPos2)
{
    // Draw 3D line
    // This would queue the line for rendering
}

void CMetalUtilityRenderer::DrawLineColor(const Vec3& vPos1, const CFColor& vColor1, 
                                         const Vec3& vPos2, const CFColor& vColor2)
{
    // Draw colored line
    // This would queue the colored line for rendering
}

void CMetalUtilityRenderer::Graph(byte* g, int x, int y, int wdt, int hgt, int nC, int type, char* text, CFColor& color, float fScale)
{
    // Draw graph
    // This would queue the graph for rendering
}

void CMetalUtilityRenderer::DrawBall(float x, float y, float z, float radius)
{
    // Draw ball
    // This would queue the ball for rendering
}

void CMetalUtilityRenderer::DrawBall(const Vec3& pos, float radius)
{
    DrawBall(pos.x, pos.y, pos.z, radius);
}

void CMetalUtilityRenderer::DrawPoint(float x, float y, float z, float fSize)
{
    // Draw point
    // This would queue the point for rendering
}

void CMetalUtilityRenderer::FlushTextMessages()
{
    // Render all queued text messages
    for (const auto& message : m_textMessages)
    {
        RenderTextMessage(message);
    }
    m_textMessages.clear();
}

void CMetalUtilityRenderer::DrawObjSprites(list2<CStatObjInst*>* pList, float fMaxViewDist, CObjManager* pObjMan)
{
    if (!pList)
        return;
        
    // Draw object sprites
    // This would queue the sprites for rendering
}

void CMetalUtilityRenderer::DrawQuad(const Vec3& right, const Vec3& up, const Vec3& origin, int nFlipMode)
{
    // Draw quad
    // This would queue the quad for rendering
}

void CMetalUtilityRenderer::DrawQuad(float dy, float dx, float dz, float x, float y, float z)
{
    // Draw quad with dimensions
    // This would queue the quad for rendering
}

void CMetalUtilityRenderer::ClearDepthBuffer()
{
    // Clear depth buffer
    // This would be handled by the Metal render pass descriptor
}

void CMetalUtilityRenderer::ClearColorBuffer(const Vec3 vColor)
{
    // Clear color buffer
    // This would be handled by the Metal render pass descriptor
}

void CMetalUtilityRenderer::ReadFrameBuffer(unsigned char* pRGB, int nSizeX, int nSizeY, 
                                          bool bBackBuffer, bool bRGBA, int nScaledX, int nScaledY)
{
    if (!pRGB)
        return;
        
    // Read frame buffer
    // This would read from the Metal drawable
}

void CMetalUtilityRenderer::SetFogColor(float* color)
{
    if (!color)
        return;
        
    // Set fog color
    // This would be handled by the Metal render pipeline state
}

void CMetalUtilityRenderer::TransformTextureMatrix(float x, float y, float angle, float scale)
{
    // Transform texture matrix
    // This would be handled by the Metal render pipeline state
}

void CMetalUtilityRenderer::ResetTextureMatrix()
{
    // Reset texture matrix
    // This would be handled by the Metal render pipeline state
}

// Label and Text Drawing
void CMetalUtilityRenderer::DrawLabelImage(const Vec3& vPos, float fSize, int nTextureId)
{
    // Draw label image
    // This would queue the label for rendering
}

void CMetalUtilityRenderer::DrawLabel(Vec3 pos, float font_size, const char* label_text, ...)
{
    if (!label_text)
        return;
        
    // Format label text
    char buffer[1024];
    va_list args;
    va_start(args, label_text);
    vsnprintf(buffer, sizeof(buffer), label_text, args);
    va_end(args);
    
    // Create text message
    TextMessage textMsg;
    textMsg.text = buffer;
    textMsg.position = pos;
    textMsg.fontSize = font_size;
    textMsg.color[0] = 1.0f;
    textMsg.color[1] = 1.0f;
    textMsg.color[2] = 1.0f;
    textMsg.color[3] = 1.0f;
    textMsg.fixedSize = false;
    textMsg.center = false;
    textMsg.is2D = false;
    textMsg.textureId = 0;
    
    m_textMessages.push_back(textMsg);
}

void CMetalUtilityRenderer::DrawLabelEx(Vec3 pos, float font_size, float* pfColor, bool bFixedSize, bool bCenter, const char* label_text, ...)
{
    if (!label_text)
        return;
        
    // Format label text
    char buffer[1024];
    va_list args;
    va_start(args, label_text);
    vsnprintf(buffer, sizeof(buffer), label_text, args);
    va_end(args);
    
    // Create text message
    TextMessage textMsg;
    textMsg.text = buffer;
    textMsg.position = pos;
    textMsg.fontSize = font_size;
    textMsg.color[0] = pfColor ? pfColor[0] : 1.0f;
    textMsg.color[1] = pfColor ? pfColor[1] : 1.0f;
    textMsg.color[2] = pfColor ? pfColor[2] : 1.0f;
    textMsg.color[3] = pfColor ? pfColor[3] : 1.0f;
    textMsg.fixedSize = bFixedSize;
    textMsg.center = bCenter;
    textMsg.is2D = false;
    textMsg.textureId = 0;
    
    m_textMessages.push_back(textMsg);
}

void CMetalUtilityRenderer::Draw2dLabel(float x, float y, float font_size, float* pfColor, bool bCenter, const char* label_text, ...)
{
    if (!label_text)
        return;
        
    // Format label text
    char buffer[1024];
    va_list args;
    va_start(args, label_text);
    vsnprintf(buffer, sizeof(buffer), label_text, args);
    va_end(args);
    
    // Create text message
    TextMessage textMsg;
    textMsg.text = buffer;
    textMsg.position = Vec3(x, y, 0);
    textMsg.fontSize = font_size;
    textMsg.color[0] = pfColor ? pfColor[0] : 1.0f;
    textMsg.color[1] = pfColor ? pfColor[1] : 1.0f;
    textMsg.color[2] = pfColor ? pfColor[2] : 1.0f;
    textMsg.color[3] = pfColor ? pfColor[3] : 1.0f;
    textMsg.fixedSize = false;
    textMsg.center = bCenter;
    textMsg.is2D = true;
    textMsg.textureId = 0;
    
    m_textMessages.push_back(textMsg);
}

// Utility Methods
void CMetalUtilityRenderer::TextToScreen(float x, float y, const char* format, ...)
{
    if (!format)
        return;
        
    // Format text
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    // Create text message
    TextMessage textMsg;
    textMsg.text = buffer;
    textMsg.position = Vec3(x, y, 0);
    textMsg.fontSize = 1.0f;
    textMsg.color[0] = 1.0f;
    textMsg.color[1] = 1.0f;
    textMsg.color[2] = 1.0f;
    textMsg.color[3] = 1.0f;
    textMsg.fixedSize = false;
    textMsg.center = false;
    textMsg.is2D = true;
    textMsg.textureId = 0;
    
    m_textMessages.push_back(textMsg);
}

void CMetalUtilityRenderer::TextToScreenColor(int x, int y, float r, float g, float b, float a, const char* format, ...)
{
    if (!format)
        return;
        
    // Format text
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    // Create text message
    TextMessage textMsg;
    textMsg.text = buffer;
    textMsg.position = Vec3(x, y, 0);
    textMsg.fontSize = 1.0f;
    textMsg.color[0] = r;
    textMsg.color[1] = g;
    textMsg.color[2] = b;
    textMsg.color[3] = a;
    textMsg.fixedSize = false;
    textMsg.center = false;
    textMsg.is2D = true;
    textMsg.textureId = 0;
    
    m_textMessages.push_back(textMsg);
}

void CMetalUtilityRenderer::ResetToDefault()
{
    // Reset utility renderer to default state
    m_2DMode = false;
    m_2DOriginX = 0;
    m_2DOriginY = 0;
    m_lineWidth = 1.0f;
    m_polygonMode = 0;
}

int CMetalUtilityRenderer::GenerateAlphaGlowTexture(float k)
{
    // Generate alpha glow texture
    return 0;
}

void CMetalUtilityRenderer::SetMaterialColor(float r, float g, float b, float a)
{
    // Set material color
    // This would be handled by the Metal render pipeline state
}

int CMetalUtilityRenderer::LoadAnimatedTexture(const char* format, const int nCount)
{
    if (!format)
        return 0;
        
    // Load animated texture
    return 0;
}

void CMetalUtilityRenderer::RemoveAnimatedTexture(AnimTexInfo* pInfo)
{
    if (!pInfo)
        return;
        
    // Remove animated texture
}

AnimTexInfo* CMetalUtilityRenderer::GetAnimTexInfoFromId(int nId)
{
    // Get animated texture info by ID
    return nullptr;
}

// Sprite and Object Rendering
unsigned int CMetalUtilityRenderer::MakeSprite(float object_scale, int tex_size, float angle, 
                                               IStatObj* pStatObj, uchar* pTmpBuffer, uint def_tid)
{
    // Make sprite
    return 0;
}

unsigned int CMetalUtilityRenderer::Make3DSprite(int nTexSize, float fAngleStep, IStatObj* pStatObj)
{
    // Make 3D sprite
    return 0;
}

ShadowMapFrustum* CMetalUtilityRenderer::MakeShadowMapFrustum(ShadowMapFrustum* lof, 
                                                            ShadowMapLightSource* pLs, const Vec3& obj_pos, 
                                                            list2<IStatObj*>* pStatObjects, int shadow_type)
{
    // Make shadow map frustum
    return nullptr;
}

void CMetalUtilityRenderer::Set2DMode(bool enable, int ortox, int ortoy)
{
    m_2DMode = enable;
    m_2DOriginX = ortox;
    m_2DOriginY = ortoy;
}

int CMetalUtilityRenderer::ScreenToTexture()
{
    // Convert screen to texture
    return 0;
}

void CMetalUtilityRenderer::SetTexClampMode(bool clamp)
{
    // Set texture clamp mode
    // This would be handled by the Metal render pipeline state
}

// File I/O
void CMetalUtilityRenderer::WriteDDS(byte* dat, int wdt, int hgt, int Size, const char* name, EImFormat eF, int NumMips)
{
    if (!dat || !name)
        return;
        
    // Write DDS file
}

void CMetalUtilityRenderer::WriteTGA(byte* dat, int wdt, int hgt, const char* name, int bits)
{
    if (!dat || !name)
        return;
        
    // Write TGA file
}

void CMetalUtilityRenderer::WriteJPG(byte* dat, int wdt, int hgt, char* name)
{
    if (!dat || !name)
        return;
        
    // Write JPG file
}

// Additional utility methods
void CMetalUtilityRenderer::OnEntityDeleted(IEntityRender* pEntityRender)
{
    if (!pEntityRender)
        return;
        
    // Handle entity deletion
}

void CMetalUtilityRenderer::SetGlobalShaderTemplateId(int nTemplateId)
{
    m_globalShaderTemplateId = nTemplateId;
}

int CMetalUtilityRenderer::GetGlobalShaderTemplateId()
{
    return m_globalShaderTemplateId;
}

int CMetalUtilityRenderer::EnumAAFormats(TArray<SAAFormat>& Formats, bool bReset)
{
    if (bReset)
        Formats.Free();
        
    // Add Metal anti-aliasing formats
    SAAFormat format;
    format.nSamples = 2;
    format.nQuality = 0;
    Formats.AddElem(format);
    
    format.nSamples = 4;
    format.nQuality = 0;
    Formats.AddElem(format);
    
    format.nSamples = 8;
    format.nQuality = 0;
    Formats.AddElem(format);
    
    return Formats.Num();
}

int CMetalUtilityRenderer::CreateRenderTarget(int nWidth, int nHeight, ETEX_Format eTF)
{
    if (nWidth <= 0 || nHeight <= 0)
        return 0;
        
    // Create render target
    int renderTargetId = AllocateRenderTargetId();
    if (renderTargetId == -1)
        return 0;
        
    // Create Metal texture for render target
    // This would need to be implemented
    
    return renderTargetId;
}

bool CMetalUtilityRenderer::DestroyRenderTarget(int nHandle)
{
    if (nHandle < 0 || nHandle >= m_renderTargets.size())
        return false;
        
    // Destroy render target
    m_renderTargets[nHandle] = nil;
    ReleaseRenderTargetId(nHandle);
    return true;
}

bool CMetalUtilityRenderer::SetRenderTarget(int nHandle)
{
    if (nHandle < 0 || nHandle >= m_renderTargets.size())
        return false;
        
    // Set render target
    // This would be handled by the Metal render pass descriptor
    return true;
}

float CMetalUtilityRenderer::EF_GetWaterZElevation(float fX, float fY)
{
    // Get water Z elevation
    return 0.0f;
}

// Protected methods
void CMetalUtilityRenderer::CreateDebugPipelineState()
{
    if (!m_renderer || !m_renderer->m_device)
        return;
        
    // Create debug pipeline state
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    
    NSError* error = nil;
    m_debugPipelineState = [m_renderer->m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!m_debugPipelineState)
    {
        printf("Error: Failed to create debug pipeline state: %s", error ? [[error localizedDescription] UTF8String] : "Unknown error");
    }
}

void CMetalUtilityRenderer::CreateTextPipelineState()
{
    if (!m_renderer || !m_renderer->m_device)
        return;
        
    // Create text pipeline state
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    
    NSError* error = nil;
    m_textPipelineState = [m_renderer->m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!m_textPipelineState)
    {
        printf("Error: Failed to create text pipeline state: %s", error ? [[error localizedDescription] UTF8String] : "Unknown error");
    }
}

void CMetalUtilityRenderer::CreateSpritePipelineState()
{
    if (!m_renderer || !m_renderer->m_device)
        return;
        
    // Create sprite pipeline state
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    
    NSError* error = nil;
    m_spritePipelineState = [m_renderer->m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!m_spritePipelineState)
    {
        printf("Error: Failed to create sprite pipeline state: %s", error ? [[error localizedDescription] UTF8String] : "Unknown error");
    }
}

void CMetalUtilityRenderer::RenderTextMessage(const TextMessage& message)
{
    // Render text message
    // This would queue the text for rendering using the text pipeline state
}

void CMetalUtilityRenderer::CreateTextVertexBuffer(const std::string& text, const Vec3& pos, 
                                                  float fontSize, const float* color, 
                                                  std::vector<float>& vertices)
{
    // Create vertex buffer for text rendering
    // This would generate vertices for the text
}

void CMetalUtilityRenderer::DrawDebugPrimitive(MTLPrimitiveType type, const std::vector<Vec3>& vertices, 
                                             const CFColor& color)
{
    // Draw debug primitive
    // This would queue the primitive for rendering using the debug pipeline state
}

void CMetalUtilityRenderer::DrawSprite(const Vec3& pos, float size, int textureId, const CFColor& color)
{
    // Draw sprite
    // This would queue the sprite for rendering using the sprite pipeline state
}

int CMetalUtilityRenderer::AllocateRenderTargetId()
{
    return m_nextRenderTargetId++;
}

void CMetalUtilityRenderer::ReleaseRenderTargetId(int id)
{
    // Release render target ID for reuse
}

#endif // __APPLE__ && __MACH__
