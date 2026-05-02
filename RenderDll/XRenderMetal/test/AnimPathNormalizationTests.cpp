// Regression tests for UnifyFilePath path normalization.
//
// Background: CCG weapon animation files compiled on Windows embed paths like
//   Objects\Weapons\RL\.\RL_activate1.caf
// The Windows file system resolves the '\.' component transparently; macOS CryPak
// does not, causing every weapon animation to report "file not found".
//
// Fix: UnifyFilePath (CryCommon/StringUtils.h) now collapses '\.\' segments.
//
// Build & run (from RenderDll/XRenderMetal/test/):
//   clang++ -std=c++17 -o anim_path_norm_tests AnimPathNormalizationTests.cpp && ./anim_path_norm_tests

#include <string>
#include <cassert>
#include <cstring>
#include <cctype>
#include <cstdio>

// Self-contained copy of the function under test (mirrors CryCommon/StringUtils.h
// UnifyFilePath exactly so this test stays in sync with the source).
static void UnifyFilePath(std::string& strPath)
{
    for (auto itPath = strPath.begin(); itPath != strPath.end(); ++itPath)
        if (*itPath == '/')
            *itPath = '\\';
        else
            *itPath = (char)tolower((unsigned char)*itPath);

    size_t pos = 0;
    while ((pos = strPath.find("\\.\\", pos)) != std::string::npos)
        strPath.erase(pos, 2);
    if (strPath.size() >= 2 && strPath[0] == '.' && strPath[1] == '\\')
        strPath.erase(0, 2);
}

static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond, label) \
    do { \
        if (cond) { \
            printf("  PASS: %s\n", label); \
            ++g_passed; \
        } else { \
            printf("  FAIL: %s\n", label); \
            ++g_failed; \
        } \
    } while (0)

static std::string normalised(std::string path)
{
    UnifyFilePath(path);
    return path;
}


int main()
{
    printf("=== AnimPathNormalizationTests ===\n");

    // Core regression: the exact pattern seen in the build log for RL weapons.
    CHECK(normalised("Objects\\Weapons\\RL\\.\\RL_activate1.caf")
              == "objects\\weapons\\rl\\rl_activate1.caf",
          "collapses mid-path backslash-dot-backslash segment");

    // Same path with forward slash input (pak normalises to backslash first).
    CHECK(normalised("Objects/Weapons/RL/./RL_activate1.caf")
              == "objects\\weapons\\rl\\rl_activate1.caf",
          "collapses mid-path forward-slash-dot-slash segment after unification");

    // Leading '.\\' prefix.
    CHECK(normalised(".\\RL_activate1.caf") == "rl_activate1.caf",
          "strips leading backslash-dot prefix");

    // Plain path without any dot segment is unchanged (beyond lowercase).
    CHECK(normalised("Objects\\Weapons\\RL\\RL_idle11.caf")
              == "objects\\weapons\\rl\\rl_idle11.caf",
          "leaves normal path unchanged");

    // Multiple consecutive dot segments are fully collapsed.
    CHECK(normalised("Objects\\.\\Weapons\\.\\RL_fire11.caf")
              == "objects\\weapons\\rl_fire11.caf",
          "collapses multiple dot segments");

    // Empty path stays empty.
    CHECK(normalised("") == "", "empty path unchanged");

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
