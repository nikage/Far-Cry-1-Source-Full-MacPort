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
#include "MetalRenderer.m"
#include "I3DEngine.h"
#include "CryCommon/IEntityRenderState.h"
#include "../Common/Textures/dxtlib.h"  // For nvDXT function signatures
#include "../Common/Shadow_Renderer.h"  // For ShadowMapFrustum
#include "CrySizer.h"
#include <atomic>
#include <cmath>
#include <algorithm>
#include <vector>
#include <cstring>
#include <cstdio>
#include <cstdint>
#include <utility>
#include <cstdlib>
#include <cstdarg>
#include <fstream>
#include <iomanip>
#include <unistd.h>
#include <limits.h>
#include <string>
#include <cctype>
#include <memory>

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

namespace
{
    inline float Clamp01(float value)
    {
        if (value < 0.0f)
            return 0.0f;
        if (value > 1.0f)
            return 1.0f;
        return value;
    }

    inline uint32_t PackColor(const CFColor& color)
    {
        const float clampedR = Clamp01(color.r);
        const float clampedG = Clamp01(color.g);
        const float clampedB = Clamp01(color.b);
        const float clampedA = Clamp01(color.a);

        union
        {
            struct
            {
                uint8_t r, g, b, a;
            };
            uint32_t packed;
        } converter;

        converter.r = static_cast<uint8_t>(clampedR * 255.0f + 0.5f);
        converter.g = static_cast<uint8_t>(clampedG * 255.0f + 0.5f);
        converter.b = static_cast<uint8_t>(clampedB * 255.0f + 0.5f);
        converter.a = static_cast<uint8_t>(clampedA * 255.0f + 0.5f);

        return converter.packed;
    }

    inline bool NeedsBlend(const CFColor& color)
    {
        return color.a < 0.999f;
    }

    constexpr size_t kMaxAnimTexturePath = 512;

    struct AnimTexturePattern
    {
        std::string printfFormat;
        int firstFrame = 0;
    };

    inline AnimTexturePattern DeriveAnimPattern(const char* literal)
    {
        AnimTexturePattern result;
        if (!literal)
            return result;

        std::string fullPath(literal);
        size_t slashPos = fullPath.find_last_of("/\\");
        std::string directory = (slashPos != std::string::npos) ? fullPath.substr(0, slashPos + 1) : std::string();
        std::string file = (slashPos != std::string::npos) ? fullPath.substr(slashPos + 1) : fullPath;

        size_t dotPos = file.find_last_of('.');
        std::string name = (dotPos != std::string::npos) ? file.substr(0, dotPos) : file;
        std::string extension = (dotPos != std::string::npos) ? file.substr(dotPos) : std::string();

        size_t digitStart = name.size();
        while (digitStart > 0 && std::isdigit(static_cast<unsigned char>(name[digitStart - 1])))
        {
            --digitStart;
        }

        std::string digits = name.substr(digitStart);
        std::string baseName = name.substr(0, digitStart);
        if (!digits.empty())
            result.firstFrame = std::atoi(digits.c_str());

        const int numDigits = static_cast<int>(digits.size());
        char formatter[16] = {};
        if (numDigits > 0)
            std::snprintf(formatter, sizeof(formatter), "%%0%dd", numDigits);
        else
            std::snprintf(formatter, sizeof(formatter), "%%d");

        result.printfFormat = directory + baseName + formatter + extension;
        return result;
    }

    inline void DecodeLineFlags(int flags, const CFColor& color,
                                bool& depthTest, bool& depthWrite, bool& blend)
    {
        int state = GS_NODEPTHTEST;
        if (flags & 1)
        {
            state |= GS_BLSRC_SRCALPHA | GS_BLDST_ONEMINUSSRCALPHA;
        }
        else if (flags & 2)
        {
            state = GS_DEPTHWRITE;
        }
        else
        {
            state = flags | GS_NODEPTHTEST;
        }

        depthTest = (state & GS_NODEPTHTEST) == 0;
        depthWrite = (state & GS_DEPTHWRITE) != 0;
        blend = (state & (GS_BLSRC_MASK | GS_BLDST_MASK)) != 0 || NeedsBlend(color);
    }
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
    if (size == 0)
    {
        free(ptr);
        return nullptr;
    }
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
      m_utilityRenderer(nullptr), m_window(nil), m_windowMetalLayer(nil),
      m_2DMode(false), m_2DOriginX(0), m_2DOriginY(0),
      m_debugPipelineState(nil), m_metalDumpStatsFlag(0),
      m_metalGPUCaptureFlag(0), m_diagOutputPath() {}

CMetalRenderer::~CMetalRenderer() {
  UnregisterMetalConsoleVariables();
  if (m_debugPipelineState) {
    [m_debugPipelineState release];
    m_debugPipelineState = nil;
  }
  m_debugCommands.clear();
  DestroyGameWindow();
  if (m_textureManager || m_shaderManager || m_utilityRenderer) {
    ShutdownManagers();
  }
}

CMetalTextureManager* CMetalRenderer::GetTextureManager() const
{
  return m_textureManager.get();
}

bool CMetalRenderer::EnsureDebugPipelineState()
{
  if (m_debugPipelineState)
    return true;

  if (!m_device)
    return false;

  NSError *error = nil;
  id<MTLLibrary> library = [m_device newDefaultLibrary];
  if (!library)
  {
    NSString *shaderPath = nil;
    NSBundle *bundle = [NSBundle mainBundle];
    if (bundle)
      shaderPath = [bundle pathForResource:@"UtilShaders" ofType:@"metallib"];
    if (!shaderPath)
    {
      NSString *exePath = [[NSBundle mainBundle] executablePath];
      NSString *exeDir = [exePath stringByDeletingLastPathComponent];
      shaderPath = [exeDir stringByAppendingPathComponent:@"UtilShaders.metallib"];
    }
    if (shaderPath)
      library = [m_device newLibraryWithFile:shaderPath error:&error];
  }

  if (!library)
  {
    iLog->Log("EnsureDebugPipelineState: Unable to load shader library (%s)\n",
              error ? [[error localizedDescription] UTF8String] : "unknown error");
    return false;
  }

  id<MTLFunction> vertexFunction = [library newFunctionWithName:@"color_vertex"];
  id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"simple_fragment"];

  if (!vertexFunction || !fragmentFunction)
  {
    iLog->Log("EnsureDebugPipelineState: Missing Metal shader functions (vertex=%p fragment=%p)\n",
              vertexFunction, fragmentFunction);
    if (vertexFunction) [vertexFunction release];
    if (fragmentFunction) [fragmentFunction release];
    [library release];
    return false;
  }

  MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
  descriptor.vertexFunction = vertexFunction;
  descriptor.fragmentFunction = fragmentFunction;
  descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  descriptor.colorAttachments[0].blendingEnabled = YES;
  descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
  descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
  descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
  descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
  descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
  descriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

  MTLVertexDescriptor *vertexDescriptor = [[MTLVertexDescriptor alloc] init];
  vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
  vertexDescriptor.attributes[0].offset = 0;
  vertexDescriptor.attributes[0].bufferIndex = 0;
  vertexDescriptor.attributes[1].format = MTLVertexFormatUChar4;
  vertexDescriptor.attributes[1].offset = sizeof(float) * 3;
  vertexDescriptor.attributes[1].bufferIndex = 0;
  vertexDescriptor.layouts[0].stride = sizeof(DebugVertex);
  vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
  descriptor.vertexDescriptor = vertexDescriptor;

