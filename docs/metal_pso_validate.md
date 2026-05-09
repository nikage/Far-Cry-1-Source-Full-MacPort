# Offline Metal PSO validator (`metal_pso_validate`)

macOS-only utility that loads **`GeneratedShaders.metallib`** and **`generated_manifest.json`** from a single directory, then for each manifest **fragment** row builds a Metal render pipeline state offline—without launching the game.

**Sources:** [`RenderDll/XRenderMetal/test/metal_pso_validate.mm`](../RenderDll/XRenderMetal/test/metal_pso_validate.mm), shared helpers [`MetalManifestPSOHelpers.mm`](../RenderDll/XRenderMetal/MetalManifestPSOHelpers.mm) (also used by [`MetalShaderLoader.mm`](../RenderDll/XRenderMetal/MetalShaderLoader.mm)).

---

## What it validates

For each fragment entry (stage other than `vertex`):

1. Resolves the paired **vertex** manifest row via **`vertexEntryPoint`**.
2. Builds **`MTLVertexDescriptor`** from that row (`vertexInputs`, else `vertexAttributeMetadata`) using the same helper path as production (`MetalManifestCreateVertexDescriptorFromManifestVertexEntry` → `CMetalVertexDescriptorHelper`).
3. Builds **`MTLFunctionConstantValues`** from the lowercase shader name plus the fragment **`directives`** array (`MetalManifestBuildFunctionConstants`).
4. Loads **vertex** and **fragment** `MTLFunction` from the metallib with those constants.
5. Applies the fragment **`pipeline`** dictionary to the descriptor (`MetalManifestApplyPipelineConfigFromManifest` → `MetalManifestApplyPipelineConfigToDescriptor`) with **BGRA8Unorm** color and **Depth32Float_Stencil8** depth/stencil (aligned with typical runtime setup).
6. Calls **`newRenderPipelineStateWithDescriptor:options:reflection:error:`** with **`MTLPipelineOptionArgumentInfo`** so Metal performs reflection like the DEBUG **`ValidateShaderPairs`** dry-run in `MetalShaderLoader.mm`.

It does **not** replicate full runtime vertex fallbacks (`InferVertexLayout`, `ApplyScreenVertexFallback`, UtilShaders-only vertex paths). If production relies on those for a given shader, behavior may diverge; treat failures as a signal to compare with DEBUG engine validation.

---

## Runtime-close validation (`metal_runtime_validate`)

For the closest practical match to game startup **without** launching FarCry, use **`metal_runtime_validate`**. It links **`XRenderMetal`**, wires a minimal **`ILog`**, calls **`CMetalBaseRenderer::InitializeMinimalForShaderLoadValidation`** (device + **`CMetalStateCache`** only—no window or gameplay systems), constructs **`CMetalShaderManager`**, and executes the same **`InitializeDefaultShaderLibrary`** → **`LoadGeneratedShaders`** path as the engine—including **`InferVertexLayout`**, UtilShader fallbacks, tangent handling, loader retries, **`CreatePipelineStateWithFunctions`**, and **`CMetalStateCache`** caching.

### Inputs

Set **`FARCRY_METAL_VALIDATION_DIR`** via **`--assets-dir`** (the harness exports this environment variable). The directory must contain all three artifacts side by side (same layout as **`FarCry.app/Contents/Resources`**):

- **`UtilShaders.metallib`**
- **`GeneratedShaders.metallib`**
- **`generated_manifest.json`**

### Build and run

```bash
cmake --build build --target metal_runtime_validate -- -j8
```

Typical binary path: **`build/RenderDll/XRenderMetal/metal_runtime_validate`**

```bash
./build/RenderDll/XRenderMetal/metal_runtime_validate \
  --assets-dir build/FarCry.app/Contents/Resources
```

### Exit codes

