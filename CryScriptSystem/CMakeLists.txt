# CryScriptSystem - Lua scripting
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRYSCRIPT_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRYSCRIPT_HEADERS "*.h")

add_library(CryScriptSystem SHARED ${CRYSCRIPT_SOURCES} ${CRYSCRIPT_HEADERS})

target_link_libraries(CryScriptSystem PUBLIC CryCommon)

target_include_directories(CryScriptSystem PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/LUA
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(CryScriptSystem PRIVATE
    CRYSCRIPTSYSTEM_EXPORTS=1
    DONT_USE_CRY_MEMORY_MANAGER=1
)

# Fix Microsoft-specific keywords for cross-platform compatibility
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_definitions(CryScriptSystem PRIVATE
        __forceinline=inline
    )
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CryScriptSystem PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS CryScriptSystem LIBRARY DESTINATION lib RUNTIME DESTINATION bin)

stage_dylib_to_bundle(CryScriptSystem)
