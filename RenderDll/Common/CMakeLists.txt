# RenderDll Common - Shared rendering components
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE RENDER_COMMON_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE RENDER_COMMON_HEADERS "*.h")

# Create interface library for common rendering code
add_library(RenderCommon INTERFACE)

target_include_directories(RenderCommon INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

# Also create object library for shared code
if(RENDER_COMMON_SOURCES)
    add_library(RenderCommonObj OBJECT ${RENDER_COMMON_SOURCES} ${RENDER_COMMON_HEADERS})
    
    target_include_directories(RenderCommonObj PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/..
        ${CMAKE_SOURCE_DIR}/CryCommon
    )
    
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_compile_options(RenderCommonObj PRIVATE
            -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
        )
    endif()
    
    target_link_libraries(RenderCommon INTERFACE RenderCommonObj)
endif()
