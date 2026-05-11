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

#include "MetalUtilityRenderer.m"
#include "MetalBaseRenderer.m"
#include "MetalRenderer.m"
#include "MetalTextureManager.m"
#include "MetalShaderManager.m"
#include "MetalDrawDiag.h"
#include "I3DEngine.h"
#include "IFont.h"
#include <Cocoa/Cocoa.h>
#include <limits>
#include <cstdlib>

extern ISystem* iSystem;

#ifdef max
#undef max
#endif
#ifdef min
#undef min
#endif

namespace
{
static MTLPixelFormat ResolveRenderTargetFormat(ETEX_Format format)
{
    switch (format)
    {
        case eTF_8888:
        case eTF_RGBA:
        case eTF_0888:
        case eTF_4444:
        case eTF_1555:
        case eTF_0555:
        case eTF_0565:
        case eTF_RGB8:
            return MTLPixelFormatRGBA8Unorm;
        case eTF_DXT1:
        case eTF_DXT3:
        case eTF_DXT5:
            return MTLPixelFormatRGBA8Unorm;
        case eTF_SIGNED_HILO16:
            return MTLPixelFormatRG16Snorm;
        case eTF_SIGNED_HILO8:
        case eTF_V8U8:
            return MTLPixelFormatRG8Snorm;
        case eTF_SIGNED_RGB8:
            return MTLPixelFormatRGBA8Snorm;
        case eTF_V16U16:
            return MTLPixelFormatRG16Snorm;
        case eTF_0088:
            return MTLPixelFormatRG8Unorm;
        case eTF_8000:
            return MTLPixelFormatR8Unorm;
        case eTF_DEPTH:
            return MTLPixelFormatDepth32Float_Stencil8;
        default:
            return MTLPixelFormatBGRA8Unorm;
    }
}
}

CMetalUtilityRenderer::CMetalUtilityRenderer(CMetalBaseRenderer* renderer, 
                                             CMetalTextureManager* textureManager,
                                             CMetalShaderManager* shaderManager)
    : m_renderer(renderer)
    , m_textureManager(textureManager)
    , m_shaderManager(shaderManager)
    , m_textPipelineState(nil)
    , m_debugPipelineState(nil)
    , m_spritePipelineState(nil)
    , m_solidColorPipelineState(nil)
    , m_fontPipelineState(nil)
    , m_2DMode(false)
    , m_2DOriginX(0)
    , m_2DOriginY(0)
    , m_lineWidth(1.0f)
    , m_polygonMode(0)
    , m_nextAnimTextureId(1)
    , m_globalShaderTemplateId(0)
    , m_nextRenderTargetId(1)
{
    assert(renderer != nullptr && "CMetalUtilityRenderer: renderer cannot be null");
    assert(textureManager != nullptr && "CMetalUtilityRenderer: textureManager cannot be null");
    assert(shaderManager != nullptr && "CMetalUtilityRenderer: shaderManager cannot be null");
    assert(renderer->m_device != nil && "CMetalUtilityRenderer: renderer must have valid Metal device");
    
    iLog->Log("CMetalUtilityRenderer: Initializing...\n");
    
    // Initialize utility renderer
    // Note: Sprite pipeline state creation is deferred until first use
    // to avoid crashes if shaders aren't loaded yet
    // CreateSpritePipelineState will be called lazily in Draw2dImage if needed
    
    iLog->Log("CMetalUtilityRenderer: Initialization complete (sprite pipeline deferred)\n");
}

CMetalUtilityRenderer::~CMetalUtilityRenderer()
{
    // Clean up resources
}

