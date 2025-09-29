# Cry3DEngine - 3D rendering engine
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRY3DENGINE_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRY3DENGINE_HEADERS "*.h")

add_library(Cry3DEngine SHARED ${CRY3DENGINE_SOURCES} ${CRY3DENGINE_HEADERS})

target_link_libraries(Cry3DEngine PUBLIC CryCommon)

target_include_directories(Cry3DEngine PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(Cry3DEngine PRIVATE
    CRY3DENGINE_EXPORTS=1
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(Cry3DEngine PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS Cry3DEngine LIBRARY DESTINATION lib RUNTIME DESTINATION bin)
