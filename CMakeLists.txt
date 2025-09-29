cmake_minimum_required(VERSION 3.20)
project(FarCryPortTest VERSION 1.0 LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Platform detection
if(APPLE)
    message(STATUS "Building test for macOS")
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        message(STATUS "Target: Apple Silicon (ARM64)")
        add_compile_definitions(_CPU_ARM64=1)
    else()
        message(STATUS "Target: Intel Mac (x86_64)")
        add_compile_definitions(_CPU_X86_64=1)
    endif()
    
    add_compile_definitions(__APPLE__=1 __MACH__=1)
    
    # macOS deployment target
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")
    
    # Find required frameworks
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    find_library(METAL_FRAMEWORK Metal REQUIRED)
    find_library(CORE_AUDIO_FRAMEWORK CoreAudio REQUIRED)
    
    message(STATUS "Found Foundation: ${FOUNDATION_FRAMEWORK}")
    message(STATUS "Found Metal: ${METAL_FRAMEWORK}")
    message(STATUS "Found CoreAudio: ${CORE_AUDIO_FRAMEWORK}")
endif()

# Include directories
include_directories(${CMAKE_SOURCE_DIR})

# Test executable
add_executable(farcry_port_test test_simple.cpp)

# Disable memory manager for this test
target_compile_definitions(farcry_port_test PRIVATE NOT_USE_CRY_MEMORY_MANAGER=1)

# Set Objective-C++ for macOS frameworks
if(APPLE)
    set_source_files_properties(test_simple.cpp PROPERTIES 
        COMPILE_FLAGS "-x objective-c++")
    
    target_link_libraries(farcry_port_test PRIVATE
        ${FOUNDATION_FRAMEWORK}
        ${METAL_FRAMEWORK}
        ${CORE_AUDIO_FRAMEWORK}
    )
endif()

# Compiler warnings
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(farcry_port_test PRIVATE
        -Wno-deprecated-declarations
        -Wno-unused-variable
        -Wno-format-security
    )
endif()
