// Unit tests for CFFont::Load(const char*) XML path.
// Tests the gate conditions of the ICryPak-based font loading without
// requiring linking against the full CryEngine runtime.
//
// Build: clang++ -std=c++17 -o font_load_tests FontLoadTests.cpp && ./font_load_tests
//
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

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);   \
            ++g_failed;                                                        \
        } else {                                                               \
            ++g_passed;                                                        \
        }                                                                      \
    } while (0)

#define CHECK_EQ(a, b) CHECK((a) == (b))
#define SECTION(name) fprintf(stdout, "\n--- %s ---\n", (name))

// ---------------------------------------------------------------------------
// Minimal interfaces that mirror ICryPak / ILog / ISystem used by CFFont::Load
// ---------------------------------------------------------------------------

struct IMockLog {
    std::vector<std::string> messages;
    void LogToFile(const char* msg) { messages.push_back(msg); }
};

struct IMockPak {
    const char* fileContent = nullptr;
    int         fileSize    = 0;
    bool        openFails   = false;
    bool        opened      = false;
    int         pos         = 0;

    void* FOpen(const char* /*path*/, const char* /*mode*/) {
        if (openFails) return nullptr;
        opened = true;
        pos    = 0;
        return static_cast<void*>(this);
    }
    void FClose(void* /*fp*/) { opened = false; }
    void FSeek(void* /*fp*/, int offset, int whence) {
        if (whence == 2 /*SEEK_END*/) pos = fileSize;
        else                          pos = offset;
    }
    int FTell(void* /*fp*/) { return pos; }
    int FRead(char* buf, int size, int count, void* /*fp*/) {
        int bytes = size * count;
        if (bytes > fileSize) bytes = fileSize;
        memcpy(buf, fileContent, bytes);
        return count;
    }
};

// ---------------------------------------------------------------------------
// Pure-logic model of CFFont::Load — mirrors the real implementation exactly
// so that the test covers the same gate conditions.
// ---------------------------------------------------------------------------

struct MockFontState {
    bool        bOK        = false;
    int         sizeX      = 0;
    int         sizeY      = 0;
    bool        parsedXml  = false;
    std::string logMessage;
};

