# xiom.arrow -- Production Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.64.6 | **Last updated**: 2026-10-17

## Current Rating: 9/10

| Criterion | Status |
|-----------|--------|
| [OK] Safe wrappers | 52 pub fn (excl. 16 DataType constructors), 51 requires contracts |
| [OK] No workarounds | Pure XIOM idioms |
| [ ] Examples | Pending -- demo.xi with round-trip scenarios |
| [OK] README | Status, two-leg split, real-backend recipe |
| [OK] SPEC.md | Architecture, API, CDI boundary, pin/ABI gate, ownership handoff |
| [OK] ROADMAP.md | This file |
| [OK] Contracts | 51 requires + 1 ensures (`xiom --dump-contracts src/arrow.xi`) |
| [OK] Tests | 32 conformance tests, GREEN x2 on v0.64.6 (2026-10-17) |
| [OK] C bridge | REAL Arrow C++ 22.0.0 backend (`bridge/arrow_real.cpp`), probe 10/10 |
| [ ] Demo stable | Demo still pending (IPC leg) |

## Implementation History

| Phase | Status | Description |
|-------|--------|-------------|
| **P1: Types** | [OK] Done | DataType (16 variants), Field, Schema, DataArray, Table |
| **P2: Low-Level FFI** | [OK] Done | ArrowArray/ArrowSchema wrappers, extern "C" surface |
| **P3: High-Level API** | [OK] Done | array_new, table_new, table_column, ipc_read/write |
| **P4: Contracts** | [OK] Done | 51 requires clauses (handle validity, index bounds, buffer limits, handoff slots) |
| **P5: Tests** | [OK] Done | 32 offline conformance tests (27 original + 5 Phase-2 stub tests) |
| **P6: Documentation** | [OK] Done | SPEC/ROADMAP/README/PROVENANCE updated 2026-10-17 |
| **P7: Real backend** | [OK] Done | 2026-10-17: `arrow_real.cpp` (C++17, exception-free C ABI) implements all 16 declared symbols; adds struct schemas, typed Int64/Float64 arrays, zero-copy `ExportRecordBatch`/`ImportRecordBatch` pair and exactly-once release helpers. Probe green against Apache Arrow C++ 22.0.0 (pyarrow 22.0.0 wheel). |
| **P8: IPC** | [ ] Pending | `ipc_write`/`ipc_read` remain declared stubs |

## Two-leg split (current state)

| Leg | What runs | Evidence |
|-----|-----------|----------|
| Offline conformance (port.ps1) | 32 tests against the 25 stub-safe `arrow_*` symbols in `bridge/arrow_bridge.c`; backend-unavailable `0` collapses to `Err`; deterministic, no libarrow needed | `port: PASS (passed=32 failed=0 ...)` x2 |
| Real backend probe (manual) | `bridge/arrow_real.cpp` against Apache Arrow C++ 22.0.0: struct schema, typed arrays, record batch, zero-copy export->import (buffer address identity), import-consumed release pointers, exactly-once release path | `tests/probe_real_backend.xi`: 10/10 PASS on v0.64.6 (2026-10-17) |
| Real-lib loader probe (manual) | Legacy loader scan + CDI layout pin + producer round-trip with the stub leg | `[SKIP]` without libarrow; `[PASS]` with a library present |

## Real Backend Status

Done:

| Task | Evidence |
|------|----------|
| Pin + license-check Apache Arrow (tag `apache-arrow-22.0.0`, commit `5aeb5f2`) | `PROVENANCE.md` |
| Acquire matching MSVC headers + import libraries + DLLs (pyarrow 22.0.0 wheel) | wheel SHA256 in SPEC/PROVENANCE |
| Implement the 16 declared symbols with Arrow C++ objects behind Int handles | `bridge/arrow_real.cpp` |
| Real `ArrowArray`/`ArrowSchema` struct semantics (release callbacks, `private_data`) | legacy `arrow_array_create` + `ExportRecordBatch` |
| Zero-copy record-batch export/import pair with documented ownership | probe buffer-address identity check |
| Build + run with the pinned XIOM toolchain (clang 22.1.8, MSVC ABI) | probe output in SPEC |

Remaining:

| Task | Effort |
|------|--------|
| IPC round-trip: write -> read -> compare (needs Arrow IPC, separate symbols) | Day |
| Demo (`demo.xi`) + pandas `dataframe_from_arrow` consumer | Day |
| Nested types (List/Struct/Map) typed builders | Weekend |

## Known Limitations

- **High-level type is `DataArray`, not `Array`** (XARROW-ARRAYNAME): `Array` is
  a built-in type name; imported structs with that name codegen as zeroed i64.
  Revisit when the compiler fixes imported-name shadowing.
- **Suite runs with `--no-contracts`** (XARROW-NOCONTRACTS): the 32 checks
  probe out-of-contract error paths on purpose; clauses stay declared and
  compile-checked.
- **Real backend is probe-only**: `port.args.json` keeps the stub leg so CI
  stays offline; `is_linked()` reports which translation unit is linked.
- **Typed constructors cover Int64/Float64**: other primitive types are
  obtainable from record-batch columns, but building them from raw XIOM
  buffers needs additional additive functions (deferred).
- **IPC read/write return stubs**: no IPC symbols were added in this pass.
- **No nested types**: List/Struct/Map DataType support deferred to Phase 3.
- **Windows-verified**: the ABI gate was run on Windows/MSVC. Linux/macOS need
  the same recipe against the distro/Homebrew Arrow build (`-std=c++17`).

## Next Milestones

| Milestone | Target | Effort |
|-----------|--------|--------|
| v0.1.1 -- real backend recorded | Suite x2 + probe evidence + docs | Day |
| v0.2.0 -- IPC round-trip | Write .arrow file, read back, verify | Week |
| v0.3.0 -- Nested types | List[T], Struct, Map<K,V> typed builders | Weekend |
| v1.0.0 -- Pandas interop | `dataframe_from_arrow(table)` via the export/import pair | Month |
