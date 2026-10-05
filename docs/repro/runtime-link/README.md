<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# AOT runtime link misses the install `lib/runtime` dir -- v0.63.1 (open)

`find_runtime_c_files()` builds its candidate dirs from CWD, walk-up from
the compiler exe, and exe-relative paths, but **none of them is the
production install layout `<install>\lib\runtime`** (`%LOCALAPPDATA%\xiom.new\lib\runtime`).
The list is then empty and the link falls back to `find_runtime_c()` --
the single `xiom_runtime.c`. `async_runtime.c`, `simd_runtime.c`,
`sha256_sw.c` and `xiom_hot_reload.c` are not linked, so any program that
references `xiom_async_now_ms` fails:

```
lld-link: error: undefined symbol: xiom_async_now_ms
>>> referenced by ...:(__unsafe_block_7)
```

## Minimal repro

`probe_async_now.xi` calls `xiom.time.monotonic_ms()` (whose body is the
`xiom_async_now_ms` extern call in `stdlib/xiom/time/time.xi`).

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\runtime-link\probe_async_now.xi
# v0.63.1: link error above (no binary produced)
```

## Workaround (supported env override)

`XIOM_RUNTIME_DIR` is checked first at `lib.rs:2113` and globs every `*.c`
in the given dir:

```powershell
$env:XIOM_RUNTIME_DIR = "E:\xiom-lang\stdlib\runtime"
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\runtime-link\probe_async_now.xi
# now_ms=<n> / bad=0 / exit 0
```

## Matrix (2026-10-05, installed v0.63.1, repo stdlib checkout)

| Condition | Result |
|---|---|
| no override | FAIL, `undefined symbol: xiom_async_now_ms` |
| `XIOM_RUNTIME_DIR=<stdlib>\runtime` | PASS, exit 0 |
| in-situ `xiom.aws` suite (no override) | FAIL `port: FAIL (passed=0 failed=0 program_exit=1 exit=1)` |
| in-situ `xiom.aws` suite (override) | PASS 27/27 |
| stdlib lane probe `tools/probes/p_pin0631_shapes.xi` | FAIL identically on installed v0.63.1 |

## Context

Latent until the v0.63.1 stdlib wave changed `xiom.time.Instant.now()` to
read the runtime monotonic clock; the stdlib test harness
(`xiom/test/harness.xi:116,145,202`, `xiom/test/test.xi:285`) uses
`Instant.now()`, so every harness-using suite pulled the missing symbol.
The JIT builds the full set (`xiom-jit/src/lib.rs:491-497`), which is why
this never surfaced in JIT runs.

Not a packages defect; fixed on the compiler side by adding
`<install>\lib\runtime` to the `find_runtime_c_files()` candidates (or by
setting `XIOM_RUNTIME_DIR` in the install/release tooling).

## RESOLVED on v0.64.0 (2026-10-05)

Official v0.64.0 (tag `c68d91de`, SHA256-verified install) fixes the
discovery: with BOTH `XIOM_RUNTIME_DIR` and `XIOM_STDLIB` unset (true
install-layout discriminator), `probe_async_now.xi` compiles and prints
`now_ms=<n>` / `bad=0`, exit 0. The `XIOM_RUNTIME_DIR` workaround is
retired; the v0.64.0 fleet sweep runs without it.
