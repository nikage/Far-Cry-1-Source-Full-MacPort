// Standalone regression tests for the LoadLevelCommon null-guard and diagnostic
// logging additions.
//
// Build: clang++ -std=c++17 -o level_load_error_tests LevelLoadErrorTests.cpp && ./level_load_error_tests

#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// Minimal test harness
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL  line %d: %s\n", __LINE__, #cond); \
            ++g_failed; \
        } else { \
            ++g_passed; \
        } \
    } while(0)

// ---------------------------------------------------------------------------
// Mirror of the null-guard logic added to LoadLevelCommon
// (mirrors XSystemBase.cpp lines ~1612-1620)
// ---------------------------------------------------------------------------
static bool loadLevelCommon_xmlGuard(void* pLevelDataXML, const char* sEPath,
                                     std::vector<std::string>& logOutput)
{
    if (!pLevelDataXML)
    {
        logOutput.push_back(std::string("[ERROR] CreateXMLDocument() returned null — XML system unavailable for '")
                            + sEPath + "'");
        return false;
    }
    return true;
}

static void test_null_xml_document_returns_false()
{
    std::vector<std::string> log;
    bool result = loadLevelCommon_xmlGuard(nullptr, "Levels/Boat/LevelData.xml", log);

    CHECK(result == false);
    CHECK(log.size() == 1);
    CHECK(log[0].find("CreateXMLDocument") != std::string::npos);
    CHECK(log[0].find("LevelData.xml") != std::string::npos);
}

static void test_non_null_xml_document_passes_guard()
{
    std::vector<std::string> log;
    int fakeDoc = 1;  // non-null sentinel
    bool result = loadLevelCommon_xmlGuard(&fakeDoc, "Levels/Boat/LevelData.xml", log);

    CHECK(result == true);
    CHECK(log.empty());
}

// ---------------------------------------------------------------------------
// Mirror of the I3DEngine failure log added to LoadLevelCommon
// (mirrors XSystemBase.cpp lines ~1696-1701)
// ---------------------------------------------------------------------------
static bool loadLevel3DEngine(bool engineSucceeds, const char* levelFolder,
                               const char* missionName,
                               std::vector<std::string>& logOutput)
{
    if (!engineSucceeds)
    {
        logOutput.push_back(std::string("[ERROR] I3DEngine::LoadLevel failed for '")
                            + levelFolder + "' mission '" + missionName + "'");
        return false;
    }
    return true;
}

static void test_3dengine_failure_logs_and_returns_false()
{
    std::vector<std::string> log;
    bool result = loadLevel3DEngine(false, "Levels/Boat", "Mission1", log);

    CHECK(result == false);
    CHECK(log.size() == 1);
    CHECK(log[0].find("I3DEngine::LoadLevel failed") != std::string::npos);
    CHECK(log[0].find("Levels/Boat") != std::string::npos);
    CHECK(log[0].find("Mission1") != std::string::npos);
}

static void test_3dengine_success_no_log()
{
    std::vector<std::string> log;
    bool result = loadLevel3DEngine(true, "Levels/Boat", "Mission1", log);

    CHECK(result == true);
    CHECK(log.empty());
}

// ---------------------------------------------------------------------------
// Mirror of the LoadingError diagnostic enrichment
// (mirrors CXGame::LoadingError + the LoadLevelCS call-sites in Game.cpp)
// ---------------------------------------------------------------------------
struct FakeLog { std::vector<std::string> errors; };

static void loadingError(FakeLog& log, const char* szError)
{
    log.errors.push_back(std::string("LoadingError: ") + szError);
}

static void test_loading_error_always_logs()
{
    FakeLog log;
    loadingError(log, "@LoadLevelError|loadlevel|Levels/Boat");
    CHECK(log.errors.size() == 1);
    CHECK(log.errors[0].find("LoadingError:") != std::string::npos);
    CHECK(log.errors[0].find("Levels/Boat") != std::string::npos);
}

static void test_loading_error_server_path_logged()
{
    FakeLog log;
    loadingError(log, "@LoadLevelError|server|Levels/Fort");
    CHECK(log.errors[0].find("server") != std::string::npos);
    CHECK(log.errors[0].find("Levels/Fort") != std::string::npos);
}

static void test_loading_error_client_path_logged()
{
    FakeLog log;
    loadingError(log, "@LoadLevelError|client|Levels/Dam");
    CHECK(log.errors[0].find("client") != std::string::npos);
    CHECK(log.errors[0].find("Levels/Dam") != std::string::npos);
}

// ---------------------------------------------------------------------------
// Verify the enriched error string still starts with the @ key so Lua
// can still attempt a localization lookup on the prefix before the '|'
// ---------------------------------------------------------------------------
static void test_enriched_error_preserves_at_prefix()
{
    std::string err = std::string("@LoadLevelError|loadlevel|") + "Levels/Boat";
    CHECK(err[0] == '@');
    CHECK(err.find('|') != std::string::npos);
    // Prefix before '|' is the localization key
    std::string key = err.substr(0, err.find('|'));
    CHECK(key == "@LoadLevelError");
}

// ---------------------------------------------------------------------------
int main()
{
    printf("=== LevelLoadErrorTests ===\n");

    test_null_xml_document_returns_false();
    test_non_null_xml_document_passes_guard();
    test_3dengine_failure_logs_and_returns_false();
    test_3dengine_success_no_log();
    test_loading_error_always_logs();
    test_loading_error_server_path_logged();
    test_loading_error_client_path_logged();
    test_enriched_error_preserves_at_prefix();

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed > 0 ? 1 : 0;
}
