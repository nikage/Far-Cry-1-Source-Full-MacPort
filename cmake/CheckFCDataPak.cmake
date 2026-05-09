# Build-time assertion: verify a required FCData PAK file exists.
# Invoked via: cmake -P CheckFCDataPak.cmake with CMAKE_PAK_PATH set in env.
#
# Usage (from CMakeLists.txt add_custom_command):
#   COMMAND ${CMAKE_COMMAND} -E env CMAKE_PAK_PATH=<path> ${CMAKE_COMMAND} -P cmake/CheckFCDataPak.cmake

set(PAK_PATH "$ENV{CMAKE_PAK_PATH}")

if(NOT PAK_PATH)
    message(FATAL_ERROR "CheckFCDataPak.cmake: CMAKE_PAK_PATH environment variable is not set.")
endif()

if(NOT EXISTS "${PAK_PATH}")
    get_filename_component(PAK_NAME "${PAK_PATH}" NAME)
    get_filename_component(PAK_DIR  "${PAK_PATH}" DIRECTORY)
    message(FATAL_ERROR
        "\n"
        "=== Missing required FCData PAK: ${PAK_NAME} ===\n"
        "Expected at: ${PAK_PATH}\n"
        "\n"
        "Copy it from your Far Cry installation into ${PAK_DIR}/\n"
        "\n"
        "Steam (via CrossOver) source path:\n"
        "  $ENV{HOME}/Library/Application Support/CrossOver/Bottles/Steam-2"
        "/drive_c/Program Files (x86)/Steam/steamapps/common/FarCry/FCData/${PAK_NAME}\n"
        "\n"
        "Symlink alternative (avoids copying large files):\n"
        "  ln -s \"<FarCry_install>/FCData/${PAK_NAME}\" \"${PAK_PATH}\"\n"
        "=================================================")
endif()
