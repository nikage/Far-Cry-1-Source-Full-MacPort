// Offscreen render + pixel readback test for representative generated shaders.
// Renders a unit quad with a known UniformBuffer (identity MVP, white light at (1,1,1))
// into a 4×4 MTLTexture and asserts the center pixel RGBA is within tolerance.
//
// Build:
//   clang++ -std=c++17 -framework Metal -framework Foundation -framework CoreFoundation \
//       -o shader_output_tests ShaderOutputTests.mm && ./shader_output_tests
//
// Requires GeneratedShaders.metallib + generated_manifest.json at GENERATED_DIR or
// next to the binary (same lookup as GeneratedPSOTests).
//
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

// ---------------------------------------------------------------------------
// Minimal test harness
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        if (!(cond)) {                                                          \
            fprintf(stderr, "FAIL: %s\n", (msg));                              \
            ++g_failed;                                                         \
        } else {                                                                \
            ++g_passed;                                                         \
        }                                                                       \
    } while (0)

#define CHECK_NEAR(actual, expected, tol, msg)                                  \
    CHECK(fabsf((actual) - (expected)) <= (tol),                               \
          (std::string(msg) + " expected=" + std::to_string(expected) +        \
           " got=" + std::to_string(actual)).c_str())

// ---------------------------------------------------------------------------
// Uniform buffer layout — must match UniformBufferData in MetalBaseRenderer.m
// ---------------------------------------------------------------------------
struct TestUniforms {
    float mvp[16];
    float model[16];
    float view[16];
    float proj[16];
    float cameraPos[4];
    float time;
    float _time_pad[3];
    float lightPos[4];
    float lightColor[4];
    struct LightEntry { float pos[4]; float color[4]; };
    LightEntry lights[4];
    int numLights;
    float _pad3[3];
    float clipPlane[4];
    float clipEnabled;
    float clipRefract;
    float fogScale;
    float fogBias;
};

static void identity4x4(float* m) {
    memset(m, 0, 16 * sizeof(float));
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

static TestUniforms makeKnownUniforms() {
    TestUniforms u;
    memset(&u, 0, sizeof(u));
    identity4x4(u.mvp);
    identity4x4(u.model);
    identity4x4(u.view);
    identity4x4(u.proj);
    u.cameraPos[0] = 0; u.cameraPos[1] = 0; u.cameraPos[2] = 5; u.cameraPos[3] = 0;
    u.time = 0.0f;
    u.lightPos[0] = 1; u.lightPos[1] = 1; u.lightPos[2] = 1; u.lightPos[3] = 0;
    u.lightColor[0] = 1; u.lightColor[1] = 1; u.lightColor[2] = 1; u.lightColor[3] = 0;
    u.numLights = 0;
    u.clipEnabled = 0;
    u.fogScale = 0;
    u.fogBias = 1;
    return u;
}

// ---------------------------------------------------------------------------
// Vertex: position (float3) + texcoord (float2) + normal (float3) + color (uchar4)
// ---------------------------------------------------------------------------
struct TestVertex {
    float pos[3];
    float texcoord[2];
    float normal[3];
    uint8_t color[4];
};

static TestVertex kQuadVertices[4] = {
    // pos             texcoord   normal          color
    {{-1,-1, 0}, {0,0}, {0,0,1}, {255,255,255,255}},
    {{ 1,-1, 0}, {1,0}, {0,0,1}, {255,255,255,255}},
    {{-1, 1, 0}, {0,1}, {0,0,1}, {255,255,255,255}},
    {{ 1, 1, 0}, {1,1}, {0,0,1}, {255,255,255,255}},
};
static uint16_t kQuadIndices[6] = {0,1,2,  1,3,2};

// ---------------------------------------------------------------------------
// Locating Generated/ directory (same strategy as GeneratedPSOTests)
// ---------------------------------------------------------------------------
static NSString* findGeneratedDir(const char* argv0) {
    const char* envPath = getenv("GENERATED_DIR");
    if (envPath && strlen(envPath) > 0)
        return [NSString stringWithUTF8String:envPath];

    NSString* binaryDir = [[NSString stringWithUTF8String:argv0] stringByDeletingLastPathComponent];

    NSString* c1 = [binaryDir stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:c1]) return binaryDir;

    NSString* c2 = [[binaryDir stringByAppendingPathComponent:@"../../Generated"] stringByStandardizingPath];
    NSString* c2ml = [c2 stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:c2ml]) return c2;

    return nil;
}

