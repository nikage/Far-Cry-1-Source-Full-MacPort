////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalShaderManager.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: Metal shader manager implementation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalShaderManager.m"
#include "MetalBaseRenderer.m"
#include "MetalTextureManager.m"

#if DEBUG
int g_metalStartupMissingShaders = 0;
#endif
#include "MetalRenderElements.m"  // For Metal render element classes
#include "MetalVertexDescriptor.m"  // For CMetalVertexDescriptorHelper
#include <Cocoa/Cocoa.h>
#include <cassert>
#include <iostream>
#include <algorithm>
#include <functional>
#include <cctype>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <strings.h>


// Render element implementations moved to MetalRenderElements.cpp to avoid duplicates
// Constructor and destructor are in MetalShaderLoader.cpp to avoid duplicates

static void ConvertDOSToUnixName(char* dst, const char* src)
{
    while (*src)
    {
        if (*src == '\\')
            *dst = '/';
        else
            *dst = *src;
        dst++;
        src++;
    }
    *dst = 0;
}

static const char* GetExtension(const char* filename)
{
    if (!filename)
        return nullptr;
    
    const char* ext = nullptr;
    const char* p = filename;
    while (*p)
    {
        if (*p == '.')
            ext = p;
        p++;
    }
    return ext;
}

static std::string NormalizeShaderName(const char* name)
{
    if (!name)
        return "";
    
    char normalized[256];
    strncpy(normalized, name, sizeof(normalized) - 1);
    normalized[sizeof(normalized) - 1] = 0;
    
    ConvertDOSToUnixName(normalized, normalized);
    ::strlwr(normalized);
    
    return std::string(normalized);
}

static void ShaderLoadFatal(const char* op, const char* requestedName, const char* lookupKey, EShClass Class, int flags)
{
    const char* req = (requestedName && requestedName[0]) ? requestedName : "";
    const char* lu = (lookupKey && lookupKey[0]) ? lookupKey : req;
    if (iLog)
        iLog->LogError("FATAL %s: required shader not registered (EF_SYSTEM). name='%s' lookup='%s' class=%d flags=0x%x",
                        op, req, lu, (int)Class, flags);
    else
        fprintf(stderr, "FATAL %s: required shader not registered (EF_SYSTEM). name='%s' lookup='%s'\n", op, req, lu);
    assert(!"MetalShaderManager: required shader missing (manifest / Aliases.txt / lookupAliases)");
    std::abort();
}

static void ShaderLoadFatalItem(const char* name, const char* templName, EShClass Class, int flags)
{
    const char* n = name ? name : "";
    const char* t = templName ? templName : "";
    if (iLog)
        iLog->LogError("FATAL EF_LoadShaderItem: required shader not registered (EF_SYSTEM). name='%s' templ='%s' class=%d flags=0x%x",
                        n, t, (int)Class, flags);
    else
        fprintf(stderr, "FATAL EF_LoadShaderItem: required shader not registered (EF_SYSTEM). name='%s' templ='%s'\n", n, t);
    assert(!"MetalShaderManager: required shader missing (manifest / Aliases.txt / lookupAliases)");
    std::abort();
}

