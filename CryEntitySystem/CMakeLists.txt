# CryEntitySystem - Entity management
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRYENTITY_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRYENTITY_HEADERS "*.h")

add_library(CryEntitySystem SHARED ${CRYENTITY_SOURCES} ${CRYENTITY_HEADERS})

target_link_libraries(CryEntitySystem PUBLIC CryCommon)

target_include_directories(CryEntitySystem PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(CryEntitySystem PRIVATE
    CRYENTITYSYSTEM_EXPORTS=1
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CryEntitySystem PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS CryEntitySystem LIBRARY DESTINATION lib RUNTIME DESTINATION bin)

stage_dylib_to_bundle(CryEntitySystem)
