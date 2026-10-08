# bindings-pilot -- compiler repro bundle (xiom-packages bindings lane)

Probes produced while building `xiom.sqlite` 0.2.0 on compiler v0.64.0
(Windows). The companion findings ledger is
`docs/BINDINGS-COMPILER-FINDINGS.md`.

General rules for this bundle:

- Each probe is run with the pinned compiler:
  `$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"` and
  `$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"` (never set XIOM_RUNTIME_DIR).
- These are build-shaped defects: if a probe is expected to flake, you must
  **rebuild** on every iteration (the defect is not run-to-run).
- `xiom --run` masks the program's exit code on v0.64.0 (see finding B-08),
  so judge probes by their **printed line**, not by `$LASTEXITCODE`. Only
  compiler-level failures (stack overflow, link errors) surface as nonzero.

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