// Text and UI Rendering
void CMetalUtilityRenderer::WriteXY(CXFont* currfont, int x, int y, float xscale, float yscale, 
                                  float r, float g, float b, float a, const char* message, ...)
{
    assert(message != nullptr && "WriteXY: message cannot be null");
    assert(xscale > 0.0f && "WriteXY: xscale must be positive");
    assert(yscale > 0.0f && "WriteXY: yscale must be positive");
    assert(r >= 0.0f && r <= 1.0f && "WriteXY: red component must be in range [0,1]");
    assert(g >= 0.0f && g <= 1.0f && "WriteXY: green component must be in range [0,1]");
    assert(b >= 0.0f && b <= 1.0f && "WriteXY: blue component must be in range [0,1]");
    assert(a >= 0.0f && a <= 1.0f && "WriteXY: alpha component must be in range [0,1]");
    
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
    assert(szText != nullptr && "Draw2dText: text cannot be null");
    assert(info.color[0] >= 0.0f && info.color[0] <= 1.0f && "Draw2dText: red component must be in range [0,1]");
    assert(info.color[1] >= 0.0f && info.color[1] <= 1.0f && "Draw2dText: green component must be in range [0,1]");
    assert(info.color[2] >= 0.0f && info.color[2] <= 1.0f && "Draw2dText: blue component must be in range [0,1]");
    assert(info.color[3] >= 0.0f && info.color[3] <= 1.0f && "Draw2dText: alpha component must be in range [0,1]");
    
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
    assert(m_renderer != nullptr && "Draw2dImage: utility renderer has no back-reference to CMetalRenderer");
    if (!m_renderer)
        return;
    if (!m_renderer->TryEnsureSwapchainRenderEncoderFor2D())
        return;

    if (w <= 0.0f || h <= 0.0f)
        return;

    r = std::max(0.0f, std::min(1.0f, r));
    g = std::max(0.0f, std::min(1.0f, g));
    b = std::max(0.0f, std::min(1.0f, b));
    a = std::max(0.0f, std::min(1.0f, a));
    
    // Lazy initialization: create sprite pipeline states on first use
    if (!m_spritePipelineState || !m_solidColorPipelineState)
    {
        CreateSpritePipelineState();
        assert(m_spritePipelineState != nil && "Draw2dImage: sprite pipeline state failed to initialize");
        if (!m_spritePipelineState)
            return;
        assert(m_solidColorPipelineState != nil && "Draw2dImage: solid-color pipeline state failed to initialize");
        if (!m_solidColorPipelineState)
            return;
    }
        
    // Get texture from texture manager (only if texture_id is valid)
    id<MTLTexture> texture = nil;
    bool hasTexture = false;
    if (m_textureManager && texture_id > 0)
    {
        const auto* texInfo = m_textureManager->GetTextureInfo(texture_id);
        if (texInfo && texInfo->metalTexture)
        {
            texture = texInfo->metalTexture;
            hasTexture = true;
        }
    }
    
    float screenWidth = static_cast<float>(m_renderer->GetWidth());
    float screenHeight = static_cast<float>(m_renderer->GetHeight());
    
    if (screenWidth <= 0 || screenHeight <= 0)
    {
        assert(false && "Draw2dImage: renderer reports zero screen dimensions — window not yet ready");
        return;
    }

    xpos = m_renderer->ScaleCoordX(xpos);
    w = m_renderer->ScaleCoordX(w);
    ypos = m_renderer->ScaleCoordY(ypos);
    h = m_renderer->ScaleCoordY(h);
    
    // Convert to NDC
    // Input: pixel coordinates where (0,0) is top-left, (screenWidth, screenHeight) is bottom-right
    // Output: NDC where (-1,-1) is bottom-left, (1,1) is top-right
    float x0_ndc = (xpos / screenWidth) * 2.0f - 1.0f;
    float y0_ndc = 1.0f - (ypos / screenHeight) * 2.0f;  // Flip Y: top becomes +1
    float x1_ndc = ((xpos + w) / screenWidth) * 2.0f - 1.0f;
    float y1_ndc = 1.0f - ((ypos + h) / screenHeight) * 2.0f;  // Flip Y: bottom becomes -1
    
    // Create quad vertices for 2D image (triangle strip order)
    // Triangle strip order for quad: v0-v1-v2 creates first triangle, then v2-v1-v3 creates second
    // Correct order: top-left, bottom-left, top-right, bottom-right
    struct QuadVertex {
        float position[2];
        float texCoord[2];
        float color[4];
    };
    
    // Metal V is bottom-up; CryEngine UI assumes top-down — flip V
    const float texTop = 1.0f - t0;
    const float texBottom = 1.0f - t1;

    // Rotate quad corners around centre when angle != 0 (angle is in degrees)
    float cx = (x0_ndc + x1_ndc) * 0.5f;
    float cy = (y0_ndc + y1_ndc) * 0.5f;
    float cosA = 1.0f, sinA = 0.0f;
    if (angle != 0.0f) {
        const float rad = angle * (3.14159265f / 180.0f);
        cosA = cosf(rad);
        sinA = sinf(rad);
    }
    auto rotateNDC = [&](float px, float py, float& rx, float& ry) {
        float lx = px - cx, ly = py - cy;
        rx = cx + lx * cosA - ly * sinA;
        ry = cy + lx * sinA + ly * cosA;
    };
    float rx0, ry0, rx1, ry1, rx2, ry2, rx3, ry3;
    rotateNDC(x0_ndc, y0_ndc, rx0, ry0);
    rotateNDC(x0_ndc, y1_ndc, rx1, ry1);
    rotateNDC(x1_ndc, y0_ndc, rx2, ry2);
    rotateNDC(x1_ndc, y1_ndc, rx3, ry3);

    QuadVertex vertices[4] = {
        {{rx0, ry0}, {s0, texTop},    {r, g, b, a}},  // v0: Top-left
        {{rx1, ry1}, {s0, texBottom}, {r, g, b, a}},  // v1: Bottom-left
        {{rx2, ry2}, {s1, texTop},    {r, g, b, a}},  // v2: Top-right
        {{rx3, ry3}, {s1, texBottom}, {r, g, b, a}}   // v3: Bottom-right
    };
    
    // Create temporary vertex buffer for this quad
    id<MTLBuffer> vertexBuffer = [m_renderer->m_device newBufferWithBytes:vertices
                                                                    length:sizeof(vertices)
                                                                   options:MTLResourceStorageModeShared];
    
    assert(vertexBuffer != nil && "Draw2dImage: failed to allocate per-quad vertex buffer");
    if (!vertexBuffer)
        return;
    
    // Set vertex buffer
    [m_renderer->m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:kMetalVertexStream_General];
    [m_renderer->m_renderEncoder setVertexBuffer:nil offset:0 atIndex:kMetalVertexStream_Tangents];
    
    // Use appropriate pipeline state based on whether we have a texture
    if (hasTexture && texture)
    {
        // Set up 2D rendering state with texture
        if (m_spritePipelineState)
        {
            [m_renderer->m_renderEncoder setRenderPipelineState:m_spritePipelineState];
        }
        
        // Bind texture and sampler
        [m_renderer->m_renderEncoder setFragmentTexture:texture atIndex:0];
        if (m_textureManager)
            m_textureManager->BindDefaultSampler(0);
    }
    else
    {
        // Solid color rendering (no texture) — uses sprite_fragment_notex which needs no texture or sampler
        [m_renderer->m_renderEncoder setRenderPipelineState:m_solidColorPipelineState];
    }
    
    [m_renderer->m_renderEncoder setCullMode:MTLCullModeNone];

    NSUInteger vpW = (NSUInteger)m_renderer->GetWidth();
    NSUInteger vpH = (NSUInteger)m_renderer->GetHeight();
    if (vpW > 0 && vpH > 0) {
        MTLScissorRect fullViewport = {0, 0, vpW, vpH};
        [m_renderer->m_renderEncoder setScissorRect:fullViewport];
    }

    MetalDrawDiag::OnDrawCall("Utility::DrawImage", m_renderer->m_renderEncoder,
                              nil, MTLPrimitiveTypeTriangleStrip, 4, 0);
    [m_renderer->m_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                                    vertexStart:0
                                    vertexCount:4];
    [vertexBuffer release];
}

