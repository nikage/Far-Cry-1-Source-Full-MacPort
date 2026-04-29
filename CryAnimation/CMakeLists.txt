# CryAnimation - Animation system
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRYANIMATION_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRYANIMATION_HEADERS "*.h")

add_library(CryAnimation SHARED ${CRYANIMATION_SOURCES} ${CRYANIMATION_HEADERS})

target_link_libraries(CryAnimation PUBLIC CryCommon)

target_include_directories(CryAnimation PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(CryAnimation PRIVATE
    CRYANIMATION_EXPORTS=1
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CryAnimation PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS CryAnimation LIBRARY DESTINATION lib RUNTIME DESTINATION bin)
