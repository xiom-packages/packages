# xiom.arrow

> **Status:** `incubating` -- Phase-1 conformance GREEN (27/27 x2, v0.64.5, 2026-10-16; stub-safe link bridge `bridge/arrow_bridge.c` + SKIP-safe real-libarrow probe `tests/probe_real_libarrow.xi`); Phase-2 real libarrow C++ backend pending; not yet published to the XIOM registry.
> **Scope:** Apache Arrow columnar memory format bindings; zero-copy interop via the Arrow C Data Interface.
> **Deps:** stdlib `extern "C"`; system libarrow only for the real (probe) leg -- the suite stays offline and deterministic.

## Libs inventory

| Lib | Description |
|-----|-------------|
| `array` | Array data structures |
| `record-batch` | Tabular record batches |
| `schema` | Schema definition |
| `table` | In-memory tables |
| `ipc` | IPC serialization |
| `flight` | Flight RPC transport |

## Phase-1 shape (two legs, one bridge file)

| Leg | What | Where |
|-----|------|-------|
| Conformance stubs (offline) | 16 `arrow_*` symbols; `0` = backend unavailable (wrappers return `Err`), `-1` = invalid argument; no allocation | linked by `port.args.json` |
| Real library probe (SKIP-safe) | Loader scans PATH, `XIOM_ARROW_LIB`, `ARROW_HOME`, System32/site-packages/vcpkg (Windows) or `/usr/lib*` etc. (POSIX) for libarrow; plus the pinned C Data Interface boundary (ArrowSchema 72 / ArrowArray 80 bytes, release contract) | `tests/probe_real_libarrow.xi` (not part of `port.ps1`) |

Run the suite: `.\scripts\port.ps1 -Package xiom-arrow -TimeoutSec 180`
Run the probe: `xiom --run packages\xiom-arrow\tests\probe_real_libarrow.xi --c-source packages\xiom-arrow\bridge\arrow_bridge.c`
(`[SKIP]` without libarrow; `[PASS]` when present; exit code = failure count)

## Notes

- Suite runs with `--no-contracts` (see SPEC.md XARROW-NOCONTRACTS): the 27
  checks probe error paths on purpose; the 36 declared `requires` clauses stay
  in `src/arrow.xi` and are visible via `xiom --dump-contracts`.
- High-level array type is `DataArray` (SPEC.md XARROW-ARRAYNAME: `Array`
  collides with the built-in fixed-size array type on v0.64.5).
- Zero-copy boundary documented in SPEC.md "Arrow C Data Interface boundary"
  (struct layout, buffer model, format strings, release semantics) for the
  pandas/pyarrow consumer.