void CMetalUtilityRenderer::DrawImage(float xpos, float ypos, float w, float h, int texture_id, 
                                     float s0, float t0, float s1, float t1, float r, float g, float b, float a)
{
    assert(w > 0.0f && "DrawImage: width must be positive");
    assert(h > 0.0f && "DrawImage: height must be positive");
    assert(s0 >= 0.0f && s0 <= 1.0f && "DrawImage: s0 must be in range [0,1]");
    assert(t0 >= 0.0f && t0 <= 1.0f && "DrawImage: t0 must be in range [0,1]");
    assert(s1 >= 0.0f && s1 <= 1.0f && "DrawImage: s1 must be in range [0,1]");
    assert(t1 >= 0.0f && t1 <= 1.0f && "DrawImage: t1 must be in range [0,1]");
    assert(r >= 0.0f && r <= 1.0f && "DrawImage: red component must be in range [0,1]");
    assert(g >= 0.0f && g <= 1.0f && "DrawImage: green component must be in range [0,1]");
    assert(b >= 0.0f && b <= 1.0f && "DrawImage: blue component must be in range [0,1]");
    assert(a >= 0.0f && a <= 1.0f && "DrawImage: alpha component must be in range [0,1]");
    
    // DrawImage is a simplified version of Draw2dImage (no angle or z parameter)
    // texture_id can be -1 for solid color quads
    Draw2dImage(xpos, ypos, w, h, texture_id, s0, t0, s1, t1, 0.0f, r, g, b, a, 1.0f);
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
    CMetalRenderer* r = checked_cast<CMetalRenderer>(gRenDev);
    if (r) r->QueueDebugLine(vPos1, vPos2, CFColor(1,1,1,1), 0);
}

void CMetalUtilityRenderer::DrawLineColor(const Vec3& vPos1, const CFColor& vColor1, 
                                         const Vec3& vPos2, const CFColor& vColor2)
{
    CMetalRenderer* r = checked_cast<CMetalRenderer>(gRenDev);
    if (!r) return;
    // QueueDebugLine is single-colour; approximate gradient via two half-segments
    Vec3 mid = (vPos1 + vPos2) * 0.5f;
    CFColor midColor(
        (vColor1.r + vColor2.r) * 0.5f,
        (vColor1.g + vColor2.g) * 0.5f,
        (vColor1.b + vColor2.b) * 0.5f,
        (vColor1.a + vColor2.a) * 0.5f);
    r->QueueDebugLine(vPos1, mid, vColor1, 0);
    r->QueueDebugLine(mid,  vPos2, vColor2,  0);
}

