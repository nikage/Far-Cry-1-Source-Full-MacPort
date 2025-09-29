# XRenderNULL - Null renderer for testing
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE XRENDERNULL_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE XRENDERNULL_HEADERS "*.h")

add_library(XRenderNULL SHARED ${XRENDERNULL_SOURCES} ${XRENDERNULL_HEADERS})

target_link_libraries(XRenderNULL PRIVATE CryCommon)

target_include_directories(XRenderNULL PRIVATE
    ${CMAKE_SOURCE_DIR}/RenderDll/Common
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(XRenderNULL PRIVATE
    XRENDERNULL_EXPORTS=1
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(XRenderNULL PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS XRenderNULL LIBRARY DESTINATION lib RUNTIME DESTINATION bin)
