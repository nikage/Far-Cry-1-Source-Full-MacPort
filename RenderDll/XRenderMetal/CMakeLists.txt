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
    MetalManifestPSOHelpers.mm
    MetalUtilityRenderer.mm
    MetalStateCache.mm
    MetalVertexDescriptor.mm
    MetalRenderElements.mm
    MetalCREScreenProcess.mm
    MetalREOcean.mm
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
    "-framework CoreGraphics"
    "-framework CoreFoundation"
    "-framework ImageIO"
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

set_source_files_properties(MetalManifestPSOHelpers.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalRenderElements.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalCREScreenProcess.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

set_source_files_properties(MetalREOcean.mm PROPERTIES
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
    $<$<CONFIG:Debug>:DEBUG=1>
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

find_program(DXC_EXECUTABLE dxc)
find_program(METAL_SHADER_CONVERTER_EXECUTABLE metal-shader-converter)

set(GENERATED_METAL_METALLIB "")
set(USE_HLSL_CONVERSION FALSE)

# Check if Metal compiler is available.
# `metal` lives inside the Xcode toolchain and is not on the standard PATH, so
# find_program typically yields NOTFOUND on a standard Xcode install.  The xcrun
# fallback is therefore the primary detection path on macOS.
execute_process(
    COMMAND xcrun -sdk macosx metal --version
    OUTPUT_QUIET
    ERROR_QUIET
    RESULT_VARIABLE METAL_CHECK_RESULT
)
if(METAL_CHECK_RESULT EQUAL 0)
    set(METAL_COMPILER "xcrun -sdk macosx metal")
    set(METAL_COMPILER_AVAILABLE TRUE)
    message(STATUS "Metal compiler found via xcrun")
else()
    # xcrun failed — fall back to searching PATH (unusual; present for non-Apple toolchains)
    find_program(METAL_COMPILER NAMES metal)
    if(METAL_COMPILER)
        set(METAL_COMPILER_AVAILABLE TRUE)
        message(STATUS "Metal compiler found in PATH: ${METAL_COMPILER}")
    else()
        message(FATAL_ERROR "Metal compiler not found. "
                            "Ensure Xcode is installed and selected:\n"
                            "  sudo xcode-select -s /Applications/Xcode.app\n"
                            "Then re-run cmake.")
    endif()
endif()

if(DART_COMMAND)
    set(SHADER_PORT_ROOT ${CMAKE_SOURCE_DIR})
    set(SHADER_PARSER ${SHADER_PORT_ROOT}/tools/shader_port/lib/parser.dart)
    set(SHADER_METAL_GENERATOR ${SHADER_PORT_ROOT}/tools/shader_port/lib/metal_generator.dart)
    set(SHADER_HLSL_GENERATOR ${SHADER_PORT_ROOT}/tools/shader_port/lib/hlsl_generator.dart)
    set(METAL_CONVERTER_SCRIPT ${SHADER_PORT_ROOT}/tools/shader_port/bin/metal_converter.dart)
    set(GENERATED_STAMP ${CMAKE_CURRENT_BINARY_DIR}/generated_shaders.stamp)
    set(SHADER_PAIR_VALIDATOR ${SHADER_PORT_ROOT}/tools/shader_port/bin/validate_pairs.dart)
    set(SHADER_PAIR_OVERRIDES ${SHADER_PORT_ROOT}/tools/shader_port/config/shader_pair_overrides.json)

    # Locate the .crycg source files. The canonical location inside this
    # repo is Assets/Shaders/Source/Shaders/HWScripts/Declarations; fall back
    # to the legacy Shaders/Legacy symlink for backwards compatibility.
    if(NOT DEFINED CRYCG_SHADERS_DIR)
        if(EXISTS ${CMAKE_SOURCE_DIR}/Assets/Shaders/Source/Shaders/HWScripts/Declarations)
            set(CRYCG_SHADERS_DIR ${CMAKE_SOURCE_DIR}/Assets/Shaders/Source/Shaders/HWScripts/Declarations)
        elseif(EXISTS ${CMAKE_SOURCE_DIR}/Shaders/Legacy)
            set(CRYCG_SHADERS_DIR ${CMAKE_SOURCE_DIR}/Shaders/Legacy)
        else()
            message(FATAL_ERROR
                "Cannot find .crycg shader source files. "
                "Expected at: ${CMAKE_SOURCE_DIR}/Assets/Shaders/Source/Shaders/HWScripts/Declarations\n"
                "Override with: cmake -DCRYCG_SHADERS_DIR=<path> .")
        endif()
    endif()
    message(STATUS "CryCG shader source directory: ${CRYCG_SHADERS_DIR}")

    add_custom_command(
        OUTPUT ${GENERATED_STAMP}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_SOURCE_DIR}/Generated
        COMMAND ${DART_COMMAND} ${SHADER_PARSER} --shaders-dir ${CRYCG_SHADERS_DIR} ${SHADER_PORT_ROOT}
        COMMAND ${DART_COMMAND} ${SHADER_METAL_GENERATOR} ${SHADER_PORT_ROOT}
            --overrides ${SHADER_PAIR_OVERRIDES}
        COMMAND ${CMAKE_COMMAND} -E touch ${GENERATED_STAMP}
        DEPENDS ${SHADER_PARSER} ${SHADER_METAL_GENERATOR} ${SHADER_PAIR_OVERRIDES}
        WORKING_DIRECTORY ${SHADER_PORT_ROOT}
        COMMENT "Generating Metal shader sources from Cry scripts"
        VERBATIM
    )

    add_custom_target(GenerateMetalShaderSources ALL DEPENDS ${GENERATED_STAMP})

    set(GENERATED_MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/Generated/generated_manifest.json)

    add_custom_target(ValidateShaderPairs ALL
        COMMAND ${DART_COMMAND} ${SHADER_PAIR_VALIDATOR}
            ${GENERATED_MANIFEST}
        DEPENDS GenerateMetalShaderSources ${SHADER_PAIR_VALIDATOR}
        WORKING_DIRECTORY ${SHADER_PORT_ROOT}
        COMMENT "Validating shader vertex/fragment pairing (100% required)"
        VERBATIM
    )

    if(DXC_EXECUTABLE AND METAL_SHADER_CONVERTER_EXECUTABLE)
        set(USE_HLSL_CONVERSION TRUE)
        set(HLSL_STAMP ${CMAKE_CURRENT_BINARY_DIR}/generated_hlsl.stamp)
        set(HLSL_OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/tools/shader_port/output/hlsl)
        
        add_custom_command(
            OUTPUT ${HLSL_STAMP}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${HLSL_OUTPUT_DIR}
            COMMAND ${DART_COMMAND} ${SHADER_HLSL_GENERATOR} ${SHADER_PORT_ROOT}
            COMMAND ${CMAKE_COMMAND} -E touch ${HLSL_STAMP}
            DEPENDS ${GENERATED_STAMP} ${SHADER_HLSL_GENERATOR}
            WORKING_DIRECTORY ${SHADER_PORT_ROOT}
            COMMENT "Generating HLSL shaders from IR"
            VERBATIM
        )

        add_custom_target(GenerateHLSLShaders ALL DEPENDS ${HLSL_STAMP})
        add_dependencies(GenerateHLSLShaders GenerateMetalShaderSources)

        set(CONVERTER_METALLIB ${CMAKE_CURRENT_SOURCE_DIR}/Generated/GeneratedShaders.metallib)
        set(CONVERTER_MANIFEST ${CMAKE_CURRENT_BINARY_DIR}/build/shader_port/metal_converter/manifest.json)
        set(CONVERTER_DXIL_DIR ${CMAKE_CURRENT_BINARY_DIR}/build/shader_port/metal_converter/dxil)
        set(CONVERTER_METALLIB_DIR ${CMAKE_CURRENT_BINARY_DIR}/build/shader_port/metal_converter/metallib)

        add_custom_command(
            OUTPUT ${CONVERTER_METALLIB}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${CONVERTER_DXIL_DIR}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${CONVERTER_METALLIB_DIR}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/build/shader_port/metal_converter
            COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_SOURCE_DIR}/Generated
            COMMAND ${DART_COMMAND} ${METAL_CONVERTER_SCRIPT}
                --root ${SHADER_PORT_ROOT}
                --input-dir ${HLSL_OUTPUT_DIR}/Shaders/HWScripts/Declarations
                --dxil-dir ${CONVERTER_DXIL_DIR}
                --metallib-dir ${CONVERTER_METALLIB_DIR}
                --manifest ${CONVERTER_MANIFEST}
                --generated-manifest ${CMAKE_CURRENT_SOURCE_DIR}/Generated/generated_manifest.json
                --dxc-path ${DXC_EXECUTABLE}
                --metal-shader-converter-path ${METAL_SHADER_CONVERTER_EXECUTABLE}
                --jobs ${CMAKE_BUILD_PARALLEL_LEVEL}
            DEPENDS ${HLSL_STAMP} ${METAL_CONVERTER_SCRIPT} ${CMAKE_CURRENT_SOURCE_DIR}/Generated/generated_manifest.json
            WORKING_DIRECTORY ${SHADER_PORT_ROOT}
            COMMENT "Converting HLSL shaders to Metal via DXIL"
            VERBATIM
        )

        add_custom_target(ConvertHLSLToMetal ALL DEPENDS ${CONVERTER_METALLIB})
        add_dependencies(ConvertHLSLToMetal GenerateHLSLShaders)
        
        set(GENERATED_METAL_METALLIB ${CONVERTER_METALLIB})
        message(STATUS "Using HLSL→Metal conversion pipeline (DXC: ${DXC_EXECUTABLE}, Converter: ${METAL_SHADER_CONVERTER_EXECUTABLE})")
    else()
        set(GENERATED_METAL_METALLIB ${CMAKE_CURRENT_BINARY_DIR}/GeneratedShaders.metallib)
        set(GENERATED_AIR_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated_air)
        set(METAL_BUILD_SCRIPT ${SHADER_PORT_ROOT}/tools/shader_port/lib/build_metal.dart)
        add_custom_command(
            OUTPUT ${GENERATED_METAL_METALLIB}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${GENERATED_AIR_DIR}
            COMMAND ${DART_COMMAND} ${METAL_BUILD_SCRIPT} ${SHADER_PORT_ROOT} ${CMAKE_CURRENT_SOURCE_DIR}/Generated ${GENERATED_AIR_DIR} ${GENERATED_METAL_METALLIB}
            DEPENDS ${GENERATED_STAMP} ${METAL_BUILD_SCRIPT}
            COMMENT "Compiling generated Metal shaders (IR→Metal)"
            VERBATIM
        )
        add_custom_target(GeneratedMetalShaders ALL DEPENDS ${GENERATED_METAL_METALLIB})
        add_dependencies(GeneratedMetalShaders GenerateMetalShaderSources)
        if(NOT DXC_EXECUTABLE)
            message(WARNING "DXC not found; falling back to IR→Metal conversion")
        endif()
        if(NOT METAL_SHADER_CONVERTER_EXECUTABLE)
            message(WARNING "metal-shader-converter not found; falling back to IR→Metal conversion")
        endif()
    endif()
