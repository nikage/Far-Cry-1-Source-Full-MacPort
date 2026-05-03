# CrySystem - Core engine system
cmake_minimum_required(VERSION 3.20)

# Find all source files
file(GLOB_RECURSE CRYSYSTEM_SOURCES
    "*.cpp"
    "*.c"
)
list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX ".*/test/.*")

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
    # MacOSFileSystem.cpp is compiled as Objective-C++ (see set_source_files_properties below).
    # The GetCurrentThread name conflict with Carbon is resolved in MacOSspecific.h via
    # the __OBJC__ guard; Foundation.h does not transitively include Carbon on modern SDKs.
    # Exclude legacy zlib 1.1.x sources that have been superseded by their
    # zlib 1.2.x replacements already present in the same directory:
    #   gzio.c      → gzclose.c + gzlib.c + gzread.c + gzwrite.c
    #   infblock.c  \
    #   infcodes.c   } → inflate.c (unified in zlib 1.2)
    #   infutil.c   /
    #   infback.c   → now a standalone optional module; conflicts with new inflate
    list(REMOVE_ITEM CRYSYSTEM_SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/zlib/gzio.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/zlib/infblock.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/zlib/infcodes.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/zlib/infutil.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/zlib/infback.c"
    )
endif()

if(NOT UNIX OR APPLE)
    list(FILTER CRYSYSTEM_SOURCES EXCLUDE REGEX ".*Linux.*")
    list(FILTER CRYSYSTEM_HEADERS EXCLUDE REGEX ".*Linux.*")
endif()

# Add our macOS-specific files
if(APPLE)
    # Add macOS compatibility stubs
    list(APPEND CRYSYSTEM_SOURCES
        macos_stubs.cpp
        SystemMacOSEvents.mm
    )
endif()

# Create the CrySystem library
add_library(CrySystem SHARED ${CRYSYSTEM_SOURCES} ${CRYSYSTEM_HEADERS})

# Link CryCommon interface
target_link_libraries(CrySystem PUBLIC CryCommon)

# Find and link system Expat library
# Prefer homebrew expat .dylib over system .tbd files
set(EXPAT_LIBRARY "")
set(EXPAT_INCLUDE_DIR "")

# Try homebrew first - check if file exists
if(EXISTS "/Users/mykola/homebrew/opt/expat/lib/libexpat.dylib")
    set(EXPAT_LIBRARY "/Users/mykola/homebrew/opt/expat/lib/libexpat.dylib")
    if(EXISTS "/Users/mykola/homebrew/opt/expat/include/expat.h")
        set(EXPAT_INCLUDE_DIR "/Users/mykola/homebrew/opt/expat/include")
    endif()
elseif(EXISTS "/Users/mykola/homebrew/lib/libexpat.dylib")
    set(EXPAT_LIBRARY "/Users/mykola/homebrew/lib/libexpat.dylib")
    if(EXISTS "/Users/mykola/homebrew/include/expat.h")
        set(EXPAT_INCLUDE_DIR "/Users/mykola/homebrew/include")
    endif()
elseif(EXISTS "/opt/homebrew/opt/expat/lib/libexpat.dylib")
    set(EXPAT_LIBRARY "/opt/homebrew/opt/expat/lib/libexpat.dylib")
    if(EXISTS "/opt/homebrew/opt/expat/include/expat.h")
        set(EXPAT_INCLUDE_DIR "/opt/homebrew/opt/expat/include")
    endif()
elseif(EXISTS "/opt/homebrew/lib/libexpat.dylib")
    set(EXPAT_LIBRARY "/opt/homebrew/lib/libexpat.dylib")
    if(EXISTS "/opt/homebrew/include/expat.h")
        set(EXPAT_INCLUDE_DIR "/opt/homebrew/include")
    endif()
endif()

# If not found via direct path, try find_library but exclude .tbd files
if(NOT EXPAT_LIBRARY)
    set(CMAKE_FIND_LIBRARY_SUFFIXES_BACKUP ${CMAKE_FIND_LIBRARY_SUFFIXES})
    set(CMAKE_FIND_LIBRARY_SUFFIXES ".dylib" ".a")
    find_library(EXPAT_LIBRARY 
        NAMES expat
        PATHS 
            /Users/mykola/homebrew/opt/expat/lib
            /Users/mykola/homebrew/lib
            /opt/homebrew/opt/expat/lib
            /opt/homebrew/lib
            /usr/local/lib
            /usr/lib
        NO_DEFAULT_PATH
    )
    if(NOT EXPAT_LIBRARY)
        find_library(EXPAT_LIBRARY expat)
    endif()
    set(CMAKE_FIND_LIBRARY_SUFFIXES ${CMAKE_FIND_LIBRARY_SUFFIXES_BACKUP})
    
    if(NOT EXPAT_INCLUDE_DIR)
        find_path(EXPAT_INCLUDE_DIR expat.h
            PATHS
                /Users/mykola/homebrew/opt/expat/include
                /Users/mykola/homebrew/include
                /opt/homebrew/opt/expat/include
                /opt/homebrew/include
                /usr/include
                /usr/local/include
            PATH_SUFFIXES
                expat
        )
    endif()
endif()

if(EXPAT_LIBRARY)
    if(EXPAT_LIBRARY MATCHES "\\.tbd$")
        message(FATAL_ERROR "Found .tbd stub instead of real library: ${EXPAT_LIBRARY}. Please ensure homebrew expat is installed: brew install expat")
    endif()
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
    
    # MacOSFileSystem.cpp uses Objective-C APIs (NSBundle, NSSearchPath*) so it must be
    # compiled as Objective-C++.  The glob already includes it; this flag enables ObjC++.
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

stage_dylib_to_bundle(CrySystem)

# --- Standalone unit-test executables ---
function(add_crysystem_test TARGET_NAME SOURCE_FILE)
    add_executable(${TARGET_NAME} ${SOURCE_FILE})
    target_compile_options(${TARGET_NAME} PRIVATE
        -include ${CMAKE_SOURCE_DIR}/CryCommon/platform_macos.h
        -Wno-deprecated-declarations -Wno-unused-variable
        -Wno-unused-function -Wno-format-security -Wno-reorder
        -Wno-macro-redefined
    )
    target_include_directories(${TARGET_NAME} PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/CryCommon
    )
    target_compile_definitions(${TARGET_NAME} PRIVATE
        NOT_USE_CRY_MEMORY_MANAGER=1
    )
    add_test(NAME ${TARGET_NAME} COMMAND ${TARGET_NAME})
endfunction()

add_crysystem_test(null_network_tests        test/NullNetworkTests.cpp)
add_crysystem_test(asset_validator_tests     test/AssetValidatorTests.cpp)
add_crysystem_test(macos_findclose_tests     test/MacOSFindCloseTests.cpp)
