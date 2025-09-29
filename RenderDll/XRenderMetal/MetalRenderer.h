////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalRenderer.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal API renderer for macOS (replacement for D3D9)
//               Apple's Metal graphics API provides low-level GPU access
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_RENDERER_H
#define METAL_RENDERER_H

#if defined(__APPLE__) && defined(__MACH__)

#include "Renderer.h"
#include <Metal/Metal.h>
#include <MetalKit/MetalKit.h>
#include <QuartzCore/CAMetalLayer.h>

class CMetalRenderer : public CRenderer
{
public:
    CMetalRenderer();
    virtual ~CMetalRenderer();

    // CRenderer interface implementation
    virtual bool Init(SSystemInitParams& rParams) override;
    virtual void ShutDown(bool bReInit = false) override;
    virtual void BeginFrame() override;
    virtual void EndFrame() override;
    virtual void SetCamera(const CCamera& cam) override;
    virtual void SetViewport(int x, int y, int width, int height) override;
    virtual void SetScissor(int x, int y, int width, int height) override;
    
    // Resource management
    virtual int CreateTexture(char* name, int wdt, int hgt, int depth, uint flags, byte* pData, 
                             ETexType eTT, float fAmount1 = -1.0f, float fAmount2 = -1.0f, 
                             int DXTSize = 0, STexPic* ti = NULL, int bind = 0, 
                             ETEX_Format eTF = eTF_8888) override;
    virtual void RemoveTexture(int tnum) override;
    virtual void SetTexture(int tnum, ETexType eTT = eTT_Base) override;
    
    // Rendering
    virtual void DrawTriStrip(CVertexBuffer* vb, int OffsIndex, int NumTris) override;
    virtual void DrawBuffer(CVertexBuffer* vb, SShader* ef, int NumVerts, int OffsIndex, 
                           int NumTris, int OffsInds = 0, eRenderPrimitiveType eType = R_PRIMV_TRIANGLES) override;
    
    // Shader support
    virtual void SetShader(SShader* sh) override;
    virtual void SetMaterial(SMaterial* m) override;
    
    // State management
    virtual void SetState(int st) override;
    virtual void SetCullMode(int mode) override;
    virtual void SetDepthFunc(int func) override;
    virtual void SetAlphaFunc(int func, float ref) override;
    
protected:
    // Metal-specific members
    id<MTLDevice> m_device;
    id<MTLCommandQueue> m_commandQueue;
    id<MTLRenderCommandEncoder> m_renderEncoder;
    MTKView* m_metalView;
    CAMetalLayer* m_metalLayer;
    
    // Current frame resources
    id<MTLCommandBuffer> m_currentCommandBuffer;
    MTLRenderPassDescriptor* m_renderPassDescriptor;
    
    // Render state
    id<MTLRenderPipelineState> m_currentPipelineState;
    id<MTLDepthStencilState> m_currentDepthStencilState;
    
    // Resource pools
    std::vector<id<MTLTexture>> m_textures;
    std::vector<id<MTLBuffer>> m_buffers;
    
    // Internal methods
    bool InitializeDevice();
    bool CreateDefaultPipelineState();
    void UpdateRenderPassDescriptor();
    id<MTLTexture> CreateMetalTexture(int width, int height, MTLPixelFormat format);
    id<MTLBuffer> CreateMetalBuffer(void* data, size_t size, MTLResourceOptions options);
};

// Metal utility functions
MTLPixelFormat ConvertToMetalFormat(ETEX_Format format);
MTLPrimitiveType ConvertToMetalPrimitive(eRenderPrimitiveType type);
MTLCompareFunction ConvertToMetalDepthFunc(int func);

#endif // __APPLE__ && __MACH__

#endif // METAL_RENDERER_H
