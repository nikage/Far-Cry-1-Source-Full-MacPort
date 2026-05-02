---
name: review-fix-and-commit
description: Reviews the current git diff, scopes the commit to only the files for the specific fix (ignoring unrelated changes), runs the applicable unit tests, and creates a commit in the project's module-bracket format. Use when the user asks to "review fix and commit", "commit the fix", or "commit this".
---

# Review Fix and Commit

## Step 1 — Gather context (run in parallel)

```bash
git diff --stat
git status --short
git log --oneline -5
```

Use the log to match the project's commit message style and identify the active branch.

## Step 2 — Read the diffs

Read the full diff for every modified file that belongs to this fix. Skip unrelated files (other modules, WIP changes, generated artifacts, `.idea/`, `.dart_tool/`).

## Step 3 — Run applicable tests

Follow the table from the `run-tests-before-commit` workspace rule:

| Changed files | Test command | Working dir |
|---|---|---|
| `CryInput/**` | *(no unit tests — build is the gate)* | — |
| `RenderDll/XRenderMetal/test/*.cpp` | `clang++ -std=c++17 -o renderer_logic_tests RendererLogicTests.cpp && ./renderer_logic_tests` | `RenderDll/XRenderMetal/test/` |
| `RenderDll/XRenderMetal/**` (shader/PSO) | `clang++ ... -o generated_pso_tests GeneratedPSOTests.mm && ./generated_pso_tests` | `RenderDll/XRenderMetal/test/` |
| `tools/shader_port/**` | `dart test` | `tools/shader_port/` |
| `CrySystem/**` | `clang++ -std=c++17 -o asset_validator_tests AssetValidatorTests.cpp && ./asset_validator_tests` | `CrySystem/test/` |

All suites must exit 0.

## Step 4 — Stage only the fix files

`git add` only the files that belong to this specific fix. Do not stage:
- Unrelated modified files (`.idea/`, `README.md`, other modules' changes)
- Generated binary artifacts (`*.metallib`, compiled test binaries)
- `debug_menu.lldb` unless it is part of the deliverable

## Step 5 — Write the commit message

Format:
```
[<module>][<submodule>] <concise description>

- bullet describing change 1
- bullet describing change 2
```

Module naming conventions for this project:

| Path prefix | Module tag |
|---|---|
| `RenderDll/XRenderMetal/**` | `[Renderer]` |
| `CryInput/**` | `[CryInput]` |
| `CryGame/**` | `[CryGame]` or `[UI]` |
| `CrySystem/**` | `[CrySystem]` |
| `CrySoundSystem/**` | `[Sound]` |
| `tools/shader_port/**` | `[shader]` |
| `CryFont/**` | `[Font]` |

Submodule tag is optional; use it when the change is scoped to a clear sub-area (e.g., `[Renderer][UI]`, `[CryInput][mouse]`).

## Step 6 — Commit

```bash
git commit -m "$(cat <<'EOF'
[Module][Submodule] Concise description

- bullet 1
- bullet 2
EOF
)"
```

Verify with `git status` that nothing was accidentally left staged or unstaged.
