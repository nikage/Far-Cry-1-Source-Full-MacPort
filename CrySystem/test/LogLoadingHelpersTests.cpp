#include <cstdio>
#include <cstring>

#include "LogLoadingHelpers.h"

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

#define CHECK_STREQ(a, b) \
	do { \
		const char *_a = (a); \
		const char *_b = (b); \
		if (!_a || !_b || strcmp(_a, _b) != 0) { \
			fprintf(stderr, "FAIL %s:%d  strcmp\n", __FILE__, __LINE__); \
			++g_failed; \
		} else { \
			++g_passed; \
		} \
	} while (0)

static void test_null_and_empty()
{
	CHECK(CryLog_TextAfterVerbosityPrefix(nullptr) == nullptr);
	const char empty[] = "";
	CHECK_STREQ(CryLog_TextAfterVerbosityPrefix(empty), empty);
}

static void test_no_prefix()
{
	const char msg[] = "Loading foo.cgf";
	CHECK_STREQ(CryLog_TextAfterVerbosityPrefix(msg), msg);
}

static void test_control_prefix_stripped()
{
	const char raw[] = "\003Loading bar.cgf";
	CHECK_STREQ(CryLog_TextAfterVerbosityPrefix(raw), "Loading bar.cgf");
}

int main()
{
	test_null_and_empty();
	test_no_prefix();
	test_control_prefix_stripped();
	if (g_failed != 0) {
		fprintf(stderr, "Results: %d passed, %d failed\n", g_passed, g_failed);
		return 1;
	}
	fprintf(stdout, "Results: %d passed, %d failed\n", g_passed, g_failed);
	return 0;
}