void CMetalUtilityRenderer::Graph(byte* g, int x, int y, int wdt, int hgt, int nC, int type, char* text, CFColor& color, float fScale)
{
    // Draw graph
    // This would queue the graph for rendering
}

void CMetalUtilityRenderer::DrawBall(float x, float y, float z, float radius)
{
    CMetalRenderer* r = checked_cast<CMetalRenderer>(gRenDev);
    if (!r) return;
    Vec3 center(x, y, z);
    Vec3 mins(x - radius, y - radius, z - radius);
    Vec3 maxs(x + radius, y + radius, z + radius);
    r->QueueDebugSphere(mins, maxs, CFColor(1, 1, 0, 1), /*solid=*/false);
}

void CMetalUtilityRenderer::DrawBall(const Vec3& pos, float radius)
{
    DrawBall(pos.x, pos.y, pos.z, radius);
}

void CMetalUtilityRenderer::DrawPoint(float x, float y, float z, float fSize)
{
    CMetalRenderer* r = checked_cast<CMetalRenderer>(gRenDev);
    if (r) r->QueueDebugPoint(Vec3(x, y, z), CFColor(1, 1, 1, 1), 0);
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
    assert(pRGB != nullptr && "ReadFrameBuffer: output buffer cannot be null");
    assert(nSizeX > 0 && "ReadFrameBuffer: width must be positive");
    assert(nSizeY > 0 && "ReadFrameBuffer: height must be positive");
    
    if (!pRGB || nSizeX <= 0 || nSizeY <= 0) return;
    if (!m_renderer || !m_renderer->m_device) return;

    m_renderer->ReleaseRenderEncoder();

    // Use the current frame's already-acquired drawable — do not call nextDrawable
    id<MTLTexture> srcTex = m_renderer->m_currentDrawable
                                ? m_renderer->m_currentDrawable.texture
                                : nil;
    if (!srcTex) return;

    int srcW = (int)srcTex.width;
    int srcH = (int)srcTex.height;
    int dstW = (nScaledX > 0) ? nScaledX : nSizeX;
    int dstH = (nScaledY > 0) ? nScaledY : nSizeY;

    // Create a readback buffer (BGRA8, 4 bytes/pixel)
    NSUInteger bytesPerRow = (NSUInteger)srcW * 4;
    NSUInteger totalBytes  = bytesPerRow * (NSUInteger)srcH;
    id<MTLBuffer> readback = [m_renderer->m_device
        newBufferWithLength:totalBytes
                   options:MTLResourceStorageModeShared];
    if (!readback) return;

    id<MTLCommandBuffer> cb = [m_renderer->m_commandQueue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit copyFromTexture:srcTex
             sourceSlice:0
             sourceLevel:0
            sourceOrigin:MTLOriginMake(0, 0, 0)
              sourceSize:MTLSizeMake(srcW, srcH, 1)
                toBuffer:readback
       destinationOffset:0
  destinationBytesPerRow:bytesPerRow
destinationBytesPerImage:totalBytes];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];

    // Copy BGRA → RGB(A) into output buffer, cropped/scaled if needed
    const unsigned char* src = (const unsigned char*)readback.contents;
    const int copyW = (srcW < dstW) ? srcW : dstW;
    const int copyH = (srcH < dstH) ? srcH : dstH;
    const int channels = bRGBA ? 4 : 3;

    for (int row = 0; row < copyH; ++row)
    {
        const unsigned char* srcRow = src + row * bytesPerRow;
        unsigned char* dstRow = pRGB + row * dstW * channels;
        for (int col = 0; col < copyW; ++col)
        {
            // Metal BGRA → RGB/RGBA
            dstRow[col * channels + 0] = srcRow[col * 4 + 2]; // R
            dstRow[col * channels + 1] = srcRow[col * 4 + 1]; // G
            dstRow[col * channels + 2] = srcRow[col * 4 + 0]; // B
            if (bRGBA)
                dstRow[col * channels + 3] = srcRow[col * 4 + 3]; // A
        }
    }
    // readback was allocated with newBufferWithLength: (retain +1); release after copy
    [readback release];
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
    assert(dat != nullptr && "WriteDDS: data cannot be null");
    assert(name != nullptr && "WriteDDS: filename cannot be null");
    assert(wdt > 0 && "WriteDDS: width must be positive");
    assert(hgt > 0 && "WriteDDS: height must be positive");
    assert(Size > 0 && "WriteDDS: data size must be positive");
    assert(NumMips >= 0 && "WriteDDS: mipmap count cannot be negative");
    
    if (!dat || !name)
        return;
        
    // Write DDS file
}

