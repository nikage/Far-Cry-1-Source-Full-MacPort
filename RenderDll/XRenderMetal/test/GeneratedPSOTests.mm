// Headless Metal PSO dry-run test for all generated shaders.
// Loads GeneratedShaders.metallib + generated_manifest.json from a well-known path
// and attempts newRenderPipelineStateWithDescriptor: for every VS/FS pair.
// No display or window required — only MTLCreateSystemDefaultDevice().
//
// Build:
//   clang++ -std=c++17 -framework Metal -framework Foundation -framework CoreFoundation \
//       -o generated_pso_tests GeneratedPSOTests.mm && ./generated_pso_tests
//
// The test looks for the metallib/manifest in, in order:
//   1. $GENERATED_DIR environment variable
//   2. The directory containing the test binary (argv[0])
//   3. ../../Generated/ relative to this source file at build time
//
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

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

static NSString* findGeneratedDir(const char* argv0)
{
    const char* envPath = std::getenv("GENERATED_DIR");
    if (envPath && strlen(envPath) > 0)
        return [NSString stringWithUTF8String:envPath];

    NSString* binaryPath = [NSString stringWithUTF8String:argv0];
    NSString* binaryDir  = [binaryPath stringByDeletingLastPathComponent];

    // Sibling to binary
    NSString* candidate1 = [binaryDir stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate1])
        return binaryDir;

    // Relative from source tree: test/ → ../../Generated/
    NSString* candidate2 = [binaryDir stringByAppendingPathComponent:@"../../Generated"];
    NSString* resolved   = [candidate2 stringByStandardizingPath];
    NSString* metallibAt2 = [resolved stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:metallibAt2])
        return resolved;

    return nil;
}

