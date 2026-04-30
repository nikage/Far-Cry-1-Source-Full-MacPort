# Metal Renderer — MacPort Implementation Plan

> Status key: ✅ Done · 🔶 Partial · ❌ Blocked · 🔲 Pending

---

## P1 — Core Renderer Infrastructure


| ID               | Item                                                | Status | Notes                                                                                                         |
| ---------------- | --------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------- |
| p1-device        | MTLDevice / CAMetalLayer / command queue init       | ✅      | `CMetalBaseRenderer::InitializeCommandQueue`; dedicated `m_blitCommandQueue` for mip-gen                      |
| p1-swapchain     | Triple-buffered drawable acquire + present          | ✅      | `AcquireDrawableFromLayer`; `m_currentDrawable` used throughout; no stray `nextDrawable` calls                |
| p1-depth         | Depth-stencil texture (`Depth32Float_Stencil8`)     | ✅      | Private storage mode, recreated on resize                                                                     |
| p1-uniforms      | Global `UniformBufferData` (MVP, fog, clip, lights) | ✅      | `m_uniformBuffer` at vertex `[[buffer(2)]]` / fragment `[[buffer(0)]]`; `MaterialUniforms` at `[[buffer(1)]]` |
| p1-vb            | Dynamic VB pools, `GetDynVBPtr` / `DrawDynVB`       | ✅      | Ring-buffer pools with `MTLResourceStorageModeShared`                                                         |
| p1-state         | Depth, blend, cull state cache                      | ✅      | `CMetalStateCache` with PSO hash map                                                                          |
| p1-hacks         | `Draw2dImage` rotation (CPU-side quad transform)    | ✅      | `cosf`/`sinf` around quad centre; no assert                                                                   |
| p1-freeresources | `FreeResources(FRR_REINITHW | FRR_ALL)`             | ✅      | Tears down uniform buffers, depth textures, VB pools; blit queue torn down in `ShutDown` only                 |


---

## P2 — Lighting


| ID           | Item                                          | Status | Notes                                                                                                     |
| ------------ | --------------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------- |
| p2-light-fix | Full active-light list in `UniformBufferData` | ✅      | Up to `kMaxLights = 4` `LightEntry` structs; `lightPos`/`lightColor` alias `lights[0]`; `numLights` field |
| p2-shadow    | Shadow-map depth pass (`PrepareDepthMap`)     | ✅      | Swaps `m_renderEncoder` to shadow encoder; entities drawn via `DrawEntity`; restored after pass           |


### Insight — `UniformBufferData` ↔ `UtilShaders.metal` must stay in sync

The CPU-side struct and the MSL `Uniforms` struct are independent definitions.  
**Rule:** any field added to `UniformBufferData` in `MetalBaseRenderer.m` must be mirrored in `UtilShaders.metal`'s `Uniforms` and `LightEntry` structs, or GPU reads will silently land at the wrong offset.

---

## P3 — Shader Porting (Dart toolchain → MSL)


| ID                  | Item                                                          | Status | Notes                                                                                                                                                                                                             |
| ------------------- | ------------------------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| p3-toolchain        | `parser.dart` → `metal_generator.dart` → `.metal` + manifest  | ✅      | 995 Metal files generated under `RenderDll/XRenderMetal/Generated/`                                                                                                                                               |
| p3-manifest         | `generated_manifest.json` structure & required fields         | ✅      | All entries have `source`, `stage`, `entryPoint`, `normalized`, `uniformStruct`, `pipeline`, `vertexAttributes`                                                                                                   |
| p3-manifest-pairing      | `vertexEntryPoint` field on fragment entries                  | 🔶     | 340/589 (57%) paired via token-based heuristic in `metal_generator.dart`; remaining 43% are post-process/HDR shaders using a fullscreen-quad vertex not identifiable by name; `MetalShaderLoader` runtime heuristic handles the rest |
| p3-manifest-pairing-crycg | Parse technique/pass declarations from `.crycg` source to resolve remaining pairings | ✅ | `parseTechniquePairs()` added to `parser.dart`; token-based heuristic in `metal_generator.dart` improved from 23% → 57%; unit tests pass (20 tests) |
| p3-shader-slots     | Per-shader uniform buffer slots                               | ✅      | Fragment `[[buffer(2)]]` = `kMetalPerShaderFragmentUniformSlot`; vertex `[[buffer(5)]]` = `kMetalPerShaderVertexUniformSlot`; global `Uniforms` remains at `[[buffer(0)]]`/`[[buffer(2)]]`; no collision          |
| p3-shader-ambient   | `CGRCAmbient` / `CGVProgAmbientTempl` MSL translation         | 🔶     | Compiled into `GeneratedShaders.metallib` (5 MB); all 995 shaders include `[[function_constant]]` + `[[user(name)]]` attributes; visual validation pending |
| p3-shader-bump      | Bump/DiffSpec/EnvLight family                                 | 🔶     | Compiled into metallib; visual validation pending |
| p3-shader-effects   | HDR, fog, screen effects                                      | 🔶     | Compiled into metallib; visual validation pending |
| p3-envlight-fix     | Remove hardcoded `envlight` heuristics in `MetalShaderLoader` | ✅      | All `cgvprogbump_diffspec_envlight_vs20` special-cases and force-tangent overrides removed; tangent requirement driven solely by `vertexAttributeMetadata`                                                        |


