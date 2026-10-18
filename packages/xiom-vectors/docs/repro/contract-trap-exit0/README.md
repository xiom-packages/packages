<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->


Status: **FIXED in v0.64.1** (2026-10-08 re-test): the violation now exits 1.
# XVC-C-02 repro: runtime contract violation exits 0

Compiler: **v0.64.0**. `probe.xi` calls a function whose `requires` clause is
violated and returns a distinguishing value on the same path:

```xiom
fn take_positive(x: Int) -> Int requires: x > 0 { return x; }
fn main() -> Int { return take_positive(-5); }   // would be exit 251 on continuation
```

Observed (both Windows and WSL Linux):

```
$ out\probe.exe
contract violated: requires at 7:13        (stdout)
contract violated: requires at 7:13        (stderr)
$ echo %ERRORLEVEL%
0
```

The process terminates at the contract check and reports **exit 0**. A second
variant returning `take_positive(0)` was identical (`probe.xi` currently holds
the `-5` variant; the `0` variant is one token away).

Impact: CI and probe runners that gate on exit code see green while the
program aborted. XVECTOR's conformance suite hit this in vivo: a negative
test called `engine_create_collection(&mut eng, 0, ...)` (its contract is
`requires: dim >= 1`) and the suite died mid-run at 86/126 with exit 0; the
test was rewritten to exercise the `is_valid_dimension` predicate instead.

Workaround: never pass contract-violating arguments; runners additionally
grep captured stdout for `contract violated`.

Reproduce:

```powershell
. .\scripts\dev-env.ps1
& $env:XIOM_COMPILER -o out\ct.exe docs\repro\contract-trap-exit0\probe.xi
cmd /c "out\ct.exe & echo EXIT=%ERRORLEVEL%"     # EXIT=0 despite the violation
```