void CMetalUtilityRenderer::WriteTGA(byte* dat, int wdt, int hgt, const char* name, int bits)
{
    assert(dat != nullptr && "WriteTGA: data cannot be null");
    assert(name != nullptr && "WriteTGA: filename cannot be null");
    assert(wdt > 0 && "WriteTGA: width must be positive");
    assert(hgt > 0 && "WriteTGA: height must be positive");
    assert(bits == 8 || bits == 16 || bits == 24 || bits == 32 && "WriteTGA: bits must be 8, 16, 24, or 32");
    
    if (!dat || !name)
        return;
        
    // Write TGA file
}

void CMetalUtilityRenderer::WriteJPG(byte* dat, int wdt, int hgt, char* name)
{
    assert(dat != nullptr && "WriteJPG: data cannot be null");
    assert(name != nullptr && "WriteJPG: filename cannot be null");
    assert(wdt > 0 && "WriteJPG: width must be positive");
    assert(hgt > 0 && "WriteJPG: height must be positive");
    
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
    assert(nWidth > 0 && "CreateRenderTarget: width must be positive");
    assert(nHeight > 0 && "CreateRenderTarget: height must be positive");
    assert(m_renderer != nullptr && "CreateRenderTarget: renderer cannot be null");
    assert(m_renderer->m_device != nil && "CreateRenderTarget: Metal device cannot be null");
    
    if (nWidth <= 0 || nHeight <= 0 || !m_renderer || !m_renderer->m_device)
        return 0;
    if (!m_textureManager)
        return 0;
        
    int renderTargetId = AllocateRenderTargetId();
    if (renderTargetId == -1)
        return 0;
    if (renderTargetId >= static_cast<int>(m_renderTargets.size()))
        m_renderTargets.resize(renderTargetId + 1);
    
    MTLPixelFormat colorFormat = ResolveRenderTargetFormat(eTF);
    if (colorFormat == MTLPixelFormatInvalid)
        colorFormat = MTLPixelFormatBGRA8Unorm;
    
    MTLTextureDescriptor* colorDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:colorFormat
                                                                                          width:nWidth
                                                                                         height:nHeight
                                                                                      mipmapped:NO];
    colorDesc.storageMode = MTLStorageModePrivate;
    colorDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    
    id<MTLTexture> colorTexture = [m_renderer->m_device newTextureWithDescriptor:colorDesc];
    if (!colorTexture)
    {
        iLog->Log("CreateRenderTarget: Failed to create color texture (%dx%d)\n", nWidth, nHeight);
        ReleaseRenderTargetId(renderTargetId);
        return 0;
    }
    
    MTLTextureDescriptor* depthDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float_Stencil8
                                                                                          width:nWidth
                                                                                         height:nHeight
                                                                                      mipmapped:NO];
    depthDesc.storageMode = MTLStorageModePrivate;
    depthDesc.usage = MTLTextureUsageRenderTarget;
    
    id<MTLTexture> depthTexture = [m_renderer->m_device newTextureWithDescriptor:depthDesc];
    if (!depthTexture)
    {
        iLog->Log("CreateRenderTarget: Failed to create depth texture (%dx%d)\n", nWidth, nHeight);
        [colorTexture release];
        ReleaseRenderTargetId(renderTargetId);
        assert(false);
        return 0;
    }
    
    RenderTargetInfo& info = m_renderTargets[renderTargetId];
    if (info.colorTexture)
        [info.colorTexture release];
    if (info.depthTexture)
        [info.depthTexture release];
    
    info.colorTexture = colorTexture;
    info.depthTexture = depthTexture;
    info.width = nWidth;
    info.height = nHeight;
    info.format = eTF;
    info.inUse = true;
    info.needsClear = true;
        
    return renderTargetId;
}

bool CMetalUtilityRenderer::DestroyRenderTarget(int nHandle)
{
    assert(nHandle > 0 && "DestroyRenderTarget: handle 0 reserved for backbuffer");
    
    if (nHandle <= 0 || nHandle >= m_renderTargets.size())
        return false;
    RenderTargetInfo& info = m_renderTargets[nHandle];
    if (!info.inUse)
        return false;
    
    if (info.colorTexture)
    {
        [info.colorTexture release];
        info.colorTexture = nil;
    }
    if (info.depthTexture)
    {
        [info.depthTexture release];
        info.depthTexture = nil;
    }
    info.inUse = false;
    info.needsClear = true;
    info.width = 0;
    info.height = 0;
    info.format = eTF_Unknown;
        
    ReleaseRenderTargetId(nHandle);
    return true;
}

