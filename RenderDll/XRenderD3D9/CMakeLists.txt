if(NOT WIN32)
    return()
endif()

find_program(DART_EXECUTABLE dart)
if(NOT DART_EXECUTABLE)
    message(WARNING "Dart executable not found; skipping canonical HLSL generation")
    return()
endif()

set(SHADER_ROOT ${PROJECT_SOURCE_DIR})
set(SHADER_GENERATOR ${SHADER_ROOT}/tools/shader_port/lib/hlsl_generator.dart)
set(SHADER_PARSER ${SHADER_ROOT}/tools/shader_port/lib/parser.dart)
set(SHADER_OUTPUT_DIR ${CMAKE_BINARY_DIR}/shader_port)
set(SHADER_STAMP ${SHADER_OUTPUT_DIR}/generated_hlsl.stamp)

add_custom_command(
    OUTPUT ${SHADER_STAMP}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${SHADER_OUTPUT_DIR}
    COMMAND ${DART_EXECUTABLE} ${SHADER_PARSER} ${SHADER_ROOT}
    COMMAND ${DART_EXECUTABLE} ${SHADER_GENERATOR} ${SHADER_ROOT}
    COMMAND ${CMAKE_COMMAND} -E touch ${SHADER_STAMP}
    DEPENDS ${SHADER_GENERATOR} ${SHADER_PARSER}
    WORKING_DIRECTORY ${SHADER_ROOT}
    COMMENT "Generating canonical HLSL shaders"
    VERBATIM
)

add_custom_target(GenerateCanonicalHLSL ALL DEPENDS ${SHADER_STAMP})

find_program(DXC_EXECUTABLE dxc)
if(DXC_EXECUTABLE)
    file(GLOB_RECURSE CONFIGURE_DEPENDS GENERATED_HLSL_FILES "${SHADER_ROOT}/tools/shader_port/output/hlsl/*.hlsl")
    set(DXIL_TARGETS)
    foreach(HLSL_FILE ${GENERATED_HLSL_FILES})
        file(RELATIVE_PATH HLSL_RELATIVE "${SHADER_ROOT}/tools/shader_port/output/hlsl" ${HLSL_FILE})
        string(REPLACE "/" "_" HLSL_STEM ${HLSL_RELATIVE})
        set(DXIL_OUTPUT ${SHADER_OUTPUT_DIR}/dxil/${HLSL_STEM}.dxil)
        add_custom_command(
            OUTPUT ${DXIL_OUTPUT}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${SHADER_OUTPUT_DIR}/dxil
            COMMAND ${DXC_EXECUTABLE} -T ps_5_0 -E GeneratedMain -Fo ${DXIL_OUTPUT} ${HLSL_FILE}
            DEPENDS ${HLSL_FILE} ${SHADER_STAMP}
            VERBATIM
        )
        list(APPEND DXIL_TARGETS ${DXIL_OUTPUT})
    endforeach()
    if(DXIL_TARGETS)
        add_custom_target(ValidateCanonicalHLSL ALL DEPENDS ${DXIL_TARGETS})
        add_dependencies(ValidateCanonicalHLSL GenerateCanonicalHLSL)
    endif()
endif()
