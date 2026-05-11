# Metal renderer — render-element status

Snapshot of the per-`EDataType` `mfDraw` coverage in the Metal backend, after
the **fix metal scene draws** pass. Every entry here is either:

- **Implemented** — issues `drawIndexedPrimitives` (directly, or via
  `CMetalBaseRenderer::DrawBuffer` / `DrawDynVB`).
- **Canonical no-op** — silent `return true;` that matches the OGL/D3D9
  semantics (used by passes where the draw is performed elsewhere via
  the chunked `CMetalREOcLeaf` path).
- **Stubbed** — placeholder that does not draw and is **not** ready for
  visual gameplay. Instrumented with `METAL_STUB_TRACE` (gate-2 telemetry,
  see `RenderDll/Common/StubTelemetry.h`) so the log surfaces them at
  runtime when `cry_trace_render_gates 2` is set.

## Implemented render elements

| EDataType                | Class                  | Source                                                  | Notes |
|---|---|---|---|
| `eDATA_OcLeaf`           | `CMetalREOcLeaf`       | `MetalRenderElements.mm`                                | Indexed draw via `DrawBuffer`. Reference template for new ports. |
| `eDATA_TempMesh`         | `CRETempMesh`          | `MetalRETempMesh.mm`                                    | Ported from `XRenderOGL/GLRERender.cpp`. Issues `DrawBuffer` for dynamic streams. |
| `eDATA_ClearStencil`     | `CREClearStencil`      | `MetalREClearStencil.mm` + `CMetalBaseRenderer::ClearStencilBuffer` | Ends current encoder, restarts pass with `stencilLoadAction = MTLLoadActionClear`. |
| `eDATA_Sky`              | `CMetalRESky`          | `MetalRenderElements.mm`                                | Pre-existing native Metal path. |
| `eDATA_Ocean`            | `CMetalREOcean`        | `MetalREOcean.mm`                                       | Pre-existing FFT ocean. |
| `eDATA_OcclusionQuery`   | `CREOcclusionQuery`    | `MetalRenderElements.mm`                                | Constructed via `new CREOcclusionQuery()` in factory; no GPU draw needed. |
| `eDATA_ScreenProcess`    | `CREScreenProcess`     | (common)                                                | Existing fullscreen path. |

## Canonical no-ops (geometry drawn by OcLeaf path)

| EDataType            | Class                  | Why no-op |
|---|---|---|
| `eDATA_TerrainSector`| `CMetalRECommon`       | Terrain sectors are emitted via `CMetalREOcLeaf` chunks; this class only carries metadata. Matches OGL/D3D9 behaviour. |
| `eDATA_TriMesh`      | `CMetalRETriMesh`      | Generic tri-meshes draw through the `CMetalREOcLeaf` chunked path attached to each `SMatInfo`. |
| `eDATA_Prefab`       | `CMetalREPrefabGeom`   | Prefabs delegate to the per-chunk OcLeaf draws; this class is a per-instance marker. |
| `eDATA_OcLeaf` (base)| `CREOcLeaf`            | Base virtual stub; should be unreachable because `CMetalREOcLeaf` overrides it. Instrumented with telemetry so any actual hit is visible. |

A `RendererLogicTests` regression test now guards each of these against
silently re-introducing the broken "set state but no draw" stub.

## Sun flares (depth visibility)

| EDataType         | Class           | Source                       | Notes |
|---|---|---|---|
| `eDATA_FlareGeom` | `CREFlareGeom`  | `MetalREFlareGeom.mm`        | Time-based fade (no synchronous depth readback). Matches NULL renderer behaviour. **Follow-up**: async blit + 1-frame-latency depth probe for true occluded flares. |

## Stubbed (placeholder factories, no draw)

The factory in `CreateMetalRenderElement` returns a bare `new CRendElement()`
that does nothing on `mfDraw`. These will silently no-op until a Metal
port is written. Listed in (approximate) impact order on gameplay visuals:

| EDataType            | What it is                                 | Visible effect of stub |
|---|---|---|
| `eDATA_ShadowMapGen` | Shadow map render-target pass              | No real shadow maps; objects render unshadowed. |
| `eDATA_TriMeshShadow`| Shadow-volume mesh draws                   | No stencil-volume shadows. |
| `eDATA_HDRProcess`   | HDR tonemap / bloom / glare composite      | HDR pipeline already runs through the dedicated `m_hdrToneMapPSO`; this RE is unused on Metal in practice. |
| `eDATA_FlashBang`    | FlashBang grenade fullscreen flash         | Grenade flash effect missing. |
| `eDATA_Glare`        | Lens-glare overlay                         | Lens glare missing (sun coronas still drive `CREFlareGeom`). |
| `eDATA_Flare`        | Legacy flare placeholder                   | Subsumed by `CREFlareGeom`; unused on Metal. |
| `eDATA_Beam`         | Beam render element                        | Missing on Metal; not exercised by stock levels. |
| `eDATA_Dummy`        | Intentional placeholder                    | Intended no-op. |

## Per-pass texture binding contract

CryEngine's scene render pipeline is two-phase: the bucket walker selects a
PSO/shader pair, then **each `SShaderPass` is responsible for binding its own
material textures** before any draw call records vertices. In the OGL and
D3D9 backends this is invoked from `EF_PipeLine` via
`if (slw->mfSetTextures()) ...` (`XRenderOGL/GLRendPipeline.cpp:4490, 4783,
5435, 5641, 6101`). The Metal port's `SShaderPass::mfSetTextures` is fully
implemented and routes through `CMetalTextureManager::ApplyTexUnit` to
`[encoder setFragmentTexture:atIndex:]`, but **the call site was missing
from `CMetalRenderer::EF_EndEf3D`**, so every scene fragment shader sampled
nil — rendered as opaque black on Metal — which produced the
"180 draws/frame but black screen" signature observed in `log.txt`.

**Contract**: the `drawBucket` lambda in `EF_EndEf3D` must call
`pPass->mfSetTextures()` immediately before `ri.Item->mfDraw(pShader, pPass)`,
guarded by `if (pPass)` for shaders without HW techniques. The
`test_ef_endef3d_binds_pass_textures_before_mfdraw` regression test locks
this invariant in source so the binding cannot regress without breaking the
build.

Texture binding flow:

```
EF_EndEf3D bucket loop
  -> pPass->mfSetTextures()
       -> for each m_TUnits[i]: SShaderTexUnit::mfSetTexture(i)
            -> CMetalTextureManager::ApplyTexUnit(stage, *this)
                 -> resolve ITexPic -> id<MTLTexture>
                 -> fallback to m_whiteTexture if missing
                 -> GetOrCreateSamplerState(unit)
                 -> BindTexture(stage, texture)   // setFragmentTexture: stage
                 -> BindSampler(stage, sampler)   // setFragmentSamplerState: stage
  -> ri.Item->mfDraw(pShader, pPass)
       -> SetCullMode/SetState/DrawBuffer (state on m_renderEncoder)
```

Follow-ups (out of scope for the black-scene fix):

- Per-pass uniform evaluation: `EF_Eval_DeformVerts`, `EF_Eval_TexGen`,
  `EF_Eval_RGBAGen` (`XRenderOGL/GLRendPipeline.cpp:5634-5636`) are still
  missing on Metal. Visual fidelity will be lower than D3D9/OGL until those
  evaluations land — surfaces using vertex deformation, animated texgen, or
  per-pass RGBA generators will not animate correctly.
- LMaterial application: `m_LMaterial->mfApply(slw->m_LMFlags)` and
  `EF_ConstantLightMaterial` are not invoked on Metal; per-material light
  constants come from the global material buffer only.

## Pass-restart contract

The Metal `m_renderEncoder` lifetime is **not** stable across the bucket loop
in `CMetalRenderer::EF_EndEf3D`. Several functions reachable from `mfDraw`
end the current encoder and start a fresh render pass:

| Site | Trigger | Restart attachments |
|---|---|---|
| `CMetalBaseRenderer::ClearStencilBuffer` | `CREClearStencil::mfDraw` (`EFSLIST_STENCIL_ID` bucket) | color/depth = `Load`, stencil = `Clear` |
| `CMetalBaseRenderer::ClearColorBuffer`   | `ClearBuffer` calls from the engine    | color = `Clear`, depth/stencil = `Load` |
| `CMetalBaseRenderer::ClearDepthBuffer`   | depth-prepass clears                   | color = `Load`, depth/stencil = `Clear` |
| `CMetalBaseRenderer::BeginHDRPass`       | HDR-enabled frames                     | binds `m_hdrColorRT` (different texture) |
| `CMetalRenderer::PrepareDepthMap`        | shadow map preparation                 | depth-only pass on `m_shadowMapTexture` |
| `CMetalUtilityRenderer::SetRenderTarget` | offscreen RT push/pop                  | RT-specific |

Because the new encoder is a **different `id<MTLRenderCommandEncoder>`** than
the one in use before the restart, any caller that captured a local copy of
`m_renderEncoder` (the bucket loop in `EF_EndEf3D` did this) sees a released
object after the swap. State setters (`setRenderPipelineState`,
`setVertexBuffer`, `setFragmentBuffer`) become silent no-ops while
`DrawBuffer` continues to use `m_renderEncoder` and submits draws with no
PSO/uniforms bound — the original "180 draws per frame but black screen"
signature.

**Contract**: `EF_EndEf3D` refreshes its local `encoder` from
`m_renderEncoder` at the top of every iteration of every `drawBucket` and
resets `prevShader = nullptr` whenever the pointer changes, forcing a PSO
re-bind on the new encoder. A null-encoder `continue` guard protects against
a pass-restart that failed to produce a new encoder. Three regression tests
in `RendererLogicTests.cpp` (`test_ef_endef3d_refreshes_encoder_inside_bucket_loop`,
`test_ef_endef3d_resets_prev_shader_on_encoder_swap`,
`test_ef_endef3d_handles_null_encoder_after_pass_restart`) lock this
behaviour in source.

When `cry_trace_render_gates >= 2`, `ClearStencilBuffer` and the
`EF_EndEf3D` loop each emit a one-shot `[CryTrace]` line so future
regressions of the contract are visible in `log.txt`.

## Telemetry conventions

- Stub-hit telemetry uses `METAL_STUB_TRACE(tag, fmt, ...)` /
  `METAL_STUB_TRACE_BARE(tag)`. Both emit at most once per first hit and
  every 300 hits thereafter, only when `cry_trace_render_gates >= 2`.
- The Metal `EndFrame` per-second draw-call counter
  (`[CryTrace] EndFrame frame=… draws=…(+…) tris=…(+…)`) is gated at
  `cry_trace_render_gates >= 1`; it remains the primary signal that the
  scene is reaching the GPU.
- A first-hit-only `[BrushLM]` diagnostic in `Cry3DEngine/BrushLM.cpp`
  surfaces the supplied vs required UV counts for the first lightmap that
  hits the mismatch path. This runs unconditionally on macOS to make the
  per-level signature obvious in `log.txt`.

## Follow-ups (out of scope of the black-screen fix)

1. **Async depth readback for `CREFlareGeom`** — replace the time-based
   fade with a 1-frame-latency depth probe (`MTLBlitCommandEncoder`
   copy → `id<MTLBuffer>` → `addCompletedHandler` callback).
2. **Lightmap UV mismatch** — current diagnostic prints the
   `iNumTexCoords` vs `m_SecVertCount` per asset. The mismatch is
   bake-side (`levellm.pak` baked by the editor on a different
   `evs_*` policy than the runtime's `evs_NoSharing` path). A
   follow-up should either:
   - re-bake `levellm.pak` against `evs_NoSharing` semantics, or
   - reconcile by expanding the brush-side UV list at load time using
     the leaf-buffer's vertex remap table.
3. **`eDATA_ShadowMapGen` / `eDATA_TriMeshShadow`** — needed for
   real-time shadows. Port path: separate depth-only render pass with
   `MTLRenderPassDescriptor.depthAttachment.texture = m_shadowMap`.
4. **`eDATA_FlashBang` / `eDATA_Glare`** — fullscreen post effects;
   should follow the existing `CMetalRenderer::PrepareDynVBColortexDrawState`
   pattern used for `Draw2dImage`.
