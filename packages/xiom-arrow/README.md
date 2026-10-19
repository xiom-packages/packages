# xiom.arrow

> **Status:** `incubating` -- offline conformance GREEN (32/32 x2, v0.64.8, 2026-10-19) and the REAL Apache Arrow C++ 22.0.0 backend (`bridge/arrow_real.cpp`) built + probe-green locally (10/10); published in `eco-v0.1.193` (sha256 `62a25672...`, 2026-10-16); `0.1.1` in `eco-v0.1.200` (sha256 `dbf4d41b...`, 2026-10-19).
> **Scope:** Apache Arrow columnar memory format bindings; zero-copy interop via the Arrow C Data Interface.
> **Deps:** stdlib `extern "C"`; Apache Arrow C++ only for the real (probe) leg -- the suite stays offline and deterministic.

## Libs inventory

| Lib | Description |
|-----|-------------|
| `array` | Array data structures |
| `record-batch` | Tabular record batches |
| `schema` | Schema definition |
| `table` | In-memory tables |
| `ipc` | IPC serialization (declared stub, Phase 2b) |
| `flight` | Flight RPC transport (not bound) |

## Current shape (two legs)

| Leg | What | Where |
|-----|------|-------|
| Offline conformance | 25 `arrow_*` symbols (16 declared + 9 additive handoff); `0` = backend unavailable, `-1` = invalid argument; deterministic, no allocation | `bridge/arrow_bridge.c` linked by `port.args.json` |
| REAL backend (probe only) | The same symbols implemented with Apache Arrow C++ 22.0.0: typed Int64/Float64 arrays, struct schemas, record batches, `ExportRecordBatch`/`ImportRecordBatch` zero-copy pair, exactly-once release helpers, real `ArrowArray` structs (release callback + `private_data`) | `bridge/arrow_real.cpp` + `tests/probe_real_backend.xi` |
| Real-lib loader probe (SKIP-safe) | Legacy loader scan + CDI layout pin (ArrowSchema 72 / ArrowArray 80) + producer round-trip | `tests/probe_real_libarrow.xi` (stub leg) |

Run the suite: `.\scripts\port.ps1 -Package xiom.arrow -TimeoutSec 300`
Run the real probe (verified recipe; see SPEC.md for the full env):

```powershell
$arrow = "E:\repos\arrow-bin\pyarrow-22.0.0"
$env:CPLUS_INCLUDE_PATH = "$arrow\pyarrow\include"
$env:PATH = "$arrow\pyarrow;$arrow\pyarrow.libs;$env:PATH"
xiom --run packages\xiom-arrow\tests\probe_real_backend.xi --cxx-standard 17 `
    --c-source packages\xiom-arrow\bridge\arrow_real.cpp `
    --link arrow --link arrow_compute --link arrow_acero `
    --link-path "$arrow\pyarrow"
```

## Notes

- Suite runs with `--no-contracts` (SPEC.md XARROW-NOCONTRACTS): the 32 checks
  probe error paths on purpose; the 51 declared `requires` clauses stay in
  `src/arrow.xi` and are visible via `xiom --dump-contracts`.
- High-level array type is `DataArray` (SPEC.md XARROW-ARRAYNAME: `Array`
  collides with the built-in fixed-size array type).
- Zero-copy ownership is pinned in SPEC.md "Real backend" and "Arrow C Data
  Interface boundary": export hands the struct pair to the consumer, import
  consumes it (release pointers become NULL), otherwise call
  `schema_release`/`array_release` exactly once.
- Arrow >= 24 requires C++20 headers; the pin (22.0.0) is the newest release
  that keeps the required C++17 artifact.
