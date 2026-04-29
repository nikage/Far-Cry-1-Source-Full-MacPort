# XRenderOGL - OpenGL renderer for macOS
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE XRENDEROGL_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE XRENDEROGL_HEADERS "*.h")

add_library(XRenderOGL SHARED ${XRENDEROGL_SOURCES} ${XRENDEROGL_HEADERS})

target_link_libraries(XRenderOGL PRIVATE CryCommon)

target_include_directories(XRenderOGL PRIVATE
    ${CMAKE_SOURCE_DIR}/RenderDll/Common
    ${CMAKE_SOURCE_DIR}/RenderDll
    ${CMAKE_SOURCE_DIR}/CryCommon
)

target_compile_definitions(XRenderOGL PRIVATE
    XRENDEROGL_EXPORTS=1
)

# macOS-specific OpenGL setup
if(APPLE)
    find_library(OPENGL_LIBRARY OpenGL REQUIRED)
    find_library(GLUT_LIBRARY GLUT REQUIRED)
    target_link_libraries(XRenderOGL PRIVATE ${OPENGL_LIBRARY} ${GLUT_LIBRARY})
    
    # Add OpenGL framework
    target_link_libraries(XRenderOGL PRIVATE "-framework OpenGL")
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(XRenderOGL PRIVATE
        -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
    )
endif()

install(TARGETS XRenderOGL LIBRARY DESTINATION lib RUNTIME DESTINATION bin)
