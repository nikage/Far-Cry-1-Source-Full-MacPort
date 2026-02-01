# CryMovie - Movie/cinematics system
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CRYMOVIE_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE CRYMOVIE_HEADERS "*.h")

# Remove bundled Expat XML library files and use system Expat instead
list(REMOVE_ITEM CRYMOVIE_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/xml/Expat/xmlparse.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/xml/Expat/xmlrole.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/xml/Expat/xmltok.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/xml/Expat/xmltok_impl.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/xml/Expat/xmltok_ns.c"
)

# Include all source files - template conflicts resolved
# list(REMOVE_ITEM CRYMOVIE_SOURCES
#     "${CMAKE_CURRENT_SOURCE_DIR}/EntityNode.cpp"
#     "${CMAKE_CURRENT_SOURCE_DIR}/AnimNode.cpp"
#     "${CMAKE_CURRENT_SOURCE_DIR}/AnimCameraNode.cpp"
# )

add_library(CryMovie SHARED ${CRYMOVIE_SOURCES} ${CRYMOVIE_HEADERS})

# Find and link system Expat library
# Prefer homebrew expat .dylib over system .tbd files
set(EXPAT_LIBRARY "")
if(EXISTS "/Users/mykola/homebrew/opt/expat/lib/libexpat.dylib")
    set(EXPAT_LIBRARY "/Users/mykola/homebrew/opt/expat/lib/libexpat.dylib")
elseif(EXISTS "/Users/mykola/homebrew/lib/libexpat.dylib")
    set(EXPAT_LIBRARY "/Users/mykola/homebrew/lib/libexpat.dylib")
elseif(EXISTS "/opt/homebrew/opt/expat/lib/libexpat.dylib")
    set(EXPAT_LIBRARY "/opt/homebrew/opt/expat/lib/libexpat.dylib")
elseif(EXISTS "/opt/homebrew/lib/libexpat.dylib")
    set(EXPAT_LIBRARY "/opt/homebrew/lib/libexpat.dylib")
else()
    set(CMAKE_FIND_LIBRARY_SUFFIXES_BACKUP ${CMAKE_FIND_LIBRARY_SUFFIXES})
    set(CMAKE_FIND_LIBRARY_SUFFIXES ".dylib" ".a")
    find_library(EXPAT_LIBRARY 
        NAMES expat
        PATHS 
            /Users/mykola/homebrew/opt/expat/lib
            /Users/mykola/homebrew/lib
            /opt/homebrew/opt/expat/lib
            /opt/homebrew/lib
            /usr/local/lib
            /usr/lib
        NO_DEFAULT_PATH
    )
    if(NOT EXPAT_LIBRARY)
        find_library(EXPAT_LIBRARY expat)
    endif()
    set(CMAKE_FIND_LIBRARY_SUFFIXES ${CMAKE_FIND_LIBRARY_SUFFIXES_BACKUP})
endif()

if(EXPAT_LIBRARY)
    if(EXPAT_LIBRARY MATCHES "\\.tbd$")
        message(FATAL_ERROR "Found .tbd stub instead of real library: ${EXPAT_LIBRARY}. Please ensure homebrew expat is installed: brew install expat")
    endif()
    target_link_libraries(CryMovie PUBLIC ${EXPAT_LIBRARY})
    message(STATUS "Found Expat library: ${EXPAT_LIBRARY}")
else()
    message(FATAL_ERROR "Expat library not found. Please install it with: brew install expat")
endif()

target_link_libraries(CryMovie PUBLIC CryCommon CrySystem)

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
