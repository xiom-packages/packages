# xiom.arrow -- Production Roadmap

**Version**: v0.1.0 | **Compiler**: v0.64.5 | **Last updated**: 2026-10-16

## Current Rating: 8/10

| Criterion | Status |
|-----------|--------|
| [OK] Safe wrappers | 27 pub fn (excl. 16 DataType constructors), 36 requires contracts |
| [OK] No workarounds | Pure XIOM idioms |
| [ ] Examples | Pending -- demo.xi with round-trip scenarios |
| [OK] README | Status, two-leg split, probe invocation |
| [OK] SPEC.md | Architecture, API surface, C Data Interface boundary, deviations |
| [OK] ROADMAP.md | This file |
| [OK] Contracts | 36 requires clauses (`xiom --dump-contracts src/arrow.xi`) |
| [OK] Tests | 27 conformance tests, GREEN x2 on v0.64.5 (2026-10-16) |
| [~] C bridge | Phase-1 stub bridge linked + real-lib loader/probe; real libarrow C++ backend pending |
| [ ] Demo stable | Demos blocked on the real FFI bridge |

## Implementation History

| Phase | Status | Description |
|-------|--------|-------------|
| **P1: Types** | [OK] Done | DataType (16 variants), Field, Schema, DataArray, Table |
| **P2: Low-Level FFI** | [OK] Done | ArrowArray/ArrowSchema wrappers, extern "C" stubs |
| **P3: High-Level API** | [OK] Done | array_new, table_new, table_column, ipc_read/write |
| **P4: Contracts** | [OK] Done | 36 requires clauses (handle validity, index bounds, buffer limits) |
| **P5: Tests** | [OK] Done | 27 conformance tests |
| **P6: Documentation** | [OK] Done | SPEC.md, ROADMAP.md, README.md updated 2026-10-16 |
| **P7: FFI Bridge** | [~] Partial | 2026-10-16: stub-safe link bridge (16 symbols), real-lib loader + C Data Interface boundary, SKIP-safe probe; real libarrow C++ backend pending |

## Two-leg split (current state)

| Leg | What runs | Evidence |
|-----|-----------|----------|
| Offline conformance (port.ps1) | 27 tests against the 16 stub-safe `arrow_*` symbols in `bridge/arrow_bridge.c`; backend-unavailable `0` collapses to `Err`; deterministic, no libarrow needed | `port: PASS (passed=27 failed=0 ...)` x2 |
| Real-libarrow probe (manual) | Loader scan + load/unload; CDI layout pin (ArrowSchema 72 / ArrowArray 80) + producer round-trip with release-contract checks | `[SKIP]` on this box (libarrow absent, 8 candidates tried); `[PASS]` with a library present |

## FFI Bridge Gap (Blocking 10/10)

The package is **8/10 functional** -- all pure-XIOM components work and the
Phase-1 bridge is linked; the remaining gap is the real backend:

| Task | Effort |
|------|--------|
| Obtain libarrow (system install or local build; Apache-2.0) | Hour |
| Compile bridge against Arrow C++ headers (light clone protocol in SPEC.md) | Day |
| Replace the 16 stub bodies with ImportArray/ExportArray (same symbols) | Day |
| Verify round-trip: create array -> get buffers -> read data | Day |
| IPC round-trip: write -> read -> compare | Day |

## Known Limitations

- **High-level type is `DataArray`, not `Array`** (XARROW-ARRAYNAME): `Array` is
  a built-in type name on v0.64.5; imported structs with that name codegen as
  zeroed i64. Revisit when the compiler fixes imported-name shadowing.
- **Suite runs with `--no-contracts`** (XARROW-NOCONTRACTS): the 27 checks
  probe out-of-contract error paths on purpose; clauses stay declared and
  compile-checked.
- **Stub backend**: `array_create`/`schema_create`/`record_batch_create` return
  0 (runtime unavailable) by design in Phase 1; `is_linked()` is false until
  the real backend lands.
- **IPC read/write return stubs**: blocked on the real Arrow C++ IPC bridge.
- **No nested types**: List/Struct/Map DataType support deferred to Phase 3.
- **No Linux/macOS CI**: verified on Windows only; the probe covers POSIX
  loader paths by inspection, not execution.
- **Probe loads, not calls**: libarrow exposes no stable C function ABI for
  arrays (the C Data Interface is a struct/data boundary consumed via C++);
  the probe therefore verifies detection/loadability plus the struct-contract
  round-trip, not Arrow C++ calls.

## Next Milestones

| Milestone | Target | Effort |
|-----------|--------|--------|
| v0.2.0 -- real bridge linked | Real array_create/free/get_buffer via Arrow C++ | Week |
| v0.3.0 -- IPC round-trip | Write .arrow file, read back, verify | Week |
| v0.4.0 -- Nested types | List[T], Struct, Map<K,V> support | Weekend |
| v1.0.0 -- Pandas interop | Zero-copy DataFrame <-> Arrow table (C Data Interface) | Month |
