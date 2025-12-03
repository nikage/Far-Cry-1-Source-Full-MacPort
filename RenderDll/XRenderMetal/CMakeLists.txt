# XRenderMetal - Metal API renderer for macOS
if(NOT APPLE)
    return()
endif()

# Render elements will be implemented directly in MetalShaderManager

# Metal renderer source files
set(XRENDER_METAL_SOURCES
    MetalRenderer.mm
    MetalBaseRenderer.mm
    MetalTextureManager.mm
    MetalShaderManager.mm
    MetalShaderLoader.mm
    MetalUtilityRenderer.mm
    MetalStateCache.mm
    MetalVertexDescriptor.mm
    MetalRenderElements.mm
    MetalOptimizations.mm
    MetalImageStubs.mm
)

# Metal renderer header files (not compiled, only included)
set(XRENDER_METAL_HEADERS
    MetalRenderer.m
    MetalBaseRenderer.m
    MetalTextureManager.m
    MetalShaderManager.m
    MetalUtilityRenderer.m
    MetalStateCache.m
    MetalVertexDescriptor.m
    MetalRenderElements.m
    MetalOptimizations.m
)

# Create the Metal renderer library
add_library(XRenderMetal SHARED ${XRENDER_METAL_SOURCES} ${XRENDER_METAL_HEADERS} $<TARGET_OBJECTS:RenderCommonObj>)

# Mark .m files as headers so they're not compiled
set_source_files_properties(${XRENDER_METAL_HEADERS} PROPERTIES HEADER_FILE_ONLY TRUE)

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
set_source_files_properties(MetalRenderer.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalBaseRenderer.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalTextureManager.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalShaderManager.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalUtilityRenderer.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalStateCache.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalVertexDescriptor.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalShaderLoader.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalRenderElements.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalOptimizations.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalImageStubs.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

# Preprocessor definitions
target_compile_definitions(XRenderMetal PRIVATE
    XRENDERMETAL_EXPORTS=1
)

find_program(DART_EXECUTABLE dart)
set(DART_COMMAND "")
if(DART_EXECUTABLE)
    set(DART_COMMAND ${DART_EXECUTABLE})
else()
    find_program(FVM_EXECUTABLE fvm)
    if(FVM_EXECUTABLE)
        set(DART_COMMAND ${FVM_EXECUTABLE} dart)
        message(STATUS "Dart executable not found; using fvm at ${FVM_EXECUTABLE}")
    endif()
endif()

set(GENERATED_METAL_METALLIB "")
if(DART_COMMAND)
    set(SHADER_PORT_ROOT ${CMAKE_SOURCE_DIR})
    set(SHADER_PARSER ${SHADER_PORT_ROOT}/tools/shader_port/lib/parser.dart)
    set(SHADER_METAL_GENERATOR ${SHADER_PORT_ROOT}/tools/shader_port/lib/metal_generator.dart)
    set(GENERATED_STAMP ${CMAKE_CURRENT_BINARY_DIR}/generated_shaders.stamp)

    add_custom_command(
        OUTPUT ${GENERATED_STAMP}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_SOURCE_DIR}/Generated
        COMMAND ${DART_COMMAND} ${SHADER_PARSER} ${SHADER_PORT_ROOT}
        COMMAND ${DART_COMMAND} ${SHADER_METAL_GENERATOR} ${SHADER_PORT_ROOT}
        COMMAND ${CMAKE_COMMAND} -E touch ${GENERATED_STAMP}
        DEPENDS ${SHADER_PARSER} ${SHADER_METAL_GENERATOR}
        WORKING_DIRECTORY ${SHADER_PORT_ROOT}
        COMMENT "Generating Metal shader sources from Cry scripts"
        VERBATIM
    )

    add_custom_target(GenerateMetalShaderSources ALL DEPENDS ${GENERATED_STAMP})

    set(GENERATED_METAL_METALLIB ${CMAKE_CURRENT_BINARY_DIR}/GeneratedShaders.metallib)
    set(GENERATED_AIR_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated_air)
    set(METAL_BUILD_SCRIPT ${SHADER_PORT_ROOT}/tools/shader_port/lib/build_metal.dart)
    add_custom_command(
        OUTPUT ${GENERATED_METAL_METALLIB}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${GENERATED_AIR_DIR}
        COMMAND ${DART_COMMAND} ${METAL_BUILD_SCRIPT} ${SHADER_PORT_ROOT} ${CMAKE_CURRENT_SOURCE_DIR}/Generated ${GENERATED_AIR_DIR} ${GENERATED_METAL_METALLIB}
        DEPENDS ${GENERATED_STAMP} ${METAL_BUILD_SCRIPT}
        COMMENT "Compiling generated Metal shaders"
        VERBATIM
    )
    add_custom_target(GeneratedMetalShaders ALL DEPENDS ${GENERATED_METAL_METALLIB})
    add_dependencies(GeneratedMetalShaders GenerateMetalShaderSources)
