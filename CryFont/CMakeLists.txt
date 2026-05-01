# CryFont - Font rendering system
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRYFONT_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRYFONT_HEADERS "*.h")

# Remove ALL bundled FreeType2 source files and use system FreeType instead
file(GLOB_RECURSE FREETYPE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/FreeType2/src/*.c")
list(REMOVE_ITEM CRYFONT_SOURCES ${FREETYPE_SOURCES})

add_library(CryFont SHARED ${CRYFONT_SOURCES} ${CRYFONT_HEADERS})

# Find and link system FreeType library
find_library(FREETYPE_LIBRARY freetype)
if(FREETYPE_LIBRARY)
    target_link_libraries(CryFont PUBLIC ${FREETYPE_LIBRARY})
    message(STATUS "Found FreeType library: ${FREETYPE_LIBRARY}")
else()
    message(FATAL_ERROR "FreeType library not found. Please install it with: brew install freetype")
endif()

target_link_libraries(CryFont PUBLIC CryCommon)

target_include_directories(CryFont PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/FreeType2/include
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

stage_dylib_to_bundle(CryFont)
