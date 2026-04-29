# RenderDll Common - Shared rendering components
cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE RENDER_COMMON_SOURCES "*.cpp" "*.c")
file(GLOB_RECURSE RENDER_COMMON_HEADERS "*.h")

# Exclude platform-specific files on macOS
if(APPLE)
    list(REMOVE_ITEM RENDER_COMMON_SOURCES 
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/FFT_SSE.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CREMotionBlur.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CREFlares.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CREFlashBang.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CREGlare.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CREHDRProcess.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CREOcLeaf.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CREOcean.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CREScreenProcess.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CRETempMesh.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CRETriMeshShadow.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CRE2DQuad.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CREClearStencil.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/RendElements/CREOcclusionQuery.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/SimpleFrameProfiler.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/Textures/Image/XtfImage.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/Textures/Image/TgaImage.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/Textures/Image/JpgImage.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/Textures/Image/JpgImage_XBox.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/Shaders/ShaderScript.cpp"
    )
endif()

# Create interface library for common rendering code
add_library(RenderCommon INTERFACE)

target_include_directories(RenderCommon INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/CryCommon
)

# Also create object library for shared code
if(RENDER_COMMON_SOURCES)
    add_library(RenderCommonObj OBJECT ${RENDER_COMMON_SOURCES} ${RENDER_COMMON_HEADERS})
    
    target_include_directories(RenderCommonObj PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/..
        ${CMAKE_SOURCE_DIR}/CryCommon
    )
    
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_compile_options(RenderCommonObj PRIVATE
            -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
        )
    endif()
    
    target_link_libraries(RenderCommon INTERFACE RenderCommonObj)
endif()
