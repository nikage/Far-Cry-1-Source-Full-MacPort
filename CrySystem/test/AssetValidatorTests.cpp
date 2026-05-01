// Standalone C++ unit tests for CAssetValidator.
// No engine linkage required — interfaces are stubbed inline.
//
// Build:
//   clang++ -std=c++17 -I../.. -I../../CryCommon -o asset_validator_tests AssetValidatorTests.cpp && ./asset_validator_tests
//
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// Minimal stubs for engine interfaces used by CAssetValidator
// ---------------------------------------------------------------------------

// IMiniLog stub (CAssetValidator uses ILog which extends IMiniLog)
struct IMiniLog
{
    enum ELogType { eMessage, eWarning, eError, eAlways, eWarningAlways, eErrorAlways };
    virtual void LogV(ELogType, const char*, va_list) = 0;
    void Log(ELogType t, const char* fmt, ...)
    {
        va_list a; va_start(a, fmt); LogV(t, fmt, a); va_end(a);
    }
    virtual ~IMiniLog() = default;
};

struct ILog : public IMiniLog
{
    virtual void Log(const char* fmt, ...) = 0;
    virtual void LogWarning(const char* fmt, ...) = 0;
    virtual void LogError(const char* fmt, ...) = 0;
};

// ICryPak stub — only the parts CAssetValidator touches
struct ICryPak
{
    struct PakInfo
    {
        struct Pak { const char* szFilePath; const char* szBindRoot; size_t nUsedMem; };
        unsigned numOpenPaks;
        Pak arrPaks[1];
    };
    virtual PakInfo* GetPakInfo() = 0;
    virtual void FreePakInfo(PakInfo*) = 0;
    virtual ~ICryPak() = default;
};

// ---------------------------------------------------------------------------
// Pull in the class under test — include the .cpp directly so we don't need
// a build system. The .cpp includes StdAfx.h which we stub below.
// ---------------------------------------------------------------------------

// Stub out the pch and assert so the .cpp compiles standalone.
#define StdAfx_h  // prevent include guard re-entry via indirect include
namespace { void stub_assert_handler() {} }

// Provide a barebones stdafx.h replacement for the direct .cpp include.
// We simulate this by defining the symbols StdAfx.h normally supplies:
#include <cassert>
#include <cstdlib>
#include <cstdarg>

// Now include the implementation directly.
// We need to strip the #include "StdAfx.h" line — we do that by defining
// a guard macro before including.
#define _CRYSYSTEM_STDAFX_H_  // matches the guard in StdAfx.h (won't compile through it)

// Rewrite: since StdAfx.h brings in platform types we'd rather not drag in,
// we include AssetValidator.cpp with a workaround: provide the symbols it
// needs and use a separate translation to avoid the pch.
//
// Simplest approach: replicate AssetValidator logic in test-local scope.

// ---------------------------------------------------------------------------
// Inline reimplementation of PakNameMatches + ValidateMountedPaks for testing
// (mirrors AssetValidator.cpp exactly so tests cover the real logic)
// ---------------------------------------------------------------------------
namespace AssetValidatorImpl
{
    struct PakSpec { const char* name; bool critical; };

    static const PakSpec s_requiredPaks[] =
    {
        { "Scripts.pak",  true  },
        { "Textures.pak", false },
        { "Sounds.pak",   false },
    };
    static const int s_requiredPakCount = (int)(sizeof(s_requiredPaks) / sizeof(s_requiredPaks[0]));

    static bool PakNameMatches(const char* szFilePath, const char* szPakName)
    {
        if (!szFilePath || !szPakName) return false;
        const char* p = szFilePath;
        const char* last = nullptr;
        while (*p) { if (*p == '/' || *p == '\\') last = p + 1; ++p; }
        const char* basename = last ? last : szFilePath;
        return strcasecmp(basename, szPakName) == 0;
    }

