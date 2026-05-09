#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "MetalManifestPSOHelpers.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

namespace
{

static bool g_failFast = false;
static bool g_json = false;
static bool g_gpuSmoke = false;
static int g_maxFailures = 1000000;
static int g_failureCount = 0;
static int g_passCount = 0;
static int g_skipCount = 0;

static NSString* FindGeneratedDir(const char* argv0, NSString* overrideDir)
{
    if (overrideDir && [overrideDir length] > 0)
        return overrideDir;

    const char* envPath = std::getenv("GENERATED_DIR");
    if (envPath && strlen(envPath) > 0)
        return [NSString stringWithUTF8String:envPath];

    NSString* binaryPath = [NSString stringWithUTF8String:argv0 ? argv0 : ""];
    NSString* binaryDir  = [binaryPath stringByDeletingLastPathComponent];

    NSString* candidate1 = [binaryDir stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate1])
        return binaryDir;

    NSString* candidate2 = [binaryDir stringByAppendingPathComponent:@"../../Generated"];
    NSString* resolved   = [candidate2 stringByStandardizingPath];
    NSString* metallibAt2 = [resolved stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:metallibAt2])
        return resolved;

    NSString* candidate3 = [binaryDir stringByAppendingPathComponent:@"../../../RenderDll/XRenderMetal/Generated"];
    NSString* resolved3  = [candidate3 stringByStandardizingPath];
    NSString* metallibAt3 = [resolved3 stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:metallibAt3])
        return resolved3;

    return nil;
}

static bool ShaderNameMatchesFilter(NSString* shaderName, NSRegularExpression* regex)
{
    if (!regex)
        return true;
    if (!shaderName)
        return false;
    NSRange r = NSMakeRange(0, [shaderName length]);
    return [regex numberOfMatchesInString:shaderName options:0 range:r] > 0;
}

static bool GpuSmokeDraw(id<MTLDevice> device,
                         id<MTLRenderPipelineState> pso,
                         MTLVertexDescriptor* vertexDescriptor)
{
    (void)vertexDescriptor;

    id<MTLCommandQueue> queue = [device newCommandQueue];
    if (!queue)
        return false;

    MTLTextureDescriptor* td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                             width:1
                                                            height:1
                                                         mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> colorTex = [device newTextureWithDescriptor:td];
    if (!colorTex)
        return false;

    MTLRenderPassDescriptor* rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = colorTex;
    rpd.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> cb = [queue commandBuffer];
    if (!cb)
        return false;

    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rpd];
    if (!enc)
        return false;

    [enc setRenderPipelineState:pso];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];

    return cb.error == nil;
}

static void RecordFailure(NSString* shader, NSString* detail)
{
    ++g_failureCount;
    if (g_json)
    {
        fprintf(stdout,
                "{\"ok\":false,\"shader\":\"%s\",\"detail\":\"%s\"}\n",
                shader ? [shader UTF8String] : "",
                detail ? [detail UTF8String] : "");
    }
    else
    {
        fprintf(stderr,
                "FAIL [%s] %s\n",
                shader ? [shader UTF8String] : "<unnamed>",
                detail ? [detail UTF8String] : "");
    }
    if (g_failFast)
        exit(2);
    if (g_failureCount >= g_maxFailures)
        exit(2);
}

static void RecordPass(NSString* shader)
{
    ++g_passCount;
    if (g_json)
    {
        fprintf(stdout,
                "{\"ok\":true,\"shader\":\"%s\"}\n",
                shader ? [shader UTF8String] : "");
    }
}

} // namespace

