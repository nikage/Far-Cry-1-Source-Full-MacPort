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

# Try to build CrySystem (we'll fix compilation issues)
add_subdirectory(CrySystem)

# Just compile the Main.cpp which we know works
set(FARCRY_WORKING_SOURCES
    FARCRY/Main.cpp
)

# Create the working Far Cry executable
add_executable(FarCryWorking ${FARCRY_WORKING_SOURCES})

# Link the CrySystem library
target_link_libraries(FarCryWorking PRIVATE CrySystem)

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
endif()
