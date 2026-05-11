#ifndef METALDRAWDIAG_H
#define METALDRAWDIAG_H

#import <Metal/Metal.h>

namespace MetalDrawDiag {

void OnDrawCall(const char* site,
                id<MTLRenderCommandEncoder> enc,
                id<MTLRenderPipelineState> pso,
                MTLPrimitiveType prim,
                NSUInteger vertexCount,
                NSUInteger indexCount);

void OnDepthDisableFired();

void OnPSOBind(const char* site,
               const char* shaderName,
               id<MTLRenderCommandEncoder> enc,
               id<MTLRenderPipelineState> pso,
               int vfmt);

void EnterEf3DScope();
void LeaveEf3DScope();

struct Ef3DScopeGuard
{
    Ef3DScopeGuard()  { EnterEf3DScope(); }
    ~Ef3DScopeGuard() { LeaveEf3DScope(); }
};

} // namespace MetalDrawDiag

#endif // METALDRAWDIAG_H
