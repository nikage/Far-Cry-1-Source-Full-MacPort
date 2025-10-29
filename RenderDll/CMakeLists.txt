# RenderDll - Graphics rendering system
cmake_minimum_required(VERSION 3.20)

# Platform-specific renderer selection
if(APPLE)
    message(STATUS "Building Metal renderer for macOS")
    add_subdirectory(XRenderMetal)
    
    # NULL renderer disabled - too many dependencies
    # add_subdirectory(XRenderNULL)
    
elseif(WIN32)
    message(STATUS "Building DirectX renderers for Windows")
    add_subdirectory(XRenderD3D9)
    add_subdirectory(XRenderNULL)
    
    # OpenGL renderer (if available)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/XRenderOGL")
        add_subdirectory(XRenderOGL)
    endif()
    
elseif(UNIX)
    message(STATUS "Building OpenGL renderer for Linux")
    
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/XRenderOGL")
        add_subdirectory(XRenderOGL)
    endif()
    
    add_subdirectory(XRenderNULL)
endif()

# Common render dll components (needed by Metal renderer)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/Common")
    add_subdirectory(Common)
endif()