### Insight — `xcrun metal` detection

`metal` is not on the standard `$PATH` — it lives inside the Xcode toolchain
(`xcrun --find metal` resolves it via `xcode-select`).  `find_program(metal)` in
CMake therefore always yields `NOTFOUND`, but the `xcrun -sdk macosx metal --version`
fallback succeeds on any machine with Xcode installed.

The CMake detection now runs `xcrun` first (primary path) and falls back to
`find_program` only for non-Apple toolchains.  A stale `METAL_COMPILER-NOTFOUND`
entry in `CMakeCache.txt` from an old configure run is harmless — re-run CMake to
pick up `METAL_COMPILER_AVAILABLE=TRUE`.

---

## P4 — Render Pipeline


| ID              | Item                                                         | Status | Notes                                                                                                                                       |
| --------------- | ------------------------------------------------------------ | ------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| p4-ef-start-end | `EF_StartEf` / `EF_AddEf` / `EF_EndEf3D` render-item buckets | ✅      | `EFSLIST_GENERAL_ID`, `EFSLIST_DISTSORT_ID`, `EFSLIST_LAST_ID` sort + draw                                                                  |
| p4-hdr          | HDR float16 RT + Reinhard tone-map + bloom chain             | ✅      | `InitHDRPipeline`, `BeginHDRPass` (returns `bool`), `DoBloomPass`, `EndHDRPass`; bloom passes completed **before** opening tone-map encoder |
| p4-hdr-fallback | `BeginHDRPass` failure falls back to LDR path                | ✅      | Caller re-evaluates `useHDR = BeginHDRPass()`; `EndHDRPass` asserts if reached with nil resources                                           |
| p4-shadow-depth | Depth-only shadow pass                                       | ✅      | See p2-shadow                                                                                                                               |
| p4-debug        | Debug line / sphere / point queue + flush                    | ✅      | `QueueDebugLine`, `QueueDebugSphere`, `QueueDebugPoint`, `FlushDebugCommands`                                                               |
| p4-screenshot   | `ScreenShot` TGA capture                                     | ✅      | Blit-to-staging-buffer path; uses `m_currentDrawable.texture`, falls back to `m_hdrColorRT`; never calls `nextDrawable`                     |


---

## P5 — Textures & Resources


| ID                | Item                                                                            | Status | Notes                                                                                                  |
| ----------------- | ------------------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------ |
| p5-packed-formats | Unpack `eTF_4444` / `eTF_1555` / `eTF_0555` / `eTF_0565` to RGBA8 before upload | ✅      | CPU-side unpack in both `DownLoadToVideoMemory` and `LoadTexture`; `UnpackPackedFormat` helper         |
| p5-mipgen         | Mip generation via `MTLBlitCommandEncoder` on dedicated blit queue              | ✅      | `m_blitCommandQueue` separate from main queue; no cross-queue fence (shared-memory textures need none) |
| p5-anim           | Animated texture cycling (`AnimTexInfo`)                                        | ✅      | `CMetalTextureManager::Update(fTime)` + `ApplyTexUnit` advances frame via `m_animTime / m_Time`        |
| p5-imageio        | ImageIO fallback for JPEG/TGA/PNG loading                                       | ✅      | `CGImageSourceRef` / `CGContextRef` path in `LoadTextureData`                                          |
| p5-text           | CryFont text rendering wired to sprite PSO                                      | ✅      | `FontSetRenderingState` activates sprite PSO; `GetFontPSO()` virtual override in `CMetalRenderer`      |
| p5-gamma          | Display gamma via Metal blit / `MTLRenderPassDescriptor`                        | ✅      | `SetGamma` applies delta                                                                               |
| p5-font-pso       | `GetFontPSO()` / `GetSpritePSO()` accessor chain                                | ✅      | `CMetalUtilityRenderer::GetSpritePSO()` lazy-creates; `CMetalRenderer::GetFontPSO()` returns it        |


