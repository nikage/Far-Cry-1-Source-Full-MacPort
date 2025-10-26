cmake_minimum_required(VERSION 3.15)
project(TextureUploadExample)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")

find_library(METAL_LIBRARY Metal REQUIRED)
find_library(FOUNDATION_LIBRARY Foundation REQUIRED)

add_executable(texture_upload_example
    texture_upload_example.mm
)

target_link_libraries(texture_upload_example
    ${METAL_LIBRARY}
    ${FOUNDATION_LIBRARY}
)

target_compile_options(texture_upload_example PRIVATE
    -Wall
    -Wno-deprecated-declarations
    -fobjc-arc
)

set_target_properties(texture_upload_example PROPERTIES
    LINKER_LANGUAGE CXX
)

message(STATUS "═══════════════════════════════════════════════════")
message(STATUS "  Texture Upload Example Configuration")
message(STATUS "═══════════════════════════════════════════════════")
message(STATUS "  Metal Library: ${METAL_LIBRARY}")
message(STATUS "  Foundation Library: ${FOUNDATION_LIBRARY}")
message(STATUS "  Build Type: Example/Demo")
message(STATUS "═══════════════════════════════════════════════════")

