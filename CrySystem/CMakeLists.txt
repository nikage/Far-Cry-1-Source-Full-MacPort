# CrySystem - Core engine system
cmake_minimum_required(VERSION 3.20)

# Find all source files
file(GLOB_RECURSE CRYSYSTEM_SOURCES
    "*.cpp"
    "*.c"
)

file(GLOB_RECURSE CRYSYSTEM_HEADERS
    "*.h"
)

# Exclude platform-specific files that don't match current platform
if(NOT WIN32)
    list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX ".*Win32.*")
    list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX ".*Windows.*")
    list(FILTER CRYSYSTEM_HEADERS EXCLUDE REGEX ".*Win32.*")
    list(FILTER CRYSYSTEM_HEADERS EXCLUDE REGEX ".*Windows.*")
endif()

if(NOT UNIX OR APPLE)
    list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX ".*Linux.*")
    list(FILTER CRYSYSTEM_HEADERS EXCLUDE REGEX ".*Linux.*")
endif()

# Add our macOS-specific files
if(APPLE)
    list(APPEND CRYSYSTEM_SOURCES
        MacOSFileSystem.cpp
    )
    list(APPEND CRYSYSTEM_HEADERS
        MacOSFileSystem.h
    )
endif()

# Create the CrySystem library
add_library(CrySystem SHARED ${CRYSYSTEM_SOURCES} ${CRYSYSTEM_HEADERS})

# Link CryCommon interface
target_link_libraries(CrySystem PUBLIC CryCommon)

# Include directories
target_include_directories(CrySystem PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

# Add STLPORT only for Windows
if(WIN32)
    target_include_directories(CrySystem PUBLIC
        ${CMAKE_SOURCE_DIR}/STLPORT/stlport
    )
endif()

# Platform-specific linking
if(APPLE)
    target_link_libraries(CrySystem PRIVATE
        ${CORE_FOUNDATION_FRAMEWORK}
        ${FOUNDATION_FRAMEWORK}
        "-framework Security"
        "-framework SystemConfiguration"
    )
    
    # Set source files that need Objective-C++ compilation
    set_source_files_properties(MacOSFileSystem.cpp PROPERTIES
        COMPILE_FLAGS "-x objective-c++"
    )
    
elseif(WIN32)
    target_link_libraries(CrySystem PRIVATE
        user32 kernel32 advapi32 shell32 ole32 version winmm
    )
    
elseif(UNIX)
    target_link_libraries(CrySystem PRIVATE
        dl pthread m rt
    )
endif()

# Preprocessor definitions
target_compile_definitions(CrySystem PRIVATE
    CRYSYSTEM_EXPORTS=1
)

if(APPLE)
    target_compile_definitions(CrySystem PRIVATE
        __APPLE__=1
        __MACH__=1
    )
endif()

# Disable specific warnings for legacy code
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CrySystem PRIVATE
        -Wno-deprecated-declarations
        -Wno-unused-variable
        -Wno-unused-function
        -Wno-format-security
        -Wno-macro-redefined
    )
endif()

# Install target
install(TARGETS CrySystem
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
)
