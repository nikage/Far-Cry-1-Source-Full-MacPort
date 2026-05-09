////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalShaderLoader.cpp
//  Version:     v1.00 - Phase 2 Implementation
//  Created:     30/10/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Shader loading and compilation for Phase 2
//               Includes initialization of default shader library
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalShaderManager.m"
#include "MetalGeneratedVertex.h"
#include "MetalManifestPSOHelpers.h"
#include "MetalBaseRenderer.m"
#include "MetalVertexDescriptor.m"
#include "MetalStateCache.m"
#include <Cocoa/Cocoa.h>
#include <fstream>
#include <sstream>
#include <cctype>
#include <cassert>
#include <strings.h>
#include <algorithm>
#include <cstdlib>
#include <vector>
#include <string>
#include <unordered_map>
#include <unordered_set>
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

namespace
{
static NSString* MetalShaderValidationAssetDirFromEnv()
{
    const char* env = getenv("FARCRY_METAL_VALIDATION_DIR");
    if (!env || !env[0])
        return nil;
    NSString* s = [NSString stringWithUTF8String:env];
    if (![s length])
        return nil;
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:s isDirectory:&isDir] && isDir)
        return s;
    return nil;
}

static int g_missingVertexLogCount = 0;
static int g_vertexMatchLogCount = 0;
static int g_requirementLogCount = 0;
static int g_fragmentMetaLogCount = 0;
static int g_orphanStandaloneVertexLogCount = 0;
static const int kMaxMissingVertexLogs = 32;
struct VertexLayoutInfo
{
    int format;
    NSString* functionName;
    bool hasTexCoords;
    bool hasColor;
    bool hasSecondTex;
    bool hasSecondColor;
    bool hasNormal;
    bool needsTangents = false;
    int texCoordCount;
};

struct VertexAttributeSummary
{
    bool hasPosition = true;
    bool hasNormal = false;
    bool hasColor0 = false;
    bool hasColor1 = false;
    bool hasTangent = false;
    bool hasBinormal = false;
    bool hasTNormal = false;
    int texCoordCount = 0;
};

static std::string ToLowerCopy(const std::string& value)
{
    std::string lower = value;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return lower;
}

struct FragmentVaryingRequirement
{
    std::string name;
    std::string normalizedName;
    int components = 0;
};

VertexAttributeSummary BuildAttributeSummary(NSArray* attributes, NSArray* metadata, int textureCount, NSString* shaderName)
{
    VertexAttributeSummary summary;
    bool populatedFromMetadata = false;
    if (metadata && [metadata isKindOfClass:[NSArray class]] && [metadata count] > 0)
    {
        populatedFromMetadata = true;
        for (id entry in metadata)
        {
            if (![entry isKindOfClass:[NSDictionary class]])
                continue;
            NSDictionary* dict = (NSDictionary*)entry;
        NSString* categoryValue = dict[@"category"];
        NSString* category = categoryValue ? [categoryValue lowercaseString] : nil;
            if (!category || ![category isKindOfClass:[NSString class]])
                continue;
            if ([category isEqualToString:@"color"])
            {
                NSNumber* indexValue = dict[@"index"];
                int index = indexValue ? indexValue.intValue : 0;
                if (index <= 0)
                    summary.hasColor0 = true;
                else if (index == 1)
                    summary.hasColor1 = true;
            }
            else if ([category isEqualToString:@"texcoord"])
            {
                NSNumber* indexValue = dict[@"index"];
                if (indexValue)
                {
                    int idx = indexValue.intValue;
                    if (idx >= 0)
                        summary.texCoordCount = std::max(summary.texCoordCount, idx + 1);
                }
            }
            else if ([category isEqualToString:@"normal"])
            {
                summary.hasNormal = true;
                NSString* token = dict[@"token"];
                if (token && [token isKindOfClass:[NSString class]])
                {
                    NSString* lowered = [token lowercaseString];
                    if ([lowered containsString:@"tnormal"] || [lowered containsString:@"t_normal"])
                    {
                        summary.hasTNormal = true;
                    }
                }
            }
            else if ([category isEqualToString:@"tangent"])
            {
                summary.hasTangent = true;
            }
            else if ([category isEqualToString:@"binormal"])
            {
                summary.hasBinormal = true;
            }
        }
    }

    const bool hasExplicitAttributes = attributes && [attributes count] > 0;
    if (summary.hasTNormal)
    {
        summary.hasNormal = true;
        summary.hasTangent = true;
        summary.hasBinormal = true;
    }

    if (!populatedFromMetadata)
    {
        if (hasExplicitAttributes)
        {
            for (id item in attributes)
            {
                if (![item isKindOfClass:[NSString class]])
                    continue;
                NSString* attrString = [(NSString*)item lowercaseString];
                if ([attrString containsString:@"normal"])
                    summary.hasNormal = true;
                if ([attrString containsString:@"color1"] || [attrString containsString:@"sec_color"])
                    summary.hasColor1 = true;
                else if ([attrString containsString:@"color"])
                    summary.hasColor0 = true;
                if ([attrString containsString:@"texcoord1"])
                    summary.texCoordCount = std::max(summary.texCoordCount, 2);
                else if ([attrString containsString:@"texcoord"])
                    summary.texCoordCount = std::max(summary.texCoordCount, 1);
            }
        }
        if (shaderName)
        {
            NSString* lowerName = [shaderName lowercaseString];
            if ([lowerName hasPrefix:@"cgv"])
            {
                summary.hasColor0 = true;
                summary.texCoordCount = std::max(summary.texCoordCount, 1);
            }

            if (([lowerName containsString:@"bump"] || [lowerName containsString:@"normalmap"]) && !summary.hasTangent)
            {
                summary.hasTangent = true;
                summary.hasBinormal = true;
                summary.hasTNormal = true;
            }
            if (!hasExplicitAttributes)
            {
                if ([lowerName containsString:@"vegetation"] ||
                    [lowerName containsString:@"plants"])
                {
                    summary.hasColor0 = true;
                    summary.texCoordCount = std::max(summary.texCoordCount, 1);
                }
                if ([lowerName containsString:@"normal"] ||
                    [lowerName containsString:@"bump"])
                {
                    summary.hasNormal = true;
                    summary.texCoordCount = std::max(summary.texCoordCount, 1);
                }
            }
        }
    }

    if (summary.texCoordCount == 0 && textureCount > 0)
        summary.texCoordCount = 1;
    if (summary.hasColor1)
        summary.hasColor0 = true;
    summary.texCoordCount = std::min(summary.texCoordCount, 2);
    return summary;
}

