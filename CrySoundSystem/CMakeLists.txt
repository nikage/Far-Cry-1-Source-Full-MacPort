# CrySoundSystem - Audio system
cmake_minimum_required(VERSION 3.20)

# Find all source files
file(GLOB_RECURSE CRYSOUND_SOURCES
    "*.cpp"
    "*.c"
)

file(GLOB_RECURSE CRYSOUND_HEADERS
    "*.h"
)

# Add our macOS-specific files
if(APPLE)
    list(APPEND CRYSOUND_SOURCES
        MacOSSound.cpp
    )
    list(APPEND CRYSOUND_HEADERS
        MacOSSound.h
    )
endif()

# Create the CrySoundSystem library
add_library(CrySoundSystem SHARED ${CRYSOUND_SOURCES} ${CRYSOUND_HEADERS})

# Link CryCommon interface
target_link_libraries(CrySoundSystem PUBLIC CryCommon)

# Include directories
target_include_directories(CrySoundSystem PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

# Platform-specific linking
if(APPLE)
    # Find Vorbis library
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(VORBIS REQUIRED vorbisfile)
    
    target_link_libraries(CrySoundSystem PRIVATE
        ${CORE_AUDIO_FRAMEWORK}
        ${AUDIO_TOOLBOX_FRAMEWORK}
        "-framework AVFoundation"
        "-framework AudioUnit"
        ${VORBIS_LIBRARIES}
    )
    
    target_include_directories(CrySoundSystem PRIVATE ${VORBIS_INCLUDE_DIRS})
    target_compile_definitions(CrySoundSystem PRIVATE ${VORBIS_CFLAGS_OTHER})
    
    # Set source files that need Objective-C++ compilation
    set_source_files_properties(MacOSSound.cpp PROPERTIES
        COMPILE_FLAGS "-x objective-c++"
    )
    
elseif(WIN32)
    target_link_libraries(CrySoundSystem PRIVATE
        dsound winmm
    )
    
elseif(UNIX)
    target_link_libraries(CrySoundSystem PRIVATE
        asound pulse
    )
endif()

# Preprocessor definitions
target_compile_definitions(CrySoundSystem PRIVATE
    CRYSOUNDSYSTEM_EXPORTS=1
)

# Disable specific warnings
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CrySoundSystem PRIVATE
        -Wno-deprecated-declarations
        -Wno-unused-variable
        -Wno-unused-function
    )
endif()

# Install target
install(TARGETS CrySoundSystem
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
)