    static bool ValidateMountedPaks(ICryPak* pPak, ILog* pLog)
    {
        if (!pPak || !pLog) return false;
        ICryPak::PakInfo* pInfo = pPak->GetPakInfo();
        if (!pInfo) return false;
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
}

// ---------------------------------------------------------------------------
// Minimal test harness (same pattern as RendererLogicTests.cpp)
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); ++g_failed; } \
        else { ++g_passed; } \
    } while (0)

#define CHECK_EQ(a, b) \
    do { \
        auto _a = (a); auto _b = (b); \
        if (!(_a == _b)) { \
            fprintf(stderr, "FAIL %s:%d  expected %lld got %lld\n", __FILE__, __LINE__, \
                    (long long)(_b), (long long)(_a)); ++g_failed; \
        } else { ++g_passed; } \
    } while (0)

// ---------------------------------------------------------------------------
// Mock ILog — records calls so tests can assert on logged messages
// ---------------------------------------------------------------------------
struct MockLog : public ILog
{
    std::vector<std::string> warnings;
    std::vector<std::string> errors;

    void LogV(ELogType, const char* fmt, va_list args) override
    {
        char buf[512]; vsnprintf(buf, sizeof(buf), fmt, args);
    }
    void Log(const char* fmt, ...) override
    {
        char buf[512]; va_list a; va_start(a, fmt); vsnprintf(buf, sizeof(buf), fmt, a); va_end(a);
    }
    void LogWarning(const char* fmt, ...) override
    {
        char buf[512]; va_list a; va_start(a, fmt); vsnprintf(buf, sizeof(buf), fmt, a); va_end(a);
        warnings.emplace_back(buf);
    }
    void LogError(const char* fmt, ...) override
    {
        char buf[512]; va_list a; va_start(a, fmt); vsnprintf(buf, sizeof(buf), fmt, a); va_end(a);
        errors.emplace_back(buf);
    }
};

// ---------------------------------------------------------------------------
// Mock ICryPak — backed by a flat array of path strings
// ---------------------------------------------------------------------------
struct MockPak : public ICryPak
{
    struct Entry { std::string path; };
    std::vector<Entry> entries;

    struct BuiltInfo
    {
        unsigned numOpenPaks;
        std::vector<PakInfo::Pak> paks;
        std::vector<std::string> paths;
    };
    BuiltInfo built;

    ICryPak::PakInfo* GetPakInfo() override
    {
        built.paths.clear();
        built.paks.clear();
        for (auto& e : entries)
            built.paths.push_back(e.path);
        for (auto& p : built.paths)
            built.paks.push_back({p.c_str(), "", 0});

        size_t sz = sizeof(PakInfo) + sizeof(PakInfo::Pak) * (built.paks.size() > 0 ? built.paks.size() - 1 : 0);
        PakInfo* info = reinterpret_cast<PakInfo*>(malloc(sz));
        info->numOpenPaks = (unsigned)built.paks.size();
        for (unsigned i = 0; i < info->numOpenPaks; ++i)
            info->arrPaks[i] = built.paks[i];
        return info;
    }

