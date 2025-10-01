# XRenderMetal - Metal API renderer for macOS
if(NOT APPLE)
    return()
endif()

# Metal renderer source files
set(XRENDER_METAL_SOURCES
    SimpleStubRenderer.cpp
    SimpleStubRenderer.h
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
)

# Create the Metal renderer library
add_library(XRenderMetal SHARED ${XRENDER_METAL_SOURCES})

# Link CryCommon interface
target_link_libraries(XRenderMetal PRIVATE CryCommon)

# Include directories
target_include_directories(XRenderMetal PRIVATE
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
set_source_files_properties(SimpleStubRenderer.cpp PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

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

# Preprocessor definitions
target_compile_definitions(XRenderMetal PRIVATE
    XRENDERMETAL_EXPORTS=1
)

# Install target
install(TARGETS XRenderMetal 
    LIBRARY DESTINATION lib
    FRAMEWORK DESTINATION Frameworks
)

