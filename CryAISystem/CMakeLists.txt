# CryAISystem - AI system
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRYAI_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRYAI_HEADERS "*.h")

add_library(CryAISystem SHARED ${CRYAI_SOURCES} ${CRYAI_HEADERS})

target_link_libraries(CryAISystem PUBLIC CryCommon)

target_include_directories(CryAISystem PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(CryAISystem PRIVATE
    CRYAISYSTEM_EXPORTS=1
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(CryAISystem PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS CryAISystem LIBRARY DESTINATION lib RUNTIME DESTINATION bin)

stage_dylib_to_bundle(CryAISystem)
