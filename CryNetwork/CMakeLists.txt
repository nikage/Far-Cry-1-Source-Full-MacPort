# CryNetwork - Networking system
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRYNETWORK_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRYNETWORK_HEADERS "*.h")

# Add our macOS-specific files
if(APPLE)
    list(APPEND CRYNETWORK_HEADERS MacOSNetwork.h)
endif()

add_library(CryNetwork SHARED ${CRYNETWORK_SOURCES} ${CRYNETWORK_HEADERS})

target_link_libraries(CryNetwork PUBLIC CryCommon)

target_include_directories(CryNetwork PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(CryNetwork PRIVATE
    CRYNETWORK_EXPORTS=1
)
if(APPLE)
    target_compile_definitions(CryNetwork PRIVATE NOT_USE_ASE_SDK=1)
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CryNetwork PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS CryNetwork LIBRARY DESTINATION lib RUNTIME DESTINATION bin)

stage_dylib_to_bundle(CryNetwork)
