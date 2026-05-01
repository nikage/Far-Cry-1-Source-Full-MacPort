---
name: lldb-batch
description: Use lldb --batch mode for automated, non-interactive debugging of native C/C++/ObjC code. Use whenever diagnosing crashes, inspecting state at breakpoints, running post-mortem analysis, or automating any debug session that does not require live user interaction with the debugger.
disable-model-invocation: true
---

# lldb --batch Debugging

Prefer `lldb --batch` over interactive lldb for all automated and agent-driven debug tasks. Batch mode exits after all commands execute and produces output that can be captured and analyzed without human input.

## When to use --batch

- Diagnosing a crash or assertion failure
- Inspecting variable / register state at a known breakpoint
- Automating a debug workflow in a script or agent session
- Reproducing a bug and collecting evidence in one shot
- Analyzing a core dump

Use interactive lldb only when the user needs to explore an unknown state in real time.

## Command pattern

```bash
xcrun lldb --batch \
  -o "<lldb-command-1>" \
  -o "<lldb-command-2>" \
  -- <executable> [args]
```

Or via a script file:

```bash
xcrun lldb --batch -s <script.lldb> -- <executable> [args]
```

`--batch` exits automatically; all output goes to stdout/stderr and can be piped or captured.

## FarCry binary path

```
./FarCry.app/Contents/MacOS/FarCry
```

Always prefix with `xcrun` on macOS to pick up the SDK-bundled lldb.

## Common recipes

### Catch an assertion / crash and print backtrace

```bash
xcrun lldb --batch \
  -o "run" \
  -o "bt" \
  -o "frame info" \
  -- ./FarCry.app/Contents/MacOS/FarCry
```

### Break at a function, print locals, continue

```bash
xcrun lldb --batch \
  -o "breakpoint set --name 'CMetalRenderer::BeginFrame'" \
  -o "run" \
  -o "frame variable" \
  -o "continue" \
  -- ./FarCry.app/Contents/MacOS/FarCry
```

### Analyze a core dump

```bash
xcrun lldb --batch \
  -o "bt all" \
  -o "frame variable" \
  ./FarCry.app/Contents/MacOS/FarCry -c <core-file>
```

### Conditional breakpoint with expression

```bash
xcrun lldb --batch \
  -o "breakpoint set --name 'CMetalUtilityRenderer::Draw2dImage' --condition 'm_solidColorPipelineState == nullptr'" \
  -o "run" \
  -o "frame variable" \
  -o "expr -- (void)printf(\"encoder=%p\\n\", m_renderEncoder)" \
  -- ./FarCry.app/Contents/MacOS/FarCry
```

## Script file format (.lldb)

Prefer a `.lldb` script file when there are more than three commands — easier to review and version-control:

```lldb
# my_debug.lldb
breakpoint set --name "CUISystem::Draw"
breakpoint set --name "CMetalUtilityRenderer::CreateSpritePipelineState"
run
bt
frame variable
continue
```

Run it:

```bash
xcrun lldb --batch -s my_debug.lldb -- ./FarCry.app/Contents/MacOS/FarCry
```

Existing project script: `debug_menu.lldb` (menu rendering diagnostics).

## Useful lldb commands in batch context

| Command | Purpose |
|---|---|
| `run` | Start the process |
| `continue` | Resume after a breakpoint |
| `bt` | Backtrace of current thread |
| `bt all` | Backtrace of all threads |
| `frame variable` | All local variables in current frame |
| `frame variable <name>` | Single variable |
| `expr -- <expr>` | Evaluate an expression |
| `register read` | CPU registers |
| `memory read <addr>` | Raw memory |
| `disassemble --frame` | Disassembly at current frame |
| `breakpoint set --name <sym>` | Symbol breakpoint |
| `breakpoint set --file <f> --line <n>` | Source breakpoint |
| `watchpoint set variable <var>` | Watchpoint |
| `target modules list` | Loaded shared libraries |
| `image lookup --address <addr>` | Symbol at address |

## Capturing output

```bash
xcrun lldb --batch -s debug_menu.lldb -- ./FarCry.app/Contents/MacOS/FarCry 2>&1 | tee debug_output.txt
```

Always redirect stderr (`2>&1`) — lldb writes some output to stderr.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | All commands executed; process exited normally |
| `non-zero` | Process crashed or an lldb command failed |

Use the exit code in scripts to detect crashes automatically.
