# External Assets

This directory mirrors data copied from the working CrossOver Steam install so we
can regenerate macOS‑friendly packages without depending on Windows at runtime.

Current contents:

- `Languages/Movies/DemoLoops/CryTek.bik`
- `Languages/Movies/English/*.bik`:
  - `Crytek`, `Ubi`, `sandbox`
  - `bunker`, `dam`, `pier`, `regulator`, `River`
  - `factory`, `factory1`
  - `training_begin`
  - `volcano01`, `volcano02`, `volcano_final`

These match the intro, cutscene, and menu background videos from the
CrossOver bottle at:

```
~/Library/Application Support/CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam/steamapps/common/FarCry/Languages/Movies
```

Use these sources as input to the Dart-based converter in
`tools/intro_video_converter` when building MP4 replacements for the macOS port.

> The legacy Steam build does not ship `Governmental_Message.bik` or `AMD64.bik`
> (referenced by the original intro sequence), so they cannot be converted here.
> The UI scripts should fall back to the available Crytek/Ubi/sandbox clips on
> macOS once MP4s are generated.