VertexLayoutInfo InferVertexLayout(const VertexAttributeSummary& summary, NSString* shaderName)
{
    VertexLayoutInfo info;
    info.hasTexCoords = summary.texCoordCount > 0;
    info.hasColor = summary.hasColor0;
    info.hasSecondTex = summary.texCoordCount > 1;
    info.hasSecondColor = summary.hasColor1;
    info.hasNormal = summary.hasNormal;
    info.texCoordCount = summary.texCoordCount;

    const bool requiresTangentFrame = summary.hasTangent || summary.hasBinormal || summary.hasTNormal;
    info.needsTangents = requiresTangentFrame;

    // Tangent frame takes highest priority: bump-mapped shaders must use the
    // tangent vertex path even when they also carry dual vertex colors, so that
    // the normal-mapping data reaches the fragment stage correctly.
    if (requiresTangentFrame)
    {
        info.format = VERTEX_FORMAT_P3F_N_COL4UB_TEX2F;
        info.functionName = @"tangent_vertex";
        return info;
    }

    if (summary.hasColor1)
    {
        if (summary.hasNormal)
        {
            if (summary.texCoordCount > 1)
            {
                info.format = VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F_TEX2F;
                info.functionName = @"basic_colordual_tex2_vertex";
            }
            else if (summary.texCoordCount > 0)
            {
                info.format = VERTEX_FORMAT_P3F_N_COL4UB_COL4UB_TEX2F;
                info.functionName = @"basic_colordual_tex_vertex";
            }
            else
            {
                info.format = VERTEX_FORMAT_P3F_N_COL4UB_COL4UB;
                info.functionName = @"basic_colordual_vertex";
            }
        }
        else
        {
            if (summary.texCoordCount > 0)
            {
                info.format = VERTEX_FORMAT_P3F_COL4UB_COL4UB_TEX2F;
                info.functionName = @"colordual_tex_vertex";
            }
            else
            {
                info.format = VERTEX_FORMAT_P3F_COL4UB_COL4UB;
                info.functionName = @"colordual_vertex";
            }
        }
        return info;
    }

    if (summary.texCoordCount > 1)
        info.format = VERTEX_FORMAT_P3F_COL4UB_TEX2F_TEX2F;
    else if (summary.hasNormal && summary.hasColor0 && summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_N_COL4UB_TEX2F;
    else if (summary.hasNormal && summary.hasColor0 && summary.texCoordCount == 0)
        info.format = VERTEX_FORMAT_P3F_N_COL4UB;
    else if (summary.hasNormal && !summary.hasColor0 && summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_N_TEX2F;
    else if (summary.hasNormal && !summary.hasColor0)
        info.format = VERTEX_FORMAT_P3F_N;
    else if (summary.hasColor0 && summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_COL4UB_TEX2F;
    else if (summary.texCoordCount > 0)
        info.format = VERTEX_FORMAT_P3F_TEX2F;
    else if (summary.hasColor0)
        info.format = VERTEX_FORMAT_P3F_COL4UB;
    else
        info.format = VERTEX_FORMAT_P3F;

    if (summary.texCoordCount > 1)
        info.functionName = summary.hasColor0 ? @"colortex2_vertex" : @"tex2_vertex";
    else if (summary.hasNormal && summary.hasColor0 && summary.texCoordCount > 0)
        info.functionName = @"basic_vertex";
    else if (summary.hasNormal && summary.hasColor0 && summary.texCoordCount == 0)
        info.functionName = @"basic_color_vertex";
    else if (summary.hasNormal && !summary.hasColor0 && summary.texCoordCount > 0)
        info.functionName = @"normaltex_vertex";
    else if (summary.hasNormal && !summary.hasColor0)
        info.functionName = @"normal_vertex";
    else if (summary.texCoordCount > 0)
        info.functionName = summary.hasColor0 ? @"colortex_vertex" : @"tex_vertex";
    else
        info.functionName = summary.hasColor0 ? @"color_vertex" : @"simple_vertex";

    return info;
}

static void ApplyScreenVertexFallback(bool hasGeneratedVertex,
                                      VertexLayoutInfo& layout,
                                      const VertexAttributeSummary& summary,
                                      NSString* shaderName)
{
    if (hasGeneratedVertex)
        return;
    if (summary.texCoordCount == 0)
        return;
    if (summary.hasNormal || summary.hasColor0 || summary.hasColor1 ||
        summary.hasTangent || summary.hasBinormal || summary.hasTNormal)
    {
        return;
    }

    layout.format = VERTEX_FORMAT_P3F_TEX2F;
    layout.functionName = @"screen_vertex";
    layout.hasTexCoords = true;
    layout.hasColor = false;
    layout.hasNormal = false;
    layout.needsTangents = false;

    if (iLog && shaderName)
    {
        iLog->Log("MetalShaderManager: applying screen_vertex fallback for shader '%s'\n",
                  [shaderName UTF8String]);
    }
}


static std::string NormalizeShaderName(const char* name)
{
    if (!name)
        return "";

    char normalized[256];
    strncpy(normalized, name, sizeof(normalized) - 1);
    normalized[sizeof(normalized) - 1] = 0;

    for (char* p = normalized; *p; ++p)
    {
        if (*p == '\\')
            *p = '/';
        *p = static_cast<char>(std::tolower(static_cast<unsigned char>(*p)));
    }
    return std::string(normalized);
}

static std::string NSStringToStdString(NSString* value)
{
    if (!value)
        return std::string();
    const char* utf8 = [value UTF8String];
    if (!utf8)
        return std::string();
    return std::string(utf8);
}

static int DetermineDefaultComponents(const std::string& categoryLower, const std::string& tokenLower)
{
    if (categoryLower == "color")
        return 4;
    if (categoryLower == "texcoord")
        return 2;
    if (categoryLower == "normal" || categoryLower == "tangent" || categoryLower == "binormal")
        return 3;
    if (tokenLower.find("tex") == 0)
        return 2;
    return 4;
}

static int ParseComponentsSuffix(const std::string& value)
{
    size_t underscore = value.rfind('_');
    if (underscore == std::string::npos || underscore + 1 >= value.size())
        return 0;
    const char* start = value.c_str() + underscore + 1;
    char* end = nullptr;
    long parsed = strtol(start, &end, 10);
    if (end == start || parsed <= 0)
        return 0;
    return static_cast<int>(parsed);
}

static bool ParseAttributeRequirementString(NSString* attrString, FragmentVaryingRequirement& outRequirement)
{
    if (!attrString || ![attrString isKindOfClass:[NSString class]])
        return false;
    const std::string value = NSStringToStdString(attrString);
    if (value.empty())
        return false;
    std::string upper = value;
    std::transform(upper.begin(), upper.end(), upper.begin(), [](unsigned char c) {
        return static_cast<char>(std::toupper(c));
    });
    std::string token;
    int components = 0;
    if (upper.find("TEXCOORD") == 0)
    {
        size_t indexPos = strlen("TEXCOORD");
        std::string indexDigits;
        while (indexPos < upper.size() && std::isdigit(static_cast<unsigned char>(upper[indexPos])))
        {
            indexDigits.push_back(static_cast<char>(upper[indexPos]));
            indexPos++;
        }
        token = "Tex" + indexDigits;
        components = ParseComponentsSuffix(upper);
        if (components <= 0)
            components = 2;
    }
    else if (upper.find("COLOR") == 0)
    {
        std::string suffix = upper.substr(strlen("COLOR"));
        token = suffix.empty() ? "Color" : "Color" + suffix;
        components = ParseComponentsSuffix(upper);
        if (components <= 0)
            components = 4;
    }
    else
    {
        token = value;
        components = ParseComponentsSuffix(upper);
        if (components <= 0)
            components = 4;
    }
    if (token.empty())
        return false;
    outRequirement.name = token;
    outRequirement.normalizedName = ToLowerCopy(token);
    outRequirement.components = components;
    return true;
}

static std::vector<FragmentVaryingRequirement> BuildFragmentVaryingRequirements(
    NSArray* metadataArray,
    NSArray* attributeArray)
{
    std::unordered_map<std::string, FragmentVaryingRequirement> requirements;
    if (metadataArray && [metadataArray isKindOfClass:[NSArray class]])
    {
        for (id entry in metadataArray)
        {
            if (![entry isKindOfClass:[NSDictionary class]])
                continue;
            NSDictionary* dict = (NSDictionary*)entry;
            NSString* tokenValue = dict[@"token"];
            if (!tokenValue || ![tokenValue isKindOfClass:[NSString class]])
                continue;
            const std::string token = NSStringToStdString(tokenValue);
            std::string normalized = ToLowerCopy(token);
            NSString* categoryValue = dict[@"category"];
            std::string categoryLower;
            if (categoryValue && [categoryValue isKindOfClass:[NSString class]])
                categoryLower = ToLowerCopy(NSStringToStdString(categoryValue));
            if (categoryLower == "position" || normalized == "position")
                continue;
            NSNumber* componentsValue = dict[@"components"];
            int components = componentsValue ? componentsValue.intValue : 0;
            if (components <= 0)
                components = DetermineDefaultComponents(categoryLower, normalized);
            FragmentVaryingRequirement requirement;
            requirement.name = token;
            requirement.normalizedName = normalized;
            requirement.components = components;
            requirements[normalized] = requirement;
        }
    }
    if (requirements.empty() && attributeArray && [attributeArray isKindOfClass:[NSArray class]])
    {
        for (id item in attributeArray)
        {
            if (![item isKindOfClass:[NSString class]])
                continue;
            FragmentVaryingRequirement requirement;
            if (!ParseAttributeRequirementString((NSString*)item, requirement))
                continue;
            if (requirement.normalizedName == "position")
                continue;
            requirements[requirement.normalizedName] = requirement;
        }
    }
    std::vector<FragmentVaryingRequirement> result;
    result.reserve(requirements.size());
    for (const auto& kv : requirements)
        result.push_back(kv.second);
    if (result.empty() && metadataArray && [metadataArray isKindOfClass:[NSArray class]] && [metadataArray count] > 0 && g_requirementLogCount < 5)
    {
        fprintf(stderr, "MetalShaderManager: requirement extraction failed for metadata count=%ld\n",
                (long)[metadataArray count]);
        g_requirementLogCount++;
    }
    std::sort(result.begin(), result.end(), [](const FragmentVaryingRequirement& a, const FragmentVaryingRequirement& b) {
        return a.normalizedName < b.normalizedName;
    });
    return result;
}

static std::string StripStagePrefix(const std::string& value)
{
    static const char* prefixes[] = {
        "cgvprog_", "cgvprog", "cgv_", "cgvs_", "cgvs",
        "cgrc_", "cgrc", "cgr_", "cgp_", "cgp", "cg_"
    };
    for (const char* prefix : prefixes)
    {
        const size_t length = strlen(prefix);
        if (value.size() >= length && value.compare(0, length, prefix) == 0)
        {
            return value.substr(length);
        }
    }
    return value;
}

static std::string StripVertexSuffix(const std::string& value)
{
    static const char* suffixes[] = { "_vs10", "_vs11", "_vs20", "_vs30" };
    for (const char* suffix : suffixes)
    {
        const size_t length = strlen(suffix);
        if (value.size() > length && value.compare(value.size() - length, length, suffix) == 0)
        {
            return value.substr(0, value.size() - length);
        }
    }
    return value;
}

static std::string StripPixelSuffix(const std::string& value)
{
    static const char* suffixes[] = {
        "_ps50", "_ps40", "_ps30", "_ps20", "_ps3x", "_ps2x",
        "_ps14", "_ps13", "_ps12", "_ps11", "_ps10", "_ps"
    };
    for (const char* suffix : suffixes)
    {
        const size_t length = strlen(suffix);
        if (value.size() > length && value.compare(value.size() - length, length, suffix) == 0)
        {
            return value.substr(0, value.size() - length);
        }
    }
    return value;
}

static std::string BuildStageAgnosticKey(const std::string& normalized)
{
    return StripPixelSuffix(StripVertexSuffix(StripStagePrefix(normalized)));
}

static std::vector<std::string> BuildVertexLookupCandidates(const std::string& canonicalKey)
{
    std::vector<std::string> candidates;
    std::unordered_set<std::string> seen;
    auto pushCandidate = [&](const std::string& key)
    {
        if (!key.empty() && seen.insert(key).second)
            candidates.push_back(key);
    };

    pushCandidate(canonicalKey);

    std::string current = canonicalKey;
    size_t depth = 0;
    size_t position = current.rfind('_');
    while (position != std::string::npos && depth < 8)
    {
        current = current.substr(0, position);
        if (current.length() < 4)
            break;
        pushCandidate(current);
        position = current.rfind('_');
        depth++;
    }

    return candidates;
}

static bool StartsWith(const std::string& value, const std::string& prefix)
{
    return value.size() >= prefix.size() &&
           value.compare(0, prefix.size(), prefix) == 0;
}

static const GeneratedVertexEntry* FindVertexEntryByOutputs(
    const std::unordered_map<std::string, GeneratedVertexEntry>& entries,
    const std::vector<FragmentVaryingRequirement>& requirements)
{
    if (requirements.empty())
        return nullptr;
    const GeneratedVertexEntry* bestEntry = nullptr;
    int bestScore = -1;
    for (const auto& kv : entries)
    {
        if (kv.second.outputs.empty())
            continue;
        std::unordered_map<std::string, int> outputMap;
        for (const GeneratedVertexOutputDesc& output : kv.second.outputs)
        {
            const std::string key = ToLowerCopy(output.name);
            const int components = output.components > 0 ? output.components : 4;
            auto it = outputMap.find(key);
            if (it == outputMap.end())
                outputMap[key] = components;
            else
                it->second = std::max(it->second, components);
        }
        bool missing = false;
        int matched = 0;
        for (const FragmentVaryingRequirement& requirement : requirements)
        {
            auto it = outputMap.find(requirement.normalizedName);
            if (it == outputMap.end() || it->second < requirement.components)
            {
                missing = true;
                break;
            }
            matched++;
        }
        if (missing)
            continue;
        const int score = matched * 100 - static_cast<int>(outputMap.size());
        if (score > bestScore)
        {
            bestScore = score;
            bestEntry = &kv.second;
        }
    }
    return bestEntry;
}

static const GeneratedVertexEntry* FindGeneratedVertexEntry(
    const std::unordered_map<std::string, GeneratedVertexEntry>& entries,
    const std::string& canonicalKey,
    NSArray* fragmentVertexAttrMetaArray,
    NSArray* fragmentVertexAttrArray)
{
    if (canonicalKey.empty() || entries.empty())
        return nullptr;

    const std::vector<FragmentVaryingRequirement> requirements =
        BuildFragmentVaryingRequirements(fragmentVertexAttrMetaArray, fragmentVertexAttrArray);
    if (!requirements.empty() && g_requirementLogCount < 5)
    {
        fprintf(stderr, "MetalShaderManager: fragment key '%s' requirement count=%zu\n",
                canonicalKey.c_str(),
                requirements.size());
        g_requirementLogCount++;
    }
    const GeneratedVertexEntry* outputMatch = FindVertexEntryByOutputs(entries, requirements);
    if (outputMatch)
    {
        if (iLog)
        {
            iLog->Log("MetalShaderManager: output matched fragment key '%s' to vertex entry '%s'\n",
                      canonicalKey.c_str(),
                      outputMatch->entryPoint.c_str());
        }
        else
        {
            fprintf(stderr, "MetalShaderManager: output matched fragment key '%s' to vertex entry '%s'\n",
                    canonicalKey.c_str(),
                    outputMatch->entryPoint.c_str());
        }
        return outputMatch;
    }

    const std::vector<std::string> candidates = BuildVertexLookupCandidates(canonicalKey);
    for (const std::string& candidate : candidates)
    {
        auto it = entries.find(candidate);
        if (it != entries.end())
        {
            if (candidate != canonicalKey && iLog)
            {
                iLog->Log("MetalShaderManager: mapped fragment key '%s' to vertex key '%s'\n",
                          canonicalKey.c_str(), candidate.c_str());
            }
            return &it->second;
        }
    }

    const GeneratedVertexEntry* bestEntry = nullptr;
    const std::string* bestKey = nullptr;
    for (const auto& kv : entries)
    {
        if (StartsWith(canonicalKey, kv.first))
        {
            if (!bestEntry || kv.first.length() > bestKey->length())
            {
                bestEntry = &kv.second;
                bestKey = &kv.first;
            }
        }
    }

    if (bestEntry && bestKey && iLog)
    {
        iLog->Log("MetalShaderManager: using prefix vertex key '%s' for fragment key '%s'\n",
                  bestKey->c_str(), canonicalKey.c_str());
    }

    return bestEntry;
}

}

CMetalShaderManager::CMetalShaderManager(CMetalBaseRenderer* renderer, 
                                        CMetalTextureManager* textureManager)
    : m_renderer(renderer)
    , m_textureManager(textureManager)
    , m_nextShaderId(1)
    , m_currentShaderId(0)
    , m_currentPipelineState(nil)
    , m_globalShaderTemplateId(0)
    , m_heatVisionEnabled(false)
    , m_lastPipelineHadTangentMismatch(false)
    , m_generatedLibrary(nil)
    , m_nStartupMissingShaders(0)
    , m_lastGeneratedShaderPsoFailureCount(0)
    , m_lastValidateShaderPairsFailureCount(0)
{
    assert(renderer != nullptr && "CMetalShaderManager: renderer cannot be null!");
    assert(textureManager != nullptr && "CMetalShaderManager: textureManager cannot be null!");
    assert(renderer->m_device != nil && "CMetalShaderManager: renderer must have valid Metal device!");
    assert(m_nextShaderId == 1 && "CMetalShaderManager: shader ID counter must start at 1!");
    
    iLog->Log("MetalShaderManager: Initializing...\n");
    
    if (!InitializeDefaultShaderLibrary())
    {
        iLog->Log("Warning: Failed to initialize default shader library\n");
    }
    
    iLog->Log("MetalShaderManager: Initialization complete (%zu shaders loaded)\n", m_shaders.size());
}

CMetalShaderManager::~CMetalShaderManager()
{
    assert(m_renderer != nullptr && "CMetalShaderManager: renderer should not be null during destruction!");
    assert(m_textureManager != nullptr && "CMetalShaderManager: textureManager should not be null during destruction!");
    
    iLog->Log("MetalShaderManager: Shutting down...\n");
    ClearAllShaders();
    
    assert(m_shaders.empty() && "CMetalShaderManager: all shaders should be cleared!");
    assert(m_shaderNameMap.empty() && "CMetalShaderManager: shader name map should be cleared!");
}

bool CMetalShaderManager::InitializeDefaultShaderLibrary()
{
    assert(m_renderer != nullptr && "InitializeDefaultShaderLibrary: renderer cannot be null!");
    assert(m_renderer->m_device != nil && "InitializeDefaultShaderLibrary: Metal device cannot be null!");
    
    if (!m_renderer || !m_renderer->m_device)
    {
        iLog->Log("Error: No Metal device available\n");
        return false;
    }
    
    NSError* error = nil;
    
    id<MTLLibrary> defaultLibrary = nil;

    NSString* validationDir = MetalShaderValidationAssetDirFromEnv();
    if (validationDir)
    {
        NSString* utilPath = [validationDir stringByAppendingPathComponent:@"UtilShaders.metallib"];
        defaultLibrary = [m_renderer->m_device newLibraryWithFile:utilPath error:&error];
        if (defaultLibrary && iLog)
            iLog->Log("MetalShaderManager: loaded UtilShaders.metallib from FARCRY_METAL_VALIDATION_DIR\n");
    }

    NSBundle* bundle = [NSBundle mainBundle];
    NSString* shaderPath = [bundle pathForResource:@"UtilShaders" ofType:@"metallib"];
    
    if (!defaultLibrary && shaderPath)
    {
        iLog->Log("Loading shader library from: %s\n", [shaderPath UTF8String]);
        defaultLibrary = [m_renderer->m_device newLibraryWithFile:shaderPath error:&error];
    }
    
    if (!defaultLibrary)
    {
        // Try loading from app bundle MacOS directory (where we copy the metallibs)
        NSString* exePath = [[NSBundle mainBundle] executablePath];
        NSString* exeDir = [exePath stringByDeletingLastPathComponent];
        NSString* metallibPath = [exeDir stringByAppendingPathComponent:@"UtilShaders.metallib"];
        
        iLog->Log("Attempting to load from executable directory: %s\n", [metallibPath UTF8String]);
        defaultLibrary = [m_renderer->m_device newLibraryWithFile:metallibPath error:&error];
    }
    
    if (!defaultLibrary)
    {
        iLog->Log("Attempting to load default library...\n");
        defaultLibrary = [m_renderer->m_device newDefaultLibrary];
    }
    
    if (!defaultLibrary)
    {
        iLog->Log("Error: Failed to create shader library: %s\n",
               error ? [[error localizedDescription] UTF8String] : "Unknown error");
        assert(!"MetalShaderManager: UtilShaders.metallib not found in bundle or executable directory");
        return false;
    }
    
    iLog->Log("Shader library loaded successfully\n");
    
    m_defaultLibrary = defaultLibrary;
    CreateDefaultShaders(defaultLibrary);
    LoadGeneratedShaders(defaultLibrary);
    if (iLog)
    {
        for (const auto& kv : m_shaderNameMap)
        {
            iLog->Log("MetalShaderManager: base shader '%s' has id=%d\n", kv.first.c_str(), kv.second);
        }
    }
#if DEBUG
    ValidateShaderPairs(m_renderer->m_device, defaultLibrary);
#endif
    
    return true;
}

void CMetalShaderManager::CreateDefaultShaders(id<MTLLibrary> library)
{
    assert(library != nil && "CreateDefaultShaders: library cannot be null!");
    assert(m_renderer != nullptr && "CreateDefaultShaders: renderer cannot be null!");
    assert(m_renderer->m_device != nil && "CreateDefaultShaders: Metal device cannot be null!");
    
    if (!library)
        return;
    
    struct ShaderPair {
        const char* name;
        const char* vertexFunc;
        const char* fragmentFunc;
        int vertexFormat;
    };
    
    ShaderPair defaultShaders[] = {
        {"simple",     "simple_vertex",     "simple_fragment",     VERTEX_FORMAT_P3F},
        {"color",      "color_vertex",      "simple_fragment",     VERTEX_FORMAT_P3F_COL4UB},
        {"colortex",   "colortex_vertex",   "colortex_fragment",   VERTEX_FORMAT_P3F_COL4UB_TEX2F},
        {"basic",      "basic_vertex",      "basic_fragment",      VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
        {"unlit",      "basic_vertex",      "unlit_fragment",      VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
        {"terrain",    "terrain_vertex",    "terrain_fragment",    VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
        {"sky",        "sky_vertex",        "sky_fragment",        VERTEX_FORMAT_P3F_N_COL4UB_TEX2F},
    };
    
    for (const auto& shader : defaultShaders)
    {
        assert(shader.name != nullptr && "CreateDefaultShaders: shader name cannot be null!");
        assert(shader.vertexFunc != nullptr && "CreateDefaultShaders: vertex function name cannot be null!");
        assert(shader.fragmentFunc != nullptr && "CreateDefaultShaders: fragment function name cannot be null!");
        
        id<MTLFunction> vertexFunc = [library newFunctionWithName:@(shader.vertexFunc)];
        id<MTLFunction> fragmentFunc = [library newFunctionWithName:@(shader.fragmentFunc)];
        
        assert(vertexFunc != nil && fragmentFunc != nil && 
               "CreateDefaultShaders: Failed to load shader functions - shader library may be missing or outdated");
        
        MTLVertexDescriptor* vertexDesc = CMetalVertexDescriptorHelper::CreateVertexDescriptor(shader.vertexFormat);
        assert(vertexDesc != nil && "CreateDefaultShaders: Failed to create vertex descriptor - invalid vertex format");
        
        ShaderInfo info;
        info.blendEnabled = true;
        info.blendMode = static_cast<uint32>(kBlendAlpha);
        info.sourceBlendFactor = MTLBlendFactorSourceAlpha;
        info.destinationBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        info.blendOperation = MTLBlendOperationAdd;
        info.sourceAlphaBlendFactor = info.sourceBlendFactor;
        info.destinationAlphaBlendFactor = info.destinationBlendFactor;
        info.alphaBlendOperation = info.blendOperation;
        info.depthTestEnabled = true;
        info.depthWriteEnabled = true;
        info.depthCompareFunction = MTLCompareFunctionLessEqual;
        info.cullMode = MTLCullModeBack;
        info.colorWriteMask = 0xF;
        info.name = shader.name;

        id<MTLRenderPipelineState> pipelineState = CreatePipelineStateWithFunctions(
            vertexFunc, fragmentFunc, vertexDesc, &info);
        
        assert(pipelineState != nil && "CreateDefaultShaders: Failed to create pipeline state");
        
        int shaderId = AllocateShaderId();
        assert(shaderId > 0 && "CreateDefaultShaders: shader ID must be positive!");
        
        info.vertexFunction = vertexFunc;
        info.fragmentFunction = fragmentFunc;
        info.pipelineState = pipelineState;
        info.shaderClass = eSH_World;
        info.isLoaded = true;
        info.nMaskGen = 0;
        info.shaderWrapper = new CMetalShader(shaderId, this);
        info.vertexDescriptor = vertexDesc;

        m_shaders[shaderId] = info;
        m_shaderNameMap[shader.name] = shaderId;
        
        assert(m_shaders.find(shaderId) != m_shaders.end() && "CreateDefaultShaders: shader should be in map!");
        assert(m_shaderNameMap.find(shader.name) != m_shaderNameMap.end() && "CreateDefaultShaders: shader name should be in map!");
        
        iLog->Log("  Loaded shader: %s (ID: %d)\n", shader.name, shaderId);
    }
    
    iLog->Log("Default shaders created: %zu shaders\n", m_shaders.size());
}

static bool ValidateShaderPairReflection(
    id<MTLDevice> device,
    id<MTLFunction> vertexFn,
    id<MTLFunction> fragmentFn,
    MTLVertexDescriptor* vertexDescriptor,
    NSString* shaderName)
{
    if (!device || !vertexFn || !fragmentFn)
        return true;

    MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction   = vertexFn;
    desc.fragmentFunction = fragmentFn;
    desc.vertexDescriptor = vertexDescriptor;
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    desc.depthAttachmentPixelFormat      = MTLPixelFormatDepth32Float_Stencil8;

    MTLRenderPipelineReflection* reflection = nil;
    NSError* err = nil;
    id<MTLRenderPipelineState> pso =
        [device newRenderPipelineStateWithDescriptor:desc
                                            options:MTLPipelineOptionArgumentInfo
                                         reflection:&reflection
                                              error:&err];
    if (!pso)
    {
        if (iLog)
            iLog->LogError("[ValidateShaderPairs] Pipeline dry-run FAILED for '%s': %s",
                shaderName ? [shaderName UTF8String] : "<unknown>",
                err ? [[err localizedDescription] UTF8String] : "unknown error");
        return false;
    }

    if (iLog)
        iLog->Log("[ValidateShaderPairs] pair OK: %s (VS args: %lu, FS args: %lu)\n",
            shaderName ? [shaderName UTF8String] : "<unknown>",
            reflection ? (unsigned long)[reflection.vertexArguments count] : 0ul,
            reflection ? (unsigned long)[reflection.fragmentArguments count] : 0ul);

    return true;
}

void CMetalShaderManager::ValidateShaderPairs(
    id<MTLDevice> device,
    id<MTLLibrary> generatedLib)
{
    if (!device || !generatedLib)
        return;

    if (iLog)
        iLog->Log("[ValidateShaderPairs] Starting debug validation pass...\n");

    int totalPaired      = 0;
    int validationFailed = 0;
    const int kMaxFailuresAllowed = 10;

    for (const auto& kv : m_shaders)
    {
        @autoreleasepool {
            const ShaderInfo& info = kv.second;
            if (!info.isLoaded || !info.vertexFunction || !info.fragmentFunction)
                continue;

            NSString* nameStr = nil;
            for (const auto& nameKv : m_shaderNameMap)
            {
                if (nameKv.second == kv.first)
                {
                    nameStr = [NSString stringWithUTF8String:nameKv.first.c_str()];
                    break;
                }
            }

            if (!ValidateShaderPairReflection(device, info.vertexFunction, info.fragmentFunction,
                                              info.vertexDescriptor, nameStr))
                validationFailed++;
            totalPaired++;
        }
    }

    if (iLog)
        iLog->Log("[ValidateShaderPairs] Validated %d shader pairs; %d pipeline dry-runs failed.\n",
            totalPaired, validationFailed);

    if (validationFailed > kMaxFailuresAllowed)
    {
        if (iLog)
            iLog->LogError(
                "[ValidateShaderPairs] %d/%d shader pairs failed pipeline dry-run "
                "(limit %d) — game continues\n",
                validationFailed, totalPaired, kMaxFailuresAllowed);
    }

    m_lastValidateShaderPairsFailureCount = validationFailed;
}

void CMetalShaderManager::RunValidateShaderPairs()
{
    if (!m_renderer || !m_renderer->m_device || !m_defaultLibrary)
        return;
    ValidateShaderPairs(m_renderer->m_device, m_defaultLibrary);
}

int CMetalShaderManager::TryRegisterOneManifestPipeline(
    NSDictionary* fragEntry,
    NSDictionary* aliasSourceOverride,
    const std::string& registrationNormalizedKey,
    id<MTLLibrary> generatedLibrary,
    id<MTLLibrary> vertexLibrary,
    const std::unordered_map<std::string, const GeneratedVertexEntry*>& vertexByFuncName,
    int* psoFailCount,
    bool fragmentPairingStats,
    size_t* matchedFragmentVertexCount,
    size_t* missingFragmentVertexCount)
{
    NSDictionary* aliasSrc = aliasSourceOverride ? aliasSourceOverride : fragEntry;

    NSString* shaderName = fragEntry[@"shader"];
    NSString* normalizedName = fragEntry[@"normalized"];
    NSString* fragmentName = fragEntry[@"entryPoint"];
    if (!fragmentName)
        fragmentName = fragEntry[@"fragment"];
    NSArray* uniformArray = fragEntry[@"uniforms"];
    NSArray* textureArray = fragEntry[@"textures"];
    NSArray* vertexAttrArray = fragEntry[@"vertexAttributes"];
    NSArray* vertexAttrMetaArray = fragEntry[@"vertexAttributeMetadata"];
    NSNumber* textureCountValue = fragEntry[@"textureCount"];
    NSArray* directiveArray = fragEntry[@"directives"];
    NSArray* maskArray = fragEntry[@"maskReferences"];
    NSDictionary* pipelineDict = fragEntry[@"pipeline"];

    if (fragmentPairingStats && g_fragmentMetaLogCount < 5)
    {
        long metaCount =
            (vertexAttrMetaArray && [vertexAttrMetaArray isKindOfClass:[NSArray class]])
                ? [vertexAttrMetaArray count]
                : -1;
        long attrCount =
            (vertexAttrArray && [vertexAttrArray isKindOfClass:[NSArray class]])
                ? [vertexAttrArray count]
                : -1;
        fprintf(stderr,
                "MetalShaderManager: fragment '%s' metaCount=%ld attrCount=%ld\n",
                shaderName ? [shaderName UTF8String] : "<nil>",
                metaCount,
                attrCount);
        g_fragmentMetaLogCount++;
    }

    if (!shaderName || !fragmentName)
        return 1;

    std::string fragNormalizedKey;
    if (normalizedName && [normalizedName length] > 0)
        fragNormalizedKey = NormalizeShaderName([normalizedName UTF8String]);
    else
        fragNormalizedKey = NormalizeShaderName([shaderName UTF8String]);

    const std::string canonicalKey = BuildStageAgnosticKey(fragNormalizedKey);

    const GeneratedVertexEntry* matchedVertexEntry = nullptr;
    NSString* manifestVEP = fragEntry[@"vertexEntryPoint"];
    if (manifestVEP && [manifestVEP length] > 0)
    {
        const std::string vepKey = NSStringToStdString(manifestVEP);
        auto it = vertexByFuncName.find(vepKey);
        if (it != vertexByFuncName.end())
            matchedVertexEntry = it->second;
    }
    if (!matchedVertexEntry)
    {
        matchedVertexEntry = FindGeneratedVertexEntry(
            m_generatedVertexEntries, canonicalKey, vertexAttrMetaArray, vertexAttrArray);
    }
    if (fragmentPairingStats)
    {
        if (matchedVertexEntry)
            (*matchedFragmentVertexCount)++;
        else
            (*missingFragmentVertexCount)++;
    }

    if (!matchedVertexEntry && fragmentPairingStats && g_missingVertexLogCount < kMaxMissingVertexLogs)
    {
        if (iLog)
        {
            iLog->Log(
                "MetalShaderManager: missing generated vertex entry for key '%s' (shader '%s')\n",
                canonicalKey.c_str(),
                shaderName ? [shaderName UTF8String] : "<unnamed>");
        }
        else
        {
            fprintf(stderr,
                    "MetalShaderManager: missing generated vertex entry for key '%s' (shader '%s')\n",
                    canonicalKey.c_str(),
                    shaderName ? [shaderName UTF8String] : "<unnamed>");
        }
        g_missingVertexLogCount++;
    }

    NSString* lowerShaderName = [shaderName lowercaseString];
    MTLFunctionConstantValues* funcConstants =
        MetalManifestBuildFunctionConstants(lowerShaderName, directiveArray);

    bool forceTangentFrame = false;

    NSError* funcErr = nil;
    id<MTLFunction> fragmentFunction =
        [generatedLibrary newFunctionWithName:fragmentName
                               constantValues:funcConstants
                                        error:&funcErr];
    if (!fragmentFunction)
    {
        if (iLog)
            iLog->Log("MetalShaderManager: Missing generated fragment function '%s' (error: %s)\n",
                      [fragmentName UTF8String],
                      funcErr ? [[funcErr localizedDescription] UTF8String] : "unknown");
        return 1;
    }

    int textureCount = textureCountValue ? textureCountValue.intValue : 0;
    if (textureArray && [textureArray isKindOfClass:[NSArray class]])
        textureCount = static_cast<int>([textureArray count]);

    if (vertexAttrMetaArray && ![vertexAttrMetaArray isKindOfClass:[NSArray class]] && iLog)
    {
        iLog->Log("MetalShaderManager: vertexAttributeMetadata for '%s' is %s instead of NSArray",
                  shaderName ? [shaderName UTF8String] : "<unnamed>",
                  NSStringFromClass([vertexAttrMetaArray class]).UTF8String);
    }
    VertexAttributeSummary attributeSummary =
        BuildAttributeSummary(vertexAttrArray, vertexAttrMetaArray, textureCount, shaderName);
    forceTangentFrame =
        attributeSummary.hasTNormal || attributeSummary.hasTangent || attributeSummary.hasBinormal;
    const bool hasGeneratedVertexEntry = (matchedVertexEntry != nullptr);
    if (fragmentPairingStats && hasGeneratedVertexEntry &&
        g_vertexMatchLogCount < kMaxMissingVertexLogs)
    {
        if (iLog)
        {
            iLog->Log("MetalShaderManager: matched fragment key '%s' to vertex entry '%s'\n",
                      canonicalKey.c_str(),
                      matchedVertexEntry->entryPoint.c_str());
        }
        fprintf(stderr,
                "MetalShaderManager: matched fragment key '%s' to vertex entry '%s'\n",
                canonicalKey.c_str(),
                matchedVertexEntry->entryPoint.c_str());
        g_vertexMatchLogCount++;
    }
    VertexLayoutInfo layout = InferVertexLayout(attributeSummary, shaderName);
    ApplyScreenVertexFallback(hasGeneratedVertexEntry, layout, attributeSummary, shaderName);
    if (forceTangentFrame)
    {
        layout.needsTangents = true;
        layout.functionName = @"tangent_vertex";
        layout.format = VERTEX_FORMAT_P3F_N_COL4UB_TEX2F;
        layout.hasTexCoords = true;
        layout.hasColor = true;
        layout.hasNormal = true;
    }
    NSString* vertexFunctionName = layout.functionName;
    int vertexFormat = layout.format;
    MTLVertexDescriptor* descriptor = nil;
    bool metadataNeedsTangents = layout.needsTangents;
    if (matchedVertexEntry)
    {
        if (!matchedVertexEntry->vertexInputDescs.empty())
        {
            descriptor = CMetalVertexDescriptorHelper::CreateVertexDescriptorFromVertexInputs(
                matchedVertexEntry->vertexInputDescs);
            layout.needsTangents = false;
        }
        else
        {
            descriptor = CMetalVertexDescriptorHelper::CreateVertexDescriptorFromMetadata(
                matchedVertexEntry->attributes, &metadataNeedsTangents, &vertexFormat);
            if (descriptor)
                layout.needsTangents = metadataNeedsTangents;
        }
    }
    if (layout.needsTangents && iLog)
    {
        iLog->Log("MetalShaderManager: '%s' requires tangent stream support (format=%d)\n",
                  shaderName ? [shaderName UTF8String] : "<unnamed>",
                  vertexFormat);
    }
    id<MTLFunction> vertexFunction = nil;

    PipelineStateConfig pipelineConfig = MetalManifestDefaultPipelineConfig();
    MetalManifestApplyPipelineConfigFromManifest(pipelineConfig, pipelineDict);

    if (vertexLibrary)
    {
        if (matchedVertexEntry && generatedLibrary)
        {
            NSString* generatedVertexName =
                (manifestVEP && [manifestVEP length] > 0)
                    ? manifestVEP
                    : [NSString stringWithUTF8String:matchedVertexEntry->entryPoint.c_str()];
            if (generatedVertexName && [generatedVertexName length] > 0)
            {
                NSError* vertFuncErr = nil;
                id<MTLFunction> generatedVertexFunction =
                    [generatedLibrary newFunctionWithName:generatedVertexName
                                           constantValues:funcConstants
                                                    error:&vertFuncErr];
                if (generatedVertexFunction)
                {
                    vertexFunction = generatedVertexFunction;
                    vertexFunctionName = generatedVertexName;
                }
                else if (iLog)
                {
                    iLog->Log("MetalShaderManager: Missing generated vertex function '%s' for shader '%s'\n",
                              [generatedVertexName UTF8String],
                              shaderName ? [shaderName UTF8String] : "<unnamed>");
                }
            }
        }

        if (!vertexFunction)
        {
            vertexFunction = [vertexLibrary newFunctionWithName:vertexFunctionName];
            if (!vertexFunction)
            {
                const char* shaderLabel = shaderName ? [shaderName UTF8String] : "<unnamed>";
                const char* functionLabel = [vertexFunctionName UTF8String];
                if (iLog)
                {
                    iLog->LogError(
                        "MetalShaderManager: Missing vertex entry '%s' required by shader '%s' - "
                        "ensure UtilShaders.metal defines this helper and regenerate UtilShaders.metallib\n",
                        functionLabel, shaderLabel);
                }
                assert(!"MetalShaderManager: Missing vertex entry in UtilShaders.metallib");
                return 2;
            }
        }
    }
    else
    {
        if (iLog)
            iLog->Log("MetalShaderManager: No vertex library available; skipping shader '%s'\n",
                      shaderName ? [shaderName UTF8String] : "<unnamed>");
        assert(!"MetalShaderManager: No default vertex library available");
        return 2;
    }

    if (!vertexFunction)
    {
        if (iLog)
            iLog->Log("MetalShaderManager: Missing generated vertex function for shader '%s'\n",
                       [shaderName UTF8String]);
        assert(!"MetalShaderManager: Missing generated vertex function");
        return 2;
    }

    if (!descriptor)
    {
        descriptor = CMetalVertexDescriptorHelper::CreateVertexDescriptor(vertexFormat);
    }
    if (!descriptor)
    {
        assert(!"MetalShaderManager: Failed to create vertex descriptor");
        return 2;
    }
    if (layout.needsTangents)
    {
        CMetalVertexDescriptorHelper::AttachTangentAttributes(descriptor);
    }

    ShaderInfo info;
    info.blendEnabled = pipelineConfig.blendEnabled;
    info.blendMode = static_cast<uint32>(pipelineConfig.blendMode);
    info.sourceBlendFactor = pipelineConfig.sourceBlendFactor;
    info.destinationBlendFactor = pipelineConfig.destinationBlendFactor;
    info.blendOperation = pipelineConfig.blendOperation;
    info.sourceAlphaBlendFactor = pipelineConfig.sourceAlphaBlendFactor;
    info.destinationAlphaBlendFactor = pipelineConfig.destinationAlphaBlendFactor;
    info.alphaBlendOperation = pipelineConfig.alphaBlendOperation;
    info.depthTestEnabled = pipelineConfig.depthTestEnabled;
    info.depthWriteEnabled = pipelineConfig.depthWriteEnabled;
    info.depthCompareFunction = pipelineConfig.depthCompareFunction;
    info.cullMode = pipelineConfig.cullMode;
    info.colorWriteMask = pipelineConfig.colorWriteMask;
    info.name = registrationNormalizedKey;
    id<MTLRenderPipelineState> pipelineState =
        CreatePipelineStateWithFunctions(vertexFunction, fragmentFunction, descriptor, &info);
    if (!pipelineState && iLog)
    {
        iLog->Log("MetalShaderManager: pipeline failure for '%s' (needsTangents=%d, tangentError=%d)",
                  shaderName ? [shaderName UTF8String] : "<unnamed>",
                  layout.needsTangents ? 1 : 0,
                  m_lastPipelineHadTangentMismatch ? 1 : 0);
    }
    if (!pipelineState && !layout.needsTangents && m_lastPipelineHadTangentMismatch)
    {
        if (iLog)
        {
            iLog->Log("MetalShaderManager: Retrying shader '%s' with tangent vertex stream\n",
                      shaderName ? [shaderName UTF8String] : "<unnamed>");
        }
        layout.needsTangents = true;
        vertexFunctionName = @"tangent_vertex";
        vertexFormat = VERTEX_FORMAT_P3F_N_COL4UB_TEX2F;
        vertexFunction = [vertexLibrary newFunctionWithName:vertexFunctionName];
        descriptor = CMetalVertexDescriptorHelper::CreateVertexDescriptor(vertexFormat);
        if (descriptor)
            CMetalVertexDescriptorHelper::AttachTangentAttributes(descriptor);
        pipelineState =
            CreatePipelineStateWithFunctions(vertexFunction, fragmentFunction, descriptor, &info);
    }
    if (!pipelineState)
    {
        (*psoFailCount)++;
        if (iLog)
            iLog->Log("MetalShaderManager: PSO creation failed for '%s' — shader will be unavailable at runtime\n",
                      shaderName ? [shaderName UTF8String] : "<unnamed>");
        return 1;
    }

    auto existing = m_shaderNameMap.find(registrationNormalizedKey);
    if (existing != m_shaderNameMap.end())
    {
        ReleaseShaderId(existing->second);
    }

    int shaderId = AllocateShaderId();
    info.shaderClass = eSH_Misc;
    info.needsTangents = layout.needsTangents;
    info.isLoaded = true;
    info.nMaskGen = 0;
    info.shaderWrapper = new CMetalShader(shaderId, this);
    info.vertexFunction = vertexFunction;
    info.fragmentFunction = fragmentFunction;
    info.pipelineState = pipelineState;
    info.vertexDescriptor = descriptor;
    if (uniformArray && [uniformArray isKindOfClass:[NSArray class]])
    {
        for (NSDictionary* uniformDict in uniformArray)
        {
            if (![uniformDict isKindOfClass:[NSDictionary class]])
                continue;
            GeneratedUniformBinding binding;
            NSString* uName = uniformDict[@"name"];
            NSString* uType = uniformDict[@"type"];
            NSString* uSemantic = uniformDict[@"semantic"];
            NSNumber* uArraySize = uniformDict[@"arraySize"];
            if (uName)
                binding.name = [uName UTF8String];
            if (uType)
                binding.type = [uName UTF8String];
            if (uSemantic)
                binding.semantic = [uSemantic UTF8String];
            binding.arraySize = uArraySize ? uArraySize.intValue : 0;
            info.uniformBindings.push_back(binding);
        }
    }
    if (textureArray && [textureArray isKindOfClass:[NSArray class]])
    {
        for (NSDictionary* textureDict in textureArray)
        {
            if (![textureDict isKindOfClass:[NSDictionary class]])
                continue;
            GeneratedTextureBinding binding;
            NSString* tName = textureDict[@"name"];
            NSString* tType = textureDict[@"type"];
            NSString* tSemantic = textureDict[@"semantic"];
            NSNumber* tSlot = textureDict[@"slot"];
            if (tName)
                binding.name = [tName UTF8String];
            if (tType)
                binding.type = [tType UTF8String];
            if (tSemantic)
                binding.semantic = [tSemantic UTF8String];
            binding.slot = tSlot ? tSlot.intValue : static_cast<int>(info.textureBindings.size());
            info.textureBindings.push_back(binding);
        }
    }
    if (directiveArray && [directiveArray isKindOfClass:[NSArray class]])
    {
        for (NSString* directive in directiveArray)
        {
            if (![directive isKindOfClass:[NSString class]])
                continue;
            info.directives.emplace_back([directive UTF8String]);
        }
    }
    if (maskArray && [maskArray isKindOfClass:[NSArray class]])
    {
        for (NSString* mask in maskArray)
        {
            if (![mask isKindOfClass:[NSString class]])
                continue;
            info.maskReferences.emplace_back([mask UTF8String]);
        }
    }

    m_shaders[shaderId] = info;
    m_shaderNameMap[registrationNormalizedKey] = shaderId;

    NSArray* lookupAliases = aliasSrc[@"lookupAliases"];
    if (lookupAliases && [lookupAliases isKindOfClass:[NSArray class]])
    {
        for (id aliasObj in lookupAliases)
        {
            if (![aliasObj isKindOfClass:[NSString class]] || [(NSString*)aliasObj length] == 0)
                continue;
            std::string aliasKey = NormalizeShaderName([(NSString*)aliasObj UTF8String]);
            if (!aliasKey.empty() && aliasKey != registrationNormalizedKey)
                m_shaderNameMap[aliasKey] = shaderId;
        }
    }

    if (iLog)
        iLog->Log("MetalShaderManager: Registered generated shader '%s' (id=%d)\n",
                  [shaderName UTF8String], shaderId);

    return 0;
}

void CMetalShaderManager::LoadGeneratedShaders(id<MTLLibrary> vertexLibrary)
{
    if (!m_renderer || !m_renderer->m_device)
        return;

    m_generatedVertexEntries.clear();

    NSError* error = nil;
    id<MTLLibrary> generatedLibrary = nil;

    NSString* validationDirGen = MetalShaderValidationAssetDirFromEnv();
    if (validationDirGen)
    {
        NSString* genPath = [validationDirGen stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
        generatedLibrary = [m_renderer->m_device newLibraryWithFile:genPath error:&error];
        if (generatedLibrary && iLog)
            iLog->Log("MetalShaderManager: loaded GeneratedShaders.metallib from FARCRY_METAL_VALIDATION_DIR\n");
    }

    NSBundle* bundle = [NSBundle mainBundle];
    if (!generatedLibrary && bundle)
    {
        NSString* resourcePath = [bundle pathForResource:@"GeneratedShaders" ofType:@"metallib"];
        if (resourcePath)
        {
            generatedLibrary = [m_renderer->m_device newLibraryWithFile:resourcePath error:&error];
        }
    }

    if (!generatedLibrary)
    {
        NSString* exePath = [[NSBundle mainBundle] executablePath];
        NSString* exeDir = [exePath stringByDeletingLastPathComponent];
        NSString* metallibPath = [exeDir stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
        generatedLibrary = [m_renderer->m_device newLibraryWithFile:metallibPath error:&error];
        if (!generatedLibrary)
        {
            NSString* sourcePath = [NSString stringWithUTF8String:"RenderDll/XRenderMetal/Generated/GeneratedShaders.metallib"];
            generatedLibrary = [m_renderer->m_device newLibraryWithFile:sourcePath error:&error];
        }
    }

    if (!generatedLibrary)
    {
        if (iLog)
            iLog->Log("MetalShaderManager: GeneratedShaders.metallib not found (%s)\n", error ? [[error localizedDescription] UTF8String] : "unknown error");
        assert(!"MetalShaderManager: GeneratedShaders.metallib not found in bundle or executable directory");
        return;
    }

    m_generatedLibrary = generatedLibrary;

    NSString* manifestPath = nil;
    if (validationDirGen)
    {
        NSString* mpath = [validationDirGen stringByAppendingPathComponent:@"generated_manifest.json"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:mpath])
            manifestPath = mpath;
    }
    if (!manifestPath && bundle)
    {
        manifestPath = [bundle pathForResource:@"generated_manifest" ofType:@"json"];
    }
    if (!manifestPath)
    {
        NSString* exePath = [[NSBundle mainBundle] executablePath];
        NSString* exeDir = [exePath stringByDeletingLastPathComponent];
        NSString* candidate = [exeDir stringByAppendingPathComponent:@"generated_manifest.json"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate])
            manifestPath = candidate;
        else
            manifestPath = [NSString stringWithUTF8String:"RenderDll/XRenderMetal/Generated/generated_manifest.json"];
    }

    NSData* manifestData = manifestPath ? [NSData dataWithContentsOfFile:manifestPath] : nil;
    if (!manifestData)
    {
        if (iLog)
            iLog->Log("MetalShaderManager: Generated shader manifest not found");
        return;
    }

    NSError* jsonError = nil;
    id manifestJson = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&jsonError];
    if (!manifestJson || ![manifestJson isKindOfClass:[NSArray class]])
    {
        if (iLog)
            iLog->Log("MetalShaderManager: Failed to parse generated shader manifest (%s)", jsonError ? [[jsonError localizedDescription] UTF8String] : "unknown error");
        return;
    }

    NSArray* entries = (NSArray*)manifestJson;

    // First pass: cache all generated vertex entries so fragments can reference them.
    // vertexByFuncName is keyed by the Metal function name (entryPoint) and lets the
    // second pass resolve entry[@"vertexEntryPoint"] directly without the heuristic.
    g_missingVertexLogCount = 0;
    g_vertexMatchLogCount = 0;
    size_t matchedFragmentVertexCount = 0;
    size_t missingFragmentVertexCount = 0;
    std::unordered_map<std::string, const GeneratedVertexEntry*> vertexByFuncName;
    // Tracks every entry-point name (bare AND versioned) that appeared for each
    // canonical key.  Used below to register aliases in vertexByFuncName so
    // that a manifest vertexEntryPoint pointing to either form resolves correctly.
    std::unordered_map<std::string, std::vector<std::string>> allEntryPointsByCanonical;

    for (NSDictionary* entry in entries)
    {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;

        NSString* shaderName = entry[@"shader"];
        NSString* normalizedName = entry[@"normalized"];
        NSString* fragmentName = entry[@"entryPoint"];
        if (!fragmentName)
            fragmentName = entry[@"fragment"];
        NSString* stageValue = entry[@"stage"];
        NSArray* vertexAttrMetaArray = entry[@"vertexAttributeMetadata"];

        if (!shaderName || !fragmentName)
            continue;

        std::string normalizedKey;
        if (normalizedName && [normalizedName length] > 0)
            normalizedKey = NormalizeShaderName([normalizedName UTF8String]);
        else
            normalizedKey = NormalizeShaderName([shaderName UTF8String]);
        NSString* loweredStage = stageValue ? [stageValue lowercaseString] : @"fragment";
        if (![loweredStage isEqualToString:@"vertex"])
            continue;

        const std::string canonicalKey = BuildStageAgnosticKey(normalizedKey);
        const std::string thisEntryPoint = NSStringToStdString(fragmentName);

        // Remember every entry-point name seen for this canonical key (bare and
        // versioned alike) — we register them all as aliases after the map is stable.
        allEntryPointsByCanonical[canonicalKey].push_back(thisEntryPoint);

        GeneratedVertexEntry vertexEntry;
        vertexEntry.shaderName = NSStringToStdString(shaderName);
        vertexEntry.normalizedName = normalizedKey;
        vertexEntry.entryPoint = thisEntryPoint;
        vertexEntry.attributes = MetalManifestBuildGeneratedVertexAttributes(vertexAttrMetaArray);
        NSArray* vertexInputsArray = entry[@"vertexInputs"];
        vertexEntry.vertexInputDescs = MetalManifestBuildGeneratedVertexInputs(vertexInputsArray);
        NSArray* vertexOutputsArray = entry[@"vertexOutputs"];
        vertexEntry.outputs = MetalManifestBuildGeneratedVertexOutputs(vertexOutputsArray);
        // When both a versioned (_vs10/_vs20 etc.) and a bare shader map to the
        // same canonical key, the versioned entry must win.  The Dart generator
        // pairs each FS with the versioned VS in the manifest and builds the
        // FS stage_in to match that variant's outputs; if the bare VS were
        // selected at runtime the types would mismatch and PSO creation fails.
        //
        // IMPORTANT: do NOT use (normalizedKey != canonicalKey) here — that is
        // always true for every VS entry because BuildStageAgnosticKey strips the
        // stage prefix ("cgvprog"), making canonicalKey differ from normalizedKey
        // even for bare shaders.  Instead, test whether the normalizedKey itself
        // has an explicit _vsXX suffix, which is the true signal of a versioned VS.
        const bool isVersioned = (StripVertexSuffix(normalizedKey) != normalizedKey);
        const bool slotEmpty =
            m_generatedVertexEntries.find(canonicalKey) ==
            m_generatedVertexEntries.end();
        if (isVersioned || slotEmpty)
        {
            m_generatedVertexEntries[canonicalKey] = std::move(vertexEntry);
            // NOTE: do NOT populate vertexByFuncName here.  Inserting into
            // m_generatedVertexEntries may trigger a rehash that moves all
            // elements, invalidating any pointer stored before the rehash.
            // vertexByFuncName is built in a second scan below, after all VS
            // entries have been inserted and the map layout is stable.
        }
    }

    // Build vertexByFuncName NOW — after all insertions — so no pointer is
    // ever taken from a map that will subsequently rehash.
    // Register EVERY known entry-point alias (bare and versioned) so that
    // manifest vertexEntryPoint values of either form resolve correctly.
    for (auto& [canonKey, eps] : allEntryPointsByCanonical)
    {
        auto it = m_generatedVertexEntries.find(canonKey);
        if (it == m_generatedVertexEntries.end())
            continue;
        for (const std::string& ep : eps)
            vertexByFuncName[ep] = &it->second;
    }

    if (iLog)
    {
        iLog->Log("MetalShaderManager: cached %zu generated vertex programs\n",
                  m_generatedVertexEntries.size());
    }
    else
    {
        fprintf(stderr, "MetalShaderManager: cached %zu generated vertex programs\n",
                m_generatedVertexEntries.size());
    }

    NSMutableDictionary* sampleFragmentByVertexEp = [NSMutableDictionary dictionary];
    for (NSDictionary* scanEntry in entries)
    {
        if (![scanEntry isKindOfClass:[NSDictionary class]])
            continue;
        NSString* st = scanEntry[@"stage"];
        NSString* loweredScan = st ? [st lowercaseString] : @"fragment";
        if ([loweredScan isEqualToString:@"vertex"])
            continue;
        NSString* vepScan = scanEntry[@"vertexEntryPoint"];
        if (!vepScan || [vepScan length] == 0)
            continue;
        if ([sampleFragmentByVertexEp objectForKey:vepScan] == nil)
            [sampleFragmentByVertexEp setObject:scanEntry forKey:vepScan];
    }

    int psoFailCount = 0;

    for (NSDictionary* entry in entries)
    {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;
        NSString* stageValueVs = entry[@"stage"];
        NSString* loweredVs = stageValueVs ? [stageValueVs lowercaseString] : @"fragment";
        if (![loweredVs isEqualToString:@"vertex"])
            continue;

        NSString* normalizedNameVs = entry[@"normalized"];
        NSString* shaderNameVs = entry[@"shader"];
        if (!shaderNameVs)
            continue;
        std::string vertexRegKey;
        if (normalizedNameVs && [normalizedNameVs length] > 0)
            vertexRegKey = NormalizeShaderName([normalizedNameVs UTF8String]);
        else
            vertexRegKey = NormalizeShaderName([shaderNameVs UTF8String]);
        if (vertexRegKey.empty())
            continue;
        if (m_shaderNameMap.find(vertexRegKey) != m_shaderNameMap.end())
            continue;

        NSString* vep = entry[@"entryPoint"];
        if (!vep || ![vep length])
            vep = entry[@"fragment"];
        if (!vep || ![vep length])
            continue;

        NSDictionary* pairedFrag = [sampleFragmentByVertexEp objectForKey:vep];
        if (!pairedFrag)
        {
            if (g_orphanStandaloneVertexLogCount < kMaxMissingVertexLogs)
            {
                if (iLog)
                    iLog->Log(
                        "MetalShaderManager: no fragment references vertexEntryPoint '%s' — skipping standalone VS '%s'\n",
                        [vep UTF8String],
                        [shaderNameVs UTF8String]);
                else
                    fprintf(stderr,
                            "MetalShaderManager: no fragment references vertexEntryPoint '%s' — skipping standalone VS '%s'\n",
                            [vep UTF8String],
                            [shaderNameVs UTF8String]);
                g_orphanStandaloneVertexLogCount++;
            }
            continue;
        }

        int rcVs = TryRegisterOneManifestPipeline(
            pairedFrag,
            entry,
            vertexRegKey,
            generatedLibrary,
            vertexLibrary,
            vertexByFuncName,
            &psoFailCount,
            false,
            &matchedFragmentVertexCount,
            &missingFragmentVertexCount);
        if (rcVs == 2)
            return;
    }

    // Second pass: build fragment pipelines
    for (NSDictionary* entry in entries)
    {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;

        NSString* shaderName = entry[@"shader"];
        NSString* normalizedName = entry[@"normalized"];
        NSString* fragmentName = entry[@"entryPoint"];
        if (!fragmentName)
            fragmentName = entry[@"fragment"];
        NSString* stageValue = entry[@"stage"];
        if (!shaderName || !fragmentName)
            continue;

        std::string normalizedKey;
        if (normalizedName && [normalizedName length] > 0)
            normalizedKey = NormalizeShaderName([normalizedName UTF8String]);
        else
            normalizedKey = NormalizeShaderName([shaderName UTF8String]);
        NSString* loweredStage = stageValue ? [stageValue lowercaseString] : @"fragment";
        if ([loweredStage isEqualToString:@"vertex"])
            continue;

        int rc = TryRegisterOneManifestPipeline(
            entry,
            nil,
            normalizedKey,
            generatedLibrary,
            vertexLibrary,
            vertexByFuncName,
            &psoFailCount,
            true,
            &matchedFragmentVertexCount,
            &missingFragmentVertexCount);
        if (rc == 2)
            return;
    }

    if (iLog)
    {
        iLog->Log("MetalShaderManager: fragments matched to generated vertices=%zu, missing=%zu\n",
                  matchedFragmentVertexCount,
                  missingFragmentVertexCount);
        if (psoFailCount > 0)
            iLog->Log("MetalShaderManager: WARNING — %d generated PSO(s) failed to create; those shaders will fall back to 'basic'\n",
                      psoFailCount);
    }
    else
    {
        fprintf(stderr, "MetalShaderManager: fragments matched to generated vertices=%zu, missing=%zu\n",
                matchedFragmentVertexCount,
                missingFragmentVertexCount);
    }
    if (psoFailCount > 0)
    {
        if (iLog)
            iLog->Log("MetalShaderManager: WARNING — %d generated PSO(s) failed to create; "
                      "those shaders will fall back to 'basic'. Check the engine log for shader names.\n",
                      psoFailCount);
        else
            fprintf(stderr, "MetalShaderManager: WARNING — %d generated PSO(s) failed.\n",
                    psoFailCount);
    }
    // Hard assert restored once psoFailCount is confirmed 0 after pair-mismatch fixes.
    // assert(psoFailCount == 0 &&
    //        "LoadGeneratedShaders: one or more generated PSOs failed — check the engine log");

    m_lastGeneratedShaderPsoFailureCount = psoFailCount;
}

id<MTLRenderPipelineState> CMetalShaderManager::CreatePipelineStateWithFunctions(
    id<MTLFunction> vertexFunction,
    id<MTLFunction> fragmentFunction,
    MTLVertexDescriptor* vertexDescriptor,
    ShaderInfo* shaderInfo)
{
    assert(vertexFunction != nil && "CreatePipelineStateWithFunctions: vertexFunction cannot be nil");
    assert(fragmentFunction != nil && "CreatePipelineStateWithFunctions: fragmentFunction cannot be nil");
    assert(vertexDescriptor != nil && "CreatePipelineStateWithFunctions: vertexDescriptor cannot be nil");
    
    assert(m_renderer != nullptr && "CreatePipelineStateWithFunctions: renderer cannot be null!");
    assert(m_renderer->m_device != nil && "CreatePipelineStateWithFunctions: Metal device cannot be nil!");
    
    if (!m_renderer || !m_renderer->m_device)
        return nil;
    
    MTLPixelFormat colorFormat = MTLPixelFormatBGRA8Unorm;
    MTLPixelFormat depthFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    bool blendEnabled = true;
    MTLBlendFactor srcBlend = MTLBlendFactorSourceAlpha;
    MTLBlendFactor dstBlend = MTLBlendFactorOneMinusSourceAlpha;
    MTLBlendOperation blendOp = MTLBlendOperationAdd;
    MTLBlendFactor srcAlphaBlend = srcBlend;
    MTLBlendFactor dstAlphaBlend = dstBlend;
    MTLBlendOperation alphaOp = blendOp;
    uint8_t colorWriteMask = 0xF;
    uint64_t renderStateHash = 0;

    if (shaderInfo)
    {
        blendEnabled = shaderInfo->blendEnabled;
        srcBlend = shaderInfo->sourceBlendFactor;
        dstBlend = shaderInfo->destinationBlendFactor;
        blendOp = shaderInfo->blendOperation;
        srcAlphaBlend = shaderInfo->sourceAlphaBlendFactor;
        dstAlphaBlend = shaderInfo->destinationAlphaBlendFactor;
        alphaOp = shaderInfo->alphaBlendOperation;
        colorWriteMask = shaderInfo->colorWriteMask;
        renderStateHash = BuildRenderStateHash(*shaderInfo);
    }
    else
    {
        ShaderInfo temp;
        temp.blendEnabled = blendEnabled;
        temp.sourceBlendFactor = srcBlend;
        temp.destinationBlendFactor = dstBlend;
        temp.blendOperation = blendOp;
        temp.sourceAlphaBlendFactor = srcAlphaBlend;
        temp.destinationAlphaBlendFactor = dstAlphaBlend;
        temp.alphaBlendOperation = alphaOp;
        temp.colorWriteMask = colorWriteMask;
        renderStateHash = BuildRenderStateHash(temp);
    }

    MetalPipelineStateKey key;
    key.vertexFunctionHash = (uint64_t)vertexFunction;
    key.fragmentFunctionHash = (uint64_t)fragmentFunction;
    key.vertexFormatHash = 0;
    key.renderStateHash = renderStateHash;
    key.colorPixelFormat = colorFormat;
    key.depthPixelFormat = depthFormat;
    
    if (m_renderer->m_stateCache && vertexFunction && fragmentFunction && vertexDescriptor) // Only cache if functions are valid
    {
        id<MTLRenderPipelineState> cachedState = m_renderer->m_stateCache->GetOrCreatePipelineState(
                key, vertexFunction, fragmentFunction, vertexDescriptor);

        if (cachedState)
            return cachedState;
    }
    
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.vertexDescriptor = vertexDescriptor;
    
    descriptor.colorAttachments[0].pixelFormat = colorFormat;
    descriptor.colorAttachments[0].blendingEnabled = blendEnabled ? YES : NO;
    if (blendEnabled)
    {
        descriptor.colorAttachments[0].sourceRGBBlendFactor = srcBlend;
        descriptor.colorAttachments[0].destinationRGBBlendFactor = dstBlend;
        descriptor.colorAttachments[0].rgbBlendOperation = blendOp;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = srcAlphaBlend;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = dstAlphaBlend;
        descriptor.colorAttachments[0].alphaBlendOperation = alphaOp;
    }
    MTLColorWriteMask writeMask = 0;
    if (colorWriteMask & 0x1)
        writeMask |= MTLColorWriteMaskRed;
    if (colorWriteMask & 0x2)
        writeMask |= MTLColorWriteMaskGreen;
    if (colorWriteMask & 0x4)
        writeMask |= MTLColorWriteMaskBlue;
    if (colorWriteMask & 0x8)
        writeMask |= MTLColorWriteMaskAlpha;
    descriptor.colorAttachments[0].writeMask = writeMask;
 
    descriptor.depthAttachmentPixelFormat = depthFormat;
    descriptor.stencilAttachmentPixelFormat = depthFormat;
    
    m_lastPipelineHadTangentMismatch = false;

    NSError* error = nil;
    id<MTLRenderPipelineState> pipelineState = 
        [m_renderer->m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    
    if (!pipelineState)
    {
        const char* vsName = vertexFunction && [vertexFunction label]
            ? [[vertexFunction label] UTF8String]
            : "<unnamed>";
        const char* fsName = fragmentFunction && [fragmentFunction label]
            ? [[fragmentFunction label] UTF8String]
            : "<unnamed>";
        const char* shaderName = (shaderInfo && !shaderInfo->name.empty())
            ? shaderInfo->name.c_str()
            : "<unnamed>";
        if (error)
        {
            const char* errorText = [[error localizedDescription] UTF8String];
            iLog->Log("CreatePipelineState failed for shader '%s' VS '%s' / FS '%s': %s\n", shaderName, vsName, fsName, errorText);
            fprintf(stderr, "CreatePipelineState failed for shader '%s' VS '%s' / FS '%s': %s\n", shaderName, vsName, fsName, errorText);
            NSString* lowerDesc = [[error localizedDescription] lowercaseString];
            if (lowerDesc &&
                ([lowerDesc containsString:@"tnormal"] ||
                 [lowerDesc containsString:@"tangent"] ||
                 [lowerDesc containsString:@"binormal"]))
            {
                m_lastPipelineHadTangentMismatch = true;
                if (iLog)
                {
                    iLog->Log("CreatePipelineState: Detected tangent attribute mismatch for shader '%s'", shaderName);
                }
            }
        }
        else
        {
            iLog->Log("CreatePipelineState failed for shader '%s' VS '%s' / FS '%s' with unknown error\n", shaderName, vsName, fsName);
            fprintf(stderr, "CreatePipelineState failed for shader '%s' VS '%s' / FS '%s' with unknown error\n", shaderName, vsName, fsName);
        }
        
        NSString* compilerError = error.userInfo[@"MTLCompilerErrorKey"];
        if (compilerError)
        {
            const char* errorDetails = [compilerError UTF8String];
            iLog->Log("Metal compiler output for shader '%s':\n%s\n", shaderName, errorDetails);
            fprintf(stderr, "Metal compiler output for shader '%s':\n%s\n", shaderName, errorDetails);
        }
    }

    if (!pipelineState && error)
    {
        iLog->Log("CreatePipelineStateWithFunctions: Unable to build pipeline state (%s)\n",
                  [[error localizedDescription] UTF8String]);
    }
    
    return pipelineState;
}

id<MTLRenderPipelineState> CMetalShaderManager::CreatePipelineState(
    id<MTLFunction> vertexFunction,
    id<MTLFunction> fragmentFunction,
    MTLVertexDescriptor* vertexDescriptor)
{
    assert(vertexFunction != nil && "CreatePipelineState: vertexFunction cannot be nil!");
    assert(fragmentFunction != nil && "CreatePipelineState: fragmentFunction cannot be nil!");
    assert(vertexDescriptor != nil && "CreatePipelineState: vertexDescriptor cannot be nil!");
 
    return CreatePipelineStateWithFunctions(vertexFunction, fragmentFunction, vertexDescriptor, nullptr);
}

void CMetalShaderManager::SetShaderUniforms(id<MTLRenderCommandEncoder> encoder, 
                                           const SShaderParam& params)
{
    assert(encoder != nil && "SetShaderUniforms: encoder cannot be nil!");
    assert(m_renderer != nullptr && "SetShaderUniforms: renderer cannot be null!");
    
    if (!encoder || !m_renderer)
        return;
    
    m_renderer->UpdateUniformBuffer();
    
    if (m_renderer->m_uniformBuffer)
    {
        [encoder setVertexBuffer:m_renderer->m_uniformBuffer offset:0 atIndex:kMetalVertexUniformSlot];
        [encoder setFragmentBuffer:m_renderer->m_uniformBuffer offset:0 atIndex:kMetalFragmentUniformSlot];
    }
    if (m_renderer->m_materialBuffer)
    {
        [encoder setFragmentBuffer:m_renderer->m_materialBuffer offset:0 atIndex:kMetalMaterialSlot];
    }
}

int CMetalShaderManager::AllocateShaderId()
{
    int id = m_nextShaderId++;
    assert(id > 0 && "AllocateShaderId: shader ID must be positive!");
    assert(m_nextShaderId > id && "AllocateShaderId: shader ID counter overflow!");
    return id;
}

void CMetalShaderManager::ReleaseShaderId(int id)
{
    assert(id > 0 && "ReleaseShaderId: shader ID must be positive!");
    
    auto it = m_shaders.find(id);
    if (it != m_shaders.end())
    {
        ShaderInfo& info = it->second;
        info.shaderWrapper = nullptr;
        
        std::string nameToRemove = info.name;
        m_shaders.erase(it);
        
        auto nameIt = m_shaderNameMap.find(nameToRemove);
        if (nameIt != m_shaderNameMap.end() && nameIt->second == id)
        {
            m_shaderNameMap.erase(nameIt);
        }
    }
}

void CMetalShaderManager::ClearAllShaders()
{
    for (auto& pair : m_shaders)
    {
        ShaderInfo& info = pair.second;
        if (info.shaderWrapper)
        {
            info.shaderWrapper->m_manager = nullptr;
            info.shaderWrapper->Release(true);
            info.shaderWrapper = nullptr;
        }
    }
    
    m_shaders.clear();
    m_shaderNameMap.clear();
    m_nextShaderId = 1;
    m_currentShaderId = 0;
    m_currentPipelineState = nil;
}

void CMetalShaderManager::ShareCacheWith(CMetalShaderManager* other)
{
    if (!other || other == this)
        return;
    
    for (const auto& shaderPair : other->m_shaders) {
        const ShaderInfo& shaderInfo = shaderPair.second;
        
        if (!shaderInfo.name.empty()) {
            auto nameIt = m_shaderNameMap.find(shaderInfo.name);
            if (nameIt == m_shaderNameMap.end()) {
                int newShaderId = AllocateShaderId();
                ShaderInfo info = shaderInfo;
                info.shaderWrapper = new CMetalShader(newShaderId, this);
                m_shaders[newShaderId] = info;
                m_shaderNameMap[shaderInfo.name] = newShaderId;
            }
        }
    }
    
    for (const auto& shaderPair : m_shaders) {
        const ShaderInfo& shaderInfo = shaderPair.second;
        
        if (!shaderInfo.name.empty()) {
            auto nameIt = other->m_shaderNameMap.find(shaderInfo.name);
            if (nameIt == other->m_shaderNameMap.end()) {
                int newShaderId = other->AllocateShaderId();
                ShaderInfo info = shaderInfo;
                info.shaderWrapper = new CMetalShader(newShaderId, other);
                other->m_shaders[newShaderId] = info;
                other->m_shaderNameMap[shaderInfo.name] = newShaderId;
            }
        }
    }
}

int CMetalShaderManager::GetShaderCount() const
{
    return static_cast<int>(m_shaders.size());
}

void CMetalShaderManager::SetGlobalShaderTemplateId(int nTemplateId)
{
    m_globalShaderTemplateId = nTemplateId;
}

int CMetalShaderManager::GetGlobalShaderTemplateId() const
{
    return m_globalShaderTemplateId;
}

void CMetalShaderManager::EF_EnableHeatVision(bool bEnable)
{
    if (m_renderer)
        m_renderer->CRenderer::EF_EnableHeatVision(bEnable);
    m_heatVisionEnabled = bEnable;
}

bool CMetalShaderManager::EF_GetHeatVision()
{
    if (m_renderer)
        return m_renderer->CRenderer::EF_GetHeatVision();
    return m_heatVisionEnabled;
}

void CMetalShaderManager::EF_PolygonOffset(bool bEnable, float fFactor, float fUnits)
{
    assert(m_renderer != nullptr && "EF_PolygonOffset: renderer cannot be null!");
    
    if (!m_renderer || !m_renderer->m_renderEncoder)
        return;
    
    if (bEnable)
    {
        [m_renderer->m_renderEncoder setDepthBias:fUnits slopeScale:fFactor clamp:0.0f];
    }
    else
    {
        [m_renderer->m_renderEncoder setDepthBias:0.0f slopeScale:0.0f clamp:0.0f];
    }
}

id<MTLRenderPipelineState> CMetalShaderManager::GetPipelineStateForShader(const char* shaderName)
{
    assert(shaderName != nullptr && "GetPipelineStateForShader: shaderName cannot be null!");
    
    if (!shaderName)
        return nil;
    
    auto it = m_shaderNameMap.find(shaderName);
    if (it != m_shaderNameMap.end())
    {
        int shaderId = it->second;
        auto shaderIt = m_shaders.find(shaderId);
        if (shaderIt != m_shaders.end())
        {
            return shaderIt->second.pipelineState;
        }
    }
    
    return nil;
}

id<MTLRenderPipelineState> CMetalShaderManager::GetPipelineStateForFormat(int vertexFormat)
{
    const char* shaderName = "colortex";
    
    switch (vertexFormat)
    {
        case VERTEX_FORMAT_P3F:
            shaderName = "simple";
            break;
        case VERTEX_FORMAT_P3F_COL4UB:
            shaderName = "color";
            break;
        case VERTEX_FORMAT_P3F_COL4UB_TEX2F:
        case VERTEX_FORMAT_P3F_N_COL4UB_TEX2F:
            shaderName = "colortex";
            break;
        default:
            shaderName = "basic";
            break;
    }
    
    return GetPipelineStateForShader(shaderName);
}

#endif

