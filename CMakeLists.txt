cmake_minimum_required(VERSION 3.20)
project(FarCry VERSION 1.34 LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Platform detection
if(APPLE)
    message(STATUS "Building working Far Cry for macOS ARM64 (Apple Silicon)")
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")
    
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        add_compile_definitions(_CPU_ARM64=1)
        add_compile_options(-mcpu=apple-m1)
    endif()

    # Ensure C++ stdlib headers are found when only CLT is installed
    execute_process(
        COMMAND xcrun --sdk macosx --show-sdk-path
        OUTPUT_VARIABLE MACOS_SDK_PATH
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE XCRUN_SDK_RESULT
    )
    if(XCRUN_SDK_RESULT EQUAL 0 AND MACOS_SDK_PATH)
        set(LIBCXX_INCLUDE_DIR "${MACOS_SDK_PATH}/usr/include/c++/v1")
        if(EXISTS "${LIBCXX_INCLUDE_DIR}")
            include_directories(SYSTEM "${LIBCXX_INCLUDE_DIR}")
            message(STATUS "Added libc++ include path: ${LIBCXX_INCLUDE_DIR}")
        else()
            message(WARNING "macOS SDK found at ${MACOS_SDK_PATH} but libc++ headers not present at expected path")
        endif()
    else()
        message(WARNING "xcrun could not locate the macOS SDK — libc++ headers may be missing. "
                        "Run: xcode-select --install")
    endif()
    
    # Find frameworks
    find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
    find_library(METAL_FRAMEWORK Metal REQUIRED)
    find_library(CORE_AUDIO_FRAMEWORK CoreAudio REQUIRED)
    find_library(AUDIO_TOOLBOX_FRAMEWORK AudioToolbox REQUIRED)
    find_library(IOKIT_FRAMEWORK IOKit REQUIRED)
    find_library(CORE_FOUNDATION_FRAMEWORK CoreFoundation REQUIRED)
    find_library(CARBON_FRAMEWORK Carbon REQUIRED)
    find_library(APPKIT_FRAMEWORK AppKit REQUIRED)

    # Require the Metal shader compiler (xcrun metal).
    # The binary lives inside the Xcode toolchain and is not on $PATH,
    # so find_program is unreliable — use xcrun directly.
    execute_process(
        COMMAND xcrun -sdk macosx metal --version
        OUTPUT_QUIET
        ERROR_QUIET
        RESULT_VARIABLE METAL_COMPILER_CHECK
    )
    if(NOT METAL_COMPILER_CHECK EQUAL 0)
        message(FATAL_ERROR "Metal shader compiler not found.\n"
                            "Ensure Xcode is installed and selected as the active developer directory:\n"
                            "  sudo xcode-select -s /Applications/Xcode.app\n"
                            "Then re-run cmake.")
    endif()
    message(STATUS "Metal shader compiler: found (xcrun metal)")
endif()

# Include directories
include_directories(${CMAKE_SOURCE_DIR})
include_directories(${CMAKE_SOURCE_DIR}/CryCommon)

# Global macOS settings
if(APPLE)
    add_compile_definitions(
        __APPLE__=1
        __MACH__=1
        NOT_USE_CRY_MEMORY_MANAGER=1
        NOT_USE_UBICOM_SDK=1
    )
endif()

# Compiler flags
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    # ASAN is opt-in (ENABLE_ASAN=ON) because libclang_rt.asan has a dyld
    # initialisation deadlock on macOS Sequoia+ when the shared cache is large.
    # Pass -DENABLE_ASAN=ON to cmake to re-enable.
    option(ENABLE_ASAN "Enable AddressSanitizer (Debug builds only)" OFF)
    if(ENABLE_ASAN AND APPLE AND CMAKE_BUILD_TYPE STREQUAL "Debug")
        add_compile_options(-fsanitize=address -fno-omit-frame-pointer -g)
        add_link_options(-fsanitize=address)
    endif()
    
    add_compile_options(
        -Wno-deprecated-declarations
        -Wno-unused-variable
        -Wno-unused-function
        -Wno-format-security
        -Wno-reorder
        -Wno-switch
        -Wno-macro-redefined
        -Wno-nonportable-include-path
        -Wno-unused-private-field
        -Wno-inconsistent-missing-override
        -Wno-deprecated-register
    )
endif()

# Add CryCommon as interface library
enable_testing()
add_subdirectory(CryCommon)

# Add embedded resources for macOS
add_subdirectory(src/resources)
add_subdirectory(CrySystem)
add_subdirectory(Cry3DEngine)
add_subdirectory(CryEntitySystem)
add_subdirectory(CryAnimation)
add_subdirectory(CryInput)
add_subdirectory(CryMovie)
add_subdirectory(CryPhysics)
add_subdirectory(CryAISystem)
add_subdirectory(CryFont)
# CryNetwork excluded as requested - multiplayer functionality
# add_subdirectory(CryNetwork)
add_subdirectory(CryScriptSystem)
add_subdirectory(CrySoundSystem)  # Enabled for macOS - Core Audio implementation available
add_subdirectory(RenderDll)
add_subdirectory(CryGame)

# Just compile the Main.cpp which we know works
set(FARCRY_SOURCES
    FARCRY/Main.cpp
)

# On macOS, compile Main.cpp as Objective-C++ for Cocoa API support
if(APPLE)
    set_source_files_properties(FARCRY/Main.cpp PROPERTIES
        COMPILE_FLAGS "-x objective-c++"
    )
endif()

# Create the working Far Cry executable
add_executable(FarCry ${FARCRY_SOURCES})

# Link all CryEngine libraries (excluding CryNetwork as requested)
target_link_libraries(FarCry PRIVATE
    CrySystem
    Cry3DEngine
    CryEntitySystem
    CryAnimation
    CryInput
    CryMovie
    CryPhysics
    CryAISystem
    CryFont
    CryScriptSystem
    CrySoundSystem  # Enabled for macOS - Core Audio implementation available
    # CryNetwork excluded as requested - multiplayer functionality
    CryGame
)

# Platform header will be included automatically via #include <platform.h>

# Link frameworks  
if(APPLE)
    target_link_libraries(FarCry PRIVATE
        ${COCOA_FRAMEWORK}
        ${METAL_FRAMEWORK}
        ${CORE_AUDIO_FRAMEWORK}
        ${AUDIO_TOOLBOX_FRAMEWORK}
        ${IOKIT_FRAMEWORK}
        ${CORE_FOUNDATION_FRAMEWORK}
        ${CARBON_FRAMEWORK}
        ${APPKIT_FRAMEWORK}
    )
    
    # Configure as macOS app bundle
    set_target_properties(FarCry PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME "Far Cry"
        MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
        MACOSX_BUNDLE_IDENTIFIER "com.crytek.farcry"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/FARCRY/Info.plist.in"
    )

    add_dependencies(FarCry XRenderMetal)
endif()

# Install
if(APPLE)
    install(TARGETS FarCry BUNDLE DESTINATION .)
    
    # Use @executable_path for dylib lookup so they can be found in the app bundle
    set_target_properties(FarCry PROPERTIES
        BUILD_RPATH "@executable_path"
        INSTALL_RPATH "@executable_path"
    )
    
    # Copy all dylibs and Metal shader libraries to the app bundle whenever FarCry or any dylib is rebuilt
    set(FARCRY_BUNDLE_DIR ${CMAKE_BINARY_DIR}/FarCry.app)
    set(FARCRY_BUNDLE_MACOS ${FARCRY_BUNDLE_DIR}/Contents/MacOS)
    set(FARCRY_BUNDLE_RESOURCES ${FARCRY_BUNDLE_DIR}/Contents/Resources)
    set(XRENDER_METAL_BINARY_DIR ${CMAKE_BINARY_DIR}/RenderDll/XRenderMetal)

    add_custom_command(TARGET FarCry POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_BUNDLE_MACOS}
        COMMAND ${CMAKE_COMMAND} -E copy 
            $<TARGET_FILE:CrySystem>
            $<TARGET_FILE:Cry3DEngine>
            $<TARGET_FILE:CryEntitySystem>
            $<TARGET_FILE:CryAnimation>
            $<TARGET_FILE:CryInput>
            $<TARGET_FILE:CryMovie>
            $<TARGET_FILE:CryPhysics>
            $<TARGET_FILE:CryAISystem>
            $<TARGET_FILE:CryFont>
            $<TARGET_FILE:CryScriptSystem>
            $<TARGET_FILE:CrySoundSystem>
            $<TARGET_FILE:CryGame>
            $<TARGET_FILE:XRenderMetal>
            ${FARCRY_BUNDLE_MACOS}
        COMMENT "Copying all dylibs to app bundle"
    )
    
    # Copy Metal shader libraries separately with explicit dependency on MetalShaders target
    add_custom_command(TARGET FarCry POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${CMAKE_BINARY_DIR}/RenderDll/XRenderMetal/UtilShaders.metallib
            ${CMAKE_BINARY_DIR}/RenderDll/XRenderMetal/SpriteShaders.metallib
            ${FARCRY_BUNDLE_MACOS}
        COMMENT "Copying Metal shader libraries to app bundle"
        DEPENDS MetalShaders
    )

    if(TARGET GeneratedMetalShaders)
        add_dependencies(FarCry GeneratedMetalShaders)
        add_custom_command(TARGET FarCry POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_BUNDLE_RESOURCES}
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                ${XRENDER_METAL_BINARY_DIR}/GeneratedShaders.metallib
                ${FARCRY_BUNDLE_RESOURCES}/GeneratedShaders.metallib
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                ${CMAKE_SOURCE_DIR}/RenderDll/XRenderMetal/Generated/generated_manifest.json
                ${FARCRY_BUNDLE_RESOURCES}/generated_manifest.json
            COMMENT "Copying generated Metal shader bundle artifacts"
        )
    endif()
    
    # Copy game assets to Resources directory
    if(EXISTS ${CMAKE_SOURCE_DIR}/fcsplash.bmp)
        add_custom_command(TARGET FarCry POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_BUNDLE_RESOURCES}
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                ${CMAKE_SOURCE_DIR}/fcsplash.bmp
                ${FARCRY_BUNDLE_RESOURCES}/fcsplash.bmp
            COMMENT "Copying splash screen asset to Resources"
        )
    endif()
    
    # Create Levels directory in Resources
    add_custom_command(TARGET FarCry POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_BUNDLE_RESOURCES}/Levels
        COMMENT "Creating Levels directory in Resources"
    )
    
    # Copy FCData directory to Resources (contains all PAK files)
    # FCData contains all game assets (textures, sounds, scripts, localized content) in PAK archives
    # It should be located in the project root directory
    set(FCData_FOUND FALSE)
    set(FCData_PATH "")
    
    # Check primary location: project root
    if(EXISTS ${CMAKE_SOURCE_DIR}/FCData)
        set(FCData_FOUND TRUE)
        set(FCData_PATH ${CMAKE_SOURCE_DIR}/FCData)
        message(STATUS "Found FCData directory at: ${FCData_PATH}")
    # Check Assets subdirectory (symlink from Steam install)
    elseif(EXISTS ${CMAKE_SOURCE_DIR}/Assets/FCData)
        set(FCData_FOUND TRUE)
        set(FCData_PATH ${CMAKE_SOURCE_DIR}/Assets/FCData)
        message(STATUS "Found FCData directory at: ${FCData_PATH}")
    # Check alternative location: build directory (for development)
    elseif(EXISTS ${CMAKE_BINARY_DIR}/FCData)
        set(FCData_FOUND TRUE)
        set(FCData_PATH ${CMAKE_BINARY_DIR}/FCData)
        message(STATUS "Found FCData directory at: ${FCData_PATH}")
    # Check if FCData exists but with different case (macOS case-insensitive filesystem)
    elseif(EXISTS ${CMAKE_SOURCE_DIR}/fcdata)
        set(FCData_FOUND TRUE)
        set(FCData_PATH ${CMAKE_SOURCE_DIR}/fcdata)
        message(STATUS "Found FCData directory (case variant) at: ${FCData_PATH}")
    else()
        message(WARNING "")
        message(WARNING "================================================================================")
        message(WARNING "FCData directory not found - Game assets will not be available!")
        message(WARNING "================================================================================")
        message(WARNING "")
        message(WARNING "The FCData directory contains all game assets (textures, sounds, scripts,")
        message(WARNING "localized content) packaged in PAK archive files.")
        message(WARNING "")
        message(WARNING "Expected locations:")
        message(WARNING "  - ${CMAKE_SOURCE_DIR}/FCData")
        message(WARNING "  - ${CMAKE_BINARY_DIR}/FCData")
        message(WARNING "")
        message(WARNING "To resolve this issue:")
        message(WARNING "  1. Ensure you have the Far Cry game assets (FCData directory)")
        message(WARNING "  2. Place the FCData directory in the project root: ${CMAKE_SOURCE_DIR}/")
        message(WARNING "  3. The FCData directory should contain:")
        message(WARNING "     - Localized/ (with language PAK files)")
        message(WARNING "     - *.pak files (Textures.pak, Sounds.pak, Scripts.pak, etc.)")
        message(WARNING "")
        message(WARNING "Note: The game will run but will not be able to load textures, sounds,")
        message(WARNING "scripts, or other assets without the FCData directory.")
        message(WARNING "")
        message(WARNING "================================================================================")
        message(WARNING "")
    endif()
    
    if(FCData_FOUND)
        add_custom_command(TARGET FarCry POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_BUNDLE_RESOURCES}/FCData
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${FCData_PATH}
                ${FARCRY_BUNDLE_RESOURCES}/FCData
            COMMENT "Copying FCData directory with PAK files to Resources"
        )
    endif()

    set(SCRIPTS_SOURCE_DIR ${CMAKE_SOURCE_DIR}/Scripts)
    if(EXISTS ${SCRIPTS_SOURCE_DIR})
        add_custom_command(TARGET FarCry POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_BUNDLE_RESOURCES}/Scripts
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${SCRIPTS_SOURCE_DIR}
                ${FARCRY_BUNDLE_RESOURCES}/Scripts
            COMMENT "Copying loose Scripts directory for runtime overrides"
        )
    else()
        message(WARNING "Scripts directory not found at ${SCRIPTS_SOURCE_DIR}; runtime overrides will be unavailable.")
    endif()

    set(CONVERTED_VIDEOS_ROOT "${CMAKE_SOURCE_DIR}/build/converted_videos" CACHE PATH "Root directory containing converted intro/demoloop videos")

    set(INTRO_VIDEOS_SOURCE_DIR ${CONVERTED_VIDEOS_ROOT}/english/English)
    set(INTRO_VIDEOS_TARGET_DIR ${FARCRY_BUNDLE_RESOURCES}/languages/movies/english)
    if(EXISTS ${INTRO_VIDEOS_SOURCE_DIR})
        add_custom_command(TARGET FarCry POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory ${INTRO_VIDEOS_TARGET_DIR}
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${INTRO_VIDEOS_SOURCE_DIR}
                ${INTRO_VIDEOS_TARGET_DIR}
            COMMENT "Copying converted intro videos for AVFoundation playback"
        )
    else()
        message(WARNING "Converted intro videos not found at ${INTRO_VIDEOS_SOURCE_DIR}; intro logos may fail to play.")
    endif()

    set(DEMO_LOOP_SOURCE_DIR ${CONVERTED_VIDEOS_ROOT}/english/DemoLoops)
    set(DEMO_LOOP_TARGET_DIR ${FARCRY_BUNDLE_RESOURCES}/languages/movies/english/demoloops)
    if(EXISTS ${DEMO_LOOP_SOURCE_DIR})
        add_custom_command(TARGET FarCry POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory ${DEMO_LOOP_TARGET_DIR}
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${DEMO_LOOP_SOURCE_DIR}
                ${DEMO_LOOP_TARGET_DIR}
            COMMENT "Copying converted demoloop videos for AVFoundation playback"
        )
    endif()
endif()
