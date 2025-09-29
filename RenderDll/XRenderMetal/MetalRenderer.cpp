////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalRenderer.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal API renderer implementation for macOS
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalRenderer.h"
#include "I3DEngine.h"
#include <Cocoa/Cocoa.h>

CMetalRenderer::CMetalRenderer()
    : m_device(nil)
    , m_commandQueue(nil)
    , m_renderEncoder(nil)
    , m_metalView(nil)
    , m_metalLayer(nil)
    , m_currentCommandBuffer(nil)
    , m_renderPassDescriptor(nil)
    , m_currentPipelineState(nil)
    , m_currentDepthStencilState(nil)
{
    CV_r_log = 0; // Disable logging by default
}

CMetalRenderer::~CMetalRenderer()
{
    ShutDown();
}

bool CMetalRenderer::Init(SSystemInitParams& rParams)
{
    if (!CRenderer::Init(rParams))
        return false;
        
    if (!InitializeDevice())
    {
        iLog->Log("Error: Failed to initialize Metal device");
        return false;
    }
    
    if (!CreateDefaultPipelineState())
    {
        iLog->Log("Error: Failed to create default Metal pipeline state");
        return false;
    }
    
    iLog->Log("Metal renderer initialized successfully");
    return true;
}

void CMetalRenderer::ShutDown(bool bReInit)
{
    // Release Metal resources
    if (m_renderEncoder)
    {
        [m_renderEncoder endEncoding];
        m_renderEncoder = nil;
    }
    
    if (m_currentCommandBuffer)
    {
        [m_currentCommandBuffer commit];
        m_currentCommandBuffer = nil;
    }
    
    // Release textures and buffers
    for (auto texture : m_textures)
    {
        if (texture) [texture release];
    }
    m_textures.clear();
    
    for (auto buffer : m_buffers)
    {
        if (buffer) [buffer release];
    }
    m_buffers.clear();
    
    // Release Metal objects
    if (m_currentPipelineState) [m_currentPipelineState release];
    if (m_currentDepthStencilState) [m_currentDepthStencilState release];
    if (m_renderPassDescriptor) [m_renderPassDescriptor release];
    if (m_commandQueue) [m_commandQueue release];
    if (m_device) [m_device release];
    
    CRenderer::ShutDown(bReInit);
}

bool CMetalRenderer::InitializeDevice()
{
    // Get the default Metal device (for Apple Silicon, this is optimal)
    m_device = MTLCreateSystemDefaultDevice();
    if (!m_device)
    {
        iLog->Log("Error: No Metal device available");
        return false;
    }
    
    // Create command queue
    m_commandQueue = [m_device newCommandQueue];
    if (!m_commandQueue)
    {
        iLog->Log("Error: Failed to create Metal command queue");
        return false;
    }
    
    // Log device info
    NSString* deviceName = [m_device name];
    iLog->Log("Metal device: %s", [deviceName UTF8String]);
    
    return true;
}

bool CMetalRenderer::CreateDefaultPipelineState()
{
    // This is a placeholder - actual implementation would need proper shaders
    // For now, just return true to allow initialization
    return true;
}

void CMetalRenderer::BeginFrame()
{
    CRenderer::BeginFrame();
    
    // Create command buffer for this frame
    m_currentCommandBuffer = [m_commandQueue commandBuffer];
    if (!m_currentCommandBuffer)
    {
        iLog->Log("Warning: Failed to create Metal command buffer");
        return;
    }
    
    UpdateRenderPassDescriptor();
    
    // Begin render pass
    if (m_renderPassDescriptor)
    {
        m_renderEncoder = [m_currentCommandBuffer renderCommandEncoderWithDescriptor:m_renderPassDescriptor];
    }
}

void CMetalRenderer::EndFrame()
{
    // End render encoding
    if (m_renderEncoder)
    {
        [m_renderEncoder endEncoding];
        m_renderEncoder = nil;
    }
    
    // Present and commit
    if (m_currentCommandBuffer)
    {
        [m_currentCommandBuffer commit];
        m_currentCommandBuffer = nil;
    }
    
    CRenderer::EndFrame();
}

void CMetalRenderer::UpdateRenderPassDescriptor()
{
    // This would be implemented based on the current render target
    // For now, create a basic render pass descriptor
    if (!m_renderPassDescriptor)
    {
        m_renderPassDescriptor = [MTLRenderPassDescriptor new];
        
        // Configure color attachment
        m_renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        m_renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
        m_renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    }
}

id<MTLBuffer> CMetalRenderer::CreateMetalBuffer(void* data, size_t size, MTLResourceOptions options)
{
    if (!m_device || !data || size == 0)
        return nil;
    
    id<MTLBuffer> buffer = [m_device newBufferWithBytes:data
                                                 length:size
                                                options:options];
    
    if (buffer)
    {
        m_buffers.push_back(buffer);
    }
    
    return buffer;
}

