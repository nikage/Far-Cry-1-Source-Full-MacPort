#import <Foundation/Foundation.h>

#include "MetalManifestPSOHelpers.h"

#include <cstdio>
#include <cstdlib>

int main(int argc, const char* argv[])
{
    (void)argc;
    (void)argv;

    PipelineStateConfig config = MetalManifestDefaultPipelineConfig();
    if (!config.blendEnabled)
    {
        fprintf(stderr, "MetalManifestDefaultPipelineConfig: expected blend enabled\n");
        return 1;
    }

    NSDictionary* blendNone = @{ @"blendMode" : @"none" };
    MetalManifestApplyPipelineConfigFromManifest(config, blendNone);
    if (config.blendEnabled || config.blendMode != kBlendNone)
    {
        fprintf(stderr, "blendMode none did not disable blending\n");
        return 1;
    }

    PipelineStateConfig cfg2 = MetalManifestDefaultPipelineConfig();
    NSDictionary* additive = @{ @"blendMode" : @"additive" };
    MetalManifestApplyPipelineConfigFromManifest(cfg2, additive);
    if (!cfg2.blendEnabled || cfg2.blendMode != kBlendAdditive)
    {
        fprintf(stderr, "additive blend mode not applied\n");
        return 1;
    }

    NSString* lower = @"cgfoo_envlight_alphaglow";
    NSArray* dirs = @[ @"HDR", @"fog" ];
    MTLFunctionConstantValues* fc = MetalManifestBuildFunctionConstants(lower, dirs);
    if (!fc)
    {
        fprintf(stderr, "MetalManifestBuildFunctionConstants returned nil\n");
        return 1;
    }

    fprintf(stdout, "MetalManifestPSOHelpersTests: ok\n");
    return 0;
}
