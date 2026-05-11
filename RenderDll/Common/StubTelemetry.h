#pragma once

#include <ILog.h>
#include <IConsole.h>

extern IConsole* iConsole;
extern ILog*     iLog;

namespace StubTelemetry
{
    inline int GateLevel()
    {
        if (!iConsole)
            return 0;
        static ICVar* s_pTr = nullptr;
        static bool   s_resolved = false;
        if (!s_resolved)
        {
            s_pTr = iConsole->GetCVar("cry_trace_render_gates");
            s_resolved = true;
        }
        return s_pTr ? s_pTr->GetIVal() : 0;
    }

    inline bool ShouldTraceStubs()
    {
        return GateLevel() >= 2 && iLog != nullptr;
    }
}

#define METAL_STUB_TRACE(tag, fmt, ...) \
    do { \
        static int s_hits = 0; \
        ++s_hits; \
        if (::StubTelemetry::ShouldTraceStubs() && (s_hits == 1 || (s_hits % 300) == 0)) \
            iLog->Log("[Stub] " tag " hits=%d " fmt, s_hits, ##__VA_ARGS__); \
    } while (0)

#define METAL_STUB_TRACE_BARE(tag) \
    do { \
        static int s_hits = 0; \
        ++s_hits; \
        if (::StubTelemetry::ShouldTraceStubs() && (s_hits == 1 || (s_hits % 300) == 0)) \
            iLog->Log("[Stub] " tag " hits=%d", s_hits); \
    } while (0)