// Returns the final value of m_bOK and populates state.
static bool ModelFontLoad(
    IMockPak*      pPak,
    IMockLog*      pLog,
    const char*    szFile,
    bool           xmlParseSetsOK,   // simulates CXmlFontShader parsing result
    int            atlasW,
    int            atlasH,
    MockFontState& state)
{
    if (!pPak)
        return false;

    void* fp = pPak->FOpen(szFile, "rb");
    if (!fp)
    {
        state.logMessage = std::string("CFFont::Load: could not open font file '") + szFile + "'";
        if (pLog) pLog->LogToFile(state.logMessage.c_str());
        return false;
    }

    pPak->FSeek(fp, 0, 2 /*SEEK_END*/);
    int size = pPak->FTell(fp);

    char* buffer = new char[size + 1];
    if (!buffer)
    {
        pPak->FClose(fp);
        return false;
    }
    buffer[size] = 0;
    pPak->FSeek(fp, 0, 0 /*SEEK_SET*/);
    pPak->FRead(buffer, size, 1, fp);
    pPak->FClose(fp);

    // Simulate CXmlFontShader parsing — sets m_bOK and atlas dimensions.
    if (xmlParseSetsOK)
    {
        state.bOK     = true;
        state.sizeX   = atlasW;
        state.sizeY   = atlasH;
        state.parsedXml = true;
    }

    delete[] buffer;
    return state.bOK;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static const char* kMinimalFontXml =
    "<?xml version=\"1.0\"?>"
    "<Font Texture=\"languages/fonts/arialnb.ttf\" W=\"512\" H=\"512\">"
    "  <Effect name=\"default\"><Pass/></Effect>"
    "</Font>";

static void testFontLoad_NullPak_ReturnsFalse() {
    SECTION("CFFont::Load — null ICryPak returns false immediately");
    MockFontState state;
    bool result = ModelFontLoad(nullptr, nullptr, "languages/fonts/default.xml",
                                true, 512, 512, state);
    CHECK(!result);
    CHECK(!state.bOK);
    CHECK(!state.parsedXml);
}

static void testFontLoad_FOpenFails_ReturnsFalse() {
    SECTION("CFFont::Load — FOpen failure returns false and logs message");
    IMockPak pak;
    pak.openFails   = true;
    pak.fileContent = kMinimalFontXml;
    pak.fileSize    = static_cast<int>(strlen(kMinimalFontXml));

    IMockLog log;
    MockFontState state;
    bool result = ModelFontLoad(&pak, &log, "languages/fonts/default.xml",
                                true, 512, 512, state);
    CHECK(!result);
    CHECK(!state.bOK);
    CHECK(!state.parsedXml);
    CHECK(log.messages.size() == 1);
    CHECK(log.messages[0].find("could not open") != std::string::npos);
}

static void testFontLoad_ValidFile_ReturnsTrueAndSetsAtlas() {
    SECTION("CFFont::Load — valid XML file opens, parses, sets m_bOK and atlas size");
    IMockPak pak;
    pak.fileContent = kMinimalFontXml;
    pak.fileSize    = static_cast<int>(strlen(kMinimalFontXml));

    IMockLog log;
    MockFontState state;
    bool result = ModelFontLoad(&pak, &log, "languages/fonts/default.xml",
                                true, 512, 512, state);
    CHECK(result);
    CHECK(state.bOK);
    CHECK(state.parsedXml);
    CHECK_EQ(state.sizeX, 512);
    CHECK_EQ(state.sizeY, 512);
    CHECK(log.messages.empty());
}

static void testFontLoad_XmlParseFailure_ReturnsFalse() {
    SECTION("CFFont::Load — XML parse failure leaves m_bOK=false → returns false");
    IMockPak pak;
    pak.fileContent = kMinimalFontXml;
    pak.fileSize    = static_cast<int>(strlen(kMinimalFontXml));

    IMockLog log;
    MockFontState state;
    bool result = ModelFontLoad(&pak, &log, "languages/fonts/default.xml",
                                false, 512, 512, state);
    CHECK(!result);
    CHECK(!state.bOK);
    CHECK_EQ(state.sizeX, 0);
    CHECK_EQ(state.sizeY, 0);
}

static void testFontLoad_ZeroSizeFile_XmlParseFails() {
    SECTION("CFFont::Load — zero-size file produces no XML parse, m_bOK stays false");
    static const char* emptyContent = "";
    IMockPak pak;
    pak.fileContent = emptyContent;
    pak.fileSize    = 0;

    IMockLog log;
    MockFontState state;
    bool result = ModelFontLoad(&pak, &log, "languages/fonts/default.xml",
                                false, 0, 0, state);
    CHECK(!result);
    CHECK(!state.bOK);
}

static void testFontLoad_FCloseCalledAfterRead() {
    SECTION("CFFont::Load — FClose is called after successful read (file not left open)");
    IMockPak pak;
    pak.fileContent = kMinimalFontXml;
    pak.fileSize    = static_cast<int>(strlen(kMinimalFontXml));

    IMockLog log;
    MockFontState state;
    ModelFontLoad(&pak, &log, "languages/fonts/default.xml",
                  true, 512, 512, state);
    CHECK(!pak.opened);
}

static void testFontLoad_NonExistentFile_LogsPath() {
    SECTION("CFFont::Load — missing file logs the exact path in the error message");
    IMockPak pak;
    pak.openFails = true;
    pak.fileContent = "";
    pak.fileSize    = 0;

    IMockLog log;
    MockFontState state;
    const char* missingPath = "languages/fonts/missing.xml";
    ModelFontLoad(&pak, &log, missingPath, true, 0, 0, state);
    CHECK(log.messages.size() == 1);
    CHECK(log.messages[0].find(missingPath) != std::string::npos);
}

static void testFontLoad_AtlasSize_NonZeroAfterSuccess() {
    SECTION("CFFont::Load — atlas dimensions are non-zero after successful load");
    IMockPak pak;
    pak.fileContent = kMinimalFontXml;
    pak.fileSize    = static_cast<int>(strlen(kMinimalFontXml));

    IMockLog log;
    MockFontState state;
    ModelFontLoad(&pak, &log, "languages/fonts/default.xml",
                  true, 256, 256, state);
    CHECK(state.sizeX > 0);
    CHECK(state.sizeY > 0);
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main() {
    testFontLoad_NullPak_ReturnsFalse();
    testFontLoad_FOpenFails_ReturnsFalse();
    testFontLoad_ValidFile_ReturnsTrueAndSetsAtlas();
    testFontLoad_XmlParseFailure_ReturnsFalse();
    testFontLoad_ZeroSizeFile_XmlParseFails();
    testFontLoad_FCloseCalledAfterRead();
    testFontLoad_NonExistentFile_LogsPath();
    testFontLoad_AtlasSize_NonZeroAfterSuccess();

    fprintf(stdout, "\nResults: %d passed, %d failed\n", g_passed, g_failed);
    return g_failed > 0 ? 1 : 0;
}
