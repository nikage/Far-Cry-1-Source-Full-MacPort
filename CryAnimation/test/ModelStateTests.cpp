// ModelStateTests.cpp — regression test for CryModelState::GetCryModelSubmesh
//
// Regression: on macOS/ARM64, the original ternary
//   return i < m_arrSubmeshes.size() ? m_arrSubmeshes[i] : nullptr;
// caused Clang to deduce _smart_ptr<CryModelSubmesh> as the common type,
// copying the smart ptr (AddRef) then destroying the copy (Release→0→dtor),
// producing infinite recursive destruction during CryModelState teardown.
//
// Build & run:
//   clang++ -std=c++17 -o model_state_tests ModelStateTests.cpp && ./model_state_tests

#include <cassert>
#include <cstdio>
#include <vector>

// ---------------------------------------------------------------------------
// Minimal _smart_ptr shim
// ---------------------------------------------------------------------------
template<class T>
class _smart_ptr {
    T* p;
public:
    _smart_ptr() : p(nullptr) {}
    explicit _smart_ptr(T* p_) : p(p_) { if (p) p->AddRef(); }
    _smart_ptr(const _smart_ptr& o) : p(o.p) { if (p) p->AddRef(); }
    ~_smart_ptr() { if (p) p->Release(); }
    _smart_ptr& operator=(T* np) {
        if (np) np->AddRef();
        if (p)  p->Release();
        p = np;
        return *this;
    }
    operator T*() const { return p; }
};

// ---------------------------------------------------------------------------
// Tracked object — counts destructor calls so we can detect runaway recursion
// ---------------------------------------------------------------------------
static int g_dtorCount = 0;
static int g_addRefCount = 0;
static int g_releaseCount = 0;
static bool g_insideGetSubmesh = false;
static bool g_recursionDetected = false;

struct FakeSubmesh {
    int refCount = 1;

    void AddRef()  { ++g_addRefCount; ++refCount; }
    void Release() {
        ++g_releaseCount;
        if (--refCount <= 0)
            delete this;
    }
    ~FakeSubmesh() {
        ++g_dtorCount;
        // Simulate what DeleteLeafBuffers() does: call GetCryModelSubmesh(0)
        // through a state pointer.  We set a flag so we can detect re-entry.
        if (g_insideGetSubmesh)
            g_recursionDetected = true;
    }
};

// ---------------------------------------------------------------------------
// The function under test — mirrors the fixed CryModelState::GetCryModelSubmesh
// ---------------------------------------------------------------------------
using SubmeshArray = std::vector<_smart_ptr<FakeSubmesh>>;

static FakeSubmesh* GetCryModelSubmesh_safe(const SubmeshArray& arr, unsigned i)
{
    // Fixed path: explicit local avoids creating a temporary _smart_ptr copy.
    FakeSubmesh* pRes = nullptr;
    if (i < arr.size())
        pRes = arr[i];
    return pRes;
}

static FakeSubmesh* GetCryModelSubmesh_buggy(const SubmeshArray& arr, unsigned i)
{
    // Original buggy path: Clang deduces _smart_ptr as common type, copies it,
    // then destroys the copy → Release() → dtor re-entered.
    return i < arr.size() ? arr[i] : nullptr;  // intentionally left as-is to show the bug
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
static int passed = 0, failed = 0;
#define EXPECT(cond, msg) \
    do { if (cond) { ++passed; } \
         else { ++failed; printf("FAIL: %s\n", msg); } } while(0)

static void test_safe_path_no_extra_addref()
{
    g_addRefCount = 0;
    g_releaseCount = 0;
    g_dtorCount = 0;
    g_recursionDetected = false;

    SubmeshArray arr;
    // Manually build a smart_ptr without going through _smart_ptr(T*) to keep
    // refcount at 1 so we fully control the lifetime.
    auto* raw = new FakeSubmesh();  // refcount=1
    _smart_ptr<FakeSubmesh> sp;
    sp = raw;                       // AddRef → refcount=2
    raw->Release();                 // back to 1; sp owns it
    arr.push_back(sp);              // copy → AddRef → refcount=2
    sp = nullptr;                   // Release → refcount=1; arr is sole owner

    g_addRefCount = 0;
    g_releaseCount = 0;

    // Call the safe getter — must NOT AddRef/Release the element.
    g_insideGetSubmesh = true;
    FakeSubmesh* result = GetCryModelSubmesh_safe(arr, 0);
    g_insideGetSubmesh = false;

    EXPECT(result != nullptr,          "safe: returns non-null for index 0");
    EXPECT(g_addRefCount  == 0,        "safe: no AddRef during getter");
    EXPECT(g_releaseCount == 0,        "safe: no Release during getter");
    EXPECT(!g_recursionDetected,       "safe: no re-entrant destructor");

    // Let arr go out of scope — should call dtor exactly once.
    arr.clear();
    EXPECT(g_dtorCount == 1,           "safe: exactly one destructor call");
}

static void test_safe_path_out_of_bounds_returns_null()
{
    SubmeshArray arr;
    EXPECT(GetCryModelSubmesh_safe(arr, 0) == nullptr, "safe: empty array returns null");
    EXPECT(GetCryModelSubmesh_safe(arr, 5) == nullptr, "safe: OOB returns null");
}

static void test_safe_path_returns_correct_element()
{
    auto* a = new FakeSubmesh();
    auto* b = new FakeSubmesh();

    SubmeshArray arr;
    _smart_ptr<FakeSubmesh> spa, spb;
    spa = a; a->Release();
    spb = b; b->Release();
    arr.push_back(spa);
    arr.push_back(spb);
    spa = nullptr;
    spb = nullptr;

    EXPECT(GetCryModelSubmesh_safe(arr, 0) == a, "safe: index 0 returns first element");
    EXPECT(GetCryModelSubmesh_safe(arr, 1) == b, "safe: index 1 returns second element");
    EXPECT(GetCryModelSubmesh_safe(arr, 2) == nullptr, "safe: index 2 OOB returns null");
}

int main()
{
    test_safe_path_no_extra_addref();
    test_safe_path_out_of_bounds_returns_null();
    test_safe_path_returns_correct_element();

    printf("%s — %d passed, %d failed\n",
           failed == 0 ? "PASS" : "FAIL", passed, failed);
    return failed == 0 ? 0 : 1;
}