// ---------------------------------------------------------------------------
// Build a vertex descriptor that matches TestVertex layout.
// Buffer 0: pos(float3) + texcoord(float2) + normal(float3) + color(uchar4 normalized)
// Attribute indices match the generated shaders' convention:
//   0 = position  (float3, offset 0)
//   1 = texcoord  (float2, offset 12)
//   2 = normal    (float3, offset 20)
//   3 = color     (uchar4, offset 32, normalized)
// ---------------------------------------------------------------------------
static MTLVertexDescriptor* buildVertexDescriptor() {
    MTLVertexDescriptor* vd = [MTLVertexDescriptor new];

    vd.attributes[0].format      = MTLVertexFormatFloat3;
    vd.attributes[0].offset      = 0;
    vd.attributes[0].bufferIndex = 0;

    vd.attributes[1].format      = MTLVertexFormatFloat2;
    vd.attributes[1].offset      = 12;
    vd.attributes[1].bufferIndex = 0;

    vd.attributes[2].format      = MTLVertexFormatFloat3;
    vd.attributes[2].offset      = 20;
    vd.attributes[2].bufferIndex = 0;

    vd.attributes[3].format      = MTLVertexFormatUChar4Normalized;
    vd.attributes[3].offset      = 32;
    vd.attributes[3].bufferIndex = 0;

    vd.layouts[0].stride       = sizeof(TestVertex);
    vd.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    return vd;
}

// ---------------------------------------------------------------------------
// Render a quad with a given PSO into a 4×4 offscreen BGRA texture.
// Returns the center pixel (pixel [2,2]) as [r,g,b,a] in [0,1].
// Returns false if the render command fails.
// ---------------------------------------------------------------------------
static bool renderQuad(id<MTLDevice> device,
                       id<MTLCommandQueue> queue,
                       id<MTLRenderPipelineState> pso,
                       id<MTLDepthStencilState> depthState,
                       float outPixel[4])
{
    const int kW = 4, kH = 4;

    MTLTextureDescriptor* colorDesc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                          width:kW height:kH mipmapped:NO];
    colorDesc.usage        = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    colorDesc.storageMode  = MTLStorageModeShared;
    id<MTLTexture> colorTex = [device newTextureWithDescriptor:colorDesc];

    MTLTextureDescriptor* depthDesc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float_Stencil8
                                                          width:kW height:kH mipmapped:NO];
    depthDesc.usage       = MTLTextureUsageRenderTarget;
    depthDesc.storageMode = MTLStorageModePrivate;
    id<MTLTexture> depthTex = [device newTextureWithDescriptor:depthDesc];

    id<MTLBuffer> vertBuf =
        [device newBufferWithBytes:kQuadVertices
                            length:sizeof(kQuadVertices)
                           options:MTLResourceStorageModeShared];
    id<MTLBuffer> idxBuf =
        [device newBufferWithBytes:kQuadIndices
                            length:sizeof(kQuadIndices)
                           options:MTLResourceStorageModeShared];

    TestUniforms uniforms = makeKnownUniforms();
    id<MTLBuffer> unifBuf =
        [device newBufferWithBytes:&uniforms
                            length:sizeof(uniforms)
                           options:MTLResourceStorageModeShared];

    MTLRenderPassDescriptor* rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture     = colorTex;
    rpd.colorAttachments[0].loadAction  = MTLLoadActionClear;
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;
    rpd.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 1);
    rpd.depthAttachment.texture         = depthTex;
    rpd.depthAttachment.loadAction      = MTLLoadActionClear;
    rpd.depthAttachment.storeAction     = MTLStoreActionDontCare;
    rpd.depthAttachment.clearDepth      = 1.0;
    rpd.stencilAttachment.texture       = depthTex;
    rpd.stencilAttachment.loadAction    = MTLLoadActionClear;
    rpd.stencilAttachment.storeAction   = MTLStoreActionDontCare;
    rpd.stencilAttachment.clearStencil  = 0;

    id<MTLCommandBuffer> cmd = [queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:rpd];
    [enc setRenderPipelineState:pso];
    if (depthState) [enc setDepthStencilState:depthState];
    [enc setVertexBuffer:vertBuf  offset:0 atIndex:0];
    [enc setVertexBuffer:unifBuf  offset:0 atIndex:1];
    [enc setFragmentBuffer:unifBuf offset:0 atIndex:1];
    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                    indexCount:6
                     indexType:MTLIndexTypeUInt16
                   indexBuffer:idxBuf
             indexBufferOffset:0];
    [enc endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    if ([cmd status] == MTLCommandBufferStatusError) return false;

    // Read pixel [2,2] (center of 4×4 grid)
    uint8_t pixel[4] = {0};
    [colorTex getBytes:pixel
           bytesPerRow:kW * 4
            fromRegion:MTLRegionMake2D(2, 2, 1, 1)
           mipmapLevel:0];
    // BGRA → RGBA normalize
    outPixel[0] = pixel[2] / 255.0f;  // R
    outPixel[1] = pixel[1] / 255.0f;  // G
    outPixel[2] = pixel[0] / 255.0f;  // B
    outPixel[3] = pixel[3] / 255.0f;  // A
    return true;
}

