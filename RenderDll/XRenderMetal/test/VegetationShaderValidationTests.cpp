// Regression tests for CheckValidVegetation shader-name acceptance list.
//
// Background: CheckValidVegetation (Cry3DEngine/StatObjConstr.cpp) warns when a
// vegetation object's shader template name is not recognised as a valid plant shader.
// The original code only accepted names containing "templplants". The Metal renderer
// registers plant shaders as "cgrcplants" and "cgrcambienttempl", causing hundreds of
// spurious warnings per level load on macOS and potentially wrong fallback shaders.
//
// Fix: added "cgrcplants" and "cgrcambienttempl" to the accepted-name set and extended
// the #ifndef guard to cover __APPLE__ so no false warning fires on macOS.
//
// These tests mirror the acceptance predicate from StatObjConstr.cpp so that any
// future change to the accepted-name set can be caught at CI time.
//
// Build & run (from RenderDll/XRenderMetal/test/):
//   clang++ -std=c++17 -o vegetation_shader_tests VegetationShaderValidationTests.cpp && ./vegetation_shader_tests

#include <string>
#include <cstring>
#include <cctype>
#include <cstdio>

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

// Mirrors the acceptance predicate in CStatObj::CheckValidVegetation.
static bool isAcceptedVegetationTemplate(const char* pTemplateName)
{
    char buff[64];
    strncpy(buff, pTemplateName, sizeof(buff));
    buff[sizeof(buff) - 1] = '\0';
    for (int i = 0; buff[i]; ++i)
        buff[i] = (char)tolower((unsigned char)buff[i]);

    return strstr(buff, "templplants")           != nullptr
        || strstr(buff, "cgrcplants")            != nullptr
        || strstr(buff, "cgrcambienttempl")      != nullptr
        || strstr(buff, "nodraw")                != nullptr
        || strstr(buff, "templdecal_vcolors")    != nullptr
        || strstr(buff, "templdecalalphatest_vcolors") != nullptr;
}

int main()
{
    printf("=== VegetationShaderValidationTests ===\n");

    // Names that MUST be accepted (no warning / correct shader path).
    CHECK(isAcceptedVegetationTemplate("templplants"),
          "original plant template accepted");
    CHECK(isAcceptedVegetationTemplate("TemplPlants"),
          "case-insensitive plant template accepted");
    CHECK(isAcceptedVegetationTemplate("cgrcplants"),
          "Metal cgrcplants accepted");
    CHECK(isAcceptedVegetationTemplate("CGRCPlants"),
          "Metal cgrcplants case-insensitive accepted");
    CHECK(isAcceptedVegetationTemplate("cgrcambienttempl"),
          "Metal cgrcambienttempl accepted");
    CHECK(isAcceptedVegetationTemplate("CGRCAmbientTempl"),
          "Metal cgrcambienttempl case-insensitive accepted");
    CHECK(isAcceptedVegetationTemplate("nodraw"),
          "nodraw accepted");
    CHECK(isAcceptedVegetationTemplate("templdecal_vcolors"),
          "templdecal_vcolors accepted");
    CHECK(isAcceptedVegetationTemplate("templdecalalphatest_vcolors"),
          "templdecalalphatest_vcolors accepted");

    // Names that must NOT be accepted (trigger the warning path).
    CHECK(!isAcceptedVegetationTemplate("default"),
          "default shader not accepted as vegetation");
    CHECK(!isAcceptedVegetationTemplate("cgrcbump_diffspec"),
          "bump-spec shader not accepted as vegetation");
    CHECK(!isAcceptedVegetationTemplate(""),
          "empty name not accepted");

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
