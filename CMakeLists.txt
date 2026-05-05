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

# Helper: copy a single dylib into the app bundle immediately after it is rebuilt.
# Must be called from the same CMakeLists.txt that defines the target (subdirectory).
function(stage_dylib_to_bundle tgt)
    if(APPLE)
        add_custom_command(TARGET ${tgt} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory
                "${CMAKE_BINARY_DIR}/FarCry.app/Contents/MacOS"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "$<TARGET_FILE:${tgt}>"
                "${CMAKE_BINARY_DIR}/FarCry.app/Contents/MacOS/"
            COMMENT "Staging ${tgt} to app bundle"
        )
    endif()
endfunction()

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
    
    # ---------------------------------------------------------------------------
    # FCData staging — required game asset PAK archives
    # ---------------------------------------------------------------------------
    # Required PAK files.  The game cannot load any level without these.
    set(FCDATA_REQUIRED_PAKS
        FCData/Textures.pak
        FCData/Shaders.pak
        FCData/Scripts.pak
        FCData/Sounds.pak
        FCData/Objects.pak
    )

    set(FCData_FOUND FALSE)
    set(FCData_PATH "")

    foreach(_candidate
            "${CMAKE_SOURCE_DIR}/FCData"
            "${CMAKE_SOURCE_DIR}/Assets/FCData"
            "${CMAKE_BINARY_DIR}/FCData"
            "${CMAKE_SOURCE_DIR}/fcdata")
        if(EXISTS "${_candidate}")
            set(FCData_FOUND TRUE)
            set(FCData_PATH "${_candidate}")
            message(STATUS "Found FCData at: ${FCData_PATH}")
            break()
        endif()
    endforeach()

    if(FCData_FOUND)
        # Verify required PAK files are present and report any that are missing.
        set(_missing_paks "")
        foreach(_pak ${FCDATA_REQUIRED_PAKS})
            if(NOT EXISTS "${FCData_PATH}/${_pak}")
                # Try without the leading FCData/ prefix (in case FCData_PATH already ends in FCData)
                string(REPLACE "FCData/" "" _pak_short "${_pak}")
                if(NOT EXISTS "${FCData_PATH}/${_pak_short}")
                    list(APPEND _missing_paks "  ${_pak_short}")
                endif()
            endif()
        endforeach()
        if(_missing_paks)
            message(WARNING
                "\n=== FCData incomplete — missing required PAK files ===\n"
                "Directory: ${FCData_PATH}\n"
                "Missing:\n${_missing_paks}\n"
                "Copy the missing files from your Far Cry installation:\n"
                "  cp <FarCry_install>/FCData/<file>.pak ${FCData_PATH}/\n"
                "Steam (via CrossOver) path:\n"
                "  $ENV{HOME}/Library/Application Support/CrossOver/Bottles/Steam-2/drive_c/Program Files (x86)/Steam/steamapps/common/FarCry/FCData/\n"
                "=======================================================")
        endif()

        add_custom_command(TARGET FarCry POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_BUNDLE_RESOURCES}/FCData
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${FCData_PATH}
                ${FARCRY_BUNDLE_RESOURCES}/FCData
            COMMENT "Staging FCData PAK archives into FarCry.app/Resources"
        )
    else()
        message(SEND_ERROR
            "\n=== FCData directory not found — cannot stage game assets ===\n"
            "The FCData directory contains all required game assets.\n"
            "Expected at one of:\n"
            "  ${CMAKE_SOURCE_DIR}/FCData\n"
            "  ${CMAKE_SOURCE_DIR}/Assets/FCData\n"
            "  ${CMAKE_BINARY_DIR}/FCData\n"
            "To obtain FCData, copy it from your Far Cry installation.\n"
            "Steam (via CrossOver):\n"
            "  cp -r \"$ENV{HOME}/Library/Application Support/CrossOver/Bottles/Steam-2/drive_c/Program Files (x86)/Steam/steamapps/common/FarCry/FCData\" ${CMAKE_SOURCE_DIR}/\n"
            "Required PAK files inside FCData/:\n"
            "  Textures.pak  Shaders.pak  Scripts.pak\n"
            "  Sounds.pak    Objects.pak  GameData.pak\n"
            "=============================================================")
    endif()

    set(FARCRY_LEVELS_SOURCE "${CMAKE_SOURCE_DIR}/Levels")
    if(EXISTS "${FARCRY_LEVELS_SOURCE}")
        add_custom_command(TARGET FarCry POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E rm -Rf
                "${FARCRY_BUNDLE_RESOURCES}/FCData/Levels"
            COMMAND ${CMAKE_COMMAND} -E make_directory
                "${FARCRY_BUNDLE_RESOURCES}/FCData/Levels"
            COMMAND rsync -a --delete --no-l
                "${FARCRY_LEVELS_SOURCE}/"
                "${FARCRY_BUNDLE_RESOURCES}/FCData/Levels/"
            COMMENT "Syncing Levels into FarCry.app/Resources/FCData/Levels"
            VERBATIM
        )
        add_custom_command(TARGET FarCry POST_BUILD
            COMMAND dart
                "${CMAKE_SOURCE_DIR}/tools/level_validator/bin/validate_levels.dart"
                "${FARCRY_BUNDLE_RESOURCES}/FCData/Levels"
            COMMENT "Validating level PAK presence in FCData/Levels"
            VERBATIM
        )
    else()
        message(WARNING
            "Levels source not found at ${FARCRY_LEVELS_SOURCE}; "
            "level loading will fail at runtime. "
            "Create the symlink: ln -s <CrossOver FarCry>/Levels ${CMAKE_SOURCE_DIR}/Levels")
    endif()

    set(SCRIPTS_SOURCE_DIR ${CMAKE_SOURCE_DIR}/Scripts)
    if(EXISTS ${SCRIPTS_SOURCE_DIR})
        add_custom_command(TARGET FarCry POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory ${FARCRY_BUNDLE_RESOURCES}/FCData/Scripts
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${SCRIPTS_SOURCE_DIR}
                ${FARCRY_BUNDLE_RESOURCES}/FCData/Scripts
            COMMENT "Copying loose Scripts overrides into FCData for runtime shadowing (sys_PakPriority=0)"
        )
    else()
        message(WARNING "Scripts directory not found at ${SCRIPTS_SOURCE_DIR}; Lua overrides will be unavailable.")
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