---

## P6 — macOS Integration


| ID                 | Item                                                              | Status | Notes                                                                                                                          |
| ------------------ | ----------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------ |
| p6-macos-entry     | `NSApplicationMain` / `CryApplicationDelegate` boot path          | ✅      | Lives in `FARCRY/Main.cpp`; `CSystem::Init` macOS path present                                                                 |
| p6-hardening       | Dedicated blit command queue (`m_blitCommandQueue`)               | ✅      | Created and labelled in `InitializeCommandQueue`; nilled in `ShutDown` only (not in `CleanupUniformBuffers`)                   |
| p6-capture         | `MTLCaptureManager` GPU frame capture via `metal_gpucapture` CVar | ✅      | `#ifdef DEBUG` only; registered/unregistered with console                                                                      |
| p6-gpu-timing      | `GPUStartTime`/`GPUEndTime` → `SPipeStat::m_fFlushTime`           | ✅      | Accumulated in `addCompletedHandler` on every tracked command buffer                                                           |
| p6-ocean           | `CMetalREOcean` grid generation + sinusoidal update + GPU draw    | ✅      | `GenerateGeometry`, `Update`, `FlushVerticesToGPU`, `mfDraw`; PSO looked up as `"ocean"` or `VERTEX_FORMAT_P3F_TEX2F` fallback |
| p6-readframebuffer | `ReadFrameBuffer` GPU readback                                    | ✅      | Blit-to-shared-buffer + BGRA→RGB/RGBA copy; uses `m_currentDrawable.texture` (never `nextDrawable`)                            |


---

## Cross-Cutting: Code Quality Patterns

### `checked_cast<T>` downcast helper

All `gRenDev` downcasts use `checked_cast<CMetalRenderer>(gRenDev)` (defined in `MetalBaseRenderer.m`).  
In debug: `dynamic_cast` verifies the type. In release: collapses to `static_cast` (zero cost).  
**Never use a bare `static_cast` downcast.**

### Assert-before-return on contract violations

Silent `return` / `return false` on conditions that are programming errors (not valid runtime states)  
must be preceded by `assert(condition && "message")`.  
Hot-path guards (called every frame) use `assert`; init-path failures use `iLog->Log`.

### `[[buffer(N)]]` slot map (must not change without updating both sides)


| Slot | Vertex stage                                                       | Fragment stage                                                       |
| ---- | ------------------------------------------------------------------ | -------------------------------------------------------------------- |
| 0    | vertex stream (`stage_in` via vertex descriptor)                   | global `Uniforms` struct                                             |
| 1    | tangent stream                                                     | `MaterialUniforms`                                                   |
| 2    | global `Uniforms` (`kMetalVertexUniformSlot`)                      | per-shader generated uniforms (`kMetalPerShaderFragmentUniformSlot`) |
| 3    | flat color (`kMetalVertexColorSlot`)                               | —                                                                    |
| 4    | water noise table (`kMetalWaterNoiseSlot`)                         | —                                                                    |
| 5    | per-shader generated uniforms (`kMetalPerShaderVertexUniformSlot`) | —                                                                    |


---

## Remaining Blockers


| Blocker                                        | Impact                                                                                    | Resolution                                                                         |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Stale `METAL_COMPILER-NOTFOUND` in CMake cache | `METAL_COMPILER_AVAILABLE` may be `FALSE` from a previous configure run                   | Delete `build/CMakeCache.txt` and re-run `cmake`; `xcrun metal` resolves correctly |
| No GPU frame captured in automated CI          | Cannot validate PSO correctness programmatically                                          | Manual Xcode GPU Frame Capture via `metal_gpucapture 1` CVar                       |
| ~43% of fragment shaders lack `vertexEntryPoint` | MetalShaderLoader must fall back to runtime heuristic for these entries                  | Post-process / HDR shaders use a generic fullscreen-quad VS; no additional mapping needed |


---

## Testing


| Layer                       | Tool                                   | State                              |
| --------------------------- | -------------------------------------- | ---------------------------------- |
| Shader toolchain unit tests | `dart test` (20 manifest tests + others) | ✅ All passing                    |
| C++ renderer logic tests    | CTest (`RendererLogicTests`)           | ✅ Passing                          |
| Metal validation layer      | Xcode Metal Validation (runtime)       | Manual only                        |
| GPU frame capture           | `metal_gpucapture` CVar (DEBUG builds) | Available                          |
| Screenshot regression       | `ScreenShot` → TGA                     | Implemented; needs manual baseline |