else()
    if(NOT DART_COMMAND)
        message(WARNING "Dart executable not found; skipping generated Metal shader integration")
    endif()
endif()

# Read the Metal standard version from the shared toolchain config so it stays
# in sync with the Dart shader migration pipeline (tools/shader_port/).
file(READ "${CMAKE_SOURCE_DIR}/tools/shader_port/config/metal_toolchain.json" _metal_toolchain_json)
string(REGEX MATCH "\"metalStd\"[ \t]*:[ \t]*\"([^\"]+)\"" _ "${_metal_toolchain_json}")
set(METAL_STD "${CMAKE_MATCH_1}")
if(NOT METAL_STD)
    set(METAL_STD "metal3.0")
    message(WARNING "metal_toolchain.json: metalStd not found, falling back to ${METAL_STD}")
endif()
message(STATUS "Metal shader standard: ${METAL_STD}")

# Compile Metal shaders at build time
# Note: Do NOT pass C++ include paths to Metal compiler
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.metallib
    COMMAND xcrun -sdk macosx metal -std=${METAL_STD} -c ${CMAKE_CURRENT_SOURCE_DIR}/UtilShaders.metal -o ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.air
    COMMAND xcrun -sdk macosx metallib ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.air -o ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.metallib
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/UtilShaders.metal
    COMMENT "Compiling UtilShaders"
    VERBATIM
)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
    COMMAND xcrun -sdk macosx metal -std=${METAL_STD} -c ${CMAKE_CURRENT_SOURCE_DIR}/SpriteShaders.metal -o ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.air
    COMMAND xcrun -sdk macosx metallib ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.air -o ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/SpriteShaders.metal
    COMMENT "Compiling SpriteShaders"
    VERBATIM
)

