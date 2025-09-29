cmake_minimum_required(VERSION 3.20)
project(FarCry VERSION 1.34 LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Platform detection
if(APPLE)
    set(PLATFORM_MACOS TRUE)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        set(PLATFORM_ARM64 TRUE)
        message(STATUS "Building Far Cry for macOS ARM64 (Apple Silicon)")
    else()
        set(PLATFORM_X86_64 TRUE)
        message(STATUS "Building Far Cry for macOS x86_64")
    endif()
elseif(WIN32)
    set(PLATFORM_WINDOWS TRUE)
    message(STATUS "Building Far Cry for Windows")
elseif(UNIX)
    set(PLATFORM_LINUX TRUE)
    message(STATUS "Building Far Cry for Linux")
endif()

# Compiler-specific settings
if(APPLE)
    set(CMAKE_OSX_ARCHITECTURES "${CMAKE_SYSTEM_PROCESSOR}")
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")
    
    # Enable ARM64 optimizations for Apple Silicon
    if(PLATFORM_ARM64)
        add_compile_definitions(_CPU_ARM64=1)
        add_compile_options(-mcpu=apple-m1)
    endif()
    
    # macOS-specific defines
    add_compile_definitions(__APPLE__=1 __MACH__=1)
    
    # Find required frameworks
    find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
    find_library(OPENGL_FRAMEWORK OpenGL REQUIRED)
    find_library(CORE_AUDIO_FRAMEWORK CoreAudio REQUIRED)
    find_library(AUDIO_TOOLBOX_FRAMEWORK AudioToolbox REQUIRED)
    find_library(IOKIT_FRAMEWORK IOKit REQUIRED)
    find_library(CORE_FOUNDATION_FRAMEWORK CoreFoundation REQUIRED)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    
elseif(WIN32)
    add_compile_definitions(WIN32=1 _WINDOWS=1)
elseif(UNIX)
    add_compile_definitions(LINUX=1)
endif()

# Global include directories
include_directories(
    ${CMAKE_SOURCE_DIR}/CryCommon
    ${CMAKE_SOURCE_DIR}/CrySystem
)

# Add STLPORT only for Windows (macOS uses standard library)
if(WIN32)
    include_directories(${CMAKE_SOURCE_DIR}/STLPORT/stlport)
endif()

# Global compiler flags for legacy code compatibility
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
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
    )
endif()

# Disable custom memory manager for macOS (use standard library)
if(APPLE)
    add_compile_definitions(NOT_USE_CRY_MEMORY_MANAGER=1)
endif()

# Subdirectories for each module (in dependency order)
add_subdirectory(CryCommon)
add_subdirectory(CrySystem)
add_subdirectory(CryEntitySystem)
add_subdirectory(CryPhysics)
add_subdirectory(CryScriptSystem)
add_subdirectory(CryFont)
add_subdirectory(CryNetwork)
add_subdirectory(CryAISystem)
add_subdirectory(CryMovie)
add_subdirectory(CryAnimation)
add_subdirectory(Cry3DEngine)
add_subdirectory(CryInput)
add_subdirectory(CrySoundSystem)
add_subdirectory(CryGame)

# Renderer modules
add_subdirectory(RenderDll)

# Main executable
add_subdirectory(FARCRY)

# Platform-specific configurations
if(APPLE)
    message(STATUS "macOS app bundle configuration will be applied to FarCry target")
endif()

# Installation
if(APPLE)
    install(TARGETS FarCry BUNDLE DESTINATION .)
else()
    install(TARGETS FarCry RUNTIME DESTINATION bin)
endif()