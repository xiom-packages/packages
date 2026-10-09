# xiom.wal 0.1.0 -- specification

Standalone write-ahead log: `xiom.durable`'s record shape plus ORBITDB's
crash-proven disk contract (packages-lane decision 2026-10-08/09). Pure XIOM,
`xiom.std` only. No contracts/clauses in this package (it joins the contract
program later); no externs; no `unsafe`.

## 1. Scope, surface and guarantees

One format = durable's serialized shape + ORBITDB's text segment. Three
intended users: ORBITDB's crash-tested core (disk reference), XVECTOR's
in-memory codec, PULSE's append-only store.

**Public disk API** (agreed names):

| Function | Result |
| --- | --- |
| `wal_open(path)` | `WalFile` (resumes `next_lsn` from the last valid record; heals a torn tail once) |
| `wal_append(&mut, op, key, value)` | `Int` LSN, -1 on write failure |
| `wal_append_tagged(&mut, op, key, value, payload, timestamp)` | `Int` LSN |
| `wal_flush(&mut)` | `Bool` (documented no-op success; see 2.5) |
| `wal_replay(path)` | `Vec[WalRecord]` (torn/malformed lines skipped) |
| `wal_last_lsn(path)` | `Int` (0 when empty/missing) |
| `wal_len(path)` | `Int` (replayed record count) |
| `wal_truncate(path, from_lsn)` | `Bool` (temp + rename; keeps `lsn >= from_lsn`) |
| `wal_close(&mut)` | `Bool` (no-op close seam for the path-handle model) |

**Op helpers:** `wal_op_code(op)`, `wal_op_from_code(code)` (codes 1-10),
`wal_op_is_write(op)`.

**In-memory vocabulary** (kept from `xiom.durable.wal.*`, names unchanged):
`WalLsn` (`wal_lsn`, `wal_lsn_value`, `wal_lsn_next`), `Checkpoint`
(`checkpoint_new`, `checkpoint_can_truncate`), `WalWriter` (`wal_writer_new`,
`wal_writer_append`, `wal_writer_flush`, `wal_writer_current_lsn`,
`wal_writer_synced_lsn`), readers (`wal_read_all`, `wal_read_from`),
`RecoveryResult` (`recovery_scan`), `WalRecord` (`wal_record_new`).

Guarantees:

- LSNs are strictly monotonic; `wal_open` resumes from the log, never reuses.
- Append heals a missing trailing newline first (state-tracked `heal_needed`;
  never an unconditional per-append rescan -- the reference bench measured
  626 ops/s for the O(n) rescan).
- Replay skips malformed and torn trailing lines; no diagnostics from this
  layer (callers compare counts).
- `wal_truncate` rewrites through `path + ".tmp"` + `io.rename`, preserving
  payloads of kept records; a crash mid-rewrite leaves the old segment.
- Single-writer rule is unenforced (no file locks in the toolchain); one
  owner per segment path.

## 2. Pins and format

### 2.1 Extraction pins (2026-10-09)

SHA256 of each extracted source at extraction time:

| Source | SHA256 |
| --- | --- |
| `xiom-durable/src/wal/wal_record.xi` | `e2f9c3cceaceec9937ed0cb79c84cdf10c0bd00a5474debe3cc4113e6b35b66b` |
| `xiom-durable/src/wal/wal_writer.xi` | `02fc3c2c81943200dfd6db519ab256af1d7ce3d5ee504fca801b0198158bb89f` |
| `xiom-durable/src/wal/wal_reader.xi` | `6075226afce98990b8b1619c215ddc5d60068c58fca90cccdeb30707ce69c5cc` |
| `xiom-durable/src/wal/recovery.xi` | `c51e3b35cd981070bb4f3c7166af2afc634152b32b1a0d9da2b7cc4047975bd4` |
| `xiom-durable/src/wal/checkpoint.xi` | `1065ed63fd9ac4877c60ab79b2434e43aed11553c89b5e56d6950da38761f4c1` |
| `xiom-durable/src/wal/lsn.xi` | `07273714d0960857c8d323b3263b4578b560236bd7eed817ae968e200634f096` |
| `xiom-orbitdb/src/wal_file.xi` (disk reference) | `ade8fe06d2cbaf99df805273ddeeb896007a8126022589f36b2ba8da3136e372` |

ORBITDB disk reference contributed by commit
`12405f54f3ced7f5012741766ae5c5d0ff69bedb` (`12405f5`, 2026-10-09
01:09:06 +0300), re-checked read-only with
`git -C E:\xiom-projects\xiom-orbitdb log -1 --format="%h %H %ci" -- src/wal_file.xi`.

### 2.2 Codec v1

One record per line, UTF-8 text, LF-terminated:

```
lsn|op|key|value|timestamp[|p0,p1,...]
```

- Entire line is trimmed before parsing; empty lines and lines with fewer
  than 5 fields are skipped; a field that does not parse as `Int` drops the
  line (record healing, no partial application).
- Payload is a comma-separated `Int` list; absent when empty.
- All write paths use binary-mode file IO (no CRLF translation); `str_trim`
  absorbs any stray CR from foreign segments.
- Replay is line-based and order-preserving; `wal_len`/
  `wal_replay(path).len()` counts well-formed records only.