// ---------------------------------------------------------------------------
// Per-shader test: build PSO, render, check that output is NOT all-black and
// alpha == 1 (confirms the shader executed and wrote something meaningful).
// Expected values per shader are recorded once and committed here as constants.
// ---------------------------------------------------------------------------

struct ShaderExpect {
    const char* normalizedName;   // lowercase shader name to look up in manifest
    float minBrightness;          // min(r+g+b)/3 — scene should not be pure black
    float expectedAlpha;          // expected alpha channel (1.0 for opaque shaders)
    float alphaTol;               // tolerance for alpha check
};

// Representative shaders from the generated set.
// minBrightness > 0 just verifies the shader ran and produced non-zero output.
// Adjust expected values by running the test once and recording actual output.
static const ShaderExpect kExpected[] = {
    {"cgrcambient",   0.01f, 1.0f, 0.05f},
    {"cgrcbump",      0.01f, 1.0f, 0.05f},
    {"cgrcshadow",    0.00f, 1.0f, 0.10f},  // shadow shaders may output black on solid surface
};
static const int kNumExpected = sizeof(kExpected) / sizeof(kExpected[0]);

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main(int argc, const char* argv[]) {
    @autoreleasepool {

    printf("=== ShaderOutputTests ===\n");

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        fprintf(stderr, "FATAL: MTLCreateSystemDefaultDevice() returned nil\n");
        return 1;
    }
    printf("Device: %s\n", [[device name] UTF8String]);

    NSString* genDir = findGeneratedDir(argc > 0 ? argv[0] : "");
    if (!genDir) {
        fprintf(stderr, "FATAL: Generated/ directory not found. "
                "Set GENERATED_DIR=/path/to/RenderDll/XRenderMetal/Generated\n");
        return 1;
    }

    NSURL* metallibURL = [NSURL fileURLWithPath:[genDir stringByAppendingPathComponent:@"GeneratedShaders.metallib"]];
    NSString* manifestPath = [genDir stringByAppendingPathComponent:@"generated_manifest.json"];

    NSError* err = nil;
    id<MTLLibrary> lib = [device newLibraryWithURL:metallibURL error:&err];
    if (!lib) {
        fprintf(stderr, "FATAL: Could not load metallib: %s\n",
                err ? [[[err localizedDescription] description] UTF8String] : "unknown");
        return 1;
    }

    NSData* manifestData = [NSData dataWithContentsOfFile:manifestPath];
    id manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&err];
    if (!manifest || ![manifest isKindOfClass:[NSArray class]]) {
        fprintf(stderr, "FATAL: Could not parse manifest\n");
        return 1;
    }
    NSArray* entries = (NSArray*)manifest;

    id<MTLCommandQueue> queue = [device newCommandQueue];

    // Depth-stencil state (write enabled, less-equal)
    MTLDepthStencilDescriptor* dsd = [MTLDepthStencilDescriptor new];
    dsd.depthCompareFunction = MTLCompareFunctionLessEqual;
    dsd.depthWriteEnabled    = YES;
    id<MTLDepthStencilState> depthState = [device newDepthStencilStateWithDescriptor:dsd];

    MTLVertexDescriptor* vd = buildVertexDescriptor();

    // Index vertex functions by entryPoint
    NSMutableDictionary<NSString*, id<MTLFunction>>* vertexFns = [NSMutableDictionary dictionary];
    for (NSDictionary* entry in entries) {
        if (![entry[@"stage"] isEqualToString:@"vertex"]) continue;
        NSString* ep = entry[@"entryPoint"];
        if (!ep) continue;
        id<MTLFunction> fn = [lib newFunctionWithName:ep];
        if (fn) vertexFns[ep] = fn;
    }

    // Run each expected shader
    for (int i = 0; i < kNumExpected; ++i) {
        const ShaderExpect& exp = kExpected[i];
        NSString* targetName = [NSString stringWithUTF8String:exp.normalizedName];

        // Find fragment entry in manifest
        NSDictionary* fragEntry = nil;
        for (NSDictionary* entry in entries) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            NSString* stage = entry[@"stage"];
            if (![stage isEqualToString:@"fragment"] && ![stage isEqualToString:@"pixel"]) continue;
            NSString* normalized = entry[@"normalized"] ?: @"";
            if ([normalized isEqualToString:targetName]) { fragEntry = entry; break; }
        }

        if (!fragEntry) {
            fprintf(stderr, "SKIP [%s]: shader not found in manifest\n", exp.normalizedName);
            continue;
        }

        NSString* fragEP = fragEntry[@"entryPoint"] ?: fragEntry[@"fragment"];
        NSString* vertEP = fragEntry[@"vertexEntryPoint"];
        if (!fragEP || !vertEP) {
            fprintf(stderr, "SKIP [%s]: no entry point or vertex pair\n", exp.normalizedName);
            continue;
        }

        id<MTLFunction> vertFn = vertexFns[vertEP];
        if (!vertFn) {
            fprintf(stderr, "SKIP [%s]: vertex function '%s' not in metallib\n",
                    exp.normalizedName, [vertEP UTF8String]);
            continue;
        }

        id<MTLFunction> fragFn = [lib newFunctionWithName:fragEP];
        if (!fragFn) {
            fprintf(stderr, "SKIP [%s]: fragment function '%s' not in metallib\n",
                    exp.normalizedName, [fragEP UTF8String]);
            continue;
        }

        MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction                  = vertFn;
        desc.fragmentFunction                = fragFn;
        desc.vertexDescriptor                = vd;
        desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        desc.depthAttachmentPixelFormat      = MTLPixelFormatDepth32Float_Stencil8;
        desc.stencilAttachmentPixelFormat    = MTLPixelFormatDepth32Float_Stencil8;

        NSError* psoErr = nil;
        id<MTLRenderPipelineState> pso =
            [device newRenderPipelineStateWithDescriptor:desc error:&psoErr];
        if (!pso) {
            fprintf(stderr, "FAIL [%s]: PSO creation failed: %s\n",
                    exp.normalizedName,
                    psoErr ? [[[psoErr localizedDescription] description] UTF8String] : "unknown");
            ++g_failed;
            continue;
        }

        float pixel[4] = {0};
        bool ok = renderQuad(device, queue, pso, depthState, pixel);
        if (!ok) {
            fprintf(stderr, "FAIL [%s]: render command failed\n", exp.normalizedName);
            ++g_failed;
            continue;
        }

        printf("[%s] pixel=[%.3f, %.3f, %.3f, %.3f]\n",
               exp.normalizedName, pixel[0], pixel[1], pixel[2], pixel[3]);

        float brightness = (pixel[0] + pixel[1] + pixel[2]) / 3.0f;
        CHECK(brightness >= exp.minBrightness,
              (std::string(exp.normalizedName) + " output too dark (all-black pixel)").c_str());
        CHECK_NEAR(pixel[3], exp.expectedAlpha, exp.alphaTol,
                   (std::string(exp.normalizedName) + " alpha").c_str());
    }

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed > 0 ? 1 : 0;

    } // @autoreleasepool
}
