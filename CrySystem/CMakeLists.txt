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

# Exclude Windows-specific non-essential files for macOS
if(APPLE)
    list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX ".*HTTPDownloader.*")
    list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX ".*DownloadManager.*")
    list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX ".*LuaDebugger.*")
    # Exclude bundled Expat XML library files and use system Expat instead
    list(REMOVE_ITEM CRYSYSTEM_SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/XML/Expat/xmlparse.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/XML/Expat/xmlrole.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/XML/Expat/xmltok.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/XML/Expat/xmltok_impl.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/XML/Expat/xmltok_ns.c"
    )
    list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX ".*getdxver.*")
    # Temporarily exclude MacOSFileSystem due to Carbon framework conflicts
    # TODO: Fix Foundation.h include conflict with GetCurrentThread
    list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX "MacOSFileSystem.cpp$")
endif()

if(NOT UNIX OR APPLE)
    list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX ".*Linux.*")
    list(FILTER CRYSYSTEM_HEADERS EXCLUDE REGEX ".*Linux.*")
endif()

# Add our macOS-specific files
# MacOSFileSystem.cpp temporarily disabled due to Carbon framework conflicts
if(APPLE)
    # Add macOS compatibility stubs
    list(APPEND CRYSYSTEM_SOURCES
        macos_stubs.cpp
        SystemMacOSEvents.mm
    )
    # list(APPEND CRYSYSTEM_SOURCES
    #     MacOSFileSystem.cpp
    # )
    # list(APPEND CRYSYSTEM_HEADERS
    #     MacOSFileSystem.h
    # )
endif()

# Create the CrySystem library
add_library(CrySystem SHARED ${CRYSYSTEM_SOURCES} ${CRYSYSTEM_HEADERS})

# Link CryCommon interface
target_link_libraries(CrySystem PUBLIC CryCommon)

# Find and link system Expat library
find_library(EXPAT_LIBRARY expat)
find_path(EXPAT_INCLUDE_DIR expat.h
    PATHS
        /usr/include
        /usr/local/include
        /opt/homebrew/include
    PATH_SUFFIXES
        expat
)
if(EXPAT_LIBRARY)
    target_link_libraries(CrySystem PUBLIC ${EXPAT_LIBRARY})
    message(STATUS "Found Expat library: ${EXPAT_LIBRARY}")
    if(EXPAT_INCLUDE_DIR)
        target_include_directories(CrySystem PUBLIC ${EXPAT_INCLUDE_DIR})
        message(STATUS "Found Expat headers: ${EXPAT_INCLUDE_DIR}")
    else()
        message(STATUS "Expat headers not explicitly found, using system defaults")
    endif()
else()
    message(FATAL_ERROR "Expat library not found. Please install it with: brew install expat")
endif()

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
    # On macOS, CrySystem directly calls CreateGameInstance() and CreateScriptSystem()
    # instead of dynamic loading, so we need to link these libraries
    target_link_libraries(CrySystem PRIVATE
        CryGame
        CryScriptSystem
        CryFont  # Link CryFont for static CreateCryFontInterface call
        ${CORE_FOUNDATION_FRAMEWORK}
        ${FOUNDATION_FRAMEWORK}
        "-framework Cocoa"
        "-framework Security"
        "-framework SystemConfiguration"
    )
    
    # Set source files that need Objective-C++ compilation
    # set_source_files_properties(MacOSFileSystem.cpp PROPERTIES
    #     COMPILE_FLAGS "-x objective-c++"
    # )
    
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
    NOT_USE_CRY_MEMORY_MANAGER=1
)

# For macOS, use forced include of clean headers to bypass legacy issues
if(APPLE)
    target_compile_options(CrySystem PRIVATE
        -include ${CMAKE_SOURCE_DIR}/CryCommon/platform_macos.h
    )
endif()

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
