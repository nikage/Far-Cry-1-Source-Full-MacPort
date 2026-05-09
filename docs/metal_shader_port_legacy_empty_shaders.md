# Metal shader port: legacy-only shaders, empty IR, and correctness

This document captures practical conclusions from triaging **Cry shader scripts** that produce **empty or degenerate IR** for the Dart → Metal pipeline, plus how **vertex–fragment pairing** and **engine binding context** affect correctness. It complements—not replaces—the full validation workflow in `.cursor/rules/shader-pipeline-validation.mdc` and [metal_renderer_plan.md](metal_renderer_plan.md).

## Related docs and rules

- [shader-pipeline-validation.mdc](../.cursor/rules/shader-pipeline-validation.mdc) — unified `validate_migration.dart` stages
- [metal_pso_validate.md](metal_pso_validate.md) — CMake PSO / manifest validation
- [shader-aliases.md](shader-aliases.md) — aliasing fragment names to existing manifests

---

## 1. Warning taxonomy

### IR-1 (fully empty shader)

**Meaning:** Parsed IR has no `CoreScript` block, no `positionScripts`, and no `positionScriptBlocks`. The Metal generator still emits a file, but the functional body is empty—validator rule **IR-1** in [`ir_validator.dart`](../tools/shader_port/lib/ir_validator.dart).

**Typical cause:** Source is gated only on legacy backends (`#ifdef D3D`, `#ifdef OPENGL`) with **register combiners**, **`ps.1.0` assembly**, or **OpenGL combiner** blocks that the Cry→IR parser does **not** lift into CoreScript. Example: [`CGRCBump_ReflLight.crycg`](../Assets/Shaders/Source/Shaders/HWScripts/Declarations/CGPShaders/CGRCBump_ReflLight.crycg).

**Mask exemption nuance:** `_checkEmpty` can skip IR-1 when **every** `maskReference` is a known non-Metal backend (D3D, OPENGL, …). During **`validateParseResult`**, the validator passes **`maskReferences: []`**, so that exemption **never runs** during bulk IR generation—warnings may appear even when the written JSON lists only `D3D`/`OPENGL`. **`validateIr`** (JSON path) **does** pass `maskReferences` from the IR object.

### Fragment output type / vertex `HPosition`

**Meaning:** [`MetalFragmentBuilder._outputType`](../tools/shader_port/lib/metal_fragment_builder.dart) could not find a declared type for a named output (e.g. `Color`, `Depth`) in `outputFieldTypes`, or could not infer vertex output width for `HPosition`.

**Effect:** Code generation continues with **`float4`** defaults and prints **`WARN:`** to stderr. Many shaders reference standard outputs without declaring them in `MainInput` in a way the parser records—so these warnings are often **bulk noise**, not a single broken shader.

### `translateType`: unknown `half4`

**Meaning:** HLSL type **`half4`** (and other `half*` variants) is not handled in the `translateType` switch in [`metal_fragment_builder.dart`](../tools/shader_port/lib/metal_fragment_builder.dart); execution falls through to **`float4`**.

**Note:** IR validation may still allow `half4` as a uniform type elsewhere—the emission path and validation lists are not identical.

---

## 2. Consequences of “empty” generated fragments

Generation still produces a **valid Metal fragment function**:

- The body default-initializes a struct **`OUT`**.
- [`ExpressionTranslator`](../tools/shader_port/lib/expression_translator.dart) sets **`returnExpression`** to **`OUT.Color`** when the analyzer’s output set includes **`Color`**.
- [`_InOutAnalyzer.outputFields`](../tools/shader_port/lib/metal_fragment_builder.dart) **always adds `Color`** to the sorted output field list.

If **no** translated lines assign **`OUT.Color`**, default initialization yields **zeros** → **`float4(0,0,0,0)`** (transparent black). That is a **silent** rendering failure for any draw that binds this shader on Metal: wrong transparency, darkening, or missing surfaces—not necessarily a compile-time error.

---

## 3. Fix strategies (rough cost order)

### Aliases

Point engine lookups at an **existing** fragment name that already has correct generated Metal and manifest entries. See [shader-aliases.md](shader-aliases.md) and `Aliases.txt`. Fastest way to confirm “wrong empty shader” vs “something else.”

### Parseable Cry / CoreScript path

Add (or restore) logic the toolchain understands—**`CoreScript`**, **`MainInput`** with uniforms/samplers, Metal-active preprocessor branches—so IR is non-empty. This is the **canonical** fix for the Dart generator; fixes belong in the generator/parser layer per project rules, not by hand-editing generated `.metal` files for regressions.

### Handwritten Metal fragments

Runtime loads **fragment** functions from **`GeneratedShaders.metallib`** via [`MetalShaderLoader.mm`](../RenderDll/XRenderMetal/MetalShaderLoader.mm) (`newFunctionWithName` on the generated library). **`UtilShaders.metallib`** supplies **default / fallback vertex** helpers and similar—not a general fallback library for arbitrary fragment names unless you extend the loader.