- **`0`** — **`pso_failures == 0`** and **`validate_pair_failures == 0`**
- **`2`** — shader load reported one or more PSO failures and/or pair-validation failures (same counters printed on stdout)
- **`1`** — bootstrap error (missing **`--assets-dir`**, device init failure, or default library missing)

The process prints the summary line to **stdout** and then exits with **`_Exit`**, so it does not run C++ destructors for the renderer or shader manager. That keeps the tool’s exit code aligned with the validation counters (full teardown of **`CMetalShader`** objects can hit legacy engine paths that are not required for this check).

The harness sets engine globals **`iLog`** and **`iConsole`** to small stderr / no-op console implementations so **`CRenderer`**’s constructor can register CVars without a full **`CrySystem`**.

In **Release** builds, the harness calls **`RunValidateShaderPairs()`** after load because **`ValidateShaderPairs`** in **`InitializeDefaultShaderLibrary`** is **`#if DEBUG`** only. **Debug** builds already run pair validation during **`InitializeDefaultShaderLibrary`**; the harness does not duplicate that call.

### Division of labor vs `metal_pso_validate`

| | **`metal_pso_validate`** | **`metal_runtime_validate`** |
|--|--|--|
| Code linked | Helpers + **`MetalManifestPSOHelpers`** | Full **`XRenderMetal`** shader manager |
| Path exercised | Direct metallib + manifest → PSO dry-run | **`CMetalShaderManager::LoadGeneratedShaders`** + production pipeline creation |

Use **`metal_pso_validate`** for fast iteration on manifest + PSO helpers; use **`metal_runtime_validate`** when debugging divergences that depend on the **full loader** (fallbacks, vertex inference, state cache).

---

## How this differs from other checks

| Layer | What it checks |
|-------|----------------|
| `dart tools/shader_port/bin/validate_pairs.dart` | Manifest structure and pairing rules; **no GPU / no metallib** |
| `dart tools/shader_port/bin/validate_migration.dart .` | Generate + compile-check every `.metal` + validate_pairs; **no linked PSO** |
| **`metal_pso_validate`** | **PSO creation** with vertex descriptor + function constants + pipeline blend parity vs helpers |
| **`metal_runtime_validate`** | Full **`CMetalShaderManager::LoadGeneratedShaders`** + **`CMetalStateCache`** path (`FARCRY_METAL_VALIDATION_DIR`); see **Runtime-close validation** below |
| DEBUG **`ValidateShaderPairs`** (`MetalShaderLoader.mm`) | Same class of PSO dry-run **after** full loader registration; capped failures |
| [`GeneratedPSOTests.mm`](../RenderDll/XRenderMetal/test/GeneratedPSOTests.mm) | Legacy single-file `clang++` harness without linking **`XRenderMetal`**; older naming—prefer CMake **`metal_pso_validate`** |

---

## Prerequisites

Both files must live in **the same directory** (the tool reads `GeneratedShaders.metallib` and `generated_manifest.json` next to each other):

- **`GeneratedShaders.metallib`**
- **`generated_manifest.json`**

Produce them via the normal shader pipeline (for example `dart tools/shader_port/bin/validate_migration.dart .`) and/or CMake targets that generate and compile Metal (**`GeneratedMetalShaders`**, **`GenerateMetalShaderSources`**) as wired in [`RenderDll/XRenderMetal/CMakeLists.txt`](../RenderDll/XRenderMetal/CMakeLists.txt).

**Common pitfall:** After a build, the pair is often staged together under **`build/FarCry.app/Contents/Resources/`**. The tree **`RenderDll/XRenderMetal/Generated/`** may contain the manifest (and many `.metal` files) while the metallib exists only under **`build/RenderDll/XRenderMetal/`** until copied—so **`--generated-dir`** must point at a folder that actually contains **both** artifacts.

---

## Build and run

From the repository root (Ninja example matches project convention):

```bash
cmake --build build --target metal_pso_validate -- -j8
```

Executable (typical path):

`build/RenderDll/XRenderMetal/metal_pso_validate`