  m_debugPipelineState = [m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
  if (!m_debugPipelineState)
  {
    iLog->Log("EnsureDebugPipelineState: Failed to create pipeline (%s)\n",
              error ? [[error localizedDescription] UTF8String] : "unknown error");
    [vertexDescriptor release];
    [descriptor release];
    [vertexFunction release];
    [fragmentFunction release];
    [library release];
    return false;
  }

  [vertexDescriptor release];
  [descriptor release];
  [vertexFunction release];
  [fragmentFunction release];
  [library release];

  return true;
}

void CMetalRenderer::QueueDebugCommand(MTLPrimitiveType primitive,
                                       const std::vector<DebugVertex> &verts,
                                       bool depthTest, bool depthWrite, bool blend)
{
  if (verts.empty())
    return;

  DebugCommand cmd;
  cmd.primitiveType = primitive;
  cmd.vertices = verts;
  cmd.depthTest = depthTest;
  cmd.depthWrite = depthWrite;
  cmd.blend = blend;
  m_debugCommands.emplace_back(std::move(cmd));
}

void CMetalRenderer::QueueDebugLine(const Vec3& a, const Vec3& b, const CFColor& color, int stateFlags)
{
  bool depthTest = false;
  bool depthWrite = false;
  bool blend = false;
  DecodeLineFlags(stateFlags, color, depthTest, depthWrite, blend);

  std::vector<DebugVertex> vertices;
  vertices.reserve(2);

  DebugVertex va;
  va.position[0] = a.x;
  va.position[1] = a.y;
  va.position[2] = a.z;
  va.color = PackColor(color);

  DebugVertex vb;
  vb.position[0] = b.x;
  vb.position[1] = b.y;
  vb.position[2] = b.z;
  vb.color = PackColor(color);

  vertices.push_back(va);
  vertices.push_back(vb);

  QueueDebugCommand(MTLPrimitiveTypeLine, vertices, depthTest, depthWrite, blend);
}

void CMetalRenderer::QueueDebugPoint(const Vec3& position, const CFColor& color, int stateFlags)
{
  bool depthTest = false;
  bool depthWrite = false;
  bool blend = false;
  DecodeLineFlags(stateFlags, color, depthTest, depthWrite, blend);

  DebugVertex v;
  v.position[0] = position.x;
  v.position[1] = position.y;
  v.position[2] = position.z;
  v.color = PackColor(color);

  std::vector<DebugVertex> vertices(1, v);
  QueueDebugCommand(MTLPrimitiveTypePoint, vertices, depthTest, depthWrite, blend);
}

void CMetalRenderer::QueueDebugBox(const Vec3& mins, const Vec3& maxs, const CFColor& color, bool solid)
{
  const Vec3 corners[8] = {
      Vec3(mins.x, mins.y, mins.z),
      Vec3(maxs.x, mins.y, mins.z),
      Vec3(maxs.x, maxs.y, mins.z),
      Vec3(mins.x, maxs.y, mins.z),
      Vec3(mins.x, mins.y, maxs.z),
      Vec3(maxs.x, mins.y, maxs.z),
      Vec3(maxs.x, maxs.y, maxs.z),
      Vec3(mins.x, maxs.y, maxs.z)
  };

  const auto makeVertex = [&](const Vec3& p) -> DebugVertex {
    DebugVertex v;
    v.position[0] = p.x;
    v.position[1] = p.y;
    v.position[2] = p.z;
    v.color = PackColor(color);
    return v;
  };

  if (solid)
  {
    static const int faceIndices[12][3] = {
        {0,1,2}, {0,2,3},
        {4,5,6}, {4,6,7},
        {0,1,5}, {0,5,4},
        {2,3,7}, {2,7,6},
        {1,2,6}, {1,6,5},
        {0,3,7}, {0,7,4}
    };

    std::vector<DebugVertex> vertices;
    vertices.reserve(12 * 3);
    for (const auto& idx : faceIndices)
    {
      vertices.push_back(makeVertex(corners[idx[0]]));
      vertices.push_back(makeVertex(corners[idx[1]]));
      vertices.push_back(makeVertex(corners[idx[2]]));
    }

    bool depthTest = true;
    bool depthWrite = false;
    bool blend = NeedsBlend(color);
    QueueDebugCommand(MTLPrimitiveTypeTriangle, vertices, depthTest, depthWrite, blend);
  }
  else
  {
    static const int edgeIndices[12][2] = {
        {0,1}, {1,2}, {2,3}, {3,0},
        {4,5}, {5,6}, {6,7}, {7,4},
        {0,4}, {1,5}, {2,6}, {3,7}
    };

    std::vector<DebugVertex> vertices;
    vertices.reserve(24);
    for (const auto& edge : edgeIndices)
    {
      vertices.push_back(makeVertex(corners[edge[0]]));
      vertices.push_back(makeVertex(corners[edge[1]]));
    }

    bool depthTest = true;
    bool depthWrite = false;
    bool blend = NeedsBlend(color);
    QueueDebugCommand(MTLPrimitiveTypeLine, vertices, depthTest, depthWrite, blend);
  }
}

void CMetalRenderer::QueueDebugSphere(const Vec3& mins, const Vec3& maxs, const CFColor& color, bool solid)
{
  const Vec3 center = (mins + maxs) * 0.5f;
  const Vec3 radii = (maxs - mins) * 0.5f;

  const float pi = 3.14159265359f;
  const int slices = 24;
  const int stacks = 12;

  const auto makePosition = [&](float theta, float phi) -> Vec3 {
    const float sinPhi = sinf(phi);
    const float cosPhi = cosf(phi);
    const float sinTheta = sinf(theta);
    const float cosTheta = cosf(theta);
    return Vec3(
        center.x + radii.x * sinPhi * cosTheta,
        center.y + radii.y * cosPhi,
        center.z + radii.z * sinPhi * sinTheta);
  };

  if (solid)
  {
    std::vector<DebugVertex> vertices;
    vertices.reserve(stacks * slices * 6);
    const uint32_t packedColor = PackColor(color);

    for (int stack = 0; stack < stacks; ++stack)
    {
      const float phi0 = pi * static_cast<float>(stack) / stacks;
      const float phi1 = pi * static_cast<float>(stack + 1) / stacks;
      for (int slice = 0; slice < slices; ++slice)
      {
        const float theta0 = 2.0f * pi * static_cast<float>(slice) / slices;
        const float theta1 = 2.0f * pi * static_cast<float>(slice + 1) / slices;

        const Vec3 p0 = makePosition(theta0, phi0);
        const Vec3 p1 = makePosition(theta1, phi0);
        const Vec3 p2 = makePosition(theta0, phi1);
        const Vec3 p3 = makePosition(theta1, phi1);

        DebugVertex v0{ {p0.x, p0.y, p0.z}, packedColor };
        DebugVertex v1{ {p1.x, p1.y, p1.z}, packedColor };
        DebugVertex v2{ {p2.x, p2.y, p2.z}, packedColor };
        DebugVertex v3{ {p3.x, p3.y, p3.z}, packedColor };

        vertices.push_back(v0);
        vertices.push_back(v1);
        vertices.push_back(v2);

        vertices.push_back(v1);
        vertices.push_back(v3);
        vertices.push_back(v2);
      }
    }

    bool depthTest = true;
    bool depthWrite = false;
    bool blend = NeedsBlend(color);
    QueueDebugCommand(MTLPrimitiveTypeTriangle, vertices, depthTest, depthWrite, blend);
  }
  else
  {
    const uint32_t packedColor = PackColor(color);
    const auto queueRing = [&](int axis) {
      std::vector<DebugVertex> ringVertices;
      ringVertices.reserve(slices + 1);

      for (int slice = 0; slice <= slices; ++slice)
      {
        const float theta = 2.0f * pi * static_cast<float>(slice) / slices;
        Vec3 point;
        switch (axis)
        {
          case 0: // XY plane
            point = Vec3(center.x + radii.x * cosf(theta),
                         center.y + radii.y * sinf(theta),
                         center.z);
            break;
          case 1: // XZ plane
            point = Vec3(center.x + radii.x * cosf(theta),
                         center.y,
                         center.z + radii.z * sinf(theta));
            break;
          default: // YZ plane
            point = Vec3(center.x,
                         center.y + radii.y * cosf(theta),
                         center.z + radii.z * sinf(theta));
            break;
        }

        DebugVertex v;
        v.position[0] = point.x;
        v.position[1] = point.y;
        v.position[2] = point.z;
        v.color = packedColor;
        ringVertices.push_back(v);
      }

      bool depthTest = true;
      bool depthWrite = false;
      bool blend = NeedsBlend(color);
      QueueDebugCommand(MTLPrimitiveTypeLineStrip, ringVertices, depthTest, depthWrite, blend);
    };

    queueRing(0);
    queueRing(1);
    queueRing(2);
  }
}

void CMetalRenderer::ApplyDebugRenderState(bool depthTest, bool depthWrite, bool blend)
{
  SetDepthTest(depthTest);
  SetDepthWrite(depthWrite);
  SetBlending(blend);
  ApplyRenderState();
}

void CMetalRenderer::RestoreDefaultRenderState()
{
  SetDepthTest(true);
  SetDepthWrite(true);
  SetBlending(false);
  ApplyRenderState();
}

void CMetalRenderer::FlushDebugCommands()
{
  if (m_debugCommands.empty())
    return;

  if (!m_renderEncoder)
  {
    m_debugCommands.clear();
    return;
  }

  if (!EnsureDebugPipelineState())
  {
    m_debugCommands.clear();
    return;
  }

  UpdateUniformBuffer();
  if (m_uniformBuffer)
  {
    [m_renderEncoder setVertexBuffer:m_uniformBuffer offset:0 atIndex:kMetalVertexUniformSlot];
    [m_renderEncoder setFragmentBuffer:m_uniformBuffer offset:0 atIndex:kMetalFragmentUniformSlot];
  }

  [m_renderEncoder setRenderPipelineState:m_debugPipelineState];
  m_currentPipelineState = m_debugPipelineState;

  for (const DebugCommand& cmd : m_debugCommands)
  {
    ApplyDebugRenderState(cmd.depthTest, cmd.depthWrite, cmd.blend);

    id<MTLBuffer> buffer = [m_device newBufferWithBytes:cmd.vertices.data()
                                                length:cmd.vertices.size() * sizeof(DebugVertex)
                                               options:MTLResourceStorageModeShared];
    if (!buffer)
      continue;

    [m_renderEncoder setVertexBuffer:buffer offset:0 atIndex:kMetalVertexStream_General];
    [m_renderEncoder setVertexBuffer:nil offset:0 atIndex:kMetalVertexStream_Tangents];
    [m_renderEncoder drawPrimitives:cmd.primitiveType
                         vertexStart:0
                         vertexCount:cmd.vertices.size()];

    [buffer release];
  }

  RestoreDefaultRenderState();
  m_debugCommands.clear();
}

WIN_HWND CMetalRenderer::Init(int x, int y, int width, int height, unsigned int cbpp,
                               int zbpp, int sbits, bool fullscreen, WIN_HINSTANCE hinst,
                               WIN_HWND Glhwnd, WIN_HDC Glhdc, WIN_HGLRC hGLrc, bool bReInit)
{
  // Initialize CMetalRenderer
  
  // Call base class Init() to create Metal device and initialize core renderer
  WIN_HWND result = CMetalBaseRenderer::Init(x, y, width, height, cbpp, zbpp, sbits,
                                             fullscreen, hinst, Glhwnd, Glhdc, hGLrc, bReInit);
  
  iLog->Log("CMetalRenderer::Init - Base renderer Init() returned %p\n", result);
  
  // Check if base renderer initialized successfully
  if (!m_isInitialized) {
    iLog->Log("CMetalRenderer::Init - Base renderer initialization failed (m_isInitialized=%d)\n", m_isInitialized);
    return nullptr;
  }
  
  // Create game window with Metal layer
  iLog->Log("CMetalRenderer::Init - Creating game window (%dx%d, fullscreen=%d)\n", width, height, fullscreen);
  if (!CreateGameWindow(width, height, fullscreen)) {
    iLog->Log("CMetalRenderer::Init - Failed to create game window\n");
    return nullptr;
  }
  
  // Display splash screen (equivalent to D3D9 DisplaySplash timing)
  iLog->Log("CMetalRenderer::Init - Displaying splash screen\n");
  // Temporarily disabled to debug AddressSanitizer crash
  DisplaySplash();
  
  // Now that Metal device is created, initialize managers
  iLog->Log("CMetalRenderer::Init - Initializing managers (device=%p)\n", m_device);
  if (!InitializeManagers()) {
    iLog->Log("CMetalRenderer::Init - Failed to initialize managers\n");
    return nullptr;
  }
  
  RegisterMetalConsoleVariables();
  const char* autoDumpEnv = getenv("FARCRY_METAL_DUMPSTATS");
  const bool autoDumpRequested = autoDumpEnv && autoDumpEnv[0] && autoDumpEnv[0] != '0';
  const char* diagFileEnv = getenv("FARCRY_METAL_DUMPSTATS_FILE");
  bool diagPathSet = false;
  if (diagFileEnv && diagFileEnv[0])
  {
    m_diagOutputPath = diagFileEnv;
    diagPathSet = true;
  }
  bool requestFileFound = false;
  if (!diagPathSet)
    diagPathSet = LoadDiagnosticsRequestFromFile(requestFileFound);
  const bool autoDump = autoDumpRequested || requestFileFound;
  if (autoDump)
  {
    DumpMetalDiagnostics();
  }
  
  iLog->Log("CMetalRenderer initialized successfully with managers and window\n");
  return (WIN_HWND)m_window;
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

void CMetalRenderer::SetTexClampMode(bool clamp) {
  if (!m_textureManager)
    return;
  m_textureManager->SetClampModeForLastTexture(clamp);
}

int CMetalRenderer::LoadAnimatedTexture(const char* format, const int nCount) {
  if (!format || nCount <= 0)
    return 0;
  if (!m_textureManager)
    return 0;

  for (int i = 0; i < m_LoadedAnimatedTextures.Count(); ++i) {
    AnimTexInfo* info = m_LoadedAnimatedTextures[i];
    if (!info)
      continue;
    if (std::strcmp(info->sName, format) == 0 && info->nFramesCount == nCount) {
      info->nRefCounter++;
      return i + 1;
    }
  }

  std::unique_ptr<AnimTexInfo> info(new AnimTexInfo());
  std::strncpy(info->sName, format, sizeof(info->sName) - 1);
  info->sName[sizeof(info->sName) - 1] = '\0';
  info->pBindIds = new int[nCount];
  std::memset(info->pBindIds, 0, sizeof(int) * nCount);

  const bool hasSpecifier = std::strchr(format, '%') != nullptr;
  AnimTexturePattern pattern = hasSpecifier ? AnimTexturePattern{format, 0}
                                            : DeriveAnimPattern(format);

  bool success = true;
  for (int frame = 0; frame < nCount; ++frame) {
    const int frameIndex = hasSpecifier ? frame : (pattern.firstFrame + frame);
    char filename[kMaxAnimTexturePath] = {};
    const int written = std::snprintf(filename, sizeof(filename), pattern.printfFormat.c_str(), frameIndex);
    if (written <= 0 || written >= static_cast<int>(sizeof(filename))) {
      success = false;
      break;
    }

    const int texId = m_textureManager->LoadTexture(filename);
    if (texId <= 0) {
      iLog->LogError("MetalRenderer: failed to load animated texture frame '%s'", filename);
      success = false;
      break;
    }

    info->pBindIds[info->nFramesCount++] = texId;
  }

  if (!success || info->nFramesCount != nCount) {
    for (int i = 0; i < info->nFramesCount; ++i)
      RemoveTexture(info->pBindIds[i]);
    delete[] info->pBindIds;
    return 0;
  }

  info->nRefCounter = 1;
  m_LoadedAnimatedTextures.Add(info.get());
  info.release();
  return m_LoadedAnimatedTextures.Count();
}

void CMetalRenderer::RemoveAnimatedTexture(AnimTexInfo* pInfo) {
  if (!pInfo)
    return;
  CRenderer::RemoveAnimatedTexture(pInfo);
}

AnimTexInfo* CMetalRenderer::GetAnimTexInfoFromId(int nId) {
  return CRenderer::GetAnimTexInfoFromId(nId);
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

void CMetalRenderer::EF_StartEf() {
  if (iTimer)
    m_RP.m_RealTime = iTimer->GetCurrTime();

  // Drain GPU flush time accumulated by command-buffer completion handlers
  // (background threads). exchange(0) is the only safe write from this thread.
  const float gpuMs = m_pendingGpuFlushMs.exchange(0.0f, std::memory_order_relaxed);
  if (gpuMs > 0.0f)
    m_RP.m_PS.m_fFlushTime += gpuMs;

  CRenderer::EF_StartEf();
  if (m_shaderManager) {
    m_shaderManager->EF_StartEf();
  }
}

CCObject *CMetalRenderer::EF_GetObject(bool bTemp, int num) {
  return m_shaderManager->EF_GetObject(bTemp, num);
}

void CMetalRenderer::EF_AddEf(int NumFog, CRendElement *re, IShader *ef,
                              SRenderShaderResources *sr, CCObject *obj,
                              int nTempl, IShader *efState, int nSort) {
  CRenderer::EF_AddEf_NotVirtual(NumFog, re, ef, sr, obj, nTempl, efState, nSort);
}

void CMetalRenderer::EF_EndEf3D(int nFlags) {
#if DEBUG
  static int s_endEf3DCount = 0;
  if (++s_endEf3DCount <= 3)
    iLog->Log("[Renderer] EF_EndEf3D call #%d nFlags=0x%x frame=%d", s_endEf3DCount, nFlags, m_nFrameID);
#endif

  const int recurse = SRendItem::m_RecurseLevel - 1;
  if (recurse < 0) {
    iLog->Log("Error: EF_EndEf3D without EF_StartEf");
    return;
  }

  // HDR: if flag set and HDR pipeline ready, render into float16 RT
  bool useHDR = (nFlags & SHDF_ALLOWHDR) && m_hdrEnabled
                && m_hdrColorRT != nil;
  if (useHDR) {
    if (!m_hdrToneMapPSO) {
      if (iLog) iLog->Log("Warning: HDR requested but tone-map PSO not ready — disabling for this frame");
      useHDR = false;
    } else {
      useHDR = BeginHDRPass();
    }
  }

  // Record end-of-list positions for all sort buckets
  for (int i = 0; i < NUMRI_LISTS; ++i) {
    SRendItem::m_EndRI[recurse][i] = SRendItem::m_RendItems[i].Num();
  }

  // Sort opaque items (GENERAL bucket) by shader/material for state batching
  {
    const int nStart = SRendItem::m_StartRI[recurse][EFSLIST_GENERAL_ID];
    const int nEnd   = SRendItem::m_EndRI[recurse][EFSLIST_GENERAL_ID];
    if (nEnd > nStart) {
      SRendItemPre *pItems = &SRendItem::m_RendItems[EFSLIST_GENERAL_ID][nStart];
      std::sort(pItems, pItems + (nEnd - nStart),
        [](const SRendItemPre &a, const SRendItemPre &b) {
          return a.SortVal.SortVal < b.SortVal.SortVal;
        });
    }
  }

  // Sort transparent/distance items
  {
    const int nStart = SRendItem::m_StartRI[recurse][EFSLIST_DISTSORT_ID];
    const int nEnd   = SRendItem::m_EndRI[recurse][EFSLIST_DISTSORT_ID];
    if (nEnd > nStart) {
      SRendItemPre *pItems = &SRendItem::m_RendItems[EFSLIST_DISTSORT_ID][nStart];
      std::sort(pItems, pItems + (nEnd - nStart),
        [](const SRendItemPre &a, const SRendItemPre &b) {
          return a.fDist > b.fDist;  // back-to-front for transparency
        });
    }
  }

  // Obtain (or create) the render encoder for this frame
  id<MTLRenderCommandEncoder> encoder = m_renderEncoder;
  if (!encoder) {
    iLog->Log("Warning: EF_EndEf3D — no active render encoder");
    SRendItem::m_RecurseLevel--;
    return;
  }

  // Draw helper: iterate one render-item bucket
  auto drawBucket = [&](int bucketId) {
    const int nStart = SRendItem::m_StartRI[recurse][bucketId];
    const int nEnd   = SRendItem::m_EndRI[recurse][bucketId];

    SShader *prevShader = nullptr;

    for (int i = nStart; i < nEnd; ++i) {
      SRendItemPre &ri = SRendItem::m_RendItems[bucketId][i];

      SShader *pShader = nullptr;
      SShader *pShaderState = nullptr;
      SRenderShaderResources *pRes = nullptr;
      int nObject = 0;
      int numFog = 0;
      SRendItem::mfGet(ri.SortVal, &nObject, &pShader, &pShaderState, &numFog, &pRes);

      if (!pShader || !ri.Item)
        continue;

      // Update model matrix from the object
      CCObject *pObj = (nObject > 0 && nObject < (int)m_RP.m_TempObjects.Num())
                       ? m_RP.m_TempObjects[nObject] : nullptr;
      if (pObj && m_uniformBufferCPU) {
        m_uniformBufferCPU->modelMatrix = pObj->m_Matrix;
        // Recompute MVP
        m_uniformBufferCPU->modelViewProjectionMatrix =
          m_projectionMatrix * m_viewMatrix * pObj->m_Matrix;
      }

      // Apply material colours from shader resources
      if (pRes && m_materialBufferCPU) {
        if (pRes->m_LMaterial) {
          m_materialBufferCPU->Ambient[0]  = pRes->m_LMaterial->Front.m_Ambient.r;
          m_materialBufferCPU->Ambient[1]  = pRes->m_LMaterial->Front.m_Ambient.g;
          m_materialBufferCPU->Ambient[2]  = pRes->m_LMaterial->Front.m_Ambient.b;
          m_materialBufferCPU->Ambient[3]  = pRes->m_LMaterial->Front.m_Ambient.a;
          m_materialBufferCPU->Diffuse[0]  = pRes->m_LMaterial->Front.m_Diffuse.r;
          m_materialBufferCPU->Diffuse[1]  = pRes->m_LMaterial->Front.m_Diffuse.g;
          m_materialBufferCPU->Diffuse[2]  = pRes->m_LMaterial->Front.m_Diffuse.b;
          m_materialBufferCPU->Diffuse[3]  = pRes->m_LMaterial->Front.m_Diffuse.a;
          m_materialBufferCPU->Specular[0] = pRes->m_LMaterial->Front.m_Specular.r;
          m_materialBufferCPU->Specular[1] = pRes->m_LMaterial->Front.m_Specular.g;
          m_materialBufferCPU->Specular[2] = pRes->m_LMaterial->Front.m_Specular.b;
          m_materialBufferCPU->Specular[3] = pRes->m_LMaterial->Front.m_Specular.a;
        }
      }

      // Bind PSO — use shader name to look up generated Metal pipeline
      if (pShader != prevShader && m_shaderManager) {
        id<MTLRenderPipelineState> pso =
          m_shaderManager->GetPipelineStateForShader(pShader->m_Name.c_str());
        if (!pso) {
          // Fall back to the format-based PSO
          pso = m_shaderManager->GetPipelineStateForFormat(
              m_RP.m_CurVFormat);
        }
        if (pso) {
          [encoder setRenderPipelineState:pso];
          prevShader = pShader;
        }
      }

      // Bind global and material uniforms
      if (m_uniformBuffer) {
        [encoder setVertexBuffer:m_uniformBuffer offset:0 atIndex:kMetalVertexUniformSlot];
        [encoder setFragmentBuffer:m_uniformBuffer offset:0 atIndex:kMetalFragmentUniformSlot];
      }
      if (m_materialBuffer) {
        [encoder setFragmentBuffer:m_materialBuffer offset:0 atIndex:kMetalMaterialSlot];
      }

      // Bind water noise table for water/ocean shaders
      if (m_waterNoiseBuffer && pShader) {
        const char* sName = pShader->m_Name.c_str();
        if (sName && (strstr(sName, "water") || strstr(sName, "Water")
                      || strstr(sName, "ocean") || strstr(sName, "Ocean")))
          [encoder setVertexBuffer:m_waterNoiseBuffer offset:0 atIndex:kMetalWaterNoiseSlot];
      }

      // Let the render element issue the actual Metal draw call
      SShaderPass *pPass = (pShader->m_HWTechniques.Num() > 0 &&
                            pShader->m_HWTechniques[0]->m_Passes.Num() > 0)
                           ? &pShader->m_HWTechniques[0]->m_Passes[0] : nullptr;
      m_RP.m_pCurObject    = pObj;
      m_RP.m_pShader       = pShader;
      m_RP.m_pShaderResources = pRes;
      m_RP.m_pRE = ri.Item;
      ri.Item->mfDraw(pShader, pPass);
    }
  };

  // Draw buckets in order: preprocess → stencil shadow → general → unsorted → distsort → last
  drawBucket(EFSLIST_GENERAL_ID);
  drawBucket(EFSLIST_DISTSORT_ID);
  drawBucket(EFSLIST_LAST_ID);

  // HDR: tone-map the float16 RT into the drawable
  if (useHDR) EndHDRPass();

  SRendItem::m_RecurseLevel--;
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
  return CRenderer::CreateLeafBuffer(bDynamic, szSource, pIndexedMesh);
}

CLeafBuffer *CMetalRenderer::CreateLeafBufferInitialized(
    void *pVertBuffer, int nVertCount, int nVertFormat, ushort *pIndices,
    int nIndices, int nPrimetiveType, const char *szSource,
    EBufferType eBufType, int nMatInfoCount, int nClientTextureBindID,
    bool (*PrepareBufferCallback)(CLeafBuffer *, bool), void *CustomData,
    bool bOnlyVideoBuffer, bool bPrecache) {
  return CRenderer::CreateLeafBufferInitialized(
      pVertBuffer, nVertCount, nVertFormat, pIndices, nIndices,
      nPrimetiveType, szSource, eBufType, nMatInfoCount, nClientTextureBindID,
      PrepareBufferCallback, CustomData, bOnlyVideoBuffer, bPrecache);
}

void CMetalRenderer::DeleteLeafBuffer(CLeafBuffer *pLBuffer) {
  CRenderer::DeleteLeafBuffer(pLBuffer);
}

#define ASSERT_UTILITY_RENDERER_INIT() \
  do { \
    if (!m_utilityRenderer) { \
      if (iLog) iLog->Log("%s: m_utilityRenderer is null — skipping", __FUNCTION__); \
      return; \
    } \
  } while(0)

// Utility rendering delegation
void CMetalRenderer::WriteXY(CXFont *currfont, int x, int y, float xscale,
                             float yscale, float r, float g, float b, float a,
                             const char *message, ...) {
  if (!message) return;
  char buf[4096];
  va_list args;
  va_start(args, message);
  vsnprintf(buf, sizeof(buf), message, args);
  va_end(args);

  SDrawTextInfo ti;
  ti.xscale = xscale;
  ti.yscale = yscale;
  ti.color[0] = r; ti.color[1] = g; ti.color[2] = b; ti.color[3] = a;
  ti.xfont = currfont;
  CRenderer::Draw2dText((float)x, (float)y, buf, ti);
}

void CMetalRenderer::Draw2dText(float posX, float posY, const char *szText,
                                SDrawTextInfo &info) {
  CRenderer::Draw2dText(posX, posY, szText, info);
}

void CMetalRenderer::Draw2dImage(float xpos, float ypos, float w, float h,
                                 int texture_id, float s0, float t0, float s1,
                                 float t1, float angle, float r, float g,
                                 float b, float a, float z) {
  if (!m_utilityRenderer) {
    if (iLog) iLog->Log("Draw2dImage: m_utilityRenderer is null — skipping");
    return;
  }
  m_utilityRenderer->Draw2dImage(xpos, ypos, w, h, texture_id, s0, t0, s1, t1,
                                   angle, r, g, b, a, z);
}

void CMetalRenderer::DrawImage(float xpos, float ypos, float w, float h,
                               int texture_id, float s0, float t0, float s1,
                               float t1, float r, float g, float b, float a) {
  if (!m_utilityRenderer) {
    if (iLog) iLog->Log("DrawImage: m_utilityRenderer is null — skipping");
    return;
  }
  m_utilityRenderer->DrawImage(xpos, ypos, w, h, texture_id, s0, t0, s1, t1,
                                 r, g, b, a);
}

int CMetalRenderer::SetPolygonMode(int mode) {
  if (!m_utilityRenderer) {
    if (iLog) iLog->Log("SetPolygonMode: m_utilityRenderer is null — skipping");
    return 0;
  }
  return m_utilityRenderer->SetPolygonMode(mode);
}

void CMetalRenderer::TransformTextureMatrix(float x, float y, float angle, float scale) {
  ASSERT_UTILITY_RENDERER_INIT();
  m_utilityRenderer->TransformTextureMatrix(x, y, angle, scale);
}

void CMetalRenderer::ResetTextureMatrix() {
  ASSERT_UTILITY_RENDERER_INIT();
  m_utilityRenderer->ResetTextureMatrix();
}

void CMetalRenderer::SetMaterialColor(float r, float g, float b, float a) {
  if (!m_utilityRenderer) {
    if (iLog) iLog->Log("SetMaterialColor: m_utilityRenderer is null — skipping");
    return;
  }
  m_utilityRenderer->SetMaterialColor(r, g, b, a);
}

int CMetalRenderer::GenerateAlphaGlowTexture(float k) {
  if (!m_utilityRenderer) return 0;
  return m_utilityRenderer->GenerateAlphaGlowTexture(k);
}

void CMetalRenderer::OnEntityDeleted(IEntityRender* pEntityRender) {
  if (m_utilityRenderer) m_utilityRenderer->OnEntityDeleted(pEntityRender);
}

void CMetalRenderer::SetGlobalShaderTemplateId(int nTemplateId) {
  if (m_utilityRenderer) m_utilityRenderer->SetGlobalShaderTemplateId(nTemplateId);
}

int CMetalRenderer::GetGlobalShaderTemplateId() {
  if (!m_utilityRenderer) return 0;
  return m_utilityRenderer->GetGlobalShaderTemplateId();
}

int CMetalRenderer::EnumAAFormats(TArray<SAAFormat>& Formats, bool bReset) {
  if (!m_utilityRenderer) return 0;
  return m_utilityRenderer->EnumAAFormats(Formats, bReset);
}

float CMetalRenderer::EF_GetWaterZElevation(float fX, float fY) {
  if (!m_utilityRenderer) return 0.0f;
  return m_utilityRenderer->EF_GetWaterZElevation(fX, fY);
}

void CMetalRenderer::Draw2dLine(float x1, float y1, float x2, float y2) {
  if (m_utilityRenderer) m_utilityRenderer->Draw2dLine(x1, y1, x2, y2);
}

void CMetalRenderer::SetLineWidth(float fWidth) {
  if (m_utilityRenderer) m_utilityRenderer->SetLineWidth(fWidth);
}

void CMetalRenderer::DrawLine(const Vec3& vPos1, const Vec3& vPos2) {
  if (m_utilityRenderer) m_utilityRenderer->DrawLine(vPos1, vPos2);
}

void CMetalRenderer::DrawLineColor(const Vec3& vPos1, const CFColor& vColor1,
                                   const Vec3& vPos2, const CFColor& vColor2) {
  if (m_utilityRenderer) m_utilityRenderer->DrawLineColor(vPos1, vColor1, vPos2, vColor2);
}

void CMetalRenderer::Graph(byte* g, int x, int y, int wdt, int hgt, int nC, int type,
                            char* text, CFColor& color, float fScale) {
  if (m_utilityRenderer) m_utilityRenderer->Graph(g, x, y, wdt, hgt, nC, type, text, color, fScale);
}

void CMetalRenderer::DrawBall(float x, float y, float z, float radius) {
  if (m_utilityRenderer) m_utilityRenderer->DrawBall(x, y, z, radius);
}

void CMetalRenderer::ResetToDefault() {
  if (m_utilityRenderer) m_utilityRenderer->ResetToDefault();
}

int CMetalRenderer::ScreenToTexture() {
  if (!m_utilityRenderer) return 0;
  return m_utilityRenderer->ScreenToTexture();
}

int CMetalRenderer::CreateRenderTarget(int nWidth, int nHeight, ETEX_Format eTF) {
  if (!m_utilityRenderer) { if (iLog) iLog->Log("CreateRenderTarget: m_utilityRenderer is null — skipping"); return 0; }
  return m_utilityRenderer->CreateRenderTarget(nWidth, nHeight, eTF);
}

bool CMetalRenderer::DestroyRenderTarget(int nHandle) {
  if (!m_utilityRenderer) { if (iLog) iLog->Log("DestroyRenderTarget: m_utilityRenderer is null — skipping"); return false; }
  return m_utilityRenderer->DestroyRenderTarget(nHandle);
}

bool CMetalRenderer::SetRenderTarget(int nHandle) {
  if (!m_utilityRenderer) { if (iLog) iLog->Log("SetRenderTarget: m_utilityRenderer is null — skipping"); return false; }
  return m_utilityRenderer->SetRenderTarget(nHandle);
}

void CMetalRenderer::FlushTextMessages() {
  ASSERT_UTILITY_RENDERER_INIT();
  m_utilityRenderer->FlushTextMessages();
}

void CMetalRenderer::TextToScreen(float x, float y, const char * format, ...) {
  if (!format || !iConsole)
    return;
    
  char buffer[512];
  va_list args;
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  
  CXFont* font = iConsole->GetFont();
  if (font && m_utilityRenderer) {
    WriteXY(font, (int)(0.01f * 800 * x), (int)(0.01f * 600 * y), 0.5f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, buffer);
  }
}

void CMetalRenderer::TextToScreenColor(int x, int y, float r, float g, float b, float a, const char * format, ...) {
  if (!format || !iConsole)
    return;
    
  char buffer[512];
  va_list args;
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  
  CXFont* font = iConsole->GetFont();
  if (font && m_utilityRenderer) {
    WriteXY(font, (int)(0.01f * 800 * x), (int)(0.01f * 600 * y), 0.5f, 1.0f, r, g, b, a, buffer);
  }
}

// Additional utility methods would be delegated similarly...

bool CMetalRenderer::InitializeManagers() {
  // If managers already exist, skip initialization (Init can be called multiple times)
  if (m_textureManager && m_shaderManager && m_utilityRenderer) {
    iLog->Log("InitializeManagers: Managers already initialized, skipping\n");
    return true;
  }
  
  assert(!m_textureManager && "InitializeManagers: Partial manager state - texture manager exists!");
  assert(!m_shaderManager && "InitializeManagers: Partial manager state - shader manager exists!");
  assert(!m_utilityRenderer && "InitializeManagers: Partial manager state - utility renderer exists!");
  
  // Initialize texture manager
  m_textureManager = std::make_unique<CMetalTextureManager>(this);
  if (!m_textureManager) {
    iLog->Log("Error: Failed to create Metal texture manager");
    return false;
  }
  assert(m_textureManager && "InitializeManagers: Texture manager creation failed!");

  // Initialize shader manager
  m_shaderManager =
      std::make_unique<CMetalShaderManager>(this, m_textureManager.get());
  if (!m_shaderManager) {
    iLog->Log("Error: Failed to create Metal shader manager");
    return false;
  }
  assert(m_shaderManager && "InitializeManagers: Shader manager creation failed!");

  // Initialize utility renderer
  m_utilityRenderer = std::make_unique<CMetalUtilityRenderer>(
      this, m_textureManager.get(), m_shaderManager.get());
  if (!m_utilityRenderer) {
    iLog->Log("Error: Failed to create Metal utility renderer");
    return false;
  }
  assert(m_utilityRenderer && "InitializeManagers: Utility renderer creation failed!");

  // Initialise HDR pipeline if the engine CVar is set
  m_hdrEnabled = (CV_r_hdrrendering != 0);
  if (m_hdrEnabled && !InitHDRPipeline()) {
    iLog->Log("Warning: HDR pipeline init failed – disabling HDR\n");
    m_hdrEnabled = false;
  }

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

bool CMetalRenderer::CreateGameWindow(int width, int height, bool fullscreen) {
  @autoreleasepool {
    iLog->Log("CreateGameWindow: Creating NSWindow (%dx%d, fullscreen=%d)\n", width, height, fullscreen);
    
    assert(m_device != nullptr && "Metal device must be created before creating window");
    assert(width > 0 && height > 0 && "Window dimensions must be positive");
    
    if (!m_device) {
      iLog->Log("CreateGameWindow: Error - Metal device not created yet\n");
      return false;
    }
    
    NSRect frame = NSMakeRect(100, 100, width, height);
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | 
                                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    
    m_window = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:styleMask
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    
    if (!m_window) {
      iLog->Log("CreateGameWindow: Error - Failed to create NSWindow\n");
      return false;
    }
    
    [m_window setTitle:@"Far Cry - macOS Metal Port"];
    [m_window setAcceptsMouseMovedEvents:YES];
    
    NSView* contentView = [m_window contentView];
    if (!contentView) {
      iLog->Log("CreateGameWindow: Error - No content view available\n");
      [m_window release];
      m_window = nil;
      return false;
    }
    
    m_windowMetalLayer = [[CAMetalLayer layer] retain];
    if (!m_windowMetalLayer) {
      iLog->Log("CreateGameWindow: Error - Failed to create CAMetalLayer\n");
      [m_window release];
      m_window = nil;
      return false;
    }
    
    assert(m_windowMetalLayer != nil && "Metal layer must be created");
    assert(m_window != nil && "Window must be created before setting layer");
    
    m_windowMetalLayer.device = m_device;
    m_windowMetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    m_windowMetalLayer.framebufferOnly = YES;
    m_windowMetalLayer.drawableSize = CGSizeMake(width, height);
    m_windowMetalLayer.maximumDrawableCount = 3;
    m_metalLayer = m_windowMetalLayer;
    
    [contentView setWantsLayer:YES];
    [contentView setLayer:m_windowMetalLayer];
    
    [m_window makeKeyAndOrderFront:nil];
    [m_window makeFirstResponder:contentView];
    
    [m_window retain];
    
    iLog->Log("CreateGameWindow: Window created successfully\n");
    iLog->Log("  Window: %p\n", m_window);
    iLog->Log("  Metal Layer: %p\n", m_windowMetalLayer);
    iLog->Log("  Metal Device: %s\n", [[m_device name] UTF8String]);
    
    return true;
  }
}

void CMetalRenderer::DestroyGameWindow() {
  @autoreleasepool {
    if (m_currentDrawable) {
      [m_currentDrawable release];
      m_currentDrawable = nil;
    }
    
    if (m_window && m_windowMetalLayer) {
      NSView* contentView = [m_window contentView];
      if (contentView && [contentView layer] == m_windowMetalLayer) {
        [contentView setLayer:nil];
        [contentView setWantsLayer:NO];
      }
    }
    
    if (m_windowMetalLayer) {
      [m_windowMetalLayer release];
      m_windowMetalLayer = nil;
    }
    m_metalLayer = nil;
    
    if (m_window) {
      [m_window close];
      [m_window release];
      [m_window release];
      m_window = nil;
    }
  }
}

// Export functions for the renderer
extern "C" {
// CreateRenderer is a convenience wrapper — NOT used by the engine at runtime.
// The engine always calls PackageRenderConstructor() via dlsym.
// This function is retained for manual/test usage only; dimensions should come
// from the engine-supplied init parameters, not hardcoded here.
#ifdef FARCRY_ENABLE_CREATE_RENDERER_STUB
IRenderer *CreateRenderer(int argc, char *argv[], SCryRenderInterface *sp) {
  CMetalRenderer *renderer = new CMetalRenderer();
  if (renderer && renderer->Init(0, 0, 1024, 768, 32, 24, 8, false, nullptr, 0,
                                 0, 0, false)) {
    return renderer;
  }
  delete renderer;
  return nullptr;
}
#endif
}

void CMetalRenderer::DrawBuffer(CVertexBuffer *src, SVertexStream *indicies,
                                int numindices, int offsindex, int prmode,
                                int vert_start, int vert_stop, CMatInfo *mi) {
  CMetalBaseRenderer::DrawBuffer(src, indicies, numindices, offsindex, prmode, vert_start, vert_stop, mi);
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

  return CMetalBaseRenderer::CreateBuffer(vertexcount, vertexformat, szSource, bDynamic);
}

void CMetalRenderer::ReleaseBuffer(CVertexBuffer *bufptr) {
  assert(bufptr && "ReleaseBuffer: Buffer pointer cannot be null!");
  
  if (!bufptr)
    return;

  CMetalBaseRenderer::ReleaseBuffer(bufptr);
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

  CMetalBaseRenderer::UpdateBuffer(dest, src, vertexcount, bUnLock, nOffs, Type);
}

void CMetalRenderer::CreateIndexBuffer(SVertexStream *dest, const void *src,
                                       int indexcount) {
  assert(dest && "CreateIndexBuffer: Destination stream cannot be null!");
  assert(src && "CreateIndexBuffer: Source data cannot be null!");
  assert(indexcount > 0 && "CreateIndexBuffer: Index count must be positive!");
  
  if (!dest || !src)
    return;

  CMetalBaseRenderer::CreateIndexBuffer(dest, src, indexcount);
}

void CMetalRenderer::UpdateIndexBuffer(SVertexStream *dest, const void *src,
                                       int indexcount, bool bUnLock) {
  assert(dest && "UpdateIndexBuffer: Destination stream cannot be null!");
  assert(src && "UpdateIndexBuffer: Source data cannot be null!");
  assert(indexcount > 0 && "UpdateIndexBuffer: Index count must be positive!");
  
  if (!dest || !src)
    return;

  CMetalBaseRenderer::UpdateIndexBuffer(dest, src, indexcount, bUnLock);
}

void CMetalRenderer::ReleaseIndexBuffer(SVertexStream *dest) {
  assert(dest && "ReleaseIndexBuffer: Destination stream cannot be null!");
  
  if (!dest)
    return;

  CMetalBaseRenderer::ReleaseIndexBuffer(dest);
}

// Drawing Methods Implementation
void CMetalRenderer::DrawTriStrip(CVertexBuffer *src, int vert_num) {
  CMetalBaseRenderer::DrawTriStrip(src, vert_num);
}

void *CMetalRenderer::GetDynVBPtr(int nVerts, int &nOffs, int Pool) {
  assert(Pool >= 0 && "GetDynVBPtr: pool index cannot be negative");
  if (nVerts <= 0)
    return CMetalBaseRenderer::GetDynVBPtr(0, nOffs, Pool);
  return CMetalBaseRenderer::GetDynVBPtr(nVerts, nOffs, Pool);
}

void CMetalRenderer::PrepareDynVBColortexDrawState() {
  if (!m_renderEncoder || !m_shaderManager)
    return;
  id<MTLRenderPipelineState> pso =
      m_shaderManager->GetPipelineStateForShader("colortex");
  if (pso) {
    m_currentPipelineState = pso;
    [m_renderEncoder setRenderPipelineState:pso];
  }
  SetShaderTangentRequirement(false);
  SetCullMode(R_CULL_DISABLE);
  if (m_textureManager)
    m_textureManager->ApplyCachedFragmentBindingsToEncoder(1);
}

void CMetalRenderer::DrawDynVB(int nOffs, int Pool, int nVerts) {
  if (nVerts <= 0 || Pool < 0 || Pool >= 2)
    return;
  if (!TryEnsureSwapchainRenderEncoderFor2D())
    return;
  PrepareDynVBColortexDrawState();
  CMetalBaseRenderer::DrawDynVB(nOffs, Pool, nVerts);
}

void CMetalRenderer::DrawDynVB(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F *pBuf,
                               ushort *pInds, int nVerts, int nInds,
                               int nPrimType) {
  if (!pBuf)
    return;
  if (nVerts <= 0)
    return;
  if (!TryEnsureSwapchainRenderEncoderFor2D())
    return;
  PrepareDynVBColortexDrawState();
  CMetalBaseRenderer::DrawDynVB(pBuf, pInds, nVerts, nInds, nPrimType);
}

void CMetalRenderer::SetFenceCompleted(CVertexBuffer *buffer) {
  if (!buffer)
    return;

  buffer->m_bFenceSet = 1;
}

// Debug and Utility Drawing Implementation
void CMetalRenderer::CheckError(const char *comment) {
  // Metal doesn't have the same error checking as OpenGL
  // Errors are typically handled through Metal's error reporting system
  if (comment) {
    iLog->Log("Metal renderer check: %s\n", comment);
  }
}

void CMetalRenderer::Draw3dBBox(const Vec3 &mins, const Vec3 &maxs,
                                int nPrimType) {
  Draw3dPrim(mins, maxs, nPrimType, nullptr);
}

void CMetalRenderer::Draw3dPrim(const Vec3 &mins, const Vec3 &maxs,
                                int nPrimType, const float *fRGBA) {
  CFColor color;
  if (fRGBA) {
    color.Set(fRGBA[0], fRGBA[1], fRGBA[2], fRGBA[3]);
  } else {
    color.Set(1.0f, 1.0f, 1.0f, 1.0f);
  }

  switch (nPrimType) {
    case DPRIM_LINE:
      QueueDebugLine(mins, maxs, color, 0);
      break;

    case DPRIM_WHIRE_BOX:
      QueueDebugBox(mins, maxs, color, false);
      break;

    case DPRIM_SOLID_BOX:
      QueueDebugBox(mins, maxs, color, true);
      break;

    case DPRIM_WHIRE_SPHERE:
      QueueDebugSphere(mins, maxs, color, false);
      break;

    case DPRIM_SOLID_SPHERE:
      QueueDebugSphere(mins, maxs, color, true);
      break;

    default:
      iLog->Log("Draw3dPrim: Unsupported primitive type %d\n", nPrimType);
      break;
  }
}

// State Management Implementation
void CMetalRenderer::SetState(int State) {
  if (m_currentState == State)
    return;

  m_currentState = State;

  bool depthTestEnabled = (State & GS_NODEPTHTEST) == 0;
  bool depthWriteEnabled = (State & GS_DEPTHWRITE) != 0;
  MTLCompareFunction depthFunction = CMetalStateCache::ConvertCompareFunction(State);

  SetDepthTest(depthTestEnabled);
  SetDepthWrite(depthWriteEnabled);
  SetDepthFunction(depthFunction);

  bool blendEnabled = (State & GS_BLEND_MASK) != 0;
  if (blendEnabled) {
    MTLBlendFactor srcBlend = CMetalStateCache::ConvertSourceBlendFactor(State);
    MTLBlendFactor dstBlend = CMetalStateCache::ConvertDestinationBlendFactor(State);
    SetBlending(true);
    SetBlendFactors(srcBlend, dstBlend, MTLBlendOperationAdd);
  } else {
    SetBlending(false);
  }

  m_colorWriteMask = CMetalStateCache::ConvertColorMask(State);

  ApplyRenderState();

  if (m_shaderManager && m_RP.m_pShader) {
    IShader *currentShader = static_cast<IShader *>(m_RP.m_pShader);
    m_shaderManager->ApplyShaderPipelineState(currentShader);
  }
}

void CMetalRenderer::SetCullMode(int mode) {
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

void CMetalRenderer::Set2DMode(bool enable, int ortox, int ortoy) {
    if (enable) {
        if (m_2DMode) {
            if (iLog) {
                iLog->Log("Set2DMode: request ignored because renderer is already in 2D mode\n");
            }
            return;
        }

        const int resolvedWidth = (ortox > 0) ? ortox
            : ((m_viewportWidth > 0) ? m_viewportWidth : ((m_width > 0) ? m_width : 1));
        const int resolvedHeight = (ortoy > 0) ? ortoy
            : ((m_viewportHeight > 0) ? m_viewportHeight : ((m_height > 0) ? m_height : 1));

        if (resolvedWidth <= 0 || resolvedHeight <= 0) {
            if (iLog) {
                iLog->Log("Set2DMode: unable to resolve valid orthographic dimensions (requested %d x %d)\n", ortox, ortoy);
            }
            return;
        }

        m_2DProjectionStack.push_back(m_projectionMatrix);
        m_2DViewStack.push_back(m_viewMatrix);

        const float invWidth = 2.0f / static_cast<float>(resolvedWidth);
        const float invHeight = -2.0f / static_cast<float>(resolvedHeight);

        m_projectionMatrix.SetIdentity();
        m_projectionMatrix(0,0) = invWidth;
        m_projectionMatrix(1,1) = invHeight;
        m_projectionMatrix(2,2) = 1.0f;
        m_projectionMatrix(3,0) = -1.0f;
        m_projectionMatrix(3,1) = 1.0f;
        m_projectionMatrix(3,2) = 0.0f;
        m_projectionMatrix(3,3) = 1.0f;

        m_viewMatrix.SetIdentity();

        m_2DMode = true;
        m_2DOriginX = resolvedWidth;
        m_2DOriginY = resolvedHeight;
        m_matrixDirty = true;

        if (iLog) {
            iLog->Log("Set2DMode: Enabled 2D mode (%dx%d)\n", resolvedWidth, resolvedHeight);
        }
    } else {
        if (!m_2DMode) {
            return;
        }

        if (!m_2DProjectionStack.empty()) {
            m_projectionMatrix = m_2DProjectionStack.back();
            m_2DProjectionStack.pop_back();
        } else {
            m_projectionMatrix.SetIdentity();
        }

        if (!m_2DViewStack.empty()) {
            m_viewMatrix = m_2DViewStack.back();
            m_2DViewStack.pop_back();
        } else {
            m_viewMatrix.SetIdentity();
        }

        m_2DMode = false;
        m_matrixDirty = true;

        if (iLog) {
            iLog->Log("Set2DMode: Disabled 2D mode\n");
        }
    }

    UpdateUniformBuffer();
}

bool CMetalRenderer::EnableFog(bool enable) {
  m_fogEnabled = enable;
  return true;
}

void CMetalRenderer::SetFog(float density, float fogstart, float fogend,
                            const float *color, int fogmode) {
  m_fogEnabled = true;
  CMetalBaseRenderer::SetFog(density, fogstart, fogend, color, fogmode);
}

void CMetalRenderer::EnableTexGen(bool enable) {
  m_texGenEnabled = enable;
}

void CMetalRenderer::SetTexgen(float scaleX, float scaleY, float translateX,
                               float translateY) {
  CMetalBaseRenderer::SetTexgen(scaleX, scaleY, translateX, translateY);
}

void CMetalRenderer::SetTexgen3D(float x1, float y1, float z1, float x2,
                                 float y2, float z2) {
  CMetalBaseRenderer::SetTexgen3D(x1, y1, z1, x2, y2, z2);
}

void CMetalRenderer::SetLodBias(float value) {
  m_lodBias = value;
}

void CMetalRenderer::EnableVSync(bool enable) {
  m_vSyncEnabled = enable;
  if (m_metalLayer) {
    m_metalLayer.displaySyncEnabled = enable ? YES : NO;
  }
}

// Matrix Management Implementation
void CMetalRenderer::PushMatrix() {
  CMetalBaseRenderer::PushMatrix();
}

void CMetalRenderer::RotateMatrix(float a, float x, float y, float z) {
  CMetalBaseRenderer::RotateMatrix(a, x, y, z);
  UpdateMatrices();
}

void CMetalRenderer::RotateMatrix(const Vec3 &angels) {
  CMetalBaseRenderer::RotateMatrix(angels);
  UpdateMatrices();
}

void CMetalRenderer::TranslateMatrix(float x, float y, float z) {
  CMetalBaseRenderer::TranslateMatrix(x, y, z);
  UpdateMatrices();
}

void CMetalRenderer::ScaleMatrix(float x, float y, float z) {
  CMetalBaseRenderer::ScaleMatrix(x, y, z);
  UpdateMatrices();
}

void CMetalRenderer::TranslateMatrix(const Vec3 &pos) {
  CMetalBaseRenderer::TranslateMatrix(pos);
  UpdateMatrices();
}

void CMetalRenderer::MultMatrix(float *mat) {
  assert(mat != nullptr && "MultMatrix: matrix pointer cannot be null");
  
  CMetalBaseRenderer::MultMatrix(mat);
  UpdateMatrices();
}

void CMetalRenderer::LoadMatrix(const Matrix44 *src) {
  assert(src != nullptr && "LoadMatrix: source matrix cannot be null");
  
  CMetalBaseRenderer::LoadMatrix(src);
  UpdateMatrices();
}

void CMetalRenderer::PopMatrix() {
  CMetalBaseRenderer::PopMatrix();
  UpdateMatrices();
}

void CMetalRenderer::EnableTMU(bool enable) {
  m_currentTMU = enable ? m_currentTMU : -1;
}

void CMetalRenderer::SelectTMU(int tnum) {
  assert(tnum >= 0 && tnum < MAX_TMU && "SelectTMU: texture unit index out of range");
  
  m_currentTMU = tnum;
}

// Display and Resolution Implementation
bool CMetalRenderer::ChangeDisplay(unsigned int width, unsigned int height,
                                   unsigned int cbpp) {
  assert(width > 0 && "ChangeDisplay: width must be positive");
  assert(height > 0 && "ChangeDisplay: height must be positive");
  assert(cbpp == 16 || cbpp == 24 || cbpp == 32 && "ChangeDisplay: bits per pixel must be 16, 24, or 32");
  
  return ChangeResolution(width, height, cbpp, 60, false);
}

void CMetalRenderer::ChangeViewport(unsigned int x, unsigned int y,
                                    unsigned int width, unsigned int height) {
  assert(width > 0 && "ChangeViewport: width must be positive");
  assert(height > 0 && "ChangeViewport: height must be positive");
  
  SetViewport(x, y, width, height);
}

bool CMetalRenderer::SaveTga(unsigned char *sourcedata, int sourceformat, int w,
                             int h, const char *filename, bool flip) {
  if (!sourcedata || !filename || w <= 0 || h <= 0)
    return false;

  return CRenderer::SaveTga(sourcedata, sourceformat, w, h, filename, flip);
}

// Screen Information Implementation
int CMetalRenderer::GetWidth() { return m_width; }

int CMetalRenderer::GetHeight() { return m_height; }

void CMetalRenderer::GetMemoryUsage(ICrySizer *Sizer) {
  if (!Sizer)
    return;

  SIZER_COMPONENT_NAME(Sizer, "MetalRenderer");
  Sizer->Add(*this);

  size_t debugBytes = sizeof(DebugCommand) * m_debugCommands.size();
  for (const DebugCommand& command : m_debugCommands) {
    debugBytes += command.vertices.capacity() * sizeof(DebugVertex);
  }
  Sizer->AddObject(&m_debugCommands, debugBytes);

  if (m_textureManager)
    Sizer->AddObject(m_textureManager.get(), sizeof(*m_textureManager));

  if (m_shaderManager)
    Sizer->AddObject(m_shaderManager.get(), sizeof(*m_shaderManager));

  if (m_utilityRenderer)
    Sizer->AddObject(m_utilityRenderer.get(), sizeof(*m_utilityRenderer));
}

void CMetalRenderer::ScreenShot(const char *filename) {
  char path[512] = {};

  if (filename && filename[0] != '\0') {
    size_t len = strlen(filename);
    if (len >= sizeof(path)) len = sizeof(path) - 1;
    memcpy(path, filename, len);
    path[len] = '\0';
  } else {
    for (int i = 0; i < 10000; ++i) {
      sprintf(path, "FarCry%04d.tga", i);
      FILE* fp = fxopen(path, "rb");
      if (!fp) break;
      fclose(fp);
      path[0] = '\0';
    }
    if (path[0] == '\0') {
      iLog->Log("ScreenShot: Unable to find free filename slot\n");
      return;
    }
  }

  // Prefer the drawable acquired this frame; fall back to the HDR RT if called
  // outside a frame. Never call nextDrawable here — it dequeues a slot that
  // would never be presented, starving the triple-buffer pool.
  id<MTLTexture> srcTex = nil;
  if (m_currentDrawable && m_currentDrawable.texture)
    srcTex = m_currentDrawable.texture;
  else if (m_hdrColorRT)
    srcTex = m_hdrColorRT;
  if (!srcTex) {
    iLog->Log("ScreenShot: No drawable or HDR RT available\n");
    return;
  }

  const NSUInteger width  = srcTex.width;
  const NSUInteger height = srcTex.height;
  if (width == 0 || height == 0) {
    iLog->Log("ScreenShot: Invalid drawable dimensions (%lu x %lu)\n",
              (unsigned long)width, (unsigned long)height);
    return;
  }

  // Blit GPU texture → CPU-readable staging buffer
  const NSUInteger bytesPerRow = width * 4;
  id<MTLBuffer> staging = [m_device newBufferWithLength:bytesPerRow * height
                                               options:MTLResourceStorageModeShared];
  if (!staging) { iLog->Log("ScreenShot: staging alloc failed\n"); return; }

  ReleaseRenderEncoder();

  id<MTLCommandBuffer> cb   = [m_commandQueue commandBuffer];
  id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
  [blit copyFromTexture:srcTex
           sourceSlice:0
           sourceLevel:0
          sourceOrigin:MTLOriginMake(0, 0, 0)
            sourceSize:MTLSizeMake(width, height, 1)
              toBuffer:staging
     destinationOffset:0
destinationBytesPerRow:bytesPerRow
destinationBytesPerImage:bytesPerRow * height];
  [blit endEncoding];
  [cb commit];
  [cb waitUntilCompleted];

  // BGRA → RGBA
  const uint8_t* src = (const uint8_t*)staging.contents;
  std::vector<uint8_t> rgba(width * height * 4);
  for (NSUInteger y = 0; y < height; ++y) {
    const uint8_t* row = src + y * bytesPerRow;
    uint8_t* dst = rgba.data() + y * bytesPerRow;
    for (NSUInteger x = 0; x < width; ++x) {
      dst[x*4+0] = row[x*4+2]; // R
      dst[x*4+1] = row[x*4+1]; // G
      dst[x*4+2] = row[x*4+0]; // B
      dst[x*4+3] = row[x*4+3]; // A
    }
  }

  [staging release];

  if (!CRenderer::SaveTga(rgba.data(), FORMAT_32_BIT,
                          (int)width, (int)height, path, true)) {
    iLog->Log("ScreenShot: Failed to save %s\n", path);
  } else {
    iLog->Log("ScreenShot saved to %s\n", path);
  }
}

int CMetalRenderer::GetColorBpp() { return m_cbpp; }

int CMetalRenderer::GetDepthBpp() { return m_zbpp; }

int CMetalRenderer::GetStencilBpp() { return m_sbpp; }

// Additional Essential Methods Implementation

static void transform_point(float out[4], const float m[16], const float in[4])
{
#define M(row,col)  m[col*4+row]
  out[0] = M(0, 0) * in[0] + M(0, 1) * in[1] + M(0, 2) * in[2] + M(0, 3) * in[3];
  out[1] = M(1, 0) * in[0] + M(1, 1) * in[1] + M(1, 2) * in[2] + M(1, 3) * in[3];
  out[2] = M(2, 0) * in[0] + M(2, 1) * in[1] + M(2, 2) * in[2] + M(2, 3) * in[3];
  out[3] = M(3, 0) * in[0] + M(3, 1) * in[1] + M(3, 2) * in[2] + M(3, 3) * in[3];
#undef M
}

void CMetalRenderer::ProjectToScreen(float ptx, float pty, float ptz, float *sx,
                                     float *sy, float *sz) {
  assert(sx != nullptr && "ProjectToScreen: output sx cannot be null");
  assert(sy != nullptr && "ProjectToScreen: output sy cannot be null");
  assert(sz != nullptr && "ProjectToScreen: output sz cannot be null");
  
  float projMatrix[16];
  float modelMatrix[16];
  int viewport[4] = {m_VX, m_VY, m_VWidth, m_VHeight};
  
  GetProjectionMatrix(projMatrix);
  GetModelViewMatrix(modelMatrix);
  
  float in[4], out[4];
  in[0] = ptx;
  in[1] = pty;
  in[2] = ptz;
  in[3] = 1.0f;
  
  transform_point(out, modelMatrix, in);
  transform_point(in, projMatrix, out);
  
  if (in[3] == 0.0f)
    return;
  
  in[0] /= in[3];
  in[1] /= in[3];
  in[2] /= in[3];
  
  *sx = viewport[0] + (1 + in[0]) * viewport[2] / 2.0f;
  *sy = viewport[1] + (1 + in[1]) * viewport[3] / 2.0f;
  *sz = (1 + in[2]) / 2.0f;
  
  *sx = *sx * 100.0f / m_width;
  *sy = 100.0f - *sy * 100.0f / m_height;
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
  
  float m[16], A[16];
  float in[4], out[4];
  
  in[0] = (sx - viewport[0]) * 2.0f / viewport[2] - 1.0f;
  in[1] = (sy - viewport[1]) * 2.0f / viewport[3] - 1.0f;
  in[2] = 2.0f * sz - 1.0f;
  in[3] = 1.0f;
  
  extern int g_CpuFlags;
  mathMatrixMultiply(A, (float *)projMatrix, (float *)modelMatrix, g_CpuFlags);
  mathMatrixInverse(m, A, g_CpuFlags);
  
  transform_point(out, m, in);
  if (out[3] == 0.0f)
    return 0;
  
  *px = out[0] / out[3];
  *py = out[1] / out[3];
  *pz = out[2] / out[3];
  return 1;
}

int CMetalRenderer::UnProjectFromScreen(float sx, float sy, float sz, float *px,
                                        float *py, float *pz) {
  assert(px != nullptr && "UnProjectFromScreen: output px cannot be null");
  assert(py != nullptr && "UnProjectFromScreen: output py cannot be null");
  assert(pz != nullptr && "UnProjectFromScreen: output pz cannot be null");
  
  float projMatrix[16];
  float modelMatrix[16];
  int viewport[4] = {m_VX, m_VY, m_VWidth, m_VHeight};
  
  GetModelViewMatrix(modelMatrix);
  GetProjectionMatrix(projMatrix);
  
  return UnProject(sx, sy, sz, px, py, pz, modelMatrix, projMatrix, viewport);
}

void CMetalRenderer::GetModelViewMatrix(float *mat) {
  assert(mat != nullptr && "GetModelViewMatrix: matrix pointer cannot be null");
  
  CMetalBaseRenderer::GetModelViewMatrix(mat);
}

void CMetalRenderer::GetModelViewMatrix(double *mat) {
  assert(mat != nullptr && "GetModelViewMatrix: matrix pointer cannot be null");
  
  CMetalBaseRenderer::GetModelViewMatrix(mat);
}

void CMetalRenderer::GetProjectionMatrix(double *mat) {
  assert(mat != nullptr && "GetProjectionMatrix: matrix pointer cannot be null");
  
  CMetalBaseRenderer::GetProjectionMatrix(mat);
}

void CMetalRenderer::GetProjectionMatrix(float *mat) {
  assert(mat != nullptr && "GetProjectionMatrix: matrix pointer cannot be null");
  
  CMetalBaseRenderer::GetProjectionMatrix(mat);
}

Vec3 CMetalRenderer::GetUnProject(const Vec3 &WindowCoords,
                                  const CCamera &cam) {
  float px, py, pz;
  int viewport[4] = {m_VX, m_VY, m_VWidth, m_VHeight};
  
  float modelMatrix[16];
  float projMatrix[16];
  
  GetModelViewMatrix(modelMatrix);
  GetProjectionMatrix(projMatrix);
  
  if (UnProject(WindowCoords.x, WindowCoords.y, WindowCoords.z, &px, &py, &pz, modelMatrix, projMatrix, viewport)) {
    return Vec3(px, py, pz);
  }
  
  return Vec3(0, 0, 0);
}

void CMetalRenderer::RenderToViewport(const CCamera &cam, float x, float y,
                                      float width, float height) {
  SetViewport((int)x, (int)y, (int)width, (int)height);
  SetCamera(cam);
}

void CMetalRenderer::DisplaySplash() {
#if defined(__APPLE__) && defined(__MACH__)
    @autoreleasepool {
        iLog->Log("DisplaySplash: Starting splash screen display\\n");
        
        // Look for fcsplash.bmp in the app bundle or current directory
        NSString *splashPath = nil;
        
        // First try app bundle Resources directory
        NSBundle *bundle = [NSBundle mainBundle];
        if (bundle) {
            splashPath = [bundle pathForResource:@"fcsplash" ofType:@"bmp"];
            if (splashPath) {
                iLog->Log("DisplaySplash: Found splash in bundle: %s\\n", [splashPath UTF8String]);
            }
        }
        
        // Try Resources directory relative to executable
        if (!splashPath && m_window) {
            NSString *exePath = [[NSBundle mainBundle] bundlePath];
            if (exePath) {
                NSString *resourcesPath = [exePath stringByAppendingPathComponent:@"Contents/Resources/fcsplash.bmp"];
                if ([[NSFileManager defaultManager] fileExistsAtPath:resourcesPath]) {
                    splashPath = resourcesPath;
                    iLog->Log("DisplaySplash: Found splash in Resources: %s\\n", [splashPath UTF8String]);
                }
            }
        }
        
        // If not in bundle, try current working directory
        if (!splashPath) {
            NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
            splashPath = [cwd stringByAppendingPathComponent:@"fcsplash.bmp"];
            
            if (![[NSFileManager defaultManager] fileExistsAtPath:splashPath]) {
                // Try parent directory (source root)
                splashPath = [[cwd stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"fcsplash.bmp"];
            }
            
            if (![[NSFileManager defaultManager] fileExistsAtPath:splashPath]) {
                iLog->Log("DisplaySplash: fcsplash.bmp not found (checked bundle, Resources, cwd, parent)\\n");
                return;
            }
            iLog->Log("DisplaySplash: Found splash in filesystem: %s\\n", [splashPath UTF8String]);
        }
        
        // Load the image
        NSImage *splashImage = [[NSImage alloc] initWithContentsOfFile:splashPath];
        if (!splashImage) {
            iLog->Log("DisplaySplash: Failed to load image from %s\\n", [splashPath UTF8String]);
            return;
        }
        
        // Get window frame if available, otherwise use screen size
        NSRect windowFrame = NSZeroRect;
        if (m_window) {
            windowFrame = [m_window frame];
        } else {
            NSScreen *mainScreen = [NSScreen mainScreen];
            if (mainScreen) {
                windowFrame = [mainScreen frame];
            }
        }
        
        // Get image size and center it
        NSSize imageSize = [splashImage size];
        if (imageSize.width == 0 || imageSize.height == 0) {
            NSImageRep *rep = [[splashImage representations] firstObject];
            if (rep) {
                imageSize = NSMakeSize([rep pixelsWide], [rep pixelsHigh]);
            }
        }
        
        // Center splash on screen
        NSRect splashFrame = NSMakeRect(
            windowFrame.origin.x + (windowFrame.size.width - imageSize.width) / 2,
            windowFrame.origin.y + (windowFrame.size.height - imageSize.height) / 2,
            imageSize.width,
            imageSize.height
        );
        
        // Create temporary overlay window for splash
        NSWindow *splashWindow = [[NSWindow alloc] initWithContentRect:splashFrame
                                                             styleMask:NSWindowStyleMaskBorderless
                                                               backing:NSBackingStoreBuffered
                                                                 defer:NO];
        [splashWindow setOpaque:NO];
        [splashWindow setBackgroundColor:[NSColor clearColor]];
        [splashWindow setLevel:NSFloatingWindowLevel];
        [splashWindow setIgnoresMouseEvents:YES];
        [splashWindow setReleasedWhenClosed:NO];
        
        // Create image view
        NSImageView *splashView = [[[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, imageSize.width, imageSize.height)] autorelease];
        [splashView setImage:splashImage];
        [splashView setImageScaling:NSImageScaleNone];
        [splashView setImageAlignment:NSImageAlignCenter];
        
        [[splashWindow contentView] addSubview:splashView];
        
        [splashWindow makeKeyAndOrderFront:nil];
        [splashWindow display];
        
        iLog->Log("DisplaySplash: Splash window %p displayed (%fx%f at %f,%f)\\n", 
                  splashWindow, imageSize.width, imageSize.height, splashFrame.origin.x, splashFrame.origin.y);
        
        [splashImage autorelease];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), 
                      dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [splashWindow close];
                iLog->Log("DisplaySplash: Splash window closed\\n");
            }
        });
        
        [splashWindow release];
    }
#endif
}

// Missing IRenderer method implementations
void CMetalRenderer::BeginFrame() {
  if (m_textureManager)
    m_textureManager->Update(m_RP.m_RealTime);

#ifdef DEBUG
  if (m_metalGPUCaptureFlag > 0) {
    MTLCaptureManager* capMgr = [MTLCaptureManager sharedCaptureManager];
    MTLCaptureDescriptor* desc = [[MTLCaptureDescriptor alloc] init];
    desc.captureObject = m_device;
    NSError* captureErr = nil;
    if (![capMgr startCaptureWithDescriptor:desc error:&captureErr])
      iLog->Log("GPU Capture start failed: %s\n", captureErr ? [[captureErr localizedDescription] UTF8String] : "");
  }
#endif

  CMetalBaseRenderer::BeginFrame();

}

void CMetalRenderer::Update() {
  // Don't process events here - System::Update handles that via ProcessMacOSEvents
  // Just call base class Update which calls EndFrame
  CMetalBaseRenderer::Update();
  
  // Flush text messages at end of frame (for UI rendering)
  FlushTextMessages();
}

void CMetalRenderer::EndFrame() {
  FlushDebugCommands();
  CMetalBaseRenderer::EndFrame();

#ifdef DEBUG
  if (m_metalGPUCaptureFlag > 0) {
    [[MTLCaptureManager sharedCaptureManager] stopCapture];
    m_metalGPUCaptureFlag = 0;
  }
#endif

  if (m_metalDumpStatsFlag > 0) {
    DumpMetalDiagnostics();
    m_metalDumpStatsFlag = 0;
  }
}

void CMetalRenderer::RegisterMetalConsoleVariables()
{
  if (!iConsole)
    return;
  iConsole->Register("metal_dumpstats", &m_metalDumpStatsFlag, 0, 0,
                     "Set to 1 to log Metal renderer diagnostics at the end of the next frame");

#ifdef DEBUG
  // Register GPU capture trigger (DEBUG builds only)
  iConsole->Register("metal_gpucapture", &m_metalGPUCaptureFlag, 0, 0,
                     "Set to 1 to trigger a single-frame GPU capture via MTLCaptureManager");
#endif
}

void CMetalRenderer::UnregisterMetalConsoleVariables()
{
  if (!iConsole)
    return;
  iConsole->UnregisterVariable("metal_dumpstats");
#ifdef DEBUG
  iConsole->UnregisterVariable("metal_gpucapture");
#endif
}

void CMetalRenderer::DumpMetalDiagnostics() const
{
  const int drawCalls = m_numDrawCalls;
  const int triangles = m_numTriangles;
  const int shaderCount = m_shaderManager ? m_shaderManager->GetShaderCount() : 0;
  const int textureCount = m_textureManager ? m_textureManager->GetTextureCount() : 0;
  const size_t textureBytes =
      m_textureManager ? m_textureManager->GetTotalTextureMemory() : 0;
  const double textureMB = textureBytes / (1024.0 * 1024.0);

  size_t pipelineStates = 0;
  size_t depthStates = 0;
  size_t samplerStates = 0;
  if (m_stateCache)
  {
    pipelineStates = m_stateCache->GetPipelineStateCacheSize();
    depthStates = m_stateCache->GetDepthStencilStateCacheSize();
    samplerStates = m_stateCache->GetSamplerStateCacheSize();
  }

  if (iLog)
  {
    iLog->Log("Metal diagnostics snapshot:");
    iLog->Log("  Draw calls: %d | Triangles: %d", drawCalls, triangles);
    iLog->Log("  Shaders loaded: %d", shaderCount);
    iLog->Log("  Textures: %d (%.2f MB)", textureCount, textureMB);
    iLog->Log("  Pipeline cache: %zu states (depth: %zu, sampler: %zu)",
              pipelineStates, depthStates, samplerStates);
  }

  if (!m_diagOutputPath.empty())
  {
    WriteDiagnosticsJson(drawCalls, triangles, shaderCount, textureCount,
                         textureBytes, pipelineStates, depthStates,
                         samplerStates);
  }
}

void CMetalRenderer::WriteDiagnosticsJson(int drawCalls, int triangles,
                                          int shaderCount, int textureCount,
                                          size_t textureBytes,
                                          size_t pipelineStates,
                                          size_t depthStates,
                                          size_t samplerStates) const
{
  std::ofstream file(m_diagOutputPath.c_str(), std::ios::out | std::ios::trunc);
  if (!file.is_open())
    return;

  const double textureMB = textureBytes / (1024.0 * 1024.0);

  file.setf(std::ios::fixed);
  file << std::setprecision(4);
  file << "{\n";
  file << "  \"drawCalls\": " << drawCalls << ",\n";
  file << "  \"triangles\": " << triangles << ",\n";
  file << "  \"shaderCount\": " << shaderCount << ",\n";
  file << "  \"textureCount\": " << textureCount << ",\n";
  file << "  \"textureBytes\": " << static_cast<unsigned long long>(textureBytes) << ",\n";
  file << "  \"textureMB\": " << textureMB << ",\n";
  file << "  \"pipelineStates\": " << static_cast<unsigned long long>(pipelineStates) << ",\n";
  file << "  \"depthStates\": " << static_cast<unsigned long long>(depthStates) << ",\n";
  file << "  \"samplerStates\": " << static_cast<unsigned long long>(samplerStates) << "\n";
  file << "}\n";
}

bool CMetalRenderer::LoadDiagnosticsRequestFromFile(bool& requestFileFound)
{
  requestFileFound = false;

  auto tryRequest = [this](const std::string& directory) -> bool {
    if (directory.empty())
      return false;
    std::string requestPath = directory + "/metal_diag_request.txt";
    std::ifstream file(requestPath.c_str());
    if (!file.is_open())
      return false;

    std::string line;
    std::getline(file, line);
    file.close();

    if (line.empty())
      return false;

    while (!line.empty())
    {
      char last = line.back();
      if (last == '\n' || last == '\r' || last == ' ' || last == '\t')
        line.pop_back();
      else
        break;
    }

    if (line.empty())
      return false;

    m_diagOutputPath = line;
    return true;
  };

  char cwd[PATH_MAX];
  if (getcwd(cwd, sizeof(cwd)))
  {
    if (tryRequest(std::string(cwd)))
    {
      requestFileFound = true;
      return true;
    }
  }

  NSBundle* bundle = [NSBundle mainBundle];
  if (bundle)
  {
    NSString* bundlePath = [bundle bundlePath];
    if (bundlePath)
    {
      NSString* buildDir = [bundlePath stringByDeletingLastPathComponent];
      NSString* repoRoot = buildDir ? [buildDir stringByDeletingLastPathComponent] : nil;
      if (repoRoot && tryRequest(std::string([repoRoot UTF8String])))
      {
        requestFileFound = true;
        return true;
      }

      if (buildDir)
      {
        std::string fallback = std::string([buildDir UTF8String]) + "/metal_diag.json";
        m_diagOutputPath = fallback;
        return true;
      }
    }
  }

  return false;
}

void CMetalRenderer::SetScissor(int x, int y, int width, int height) {
  if (x < 0) {
    if (iLog) iLog->Log("SetScissor: x=%d clamped to 0", x);
    x = 0;
  }
  if (y < 0) {
    if (iLog) iLog->Log("SetScissor: y=%d clamped to 0", y);
    y = 0;
  }
  if (width <= 0 || height <= 0)
    return;
  if (!m_renderEncoder)
    return;

  CMetalBaseRenderer::SetScissor(x, y, width, height);
}

int CMetalRenderer::GetFeatures() {
  int features = CMetalBaseRenderer::GetFeatures();
  features |= RFT_DETAILTEXTURE;
  features |= RFT_DIRECTACCESSTOVIDEOMEMORY;
  features |= RFT_OCCLUSIONTEST;
  features |= RFT_DEPTHMAPS;
  features |= RFT_SHADOWMAP_SELFSHADOW;
  return features;
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
  return m_device != nil;
}

bool CMetalRenderer::DeleteContext(WIN_HWND hWnd) {
  ReleaseRenderEncoder();
  if (m_currentCommandBuffer) {
    [m_currentCommandBuffer commit];
    [m_currentCommandBuffer waitUntilCompleted];
    m_currentCommandBuffer = nil;
  }
  if (m_currentDrawable) {
    [m_currentDrawable release];
    m_currentDrawable = nil;
  }
  
  if (hWnd == m_window) {
    m_window = nil;
    m_windowMetalLayer = nil;
    m_metalLayer = nil;
  }
  
  return true;
}

void CMetalRenderer::FreeResources(int nFlags) {
  if (nFlags & FRR_TEXTURES) {
    if (m_textureManager) {
      m_textureManager->ClearAllTextures();
    }
  }
  
  if (nFlags & FRR_SHADERS) {
    if (m_shaderManager) {
      m_shaderManager->ClearAllShaders();
    }
  }
  
  if (nFlags & FRR_REINITHW) {
    ReleaseRenderEncoder();
    if (m_currentCommandBuffer) {
      [m_currentCommandBuffer commit];
      [m_currentCommandBuffer waitUntilCompleted];
      m_currentCommandBuffer = nil;
    }
    if (m_currentDrawable) {
      [m_currentDrawable release];
      m_currentDrawable = nil;
    }
    
    CMetalBaseRenderer::FreeResources(nFlags);
  }
  
  if (nFlags & FRR_ALL) {
    if (m_textureManager) {
      m_textureManager->ClearAllTextures();
    }
    if (m_shaderManager) {
      m_shaderManager->ClearAllShaders();
    }
    CMetalBaseRenderer::FreeResources(nFlags);
  }
}

void CMetalRenderer::ShareResources(IRenderer *renderer) {
  if (!renderer || renderer == this) {
    return;
  }
  
  CMetalRenderer* metalRenderer = dynamic_cast<CMetalRenderer*>(renderer);
  if (!metalRenderer) {
    iLog->Log("Warning: ShareResources: Cannot share with non-Metal renderer\n");
    return;
  }
  
  if (metalRenderer->m_device != m_device) {
    iLog->Log("Warning: ShareResources: Renderers use different Metal devices, sharing not supported\n");
    return;
  }
  
  if (!m_textureManager || !m_shaderManager || 
      !metalRenderer->m_textureManager || !metalRenderer->m_shaderManager) {
    iLog->Log("Warning: ShareResources: Managers not initialized, cannot share resources\n");
    return;
  }
  
  m_textureManager->ShareCacheWith(metalRenderer->m_textureManager.get());
  m_shaderManager->ShareCacheWith(metalRenderer->m_shaderManager.get());
  
  iLog->Log("ShareResources: Bidirectionally shared texture and shader caches between Metal renderers\n");
}

bool CMetalRenderer::ChangeResolution(int nNewWidth, int nNewHeight,
                                      int nNewColDepth, int nNewRefreshHZ,
                                      bool bFullScreen) {
  if (!EnsureBackbufferSize(static_cast<NSUInteger>(nNewWidth),
                            static_cast<NSUInteger>(nNewHeight))) {
    return false;
  }
  m_cbpp = nNewColDepth;
  
  if (m_metalLayer) {
    CGSize size = CGSizeMake(nNewWidth, nNewHeight);
    m_metalLayer.drawableSize = size;
  }
  
  SetViewport(0, 0, nNewWidth, nNewHeight);
  return true;
}

void CMetalRenderer::RefreshResources(int nFlags) {
  if (nFlags & FRO_TEXTURES) {
    if (m_shaderManager) {
      m_shaderManager->EF_ReloadTextures();
    }
  }
  
  if (nFlags & (FRO_SHADERS | FRO_SHADERTEXTURES)) {
    if (m_shaderManager) {
      m_shaderManager->EF_ReloadShaderFiles(0);
      if (nFlags & FRO_SHADERTEXTURES) {
        m_shaderManager->EF_ReloadTextures();
      }
    }
  }
}

bool CMetalRenderer::SetCurrentContext(WIN_HWND hWnd) {
  if (!hWnd) {
    return false;
  }
  
  if (hWnd == m_window) {
    return true;
  }
  
  NSWindow* window = (__bridge NSWindow*)hWnd;
  if (!window) {
    return false;
  }
  
  NSView* contentView = [window contentView];
  if (!contentView) {
    return false;
  }
  
  CAMetalLayer* metalLayer = nil;
  if ([contentView.layer isKindOfClass:[CAMetalLayer class]]) {
    metalLayer = (CAMetalLayer*)contentView.layer;
  } else {
    metalLayer = [CAMetalLayer layer];
    contentView.layer = metalLayer;
    contentView.wantsLayer = YES;
  }
  
  if (metalLayer && m_device) {
    metalLayer.device = m_device;
    metalLayer.maximumDrawableCount = 3;
    m_window = window;
    m_windowMetalLayer = metalLayer;
    m_metalLayer = metalLayer;
    
    ReleaseRenderEncoder();
    if (m_currentCommandBuffer) {
      [m_currentCommandBuffer commit];
      m_currentCommandBuffer = nil;
    }
    if (m_currentDrawable) {
      [m_currentDrawable release];
      m_currentDrawable = nil;
    }
    
    return true;
  }
  
  return false;
}

int CMetalRenderer::EnumDisplayFormats(TArray<SDispFormat> &Formats,
                                       bool bReset) {
  if (bReset) {
    Formats.Free();
  }
  
  SDispFormat fmt;
  fmt.m_BPP = 32;
  fmt.m_Width = m_width;
  fmt.m_Height = m_height;
  Formats.AddElem(fmt);
  
  return Formats.Num();
}

int CMetalRenderer::GetMaxTextureMemory() {
  if (m_device) {
    return (int)[m_device recommendedMaxWorkingSetSize];
  }
  return 512 * 1024 * 1024;
}

// Init implementation moved to earlier in file (after constructor)

void CMetalRenderer::PreLoad() {
  EF_InitFogVolumes();

  for (int i = 0; i < VERTEX_FORMAT_NUMS; i++)
  {
    for (int j = 0; j < VERTEX_FORMAT_NUMS; j++)
    {
      SVertBufComps Cps[2];
      GetVertBufComps(&Cps[0], i);
      GetVertBufComps(&Cps[1], j);
      bool bNeedTC      = Cps[1].m_bHasTC       | Cps[0].m_bHasTC;
      bool bNeedCol     = Cps[1].m_bHasColors    | Cps[0].m_bHasColors;
      bool bNeedSecCol  = Cps[1].m_bHasSecColors | Cps[0].m_bHasSecColors;
      bool bNeedNormals = Cps[1].m_bHasNormals   | Cps[0].m_bHasNormals;
      m_RP.m_VFormatsMerge[i][j] = VertFormatForComponents(bNeedCol, bNeedSecCol, bNeedNormals, bNeedTC);
    }
  }
}

void CMetalRenderer::Release() {
  FreeResources(FRR_ALL);
}

void CMetalRenderer::PostLoad() {
  m_nFrameLoad++;
  if (!m_bEditor) {
    if (m_textureManager) {
      // PreloadScreenFxMaps is typically in texture manager
      // For now, just ensure textures are ready
    }
    Reset();
  }
  m_bTemporaryDisabledSFX = false;
}

// Tears down the renderer.  Sequence:
//   1. Unregister console variables (must happen before device is released).
//   2. Delegate to CMetalBaseRenderer::ShutDown which:
//        - Waits for all in-flight command buffers to complete.
//        - Ends and releases m_renderEncoder if active.
//        - Commits and nils m_currentCommandBuffer.
//        - Releases m_currentDrawable.
//        - Destroys all pools, uniform buffers, depth targets, and caches.
//        - Nils m_device, m_commandQueue, m_blitCommandQueue, m_metalLayer.
//        - Sets m_isInitialized = false.
//
// @param bReInit  If true the engine plans to re-initialize; buffers may be
//                 recreated without a full device teardown.
void CMetalRenderer::ShutDown(bool bReInit) {
  UnregisterMetalConsoleVariables();
  CMetalBaseRenderer::ShutDown(bReInit);
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
 * - Logs errors to both console (iLog->Log) and /tmp/farcry_metal_create.log
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

  
  assert(argc >= 0 && "CreateMetalRendererInstance: argc cannot be negative!");
  assert(sp != nullptr && "CreateMetalRendererInstance: SCryRenderInterface cannot be null!");
  sp->ipLog->Log("CreateMetalRendererInstance called\n");

  iLog->Log(
    "Creating CMetalRenderer (new architecture)\n",
    "argc=%d, argv=%p, sp=%p\n", argc, argv, sp
    );


  // Initialize global engine interface pointers BEFORE creating renderer
  // The CRenderer constructor needs these to register console variables
    iSystem = sp->ipSystem;
    iConsole = sp->ipConsole;
    iLog = sp->ipLog;
    iTimer = sp->ipTimer;
    iLog->Log("Initialized engine interfaces: iSystem=%p, iConsole=%p, iLog=%p, iTimer=%p\n",
           iSystem, iConsole, iLog, iTimer);


  CMetalRenderer *renderer = new CMetalRenderer();
  assert(renderer && "CreateMetalRendererInstance: Failed to allocate CMetalRenderer!");

  iLog->Log("CMetalRenderer created: %p\n", renderer);

  // Get display settings from SCryRenderInterface or system defaults
  int width = 800;
  int height = 600;
  int colorBpp = 32;
  int depthBpp = 24;
  int stencilBpp = 8;
  bool fullscreen = false;

  // Use passed-in display settings or defaults
  // SCryRenderInterface provides system services (log, console, timer), not display settings

  
  // Display settings come from function parameters or defaults
  {
    // Fallback: Get primary screen resolution from NSScreen
    @autoreleasepool {
      NSScreen *mainScreen = [NSScreen mainScreen];
      if (mainScreen) {
        NSRect screenRect = [mainScreen frame];
        width = (int)screenRect.size.width;
        height = (int)screenRect.size.height;
        iLog->Log("Display settings from NSScreen: %dx%d\n", width, height);
      } else {
        iLog->Log(
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

  iLog->Log("Final renderer settings: %dx%d, color=%dbpp, depth=%dbpp, "
         "stencil=%dbpp, fullscreen=%d\n",
         width, height, colorBpp, depthBpp, stencilBpp, fullscreen);

  // Initialize the renderer
  void *result =
      renderer->Init(0, 0, width, height, colorBpp, depthBpp, stencilBpp,
                     fullscreen, nullptr, nullptr, nullptr, nullptr, false);

  if (!result) {
    assert(result && "CreateMetalRendererInstance: Failed to initialize renderer!");
    delete renderer;
    return nullptr;
  }

  iLog->Log("CMetalRenderer initialized successfully\n");
  iLog->Log("SUCCESS: Renderer initialized at %p\n", renderer);

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
  // Initialize iLog from the interface if not already set
  if (!iLog && sp && sp->ipLog) {
    iLog = sp->ipLog;
  }

    iLog->Log("PackageRenderConstructor called\n");
    iLog->Log("argc=%d, argv=%p, sp=%p\n", argc, argv, sp);
    iLog->Log("Using CMetalRenderer (manager pattern)\n");

  IRenderer *renderer = CreateMetalRendererInstance(argc, argv, sp);

  assert(renderer && "SUCCESS: CMetalRenderer created and initialized: %p\n");

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
  if (!v || nump <= 0)
    return;

  bool depthTest = false;
  bool depthWrite = false;
  bool blend = false;
  DecodeLineFlags(flags, col, depthTest, depthWrite, blend);

  std::vector<DebugVertex> vertices;
  vertices.reserve(nump);
  const uint32_t packedColor = PackColor(col);

  for (int i = 0; i < nump; ++i) {
    DebugVertex dv;
    dv.position[0] = v[i].x;
    dv.position[1] = v[i].y;
    dv.position[2] = v[i].z;
    dv.color = packedColor;
    vertices.push_back(dv);
  }

  QueueDebugCommand(MTLPrimitiveTypePoint, vertices, depthTest, depthWrite, blend);
}

void CMetalRenderer::DrawLines(Vec3 v[], int nump, CFColor& col, int flags, float fGround) {
  if (!v || nump <= 0)
    return;

  bool depthTest = false;
  bool depthWrite = false;
  bool blend = false;
  DecodeLineFlags(flags, col, depthTest, depthWrite, blend);

  const uint32_t packedColor = PackColor(col);

  if (fGround >= 0.0f) {
    std::vector<DebugVertex> vertices;
    vertices.reserve(nump * 2);

    for (int i = 0; i < nump; ++i) {
      const Vec3 groundPos(v[i].x, fGround, v[i].z);

      DebugVertex vg{{groundPos.x, groundPos.y, groundPos.z}, packedColor};
      DebugVertex vp{{v[i].x, v[i].y, v[i].z}, packedColor};

      vertices.push_back(vg);
      vertices.push_back(vp);
    }

    QueueDebugCommand(MTLPrimitiveTypeLine, vertices, depthTest, depthWrite, blend);
    return;
  }

  if (nump < 2)
    return;

  std::vector<DebugVertex> vertices;
  vertices.reserve(nump);

  for (int i = 0; i < nump; ++i) {
    DebugVertex dv;
    dv.position[0] = v[i].x;
    dv.position[1] = v[i].y;
    dv.position[2] = v[i].z;
    dv.color = packedColor;
    vertices.push_back(dv);
  }

  QueueDebugCommand(MTLPrimitiveTypeLineStrip, vertices, depthTest, depthWrite, blend);
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
    
    assert(Type >= 0 && Type < VSF_NUM && "CreateBuffer: Invalid vertex stream type");
    
    if (Type < 0 || Type >= VSF_NUM)
        return;
    
    @autoreleasepool {
        bool bDynamic = buf->m_VS[Type].m_bDynamic != 0;
        MTLResourceOptions options = bDynamic ? MTLResourceStorageModeShared : MTLResourceStorageModeManaged;
        
        id<MTLBuffer> metalBuffer = [m_device newBufferWithLength:size options:options];
        if (!metalBuffer) {
            iLog->LogWarning("CreateBuffer failed: Could not allocate Metal buffer of size %d for %s", 
                           size, szSource ? szSource : "Unknown");
            return;
        }
        
        int bufferId = m_nextVertexBufferId++;
        if (bufferId >= (int)m_vertexBuffers.size()) {
            m_vertexBuffers.resize(bufferId + 1, nil);
        }
        m_vertexBuffers[bufferId] = metalBuffer;
        
        buf->m_VS[Type].m_VertBuf.m_nID = bufferId;
        buf->m_VS[Type].m_VData = [metalBuffer contents];
        
        if (vertexformat >= 0) {
            int vertexSize = GetVertexFormatSize(vertexformat);
            if (vertexSize > 0) {
                buf->m_VS[Type].m_nItems = size / vertexSize;
            }
        }
        
        if (szSource && iLog) {
            iLog->Log("Created Metal buffer: size=%d bytes, format=%d, type=%d, dynamic=%d, source=%s",
                           size, vertexformat, Type, bDynamic, szSource);
        }
    }
}

void CMetalRenderer::SetClipPlane(int id, float * params) {
    if (params) {
        // Enable clipping with the specified plane
        iLog->Log("SetClipPlane: Enabling clip plane %d: Normal=(%.3f,%.3f,%.3f) Distance=%.3f\n", 
                  id, params[0], params[1], params[2], params[3]);
        
        m_clipPlaneEnabled = true;
        m_clipPlaneParams[0] = params[0];  // Normal.x
        m_clipPlaneParams[1] = params[1];  // Normal.y
        m_clipPlaneParams[2] = params[2];  // Normal.z
        m_clipPlaneParams[3] = params[3];  // Distance
        
        // Update uniform buffer with clip plane data
        if (m_uniformBufferCPU) {
            m_uniformBufferCPU->clipPlane[0] = params[0];
            m_uniformBufferCPU->clipPlane[1] = params[1];
            m_uniformBufferCPU->clipPlane[2] = params[2];
            m_uniformBufferCPU->clipPlane[3] = params[3];
            m_uniformBufferCPU->clipEnabled = 1.0f;
            m_uniformBufferCPU->clipRefract = m_clipPlaneRefract ? 1.0f : 0.0f;
            
            iLog->Log("SetClipPlane: Updated uniform buffer - clipEnabled=%.1f clipRefract=%.1f\n", 
                      m_uniformBufferCPU->clipEnabled, m_uniformBufferCPU->clipRefract);
        } else {
            iLog->Log("SetClipPlane: WARNING - No uniform buffer CPU pointer!\n");
        }
    } else {
        // Disable clipping
        iLog->Log("SetClipPlane: Disabling clip plane %d\n", id);
        
        m_clipPlaneEnabled = false;
        
        // Update uniform buffer to disable clipping
        if (m_uniformBufferCPU) {
            m_uniformBufferCPU->clipEnabled = 0.0f;
            iLog->Log("SetClipPlane: Disabled clipping in uniform buffer\n");
        } else {
            iLog->Log("SetClipPlane: WARNING - No uniform buffer CPU pointer for disable!\n");
        }
    }
}

char* CMetalRenderer::GetStatusText(ERendStats type) {
    static char statusText[256];
    if (m_device) {
        snprintf(statusText, sizeof(statusText), "Metal: %s", [[m_device name] UTF8String]);
    } else {
        strlcpy(statusText, "Metal Renderer (no device)", sizeof(statusText));
    }
    return statusText;
}

void CMetalRenderer::EF_SetClipPlane(bool bEnable, float *pPlane, bool bRefract) {
    if (bEnable && pPlane) {
        m_clipPlaneRefract = bRefract;
        SetClipPlane(0, pPlane);  // Use clip plane ID 0
    } else {
        SetClipPlane(0, nullptr);  // Disable clipping
    }
}

void CMetalRenderer::PrepareDepthMap(ShadowMapFrustum * lof, bool make_new_tid) {
    if (!lof || !lof->pLs)
        return;
    
    if (!m_textureManager || !m_utilityRenderer) {
        if (iLog)
            iLog->Log("PrepareDepthMap: Texture manager or utility renderer not available\n");
        return;
    }
    
    int nShadowTexSize = lof->nTexSize;
    if (nShadowTexSize < 32)
        nShadowTexSize = 32;
    
    // Create or reuse the shadow depth render target
    if (make_new_tid || !lof->depth_tex_id) {
        int renderTargetId = m_utilityRenderer->CreateRenderTarget(nShadowTexSize, nShadowTexSize, eTF_DEPTH);
        if (renderTargetId > 0) {
            lof->depth_tex_id = renderTargetId;
        }
    }
    
    if (!lof->depth_tex_id) {
        if (iLog)
            iLog->Log("PrepareDepthMap: Failed to create shadow map texture\n");
        return;
    }

    id<MTLTexture> depthTex = m_utilityRenderer->GetRenderTargetDepthTexture(lof->depth_tex_id);
    if (!depthTex || !m_currentCommandBuffer) {
        lof->bUpdateRequested = false;
        return;
    }

    ReleaseRenderEncoder();
    
    // Build a depth-only render pass descriptor
    MTLRenderPassDescriptor *shadowDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    shadowDesc.depthAttachment.texture     = depthTex;
    shadowDesc.depthAttachment.loadAction  = MTLLoadActionClear;
    shadowDesc.depthAttachment.storeAction = MTLStoreActionStore;
    shadowDesc.depthAttachment.clearDepth  = 1.0;

    id<MTLRenderCommandEncoder> shadowEncoder =
        [m_currentCommandBuffer renderCommandEncoderWithDescriptor:shadowDesc];
    if (!shadowEncoder) {
        lof->bUpdateRequested = false;
        if (!BeginSwapchainRenderPass(MTLLoadActionLoad, MTLLoadActionLoad, MTLLoadActionLoad))
        {
#if DEBUG
            static bool s_loggedPrepareDepthMapResumeFail = false;
            if (!s_loggedPrepareDepthMapResumeFail && iLog)
            {
                iLog->Log("PrepareDepthMap: shadow encoder nil and BeginSwapchainRenderPass failed\n");
                s_loggedPrepareDepthMapResumeFail = true;
            }
#endif
        }
        return;
    }
    [shadowEncoder setLabel:@"ShadowDepthPass"];

    // Set the light's view-projection matrix into the uniform buffer
    // debugLightFrustumMatrix is the proj, debugLightViewMatrix is the view
    if (m_uniformBufferCPU) {
        Matrix44 lightView, lightProj;
        memcpy(&lightView,  lof->debugLightViewMatrix,    sizeof(Matrix44));
        memcpy(&lightProj,  lof->debugLightFrustumMatrix, sizeof(Matrix44));
        m_uniformBufferCPU->viewMatrix       = lightView;
        m_uniformBufferCPU->projectionMatrix = lightProj;
        m_uniformBufferCPU->modelMatrix.SetIdentity();
        m_uniformBufferCPU->modelViewProjectionMatrix = lightProj * lightView;
        [shadowEncoder setVertexBuffer:m_uniformBuffer offset:0 atIndex:kMetalVertexUniformSlot];
    }

    // Get the depth-only PSO
    id<MTLRenderPipelineState> depthPSO = m_shaderManager
        ? m_shaderManager->GetPipelineStateForShader("depth") : nil;
    if (depthPSO) {
        [shadowEncoder setRenderPipelineState:depthPSO];

        [shadowEncoder setVertexBuffer:m_uniformBuffer offset:0 atIndex:kMetalVertexUniformSlot];

        m_renderEncoder = [shadowEncoder retain];
        m_renderEncoderOpen = true;

        if (lof->pEntityList)
        {
            SRendParams shadowParams;
            shadowParams.nDLightMask = 0;
            for (int i = 0; i < lof->pEntityList->Count(); ++i)
            {
                IEntityRender* pEnt = lof->pEntityList->GetAt(i);
                if (pEnt)
                {
                    const Vec3& pos = pEnt->GetPos();
                    shadowParams.vPos    = pos;
                    shadowParams.pMatrix = nullptr;
                    pEnt->DrawEntity(shadowParams);
                }
            }
        }

        ReleaseRenderEncoder();
    } else {
        [shadowEncoder endEncoding];
    }

    if (!BeginSwapchainRenderPass(MTLLoadActionLoad, MTLLoadActionLoad, MTLLoadActionLoad))
    {
#if DEBUG
        static bool s_loggedPrepareDepthMapResumeFail2 = false;
        if (!s_loggedPrepareDepthMapResumeFail2 && iLog)
        {
            iLog->Log("PrepareDepthMap: BeginSwapchainRenderPass failed after shadow pass\n");
            s_loggedPrepareDepthMapResumeFail2 = true;
        }
#endif
    }

    lof->bUpdateRequested = false;
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
    return nullptr;
}

unsigned int CMetalRenderer::MakeSprite(float object_scale, int tex_size, float angle,
                                        IStatObj* pStatObj, uchar* pTmpBuffer, uint def_tid)
{
    if (m_utilityRenderer)
        return m_utilityRenderer->MakeSprite(object_scale, tex_size, angle, pStatObj, pTmpBuffer, def_tid);
    return def_tid;
}

unsigned int CMetalRenderer::Make3DSprite(int nTexSize, float fAngleStep, IStatObj* pStatObj)
{
    if (m_utilityRenderer)
        return m_utilityRenderer->Make3DSprite(nTexSize, fAngleStep, pStatObj);
    return 0;
}

ShadowMapFrustum* CMetalRenderer::MakeShadowMapFrustum(ShadowMapFrustum* lof, ShadowMapLightSource* pLs,
                                                        const Vec3& obj_pos, list2<IStatObj*>* pStatObjects,
                                                        int shadow_type)
{
    if (m_utilityRenderer)
    {
        ShadowMapFrustum* result = m_utilityRenderer->MakeShadowMapFrustum(lof, pLs, obj_pos, pStatObjects, shadow_type);
        return result ? result : lof;
    }
    return lof;
}

void CMetalRenderer::DrawObjSprites(list2<CStatObjInst*>* pList, float fMaxViewDist, CObjManager* pObjMan)
{
    if (m_utilityRenderer)
        m_utilityRenderer->DrawObjSprites(pList, fMaxViewDist, pObjMan);
}

void CMetalRenderer::EF_PipelineShutdown() {
    // Flush any in-flight command buffers
    ReleaseRenderEncoder();
    if (m_currentCommandBuffer) {
        [m_currentCommandBuffer commit];
        [m_currentCommandBuffer waitUntilCompleted];
        m_currentCommandBuffer = nil;
    }

    // Release PSO cache and all shader resources
    if (m_shaderManager) {
        m_shaderManager->ClearAllShaders();
    }

    // Release per-draw buffers
    CleanupUniformBuffers(); // releases m_uniformBuffer, m_materialBuffer, m_waterNoiseBuffer
}

void CMetalRenderer::SetupShadowOnlyPass(int Num, ShadowMapFrustum * pFrustum, Vec3 * vShadowTrans, 
                                         const float fShadowScale, Vec3 vObjTrans, float fObjScale, 
                                         const Vec3 vObjAngles, Matrix44 * pObjMat) {
    if (!pFrustum || !pFrustum->pLs)
        return;
    
    if (iLog)
        iLog->Log("SetupShadowOnlyPass: Configuring shadow pass %d (FOV=%.2f, scale=%.2f)\n", 
                  Num, pFrustum->FOV, fShadowScale);
    
    if (pFrustum->depth_tex_id > 0 && m_utilityRenderer) {
        m_utilityRenderer->SetRenderTarget(pFrustum->depth_tex_id);
        SetViewport(0, 0, pFrustum->nTexSize, pFrustum->nTexSize);
    }
}

void CMetalRenderer::DrawAllShadowsOnTheScreen() {
    if (iLog)
        iLog->Log("DrawAllShadowsOnTheScreen: Debug visualization not implemented\n");
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
