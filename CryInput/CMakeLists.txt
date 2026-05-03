# CryInput - Input system
cmake_minimum_required(VERSION 3.20)

# Find all source files
file(GLOB_RECURSE CRYINPUT_SOURCES
    "*.cpp"
    "*.c"
)
list(FILTER CRYINPUT_SOURCES EXCLUDE REGEX ".*/test/.*")

# Remove Xbox-specific files for non-Xbox platforms
if(NOT _XBOX)
    list(REMOVE_ITEM CRYINPUT_SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/XGamepad.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/XDebugKeyboard.cpp"
    )
endif()

# Remove Windows-specific files for macOS
if(APPLE)
    list(REMOVE_ITEM CRYINPUT_SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/XKeyboard.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/XMouse.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/Joystick.cpp"
    )
endif()

file(GLOB_RECURSE CRYINPUT_HEADERS
    "*.h"
)

# Add our macOS-specific files
if(APPLE)
    list(APPEND CRYINPUT_SOURCES
        MacOSInput.cpp
        MacOSMouseHelper.mm
        JoystickMacOS.cpp
        XKeyboardMacOS.cpp
        XMouseMacOS.cpp
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
    NOT_USE_CRY_MEMORY_MANAGER=1
)

# For macOS, use forced include of clean headers to bypass legacy issues
if(APPLE)
    target_compile_options(CryInput PRIVATE
        -include ${CMAKE_SOURCE_DIR}/CryCommon/platform_macos.h
        -D_PLATFORM_H_=1  # Prevent original platform.h from being included
    )
    target_compile_definitions(CryInput PRIVATE
        _PLATFORM_H_=1  # Prevent original platform.h from being included
    )
endif()

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

stage_dylib_to_bundle(CryInput)

# --- Standalone unit-test executables ---
if(APPLE)
    function(add_cryinput_test TARGET_NAME SOURCE_FILE)
        add_executable(${TARGET_NAME} ${SOURCE_FILE})
        target_compile_options(${TARGET_NAME} PRIVATE
            -std=c++17
            -Wno-deprecated-declarations -Wno-unused-variable
            -Wno-unused-function -Wno-macro-redefined
        )
        target_include_directories(${TARGET_NAME} PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${CMAKE_SOURCE_DIR}/CryCommon
        )
        add_test(NAME ${TARGET_NAME} COMMAND ${TARGET_NAME})
    endfunction()

    add_cryinput_test(macos_mouse_input_tests  test/MacOSMouseInputTests.cpp)
    add_cryinput_test(macos_keyboard_input_tests test/MacOSKeyboardInputTests.cpp)
endif()
