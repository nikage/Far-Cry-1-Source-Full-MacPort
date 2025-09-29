# CryInput - Input system
cmake_minimum_required(VERSION 3.20)

# Find all source files
file(GLOB_RECURSE CRYINPUT_SOURCES
    "*.cpp"
    "*.c"
)

file(GLOB_RECURSE CRYINPUT_HEADERS
    "*.h"
)

# Add our macOS-specific files
if(APPLE)
    list(APPEND CRYINPUT_SOURCES
        MacOSInput.cpp
    )
    list(APPEND CRYINPUT_HEADERS
        MacOSInput.h
    )
endif()

# Create the CryInput library
add_library(CryInput SHARED ${CRYINPUT_SOURCES} ${CRYINPUT_HEADERS})

# Link CryCommon interface
target_link_libraries(CryInput PUBLIC CryCommon)

# Include directories
target_include_directories(CryInput PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

# Platform-specific linking
if(APPLE)
    target_link_libraries(CryInput PRIVATE
        ${CORE_FOUNDATION_FRAMEWORK}
        ${IOKIT_FRAMEWORK}
        "-framework Carbon"
        "-framework AppKit"
    )
    
    # Set source files that need Objective-C++ compilation
    set_source_files_properties(MacOSInput.cpp PROPERTIES
        COMPILE_FLAGS "-x objective-c++"
    )
    
elseif(WIN32)
    target_link_libraries(CryInput PRIVATE
        user32 dinput8 dxguid
    )
    
elseif(UNIX)
    target_link_libraries(CryInput PRIVATE
        X11 Xext
    )
endif()

# Preprocessor definitions
target_compile_definitions(CryInput PRIVATE
    CRYINPUT_EXPORTS=1
)

# Disable specific warnings
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CryInput PRIVATE
        -Wno-deprecated-declarations
        -Wno-unused-variable
        -Wno-unused-function
    )
endif()

# Install target
install(TARGETS CryInput
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
)
