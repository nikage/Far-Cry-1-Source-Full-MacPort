# Renderer Comparison Utilities

This directory contains lightweight smoke tests that validate the shader
porting pipeline:

- `d3d9_smoke.dart` – Confirms that canonical HLSL shaders were emitted and,
  when available, that DXIL outputs exist.
- `metal_smoke.dart` – Verifies the generated Metal manifest and the compiled
  `GeneratedShaders.metallib` artifact.

Both scripts default to the repository root as their working directory but
accept an optional path argument for custom build trees. Run them with the
`dart` executable, for example:

```
dart Testing/renderer_compare/d3d9_smoke.dart /path/to/repo
```

Integrate these checks into CI to detect regressions when shader generation or
compilation fails on either renderer.