add_custom_target(MetalShaders ALL
    DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.metallib
            ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
)

if(NOT GENERATED_METAL_METALLIB)
    message(FATAL_ERROR "GENERATED_METAL_METALLIB is not set — generated game shaders will not be compiled.\n"
                        "Ensure Dart is installed and on PATH (https://dart.dev/get-dart) then re-run cmake.")
endif()
if(USE_HLSL_CONVERSION)
    add_dependencies(MetalShaders ConvertHLSLToMetal)
else()
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

install(FILES ${GENERATED_METAL_METALLIB}
              ${CMAKE_CURRENT_SOURCE_DIR}/Generated/generated_manifest.json
              ${CMAKE_CURRENT_SOURCE_DIR}/Generated/builtin_lookup_aliases.json
    DESTINATION lib
)
if(USE_HLSL_CONVERSION)
    install(FILES ${CONVERTER_MANIFEST}
        DESTINATION lib
        RENAME metal_converter_manifest.json
    )
endif()

set(DEFAULT_FARCRY_APP_BUNDLE "${CMAKE_BINARY_DIR}/FarCry.app")
set(FARCRY_APP_BUNDLE_DIR "${DEFAULT_FARCRY_APP_BUNDLE}" CACHE PATH "Location of FarCry.app for resource staging")
set(FARCRY_APP_RESOURCES_DIR "${FARCRY_APP_BUNDLE_DIR}/Contents/Resources")

