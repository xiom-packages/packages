# bindings-pilot -- compiler repro bundle (xiom-packages bindings lane)

Probes produced while building `xiom.sqlite` 0.2.0 on compiler v0.64.0
(Windows). The companion findings ledger is
`docs/BINDINGS-COMPILER-FINDINGS.md`.

General rules for this bundle:

- Each probe is run with the resolved toolchain (`scripts/xiom.ps1 -Info`);
  v0.64.2 runs used `E:\xiom-lang\xiom\target\release\xiom.exe` with
  `$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"` (never set XIOM_RUNTIME_DIR).
  The old `%LOCALAPPDATA%\xiom.new` install slot no longer exists.
- These are build-shaped defects: if a probe is expected to flake, you must
  **rebuild** on every iteration (the defect is not run-to-run).
- `xiom --run` masked the program's exit code on v0.64.0/v0.64.1 (finding
  B-08); **v0.64.2 (m228) fixed it** -- `$LASTEXITCODE` now equals the
  program's code (see `run-exit/`). For pre-fix builds, judge probes by
  their **printed line**. Only compiler-level failures (stack overflow,
  link errors) surface as nonzero.

## enum-payload-nd -- RESPAWNED, runnable

A struct wrapping a user enum with payloads plus match-based accessors; the
pre-fix `xiom.sqlite` value model.

- `probe.xi` -- single-file version of the shape (green in 18/18 builds the
  day it was written; keep as shape documentation).
- `pkg/` -- the actual reproducer: the pre-fix enum model + the real sqlite
  FFI + row materialization. Build+run loop:

```
cd docs/repro/bindings-pilot/enum-payload-nd/pkg
xiom --run tests/probe.xi --c-source <repo>\packages\xiom-sqlite\vendor\sqlite3.c
```

port.ps1 users can instead pass `-Package` with a copy of this pkg under
`packages/`; `port.args.json` resolves the vendored amalgamation relative to
the package directory.

Observed 2026-10-08: 2 of 6 rebuilds printed `B=false` (the enum accessor
path through rows) while `A/C/D` stayed true; in the real pre-fix package the
suite alternated 16/16 and 11/16 PASS across 6 rebuilds. A miscompiled build
is consistently bad for that binary; the next rebuild may be green again.

Re-tested on v0.64.2 (2026-10-09): **6/6 rebuilds all-true**
(`A=true B=true C=true D=true`) -- finding B-01 FIXED (m231).

## up-down-name -- NOT independently reproducible

`pkg/` is the closest reduction of the crashing `xiom.sqlite.migration`
module: associated fns named `up`/`down`, `derive[Clone]` manager,
sort/pending/up/down, a stub `ffi.exec`, a test importing `xiom.test`.

Result on v0.64.0: **green** (`up=1 down=1`). Earlier reductions (a bare
`T.up`; the same without externs) are also green. The original crash
(compiler `thread has overflowed its stack`, exit `-1073741571`) appeared
only inside the full pre-fix package catalog: removing the `up` function
removed the crash; renaming a variant back to `up` reintroduced it
(transcript in `docs/BINDINGS-COMPILER-FINDINGS.md`, B-06). Treat the
reduction as documentation of what was ruled out; the full catalog is needed
to reproduce.

Re-tested on v0.64.2 (2026-10-09): green (`up=1 down=1`) -- B-06 stays fixed.

## alloc-guard-spin -- REPRODUCED, runnable (watchdog required)

`xiom.ffi.alloc` inside a confined block, freed through `xiom.ffi.free`.

```
cd docs/repro/bindings-pilot/alloc-guard-spin
xiom -o tests\ag.exe tests\probe.xi
# run under a memory/time watchdog, e.g. the scratch watch.ps1 pattern:
#   Start-Process tests\ag.exe; kill when WorkingSet > 512 MB or after 10 s
```

Observed 2026-10-08: killed at the 8 s watchdog with 8.1 CPU-seconds burned
and a flat 4.5 MB working set -- a pure spin (the guard heap loops after
libc frees a guard allocation). Never run this probe without a watchdog.

Control shapes that exit 0: the same function with the `ffi.free` call
removed, or with module-local `extern "C" { fn malloc/free }` used as a pair.

Re-tested on v0.64.2 (2026-10-09): **still spins** -- killed at the 10 s
watchdog with 8.7 CPU-s and a flat 4.5 MB working set (B-05 still open,
runtime side).

## win32-gl-unsafe -- REPRODUCED, runnable (fails fast, no watchdog needed)

Staged Win32/WGL context creation inside one confined `unsafe` block
(pre-fix `xiom.opengl` probe shape).

```
cd docs/repro/bindings-pilot/win32-gl-unsafe/pkg
xiom --run tests\probe_q1.xi   # control: green (q1-start | roundtrip_rc=0)
xiom --run tests\probe_q2.xi   # repro:   exit 0xC0000409, no output, every rebuild
```

Observed 2026-10-08: `probe_q2` is deterministic (3/3 rebuilds crash before
any output); `probe_q1` -- window + GetDC + cleanup with the same 12-argument
fn-pointer cast -- is green, which bounds the trigger to the added
pixel-format/WGL stage. Finding B-09.

Re-tested on v0.64.2 (2026-10-09): q1 green (`roundtrip_rc=0`), q2 green
(real GL string `4.6.0 NVIDIA 616.92`) -- B-09 stays fixed.

## run-exit -- FIXED on v0.64.2 (B-08)

A single-file probe whose `main` returns 5; `xiom --run` must surface the
program's exit code.

```
xiom --run docs/repro/bindings-pilot/run-exit/probe.xi
```

Observed on v0.64.0/v0.64.1: program output printed, `exit code: 0` (the
program's code was masked). Observed on v0.64.2 (2026-10-09): prints
`exit code: 5` and the compiler exits 5 (m228); `$LASTEXITCODE` equals the
program's code.
