cmake_minimum_required(VERSION 3.15)
project(TextureUploadExample)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")

find_library(METAL_LIBRARY Metal REQUIRED)
find_library(METALKIT_LIBRARY MetalKit REQUIRED)
find_library(FOUNDATION_LIBRARY Foundation REQUIRED)
find_library(APPKIT_LIBRARY AppKit REQUIRED)

add_executable(texture_upload_example
    texture_upload_example.mm
)

add_executable(test_load_texture
    test_load_texture.mm
)

add_executable(itexpic_interface_example
    itexpic_interface_example.mm
)

add_executable(texture_flags_example
    texture_flags_example.mm
)

add_executable(test_cubemap_scan
    test_cubemap_scan.mm
)

target_link_libraries(texture_upload_example
    ${METAL_LIBRARY}
    ${FOUNDATION_LIBRARY}
)

target_link_libraries(test_load_texture
    ${METAL_LIBRARY}
    ${METALKIT_LIBRARY}
    ${FOUNDATION_LIBRARY}
    ${APPKIT_LIBRARY}
)

target_compile_options(texture_upload_example PRIVATE
    -Wall
    -Wno-deprecated-declarations
    -fobjc-arc
)

target_link_libraries(itexpic_interface_example
    ${METAL_LIBRARY}
    ${METALKIT_LIBRARY}
    ${FOUNDATION_LIBRARY}
    ${APPKIT_LIBRARY}
)

target_compile_options(test_load_texture PRIVATE
    -Wall
    -Wno-deprecated-declarations
    -fobjc-arc
)

target_link_libraries(texture_flags_example
    ${METAL_LIBRARY}
    ${METALKIT_LIBRARY}
    ${FOUNDATION_LIBRARY}
    ${APPKIT_LIBRARY}
)

target_compile_options(itexpic_interface_example PRIVATE
    -Wall
    -Wno-deprecated-declarations
    -fobjc-arc
)

target_link_libraries(test_cubemap_scan
    ${METAL_LIBRARY}
    ${METALKIT_LIBRARY}
    ${FOUNDATION_LIBRARY}
    ${APPKIT_LIBRARY}
)

target_compile_options(texture_flags_example PRIVATE
    -Wall
    -Wno-deprecated-declarations
    -fobjc-arc
)

target_compile_options(test_cubemap_scan PRIVATE
    -Wall
    -Wno-deprecated-declarations
    -fobjc-arc
)

set_target_properties(texture_upload_example PROPERTIES
    LINKER_LANGUAGE CXX
)

set_target_properties(test_load_texture PROPERTIES
    LINKER_LANGUAGE CXX
)

set_target_properties(itexpic_interface_example PROPERTIES
    LINKER_LANGUAGE CXX
)

set_target_properties(texture_flags_example PROPERTIES
    LINKER_LANGUAGE CXX
)

set_target_properties(test_cubemap_scan PROPERTIES
    LINKER_LANGUAGE CXX
)

message(STATUS "═══════════════════════════════════════════════════")
message(STATUS "  Texture Upload Example Configuration")
message(STATUS "═══════════════════════════════════════════════════")
message(STATUS "  Metal Library: ${METAL_LIBRARY}")
message(STATUS "  MetalKit Library: ${METALKIT_LIBRARY}")
message(STATUS "  Foundation Library: ${FOUNDATION_LIBRARY}")
message(STATUS "  AppKit Library: ${APPKIT_LIBRARY}")
message(STATUS "  Build Type: Example/Demo")
message(STATUS "═══════════════════════════════════════════════════")

