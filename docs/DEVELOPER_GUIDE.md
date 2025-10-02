# FarCry Metal Renderer - Developer Guide

## Architecture Overview

The Metal renderer implementation follows a modular architecture that integrates with CryEngine's existing rendering pipeline.

### Core Components

#### 1. CMetalBaseRenderer
- **Purpose**: Core Metal device and context management
- **Key Features**:
  - Metal device initialization
  - Command queue management
  - Render state management
  - Vertex/index buffer operations
- **Files**: `MetalBaseRenderer.h/cpp`

#### 2. CMetalTextureManager
- **Purpose**: Texture loading and format conversion
- **Key Features**:
  - CryEngine to Metal format conversion
  - Texture binding and management
  - Memory optimization
- **Files**: `MetalTextureManager.h/cpp`

#### 3. CMetalShaderManager
- **Purpose**: Metal shader compilation and management
- **Key Features**:
  - Shader source loading
  - Metal shader compilation
  - Pipeline state creation
- **Files**: `MetalShaderManager.h/cpp`

#### 4. CMetalUtilityRenderer
- **Purpose**: 2D rendering utilities
- **Key Features**:
  - 2D image rendering
  - UI element drawing
  - Text rendering support
- **Files**: `MetalUtilityRenderer.h/cpp`

#### 5. CSimpleMetalRenderer
- **Purpose**: Main renderer interface implementation
- **Key Features**:
  - IRenderer interface implementation
  - Entry point for PackageRenderConstructor
  - Integration with CryEngine systems
- **Files**: `SimpleMetalRenderer.h/cpp`

## Implementation Details

### IRenderer Interface Compliance

The Metal renderer implements all required methods from the `IRenderer` interface:

```cpp
class CSimpleMetalRenderer : public IRenderer
{
public:
    // Core rendering methods
    virtual bool Init(int argc, char* argv[], SCryRenderInterface* sp);
    virtual void ShutDown();
    virtual void BeginFrame();
    virtual void EndFrame();
    
    // Texture management
    virtual ITexPic* EF_LoadTexture(const char* nameTex, uint flags, uint flags2, byte eTT, float fAmount1=-1.0f, float fAmount2=-1.0f, int Id=-1, int BindId=0);
    virtual ITexPic* EF_GetTextureByID(int texture_id);
    virtual void SetTexture(int tnum, ETexType Type = eTT_Base);
    
    // Buffer management
    virtual CLeafBuffer* CreateLeafBuffer(void* pVertBuffer, int nVertCount, int nVertFormat, ushort* pIndices, int nIndices, int nPrimetiveType, const char* szSource, EBufferType eBufType = eBT_Dynamic);
    virtual CLeafBuffer* CreateLeafBufferInitialized(void* pVertBuffer, int nVertCount, int nVertFormat, ushort* pIndices, int nIndices, int nPrimetiveType, const char* szSource, EBufferType eBufType = eBT_Dynamic, int nMatInfoCount=1, int nClientTextureBindID=0, bool (*PrepareBufferCallback)(CLeafBuffer*, bool)=NULL, void* CustomData=NULL, bool bOnlyVideoBuffer=false, bool bPrecache=true);
    
    // Rendering operations
    virtual void DrawBuffer(CVertexBuffer* src, SVertexStream* indicies, int numindices, int offsindex, int prmode, CMatInfo* mi);
    virtual void Draw2dImage(float xpos, float ypos, float w, float h, int texture_id, float s0, float t0, float s1, float t1, float angle, float r, float g, float b, float a, float z);
    
    // Display management
    virtual int EnumDisplayFormats(TArray<SDispFormat>& Formats, bool bReset);
    virtual void FlushTextMessages();
    
    // Type management
    virtual char GetType();
    virtual void SetType(char type);
};
```

### Dynamic Library Integration

The renderer is loaded as a dynamic library with the following entry point:

```cpp
extern "C" DLL_EXPORT IRenderer* PackageRenderConstructor(int argc, char* argv[], SCryRenderInterface* sp)
{
    // Create and return the Metal renderer instance
    return CreateSimpleRenderer(argc, argv, sp);
}
```