bool CMetalUtilityRenderer::SetRenderTarget(int nHandle)
{
    assert(nHandle >= 0 && "SetRenderTarget: handle cannot be negative");
    assert(m_renderer != nullptr && "SetRenderTarget: renderer cannot be null");
    
    if (nHandle < 0 || (!m_renderer) || (nHandle >= m_renderTargets.size() && nHandle > 0))
        return false;
    if (!m_renderer->m_currentCommandBuffer)
        return false;

    if (nHandle == 0)
    {
        if (!m_renderer->m_currentDrawable)
        {
            iLog->Log("SetRenderTarget: Back buffer drawable is not available\n");
            return false;
        }
    }
    else
    {
        RenderTargetInfo& preInfo = m_renderTargets[nHandle];
        if (!preInfo.inUse || !preInfo.colorTexture)
            return false;
    }
    
    m_renderer->ReleaseRenderEncoder();
    
    if (m_renderer->m_renderPassDescriptor)
    {
        [m_renderer->m_renderPassDescriptor release];
        m_renderer->m_renderPassDescriptor = nil;
    }
    
    MTLRenderPassDescriptor* descriptor = nil;
    int targetWidth = m_renderer->GetWidth();
    int targetHeight = m_renderer->GetHeight();
    
    if (nHandle == 0)
    {
        id<MTLTexture> depthTexture = m_renderer->m_depthStencilTextures[m_renderer->m_currentFrameIndex];
        descriptor = m_renderer->CreateRenderPassDescriptor(m_renderer->m_currentDrawable.texture, depthTexture);
    }
    else
    {
        RenderTargetInfo& info = m_renderTargets[nHandle];
        targetWidth = info.width;
        targetHeight = info.height;
        
        MTLLoadAction loadAction = info.needsClear ? MTLLoadActionClear : MTLLoadActionLoad;
        descriptor = m_renderer->GetOrCreateRenderPassDescriptor(info.colorTexture,
                                                                 info.depthTexture,
                                                                 loadAction,
                                                                 loadAction,
                                                                 loadAction);
        if (descriptor && info.needsClear)
        {
            descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
            descriptor.depthAttachment.clearDepth = 1.0;
            descriptor.stencilAttachment.clearStencil = 0;
        }
        info.needsClear = false;
    }
    
    if (!descriptor)
        return false;
    
    m_renderer->m_renderPassDescriptor = [descriptor retain];
    m_renderer->m_renderEncoder = [[m_renderer->m_currentCommandBuffer renderCommandEncoderWithDescriptor:descriptor] retain];
    
    if (!m_renderer->m_renderEncoder)
        return false;
    m_renderer->m_renderEncoderOpen = true;
    
    m_renderer->SetViewport(0, 0, targetWidth, targetHeight);
    return true;
}

id<MTLTexture> CMetalUtilityRenderer::GetRenderTargetDepthTexture(int nHandle) const
{
    if (nHandle <= 0 || nHandle >= (int)m_renderTargets.size())
        return nil;
    return m_renderTargets[nHandle].depthTexture;
}

id<MTLTexture> CMetalUtilityRenderer::GetRenderTargetColorTexture(int nHandle) const
{
    if (nHandle <= 0 || nHandle >= (int)m_renderTargets.size())
        return nil;
    return m_renderTargets[nHandle].colorTexture;
}

float CMetalUtilityRenderer::EF_GetWaterZElevation(float fX, float fY)
{
    return m_renderer->CRenderer::EF_GetWaterZElevation(fX, fY);
}

// Protected methods
void CMetalUtilityRenderer::CreateDebugPipelineState()
{
    // Debug pipeline state creation deferred - not needed for UI rendering
    // Will be implemented when debug rendering is needed
}

void CMetalUtilityRenderer::CreateTextPipelineState()
{
    // Text pipeline state creation deferred - not needed for UI rendering
    // Will be implemented when text rendering is needed
}

