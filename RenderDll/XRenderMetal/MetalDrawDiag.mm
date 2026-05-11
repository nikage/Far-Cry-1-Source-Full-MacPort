#include "MetalDrawDiag.h"

#include "MetalRenderPCH.h"
#include <ILog.h>

extern ILog* iLog;
extern int g_metal_debug_dump_draws;
extern int g_metal_debug_dump_scope;

namespace MetalDrawDiag {

static int s_ef3dScopeDepth = 0;

void EnterEf3DScope() { ++s_ef3dScopeDepth; }
void LeaveEf3DScope()
{
    if (s_ef3dScopeDepth > 0)
        --s_ef3dScopeDepth;
}

void OnDrawCall(const char* site,
                id<MTLRenderCommandEncoder> enc,
                id<MTLRenderPipelineState> pso,
                MTLPrimitiveType prim,
                NSUInteger vertexCount,
                NSUInteger indexCount)
{
    if (g_metal_debug_dump_draws <= 0 || !iLog)
        return;
    if (g_metal_debug_dump_scope == 1 && s_ef3dScopeDepth == 0)
        return;
    --g_metal_debug_dump_draws;
    iLog->Log("\003[MetalDiag] Draw site=%s ef3d=%d enc=%p pso=%p prim=%lu verts=%lu indices=%lu",
              site ? site : "?",
              s_ef3dScopeDepth,
              (void*)enc,
              (void*)pso,
              (unsigned long)prim,
              (unsigned long)vertexCount,
              (unsigned long)indexCount);
}

void OnDepthDisableFired()
{
    static bool s_loggedOnce = false;
    if (s_loggedOnce || !iLog)
        return;
    s_loggedOnce = true;
    iLog->Log("\003[MetalDiag] depth-disable engaged: SetDepthTest(false) applied in EF_EndEf3D drawBucket");
}

void OnPSOBind(const char* site,
               const char* shaderName,
               id<MTLRenderCommandEncoder> enc,
               id<MTLRenderPipelineState> pso,
               int vfmt)
{
    if (g_metal_debug_dump_draws <= 0 || !iLog)
        return;
    if (g_metal_debug_dump_scope == 1 && s_ef3dScopeDepth == 0)
        return;
    iLog->Log("\003[MetalDiag] PSO bind site=%s shader=%s vfmt=%d enc=%p pso=%p",
              site ? site : "?",
              shaderName ? shaderName : "?",
              vfmt,
              (void*)enc,
              (void*)pso);
}

} // namespace MetalDrawDiag