add_custom_command(
    OUTPUT ${FARCRY_APP_RESOURCES_DIR}/GeneratedShaders.metallib
           ${FARCRY_APP_RESOURCES_DIR}/generated_manifest.json
           ${FARCRY_APP_RESOURCES_DIR}/builtin_lookup_aliases.json
    COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_APP_RESOURCES_DIR}
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${GENERATED_METAL_METALLIB} ${FARCRY_APP_RESOURCES_DIR}/GeneratedShaders.metallib
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_SOURCE_DIR}/Generated/generated_manifest.json ${FARCRY_APP_RESOURCES_DIR}/generated_manifest.json
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_SOURCE_DIR}/Generated/builtin_lookup_aliases.json ${FARCRY_APP_RESOURCES_DIR}/builtin_lookup_aliases.json
    DEPENDS ${GENERATED_METAL_METALLIB} ${CMAKE_CURRENT_SOURCE_DIR}/Generated/generated_manifest.json
            ${CMAKE_CURRENT_SOURCE_DIR}/Generated/builtin_lookup_aliases.json
    COMMENT "Staging generated Metal shaders into FarCry.app resources"
    VERBATIM
)

add_custom_target(GeneratedMetalBundleResources ALL
    DEPENDS ${FARCRY_APP_RESOURCES_DIR}/GeneratedShaders.metallib
            ${FARCRY_APP_RESOURCES_DIR}/generated_manifest.json
            ${FARCRY_APP_RESOURCES_DIR}/builtin_lookup_aliases.json)
if(USE_HLSL_CONVERSION)
    add_dependencies(GeneratedMetalBundleResources ConvertHLSLToMetal)
else()
    add_dependencies(GeneratedMetalBundleResources GeneratedMetalShaders)
endif()
add_dependencies(MetalShaders GeneratedMetalBundleResources)

add_custom_command(
    OUTPUT  ${FARCRY_APP_RESOURCES_DIR}/SpriteShaders.metallib
            ${FARCRY_APP_RESOURCES_DIR}/UtilShaders.metallib
    COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_APP_RESOURCES_DIR}
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
        ${FARCRY_APP_RESOURCES_DIR}/SpriteShaders.metallib
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.metallib
        ${FARCRY_APP_RESOURCES_DIR}/UtilShaders.metallib
    DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/SpriteShaders.metallib
            ${CMAKE_CURRENT_BINARY_DIR}/UtilShaders.metallib
    COMMENT "Staging SpriteShaders and UtilShaders into FarCry.app resources"
    VERBATIM
)
add_custom_target(StagedMetalShaders ALL
    DEPENDS ${FARCRY_APP_RESOURCES_DIR}/SpriteShaders.metallib
            ${FARCRY_APP_RESOURCES_DIR}/UtilShaders.metallib)
