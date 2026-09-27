<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Arity-laxness repros (v0.61.3)

Minimal probes for row 8 of `docs/COMPILER-FINDINGS.md`: *the compiler does
not validate arity of user function calls*. Calls with fewer arguments than
the declaration compile (missing arguments read as 0) and calls with extra
arguments compile (extras are dropped).

**Status (2026-09-27):** the compiler lane reports arity validation fixed in
its item-3 batch. These probes are the packages-side re-test; run them
against the next installed build and record the result.

Environment: `XIOM Compiler v0.61.3`, `XIOM_STDLIB=E:\xiom-lang\stdlib`.
Run from the repository root (pass `-Stdlib` explicitly; the first bare
token otherwise binds to that parameter):

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\arity-laxness\<file>.xi
```

Baseline re-confirmed on v0.61.3 (2026-09-27): `control_exact_arity` printed
`CONTROL OK 3` (exit 0); `repro_missing_arg` printed `SILENT-ACCEPT 3`
(program exit 10); `repro_extra_arg` printed `SILENT-ACCEPT 3` (program
exit 12).

## Matrix

| File | Call shape | v0.61.3 observed | After the fix (expected) |
|---|---|---|---|
| `repro_missing_arg.xi` | `add3(1, 2)` | compiles; prints `SILENT-ACCEPT 3`; exit 10 | compilation fails with an argument-count diagnostic; no program output |
| `repro_extra_arg.xi` | `add2(1, 2, 99)` | compiles; prints `SILENT-ACCEPT 3`; exit 12 | compilation fails with an argument-count diagnostic; no program output |
| `control_exact_arity.xi` | `add2(1, 2)` | green; prints `CONTROL OK 3`; exit 0 | unchanged: green, exit 0 |

Re-test recipe (after the compiler commit is installed):

1. `& .\scripts\xiom.ps1 --run docs\repro\arity-laxness\control_exact_arity.xi` -> must stay `CONTROL OK 3`, exit 0.
2. `& .\scripts\xiom.ps1 --run docs\repro\arity-laxness\repro_missing_arg.xi` -> must NOT print `SILENT-ACCEPT`; expect a compile error and a non-zero compiler exit.
3. `& .\scripts\xiom.ps1 --run docs\repro\arity-laxness\repro_extra_arg.xi` -> same as step 2.
4. Cross-check the packages tree: every `.xi` in `packages/` was written with manual argument-count review, so no package should newly fail to compile after the strict flip. Re-run `& .\scripts\port.ps1 -Package <name>` on a sample (and the full allowlist batch at the next wrap).