void CMetalUtilityRenderer::CreateSpritePipelineState()
{
    // Lazy initialization: Create sprite pipeline state on first use
    // This is deferred from constructor because shaders may not be loaded yet at initialization time
    // The sprite pipeline is required for all 2D UI rendering (both textured and solid color quads)
    
    assert(m_renderer != nullptr && "CreateSpritePipelineState: renderer cannot be null");
    assert(m_renderer->m_device != nil && "CreateSpritePipelineState: Metal device cannot be nil");
    
    if (!m_renderer || !m_renderer->m_device)
    {
        return;
    }
        
    // Create sprite pipeline state descriptor
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    descriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    // Enable alpha blending for 2D sprites
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    
    // Set up vertex descriptor for 2D sprite vertices
    MTLVertexDescriptor* vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    assert(vertexDescriptor != nil && "CreateSpritePipelineState: vertex descriptor allocation failed");
    
    // Position (float2 at index 0)
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    
    // TexCoord (float2 at index 1)
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[1].offset = sizeof(float) * 2;
    vertexDescriptor.attributes[1].bufferIndex = 0;
    assert(sizeof(float) * 2 == 8 && "CreateSpritePipelineState: texCoord offset should be 8 bytes");
    
    // Color (float4 at index 2)
    vertexDescriptor.attributes[2].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[2].offset = sizeof(float) * 4;
    vertexDescriptor.attributes[2].bufferIndex = 0;
    assert(sizeof(float) * 4 == 16 && "CreateSpritePipelineState: color offset should be 16 bytes");
    
    // Layout stride
    vertexDescriptor.layouts[0].stride = sizeof(float) * 8; // 2 + 2 + 4
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    assert(sizeof(float) * 8 == 32 && "CreateSpritePipelineState: vertex stride should be 32 bytes");
    
    descriptor.vertexDescriptor = vertexDescriptor;
    
    // Try to load shader functions from SpriteShaders.metallib
    NSError* error = nil;
    id<MTLLibrary> spriteLibrary = nil;
    
    // Try loading from app bundle Resources
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* shaderPath = [bundle pathForResource:@"SpriteShaders" ofType:@"metallib"];
    
    if (shaderPath)
    {
        spriteLibrary = [m_renderer->m_device newLibraryWithFile:shaderPath error:&error];
    }
    
    if (!spriteLibrary)
    {
        NSString* exePath = [[NSBundle mainBundle] executablePath];
        NSString* exeDir = [exePath stringByDeletingLastPathComponent];
        NSString* metallibPath = [exeDir stringByAppendingPathComponent:@"SpriteShaders.metallib"];
        spriteLibrary = [m_renderer->m_device newLibraryWithFile:metallibPath error:&error];
    }

    if (!spriteLibrary)
    {
        spriteLibrary = [m_renderer->m_device newDefaultLibrary];
    }

    assert(spriteLibrary != nil && "CreateSpritePipelineState: could not locate SpriteShaders.metallib in any search path");
    if (!spriteLibrary)
        return;

    id<MTLFunction> vertexFunction   = [spriteLibrary newFunctionWithName:@"sprite_vertex"];
    id<MTLFunction> fragmentFunction = [spriteLibrary newFunctionWithName:@"sprite_fragment"];
    assert(vertexFunction   != nil && "CreateSpritePipelineState: sprite_vertex not found in library");
    assert(fragmentFunction != nil && "CreateSpritePipelineState: sprite_fragment not found in library");
    if (!vertexFunction || !fragmentFunction)
        return;

    descriptor.vertexFunction   = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;

    m_spritePipelineState = [m_renderer->m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    assert(m_spritePipelineState != nil && "CreateSpritePipelineState: textured PSO creation failed");
    if (!m_spritePipelineState)
        return;

    id<MTLFunction> noTexFragment = [spriteLibrary newFunctionWithName:@"sprite_fragment_notex"];
    if (!noTexFragment)
        noTexFragment = fragmentFunction;

    MTLRenderPipelineDescriptor* solidDesc = [[MTLRenderPipelineDescriptor alloc] init];
    solidDesc.colorAttachments[0].pixelFormat               = MTLPixelFormatBGRA8Unorm;
    solidDesc.depthAttachmentPixelFormat                    = MTLPixelFormatDepth32Float_Stencil8;
    solidDesc.stencilAttachmentPixelFormat                  = MTLPixelFormatDepth32Float_Stencil8;
    solidDesc.colorAttachments[0].blendingEnabled           = YES;
    solidDesc.colorAttachments[0].sourceRGBBlendFactor      = MTLBlendFactorSourceAlpha;
    solidDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    solidDesc.colorAttachments[0].rgbBlendOperation         = MTLBlendOperationAdd;
    solidDesc.colorAttachments[0].sourceAlphaBlendFactor    = MTLBlendFactorOne;
    solidDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    solidDesc.colorAttachments[0].alphaBlendOperation       = MTLBlendOperationAdd;
    solidDesc.vertexDescriptor = vertexDescriptor;
    solidDesc.vertexFunction   = vertexFunction;
    solidDesc.fragmentFunction = noTexFragment;

    NSError* solidError = nil;
    m_solidColorPipelineState = [m_renderer->m_device newRenderPipelineStateWithDescriptor:solidDesc error:&solidError];
    assert(m_solidColorPipelineState != nil && "CreateSpritePipelineState: solid-color PSO creation failed");
}

void CMetalUtilityRenderer::CreateFontPipelineState()
{
    assert(m_renderer != nullptr && "CreateFontPipelineState: renderer cannot be null");
    assert(m_renderer->m_device != nil && "CreateFontPipelineState: Metal device cannot be nil");
    if (!m_renderer || !m_renderer->m_device)
        return;

    NSError* loadError = nil;
    id<MTLLibrary> spriteLibrary = nil;
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* shaderPath = [bundle pathForResource:@"SpriteShaders" ofType:@"metallib"];
    if (shaderPath)
        spriteLibrary = [m_renderer->m_device newLibraryWithFile:shaderPath error:&loadError];
    if (!spriteLibrary) {
        NSString* exeDir = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
        spriteLibrary = [m_renderer->m_device newLibraryWithFile:
            [exeDir stringByAppendingPathComponent:@"SpriteShaders.metallib"] error:&loadError];
    }
    if (!spriteLibrary)
        spriteLibrary = [m_renderer->m_device newDefaultLibrary];
    assert(spriteLibrary != nil && "CreateFontPipelineState: SpriteShaders.metallib not found");
    if (!spriteLibrary)
        return;

    id<MTLFunction> vertexFunction   = [spriteLibrary newFunctionWithName:@"font_vertex"];
    id<MTLFunction> fragmentFunction = [spriteLibrary newFunctionWithName:@"sprite_fragment"];
    assert(vertexFunction   != nil && "CreateFontPipelineState: font_vertex not found in library");
    assert(fragmentFunction != nil && "CreateFontPipelineState: sprite_fragment not found in library");
    if (!vertexFunction || !fragmentFunction)
        return;

    // Vertex descriptor matches struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F (stride 24):
    //   float3 xyz   offset  0  (12 bytes)
    //   uchar4 color offset 12  ( 4 bytes)
    //   float2 st    offset 16  ( 8 bytes)
    MTLVertexDescriptor* fontDesc = [[MTLVertexDescriptor alloc] init];
    fontDesc.attributes[0].format      = MTLVertexFormatFloat3;
    fontDesc.attributes[0].offset      = 0;
    fontDesc.attributes[0].bufferIndex = kMetalVertexStream_General;
    fontDesc.attributes[1].format      = MTLVertexFormatUChar4;
    fontDesc.attributes[1].offset      = 12;
    fontDesc.attributes[1].bufferIndex = kMetalVertexStream_General;
    fontDesc.attributes[2].format      = MTLVertexFormatFloat2;
    fontDesc.attributes[2].offset      = 16;
    fontDesc.attributes[2].bufferIndex = kMetalVertexStream_General;
    fontDesc.layouts[kMetalVertexStream_General].stride       = 24;
    fontDesc.layouts[kMetalVertexStream_General].stepFunction = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.colorAttachments[0].pixelFormat               = MTLPixelFormatBGRA8Unorm;
    descriptor.depthAttachmentPixelFormat                    = MTLPixelFormatDepth32Float_Stencil8;
    descriptor.stencilAttachmentPixelFormat                  = MTLPixelFormatDepth32Float_Stencil8;
    descriptor.colorAttachments[0].blendingEnabled           = YES;
    descriptor.colorAttachments[0].sourceRGBBlendFactor      = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].rgbBlendOperation         = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor    = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].alphaBlendOperation       = MTLBlendOperationAdd;
    descriptor.vertexDescriptor = fontDesc;
    descriptor.vertexFunction   = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;

    NSError* error = nil;
    m_fontPipelineState = [m_renderer->m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!m_fontPipelineState) {
        const char* desc = error ? [[error localizedDescription] UTF8String] : "(no error object)";
        fprintf(stderr, "[FONT_PSO_ERROR] CreateFontPipelineState failed: %s\n", desc);
        if (iLog) iLog->Log("CreateFontPipelineState failed: %s\n", desc);
        assert(m_fontPipelineState != nil && "CreateFontPipelineState: font PSO creation failed — check log for Metal error");
    }
}

void CMetalUtilityRenderer::RenderTextMessage(const TextMessage& message)
{
    if (message.text.empty())
        return;

    ICryFont* pCryFont = iSystem ? iSystem->GetICryFont() : nullptr;
    if (!pCryFont)
        return;

    IFFont* pFont = pCryFont->GetFont("default");
    if (!pFont)
        return;

    const float kBaseSize = 16.0f;
    float size = kBaseSize * message.fontSize;
    pFont->SetSize(vector2f(size, size));
    pFont->SetColor(color4f(message.color[0], message.color[1], message.color[2], message.color[3]));
    pFont->DrawString(message.position.x, message.position.y, message.text.c_str());
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
    if (m_nextRenderTargetId == std::numeric_limits<int>::max())
        return -1;
    return m_nextRenderTargetId++;
}

void CMetalUtilityRenderer::ReleaseRenderTargetId(int id)
{
    if (id <= 0 || id >= m_renderTargets.size())
        return;
    m_renderTargets[id] = RenderTargetInfo();
}

#endif // __APPLE__ && __MACH__

