// Standalone unit tests for MacOSspecific.h file-find helpers.
// Regression test for _findclose(-1) / _findnext64(-1) crash.
//
// Build:
//   clang++ -std=c++17 -I../.. -I../../CryCommon -o macos_findclose_tests MacOSFindCloseTests.cpp && ./macos_findclose_tests
//
// NOTE: These tests exercise the portable guard logic only — they do not open
// real directories, so they run on any platform without filesystem fixtures.

#include <cassert>
#include <cstdio>

// Pull in the helpers under test (header-only inline functions)
#include "MacOSspecific.h"

// ---------------------------------------------------------------------------
// Minimal test harness
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); \
            ++g_failed; \
        } else { \
            ++g_passed; \
        } \
    } while (0)

#define CHECK_EQ(a, b) \
    do { \
        auto _a = (a); auto _b = (b); \
        if (!(_a == _b)) { \
            fprintf(stderr, "FAIL %s:%d  expected %lld got %lld\n", \
                    __FILE__, __LINE__, (long long)(_b), (long long)(_a)); \
            ++g_failed; \
        } else { \
            ++g_passed; \
        } \
    } while (0)

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static void test_findclose_null_handle_returns_minus_one()
{
    int result = _findclose((intptr_t)0);
    CHECK_EQ(result, -1);
}

static void test_findclose_error_sentinel_returns_minus_one_no_crash()
{
    // Regression: _findclose(-1) used to dereference 0xffffffffffffffff → crash.
    int result = _findclose((intptr_t)-1);
    CHECK_EQ(result, -1);
}

static void test_findnext64_null_handle_returns_minus_one()
{
    struct __finddata64_t fd = {};
    int result = _findnext64((intptr_t)0, &fd);
    CHECK_EQ(result, -1);
}

static void test_findnext64_error_sentinel_returns_minus_one_no_crash()
{
    // Regression: _findnext64(-1, ...) should guard against the -1 sentinel.
    struct __finddata64_t fd = {};
    int result = _findnext64((intptr_t)-1, &fd);
    CHECK_EQ(result, -1);
}

static void test_findnext64_null_fileinfo_returns_minus_one()
{
    int result = _findnext64((intptr_t)1234, nullptr);
    CHECK_EQ(result, -1);
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main()
{
    test_findclose_null_handle_returns_minus_one();
    test_findclose_error_sentinel_returns_minus_one_no_crash();
    test_findnext64_null_handle_returns_minus_one();
    test_findnext64_error_sentinel_returns_minus_one_no_crash();
    test_findnext64_null_fileinfo_returns_minus_one();

    printf("%s  passed=%d  failed=%d\n",
           g_failed == 0 ? "ALL PASSED" : "FAILURES DETECTED",
           g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
