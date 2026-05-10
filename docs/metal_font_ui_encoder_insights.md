# Metal: fonts, `DrawDynVB`, and UI encoder — key insights

This note captures findings from debugging script/HUD `DrawDynVB`, menu fonts, and swapchain encoder usage. The working tree was reverted to the last known-good font behavior (commit `1a99b1c` on `metal-renderer`: colortex prep for `DrawDynVB`, texture cache fixes, **without** later uniform-slot / overlay experiments).

## 1. Global `Uniforms` vs font MVP share vertex buffer index 2

- `UtilShaders.metal` / `colortex_vertex` uses `METAL_VERTEX_UNIFORM_BUFFER_INDEX` **2** (`kMetalVertexUniformSlot`).
- `SpriteShaders.metal` `font_vertex` used `FontUniforms` at `[[buffer(2)]]` and the host bound the ortho `MTLBuffer` at the same index.
- **Binding `m_uniformBuffer` in `DrawDynVB` for `colortex` fixes MVP for immediate-mode HUD geometry but overwrites slot 2**, so the next font draw reads engine `Uniforms` bytes as `FontUniforms` → broken or invisible menu text.
- **Reliable fix** when `DrawDynVB` must bind `Uniforms`: move font uniforms to a **dedicated vertex buffer index** (e.g. 6) in `SpriteShaders.metal` + `MetalRenderPCH.h` + `FontSetRenderingState`, then bind globals in `DrawDynVB` as in `SetShaderUniforms` (vertex **and** fragment slots).

## 2. `FlushTextMessages()` must not run after `EndFrame` / commit

- `CSystem::RenderEnd` calls `FlushTextMessages()` **before** `Update()` while `m_currentCommandBuffer` is still valid.
- `CMetalRenderer::Update()` historically called `FlushTextMessages()` **after** `CMetalBaseRenderer::Update()` → `EndFrame()` → commit and `m_currentCommandBuffer = nil`, so that flush could not encode.
- Any flush that needs a render encoder must run **before** present/commit, aligned with `RenderEnd` ordering.

## 2b. `ScaleCoordX` / `ScaleCoordY` on Metal

- `CMetalBaseRenderer` implements the same formula as `CRenderer` in `Renderer.h`: scale from **virtual 800×600** layout coordinates to **`GetWidth` / `GetHeight`** (backbuffer pixels). Together with `FontSetRenderingState(0,0)` using full backbuffer ortho, CryFont matches the D3D path where coordinates are scaled before the orthographic projection.

## 3. `TryEnsureSwapchainRenderEncoderFor2D()` reuses the current encoder

- If `m_renderEncoder` is already open on the same command buffer, `TryEnsure` returns **true** without resetting **viewport/scissor**.
- `Draw2dImage` explicitly sets a **full-drawable scissor** before drawing; `FontSetRenderingState` did not, so menu text could be **fully clipped** by a leftover small scissor from an earlier draw.
- **Mitigations**: reset full viewport/scissor when entering font/UI, or start a dedicated **UI overlay pass** (`ReleaseRenderEncoder` + `BeginSwapchainRenderPass` with `MTLLoadActionLoad` + full viewport/scissor) at a stable UI boundary.

## 4. Script `Draw` path: texture + PSO contract

- `CryGame/ScriptObjectRenderer.cpp` calls `Set2DMode`, `SetState`, `SetTexture`, then `DrawDynVB` **without** setting `m_RP.m_pShader`, so `SetState` does not apply a pipeline via the shader manager.
- Metal must bind a pipeline matching `struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F` (e.g. builtin `colortex`) and ensure **fragment slot 0** reflects `SetTexture` even when `SetTexture` ran with **no encoder** (cache `m_boundFragmentTextures` / samplers and re-apply when the encoder exists).

## 5. CryFont call order

- `FFont.cpp` calls `FontSetTexture` **then** `FontSetRenderingState`. If the encoder does not exist at `FontSetTexture`, the atlas must still be recorded in CPU-side cache and **re-bound** once `FontSetRenderingState` creates or reuses the encoder.

## Reverting experiments

Later attempts added: `kMetalFontUniformSlot`, `BeginSwapchainUIOverlayPass`, `DrawDynVB` uniform binds, and `FlushTextMessages` overlay entry. Those changes were reverted to restore menu fonts while keeping the insights above for a future incremental fix (font slot 6 + `DrawDynVB` uniform bind + optional UI overlay, with runtime validation).
