# FarCry Main Executable
cmake_minimum_required(VERSION 3.20)

# Source files for FarCry executable
set(FARCRY_SOURCES
    Main.cpp
)

# Platform-specific resources
if(WIN32)
    set(FARCRY_SOURCES ${FARCRY_SOURCES}
        FarCry.rc
        resource.h
    )
endif()

# Create the main executable
add_executable(FarCry ${FARCRY_SOURCES})

# Link required libraries
target_link_libraries(FarCry PRIVATE
    CryCommon
    CrySystem
    CryGame
    Cry3DEngine
    CryAnimation
    CryAISystem
    CryEntitySystem
    CryFont
    CryInput
    CryMovie
    CryNetwork
    CryPhysics
    CryScriptSystem
    CrySoundSystem
)

# Platform-specific linking
if(APPLE)
    # macOS frameworks
    target_link_libraries(FarCry PRIVATE
        ${COCOA_FRAMEWORK}
        ${OPENGL_FRAMEWORK}
        ${CORE_AUDIO_FRAMEWORK}
        ${AUDIO_TOOLBOX_FRAMEWORK}
        ${IOKIT_FRAMEWORK}
        ${CORE_FOUNDATION_FRAMEWORK}
        "-framework Metal"
        "-framework MetalKit"
        "-framework QuartzCore"
        "-framework Carbon"
    )
    
    # Set as macOS app bundle
    set_target_properties(FarCry PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME "Far Cry"
        MACOSX_BUNDLE_BUNDLE_VERSION ${CMAKE_PROJECT_VERSION}
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${CMAKE_PROJECT_VERSION}
        MACOSX_BUNDLE_IDENTIFIER "com.crytek.farcry"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    )
    
elseif(WIN32)
    # Windows libraries
    target_link_libraries(FarCry PRIVATE
        user32 gdi32 winmm wsock32 advapi32 kernel32
        d3d9 d3dx9 dinput8 dxguid
    )
    
elseif(UNIX)
    # Linux libraries
    target_link_libraries(FarCry PRIVATE
        dl pthread m
        GL GLU X11 Xext
    )
endif()

# Include directories
target_include_directories(FarCry PRIVATE
    ${CMAKE_SOURCE_DIR}/CryCommon
    ${CMAKE_SOURCE_DIR}/CrySystem
    ${CMAKE_SOURCE_DIR}/CryGame
)

# Preprocessor definitions
target_compile_definitions(FarCry PRIVATE
    FARCRY_EXECUTABLE=1
)

if(APPLE)
    target_compile_definitions(FarCry PRIVATE
        __APPLE__=1
        __MACH__=1
    )
    
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        target_compile_definitions(FarCry PRIVATE
            _CPU_ARM64=1
        )
    endif()
endif()

# Set output directory
set_target_properties(FarCry PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)
