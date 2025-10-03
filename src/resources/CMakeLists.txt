# Embedded Resources for FarCry Mac Silicon
cmake_minimum_required(VERSION 3.20)

# Add embedded resources source files
set(RESOURCES_SOURCES
    EmbeddedResources.cpp
    EmbeddedResources.h
)

# Create resources library
add_library(EmbeddedResources STATIC ${RESOURCES_SOURCES})

# Set include directories
target_include_directories(EmbeddedResources PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

# Link with CryCommon
target_link_libraries(EmbeddedResources PUBLIC CryCommon)

# Set compile definitions
target_compile_definitions(EmbeddedResources PRIVATE
    EMBEDDED_RESOURCES=1
)

# Set compile options for debug builds
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(EmbeddedResources PRIVATE
        -g -O0 -DDEBUG
    )
endif()

# Install the library
install(TARGETS EmbeddedResources LIBRARY DESTINATION lib RUNTIME DESTINATION bin)
