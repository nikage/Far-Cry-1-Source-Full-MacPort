# CryGame - Game logic
cmake_minimum_required(VERSION 3.20)

# Find all source files
file(GLOB_RECURSE CRYGAME_SOURCES
    "*.cpp"
    "*.c"
)

file(GLOB_RECURSE CRYGAME_HEADERS
    "*.h"
)

if(APPLE)
    file(GLOB_RECURSE CRYGAME_OBJC_SOURCES
        "*.mm"
    )
    list(APPEND CRYGAME_SOURCES ${CRYGAME_OBJC_SOURCES})
endif()

# Create the CryGame library
add_library(CryGame SHARED ${CRYGAME_SOURCES} ${CRYGAME_HEADERS})

# Link CryCommon interface
target_link_libraries(CryGame PUBLIC CryCommon)

# Include directories
target_include_directories(CryGame PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
    ${CMAKE_SOURCE_DIR}/CrySystem
    ${CMAKE_SOURCE_DIR}/CryEntitySystem
    ${CMAKE_SOURCE_DIR}/CryPhysics
)

# Preprocessor definitions
target_compile_definitions(CryGame PRIVATE
    CRYGAME_EXPORTS=1
    NOT_USE_CRY_MEMORY_MANAGER=1
)

# For macOS, use forced include of clean headers to bypass legacy issues
if(APPLE)
    target_compile_options(CryGame PRIVATE
        -include ${CMAKE_SOURCE_DIR}/CryCommon/platform_macos.h
    )
    target_link_libraries(CryGame PRIVATE
        "-framework AVFoundation"
        "-framework CoreMedia"
        "-framework CoreVideo"
        "-framework QuartzCore"
        "-framework Foundation"
        "-framework CoreFoundation"
    )
endif()

# Disable specific warnings for legacy code
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CryGame PRIVATE
        -Wno-deprecated-declarations
        -Wno-unused-variable
        -Wno-unused-function
        -Wno-format-security
        -Wno-reorder
    )
endif()

# Install target
install(TARGETS CryGame
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
)
