# CryPhysics - Physics system
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRYPHYSICS_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRYPHYSICS_HEADERS "*.h")

add_library(CryPhysics SHARED ${CRYPHYSICS_SOURCES} ${CRYPHYSICS_HEADERS})

target_link_libraries(CryPhysics PUBLIC CryCommon)

target_include_directories(CryPhysics PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(CryPhysics PRIVATE
    CRYPHYSICS_EXPORTS=1
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CryPhysics PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS CryPhysics LIBRARY DESTINATION lib RUNTIME DESTINATION bin)

stage_dylib_to_bundle(CryPhysics)