int main(int argc, const char* argv[])
{
    @autoreleasepool {

    printf("=== GeneratedPSOTests ===\n");

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        fprintf(stderr, "FATAL: MTLCreateSystemDefaultDevice() returned nil — Metal not available\n");
        return 1;
    }
    printf("Device: %s\n", [[device name] UTF8String]);

    NSString* genDir = findGeneratedDir(argc > 0 ? argv[0] : "");
    if (!genDir) {
        fprintf(stderr, "FATAL: Could not locate Generated/ directory.\n"
                "Set GENERATED_DIR=/path/to/RenderDll/XRenderMetal/Generated and re-run.\n");
        return 1;
    }

    NSString* metallibPath  = [genDir stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
    NSString* manifestPath  = [genDir stringByAppendingPathComponent:@"generated_manifest.json"];

    NSError* err = nil;
    NSURL* metallibURL = [NSURL fileURLWithPath:metallibPath];
    id<MTLLibrary> lib = [device newLibraryWithURL:metallibURL error:&err];
    if (!lib) {
        fprintf(stderr, "FATAL: Could not load %s: %s\n",
                [metallibPath UTF8String],
                err ? [[[err localizedDescription] description] UTF8String] : "unknown");
        return 1;
    }

    NSData* manifestData = [NSData dataWithContentsOfFile:manifestPath];
    if (!manifestData) {
        fprintf(stderr, "FATAL: Could not read manifest at %s\n", [manifestPath UTF8String]);
        return 1;
    }

    id manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&err];
    if (!manifest || ![manifest isKindOfClass:[NSArray class]]) {
        fprintf(stderr, "FATAL: Could not parse manifest JSON: %s\n",
                err ? [[[err localizedDescription] description] UTF8String] : "not an array");
        return 1;
    }

    NSArray* entries = (NSArray*)manifest;
    printf("Manifest entries: %lu\n", (unsigned long)[entries count]);

    // First pass: index vertex functions by entryPoint name.
    NSMutableDictionary<NSString*, id<MTLFunction>>* vertexFns = [NSMutableDictionary dictionary];
    for (NSDictionary* entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString* stage = entry[@"stage"];
        if (![stage isEqualToString:@"vertex"]) continue;
        NSString* ep = entry[@"entryPoint"];
        if (!ep) continue;
        NSError* fnErr = nil;
        id<MTLFunction> fn = [lib newFunctionWithName:ep];
        if (fn)
            vertexFns[ep] = fn;
        else
            fprintf(stderr, "WARN: vertex function '%s' not found in metallib: %s\n",
                    [ep UTF8String],
                    fnErr ? [[[fnErr localizedDescription] description] UTF8String] : "");
    }
    printf("Vertex functions loaded: %lu\n", (unsigned long)[vertexFns count]);

    // Second pass: for each fragment entry, build PSO dry-run.
    int totalTried   = 0;
    int totalSkipped = 0;

    for (NSDictionary* entry in entries) {
        @autoreleasepool {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            NSString* stage = entry[@"stage"];
            if (![stage isEqualToString:@"fragment"] && ![stage isEqualToString:@"pixel"]) continue;

            NSString* shaderName  = entry[@"shader"]     ?: @"<unnamed>";
            NSString* fragEP      = entry[@"entryPoint"] ?: entry[@"fragment"];
            NSString* vertEP      = entry[@"vertexEntryPoint"];

            if (!fragEP) { totalSkipped++; continue; }
            if (!vertEP) { totalSkipped++; continue; }

            id<MTLFunction> vertFn = vertexFns[vertEP];
            if (!vertFn) { totalSkipped++; continue; }

            NSError* fnErr = nil;
            // Function constants — build from directive array like the runtime does.
            NSArray* directives = entry[@"directives"];
            MTLFunctionConstantValues* fcv = [MTLFunctionConstantValues new];
            bool bFalse = false, bTrue = true;
            // Default all to false; flip known flags by name substring.
            NSString* lowerName = [shaderName lowercaseString];
            bool envLight      = [lowerName containsString:@"envlight"];
            bool alphaGlow     = [lowerName containsString:@"alphaglow"];
            bool glossAlpha    = [lowerName containsString:@"glossalpha"];
            bool multLights    = [lowerName containsString:@"multiplelight"];
            bool attenEnabled  = [lowerName containsString:@"atten"];
            bool projLight     = [lowerName containsString:@"proj"];
            bool plantsBending = [lowerName containsString:@"plants"] ||
                                  [lowerName containsString:@"vegetation"];
            [fcv setConstantValue:&envLight      type:MTLDataTypeBool atIndex:0];
            [fcv setConstantValue:&alphaGlow     type:MTLDataTypeBool atIndex:1];
            [fcv setConstantValue:&glossAlpha    type:MTLDataTypeBool atIndex:2];
            [fcv setConstantValue:&multLights    type:MTLDataTypeBool atIndex:3];
            [fcv setConstantValue:&attenEnabled  type:MTLDataTypeBool atIndex:4];
            [fcv setConstantValue:&projLight     type:MTLDataTypeBool atIndex:5];
            [fcv setConstantValue:&plantsBending type:MTLDataTypeBool atIndex:6];

            id<MTLFunction> fragFn = [lib newFunctionWithName:fragEP
                                               constantValues:fcv
                                                        error:&fnErr];
            if (!fragFn) {
                fprintf(stderr, "FAIL [%s]: fragment function '%s' not found: %s\n",
                        [shaderName UTF8String],
                        [fragEP UTF8String],
                        fnErr ? [[[fnErr localizedDescription] description] UTF8String] : "");
                ++g_failed;
                totalTried++;
                continue;
            }

            MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
            desc.vertexFunction                    = vertFn;
            desc.fragmentFunction                  = fragFn;
            desc.colorAttachments[0].pixelFormat   = MTLPixelFormatBGRA8Unorm;
            desc.depthAttachmentPixelFormat        = MTLPixelFormatDepth32Float_Stencil8;

            NSError* psoErr = nil;
            id<MTLRenderPipelineState> pso =
                [device newRenderPipelineStateWithDescriptor:desc
                                                     options:MTLPipelineOptionBindingInfo
                                                  reflection:nil
                                                       error:&psoErr];
            totalTried++;
            if (pso) {
                ++g_passed;
            } else {
                fprintf(stderr, "FAIL [%s]: PSO creation failed: %s\n",
                        [shaderName UTF8String],
                        psoErr ? [[[psoErr localizedDescription] description] UTF8String] : "unknown");
                ++g_failed;
            }
        }
    }

    printf("\nTried: %d  Skipped (no vertex pair): %d\n", totalTried, totalSkipped);
    printf("%d passed, %d failed\n", g_passed, g_failed);
    return g_failed > 0 ? 1 : 0;

    } // @autoreleasepool
}
