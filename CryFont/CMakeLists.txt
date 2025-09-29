# CryFont - Font rendering system
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRYFONT_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRYFONT_HEADERS "*.h")

add_library(CryFont SHARED ${CRYFONT_SOURCES} ${CRYFONT_HEADERS})

target_link_libraries(CryFont PUBLIC CryCommon)

target_include_directories(CryFont PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(CryFont PRIVATE
    CRYFONT_EXPORTS=1
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CryFont PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS CryFont LIBRARY DESTINATION lib RUNTIME DESTINATION bin)
