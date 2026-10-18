<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->


Status: **FIXED in v0.64.1** (2026-10-08 re-test): both probe.xi and probe_deref.xi compile and run exit 0.
# XVC-C-01 repro: `&fn() -> T` parameter call miscompile

Compiler: **v0.64.0** (Windows `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`; WSL
Ubuntu `~/.local/bin/xiom`). Expected: exit 0.

| File | Shape | Observed |
|---|---|---|
| `probe.xi` | `fn call_ref(f: &fn() -> Int) -> Int { return f(); }` | compile fails: `clang failed with exit code 1`; IR `%tmp6 = inttoptr i64* %tmp5 to i64 ()*` (`invalid cast opcode for cast from 'ptr' to 'ptr'`). The real method is never callable. |
| `probe_deref.xi` | same via `(*f)()` | compiles; **runtime access violation** (Windows exit `-1073741819`); IR calls `i64 (i64)*` with the raw param as an argument -- wrong signature for `fn() -> Int`. |
| `probe_local.xi` | copy `*f` into a local `fn() -> Int`, call the local | compiles; same runtime crash. |

Control (packages-lane `generic-fnptr`, xvector run): `repro_struct_fnfield.xi`
-- fn pointer stored in a **struct field**, called `(op.f)(&3)` -- **exit 0**.
So the defect is the reference-parameter call path, not fn pointers per se.

Consequences in xvector: the conformance suite's 126-pointer dispatcher
(`fn run_one_test(fn_ptr: &fn() -> TestResult)`) could not compile; the suite
was rewritten to evaluate each test at the call site
(`run_one_test(test_fn())`).

Reproduce:

```powershell
. .\scripts\dev-env.ps1
& $env:XIOM_COMPILER -o out\probe.exe docs\repro\xv-fnptr-call-inttoptr\probe.xi        # clang exit 1
& $env:XIOM_COMPILER -o out\probe.exe docs\repro\xv-fnptr-call-inttoptr\probe_deref.xi  # exit 0; run -> -1073741819
```
