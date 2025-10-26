////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalRenderer.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Main Metal renderer class that combines specialized managers
//               Apple's Metal graphics API provides low-level GPU access
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef METAL_RENDERER_H
#define METAL_RENDERER_H

#if defined(__APPLE__) && defined(__MACH__)

#include <Metal/Metal.h>
#include <MetalKit/MetalKit.h>
#include <QuartzCore/CAMetalLayer.h>
#include <Cocoa/Cocoa.h>
#include <vector>
#include <memory>

// Include CryEngine interfaces
#include "IRenderer.h"
#include "IShader.h"
#include "Cry_Math.h"

// Include specialized manager classes
#include "MetalBaseRenderer.h"
#include "MetalTextureManager.h"
#include "MetalShaderManager.h"
#include "MetalUtilityRenderer.h"

// Forward declarations
struct SSystemInitParams;
struct SCryRenderInterface;
class CCamera;
class ISystem;
class CVertexBuffer;
class SShader;
class SMaterial;
class STexPic;

// Main Metal renderer class that combines all specialized managers
class CMetalRenderer : public IRenderer
{
public:
    CMetalRenderer();
    virtual ~CMetalRenderer();
    void SetTexture(int tnum, ETexType Type) override;
    void SetWhiteTexture() override;
    unsigned int DownLoadToVideoMemory(unsigned char *data, int w, int h,
                                       ETEX_Format eTFSrc, ETEX_Format eTFDst,
                                       int nummipmap, bool repeat, int filter,
                                       int Id, char *szCacheName, int flags) override;
    void UpdateTextureInVideoMemory(uint tnum, unsigned char *newdata, int posx,
                                    int posy, int w, int h, ETEX_Format eTF);

  protected:
    // Specialized manager instances
    std::unique_ptr<CMetalTextureManager> m_textureManager;
    std::unique_ptr<CMetalShaderManager> m_shaderManager;
    std::unique_ptr<CMetalUtilityRenderer> m_utilityRenderer;
    
    // Initialization methods
    bool InitializeManagers();
    void ShutdownManagers();
};

// Metal utility functions
MTLPixelFormat ConvertToMetalFormat(ETEX_Format format);
MTLPrimitiveType ConvertToMetalPrimitive(int type);
MTLCompareFunction ConvertToMetalDepthFunc(int func);

#endif // __APPLE__ && __MACH__

#endif // METAL_RENDERER_H