### 2.3 Op-code table (union)

| Code | Variant | `wal_op_is_write` |
| --- | --- | --- |
| 1 | Insert | true |
| 2 | Update | true |
| 3 | Delete | true |
| 4 | SegmentSeal | false |
| 5 | ManifestUpdate | false |
| 6 | Checkpoint | false |
| 7 | SnapshotMarker | false |
| 8 | BeginTxn | false |
| 9 | CommitTxn | false |
| 10 | AbortTxn | false |

Codes 1-7 are durable's variants, 8-10 ORBITDB's txn kinds; the union means
existing ORBITDB segments replay without a codec change. Unknown codes fall
back to Insert (code 1), matching the reference.

### 2.4 Crash contract

```
write N -> hard kill process tree -> append torn tail "torn|" (no newline)
  -> reopen: replay exactly N (torn skipped)
  -> heal-append: N+1 (missing newline healed first; torn text stays its own
     skipped line and cannot fuse with the new record)
```

Truncate smoke: keep `lsn >= 15` -> replay 7 (on a 21-record crashed-then-healed
segment; generalized in the harness as keep `lsn >= N-5` -> replay 7).

Recorded evidence (v0.64.1, 2026-10-09):

| Check | Command | Result |
| --- | --- | --- |
| conformance x2 | `scripts/port.ps1 -Package xiom-wal -TimeoutSec 90` | PASS passed=21 failed=0 (5.7s), PASS passed=21 failed=0 (6.1s) |
| crash x2 | `powershell -NoProfile -File packages\xiom-wal\tests\crash_test.ps1 -Events 20` | GREEN 6/6 each: observed=20, segment=258 B, replay 20 -> append lsn 21 -> replay 21 -> truncate `>=15` kept 7 |
| soak | same, `-Events 200 -TimeoutSec 120` | GREEN 6/6: observed=200, segment=3,081 B, replay 200 -> append lsn 201 -> replay 201 -> truncate `>=195` kept 7 |

### 2.5 Durability honesty

`wal_flush` is a no-op success: the toolchain has no fsync/
`FlushFileBuffers` wrapper yet (stdlib durable-write/fsync row). "Durable"
today means OS write-back + torn-tail healing, not power-loss durability.
The call site is kept so the swap is one line when the row lands.
`wal_close` is likewise a no-op seam until a persistent-handle IO API exists.

### 2.6 Payload convention

`payload[0]` is the subtype tag (xvector / xiom.db); the remaining elements
are per-subtype. `wal_append_tagged` carries payload + explicit timestamp;
`wal_append` writes an empty payload and timestamp 0.

## 3. Layout

```
packages/xiom-wal/
  package.xi                  manifest (xiom.wal 0.1.0, xiom.std dep)
  src/wal.xi                  single root module `xiom.wal` (487 lines)
  tests/test_conformance.xi   21 checks, [PASS]/[FAIL] per check
  tests/probes/probe_wal_crash.xi  crash probe (write/verify/append1/truncate)
  tests/crash_test.ps1        hard-kill + torn-tail harness (+ truncate smoke)
  SPEC.md README.md ROADMAP.md STATUS.json .gitignore
```

Single root module (the preferred, proven layout) aggregating the vocabulary
plus the disk layer; no sibling modules needed (well under the ~600-line
split threshold). Phase-2 TODOs stay documented in the source; the in-memory
`WalWriter` is deliberately not wired to disk here.

## 4. Provenance and durable reconciliation

Extraction sources and pins are in 2.1. The disk layer's codec/heal/replay/
truncate logic is taken from ORBITDB's landed reference; the probe + harness
are adapted from ORBITDB's acceptance pair. The vocabulary is taken from
`xiom.durable`'s WAL subtree with names unchanged.

Reconciliation (separate, sequenced step -- this package does NOT modify
`xiom.durable`):

1. packages moves durable's `src/wal/*` under `xiom.wal` (types kept as-is);
   this package is that move, and durable's subtree becomes the fold-in
   target to delete there.
2. ORBITDB's disk segment + replay + crash harness land against that shape
   (done; `wal_file.xi` was the drop-in reference).
3. `xiom.durable` keeps `src/txn/*` and consumes `xiom.wal`; nothing in
   durable's WAL names is lost.

See `ROADMAP.md` for the reconciliation row and the fsync row.

## 5. Toolchain notes (v0.64.1)

- `io.read_file_lines` is deliberately not used by `wal_replay`: its
  `ensures: result is Ok => result.len() >= 1` clause mis-fires when the
  parsed part is empty (an empty file read produced a genuine contract panic
  in one in three runs), the same false-contract class as the documented
  `fs_read` trap. Replay reads with `io.read_file` (its clause always holds)
  and splits with `str_split`.
- No contracts/clauses are declared by this package.
- Module-qualified variant returns (`WalOpKind.Insert`, ...) are kept
  (C-ORBIT-04); the explicitly typed local for cross-module payloads
  (C-ORBIT-01) is kept where a `Result` payload is rebound.
- Byte-level bracket scan clean: the five legacy C-style angle-bracket
  generic shapes named in the extraction brief (openers for Vec-of,
  Result-of, Option-of, and both close-bracket forms) all return 0 matches
  across `packages/xiom-wal`.