namespace
{
const SShaderParam* FindShaderParam(const TArray<SShaderParam>& params, const std::string& name)
{
    if (name.empty())
        return nullptr;
    for (int i = 0; i < params.Num(); ++i)
    {
        const SShaderParam& param = params[i];
        if (param.m_Name[0] == '\0')
            continue;
#if defined(__APPLE__)
        if (strcasecmp(param.m_Name, name.c_str()) == 0)
            return &param;
#else
        if (_stricmp(param.m_Name, name.c_str()) == 0)
            return &param;
#endif
    }
    return nullptr;
}

int FindShaderParamIndex(const TArray<SShaderParam>& params, const std::string& name)
{
    if (name.empty())
        return -1;
    for (int i = 0; i < params.Num(); ++i)
    {
        const SShaderParam& param = params[i];
        if (param.m_Name[0] == '\0')
            continue;
#if defined(__APPLE__)
        if (strcasecmp(param.m_Name, name.c_str()) == 0)
            return i;
#else
        if (_stricmp(param.m_Name, name.c_str()) == 0)
            return i;
#endif
    }
    return -1;
}

void ConvertShaderParamToFloat4(const SShaderParam& param, float(&out)[4])
{
    switch (param.m_Type)
    {
    case eType_FLOAT:
        out[0] = out[1] = out[2] = param.m_Value.m_Float;
        out[3] = 1.0f;
        break;
    case eType_INT:
    case eType_SHORT:
        out[0] = out[1] = out[2] = static_cast<float>(param.m_Value.m_Int);
        out[3] = 1.0f;
        break;
    case eType_BYTE:
        out[0] = out[1] = out[2] = static_cast<float>(param.m_Value.m_Byte);
        out[3] = 1.0f;
        break;
    case eType_BOOL:
        out[0] = out[1] = out[2] = param.m_Value.m_Bool ? 1.0f : 0.0f;
        out[3] = 1.0f;
        break;
    case eType_VECTOR:
        out[0] = param.m_Value.m_Vector[0];
        out[1] = param.m_Value.m_Vector[1];
        out[2] = param.m_Value.m_Vector[2];
        out[3] = 0.0f;
        break;
    case eType_FCOLOR:
        out[0] = param.m_Value.m_Color[0];
        out[1] = param.m_Value.m_Color[1];
        out[2] = param.m_Value.m_Color[2];
        out[3] = param.m_Value.m_Color[3];
        break;
    default:
        out[0] = out[1] = out[2] = 0.0f;
        out[3] = 1.0f;
        break;
    }
}

void FillDefaultUniform(const CMetalShaderManager::GeneratedUniformBinding& binding, float(&out)[4])
{
    out[0] = out[1] = out[2] = 0.0f;
    out[3] = 1.0f;
    std::string lowerType = binding.type;
    std::transform(lowerType.begin(), lowerType.end(), lowerType.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (lowerType.find("float4") != std::string::npos)
    {
        out[0] = out[1] = out[2] = out[3] = 1.0f;
    }
    else if (lowerType.find("float3") != std::string::npos)
    {
        out[0] = out[1] = out[2] = 1.0f;
    }
    else if (lowerType.find("float2") != std::string::npos)
    {
        out[0] = out[1] = 1.0f;
    }
    else if (lowerType.find("float") != std::string::npos)
    {
        out[0] = out[1] = out[2] = 0.0f;
        out[3] = 1.0f;
    }
}

int SemanticToTextureSlot(const std::string& semantic, size_t fallbackIndex)
{
    if (!semantic.empty())
    {
        std::string lower = semantic;
        std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        const std::string tag = "texunit";
        const size_t pos = lower.find(tag);
        if (pos != std::string::npos)
        {
            const char* digits = lower.c_str() + pos + tag.size();
            int slot = std::atoi(digits);
            if (slot >= 0)
                return slot;
        }
    }
    return static_cast<int>(fallbackIndex);
}

size_t CombineHash(size_t seed, size_t value)
{
    seed ^= value + 0x9e3779b97f4a7c15ULL + (seed << 6) + (seed >> 2);
    return seed;
}

size_t ComputePublicParamSignature(const TArray<SShaderParam>& params)
{
    size_t hash = static_cast<size_t>(params.Num());
    std::hash<std::string> stringHasher;
    for (int i = 0; i < params.Num(); ++i)
    {
        const SShaderParam& param = params[i];
        if (param.m_Name[0] == '\0')
            continue;
        hash = CombineHash(hash, stringHasher(std::string(param.m_Name)));
        hash = CombineHash(hash, static_cast<size_t>(param.m_Type));
    }
    return hash;
}

struct UniformLayoutInfo
{
    UniformScalarType scalarType;
    int rows;
    int columns;
    int arrayCount;
    size_t elementSize;
    size_t alignedSize;
};

static size_t AlignSize(size_t value, size_t alignment)
{
    const size_t mask = alignment - 1;
    return (value + mask) & ~mask;
}

static UniformLayoutInfo ParseUniformLayout(const CMetalShaderManager::GeneratedUniformBinding& binding)
{
    UniformLayoutInfo info;
    info.scalarType = UniformScalarType::Float;
    info.rows = 1;
    info.columns = 1;
    info.arrayCount = binding.arraySize > 0 ? binding.arraySize : 1;
    std::string lowerType = binding.type;
    std::transform(lowerType.begin(), lowerType.end(), lowerType.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (lowerType.find("bool") != std::string::npos)
        info.scalarType = UniformScalarType::Bool;
    else if (lowerType.find("int") != std::string::npos)
        info.scalarType = UniformScalarType::Int;
    int numbers[2] = {0, 0};
    int numberIndex = 0;
    for (char ch : lowerType)
    {
        if (ch >= '0' && ch <= '9')
        {
            numbers[numberIndex] = numbers[numberIndex] * 10 + (ch - '0');
        }
        else if (ch == 'x' && numberIndex == 0)
        {
            numberIndex = 1;
        }
    }
    if (numbers[0] > 0 && numbers[1] > 0)
    {
        info.rows = numbers[0];
        info.columns = numbers[1];
    }
    else if (numbers[0] > 0)
    {
        info.columns = numbers[0];
    }
    size_t componentCount = static_cast<size_t>(info.rows) * static_cast<size_t>(info.columns);
    if (componentCount == 0)
        componentCount = 1;
    size_t scalarSize = sizeof(float);
    if (info.scalarType == UniformScalarType::Int || info.scalarType == UniformScalarType::Bool)
        scalarSize = sizeof(int32_t);
    info.elementSize = componentCount * scalarSize;
    info.alignedSize = AlignSize(info.elementSize, 16);
    return info;
}

static UniformValueSource EvaluateUniformIdentifier(const std::string& identifier)
{
    if (identifier.empty())
        return UniformValueSource::ShaderParam;
    if (identifier.find("modelviewproj") != std::string::npos || identifier.find("worldviewproj") != std::string::npos || identifier == "mvp")
        return UniformValueSource::RendererModelViewProj;
    if (identifier.find("model") != std::string::npos || identifier.find("world") != std::string::npos)
        return UniformValueSource::RendererModel;
    if (identifier.find("view") != std::string::npos && identifier.find("proj") == std::string::npos)
        return UniformValueSource::RendererView;
    if (identifier.find("proj") != std::string::npos)
        return UniformValueSource::RendererProjection;
    if (identifier.find("camerapos") != std::string::npos || identifier.find("eye") != std::string::npos || identifier.find("viewpos") != std::string::npos)
        return UniformValueSource::RendererCameraPos;
    if (identifier.find("lightpos") != std::string::npos)
        return UniformValueSource::RendererLightPos;
    if (identifier.find("lightcolor") != std::string::npos || identifier.find("lightcolour") != std::string::npos)
        return UniformValueSource::RendererLightColor;
    if (identifier.find("clipplane") != std::string::npos)
        return UniformValueSource::RendererClipPlane;
    if (identifier.find("clipenabled") != std::string::npos || identifier.find("clip_enable") != std::string::npos)
        return UniformValueSource::RendererClipEnabled;
    if (identifier.find("cliprefract") != std::string::npos)
        return UniformValueSource::RendererClipRefract;
    if (identifier.find("time") != std::string::npos)
        return UniformValueSource::RendererTime;
    if (identifier.find("globalfogcolor") != std::string::npos
        || identifier.find("fogcolor") != std::string::npos
        || identifier.find("fog_color") != std::string::npos)
        return UniformValueSource::RendererGlobalFogColor;
    return UniformValueSource::ShaderParam;
}

static UniformValueSource DetermineUniformSource(const CMetalShaderManager::GeneratedUniformBinding& binding)
{
    std::string normalizedName = NormalizeShaderName(binding.name.c_str());
    UniformValueSource fromName = EvaluateUniformIdentifier(normalizedName);
    if (fromName != UniformValueSource::ShaderParam)
        return fromName;
    if (!binding.semantic.empty())
    {
        std::string normalizedSemantic = NormalizeShaderName(binding.semantic.c_str());
        return EvaluateUniformIdentifier(normalizedSemantic);
    }
    return UniformValueSource::ShaderParam;
}

static size_t GetComponentCount(const CMetalShaderManager::ShaderInfo::UniformRuntimeBinding& binding)
{
    size_t count = static_cast<size_t>(binding.rows) * static_cast<size_t>(binding.columns);
    return count == 0 ? 1 : count;
}

static void WriteDefaultUniform(const CMetalShaderManager::ShaderInfo::UniformRuntimeBinding& binding, uint8_t* dst)
{
    size_t componentCount = GetComponentCount(binding);
    if (binding.scalarType == UniformScalarType::Float)
    {
        float* out = reinterpret_cast<float*>(dst);
        for (size_t i = 0; i < componentCount; ++i)
            out[i] = 0.0f;
        if (binding.rows > 1 && binding.columns > 1)
        {
            const size_t rows = static_cast<size_t>(binding.rows);
            const size_t cols = static_cast<size_t>(binding.columns);
            size_t diagCount = (rows < cols) ? rows : cols;
            for (size_t i = 0; i < diagCount; ++i)
                out[i * binding.columns + i] = 1.0f;
        }
        else if (componentCount > 0)
        {
            out[componentCount - 1] = 1.0f;
        }
    }
    else if (binding.scalarType == UniformScalarType::Int)
    {
        int32_t* out = reinterpret_cast<int32_t*>(dst);
        for (size_t i = 0; i < componentCount; ++i)
            out[i] = 0;
    }
    else
    {
        uint32_t* out = reinterpret_cast<uint32_t*>(dst);
        for (size_t i = 0; i < componentCount; ++i)
            out[i] = 0;
    }
}

static void ExtractShaderParamValues(const SShaderParam& param, std::vector<float>& values)
{
    switch (param.m_Type)
    {
    case eType_FLOAT:
        if (!values.empty())
            values[0] = param.m_Value.m_Float;
        break;
    case eType_INT:
        if (!values.empty())
            values[0] = static_cast<float>(param.m_Value.m_Int);
        break;
    case eType_SHORT:
        if (!values.empty())
            values[0] = static_cast<float>(param.m_Value.m_Short);
        break;
    case eType_BYTE:
        if (!values.empty())
            values[0] = static_cast<float>(param.m_Value.m_Byte);
        break;
    case eType_BOOL:
        if (!values.empty())
            values[0] = param.m_Value.m_Bool ? 1.0f : 0.0f;
        break;
    case eType_VECTOR:
        for (size_t i = 0; i < values.size() && i < 3; ++i)
            values[i] = param.m_Value.m_Vector[i];
        if (values.size() > 3)
            values[3] = 1.0f;
        break;
    case eType_FCOLOR:
        for (size_t i = 0; i < values.size() && i < 4; ++i)
            values[i] = param.m_Value.m_Color[i];
        break;
    default:
        break;
    }
}

static void WriteShaderParamUniform(const CMetalShaderManager::ShaderInfo::UniformRuntimeBinding& binding, const SShaderParam& param, uint8_t* dst)
{
    size_t componentCount = GetComponentCount(binding);
    if (binding.scalarType == UniformScalarType::Float)
    {
        std::vector<float> values(componentCount, 0.0f);
        ExtractShaderParamValues(param, values);
        float* out = reinterpret_cast<float*>(dst);
        for (size_t i = 0; i < componentCount; ++i)
            out[i] = values[i];
    }
    else if (binding.scalarType == UniformScalarType::Int)
    {
        std::vector<float> values(componentCount, 0.0f);
        ExtractShaderParamValues(param, values);
        int32_t* out = reinterpret_cast<int32_t*>(dst);
        for (size_t i = 0; i < componentCount; ++i)
            out[i] = static_cast<int32_t>(values[i]);
    }
    else
    {
        std::vector<float> values(componentCount, 0.0f);
        ExtractShaderParamValues(param, values);
        uint32_t* out = reinterpret_cast<uint32_t*>(dst);
        for (size_t i = 0; i < componentCount; ++i)
            out[i] = values[i] != 0.0f ? 1u : 0u;
    }
}

static void WriteRendererUniform(const CMetalShaderManager::ShaderInfo::UniformRuntimeBinding& binding, uint8_t* dst, CMetalBaseRenderer* renderer)
{
    if (!renderer)
    {
        WriteDefaultUniform(binding, dst);
        return;
    }
    size_t componentCount = GetComponentCount(binding);
    if (binding.scalarType == UniformScalarType::Float)
    {
        float* out = reinterpret_cast<float*>(dst);
        for (size_t i = 0; i < componentCount; ++i)
            out[i] = 0.0f;
        switch (binding.source)
        {
        case UniformValueSource::RendererModelViewProj:
        {
            Matrix44 matrix = renderer->GetUniformModelViewProjection();
            const float* src = reinterpret_cast<const float*>(&matrix);
            for (size_t i = 0; i < componentCount && i < 16; ++i)
                out[i] = src[i];
            break;
        }
        case UniformValueSource::RendererModel:
        {
            Matrix44 matrix = renderer->GetUniformModelMatrix();
            const float* src = reinterpret_cast<const float*>(&matrix);
            for (size_t i = 0; i < componentCount && i < 16; ++i)
                out[i] = src[i];
            break;
        }
        case UniformValueSource::RendererView:
        {
            Matrix44 matrix = renderer->GetUniformViewMatrix();
            const float* src = reinterpret_cast<const float*>(&matrix);
            for (size_t i = 0; i < componentCount && i < 16; ++i)
                out[i] = src[i];
            break;
        }
        case UniformValueSource::RendererProjection:
        {
            Matrix44 matrix = renderer->GetUniformProjectionMatrix();
            const float* src = reinterpret_cast<const float*>(&matrix);
            for (size_t i = 0; i < componentCount && i < 16; ++i)
                out[i] = src[i];
            break;
        }
        case UniformValueSource::RendererCameraPos:
        {
            Vec3 value = renderer->GetUniformCameraPosition();
            if (componentCount > 0)
                out[0] = value.x;
            if (componentCount > 1)
                out[1] = value.y;
            if (componentCount > 2)
                out[2] = value.z;
            if (componentCount > 3)
                out[3] = 1.0f;
            break;
        }
        case UniformValueSource::RendererLightPos:
        {
            Vec3 value = renderer->GetUniformLightPosition();
            if (componentCount > 0)
                out[0] = value.x;
            if (componentCount > 1)
                out[1] = value.y;
            if (componentCount > 2)
                out[2] = value.z;
            if (componentCount > 3)
                out[3] = 1.0f;
            break;
        }
        case UniformValueSource::RendererLightColor:
        {
            Vec3 value = renderer->GetUniformLightColor();
            if (componentCount > 0)
                out[0] = value.x;
            if (componentCount > 1)
                out[1] = value.y;
            if (componentCount > 2)
                out[2] = value.z;
            if (componentCount > 3)
                out[3] = 1.0f;
            break;
        }
        case UniformValueSource::RendererClipPlane:
        {
            float clip[4] = {0.0f, 0.0f, 0.0f, 0.0f};
            renderer->GetUniformClipPlane(clip);
            for (size_t i = 0; i < componentCount && i < 4; ++i)
                out[i] = clip[i];
            break;
        }
        case UniformValueSource::RendererClipEnabled:
        {
            float value = renderer->GetUniformClipEnabled();
            if (componentCount > 0)
                out[0] = value;
            break;
        }
        case UniformValueSource::RendererClipRefract:
        {
            float value = renderer->GetUniformClipRefract();
            if (componentCount > 0)
                out[0] = value;
            break;
        }
        case UniformValueSource::RendererTime:
        {
            float value = renderer->GetUniformTime();
            if (componentCount > 0)
                out[0] = value;
            break;
        }
        case UniformValueSource::RendererGlobalFogColor:
        {
            float fog[4] = {0.0f, 0.0f, 0.0f, 1.0f};
            renderer->GetUniformGlobalFogColor(fog);
            for (size_t i = 0; i < componentCount && i < 4; ++i)
                out[i] = fog[i];
            break;
        }
        default:
            break;
        }
    }
    else if (binding.scalarType == UniformScalarType::Int)
    {
        int32_t* out = reinterpret_cast<int32_t*>(dst);
        for (size_t i = 0; i < componentCount; ++i)
            out[i] = 0;
    }
    else
    {
        uint32_t* out = reinterpret_cast<uint32_t*>(dst);
        for (size_t i = 0; i < componentCount; ++i)
            out[i] = 0;
    }
}

static void WriteUniformElement(const CMetalShaderManager::ShaderInfo::UniformRuntimeBinding& binding, const SShaderParam* param, uint8_t* dst, CMetalBaseRenderer* renderer)
{
    if (binding.source == UniformValueSource::ShaderParam)
    {
        if (param)
            WriteShaderParamUniform(binding, *param, dst);
        else
            WriteDefaultUniform(binding, dst);
    }
    else
    {
        WriteRendererUniform(binding, dst, renderer);
    }
}
}

void CMetalShaderManager::RegisterShaderAlias(const char* alias, const char* target)
{
    if (!alias || !target)
        return;
    std::string normalizedAlias = NormalizeShaderName(alias);
    std::string normalizedTarget = NormalizeShaderName(target);
    if (normalizedAlias.empty() || normalizedTarget.empty())
        return;
    if (normalizedAlias == normalizedTarget)
        return;
    auto targetIt = m_shaderNameMap.find(normalizedTarget);
    if (targetIt == m_shaderNameMap.end())
    {
        if (iLog)
            iLog->Log("MetalShaderManager: alias skipped '%s' -> '%s' (target missing)\n", normalizedAlias.c_str(), normalizedTarget.c_str());
        return;
    }
    m_shaderNameMap[normalizedAlias] = targetIt->second;
    if (iLog)
        iLog->Log("MetalShaderManager: alias '%s' -> '%s' (id=%d)\n", normalizedAlias.c_str(), normalizedTarget.c_str(), targetIt->second);
}



CMetalShader::CMetalShader(int shaderId, CMetalShaderManager* manager)
    : m_shaderId(shaderId)
    , m_manager(manager)
    , m_refCount(1)
    , m_flags(0)
    , m_flags2(0)
    , m_flags3(0)
    , m_renderFlags(0)
    , m_sort(eS_Unknown)
    , m_cull(eCULL_Back)
    , m_templates(nullptr)
    , m_shaderGenParams(nullptr)
    , m_pGenShader(nullptr)
    , m_LMFlags(0)
{
    assert(manager != nullptr && "CMetalShader: manager cannot be null!");
    assert(shaderId > 0 && "CMetalShader: shaderId must be positive!");
}

void CMetalShader::ApplyRendPipelineSortFlags(bool depthWriteEnabled, bool blendEnabled)
{
    m_flags2 |= EF2_DONTSORTBYDIST;
    if (depthWriteEnabled && !blendEnabled)
        m_flags2 |= EF2_OPAQUE;
    if (m_sort == eS_Unknown)
        m_sort = eS_Opaque;
}

CMetalShader::~CMetalShader()
{
    if (m_templates)
    {
        if (m_templates->m_TemplShaders.Num() > 0)
        {
            for (int i = 0; i < m_templates->m_TemplShaders.Num(); i++)
            {
                IShader* shader = reinterpret_cast<IShader*>(m_templates->m_TemplShaders[i]);
                if (shader && shader != this)
                {
                    shader->Release();
                }
            }
        }
        delete m_templates;
        m_templates = nullptr;
    }
    
    if (m_shaderGenParams)
    {
        for (int i = 0; i < m_shaderGenParams->m_BitMask.Num(); i++)
        {
            SShaderGenBit* bit = m_shaderGenParams->m_BitMask[i];
            if (bit)
            {
                delete bit;
            }
        }
        delete m_shaderGenParams;
        m_shaderGenParams = nullptr;
    }
    
    m_pGenShader = nullptr;
}

int CMetalShader::GetID()
{
    return m_shaderId;
}

void CMetalShader::AddRef()
{
    assert(m_refCount > 0 && "CMetalShader: Invalid ref count!");
    m_refCount++;
}

void CMetalShader::Release(bool bForce)
{
    assert(m_refCount > 0 && "CMetalShader: Release called on object with zero ref count!");
    
    m_refCount--;
    if (m_refCount <= 0 || bForce)
    {
        CMetalShaderManager* manager = m_manager;
        int shaderId = m_shaderId;
        const char* name = "<unknown>";
        if (manager)
        {
            auto it = manager->m_shaders.find(shaderId);
            if (it != manager->m_shaders.end())
                name = it->second.name.c_str();
        }
        if (iLog)
            iLog->Log("CMetalShader::Release deleting shader '%s' (id=%d) bForce=%d", name, shaderId, (int)bForce);
        else
            printf("CMetalShader::Release deleting shader '%s' (id=%d) bForce=%d\n", name, shaderId, (int)bForce);
        m_manager = nullptr;
        
        if (manager)
        {
            manager->ReleaseShaderId(shaderId);
        }
        delete this;
    }
}

int CMetalShader::GetRefCount()
{
    return m_refCount;
}

const char* CMetalShader::GetName()
{
    if (!m_manager)
    {
        assert(false);
        return "";
    }
    
    auto it = m_manager->m_shaders.find(m_shaderId);
    if (it != m_manager->m_shaders.end())
    {
        return it->second.name.c_str();
    }
    iLog->LogWarning("Shader %d not found in shader manager!", m_shaderId);
    return "";
}

EF_Sort CMetalShader::GetSort()
{
    return m_sort;
}

int CMetalShader::GetFlags()
{
    return m_flags;
}

int CMetalShader::GetFlags2()
{
    return m_flags2;
}

int CMetalShader::GetFlags3()
{
    return m_flags3;
}

int CMetalShader::GetRenderFlags()
{
    return m_renderFlags;
}

void CMetalShader::SetRenderFlags(int nFlags)
{
    m_renderFlags = nFlags;
}

int CMetalShader::GetLFlags()
{
    return m_LMFlags;
}

int CMetalShader::GetCull()
{
    return m_cull;
}

uint CMetalShader::GetPreprocessFlags()
{
    return 0;
}

void CMetalShader::SetFlags3(int Flags)
{
    m_flags3 |= Flags;
}

bool CMetalShader::Reload(int nFlags)
{
    return true;
}

TArray<CRendElement*>* CMetalShader::GetREs()
{
    return &m_renderElements;
}

bool CMetalShader::AddTemplate(SRenderShaderResources* Res, int& TemplId, const char* Name, bool bSetPreferred, uint64 nMaskGen)
{
    if (m_flags2 & (EF2_TEMPLATE | EF_SYSTEM))
        return false;
    
    if (!m_templates)
    {
        m_templates = new SEfTemplates;
    }
    
    if (TemplId < 0)
    {
        if (!Name || !Name[0])
            return false;
        
        for (int i = EFT_USER_FIRST; i < m_templates->m_TemplShaders.Num(); i++)
        {
            IShader* sh = reinterpret_cast<IShader*>(m_templates->m_TemplShaders[i]);
            if (sh && !strcmp(Name, sh->GetName()))
            {
                TemplId = i;
                return true;
            }
        }
        TemplId = m_templates->m_TemplShaders.Num();
    }
    
    if (TemplId >= m_templates->m_TemplShaders.Num())
    {
        m_templates->m_TemplShaders.ReserveNew(TemplId + 1);
        while (m_templates->m_TemplShaders.Num() <= TemplId)
        {
            m_templates->m_TemplShaders.AddElem(nullptr);
        }
    }
    
    if (Name && Name[0] && m_manager)
    {
        IShader* templateShader = m_manager->EF_LoadShader(Name, eSH_Misc, 0, nMaskGen);
        if (templateShader)
        {
            IShader* oldShader = reinterpret_cast<IShader*>(m_templates->m_TemplShaders[TemplId]);
            if (oldShader && oldShader != this)
            {
                oldShader->Release();
            }
            m_templates->m_TemplShaders[TemplId] = reinterpret_cast<SShader*>(templateShader);
            
            if (bSetPreferred)
            {
                m_templates->m_Preferred = reinterpret_cast<SShader*>(templateShader);
                m_templates->m_nPreferred = TemplId;
            }
            
            return true;
        }
    }
    
    return false;
}

void CMetalShader::RemoveTemplate(int TemplId)
{
    if (!m_templates || TemplId < 0 || TemplId >= m_templates->m_TemplShaders.Num())
        return;
    
    if (!m_templates->m_TemplShaders[TemplId])
        return;
    
    IShader* shader = reinterpret_cast<IShader*>(m_templates->m_TemplShaders[TemplId]);
    if (shader && shader != this)
    {
        shader->Release();
    }
    
    m_templates->m_TemplShaders[TemplId] = nullptr;
    
    if (m_templates->m_nPreferred == TemplId)
    {
        m_templates->m_Preferred = nullptr;
        m_templates->m_nPreferred = -1;
    }
}

IShader* CMetalShader::GetTemplate(int num)
{
    if (!m_templates)
        return this;
    
    if (num >= 0 && num < m_templates->m_TemplShaders.Num() && m_templates->m_TemplShaders[num])
    {
        return reinterpret_cast<IShader*>(m_templates->m_TemplShaders[num]);
    }
    
    if (m_templates->m_Preferred)
    {
        return reinterpret_cast<IShader*>(m_templates->m_Preferred);
    }
    
    return this;
}

SEfTemplates* CMetalShader::GetTemplates()
{
    return m_templates;
}

TArray<SShaderParam>& CMetalShader::GetPublicParams()
{
    return m_publicParams;
}

int CMetalShader::GetTexId()
{
    return 0;
}

ITexPic* CMetalShader::GetBaseTexture(int* nPass, int* nTU)
{
    if (nPass)
        *nPass = 0;
    if (nTU)
        *nTU = 0;
    return nullptr;
}

unsigned int CMetalShader::GetUsedTextureTypes(void)
{
    return 0;
}

int CMetalShader::GetVertexFormat(void)
{
    return VERTEX_FORMAT_P3F_N_COL4UB_TEX2F;
}

int CMetalShader::Size(int Flags)
{
    return 0;
}

uint64 CMetalShader::GetGenerationMask()
{
    if (!m_manager)
        return 0;
    
    auto it = m_manager->m_shaders.find(m_shaderId);
    if (it != m_manager->m_shaders.end())
    {
        return it->second.nMaskGen;
    }
    return 0;
}

SShaderGen* CMetalShader::GetGenerationParams()
{
    if (m_shaderGenParams)
        return m_shaderGenParams;
    if (m_pGenShader)
        return m_pGenShader->m_shaderGenParams;
    return nullptr;
}

// Shader System Interface (EF_ methods)
bool CMetalShaderManager::EF_PrecacheResource(IShader* pSH, float fDist, float fTimeToReady, int Flags)
{
    if (!pSH)
        return false;
        
    // Precache shader resources
    return true;
}

bool CMetalShaderManager::EF_PrecacheResource(ITexPic* pTP, float fDist, float fTimeToReady, int Flags)
{
    if (!pTP)
        return false;
        
    // Precache texture resources
    return true;
}

bool CMetalShaderManager::EF_PrecacheResource(CLeafBuffer* pPB, float fDist, float fTimeToReady, int Flags)
{
    if (!pPB)
        return false;
        
    // Precache geometry resources
    return true;
}

bool CMetalShaderManager::EF_PrecacheResource(CDLight* pLS, float fDist, float fTimeToReady, int Flags)
{
    if (!pLS)
        return false;
        
    // Precache light resources
    return true;
}

void CMetalShaderManager::EF_AddPolyToScene3D(int Ef, int numPts, SColorVert* verts, CCObject* obj, int nFogID)
{
    // Add 3D polygon to scene
    // This would queue the polygon for rendering
}

CCObject* CMetalShaderManager::EF_AddSpriteToScene(int Ef, int numPts, SColorVert* verts, CCObject* obj, byte* inds, int ninds, int nFogID)
{
    // Add sprite to scene
    // This would create and return a CCObject for the sprite
    return nullptr;
}

void CMetalShaderManager::EF_AddPolyToScene2D(int Ef, int numPts, SColorVert2D* verts)
{
    // Add 2D polygon to scene
    // This would queue the 2D polygon for rendering
}

void CMetalShaderManager::EF_AddPolyToScene2D(SShaderItem si, int nTempl, int numPts, SColorVert2D* verts)
{
    // Add 2D polygon to scene with shader item
    // This would queue the 2D polygon for rendering with specific shader
}

// Shader Management
IShader* CMetalShaderManager::EF_LoadShader(const char* name, EShClass Class, int flags, uint64 nMaskGen)
{
    if (!name || !name[0])
        return nullptr;
    
    std::string normalizedName = NormalizeShaderName(name);
    printf("MetalShaderManager::EF_LoadShader name='%s' normalized='%s' class=%d flags=%d mask=%llu\n", name, normalizedName.c_str(), (int)Class, flags, (unsigned long long)nMaskGen);
    if (iLog)
        iLog->Log("MetalShaderManager::EF_LoadShader name='%s' normalized='%s' class=%d flags=%d mask=%llu", name, normalizedName.c_str(), (int)Class, flags, (unsigned long long)nMaskGen);
    if (normalizedName.empty())
        return nullptr;
    
    auto baseEntryIt = m_shaderNameMap.find(normalizedName);
    ShaderInfo* baseInfoPtr = nullptr;
    if (baseEntryIt != m_shaderNameMap.end())
    {
        auto baseShaderIt = m_shaders.find(baseEntryIt->second);
        if (baseShaderIt != m_shaders.end())
        {
            baseInfoPtr = &baseShaderIt->second;
        }
    }
    
    std::string lookupName = normalizedName;
    if (nMaskGen != 0)
    {
        char nameWithMask[512];
        snprintf(nameWithMask, sizeof(nameWithMask), "%s(%llx)", normalizedName.c_str(), (unsigned long long)nMaskGen);
        lookupName = nameWithMask;
        if (baseInfoPtr && !baseInfoPtr->maskReferences.empty())
        {
            uint64 validMask = baseInfoPtr->maskReferences.size() >= 64
                ? ~0ULL
                : ((1ULL << baseInfoPtr->maskReferences.size()) - 1ULL);
            if ((nMaskGen & ~validMask) != 0)
            {
                if (iLog)
                {
                    iLog->Log("MetalShaderManager: Shader '%s' requested mask 0x%llx outside supported range 0x%llx",
                              normalizedName.c_str(),
                              (unsigned long long)nMaskGen,
                              (unsigned long long)validMask);
                }
            }
        }
    }
    
    auto nameIt = m_shaderNameMap.find(lookupName);
    if (nameIt != m_shaderNameMap.end())
    {
        auto shaderIt = m_shaders.find(nameIt->second);
        if (shaderIt != m_shaders.end())
        {
            ShaderInfo& info = shaderIt->second;
            if (info.shaderWrapper)
            {
                if (!(flags & 1))
                {
                    info.shaderWrapper->AddRef();
                    if (flags != 0)
                    {
                        info.shaderWrapper->m_flags |= flags;
                    }
                    return info.shaderWrapper;
                }
            }
        }
    }
    
    if (flags & 1)
    {
        if (nameIt != m_shaderNameMap.end())
        {
            int shaderId = nameIt->second;
            auto shaderIt = m_shaders.find(shaderId);
            if (shaderIt != m_shaders.end())
            {
                ShaderInfo& info = shaderIt->second;
                ReleaseRendItemTableStub(info);
                if (info.shaderWrapper)
                {
                    info.shaderWrapper->Release(true);
                }
                m_shaders.erase(shaderIt);
                m_shaderNameMap.erase(nameIt);
            }
        }
    }
    
    if (baseEntryIt != m_shaderNameMap.end())
    {
        auto shaderIt = m_shaders.find(baseEntryIt->second);
        if (shaderIt != m_shaders.end())
        {
            ShaderInfo& baseInfo = shaderIt->second;
            
            int shaderId = AllocateShaderId();
            ShaderInfo info = baseInfo;
            info.name = lookupName;
            info.nMaskGen = nMaskGen;
            info.shaderWrapper = new CMetalShader(shaderId, this);
            ResetRuntimeBindingState(info);
            
            if (nMaskGen != 0 && baseInfo.shaderWrapper)
            {
                info.shaderWrapper->m_pGenShader = baseInfo.shaderWrapper;
            }
            
            m_shaders[shaderId] = info;
            m_shaderNameMap[lookupName] = shaderId;
            InstallRendItemTableStub(shaderId, m_shaders[shaderId]);

            return info.shaderWrapper;
        }
    }
    
    if ((flags & EF_SYSTEM) != 0)
        ShaderLoadFatal("EF_LoadShader", name, lookupName.c_str(), Class, flags);

    ++m_nStartupMissingShaders;
#if DEBUG
    extern int g_metalStartupMissingShaders;
    ++g_metalStartupMissingShaders;
#endif
    printf("MetalShaderManager: EF_LoadShader unregistered '%s' (class=%d) — returning nullptr\n", lookupName.c_str(), (int)Class);
    if (iLog)
        iLog->Log("MetalShaderManager: EF_LoadShader unregistered '%s' — not in generated manifest / shader map.", lookupName.c_str());
    return nullptr;
}

SShaderItem CMetalShaderManager::EF_LoadShaderItem(const char* name, EShClass Class, bool bShare, const char* templName, int flags, SInputShaderResources* Res, uint64 nMaskGen)
{
    SShaderItem item;

    auto lookupDirect = [&](const char* key) -> IShader*
    {
        if (!key || !key[0])
            return nullptr;
        std::string norm = NormalizeShaderName(key);
        auto it = m_shaderNameMap.find(norm);
        if (it == m_shaderNameMap.end())
            return nullptr;
        auto shIt = m_shaders.find(it->second);
        if (shIt == m_shaders.end() || !shIt->second.shaderWrapper)
            return nullptr;
        shIt->second.shaderWrapper->AddRef();
        return shIt->second.shaderWrapper;
    };

    const bool templIsDefault = !templName || !templName[0]
        || _stricmp(templName, "nodraw") == 0;

    if (!templIsDefault)
        item.m_pShader = lookupDirect(templName);

    if (!item.m_pShader)
        item.m_pShader = lookupDirect(name);

    SRenderShaderResources* pRes = Res ? new SRenderShaderResources(Res)
                                       : new SRenderShaderResources();
    pRes->m_LMaterial = nullptr;
    pRes->m_nRefCounter = 1;

    if (Res && m_textureManager)
    {
        const char* path = pRes->m_TexturePath.c_str();
        for (int i = 0; i < EFTT_MAX; ++i)
        {
            SEfResTexture* tex = pRes->m_Textures[i];
            if (!tex || tex->m_Name.empty() || tex->m_TU.m_ITexPic)
                continue;

            const uint flags  = (uint)tex->m_TU.GetTexFlags();
            const uint flags2 = (uint)tex->m_TU.GetTexFlags2();
            const byte eTT    = tex->m_TU.m_eTexType ? tex->m_TU.m_eTexType : (byte)eTT_Base;

            ITexPic* pic = m_textureManager->EF_LoadTexture(
                tex->m_Name.c_str(), flags, flags2, eTT, tex->m_Amount, -1.0f);

            if ((!pic || !pic->IsTextureLoaded()) && path && path[0])
            {
                if (pic)
                    pic->Release(false);
                char combined[512];
                snprintf(combined, sizeof(combined), "%s%s", path, tex->m_Name.c_str());
                pic = m_textureManager->EF_LoadTexture(
                    combined, flags, flags2, eTT, tex->m_Amount, -1.0f);
            }

            if (pic)
                tex->m_TU.m_TexPic = (STexPic*)pic;
        }
    }

    if (!SShader::m_ShaderResources_known.Num())
    {
        SShader::m_ShaderResources_known.AddIndex(1);
        SRenderShaderResources* pSRNULL = new SRenderShaderResources;
        pSRNULL->m_nRefCounter = 1;
        SShader::m_ShaderResources_known[0] = pSRNULL;
    }

    if (SShader::m_ShaderResources_known.Num() < MAX_SHADER_RES)
    {
        pRes->m_Id = SShader::m_ShaderResources_known.Num();
        SShader::m_ShaderResources_known.AddElem(pRes);
    }
    else
    {
        if (iLog)
            iLog->LogWarning("CMetalShaderManager::EF_LoadShaderItem: "
                             "MAX_SHADER_RES (%d) hit, reusing sentinel for '%s'",
                             MAX_SHADER_RES, name ? name : "(null)");
        delete pRes;
        pRes = SShader::m_ShaderResources_known[1];
        if (pRes)
            pRes->m_nRefCounter++;
    }
    item.m_pShaderResources = pRes;

    if (!item.m_pShader && (flags & EF_SYSTEM) != 0)
        ShaderLoadFatalItem(name, templName, Class, flags);

    return item;
}

bool CMetalShaderManager::EF_ReloadFile(const char* szFileName)
{
    if (!szFileName)
        return false;
        
    // Reload shader file
    return true;
}

void CMetalShaderManager::EF_ReloadShaderFiles(int nCategory)
{
    // Reload all shader files in category
}

void CMetalShaderManager::EF_ReloadTextures()
{
    // Reload all textures
}

IShader* CMetalShaderManager::EF_CopyShader(IShader* ef)
{
    if (!ef)
        return nullptr;
        
    // Copy shader
    return nullptr;
}

char** CMetalShaderManager::EF_GetShadersForFile(const char* File, int num)
{
    if (!File)
        return nullptr;
        
    // Get shaders for file
    return nullptr;
}

SLightMaterial* CMetalShaderManager::EF_GetLightMaterial(char* Str)
{
    if (!Str)
        return nullptr;
        
    // Get light material
    return nullptr;
}

bool CMetalShaderManager::EF_RegisterTemplate(int nTemplId, char* Name, bool bReplace)
{
    if (!Name)
        return false;
        
    // Register shader template
    return true;
}

void CMetalShaderManager::EF_AddSplash(Vec3 Pos, eSplashType eST, float fForce, int Id)
{
    // Add splash effect
}

bool CMetalShaderManager::EF_HideTemplate(const char* name)
{
    if (!name)
        return false;
        
    // Hide shader template
    return true;
}

bool CMetalShaderManager::EF_UnhideTemplate(const char* name)
{
    if (!name)
        return false;
        
    // Unhide shader template
    return true;
}

bool CMetalShaderManager::EF_UnhideAllTemplates()
{
    // Unhide all shader templates
    return true;
}

bool CMetalShaderManager::EF_SetLightHole(Vec3 vPos, Vec3 vNormal, int idTex, float fScale, bool bAdditive)
{
    // Set light hole
    return true;
}


void CMetalShaderManager::EF_StartEf()
{
    // Start shader effects
}

CCObject* CMetalShaderManager::EF_GetObject(bool bTemp, int num)
{
    static CCObject sPool[256];
    static int sNext = 0;
    CCObject* obj = &sPool[sNext++ & 255];
    // Clear ShaderParams before Init() so it never attempts to delete a stale
    // pointer left over from the previous use of this pool slot.
    obj->m_ShaderParams = nullptr;
    obj->m_bShaderParamCreatedInRenderer = false;
    // Init() zeros m_NumWFX/m_NumWFY (and all other render-state fields) so
    // AddWaves/SetupBending never indexes CCObject::m_Waves with a stale index.
    // The D3D CRenderer::EF_GetObject follows the same contract (Renderer.cpp:2832).
    obj->Init();
    return obj;
}

void CMetalShaderManager::EF_AddEf(int NumFog, CRendElement* re, IShader* ef, SRenderShaderResources* sr, CCObject* obj, int nTempl, IShader* efState, int nSort)
{
    // Add shader effect to render list
}

void CMetalShaderManager::EF_EndEf3D(int nFlags)
{
    // End 3D shader effects
}

bool CMetalShaderManager::EF_IsFakeDLight(CDLight* Source)
{
    if (!Source)
        return false;
        
    // Check if light is fake
    return false;
}

void CMetalShaderManager::EF_ADDDlight(CDLight* Source)
{
    if (!Source)
        return;
        
    // Add dynamic light
}

void CMetalShaderManager::EF_ClearLightsList()
{
    // Clear dynamic lights list
}

bool CMetalShaderManager::EF_UpdateDLight(CDLight* pDL)
{
    if (!pDL)
        return false;
        
    // Update dynamic light
    return true;
}

void CMetalShaderManager::EF_EndEf2D(bool bSort)
{
    // End 2D shader effects
}

bool CMetalShaderManager::EF_DrawEfForName(char* name, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    if (!name)
        return false;
        
    // Draw shader effect by name
    return true;
}

bool CMetalShaderManager::EF_DrawEfForNum(int num, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    // Draw shader effect by number
    return true;
}

bool CMetalShaderManager::EF_DrawEf(IShader* ef, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    if (!ef)
        return false;
        
    // Draw shader effect
    return true;
}

bool CMetalShaderManager::EF_DrawEf(SShaderItem si, float x, float y, float width, float height, CFColor& col, int nTempl)
{
    // Draw shader effect with shader item
    return true;
}

bool CMetalShaderManager::EF_DrawPartialEfForName(char* name, SVrect* vr, SVrect* pr, CFColor& col)
{
    if (!name)
        return false;
        
    // Draw partial shader effect by name
    return true;
}

bool CMetalShaderManager::EF_DrawPartialEfForNum(int num, SVrect* vr, SVrect* pr, CFColor& col)
{
    // Draw partial shader effect by number
    return true;
}

bool CMetalShaderManager::EF_DrawPartialEf(IShader* ef, SVrect* vr, SVrect* pr, CFColor& col, float iwdt, float ihgt)
{
    if (!ef)
        return false;
        
    // Draw partial shader effect
    return true;
}

void* CMetalShaderManager::EF_Query(int Query, int Param)
{
    // Query shader system
    return nullptr;
}

void CMetalShaderManager::EF_ConstructEf(IShader* Ef)
{
    if (!Ef)
        return;
        
    // Construct shader effect
}

void CMetalShaderManager::EF_SetWorldColor(float r, float g, float b, float a)
{
    // Set world color for shaders
}

int CMetalShaderManager::EF_RegisterFogVolume(float fMaxFogDist, float fFogLayerZ, CFColor color, int nIndex, bool bCaustics)
{
    // Register fog volume
    return 0;
}

// LeafBuffer Management
CLeafBuffer* CMetalShaderManager::CreateLeafBuffer(bool bDynamic, const char* szSource, class CIndexedMesh* pIndexedMesh)
{
    if (!szSource)
        return nullptr;
        
    // Create leaf buffer
    return nullptr;
}

CLeafBuffer* CMetalShaderManager::CreateLeafBufferInitialized(void* pVertBuffer, int nVertCount, int nVertFormat, ushort* pIndices, int nIndices, int nPrimetiveType, const char* szSource, EBufferType eBufType, int nMatInfoCount, int nClientTextureBindID, bool (*PrepareBufferCallback)(CLeafBuffer*, bool), void* CustomData, bool bOnlyVideoBuffer, bool bPrecache)
{
    if (!pVertBuffer || !szSource)
        return nullptr;
        
    // Create initialized leaf buffer
    return nullptr;
}

void CMetalShaderManager::DeleteLeafBuffer(CLeafBuffer* pLBuffer)
{
    if (!pLBuffer)
        return;
        
    // Delete leaf buffer
}

// Protected methods
bool CMetalShaderManager::LoadShaderFromFile(const char* filename, std::string& source)
{
    if (!filename || !filename[0])
    {
        iLog->Log("CMetalShaderManager::LoadShaderFromFile: Invalid filename\n");
        return false;
    }
    
    source.clear();
    
    std::string shaderPath = filename;
    ConvertDOSToUnixName(const_cast<char*>(shaderPath.c_str()), const_cast<char*>(shaderPath.c_str()));
    
    const char* ext = GetExtension(shaderPath.c_str());
    bool hasMetalExt = ext && !stricmp(ext, ".metal");
    
    if (!hasMetalExt)
    {
        shaderPath += ".metal";
    }
    
    FILE* fp = nullptr;
    std::string fullPath;
    
    if (shaderPath[0] == '/' || (shaderPath.length() > 1 && shaderPath[1] == ':'))
    {
        fullPath = shaderPath;
        fp = GetISystem()->GetIPak()->FOpen(fullPath.c_str(), "rb");
    }
    
    if (!fp)
    {
        const char* searchPaths[] = {
            "Shaders/Metal/",
            "Shaders/HWScripts/Metal/",
            "Shaders/HWScripts/Declarations/Metal/",
            "Shaders/",
            ""
        };
        
        for (auto & searchPath : searchPaths)
        {
            fullPath = searchPath;
            if (!fullPath.empty())
            {
                fullPath += shaderPath;
            }
            else
            {
                fullPath = shaderPath;
            }
            
            ConvertDOSToUnixName(const_cast<char*>(fullPath.c_str()), const_cast<char*>(fullPath.c_str()));
            fp = GetISystem()->GetIPak()->FOpen(fullPath.c_str(), "rb");
            
            if (fp)
            {
                break;
            }
        }
    }
    
    if (!fp)
    {
        iLog->Log("CMetalShaderManager::LoadShaderFromFile: Could not find shader file '%s'\n", filename);
        return false;
    }
    
    GetISystem()->GetIPak()->FSeek(fp, 0, SEEK_END);
    long fileSize = GetISystem()->GetIPak()->FTell(fp);
    
    if (fileSize <= 0)
    {
        GetISystem()->GetIPak()->FClose(fp);
        iLog->Log("CMetalShaderManager::LoadShaderFromFile: Shader file '%s' is empty\n", fullPath.c_str());
        return false;
    }
    
    GetISystem()->GetIPak()->FSeek(fp, 0, SEEK_SET);
    
    source.resize(fileSize);
    size_t bytesRead = GetISystem()->GetIPak()->FRead(&source[0], 1, fileSize, fp);
    GetISystem()->GetIPak()->FClose(fp);
    
    if (bytesRead != static_cast<size_t>(fileSize))
    {
        iLog->Log("CMetalShaderManager::LoadShaderFromFile: Failed to read entire shader file '%s' (read %zu of %ld bytes)\n", 
                  fullPath.c_str(), bytesRead, fileSize);
        source.clear();
        return false;
    }
    
    iLog->Log("CMetalShaderManager::LoadShaderFromFile: Successfully loaded shader from '%s' (%ld bytes)\n", 
              fullPath.c_str(), fileSize);
    
    return true;
}

bool CMetalShaderManager::CompileShader(const std::string& source, id<MTLFunction>& function)
{
    if (!m_renderer || !m_renderer->m_device)
        return false;
        
    NSError* error = nil;
    id<MTLLibrary> library = [m_renderer->m_device newLibraryWithSource:@(source.c_str()) options:nil error:&error];
    if (!library)
    {
        iLog->Log("Error: Failed to create Metal library: %s\n", error ? [[error localizedDescription] UTF8String] : "Unknown error");
        return false;
    }
    
    // Get the main function
    function = [library newFunctionWithName:@"main"];
    return function != nil;
}

void CMetalShaderManager::ResetRuntimeBindingState(ShaderInfo& info)
{
    info.uniformRuntimeBindings.clear();
    info.textureRuntimeBindings.clear();
    info.runtimeBindingsPrepared = false;
    info.publicParamSignature = 0;
    info.uniformDataSize = 0;
    info.uniformStaging.clear();
}

void CMetalShaderManager::PrepareRuntimeBindings(CMetalShader* shader, ShaderInfo& info)
{
    if (!shader)
        return;

    TArray<SShaderParam>& params = shader->GetPublicParams();
    ResetRuntimeBindingState(info);

    size_t offset = 0;
    for (const GeneratedUniformBinding& binding : info.uniformBindings)
    {
        int index = FindShaderParamIndex(params, binding.name);
        if (index == -1 && !binding.semantic.empty())
        {
            index = FindShaderParamIndex(params, binding.semantic);
        }
        ShaderInfo::UniformRuntimeBinding runtimeBinding;
        runtimeBinding.paramIndex = index;
        runtimeBinding.binding = binding;
        UniformLayoutInfo layout = ParseUniformLayout(binding);
        runtimeBinding.scalarType = layout.scalarType;
        runtimeBinding.rows = layout.rows;
        runtimeBinding.columns = layout.columns;
        runtimeBinding.arrayCount = layout.arrayCount;
        runtimeBinding.source = DetermineUniformSource(binding);
        runtimeBinding.elementStride = layout.alignedSize;
        size_t alignedOffset = AlignSize(offset, 16);
        runtimeBinding.offset = alignedOffset;
        runtimeBinding.size = layout.alignedSize * static_cast<size_t>(layout.arrayCount);
        offset = alignedOffset + runtimeBinding.size;
        if (layout.arrayCount > 1)
        {
            runtimeBinding.arrayParamIndices.reserve(layout.arrayCount);
            for (int element = 0; element < layout.arrayCount; ++element)
            {
                std::string indexedName = binding.name;
                indexedName += "[";
                indexedName += std::to_string(element);
                indexedName += "]";
                int elementIndex = FindShaderParamIndex(params, indexedName);
                if (elementIndex == -1 && !binding.semantic.empty())
                {
                    std::string indexedSemantic = binding.semantic;
                    indexedSemantic += "[";
                    indexedSemantic += std::to_string(element);
                    indexedSemantic += "]";
                    elementIndex = FindShaderParamIndex(params, indexedSemantic);
                }
                runtimeBinding.arrayParamIndices.push_back(elementIndex);
            }
        }
        info.uniformRuntimeBindings.push_back(runtimeBinding);
    }

    int fallbackIndex = 0;
    for (const GeneratedTextureBinding& binding : info.textureBindings)
    {
        ShaderInfo::TextureRuntimeBinding runtimeBinding;
        runtimeBinding.slot = SemanticToTextureSlot(binding.semantic, fallbackIndex);
        runtimeBinding.binding = binding;
        info.textureRuntimeBindings.push_back(runtimeBinding);
        fallbackIndex++;
    }

    info.uniformDataSize = offset > 0 ? AlignSize(offset, 16) : 0;
    if (info.uniformDataSize > 0)
        info.uniformStaging.assign(info.uniformDataSize, 0);

    info.runtimeBindingsPrepared = true;
    info.publicParamSignature = ComputePublicParamSignature(params);
}

void CMetalShaderManager::SetShaderParameters(id<MTLRenderCommandEncoder> encoder, IShader* shader)
{
    if (!encoder || !shader)
        return;

    int shaderId = shader->GetID();
    auto it = m_shaders.find(shaderId);
    if (it == m_shaders.end())
        return;

    ShaderInfo& info = it->second;
    CMetalShader* metalShader = static_cast<CMetalShader*>(shader);
    TArray<SShaderParam>& shaderParams = shader->GetPublicParams();
    if (metalShader)
    {
        size_t currentSignature = ComputePublicParamSignature(shaderParams);
        if (!info.runtimeBindingsPrepared || info.publicParamSignature != currentSignature)
        {
            PrepareRuntimeBindings(metalShader, info);
        }
    }
    const bool hasUniformBindings = !info.uniformRuntimeBindings.empty();

    ApplyPipelineStateInternal(info);

    if (!hasUniformBindings)
        return;

    if (info.uniformDataSize == 0)
        return;

    if (info.uniformStaging.size() != info.uniformDataSize)
        info.uniformStaging.assign(info.uniformDataSize, 0);
    else
        std::fill(info.uniformStaging.begin(), info.uniformStaging.end(), 0);

    uint8_t* stagingData = info.uniformStaging.data();
    CMetalBaseRenderer* rendererBase = m_renderer;
    for (const auto& runtimeBinding : info.uniformRuntimeBindings)
    {
        uint8_t* basePtr = stagingData + runtimeBinding.offset;
        int arrayCount = runtimeBinding.arrayCount > 0 ? runtimeBinding.arrayCount : 1;
        for (int element = 0; element < arrayCount; ++element)
        {
            uint8_t* elementPtr = basePtr + runtimeBinding.elementStride * static_cast<size_t>(element);
            int paramIndex = runtimeBinding.paramIndex;
            if (!runtimeBinding.arrayParamIndices.empty() && element < static_cast<int>(runtimeBinding.arrayParamIndices.size()))
                paramIndex = runtimeBinding.arrayParamIndices[element];
            const SShaderParam* paramPtr = (paramIndex >= 0 && paramIndex < shaderParams.Num()) ? &shaderParams[paramIndex] : nullptr;
            WriteUniformElement(runtimeBinding, paramPtr, elementPtr, rendererBase);
        }
    }

    [encoder setFragmentBytes:info.uniformStaging.data() length:info.uniformDataSize atIndex:kMetalPerShaderFragmentUniformSlot];
    [encoder setVertexBytes:info.uniformStaging.data() length:info.uniformDataSize atIndex:kMetalPerShaderVertexUniformSlot];
}

void CMetalShaderManager::BindShaderTextures(id<MTLRenderCommandEncoder> encoder, IShader* shader)
{
    if (!encoder || !shader || !m_textureManager)
        return;

    int shaderId = shader->GetID();
    auto it = m_shaders.find(shaderId);
    if (it == m_shaders.end())
        return;

    ShaderInfo& info = it->second;
    if (info.textureBindings.empty())
        return;

    CMetalShader* metalShader = static_cast<CMetalShader*>(shader);
    if (metalShader)
    {
        TArray<SShaderParam>& shaderParams = shader->GetPublicParams();
        size_t currentSignature = ComputePublicParamSignature(shaderParams);
        if (!info.runtimeBindingsPrepared || info.publicParamSignature != currentSignature)
        {
            PrepareRuntimeBindings(metalShader, info);
        }
    }

    if (info.textureRuntimeBindings.empty())
        return;

    size_t bindingIndex = 0;
    for (const auto& runtimeBinding : info.textureRuntimeBindings)
    {
        int slot = runtimeBinding.slot;
        if (slot < 0)
        {
            ++bindingIndex;
            continue;
        }
        id<MTLTexture> texture = m_textureManager->GetBoundFragmentTexture(slot);
        if (!texture)
            texture = m_textureManager->GetWhiteTexture();
        id<MTLSamplerState> sampler = m_textureManager->GetBoundFragmentSampler(slot);
        if (texture)
            [encoder setFragmentTexture:texture atIndex:slot];
        if (sampler)
            [encoder setFragmentSamplerState:sampler atIndex:slot];
        ++bindingIndex;
    }
}

void CMetalShaderManager::ApplyShaderPipelineState(IShader* shader)
{
    ShaderInfo* info = FindShaderInfo(shader);
    if (!info)
        return;
    ApplyPipelineStateInternal(*info);
}

CMetalShaderManager::ShaderInfo* CMetalShaderManager::FindShaderInfo(IShader* shader)
{
    if (!shader)
        return nullptr;
    int shaderId = shader->GetID();
    auto it = m_shaders.find(shaderId);
    if (it == m_shaders.end())
        return nullptr;
    return &it->second;
}

void CMetalShaderManager::ApplyPipelineStateInternal(ShaderInfo& info)
{
    if (!m_renderer)
        return;

    if (info.pipelineState)
        m_renderer->m_currentPipelineState = info.pipelineState;

    if (info.cullMode == MTLCullModeNone)
        m_renderer->SetCullMode(R_CULL_DISABLE);
    else if (info.cullMode == MTLCullModeFront)
        m_renderer->SetCullMode(R_CULL_FRONT);
    else
        m_renderer->SetCullMode(R_CULL_BACK);

    m_renderer->SetDepthTest(info.depthTestEnabled);
    m_renderer->SetDepthWrite(info.depthWriteEnabled);
    m_renderer->SetDepthFunction(info.depthCompareFunction);

    if (info.blendEnabled)
    {
        m_renderer->SetBlending(true);
        m_renderer->SetBlendFactors(info.sourceBlendFactor, info.destinationBlendFactor, info.blendOperation);
    }
    else
    {
        m_renderer->SetBlending(false);
    }

    m_renderer->SetShaderTangentRequirement(info.needsTangents);
    m_renderer->ApplyRenderState();
}

bool SShaderPass::mfSetTextures()
{
    for (int i = 0; i < m_TUnits.Num(); ++i)
    {
        SShaderTexUnit* unit = &m_TUnits[i];
        if (!unit)
            continue;
        unit->mfSetTexture(i);
    }
    return true;
}

void SShaderPass::mfResetTextures()
{
}

#endif // __APPLE__ && __MACH__