The binary links **`libXRenderMetal.dylib`** (helpers + Cry dependencies live in that library). CMake adds **`-Wl,-rpath,@executable_path`** so the loader finds **`libXRenderMetal.dylib`** sitting **next to** `metal_pso_validate` in the same directory.

**Example** using staged app resources (paths relative to repo root):

```bash
./build/RenderDll/XRenderMetal/metal_pso_validate \
  --generated-dir build/FarCry.app/Contents/Resources
```

Optional lightweight test target (when CMake enables tests): **`MetalManifestPSOHelpersTests`** — exercises manifest pipeline parsing helpers without walking the full manifest.

---

## Discovery order for `--generated-dir`

If you omit **`--generated-dir`**, the tool tries:

1. **`GENERATED_DIR`** environment variable  
2. Directory containing **`GeneratedShaders.metallib`** next to **`argv[0]`**  
3. **`../../Generated`** relative to the binary  
4. **`../../../RenderDll/XRenderMetal/Generated`** relative to the binary  

Prefer an explicit **`--generated-dir`** when artifacts are staged outside those layouts.

---

## Command-line reference

| Flag | Meaning |
|------|---------|
| `--generated-dir DIR` | Directory containing both `GeneratedShaders.metallib` and `generated_manifest.json` |
| `--filter REGEX` | Case-insensitive regex; only fragment rows whose `shader` name matches are validated |
| `--fail-fast` | Exit on first validation failure (after recording it) |
| `--max-failures N` | Stop after **N** failures (default is very large; use for CI sampling) |
| `--shard I N` | Only process fragment rows whose manifest index satisfies `index % N == I` (0-based **I**, **N** ≥ 1) |
| `--json` | Print one JSON object per shader result on stdout (`ok`, `shader`, `detail` on failure) |
| `--gpu-smoke` | After a successful PSO, run a minimal render pass (1×1 RT, triangle draw without guaranteed vertex buffer layout—best-effort encoder smoke) |
| `-h`, `--help` | Usage line |

---

## Exit codes

| Code | Meaning |
|------|---------|
| **0** | Success: no validation failures; or **`--help`** |
| **1** | Startup / environment errors (invalid `--shard`, bad `--filter` regex, cannot find artifacts directory, cannot load metallib or manifest, no Metal device, JSON parse failure) |
| **2** | One or more shader pairs failed validation; or **`--fail-fast`** / **`--max-failures`** triggered after failures |

---

## Interpreting failures

- **Cannot load metallib / manifest** — Wrong **`--generated-dir`**; files missing or not co-located.
- **missing vertex manifest row for vertexEntryPoint** — Fragment **`vertexEntryPoint`** does not match any vertex row **`entryPoint`** in the manifest array.
- **`MetalManifestCreateVertexDescriptorFromManifestVertexEntry returned nil`** — Vertex row lacks usable **`vertexInputs`** / **`vertexAttributeMetadata`**.
- **Missing vertex / fragment function** — Entry point name typo or metallib built without that symbol; check **`newFunctionWithName:constantValues:error:`** message.
- **PSO creation failed** (`localizedDescription`) — Layout vs shader signature mismatch, blend state, or Metal reflection error; compare with DEBUG **`ValidateShaderPairs`** logs for the same shader.
- **GPU smoke draw failed** — Encoder or GPU validation rejected the draw (optional path; does not prove correctness of full vertex streams).

---

## See also

- Feature checklist and testing overview: [`metal_renderer_plan.md`](metal_renderer_plan.md) — section **Testing**
- Production roadmap (automation / QA context): [`metal_renderer_production_roadmap.md`](metal_renderer_production_roadmap.md)
- Commit gate commands: [`.cursor/rules/run-tests-before-commit.mdc`](../.cursor/rules/run-tests-before-commit.mdc)
- Unified shader toolchain validation: [`.cursor/rules/shader-pipeline-validation.mdc`](../.cursor/rules/shader-pipeline-validation.mdc)