// Utility function implementations
MTLPixelFormat ConvertToMetalFormat(ETEX_Format format)
{
    switch(format)
    {
        case eTF_8888: return MTLPixelFormatRGBA8Unorm;
        case eTF_0888: return MTLPixelFormatRGBA8Unorm;
        case eTF_DXT1: return MTLPixelFormatBC1_RGBA;
        case eTF_DXT3: return MTLPixelFormatBC2_RGBA;
        case eTF_DXT5: return MTLPixelFormatBC3_RGBA;
        default: return MTLPixelFormatRGBA8Unorm;
    }
}

MTLPrimitiveType ConvertToMetalPrimitive(eRenderPrimitiveType type)
{
    switch(type)
    {
        case R_PRIMV_TRIANGLES: return MTLPrimitiveTypeTriangle;
        case R_PRIMV_TRIANGLE_STRIP: return MTLPrimitiveTypeTriangleStrip;
        case R_PRIMV_QUADS: return MTLPrimitiveTypeTriangle; // Convert quads to triangles
        default: return MTLPrimitiveTypeTriangle;
    }
}

MTLCompareFunction ConvertToMetalDepthFunc(int func)
{
    // Convert from OpenGL/D3D depth functions to Metal
    switch(func)
    {
        case 0x0200: return MTLCompareFunctionNever;      // GL_NEVER
        case 0x0201: return MTLCompareFunctionLess;       // GL_LESS
        case 0x0202: return MTLCompareFunctionEqual;      // GL_EQUAL
        case 0x0203: return MTLCompareFunctionLessEqual;  // GL_LEQUAL
        case 0x0204: return MTLCompareFunctionGreater;    // GL_GREATER
        case 0x0205: return MTLCompareFunctionNotEqual;   // GL_NOTEQUAL
        case 0x0206: return MTLCompareFunctionGreaterEqual; // GL_GEQUAL
        case 0x0207: return MTLCompareFunctionAlways;     // GL_ALWAYS
        default: return MTLCompareFunctionLess;
    }
}

// Stub implementations for required virtual methods
void CMetalRenderer::SetCamera(const CCamera& cam) 
{
    CRenderer::SetCamera(cam);
    // TODO: Update Metal view/projection matrices
}

void CMetalRenderer::SetViewport(int x, int y, int width, int height)
{
    CRenderer::SetViewport(x, y, width, height);
    
    if (m_renderEncoder)
    {
        MTLViewport viewport = { (double)x, (double)y, (double)width, (double)height, 0.0, 1.0 };
        [m_renderEncoder setViewport:viewport];
    }
}

void CMetalRenderer::SetScissor(int x, int y, int width, int height)
{
    if (m_renderEncoder)
    {
        MTLScissorRect scissor = { (NSUInteger)x, (NSUInteger)y, (NSUInteger)width, (NSUInteger)height };
        [m_renderEncoder setScissorRect:scissor];
    }
}

// Metal texture management implementation
int CMetalRenderer::CreateTexture(char* name, int wdt, int hgt, int depth, uint flags, byte* pData, 
                                 ETexType eTT, float fAmount1, float fAmount2, 
                                 int DXTSize, STexPic* ti, int bind, ETEX_Format eTF)
{
    if (!m_device)
        return 0;
    
    // Convert format to Metal pixel format
    MTLPixelFormat metalFormat = ConvertToMetalFormat(eTF);
    
    // Create texture descriptor
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor new];
    descriptor.textureType = (depth > 1) ? MTLTextureType3D : MTLTextureType2D;
    descriptor.pixelFormat = metalFormat;
    descriptor.width = wdt;
    descriptor.height = hgt;
    descriptor.depth = (depth > 1) ? depth : 1;
    descriptor.mipmapLevelCount = 1; // TODO: Calculate mipmap levels
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    descriptor.storageMode = MTLStorageModePrivate;
    
    // Create the Metal texture
    id<MTLTexture> metalTexture = [m_device newTextureWithDescriptor:descriptor];
    if (!metalTexture)
    {
        iLog->Log("Error: Failed to create Metal texture %s (%dx%d)", name ? name : "unnamed", wdt, hgt);
        [descriptor release];
        return 0;
    }
    
    // Upload texture data if provided
    if (pData)
    {
        MTLRegion region = MTLRegionMake2D(0, 0, wdt, hgt);
        NSUInteger bytesPerRow = wdt * 4; // Assuming RGBA format for now
        
        [metalTexture replaceRegion:region
                         mipmapLevel:0
                           withBytes:pData
                         bytesPerRow:bytesPerRow];
    }
    
    // Store texture and return handle
    m_textures.push_back(metalTexture);
    int textureID = (int)m_textures.size() - 1;
    
    [descriptor release];
    
    iLog->Log("Created Metal texture %s (%dx%d) with ID %d", name ? name : "unnamed", wdt, hgt, textureID);
    return textureID;
}

