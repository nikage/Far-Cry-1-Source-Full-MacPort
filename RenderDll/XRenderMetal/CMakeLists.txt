# XRenderMetal - Metal API renderer for macOS
if(NOT APPLE)
    return()
endif()

# Render elements will be implemented directly in MetalShaderManager

# Metal renderer source files
set(XRENDER_METAL_SOURCES
    MetalRenderer.cpp
    MetalRenderer.h
    MetalBaseRenderer.cpp
    MetalBaseRenderer.h
    MetalTextureManager.cpp
    MetalTextureManager.h
    MetalShaderManager.cpp
    MetalShaderManager.h
    MetalShaderLoader.cpp
    MetalUtilityRenderer.cpp
    MetalUtilityRenderer.h
    MetalStateCache.cpp
    MetalStateCache.h
    MetalVertexDescriptor.cpp
    MetalVertexDescriptor.h
    MetalRenderElements.cpp
    MetalRenderElements.h
    MetalOptimizations.cpp
    MetalOptimizations.h
    MetalImageStubs.cpp
)

# Create the Metal renderer library
add_library(XRenderMetal SHARED ${XRENDER_METAL_SOURCES} $<TARGET_OBJECTS:RenderCommonObj>)

# Link CryCommon interface and RenderCommon base classes
target_link_libraries(XRenderMetal PRIVATE 
    CryCommon
    RenderCommon
)

# Include directories
target_include_directories(XRenderMetal PRIVATE
    ${CMAKE_SOURCE_DIR}/RenderDll
    ${CMAKE_SOURCE_DIR}/RenderDll/Common
    ${CMAKE_SOURCE_DIR}/RenderDll/Common/Shaders
    ${CMAKE_SOURCE_DIR}/CryCommon
)

# macOS frameworks
target_link_libraries(XRenderMetal PRIVATE
    ${COCOA_FRAMEWORK}
    ${OPENGL_FRAMEWORK}
    "-framework Metal"
    "-framework MetalKit"
    "-framework QuartzCore"
)

# Compiler settings for Objective-C++
set_source_files_properties(MetalRenderer.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalBaseRenderer.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalTextureManager.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalShaderManager.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalUtilityRenderer.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalStateCache.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalVertexDescriptor.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalShaderLoader.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalRenderElements.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalOptimizations.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalImageStubs.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

# Preprocessor definitions
target_compile_definitions(XRenderMetal PRIVATE
    XRENDERMETAL_EXPORTS=1
)

# Compile Metal shaders at build time  
# Note: Do NOT pass C++ include paths to Metal compiler
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/BasicShaders.metallib
    COMMAND xcrun -sdk macosx metal -std=macos-metal2.0 -c ${CMAKE_CURRENT_SOURCE_DIR}/BasicShaders.metal -o ${CMAKE_CURRENT_BINARY_DIR}/BasicShaders.air
    COMMAND xcrun -sdk macosx metallib ${CMAKE_CURRENT_BINARY_DIR}/BasicShaders.air -o ${CMAKE_CURRENT_BINARY_DIR}/BasicShaders.metallib
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/BasicShaders.metal
    COMMENT "Compiling BasicShaders"
    VERBATIM
)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
    COMMAND xcrun -sdk macosx metal -std=macos-metal2.0 -c ${CMAKE_CURRENT_SOURCE_DIR}/SpriteShaders.metal -o ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.air
    COMMAND xcrun -sdk macosx metallib ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.air -o ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/SpriteShaders.metal
    COMMENT "Compiling SpriteShaders"
    VERBATIM
)

add_custom_target(MetalShaders ALL
    DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/BasicShaders.metallib
            ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
)

add_dependencies(XRenderMetal MetalShaders)

# Install target
install(TARGETS XRenderMetal 
    LIBRARY DESTINATION lib
    FRAMEWORK DESTINATION Frameworks
)

# Install Metal shader libraries
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/BasicShaders.metallib
              ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
    DESTINATION lib
)

