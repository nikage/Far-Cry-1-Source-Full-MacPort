#include "StdAfx.h"
#include "AssetValidator.h"

#include <string.h>

namespace
{
    struct PakSpec
    {
        const char* name;
        bool critical;
    };

    static const PakSpec s_requiredPaks[] =
    {
        { "Scripts.pak",  true  },
        { "Textures.pak", false },
        { "Sounds.pak",   false },
        // Shaders.pak intentionally absent: Metal port loads shaders from
        // compiled .metallib binaries in the app bundle, not through CryPak.
    };

    static const int s_requiredPakCount = sizeof(s_requiredPaks) / sizeof(s_requiredPaks[0]);

    bool PakNameMatches(const char* szFilePath, const char* szPakName)
    {
        if (!szFilePath || !szPakName)
            return false;

        const char* p = szFilePath;
        const char* last = nullptr;

        while (*p)
        {
            if (*p == '/' || *p == '\\')
                last = p + 1;
            ++p;
        }

        const char* basename = last ? last : szFilePath;

#if defined(__APPLE__) || defined(LINUX)
        return strcasecmp(basename, szPakName) == 0;
#else
        return _stricmp(basename, szPakName) == 0;
#endif
    }
}

bool CAssetValidator::ValidateMountedPaks(ICryPak* pPak, ILog* pLog)
{
    assert(pPak && "CAssetValidator::ValidateMountedPaks: pPak is null");
    assert(pLog && "CAssetValidator::ValidateMountedPaks: pLog is null");

    if (!pPak || !pLog)
        return false;

    ICryPak::PakInfo* pInfo = pPak->GetPakInfo();
    assert(pInfo && "CAssetValidator::ValidateMountedPaks: GetPakInfo returned null");
    if (!pInfo)
        return false;

    bool allCriticalPresent = true;

    for (int i = 0; i < s_requiredPakCount; ++i)
    {
        const PakSpec& spec = s_requiredPaks[i];
        bool found = false;

        for (unsigned j = 0; j < pInfo->numOpenPaks; ++j)
        {
            if (PakNameMatches(pInfo->arrPaks[j].szFilePath, spec.name))
            {
                found = true;
                break;
            }
        }

        if (!found)
        {
            if (spec.critical)
            {
                pLog->LogError("[AssetValidator] Critical pak not mounted: %s", spec.name);
                allCriticalPresent = false;
            }
            else
            {
                pLog->LogWarning("[AssetValidator] Non-critical pak not mounted: %s", spec.name);
            }
        }
    }

    pPak->FreePakInfo(pInfo);

    return allCriticalPresent;
}
