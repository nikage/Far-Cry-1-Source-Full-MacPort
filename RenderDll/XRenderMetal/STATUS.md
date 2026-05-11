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
