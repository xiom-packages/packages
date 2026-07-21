# xiom-arrow — Production Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.49.7 | **Last updated**: 2026-07-21

## Current Rating: 7/10

| Criterion | Status |
|-----------|--------|
| ✅ Safe wrappers | 27 pub fn, 32 requires contracts |
| ✅ No workarounds | Pure XIOM idioms |
| ⬜ Examples | Pending — demo.xi with round-trip scenarios |
| ⬜ README | Pending — build instructions, API reference |
| ✅ SPEC.md | Architecture, API surface, bundling strategy |
| ✅ ROADMAP.md | This file |
| ✅ Contracts | 32 requires clauses across all functions |
| ✅ Tests | 27 conformance tests (types, fields, schema, array, batch, table, IPC) |
| ⬜ C bridge | **FFI stubs** — Arrow C bridge not yet linked |
| ⬜ Demo stable | Demos blocked on FFI bridge |

## Implementation History

| Phase | Status | Description |
|-------|--------|-------------|
| **P1: Types** | ✅ Done | DataType (16 variants), Field, Schema, Array, Table |
| **P2: Low-Level FFI** | ✅ Done | ArrowArray/ArrowSchema wrappers, extern "C" stubs |
| **P3: High-Level API** | ✅ Done | array_new, table_new, table_column, ipc_read/write |
| **P4: Contracts** | ✅ Done | 32 requires clauses (handle validity, index bounds, buffer limits) |
| **P5: Tests** | ✅ Done | 27 conformance tests |
| **P6: Documentation** | ⬜ Partial | SPEC.md updated, ROADMAP.md created, README.md pending |
| **P7: FFI Bridge** | ⬜ Pending | Arrow C Data Interface native integration |

## FFI Bridge Gap (Blocking 10/10)

The package is **7/10 functional** — all pure-XIOM components work correctly.
The FFI bridge needs:

| Task | Effort |
|------|--------|
| Install libarrow-dev (`apt install libarrow-dev` or vcpkg) | Hour |
| Write C bridge (arrow_array_create, arrow_schema_create, etc.) | Day |
| Link bridge .obj to xiom-arrow package | Day |
| Verify round-trip: create array → get buffers → read data | Day |
| IPC round-trip: write → read → compare | Day |

## Known Limitations

- **No derive[Clone] on Array/Table**: Manual clone helpers not yet implemented
- **IPC read/write return stubs**: Blocked on Arrow C++ IPC bridge
- **No nested types**: List/Struct/Map DataType support deferred to Phase 3
- **No Linux/macOS CI**: Verified on Windows only

## Next Milestones

| Milestone | Target | Effort |
|-----------|--------|--------|
| v0.2.0 — C bridge linked | Working array_create/free/get_buffer | Week |
| v0.3.0 — IPC round-trip | Write .arrow file, read back, verify | Week |
| v0.4.0 — Nested types | List[T], Struct, Map<K,V> support | Weekend |
| v1.0.0 — Pandas interop | Zero-copy DataFrame ↔ Arrow table | Month |