To ship a hand-written fragment under an existing manifest entry point name, it must end up **compiled into** (or linked as) the **same metallib the loader uses for generated fragments**, **or** you add explicit multi-library fallback in C++.

### `shader_pair_overrides.json` is not “hand Metal injection”

[`shader_pair_overrides.json`](../tools/shader_port/config/shader_pair_overrides.json) drives **vertex–fragment pairing** in [`metal_generator.dart`](../tools/shader_port/lib/metal_generator.dart) (`fragmentPairing`): which **vertex shader name** pairs with a fragment when resolving **`vertexEntryPoint`** and **`pairedVertexOutputs`**. It does **not** substitute custom `.metal` sources by itself.

---

## 4. Correctness: engine context (`col0`, `texK`, `const*`)

Register-combiner and fixed-function symbols are **pipeline-relative**:

| Symbol | Typical role |
|--------|----------------|
| `col0` | Primary **vertex color** (diffuse tint), analogous to varyings like **`IN.Color`** in CoreScript shaders. |
| `texK` | Result of **texture stage K** after stage setup—not “slot K” in isolation. |
| `const*` | **Combiner constant registers**, fed from **shader parameters**, material constants, or pass state. |

A **fragment-only** `.crycg` with only **`Script`/`CombinersStat`** blocks often declares **none** of this in IR. Full correctness requires:

1. **`MainInput` / declarations** when present (uniforms, `sampler`, registers).
2. **Technique / pass definitions** that reference this pixel shader name and configure **texture stages**.
3. **`generated_manifest.json`** rows for that fragment: **`uniforms`**, **`textures`**, and **`slot`** alignment with what the engine binds.
4. **Metal runtime**: fragment texture binding path in [`MetalShaderManager.mm`](../RenderDll/XRenderMetal/MetalShaderManager.mm) (e.g. slot-indexed `setFragmentTexture`).

Optional: frame capture on the **original** D3D/OpenGL path to verify bound textures and constants.

---

## 5. Manifest-paired vertex entry

**Definition:** For each **fragment** shader row in **`generated_manifest.json`**, **`vertexEntryPoint`** is the Metal function name of the **vertex shader** the generator paired with that fragment (when pairing succeeded).

**Construction order** in [`metal_generator.dart`](../tools/shader_port/lib/metal_generator.dart) (`fragmentPairing`):

1. Explicit **`shader_pair_overrides.json`** entry → named vertex shader → `generated_<normalizedVS>_vertex`.
2. **Technique-derived** fragment→vertex map (`techniqueFragToVertShader`).
3. Heuristic **`_resolveVertexEntryPoint`** if still unmatched.

The fragment Metal emitter uses **`pairedVertexOutputs`** so **`stage_in`** matches **that** vertex shader’s output struct widths.

**Runtime:** [`MetalShaderLoader.mm`](../RenderDll/XRenderMetal/MetalShaderLoader.mm) prefers the manifest’s **`vertexEntryPoint`** when resolving `MTLFunction`s for the paired VS so the **VS/FS interface stays consistent** (including versioned VS variants vs canonical keys).

---

## 6. Case-by-case triage checklist

1. **Classify** the legacy body: register combiners (`!!RC1.0`), **`ps.1.0`**, vs parseable **CoreScript**.
2. **Do not** infer the full FS **`stage_in`** from an empty fragment IR alone—open **`generated_manifest.json`** for that fragment: **`vertexEntryPoint`**, **`vertexAttributeMetadata`**, **`textures`**, **`uniforms`**.
3. **Estimate math vs interface:**
   - Combiner/ps.1.0 snippets are often **short** algebraically but **opaque** on bindings until technique/uniform context is known.
   - **Interface** difficulty tracks the **paired vertex** outputs (tangents, multiple texcoords, clip)—see manifest, not the stub IR.
4. **Choose fix:** alias → hand fragment (matching existing signature) → full Cry/CoreScript port → parser extensions for legacy syntax (last resort).
5. **Validate:** `dart tools/shader_port/bin/validate_migration.dart .`, build **`metal_pso_validate`**, project runtime smoke (menu, level, debug asserts per `.cursor/rules`).

---

## 7. Example: empty IR but non-empty pairing elsewhere

[`CGRCBump_ReflLight.crycg`](../Assets/Shaders/Source/Shaders/HWScripts/Declarations/CGPShaders/CGRCBump_ReflLight.crycg) contains only D3D/OpenGL legacy blocks; paired IR JSON may show **`maskReferences`: `D3D`, `OPENGL`** and **empty** `coreScriptExpressions`. Correctness and varyings for any **future** Metal implementation still depend on **technique pairing** and **manifest** rows for the fragment name actually used in-game—not on this fragment file’s minimal parsed attributes alone.
