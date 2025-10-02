cmake_minimum_required(VERSION 3.20)
project(FarCryWorking VERSION 1.34 LANGUAGES C CXX OBJCXX)

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
    
    # Find frameworks
    find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
    find_library(METAL_FRAMEWORK Metal REQUIRED)
    find_library(CORE_AUDIO_FRAMEWORK CoreAudio REQUIRED)
    find_library(AUDIO_TOOLBOX_FRAMEWORK AudioToolbox REQUIRED)
    find_library(IOKIT_FRAMEWORK IOKit REQUIRED)
    find_library(CORE_FOUNDATION_FRAMEWORK CoreFoundation REQUIRED)
    find_library(CARBON_FRAMEWORK Carbon REQUIRED)
    find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
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
add_subdirectory(CryCommon)

# Build all CryEngine components
add_subdirectory(CrySystem)
add_subdirectory(Cry3DEngine)
add_subdirectory(CryEntitySystem)
add_subdirectory(CryAnimation)
# CryInput temporarily excluded due to interface mismatch issues
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
set(FARCRY_WORKING_SOURCES
    FARCRY/Main.cpp
)

# Create the working Far Cry executable
add_executable(FarCryWorking ${FARCRY_WORKING_SOURCES})

# Link all CryEngine libraries (excluding CryNetwork as requested)
target_link_libraries(FarCryWorking PRIVATE
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
    target_link_libraries(FarCryWorking PRIVATE
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
    set_target_properties(FarCryWorking PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME "Far Cry"
        MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
        MACOSX_BUNDLE_IDENTIFIER "com.crytek.farcry"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/FARCRY/Info.plist.in"
    )
endif()

# Install
if(APPLE)
    install(TARGETS FarCryWorking BUNDLE DESTINATION .)
    
    # Copy all dylibs to the app bundle automatically
    add_custom_command(TARGET FarCryWorking POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/FarCryWorking.app/Contents/MacOS/
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
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
            $<TARGET_FILE:XRenderMetal>
            ${CMAKE_BINARY_DIR}/FarCryWorking.app/Contents/MacOS/
        COMMENT "Copying all dylibs to app bundle"
    )
endif()
