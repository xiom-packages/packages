# v0.62.2 regressions -- repro bundle (packages lane -> compiler lane)

Two open v0.62.2 issues reported by the packages lane. Both are reproducible
with the files here and/or the published artifacts.

Toolchain used for every observation: `COMPILER_VERSION` = v0.62.2
(repo release deployed to `%LOCALAPPDATA%\xiom.new\bin`), stdlib checkout
`E:\xiom-lang\stdlib` (`stdlib-perf1` +3 docs commits), Windows x64.

---

## 1. `Vec[Str]` push mis-lowers when the Vec is a module-level global

**Minimal repro:** `vec_str_push_global.xi` (in this directory).

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\v0622-regressions\vec_str_push_global.xi
# -> error: clang failed with exit code 1
```

Observed on v0.62.2:

```
error: clang failed with exit code 1
  stderr: xiominput.ll:4652:3: error: '%tmp1035' defined with type 'ptr' but expected 'i8'
   4652 |   store i8 %tmp1035, i8* %tmp1034
```

The emitted IR around the bad store (from the compiler's own `a.exe.ll`):

```
%tmp1029 = load i8*, i8** %tmp1003
%tmp1030 = load i64, i64* %tmp1005
%tmp1032 = getelementptr i8, i8* %tmp1029, i64 %tmp1030
%tmp1033 = alloca i8*
store i8* %tmp1032, i8** %tmp1033
%tmp1034 = load i8*, i8** %tmp1033          ; element address (ptr)
%tmp1035 = load i8*, i8** %tmp1007          ; the Str value (ptr)
store i8 %tmp1035, i8* %tmp1034             ; BUG: must be `store i8*`
```

Element stride is 8 (the grow path does `mul ... 8`); only the store's value
type is wrong (`i8` instead of `i8*`).

**Findings so far:**
- A **local** `Vec[Str]` (declared inside `main`) pushing the same literals
  compiles and runs correctly -- so the global/module-level Vec is the
  differentiator, not the push itself.
- `vec_str_push_param.xi` is the shape `xiom.consensus` originally used
  (module-level Vec + `Str` parameter push under a Bool guard) -- same failure.
- The package workaround was a single `Str` + parallel `Vec[Int]` line-start
  offsets (documented in `xiom.consensus` SPEC sections 7/11).

---

## 2. `xiom.expat` / `xiom.nbt` silent exit `-1` (first in the compiler queue)

**Repro = the published suites.** The registry artifacts contain the full
source including tests (verified by downloading and listing):

```
https://registry.xiom-lang.org/packages/xiom.expat/0.1.1/download   # 139,297 bytes
https://registry.xiom-lang.org/packages/xiom.nbt/0.1.1/download
```

Also available locally in this repo:

```
packages/xiom-expat/tests/test_conformance.xi   (25 checks)
packages/xiom-nbt/tests/test_conformance.xi     (26 checks)
```

**Run (from the package directory or with the suite path):**

```powershell
& .\scripts\port.ps1 -Package xiom.expat -TimeoutSec 60   # or xiom.nbt
```

Observed on v0.62.2: `compiled: a.exe`, then the program exits `-1` with
**no stdout at all** (not even the suite banner); direct `a.exe` execution
reproduces. Both packages were green on v0.62.1 (README-refresh batch
records: expat 25/25, nbt 26/26).

**Flushed variant experiment (strongest clue):**
- Copy the suite and insert `io.flush_stdout();` after every `io.println`.
- `xiom.expat` flushed variant: prints normally, **25/25 PASS, exit 0**.
- `xiom.nbt` flushed variant: prints, **25/26** -- `t5`
  ("strings: u16 length prefix, UTF-8 bytes, UTF-8 names") is a genuine
  `[FAIL]`; the other 25 pass.
- So the silent `-1` looks like an exit/flush-path issue (buffered stdout
  never flushed and the process reports `-1`), independent of the nbt `t5`
  assertion failure (which may or may not share a root cause).

Additional artifacts on this machine: `%TEMP%\kilo\sweep-v0622\*.log`
(original sweep runs), `%TEMP%\kilo\sweep-v0622-rerun\*.log` (serial reruns),
`%TEMP%\kilo\expat-inst.log` / `%TEMP%\kilo\nbt-inst2.log` (flushed variants).
