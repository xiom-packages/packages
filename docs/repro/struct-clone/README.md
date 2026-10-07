<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# `Vec[Struct].clone()` aborts the v0.64.0 codegen -- 2026-10-07 (open)

Found by the `xiom.session` porter during PULSE wave 3 (`session_rotate`
clones an entry list). Isolated here.

- `probe_struct_clone.xi`: `Vec[Pair].clone()` where `Pair = { a: Int; b: Str; }`
  - **v0.64.0: compiles, crashes `0xC0000005` (exit `-1073741819`), no output.**
- `probe_struct_push.xi` (control, same operations without the clone):
  - prints `before` / `len=2` / `second=2:two`, **exit 0** -- the clone is the trigger.

## Run (repo root, pinned toolchain)

```powershell
$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"   # v0.64.0
& $env:XIOM_COMPILER --run docs\repro\struct-clone\probe_struct_clone.xi
# CRASH -1073741819
& $env:XIOM_COMPILER --run docs\repro\struct-clone\probe_struct_push.xi
# before / len=2 / second=2:two / exit 0
```

## Matrix (2026-10-07, installed v0.64.0)

| Variant | Result |
|---|---|
| `Vec[Pair].clone()` | CRASH `-1073741819` |
| identical ops without clone | exit 0 |

## Workaround in packages

Never `.clone()` a Vec of structs on this pin. Copy element-wise
(`xiom.session` `_entries_copy` plus whole-element write-back
`s.sessions[at] = Session{ ... }`) or rebuild through an explicit deep-copy
function. `Vec[Struct]` push/read itself is fine (`docs/repro/vec-struct/`).

Related: COMPILER-FINDINGS 2026-10-02 (aggregate-payload `derive[Clone]`
corruption, `0xC000001D` on v0.62.x) -- same clone family, wider shape now
confirmed on v0.64.0.