### Metal API Integration

The renderer uses Objective-C++ to interface with Apple's Metal API:

```cpp
// Metal device and command queue
id<MTLDevice> m_device;
id<MTLCommandQueue> m_commandQueue;
id<MTLCommandBuffer> m_commandBuffer;
id<MTLRenderCommandEncoder> m_renderEncoder;

// Metal buffers and textures
id<MTLBuffer> m_vertexBuffer;
id<MTLBuffer> m_indexBuffer;
id<MTLTexture> m_texture;
```

## Build System Integration

### CMake Configuration

The Metal renderer is integrated into the build system via `RenderDll/XRenderMetal/CMakeLists.txt`:

```cmake
# Metal renderer sources
set(XRENDER_METAL_SOURCES
    MetalRenderer.cpp
    MetalRenderer.h
    MetalBaseRenderer.cpp
    MetalBaseRenderer.h
    MetalTextureManager.cpp
    MetalTextureManager.h
    MetalShaderManager.cpp
    MetalShaderManager.h
    MetalUtilityRenderer.cpp
    MetalUtilityRenderer.h
    SimpleMetalRenderer.cpp
)

# Objective-C++ compilation for Metal API
set_source_files_properties(SimpleMetalRenderer.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

# Create Metal renderer library
add_library(XRenderMetal SHARED ${XRENDER_METAL_SOURCES})
target_link_libraries(XRenderMetal
    ${METAL_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
)
```

### App Bundle Integration

The renderer library is automatically copied to the app bundle:

```cmake
# Copy Metal renderer to app bundle
add_custom_command(TARGET FarCryWorking POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        $<TARGET_FILE:XRenderMetal>
        ${CMAKE_BINARY_DIR}/FarCryWorking.app/Contents/MacOS/
)
```

## Code Signing Considerations

### Development Environment

For development, code signing validation is bypassed using:

```bash
export DYLD_DISABLE_CODE_SIGNING=1
```

### Production Signing

For production distribution, all libraries must be properly signed:

```bash
# Sign individual libraries
codesign --force --sign "Your Developer ID" libXRenderMetal.dylib

# Sign the entire app bundle
codesign --force --sign "Your Developer ID" --deep FarCryWorking.app
```

## Debugging and Development

### Debug Output

The renderer includes comprehensive debug output:

```cpp
// File logging for debugging
FILE* f = fopen("/tmp/farcry_render_constructor.log", "w");
if (f) {
    fprintf(f, "PackageRenderConstructor called successfully\n");
    fclose(f);
}

// Console output
printf("Metal renderer initialized successfully\n");
```

### Common Issues

1. **Code Signing**: Use `DYLD_DISABLE_CODE_SIGNING=1` for development
2. **Library Loading**: Ensure all dependencies are in the app bundle
3. **Metal API**: Requires macOS 11.0+ and Metal-compatible GPU
4. **Memory Management**: Use ARC for Objective-C++ objects

## Performance Considerations

### Metal Optimization

- Use `MTLResourceStorageModeShared` for frequently updated buffers
- Implement proper buffer recycling
- Minimize state changes between draw calls
- Use Metal Performance Shaders when available

### Memory Management

- Implement proper cleanup in destructors
- Use smart pointers for C++ objects
- Follow Metal memory management best practices

## Future Enhancements

### Planned Features

1. **Advanced Shading**: Implement PBR materials
2. **Post-Processing**: Add bloom, tone mapping, etc.
3. **Compute Shaders**: Utilize Metal compute for effects
4. **Performance Profiling**: Add Metal GPU profiling

### Integration Improvements

1. **Shader Caching**: Implement shader compilation caching
2. **Texture Streaming**: Add texture streaming support
3. **Multi-threading**: Implement multi-threaded rendering
4. **VR Support**: Add Metal VR rendering support

---

**Developer Contact**: For technical questions or contributions, refer to the main project documentation.
