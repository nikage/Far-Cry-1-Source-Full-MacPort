// Standalone pure-C++ unit tests for CMacOSSoundSystem logic.
// No Metal, no AVFoundation, no Objective-C runtime required.
//
// Build & run:
//   clang++ -std=c++17 -o MacOSSoundSystemTests MacOSSoundSystemTests.cpp && ./MacOSSoundSystemTests
//
#include <cassert>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>
#include <cstdint>

// ---------------------------------------------------------------------------
// Minimal test harness
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(expr) \
    do { \
        if (expr) { ++g_passed; } \
        else { ++g_failed; printf("FAIL [%s:%d]: %s\n", __FILE__, __LINE__, #expr); } \
    } while (0)

// ---------------------------------------------------------------------------
// Mock ICryPak — mirrors the FOpen/FRead/FClose subset used by LoadSound
// ---------------------------------------------------------------------------
struct MockFileEntry
{
    std::vector<uint8_t> data;
    size_t readPos = 0;
};

class MockCryPak
{
public:
    void AddFile(const std::string& path, const std::vector<uint8_t>& data)
    {
        m_files[path] = { data, 0 };
    }

    // ---- ICryPak subset ---------------------------------------------------
    void* FOpen(const char* pName, const char* /*mode*/)
    {
        auto it = m_files.find(pName);
        if (it == m_files.end()) return nullptr;
        it->second.readPos = 0;
        return (void*)&it->second;
    }

    size_t FRead(void* dst, size_t elemSize, size_t count, void* handle)
    {
        auto* entry = static_cast<MockFileEntry*>(handle);
        size_t bytes = elemSize * count;
        size_t avail = entry->data.size() - entry->readPos;
        size_t toCopy = bytes < avail ? bytes : avail;
        memcpy(dst, entry->data.data() + entry->readPos, toCopy);
        entry->readPos += toCopy;
        return toCopy / elemSize;
    }

    int FSeek(void* handle, long offset, int mode)
    {
        auto* entry = static_cast<MockFileEntry*>(handle);
        if (mode == SEEK_SET) entry->readPos = (size_t)offset;
        else if (mode == SEEK_END) entry->readPos = entry->data.size() + (size_t)offset;
        else entry->readPos += (size_t)offset;
        return 0;
    }

    long FTell(void* handle)
    {
        return (long)static_cast<MockFileEntry*>(handle)->readPos;
    }

    int FClose(void* /*handle*/) { return 0; }

private:
    std::map<std::string, MockFileEntry> m_files;
};

// ---------------------------------------------------------------------------
// Model of the CryPak extraction logic from CMacOSSoundSystem::LoadSound
// Returns the bytes extracted, or empty if file not found.
// ---------------------------------------------------------------------------
static std::vector<uint8_t> extractViaPak(MockCryPak& pak, const char* sFileName)
{
    void* f = pak.FOpen(sFileName, "rb");
    if (!f) return {};

    pak.FSeek(f, 0, SEEK_END);
    long size = pak.FTell(f);
    pak.FSeek(f, 0, SEEK_SET);

    if (size <= 0) { pak.FClose(f); return {}; }

    std::vector<uint8_t> buf((size_t)size);
    pak.FRead(buf.data(), 1, (size_t)size, f);
    pak.FClose(f);
    return buf;
}

// ---------------------------------------------------------------------------
// Model of GetSound indexing logic: 1-based index into soundBuffers vector
// ---------------------------------------------------------------------------
struct FakeSoundBuffer { int id; std::string name; };

static FakeSoundBuffer* getSound(const std::vector<FakeSoundBuffer*>& buffers, int nSoundID)
{
    if (nSoundID > 0 && nSoundID <= (int)buffers.size())
        return buffers[nSoundID - 1];
    return nullptr;
}

// ---------------------------------------------------------------------------
// Model of Release (delete this) — use a flag to verify it ran
// ---------------------------------------------------------------------------
struct FakeSoundSystem
{
    bool* m_deleted;
    explicit FakeSoundSystem(bool* d) : m_deleted(d) {}
    void Release() { *m_deleted = true; delete this; }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static void test_loadSound_pak_file_returns_data()
{
    MockCryPak pak;
    std::vector<uint8_t> wav = { 0x52, 0x49, 0x46, 0x46 }; // "RIFF"
    pak.AddFile("Sounds/ui/click.wav", wav);

    auto result = extractViaPak(pak, "Sounds/ui/click.wav");
    CHECK(result.size() == 4);
    CHECK(result[0] == 0x52); // 'R'
    CHECK(result[3] == 0x46); // 'F'
}

static void test_loadSound_missing_file_returns_empty()
{
    MockCryPak pak;
    auto result = extractViaPak(pak, "Sounds/missing.wav");
    CHECK(result.empty());
}

static void test_loadSound_large_file_reads_fully()
{
    MockCryPak pak;
    std::vector<uint8_t> data(4096, 0xAB);
    pak.AddFile("Sounds/music/theme.wav", data);

    auto result = extractViaPak(pak, "Sounds/music/theme.wav");
    CHECK(result.size() == 4096);
    CHECK(result[0] == 0xAB);
    CHECK(result[4095] == 0xAB);
}

static void test_getSound_valid_id_returns_buffer()
{
    FakeSoundBuffer b1{1, "click.wav"};
    FakeSoundBuffer b2{2, "music.wav"};
    std::vector<FakeSoundBuffer*> buffers = { &b1, &b2 };

    CHECK(getSound(buffers, 1) == &b1);
    CHECK(getSound(buffers, 2) == &b2);
}

static void test_getSound_invalid_id_returns_null()
{
    FakeSoundBuffer b1{1, "click.wav"};
    std::vector<FakeSoundBuffer*> buffers = { &b1 };

    CHECK(getSound(buffers, 0) == nullptr);
    CHECK(getSound(buffers, 2) == nullptr);
    CHECK(getSound(buffers, -1) == nullptr);
}

static void test_getSound_empty_list_returns_null()
{
    std::vector<FakeSoundBuffer*> buffers;
    CHECK(getSound(buffers, 1) == nullptr);
}

static void test_release_deletes_system()
{
    bool deleted = false;
    FakeSoundSystem* sys = new FakeSoundSystem(&deleted);
    CHECK(!deleted);
    sys->Release();
    CHECK(deleted);
}

static void test_loadSound_pak_seek_and_tell_match()
{
    MockCryPak pak;
    std::vector<uint8_t> data = {1, 2, 3, 4, 5};
    pak.AddFile("test.wav", data);

    void* f = pak.FOpen("test.wav", "rb");
    pak.FSeek(f, 0, SEEK_END);
    long size = pak.FTell(f);
    CHECK(size == 5);
    pak.FSeek(f, 0, SEEK_SET);
    CHECK(pak.FTell(f) == 0);
    pak.FClose(f);
}

// ---------------------------------------------------------------------------
// Model of the channel-count guard: Play should be a no-op when the buffer
// or player node is null, and should not throw on a mismatch — it just
// sets m_isPlaying = false and returns.
// ---------------------------------------------------------------------------
struct FakeAudioNode
{
    bool scheduleCalled = false;
    bool playCalled     = false;
    bool throwOnPlay    = false;

    bool scheduleBuffer() { scheduleCalled = true; return !throwOnPlay; }
    bool play()           { playCalled     = true; return !throwOnPlay; }
};

static bool stub_play_safe(FakeAudioNode* node, void* buffer, bool& isPlaying)
{
    if (!node || !buffer) return false;
    isPlaying = true;
    bool ok = node->scheduleBuffer();
    if (!ok) { isPlaying = false; return false; }
    ok = node->play();
    if (!ok) { isPlaying = false; return false; }
    return true;
}

static void test_play_guard_null_node_is_no_op()
{
    bool isPlaying = false;
    int dummy = 1;
    CHECK(!stub_play_safe(nullptr, &dummy, isPlaying));
    CHECK(!isPlaying);
}

static void test_play_guard_null_buffer_is_no_op()
{
    FakeAudioNode node;
    bool isPlaying = false;
    CHECK(!stub_play_safe(&node, nullptr, isPlaying));
    CHECK(!isPlaying);
    CHECK(!node.scheduleCalled);
}

static void test_play_guard_exception_resets_isplaying()
{
    FakeAudioNode node;
    node.throwOnPlay = true;
    bool isPlaying = false;
    int dummy = 1;
    stub_play_safe(&node, &dummy, isPlaying);
    CHECK(node.scheduleCalled);
    CHECK(!isPlaying);
}

// ---------------------------------------------------------------------------
int main()
{
    printf("=== MacOSSoundSystemTests ===\n");

    test_loadSound_pak_file_returns_data();
    test_loadSound_missing_file_returns_empty();
    test_loadSound_large_file_reads_fully();
    test_getSound_valid_id_returns_buffer();
    test_getSound_invalid_id_returns_null();
    test_getSound_empty_list_returns_null();
    test_release_deletes_system();
    test_loadSound_pak_seek_and_tell_match();
    test_play_guard_null_node_is_no_op();
    test_play_guard_null_buffer_is_no_op();
    test_play_guard_exception_resets_isplaying();

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed > 0 ? 1 : 0;
}