add_dependencies(StagedMetalShaders MetalShaders)
add_dependencies(XRenderMetal StagedMetalShaders)

if(APPLE)
    add_executable(metal_pso_validate test/metal_pso_validate.mm)
    target_include_directories(metal_pso_validate PRIVATE
        ${CMAKE_SOURCE_DIR}/CryCommon
        ${CMAKE_SOURCE_DIR}/RenderDll
        ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(metal_pso_validate PRIVATE XRenderMetal
        "-framework Foundation"
        "-framework Metal"
        "-framework CoreFoundation")
    set_source_files_properties(test/metal_pso_validate.mm PROPERTIES COMPILE_FLAGS "-x objective-c++")
    target_compile_features(metal_pso_validate PRIVATE cxx_std_17)
    target_link_options(metal_pso_validate PRIVATE "-Wl,-rpath,@executable_path")

    add_executable(metal_runtime_validate test/metal_runtime_validate.mm)
    target_include_directories(metal_runtime_validate PRIVATE
        ${CMAKE_SOURCE_DIR}/CryCommon
        ${CMAKE_SOURCE_DIR}/RenderDll
        ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(metal_runtime_validate PRIVATE XRenderMetal
        "-framework Foundation"
        "-framework Metal"
        "-framework MetalKit"
        "-framework QuartzCore"
        "-framework Cocoa"
        "-framework CoreFoundation")
    set_source_files_properties(test/metal_runtime_validate.mm PROPERTIES COMPILE_FLAGS "-x objective-c++")
    target_compile_features(metal_runtime_validate PRIVATE cxx_std_14)
    target_link_options(metal_runtime_validate PRIVATE "-Wl,-rpath,@executable_path")
endif()

# ------------------------------------------------------------------
# Unit tests — pure-logic renderer functions (no Metal dependency)
# ------------------------------------------------------------------
if(BUILD_TESTING OR CMAKE_BUILD_TYPE STREQUAL "Debug")
    enable_testing()
    add_executable(RendererLogicTests test/RendererLogicTests.cpp)
    target_include_directories(RendererLogicTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_compile_features(RendererLogicTests PRIVATE cxx_std_14)
    # Resolve libc++ headers in CLT-only environments
    if(DEFINED LIBCXX_INCLUDE_DIR AND EXISTS "${LIBCXX_INCLUDE_DIR}")
        target_include_directories(RendererLogicTests SYSTEM PRIVATE "${LIBCXX_INCLUDE_DIR}")
    endif()
    # This target is pure-logic C++ (no heap bugs to catch) — opt out of the
    # global Debug ASan flags to avoid libclang_rt.asan dyld initialisation
    # hangs on machines where the ASan runtime deadlocks at startup.
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        target_compile_options(RendererLogicTests PRIVATE -fno-sanitize=address)
        target_link_options(RendererLogicTests PRIVATE -fno-sanitize=address)
    endif()
    add_test(NAME RendererLogicTests COMMAND RendererLogicTests)
    if(APPLE)
        add_executable(MetalManifestPSOHelpersTests test/MetalManifestPSOHelpersTests.mm)
        target_include_directories(MetalManifestPSOHelpersTests PRIVATE
            ${CMAKE_SOURCE_DIR}/CryCommon
            ${CMAKE_SOURCE_DIR}/RenderDll
            ${CMAKE_CURRENT_SOURCE_DIR})
        target_link_libraries(MetalManifestPSOHelpersTests PRIVATE XRenderMetal
            "-framework Foundation"
            "-framework Metal"
            "-framework CoreFoundation")
        set_source_files_properties(test/MetalManifestPSOHelpersTests.mm PROPERTIES COMPILE_FLAGS "-x objective-c++")
        target_compile_features(MetalManifestPSOHelpersTests PRIVATE cxx_std_17)
        target_link_options(MetalManifestPSOHelpersTests PRIVATE "-Wl,-rpath,@executable_path")
        add_test(NAME MetalManifestPSOHelpersTests COMMAND MetalManifestPSOHelpersTests)
        add_test(NAME metal_pso_validate COMMAND metal_pso_validate --generated-dir ${CMAKE_CURRENT_SOURCE_DIR}/Generated --max-failures 10)
    endif()
endif()


stage_dylib_to_bundle(XRenderMetal)
