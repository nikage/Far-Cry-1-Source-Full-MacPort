////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   EmbeddedResources.cpp
//  Version:     v1.00
//  Created:     03/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Embedded resources implementation for macOS
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#include "EmbeddedResources.h"
#include <fstream>
#include <iostream>

CEmbeddedResources& CEmbeddedResources::GetInstance()
{
    static CEmbeddedResources instance;
    return instance;
}

CEmbeddedResources::CEmbeddedResources()
{
    InitializeResources();
}

CEmbeddedResources::~CEmbeddedResources()
{
}

void CEmbeddedResources::InitializeResources()
{
    // Initialize default font XML content
    m_fontXML["default"] = R"(<?xml version="1.0" encoding="UTF-8"?>
<fontshader>
    <font path="languages/fonts/arialnb.ttf" w="512" h="512"/>
    <effect name="default">
        <pass>
        </pass>
        <pass>
            <color r="0" g="0" b="0" a="1"/>
            <pos x="1" y="1"/>
        </pass>
    </effect>
    <effect name="console">
        <pass>
        </pass>
        <pass>
            <color r="0" g="0" b="0" a="0.5"/>
            <pos x="2" y="2"/>
        </pass>
    </effect>
</fontshader>)";

    m_fontXML["console"] = R"(<?xml version="1.0" encoding="UTF-8"?>
<fontshader>
    <font path="languages/fonts/arialnb.ttf" w="512" h="512"/>
    <effect name="default">
        <pass>
        </pass>
        <pass>
            <color r="0" g="0" b="0" a="1"/>
            <pos x="1" y="1"/>
            <size scale="1"/>    
        </pass>
    </effect>
    <effect name="console">
        <pass>
        </pass>
        <pass>
            <color r="0" g="0" b="0" a="0.5"/>
            <pos x="2" y="2"/>
        </pass>
    </effect>
</fontshader>)";
}

bool CEmbeddedResources::GetFontData(const std::string& fontName, std::vector<uint8_t>& data)
{
    // For now, return empty data - fonts will be handled by system fonts
    data.clear();
    return true;
}

bool CEmbeddedResources::GetFontXML(const std::string& fontName, std::string& xmlContent)
{
    auto it = m_fontXML.find(fontName);
    if (it != m_fontXML.end())
    {
        xmlContent = it->second;
        return true;
    }
    return false;
}

bool CEmbeddedResources::GetTextureData(const std::string& textureName, std::vector<uint8_t>& data)
{
    // For now, return empty data - textures will be handled by Metal renderer
    data.clear();
    return true;
}

bool CEmbeddedResources::GetSoundData(const std::string& soundName, std::vector<uint8_t>& data)
{
    // For now, return empty data - sounds will be handled by sound system
    data.clear();
    return true;
}

bool CEmbeddedResources::HasResource(const std::string& resourceName)
{
    return m_fontXML.find(resourceName) != m_fontXML.end() ||
           m_fontData.find(resourceName) != m_fontData.end() ||
           m_textureData.find(resourceName) != m_textureData.end() ||
           m_soundData.find(resourceName) != m_soundData.end();
}