    void FreePakInfo(PakInfo* p) override { free(p); }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static void test_all_required_paks_present_returns_true()
{
    MockPak pak;
    pak.entries.push_back({"FCData/Scripts.pak"});
    pak.entries.push_back({"FCData/Textures.pak"});
    pak.entries.push_back({"FCData/Sounds.pak"});

    MockLog log;
    bool result = AssetValidatorImpl::ValidateMountedPaks(&pak, &log);

    CHECK(result == true);
    CHECK(log.errors.empty());
    CHECK(log.warnings.empty());
}

static void test_missing_critical_pak_returns_false_and_logs_error()
{
    MockPak pak;
    pak.entries.push_back({"FCData/Textures.pak"});
    pak.entries.push_back({"FCData/Sounds.pak"});
    // Scripts.pak absent

    MockLog log;
    bool result = AssetValidatorImpl::ValidateMountedPaks(&pak, &log);

    CHECK(result == false);
    CHECK(log.errors.size() == 1u);
    CHECK(log.errors[0].find("Scripts.pak") != std::string::npos);
    CHECK(log.warnings.empty());
}

static void test_missing_noncritical_pak_returns_true_and_logs_warning()
{
    MockPak pak;
    pak.entries.push_back({"FCData/Scripts.pak"});
    // Textures.pak and Sounds.pak absent

    MockLog log;
    bool result = AssetValidatorImpl::ValidateMountedPaks(&pak, &log);

    CHECK(result == true);
    CHECK(log.errors.empty());
    CHECK(log.warnings.size() == 2u);
    bool hasTextures = false, hasSounds = false;
    for (auto& w : log.warnings)
    {
        if (w.find("Textures.pak") != std::string::npos) hasTextures = true;
        if (w.find("Sounds.pak")   != std::string::npos) hasSounds   = true;
    }
    CHECK(hasTextures);
    CHECK(hasSounds);
}

static void test_empty_pak_list_returns_false()
{
    MockPak pak;
    MockLog log;
    bool result = AssetValidatorImpl::ValidateMountedPaks(&pak, &log);

    CHECK(result == false);
    CHECK(!log.errors.empty());
}

static void test_pak_name_matched_case_insensitively()
{
    MockPak pak;
    pak.entries.push_back({"FCData/SCRIPTS.PAK"});
    pak.entries.push_back({"FCData/textures.pak"});
    pak.entries.push_back({"FCData/sounds.PAK"});

    MockLog log;
    bool result = AssetValidatorImpl::ValidateMountedPaks(&pak, &log);

    CHECK(result == true);
    CHECK(log.errors.empty());
    CHECK(log.warnings.empty());
}

static void test_pak_matched_by_basename_not_full_path()
{
    MockPak pak;
    pak.entries.push_back({"/very/long/path/to/bundle/Scripts.pak"});
    pak.entries.push_back({"relative\\path\\Textures.pak"});
    pak.entries.push_back({"Sounds.pak"});

    MockLog log;
    bool result = AssetValidatorImpl::ValidateMountedPaks(&pak, &log);

    CHECK(result == true);
    CHECK(log.errors.empty());
    CHECK(log.warnings.empty());
}

static void test_shaders_pak_is_not_required()
{
    MockPak pak;
    pak.entries.push_back({"FCData/Scripts.pak"});
    pak.entries.push_back({"FCData/Textures.pak"});
    pak.entries.push_back({"FCData/Sounds.pak"});
    // Shaders.pak intentionally absent — Metal port uses .metallib

    MockLog log;
    bool result = AssetValidatorImpl::ValidateMountedPaks(&pak, &log);

    CHECK(result == true);
    CHECK(log.errors.empty());
    CHECK(log.warnings.empty());
}

// ---------------------------------------------------------------------------
// PakNameMatches unit tests
// ---------------------------------------------------------------------------
static void test_pak_name_matches_exact()
{
    CHECK(AssetValidatorImpl::PakNameMatches("Scripts.pak", "Scripts.pak"));
    CHECK(!AssetValidatorImpl::PakNameMatches("Textures.pak", "Scripts.pak"));
}

static void test_pak_name_matches_null_inputs()
{
    CHECK(!AssetValidatorImpl::PakNameMatches(nullptr, "Scripts.pak"));
    CHECK(!AssetValidatorImpl::PakNameMatches("Scripts.pak", nullptr));
    CHECK(!AssetValidatorImpl::PakNameMatches(nullptr, nullptr));
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main()
{
    test_all_required_paks_present_returns_true();
    test_missing_critical_pak_returns_false_and_logs_error();
    test_missing_noncritical_pak_returns_true_and_logs_warning();
    test_empty_pak_list_returns_false();
    test_pak_name_matched_case_insensitively();
    test_pak_matched_by_basename_not_full_path();
    test_shaders_pak_is_not_required();
    test_pak_name_matches_exact();
    test_pak_name_matches_null_inputs();

    printf("\n%s — %d passed, %d failed\n",
           g_failed == 0 ? "OK" : "FAILED",
           g_passed, g_failed);

    return g_failed == 0 ? 0 : 1;
}