void CMetalRenderer::RemoveTexture(int tnum) 
{
    if (tnum >= 0 && tnum < (int)m_textures.size())
    {
        id<MTLTexture> texture = m_textures[tnum];
        if (texture)
        {
            [texture release];
            m_textures[tnum] = nil;
        }
    }
}

void CMetalRenderer::SetTexture(int tnum, ETexType eTT) 
{
    if (!m_renderEncoder || tnum < 0 || tnum >= (int)m_textures.size())
        return;
    
    id<MTLTexture> texture = m_textures[tnum];
    if (texture)
    {
        // Bind texture to fragment shader (slot 0 for now)
        [m_renderEncoder setFragmentTexture:texture atIndex:0];
        
        // TODO: Support multiple texture units and vertex shader textures
        // [m_renderEncoder setVertexTexture:texture atIndex:0];
    }
}

void CMetalRenderer::DrawTriStrip(CVertexBuffer* vb, int OffsIndex, int NumTris) 
{
    if (!m_renderEncoder || !vb || NumTris <= 0)
        return;
    
    // For now, convert triangle strip to individual triangles
    // TODO: Optimize this with proper Metal triangle strip support
    int numVertices = NumTris + 2;
    
    if (vb->m_pVertices && m_currentPipelineState)
    {
        // Create vertex buffer if needed
        id<MTLBuffer> vertexBuffer = CreateMetalBuffer(vb->m_pVertices, 
                                                      numVertices * vb->m_nVertexFormat,
                                                      MTLResourceStorageModeShared);
        
        if (vertexBuffer)
        {
            [m_renderEncoder setRenderPipelineState:m_currentPipelineState];
            [m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
            [m_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                                vertexStart:OffsIndex
                                vertexCount:numVertices];
            
            [vertexBuffer release];
        }
    }
}

void CMetalRenderer::DrawBuffer(CVertexBuffer* vb, SShader* ef, int NumVerts, int OffsIndex, 
                               int NumTris, int OffsInds, eRenderPrimitiveType eType) 
{
    if (!m_renderEncoder || !vb || NumVerts <= 0)
        return;
    
    // Convert primitive type to Metal
    MTLPrimitiveType metalPrimType = ConvertToMetalPrimitive(eType);
    
    if (vb->m_pVertices && m_currentPipelineState)
    {
        // Create vertex buffer
        id<MTLBuffer> vertexBuffer = CreateMetalBuffer(vb->m_pVertices, 
                                                      NumVerts * vb->m_nVertexFormat,
                                                      MTLResourceStorageModeShared);
        
        if (vertexBuffer)
        {
            [m_renderEncoder setRenderPipelineState:m_currentPipelineState];
            [m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
            
            // Check if we have index buffer
            if (vb->m_pIndices && NumTris > 0)
            {
                id<MTLBuffer> indexBuffer = CreateMetalBuffer(vb->m_pIndices,
                                                            NumTris * 3 * sizeof(uint16),
                                                            MTLResourceStorageModeShared);
                
                if (indexBuffer)
                {
                    [m_renderEncoder drawIndexedPrimitives:metalPrimType
                                                indexCount:NumTris * 3
                                                 indexType:MTLIndexTypeUInt16
                                               indexBuffer:indexBuffer
                                         indexBufferOffset:OffsInds * sizeof(uint16)];
                    
                    [indexBuffer release];
                }
            }
            else
            {
                // Non-indexed rendering
                [m_renderEncoder drawPrimitives:metalPrimType
                                    vertexStart:OffsIndex
                                    vertexCount:NumVerts];
            }
            
            [vertexBuffer release];
        }
    }
}

void CMetalRenderer::SetShader(SShader* sh) 
{
    // TODO: Implement Metal shader binding
}

void CMetalRenderer::SetMaterial(SMaterial* m) 
{
    // TODO: Implement Metal material binding
}

void CMetalRenderer::SetState(int st) 
{
    // TODO: Implement Metal state management
}

void CMetalRenderer::SetCullMode(int mode) 
{
    // TODO: Implement Metal culling
}

void CMetalRenderer::SetDepthFunc(int func) 
{
    // TODO: Implement Metal depth function
}

void CMetalRenderer::SetAlphaFunc(int func, float ref) 
{
    // TODO: Implement Metal alpha testing
}

#endif // __APPLE__ && __MACH__