else()
    message(WARNING "Dart executable not found; skipping generated Metal shader integration")
endif()

# Compile Metal shaders at build time  
# Note: Do NOT pass C++ include paths to Metal compiler
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.metallib
    COMMAND xcrun -sdk macosx metal -std=macos-metal2.0 -c ${CMAKE_CURRENT_SOURCE_DIR}/UtilShaders.metal -o ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.air
    COMMAND xcrun -sdk macosx metallib ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.air -o ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.metallib
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/UtilShaders.metal
    COMMENT "Compiling UtilShaders"
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
    DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.metallib
            ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
)

if(GENERATED_METAL_METALLIB)
    add_dependencies(MetalShaders GeneratedMetalShaders)
endif()

add_dependencies(XRenderMetal MetalShaders)

# Install target
install(TARGETS XRenderMetal 
    LIBRARY DESTINATION lib
    FRAMEWORK DESTINATION Frameworks
)

# Install Metal shader libraries
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.metallib
              ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
    DESTINATION lib
)

if(GENERATED_METAL_METALLIB)
install(FILES ${GENERATED_METAL_METALLIB}
              ${CMAKE_CURRENT_SOURCE_DIR}/Generated/generated_manifest.json
    DESTINATION lib
)

    set(DEFAULT_FARCRY_APP_BUNDLE "${CMAKE_BINARY_DIR}/FarCry.app")
    set(FARCRY_APP_BUNDLE_DIR "${DEFAULT_FARCRY_APP_BUNDLE}" CACHE PATH "Location of FarCry.app for resource staging")
    set(FARCRY_APP_RESOURCES_DIR "${FARCRY_APP_BUNDLE_DIR}/Contents/Resources")

    add_custom_command(
        OUTPUT ${FARCRY_APP_RESOURCES_DIR}/GeneratedShaders.metallib
               ${FARCRY_APP_RESOURCES_DIR}/generated_manifest.json
        COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_APP_RESOURCES_DIR}
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${GENERATED_METAL_METALLIB} ${FARCRY_APP_RESOURCES_DIR}/GeneratedShaders.metallib
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_SOURCE_DIR}/Generated/generated_manifest.json ${FARCRY_APP_RESOURCES_DIR}/generated_manifest.json
        DEPENDS ${GENERATED_METAL_METALLIB} ${CMAKE_CURRENT_SOURCE_DIR}/Generated/generated_manifest.json
        COMMENT "Staging generated Metal shaders into FarCry.app resources"
        VERBATIM
    )

    add_custom_target(GeneratedMetalBundleResources ALL
        DEPENDS ${FARCRY_APP_RESOURCES_DIR}/GeneratedShaders.metallib
                ${FARCRY_APP_RESOURCES_DIR}/generated_manifest.json)
    add_dependencies(GeneratedMetalBundleResources GeneratedMetalShaders)
    add_dependencies(MetalShaders GeneratedMetalBundleResources)
endif()

