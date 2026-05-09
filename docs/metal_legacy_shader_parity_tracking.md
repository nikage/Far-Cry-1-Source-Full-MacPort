# Metal legacy shader parity — execution log

Working notes from applying **Metal parity for legacy empty-body shaders** (see plan). Update this file when completing phases for additional shader names.

**Related:** [metal_shader_port_legacy_empty_shaders.md](metal_shader_port_legacy_empty_shaders.md)

---

## Scope: `CGRCBump_ReflLight`, `CGRCBump_ReflLight_Overlay`

Sources: [CGRCBump_ReflLight.crycg](../Assets/Shaders/Source/Shaders/HWScripts/Declarations/CGPShaders/CGRCBump_ReflLight.crycg), [CGRCBump_ReflLight_Overlay.crycg](../Assets/Shaders/Source/Shaders/HWScripts/Declarations/CGPShaders/CGRCBump_ReflLight_Overlay.crycg).

---

### Phase 1 — Usage (in scope for parity?)

| Finding | Detail |
|--------|--------|
| **Declarations in tree** | Present under `Assets/Shaders/Source/.../CGPShaders/`. |
| **Cross-references in `.crycg`** | No other `Assets/Shaders/Source` file text-matched `CGRCBump_ReflLight` / `_Overlay` (techniques may reference templates or pak-only scripts). |
| **Runtime** | [RenderDll/XRenderMetal/test/log.txt](../RenderDll/XRenderMetal/test/log.txt) shows both names **registered** by MetalShaderManager (`CGRCBump_ReflLight_Overlay` id=283, `CGRCBump_ReflLight` id=571). |

**Decision:** Treat as **potentially used** at runtime; parity matters if any draw binds them. Further **material-level** confirmation: grep extracted game packs / in-game capture if full certainty is required.

---

### Phase 2 — Ground truth (legacy behavior)

| Variant | Legacy body |
|--------|-------------|
| **ReflLight** | D3D/OpenGL `!!RC1.0` combiners: combine `col0 * const0` with `tex3`, then mix with `const1`; `out.a = unsigned_invert(zero)`. |
| **Overlay** | D3D `ps.1.0`: `texm3x3*` bump/spec sample × `c0`; OPENGL RC: `out.rgb = tex3 * const0`. |

**Empirical capture:** Not run in this pass — optional RenderDoc/PIX on original API for slot/bind verification before declaring visual parity.

---

### Phase 3 — Manifest / pairing / VS contract

| Item | Value |
|------|--------|
| **Normalized fragment keys** | `cgrcbump_refllight`, `cgrcbump_refllight_overlay` |
| **Explicit pair override** | [shader_pair_overrides.json](../tools/shader_port/config/shader_pair_overrides.json): both map to vertex **`CGVProgBump_DiffSpecPass_Atten`**, category **mesh**. |
| **Expected vertex entry point** | `generated_<normalized_vs>_vertex` for `CGVProgBump_DiffSpecPass_Atten` (run `metal_generator.dart` and read `generated_manifest.json` for exact string). |
| **Repo `Generated/generated_manifest.json`** | Not checked in — regenerate after `dart ... metal_generator.dart` / full validation pipeline. |

**Contract rule:** Any replacement fragment must match **`stage_in`** implied by **`CGVProgBump_DiffSpecPass_Atten`** outputs paired via [`metal_generator.dart`](../tools/shader_port/lib/metal_generator.dart) `pairedVertexOutputs`.

---

### Phase 4 — Porting lane (chosen / next step)

| Lane | Status | Notes |
|------|--------|--------|
| **A — Alias** | Not applied | Candidate substitutes must share pass semantics and manifest-normalized targets per [shader-aliases.md](shader-aliases.md); requires visual + PSO validation before editing `Aliases.txt`. |
| **B — CoreScript / Metal-visible branch** | **Recommended** | Add parseable `MainInput` + `CoreScript` (and preprocessor branch active for the Metal preprocessor) so IR is non-empty; mirror RC/ps1.0 math with explicit `tex2D`/`texCUBE` and uniforms aligned to manifest slots. |
| **C — Hand Metal** | Alternative | Same fragment `entryPoint` as manifest, compiled into `GeneratedShaders.metallib`; see [MetalShaderLoader.mm](../RenderDll/XRenderMetal/MetalShaderLoader.mm) fragment load path. |
| **D — Parser lifts RC/ps1.0** | Deferred | Only if many shaders share this pattern. |

**Binding parity:** Match texture **slots** and uniform semantics to [`MetalShaderManager`](../RenderDll/XRenderMetal/MetalShaderManager.mm) fragment binding order, not only the math.

---

### Phase 5 — Validation gates

Run after any shader or generator change:

1. `dart tools/shader_port/bin/validate_migration.dart .`
2. `cmake --build build --target metal_pso_validate -- -j8` then `./build/RenderDll/XRenderMetal/metal_pso_validate --generated-dir RenderDll/XRenderMetal/Generated` (adjust paths if build layout differs).
3. Runtime smoke per `.cursor/rules/run-tests-before-commit.mdc` and `verify-fixes-at-runtime.mdc`.

**Recorded local run (parity-plan execution, doc-only branch):**

| Step | Result |
|------|--------|
| `validate_migration.dart .` | **Exit 0** — IR validate + generate + compile-check (995/995) + validate-pairs (589/589). |
| `cmake --build … metal_pso_validate` | **Exit 0** — target built (`build/RenderDll/XRenderMetal/metal_pso_validate`). |
| `metal_pso_validate` | **Exit 0** — `pass=589 fail=0` after copying freshly built `GeneratedShaders.metallib` from `build/RenderDll/XRenderMetal/` beside `RenderDll/XRenderMetal/Generated/generated_manifest.json` (the validator requires **both** files in the same `--generated-dir`; metallib is normally produced next to the binary, not always checked into `Generated/`). |

**Runtime smoke (game menu / level / asserts):** not executed in this pass — required when changing actual shader source or Metal binaries.

---

## Deliverable checklist (plan)

- [x] Usage/risk note (Phase 1)
- [x] Legacy behavior summary (Phase 2)
- [x] Pairing / VS intent (Phase 3)
- [x] Lane recommendation (Phase 4)
- [x] Phase 5 toolchain gates (`validate_migration`, `metal_pso_validate`); runtime smoke **manual** until shader code changes
