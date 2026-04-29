# FarCry Main Executable
cmake_minimum_required(VERSION 3.20)

# Source files for FarCry executable
set(FARCRY_SOURCES
    Main.cpp
)

# Platform-specific resources
if(WIN32)
    set(FARCRY_SOURCES ${FARCRY_SOURCES}
        FarCry.rc
        resource.h
    )
endif()

# Create the main executable
add_executable(FarCry ${FARCRY_SOURCES})

# Link required libraries
target_link_libraries(FarCry PRIVATE
    CryCommon
    CrySystem
    CryGame
    Cry3DEngine
    CryAnimation
    CryAISystem
    CryEntitySystem
    CryFont
    CryInput
    CryMovie
    CryNetwork
    CryPhysics
    CryScriptSystem
    CrySoundSystem
)

# Platform-specific linking
if(APPLE)
    # macOS frameworks
    target_link_libraries(FarCry PRIVATE
        ${COCOA_FRAMEWORK}
        ${OPENGL_FRAMEWORK}
        ${CORE_AUDIO_FRAMEWORK}
        ${AUDIO_TOOLBOX_FRAMEWORK}
        ${IOKIT_FRAMEWORK}
        ${CORE_FOUNDATION_FRAMEWORK}
        "-framework Metal"
        "-framework MetalKit"
        "-framework QuartzCore"
        "-framework Carbon"
    )
    
    # Set as macOS app bundle
    set_target_properties(FarCry PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME "Far Cry"
        MACOSX_BUNDLE_BUNDLE_VERSION ${CMAKE_PROJECT_VERSION}
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${CMAKE_PROJECT_VERSION}
        MACOSX_BUNDLE_IDENTIFIER "com.crytek.farcry"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    )
    
elseif(WIN32)
    # Windows libraries
    target_link_libraries(FarCry PRIVATE
        user32 gdi32 winmm wsock32 advapi32 kernel32
        d3d9 d3dx9 dinput8 dxguid
    )
    
elseif(UNIX)
    # Linux libraries
    target_link_libraries(FarCry PRIVATE
        dl pthread m
        GL GLU X11 Xext
    )
endif()

# Include directories
target_include_directories(FarCry PRIVATE
    ${CMAKE_SOURCE_DIR}/CryCommon
    ${CMAKE_SOURCE_DIR}/CrySystem
    ${CMAKE_SOURCE_DIR}/CryGame
)

# Preprocessor definitions
target_compile_definitions(FarCry PRIVATE
    FARCRY_EXECUTABLE=1
    NOT_USE_CRY_MEMORY_MANAGER=1
)

# For macOS, use forced include of clean headers to bypass legacy issues  
if(APPLE)
    target_compile_options(FarCry PRIVATE
        -include ${CMAKE_SOURCE_DIR}/CryCommon/platform_macos.h
    )
    
    # Compile Main.cpp as Objective-C++ for Cocoa API support
    set_source_files_properties(Main.cpp PROPERTIES
        COMPILE_FLAGS "-x objective-c++"
    )
endif()

if(APPLE)
    target_compile_definitions(FarCry PRIVATE
        __APPLE__=1
        __MACH__=1
    )
    
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        target_compile_definitions(FarCry PRIVATE
            _CPU_ARM64=1
        )
    endif()
endif()

# Asset Management
# Define game assets that need to be deployed
set(GAME_ASSETS
    ${CMAKE_SOURCE_DIR}/fcsplash.bmp
)

# Define level assets if they exist
file(GLOB LEVEL_ASSETS ${CMAKE_SOURCE_DIR}/Levels/*)

# Asset deployment function
function(deploy_game_assets target_name)
    if(APPLE)
        # Install splash screen and other assets to Resources
        foreach(ASSET ${GAME_ASSETS})
            if(EXISTS ${ASSET})
                get_filename_component(ASSET_NAME ${ASSET} NAME)
                install(FILES ${ASSET} 
                    DESTINATION "${CMAKE_INSTALL_PREFIX}/${target_name}.app/Contents/Resources"
                    COMPONENT Runtime
                )
            else()
                message(WARNING "Asset file not found: ${ASSET}")
            endif()
        endforeach()
        
        # Install levels directory if it exists
        if(LEVEL_ASSETS)
            install(DIRECTORY ${CMAKE_SOURCE_DIR}/Levels
                DESTINATION "${CMAKE_INSTALL_PREFIX}/${target_name}.app/Contents/Resources"
                COMPONENT Runtime
            )
        endif()
        
        # Also use POST_BUILD for development builds (when not installing)
        # Ensure Resources directory exists first
        add_custom_command(TARGET ${target_name} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_CONTENT_DIR:${target_name}>/Resources"
            COMMENT "Creating Resources directory for ${target_name}"
            VERBATIM
        )
        
        # Copy splash screen and other assets
        foreach(ASSET ${GAME_ASSETS})
            if(EXISTS ${ASSET})
                get_filename_component(ASSET_NAME ${ASSET} NAME)
                add_custom_command(TARGET ${target_name} POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${ASSET}"
                        "$<TARGET_BUNDLE_CONTENT_DIR:${target_name}>/Resources/${ASSET_NAME}"
                    COMMENT "Copying asset: ${ASSET_NAME} to Resources"
                    VERBATIM
                    DEPENDS ${ASSET}
                )
            endif()
        endforeach()
        
        # Copy levels directory if it exists
        if(LEVEL_ASSETS)
            add_custom_command(TARGET ${target_name} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_directory_if_different
                    "${CMAKE_SOURCE_DIR}/Levels"
                    "$<TARGET_BUNDLE_CONTENT_DIR:${target_name}>/Resources/Levels"
                COMMENT "Copying Levels directory"
                VERBATIM
            )
        else()
            # Create Levels directory even if empty (for testing)
            add_custom_command(TARGET ${target_name} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory
                    "$<TARGET_BUNDLE_CONTENT_DIR:${target_name}>/Resources/Levels"
                COMMENT "Creating Levels directory in Resources"
                VERBATIM
            )
        endif()
    else()
        # For other platforms, install assets next to executable
        foreach(ASSET ${GAME_ASSETS})
            if(EXISTS ${ASSET})
                get_filename_component(ASSET_NAME ${ASSET} NAME)
                install(FILES ${ASSET} 
                    DESTINATION bin
                    COMPONENT Runtime
                )
                add_custom_command(TARGET ${target_name} POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${ASSET}"
                        "$<TARGET_FILE_DIR:${target_name}>/${ASSET_NAME}"
                    COMMENT "Copying asset: ${ASSET_NAME}"
                    VERBATIM
                )
            endif()
        endforeach()
    endif()
endfunction()

# Deploy assets for this target
deploy_game_assets(FarCry)

# Set output directory
set_target_properties(FarCry PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)