int main(int argc, const char* argv[])
{
    @autoreleasepool {

    NSString* generatedDirOverride = nil;
    NSString* filterPattern = nil;
    int shardIndex = -1;
    int shardCount = 0;

    for (int i = 1; i < argc; ++i)
    {
        const char* a = argv[i];
        if (!strcmp(a, "--fail-fast"))
            g_failFast = true;
        else if (!strcmp(a, "--json"))
            g_json = true;
        else if (!strcmp(a, "--gpu-smoke"))
            g_gpuSmoke = true;
        else if (!strcmp(a, "--generated-dir") && i + 1 < argc)
            generatedDirOverride = [NSString stringWithUTF8String:argv[++i]];
        else if (!strcmp(a, "--filter") && i + 1 < argc)
            filterPattern = [NSString stringWithUTF8String:argv[++i]];
        else if (!strcmp(a, "--max-failures") && i + 1 < argc)
            g_maxFailures = atoi(argv[++i]);
        else if (!strcmp(a, "--shard") && i + 2 < argc)
        {
            shardIndex = atoi(argv[++i]);
            shardCount = atoi(argv[++i]);
        }
        else if (!strcmp(a, "--help") || !strcmp(a, "-h"))
        {
            fprintf(stderr,
                    "metal_pso_validate [--generated-dir DIR] [--filter REGEX] [--fail-fast] "
                    "[--max-failures N] [--shard I N] [--json] [--gpu-smoke]\n");
            return 0;
        }
    }

    if (shardCount > 0 && (shardIndex < 0 || shardIndex >= shardCount))
    {
        fprintf(stderr, "Invalid --shard I N (need 0 <= I < N)\n");
        return 1;
    }

    NSRegularExpression* filterRegex = nil;
    if (filterPattern && [filterPattern length] > 0)
    {
        NSError* rxErr = nil;
        filterRegex = [NSRegularExpression regularExpressionWithPattern:filterPattern
                                                                  options:NSRegularExpressionCaseInsensitive
                                                                    error:&rxErr];
        if (!filterRegex)
        {
            fprintf(stderr, "Invalid --filter regex: %s\n",
                    rxErr ? [[rxErr localizedDescription] UTF8String] : "");
            return 1;
        }
    }

    NSString* genDir = FindGeneratedDir(argc > 0 ? argv[0] : "", generatedDirOverride);
    if (!genDir)
    {
        fprintf(stderr,
                "Could not locate Generated/ (use --generated-dir or set GENERATED_DIR).\n");
        return 1;
    }

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device)
    {
        fprintf(stderr, "MTLCreateSystemDefaultDevice() returned nil.\n");
        return 1;
    }

    NSString* metallibPath = [genDir stringByAppendingPathComponent:@"GeneratedShaders.metallib"];
    NSString* manifestPath = [genDir stringByAppendingPathComponent:@"generated_manifest.json"];

    NSError* err = nil;
    id<MTLLibrary> lib = [device newLibraryWithFile:metallibPath error:&err];
    if (!lib)
    {
        fprintf(stderr,
                "Could not load metallib %s: %s\n",
                [metallibPath UTF8String],
                err ? [[err localizedDescription] UTF8String] : "");
        return 1;
    }

    NSData* manifestData = [NSData dataWithContentsOfFile:manifestPath];
    if (!manifestData)
    {
        fprintf(stderr, "Could not read manifest %s\n", [manifestPath UTF8String]);
        return 1;
    }

    id manifestJson = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&err];
    if (!manifestJson || ![manifestJson isKindOfClass:[NSArray class]])
    {
        fprintf(stderr,
                "Manifest JSON parse failed: %s\n",
                err ? [[err localizedDescription] UTF8String] : "not an array");
        return 1;
    }

    NSArray* entries = (NSArray*)manifestJson;

    NSMutableDictionary<NSString*, NSDictionary*>* vertexRowsByEntryPoint =
        [NSMutableDictionary dictionary];
    for (NSDictionary* entry in entries)
    {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;
        NSString* stage = entry[@"stage"];
        NSString* lowered = stage ? [stage lowercaseString] : @"";
        if (![lowered isEqualToString:@"vertex"])
            continue;
        NSString* ep = entry[@"entryPoint"];
        if (ep && [ep length] > 0)
            vertexRowsByEntryPoint[ep] = entry;
    }

    const NSUInteger entryCount = [entries count];
    for (NSUInteger ei = 0; ei < entryCount; ++ei)
    {
        @autoreleasepool {
            id rawEntry = entries[ei];
            if (![rawEntry isKindOfClass:[NSDictionary class]])
                continue;
            NSDictionary* entry = (NSDictionary*)rawEntry;

            if (shardCount > 0)
            {
                int bucket = static_cast<int>(ei % static_cast<unsigned>(shardCount));
                if (bucket != shardIndex)
                    continue;
            }

            NSString* stage = entry[@"stage"];
            NSString* loweredStage = stage ? [stage lowercaseString] : @"fragment";
            if ([loweredStage isEqualToString:@"vertex"])
                continue;

            NSString* shaderName = entry[@"shader"] ?: @"<unnamed>";
            if (!ShaderNameMatchesFilter(shaderName, filterRegex))
                continue;

            NSString* fragEP = entry[@"entryPoint"] ?: entry[@"fragment"];
            NSString* vertEP = entry[@"vertexEntryPoint"];
            NSArray* directives = entry[@"directives"];
            NSDictionary* pipelineDict = entry[@"pipeline"];

            if (!fragEP || !vertEP)
            {
                ++g_skipCount;
                continue;
            }

            NSDictionary* vertexRow = vertexRowsByEntryPoint[vertEP];
            if (!vertexRow)
            {
                RecordFailure(shaderName, @"missing vertex manifest row for vertexEntryPoint");
                continue;
            }

            MTLVertexDescriptor* vertexDesc =
                MetalManifestCreateVertexDescriptorFromManifestVertexEntry(vertexRow);
            if (!vertexDesc)
            {
                RecordFailure(shaderName, @"MetalManifestCreateVertexDescriptorFromManifestVertexEntry returned nil");
                continue;
            }

            NSString* lowerShaderName = [shaderName lowercaseString];
            MTLFunctionConstantValues* funcConstants =
                MetalManifestBuildFunctionConstants(lowerShaderName, directives);

            NSError* vsErr = nil;
            NSError* fsErr = nil;
            id<MTLFunction> vsFn =
                [lib newFunctionWithName:vertEP constantValues:funcConstants error:&vsErr];
            id<MTLFunction> fsFn =
                [lib newFunctionWithName:fragEP constantValues:funcConstants error:&fsErr];

            if (!vsFn)
            {
                RecordFailure(shaderName,
                              vsErr ? [vsErr localizedDescription]
                                    : @"missing vertex function");
                continue;
            }
            if (!fsFn)
            {
                RecordFailure(shaderName,
                              fsErr ? [fsErr localizedDescription]
                                    : @"missing fragment function");
                continue;
            }

            PipelineStateConfig pipelineConfig = MetalManifestDefaultPipelineConfig();
            MetalManifestApplyPipelineConfigFromManifest(pipelineConfig, pipelineDict);

            MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
            desc.vertexFunction = vsFn;
            desc.fragmentFunction = fsFn;
            desc.vertexDescriptor = vertexDesc;
            MetalManifestApplyPipelineConfigToDescriptor(desc,
                                                         pipelineConfig,
                                                         MTLPixelFormatBGRA8Unorm,
                                                         MTLPixelFormatDepth32Float_Stencil8);

            MTLRenderPipelineReflection* reflection = nil;
            NSError* psoErr = nil;
            id<MTLRenderPipelineState> pso =
                [device newRenderPipelineStateWithDescriptor:desc
                                                     options:MTLPipelineOptionArgumentInfo
                                                  reflection:&reflection
                                                       error:&psoErr];

            if (!pso)
            {
                NSString* detail =
                    psoErr ? [psoErr localizedDescription] : @"PSO creation failed";
                RecordFailure(shaderName, detail);
                continue;
            }

            if (g_gpuSmoke)
            {
                if (!GpuSmokeDraw(device, pso, vertexDesc))
                {
                    RecordFailure(shaderName, @"GPU smoke draw failed");
                    continue;
                }
            }

            RecordPass(shaderName);
        }
    }

    if (!g_json)
    {
        fprintf(stdout,
                "metal_pso_validate: pass=%d fail=%d skip=%d dir=%s\n",
                g_passCount,
                g_failureCount,
                g_skipCount,
                [genDir UTF8String]);
    }

    return g_failureCount > 0 ? 2 : 0;
    }
}
