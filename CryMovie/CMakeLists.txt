# CryMovie - Movie/cinematics system
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRYMOVIE_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRYMOVIE_HEADERS "*.h")

add_library(CryMovie SHARED ${CRYMOVIE_SOURCES} ${CRYMOVIE_HEADERS})

target_link_libraries(CryMovie PUBLIC CryCommon)

target_include_directories(CryMovie PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(CryMovie PRIVATE
    CRYMOVIE_EXPORTS=1
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CryMovie PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS CryMovie LIBRARY DESTINATION lib RUNTIME DESTINATION bin)
