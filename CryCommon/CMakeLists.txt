# CryCommon - Common headers and interfaces
# This is a header-only library that provides platform abstractions

# Create an interface library for CryCommon headers
add_library(CryCommon INTERFACE)

# Set include directories
target_include_directories(CryCommon INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# Platform-specific compile definitions
if(APPLE)
    target_compile_definitions(CryCommon INTERFACE
        __APPLE__=1
        __MACH__=1
    )
    
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        target_compile_definitions(CryCommon INTERFACE
            _CPU_ARM64=1
        )
    else()
        target_compile_definitions(CryCommon INTERFACE
            _CPU_X86_64=1
        )
    endif()
    
elseif(WIN32)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        target_compile_definitions(CryCommon INTERFACE
            WIN64=1
            _CPU_AMD64=1
        )
    else()
        target_compile_definitions(CryCommon INTERFACE
            WIN32=1
            _CPU_X86=1
        )
    endif()
    
elseif(UNIX)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        target_compile_definitions(CryCommon INTERFACE
            LINUX64=1
            _CPU_AMD64=1
        )
    else()
        target_compile_definitions(CryCommon INTERFACE
            LINUX32=1
            _CPU_X86=1
        )
    endif()
endif()

# Disable certain warnings for compatibility
if(APPLE)
    target_compile_options(CryCommon INTERFACE
        -Wno-deprecated-declarations
        -Wno-unused-variable
        -Wno-unused-function
        -Wno-format-security
    )
endif()

# Export all headers as part of the interface
file(GLOB_RECURSE CRYCOMMON_HEADERS "*.h")
target_sources(CryCommon INTERFACE ${CRYCOMMON_HEADERS})
