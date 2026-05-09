# Empty CoreScript IR inventory (shader_port output snapshot)

Shaders whose parsed IR contains **`coreScriptExpressions`: []** yield degenerate Metal fragments until Cry sources gain parseable **`CoreScript`**.

## Snapshot command

```bash
rg -l '"coreScriptExpressions": \[\]' tools/shader_port/output/ir
```

## Results (current tree)

| Priority | Shader | Notes |
|----------|--------|--------|
| High | `CGPShaders/CGRCBump_ReflLight.crycg` | Pilot fix: PS20 CoreScript paired with `CGVProgBump_DiffSpecPass_Atten`. |
| High | `CGPShaders/CGRCBump_ReflLight_Overlay.crycg` | Same pairing; simpler overlay combine. |
| Review | `CGVShaders/CGVProgSimple.crycg` | Vertex shader; investigate separately (may be intentional minimal VS). |
| Review | `CGVShaders/CGVProgSimple_Stencil.crycg` | Vertex shader; investigate separately. |

Re-run `dart tools/shader_port/bin/validate_migration.dart .` after editing sources and refresh this list if counts change.
