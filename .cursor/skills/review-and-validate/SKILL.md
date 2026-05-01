---
name: review-and-validate
description: Reviews code changes and validates they work at runtime for the FarCry Metal port. Covers: running affected unit tests, building with CMake/Ninja, checking asset validation log output, and the integration smoke checklist. Use when the user asks to validate changes work, review a changeset, or check nothing is broken before shipping.
---

# Review Changes and Validate Runtime

## Step 1 — Identify affected modules

Look at changed files and map them to test suites:

| Changed area | Tests to run |
|---|---|
| `CrySystem/**` (incl. `AssetValidator`) | `CrySystem/test/asset_validator_tests` |
| `RenderDll/XRenderMetal/test/*.cpp` | `renderer_logic_tests`, `shader_pair_validation_tests` |
| `RenderDll/XRenderMetal/**` (shader/PSO) | `generated_pso_tests` (requires Generated/ artifacts) |
| `tools/shader_port/**` | `dart test` in `tools/shader_port/` |

## Step 2 — Run unit tests

```bash
# CrySystem (asset validator and friends)
cd /Users/mykolamikhno/projects/FarCry/CrySystem/test
clang++ -std=c++17 -o asset_validator_tests AssetValidatorTests.cpp && ./asset_validator_tests

# Renderer logic
cd /Users/mykolamikhno/projects/FarCry/RenderDll/XRenderMetal/test
clang++ -std=c++17 -o renderer_logic_tests RendererLogicTests.cpp && ./renderer_logic_tests
clang++ -std=c++17 -o shader_pair_validation_tests ShaderPairValidationTests.cpp && ./shader_pair_validation_tests

# Shader toolchain
cd /Users/mykolamikhno/projects/FarCry/tools/shader_port && dart test
```

All suites must exit 0. Fix failures before proceeding.

## Step 3 — Build (DEBUG)

```bash
cd /Users/mykolamikhno/projects/FarCry/cmake-build-debug
cmake --build . --target FarCry -- -j8
```

Zero compiler errors required. Warnings in legacy code are acceptable; new warnings in changed files must be addressed.

## Step 4 — Check asset validation at launch

Launch the game and watch the log for `[AssetValidator]` and `[Asset]` prefixed lines:

- `[AssetValidator] Critical pak not mounted: Scripts.pak` → fatal; FCData is missing or misconfigured
- `[AssetValidator] Non-critical pak not mounted: Textures.pak` → warning; visuals will be degraded
- `[Asset] Missing: <path>` → a file was requested at runtime but not found in any mounted pak (DEBUG only)
- `[Asset] Failed to load minimap icon: ...` → minimap will show blank icons

Expected clean output: no `[AssetValidator]` lines and no `[Asset] Missing` lines.

## Step 5 — Integration smoke checklist

Run after any change to `RenderDll/XRenderMetal/**`, `CrySystem/**`, or `CryGame/**`:

- [ ] Game reaches main menu without crash or assert
- [ ] Load a level — first frame completes without firing `assert(fallbacks == 0)` in `CMetalRenderer::BeginFrame`
- [ ] `ValidateShaderPairs` (auto-called in `#if DEBUG` after `LoadGeneratedShaders`) reports 0 failures
- [ ] No all-black surfaces, fog gradient visible, lighting responds to a moving light source
- [ ] `Missing Files Report.txt` is absent or empty after a clean run (written by `~CCryPak()` only when files are missing)

## Metallib-specific checks

If `RenderDll/XRenderMetal/**` changed:

- Confirm `UtilShaders.metallib` and `GeneratedShaders.metallib` are present in the app bundle at `FarCry.app/Contents/Resources/`
- If either is absent the game will hit `assert(!"MetalShaderManager: *.metallib not found …")` immediately at renderer init
- Regenerate with `dart tools/shader_port/bin/validate_migration.dart .` if generated shaders changed

## Quick reference — build directories

| Purpose | Directory |
|---|---|
| Debug build | `cmake-build-debug/` |
| Release build | `build/` |
| App bundle | `cmake-build-debug/FarCry.app/` |
| FCData (paks) | `cmake-build-debug/FarCry.app/Contents/Resources/FCData/` |
