# xiom.wal

Standalone write-ahead log for XIOM: `xiom.durable`'s record vocabulary plus
ORBITDB's crash-proven disk segment. One line per record
(`lsn|op|key|value|timestamp[|payload]`), torn-tail healing before append,
malformed/torn lines skipped on replay, LSN resume on open, and a
temp+rename truncate that preserves payloads. Pure XIOM, standard library
only (`xiom.std`).

## Consumer snippet

```xiom
var w = wal_open("app.wal");                          // resumes LSNs, heals a torn tail
let lsn = wal_append(&mut w, WalOpKind.Insert, 42, 7); // -1 on write failure
let _ = wal_flush(&mut w);                             // no-op until fsync lands
```

## API

| Function | Result |
| --- | --- |
| `wal_open(path)` | `WalFile`; resumes `next_lsn` from the log, heals a torn tail once |
| `wal_append(&mut, op, key, value)` | `Int` LSN, -1 on write failure |
| `wal_append_tagged(&mut, op, key, value, payload, timestamp)` | `Int` LSN (`payload[0]` = subtype tag) |
| `wal_flush(&mut)` | `Bool` -- documented no-op success until the fsync row lands |
| `wal_replay(path)` | `Vec[WalRecord]`; torn/malformed lines are skipped |
| `wal_last_lsn(path)` / `wal_len(path)` | `Int` (0 / empty when missing) |
| `wal_truncate(path, from_lsn)` | `Bool`; keeps records with `lsn >= from_lsn` via temp + rename |
| `wal_close(&mut)` | `Bool`; no-op close seam for the path-handle model |
| `wal_op_code(op)` / `wal_op_from_code(code)` | code 1-10 round-trip (Insert..AbortTxn) |
| `wal_op_is_write(op)` | `Bool` (true for Insert/Update/Delete) |

In-memory vocabulary kept from `xiom.durable` (types + fns unchanged):
`wal_writer_new/append/flush/current_lsn/synced_lsn`, `wal_read_all/read_from`,
`checkpoint_new/can_truncate`, `recovery_scan`, `wal_lsn/_value/_next`,
`wal_record_new`. Wiring the in-memory writer to disk is Phase 2
(`ROADMAP.md`).

## Durability caveat

**Crash-consistent, not durable.** The toolchain has no fsync yet, so
`wal_flush` is an honest no-op: an acknowledged append can be lost on power
failure, but a torn tail is healed before the next append and partial lines
are never replayed. The crash contract (write N -> hard kill -> torn tail ->
replay exactly N -> heal-append -> N+1) is exercised by
`tests/crash_test.ps1` (including the 200-record soak).

## Single-writer rule

One owner per segment path. There are no file locks in the toolchain, so
concurrent writers to the same path are an unenforced contract and can
interleave records.

## Tests

- `tests/test_conformance.xi` -- 21 checks; run with
  `.\scripts\port.ps1 -Package xiom-wal -TimeoutSec 90` (PASS 21/21 x2 on
  v0.64.1, 2026-10-09).
- `tests/crash_test.ps1 -Events 20` -- hard-kill + torn-tail + truncate
  smoke; GREEN 6/6 x2, plus a 200-record soak (segment 3,081 B).
