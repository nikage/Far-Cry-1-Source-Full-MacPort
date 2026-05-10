# Metal Renderer — MacPort Implementation Plan

**See also:** [Metal renderer production roadmap](metal_renderer_production_roadmap.md) — phased path to shippable confidence (packaging, shader resolution, QA, automation).

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
| p3-manifest-pairing      | `vertexEntryPoint` field on fragment entries                  | ✅      | All 589 fragment manifest rows include `vertexEntryPoint`; pairing order is `shader_pair_overrides.json` → technique-file scan (`parseTechniquePairs` over `Assets/.../Shaders/Source` when `Technique` blocks exist) → `_resolveVertexEntryPoint` heuristic; `validate_pairs` reports 100% coverage |
| p3-manifest-pairing-crycg | Parse technique/pass declarations from `.crycg` source to resolve remaining pairings | ✅ | `parseTechniquePairs()` in `parser.dart`; generator merges technique-derived pairings before the stem heuristic; unit tests cover parser + `loadTechniqueFragmentToVertexShaderMap` |
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
| p6-retina-swapchain | Retina `drawableSize`, resize, HDR RT resize                     | ✅      | `SyncMetalLayerDrawableToContentView` → `ChangeResolution` (pixel bounds × backing scale); `NSWindowDidResize` / `DidChangeBackingProperties`; `ResizeHDRPipelineIfNeeded` from `EnsureBackbufferSize`; `GetWidth`/`GetHeight` = backbuffer pixels; UI virtual 800×600 via `ScaleCoordX`/`Y` + font ortho from `GetWidth`/`Height` when `FontSetRenderingState(0,0)` |


### DEBUG — MetalDiag fast-fails and sharing evidence

**Built-in (DEBUG builds only)**

- `CMetalRenderer::EF_EndEf3D`: assert if there is no render encoder after frame 1; assert (and log shader name + vertex format) if neither manifest PSO nor format fallback PSO exists — **Release skips that draw** instead of issuing `mfDraw` with an undefined pipeline.
- `CMetalBaseRenderer::BeginHDRPass`: assert if `m_hdrColorRT` is non-nil but the HDR render encoder failed to create (swapchain pass was already ended).
- `CMetalBaseRenderer::EndHDRPass`: assert if the HDR colour RT exists but the drawable texture is nil.
- `CMetalBaseRenderer::EndFrame`: `[MetalDiag] EndFrame` logs `m_nFrameID`, `m_numDrawCalls`, `m_numTriangles`, backbuffer size, and `lastEF3D_HDR` (accumulated from `EF_EndEf3D` that frame). If there is a drawable, `m_nFrameID > 60`, and draws/tris are both zero, a **one-shot** log suggests checking the 3D path / PSO / buckets.

**Console CVars**

- `metal_gpucapture 1` — start a single-frame `MTLCaptureManager` capture (see `CMetalRenderer::RegisterMetalConsoleVariables`).
- `metal_dumpstats 1` — dump Metal diagnostics after the next frame.
- `r_HDRRendering 0` vs `1` — A/B LDR (direct swapchain 3D) vs HDR (scene to float16 RT, then tonemap).

**Xcode Metal GPU capture**

1. Scheme **Edit Scheme → Run → Diagnostics** — enable **Metal API Validation** while reproducing.
2. Run or attach to the game, then **Debug → Capture GPU Frame** (or trigger `metal_gpucapture` and open the capture from the navigator).
3. In the capture: confirm whether **HDRColorRT** or the **swapchain** receives colour draws after the initial clear; inspect bound **PSO**, **viewport/scissor**, and **depth** for the first failing draw.

**What to paste when reporting an issue**

- Lines containing `[MetalDiag]`, `EF_EndEf3D`, `BeginHDRPass`, `EndHDRPass`, `missing PSO`, or any new assert message.
- Whether the black screen appears with **HDR off** (`r_HDRRendering 0`) only, **HDR on** only, or both.
- Build (**DEBUG** vs Release), macOS version, and GPU. Optional: screenshot and a short description of the capture (e.g. “HDR RT stays black after clear”).

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
| Manifest–vertex drift if generator not re-run | Stale `vertexEntryPoint` vs emitted VS outputs                                                          | After shader changes run `dart tools/shader_port/bin/validate_migration.dart .`; commit regenerated `Generated/` + manifest |
| `EF_SYSTEM` caller-bug class in legacy engine modules | `ShaderLoadFatal` aborts when modules pass `EF_SYSTEM` for shaders the Metal port does not ship (legacy CryEngine 1 high-level `Shader 'X' ( … )` blocks, never-defined names). Startup path is fixed (4 modules, 20 calls). Subsystems that load only on gameplay (`CryAnimation/*`, `terrain_water_quad`, `DecalManager`, `3DEngineLight` XML lights, etc.) still carry the bug. | Per-module classification using the decision tree in [`metal-shader-load-fatal-resolution.md`](metal-shader-load-fatal-resolution.md). Iterate `lldb --batch` → classify (true-alias / missing-shader / caller-bug) → fix → regress-test → rebuild. |


---

## Testing


| Layer                       | Tool                                   | State                              |
| --------------------------- | -------------------------------------- | ---------------------------------- |
| Shader toolchain unit tests | `dart test` (`tools/shader_port/`)     | ✅ Full package suite passing (`All tests passed!`) |
| C++ renderer logic tests    | `clang++ -std=c++17 RendererLogicTests.cpp` | ✅ Full suite passing — anchors caller-bug fixes (`LoadRendererShaderSafe`, `CTerrain::CTerrain`, `CTerrain::LoadTerrain`, `CPartManager::CPartManager`, `Terrain` keeps `EF_SYSTEM`) and manifest `lookupAliases` (e.g. `crylight → cgrcflare`, `default → cgrcdefault`, 3dEngine soft loads → `cgrcscreen` / `cgrcdefault` / … per [`metal-shader-load-fatal-resolution.md`](metal-shader-load-fatal-resolution.md) §6) |
| Offline Metal PSO validator | See [`metal_pso_validate.md`](metal_pso_validate.md). Build: `cmake --build build --target metal_pso_validate -- -j8`. Example: `./build/RenderDll/XRenderMetal/metal_pso_validate --generated-dir build/FarCry.app/Contents/Resources` (directory must contain **both** `GeneratedShaders.metallib` and `generated_manifest.json`; same folder under `RenderDll/XRenderMetal/Generated` when both exist after generation). |
| Runtime-close shader load (`metal_runtime_validate`) | Same doc — section **Runtime-close validation**. Build: `cmake --build build --target metal_runtime_validate -- -j8`. Example: `./build/RenderDll/XRenderMetal/metal_runtime_validate --assets-dir build/FarCry.app/Contents/Resources` (needs **`UtilShaders.metallib`** + **`GeneratedShaders.metallib`** + **`generated_manifest.json`**). Exercises **`LoadGeneratedShaders`** + **`CMetalStateCache`** like startup; no game loop. |
| Shader-fatal runtime gate   | `lldb --batch -s build/shader_abort_session.lldb` | ✅ Startup path reaches `main(): Starting game` with zero `ShaderLoadFatal` aborts |
| Metal validation layer      | Xcode Metal Validation (runtime)       | Manual only                        |
| GPU frame capture           | `metal_gpucapture` CVar (DEBUG builds) | Available                          |
| Screenshot regression       | `ScreenShot` → TGA                     | Implemented; needs manual baseline |


