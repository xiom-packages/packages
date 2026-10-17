<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# C-ORBIT-10 repro: RETRACTED -- `xiom --check` exit codes are correct on Linux (v0.64.5 re-verification)

**Status: NOT A COMPILER DEFECT; finding retracted 2026-10-15.**
**Original report (v0.64.4 wave):** "the Linux build's `--check` exits 0 even
when it reports errors; Windows exits 1." The compiler lane re-investigated
(bus history 2026-10-13, `REL-20261012-1358-orbitdb`): the documented Linux
artifact exits rc=1 in 20+ invocation variants; rc=0 reproduces ONLY with
the sibling `xiom-dbg` DAP-adapter binary, which ignores `--check` and exits
0 (sha256 `8060704c...`; "xiom-dbg: GDB/MI backend" banner).
**Likely root cause on our side:** the WSL side of the original matrix
executed the wrong binary (a harness resolution problem, not a build
difference).

## v0.64.5 re-verification (2026-10-15, official artifacts)

Windows shadow `xiom.new.0645` (`xiom.exe` sha256 `02f0857887e14e48...`);
WSL canonical `~/.local/share/xiom/bin/xiom` (sha256 `c4aa877a8a4c219f...`
== `xiom-0.64.5-linux-x64.tar.gz` `bin/xiom`).

```
Windows: xiom.exe --check docs\repro\check-exit-code\probe_type.xi    -> rc 1
         xiom.exe --check docs\repro\check-exit-code\probe_syntax.xi  -> rc 1
WSL:     xiom --check docs/repro/check-exit-code/probe_type.xi        -> rc 1
         xiom --check docs/repro/check-exit-code/probe_syntax.xi      -> rc 1
         ~/.local/share/xiom/bin/xiom-dbg --check probe_type.xi       -> rc 0  (the artifact!)
```

Both platforms agree: `rc 1` on reported errors, matching the documented
gate semantics. No Linux/Windows divergence exists in these artifacts.

## Lesson (applied)

- The lane harnesses now resolve the compiler explicitly (`dev-env.ps1`
  pins the Windows shadow path; `dev-env.sh` falls back to
  `$HOME/.local/bin/xiom`, and both report the resolving path/version).
- Gate on BOTH the exit code and the output text (`compilation failed` /
  `error[`) where cheap; assert the compiler identity in automation that
  must be authoritative (`xiom --version` / sha256).
- `xiom-dbg` is the DAP debug adapter (GDB/MI backend), NOT a compiler
  variant: it accepts unknown flags like `--check` and exits 0. Never point
  CI/gates at it.

## Files

- `probe_type.xi` -- a T001 type error (`undefined_symbol_repro`).
- `probe_syntax.xi` -- a P001 syntax error (missing `;` / closing structure).

These stay as regression probes for the exit-code contract.
