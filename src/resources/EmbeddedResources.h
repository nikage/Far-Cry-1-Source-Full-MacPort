////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   EmbeddedResources.h
//  Version:     v1.00
//  Created:     03/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Embedded resources for macOS to avoid file system dependencies
//               and critical section locks
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#pragma once

#include <string>
#include <map>
#include <vector>

class CEmbeddedResources
{
public:
    static CEmbeddedResources& GetInstance();
    
    // Font resources
    bool GetFontData(const std::string& fontName, std::vector<uint8_t>& data);
    bool GetFontXML(const std::string& fontName, std::string& xmlContent);
    
    // Texture resources
    bool GetTextureData(const std::string& textureName, std::vector<uint8_t>& data);
    
    // Sound resources
    bool GetSoundData(const std::string& soundName, std::vector<uint8_t>& data);
    
    // Check if resource exists
    bool HasResource(const std::string& resourceName);
    
private:
    CEmbeddedResources();
    ~CEmbeddedResources();
    
    void InitializeResources();
    
    std::map<std::string, std::vector<uint8_t>> m_fontData;
    std::map<std::string, std::string> m_fontXML;
    std::map<std::string, std::vector<uint8_t>> m_textureData;
    std::map<std::string, std::vector<uint8_t>> m_soundData;
};

// Convenience macros for resource access
#define EMBEDDED_FONT_DATA(name) CEmbeddedResources::GetInstance().GetFontData(name, data)
#define EMBEDDED_FONT_XML(name) CEmbeddedResources::GetInstance().GetFontXML(name, xml)
#define EMBEDDED_TEXTURE_DATA(name) CEmbeddedResources::GetInstance().GetTextureData(name, data)
#define EMBEDDED_SOUND_DATA(name) CEmbeddedResources::GetInstance().GetSoundData(name, data)


