# Relay: ORBITDB -> packages lane: response (paste-ready)

**From:** ORBITDB lane (`E:\xiom-projects\xiom-orbitdb`). **Re:** xiom.wal
standalone decision + xiom.btree gate + xiom.durable reconciliation.

Thanks -- answers inline, with evidence.

**1. `xiom.btree` gate: MET.** The churn soak you asked for is green:
`tests/probes/probe_btree_churn.xi` runs randomized insert/delete/search
against a flat reference model plus a structural validator (sorted keys,
child-count consistency, min/max key bounds, uniform leaf depth). Green:
orders 4/5/6 x 20,000 ops at keyspace 4096 (~3-4s each), plus a seed matrix
(orders 4/5/6 x seeds 2026/777) and conformance churn regressions in the
suite (**95/95 x2**). The soak caught and we fixed three real defects
(child-node-index contract after merge, leaf borrow placeholder, odd-order
min-keys). Extraction can proceed when you are ready; proposed surface is
the current one -- `btree_new(order)`, `btree_insert/search/delete`,
`btree_range_query`, `btree_min/max/size/to_vec` -- with one documented
invariant: `min_keys = (order-2)/2` for this split scheme (odd orders
included), and the churn probe is the acceptance test. The flat-array
representation (nodes in a `Vec`, integer child indices) exists for the
borrow checker; node indices are append-only today, free-list reuse is
future work.

**2. `xiom.wal` standalone: agreed, and we can be the disk reference.**
ORBITDB's WAL is furthest along on the *disk* side (crash-proven), while
`xiom.durable`'s `src/wal/*` has the richer *vocabulary* (LSNs, full op
kinds, checkpoint, recovery result, txn integration). Proposal: **one
format, durable's shape, our disk contract**:

- Keep `WalOpKind` (Insert/Update/Delete/SegmentSeal/ManifestUpdate/
  Checkpoint/SnapshotMarker) and `WalRecord { lsn, op, key, value,
  payload: Vec[Int], timestamp }` from `xiom.durable.wal.wal_record` --
  its "one shape, tagged payloads, no forked layouts" comment is exactly
  right; adopt it rather than inventing a second record.
- Disk segment layer (from our `probe_wal_file` line format, promoted):
  `wal_open(path)`, `wal_append(w, op, key, value) -> Lsn`,
  `wal_flush(w)`, `wal_replay(w, from_lsn) -> Vec[WalRecord]`,
  `wal_last_lsn(w)`, `wal_len(w)`, `wal_truncate(w, before_lsn)` (the
  checkpoint seam; needs the filed stdlib truncate), `wal_close(w)`.
- Codec v1: text line `lsn|op|key|value|payload|timestamp`; malformed/torn
  tail lines are skipped; **append heals a missing trailing newline first**
  (a torn tail otherwise merges with the next record -- we reproduced
  `applied=3` vs 4 without it); per-record checksum lands when stdlib byte
  IO + fsync do.
- Crash contract (the differentiator): write N -> hard kill -> torn tail ->
  reopen -> replay exactly N -> heal-append -> N+1. Evidence:
  `scripts/crash_test.{ps1,sh}` GREEN x2 on Windows and in WSL, plus a
  200-record soak. `wal_writer_flush`'s `TODO(Phase 2): fsync` is the same
  stdlib row we filed -- one dependency, not two.
- Payload convention for xvector/xiom.db: `payload[0]` = subtype tag, rest
  as documented per subtype, so the record layout stays single.

**3. `xiom.durable` reconciliation:** happy to let xiom.wal be the WAL
home. Suggested order: (a) packages moves `src/wal/*` under `xiom.wal`
(keeps LSN/op-kind/checkpoint/recovery types as-is); (b) ORBITDB lands the
disk segment + replay + crash harness against that shape (our repo can hand
the codec/heal/replay logic and the probe as the acceptance test);
(c) `xiom.durable`'s engine keeps `src/txn/*` and consumes `xiom.wal`.
Nothing in durable's WAL names should be lost -- only `WalWriter.records`
grows a disk segment behind it.

**4. kv watch acknowledged:** C-PULSE-10 Linux-only, fsync row filed --
noted; no change on our side.

**Update (same day):** the reference disk layer is now landed in ORBITDB as
`src/wal_file.xi` -- `WALOpKind` + `WALRecord { lsn, op, key, value,
payload, timestamp }` (durable's shape), `wal_file_open` (resumes LSN from
the log), `wal_file_append` (+ tagged payload variant), `wal_file_flush`
(no-op until fsync), `wal_file_replay`, `wal_file_last_lsn`,
`wal_file_truncate` (checkpoint seam via temp + rename), torn-tail heal.
Acceptance: `tests/probes/probe_wal_file.xi` through
`scripts/crash_test.{ps1,sh}` -- GREEN x2 Windows, GREEN in WSL, 200-record
soak (3,081 B segment), plus a truncate smoke (keep lsn >= 15 -> replay 7).
Conformance suite green. Codec v1 is text (`lsn|op|key|value|timestamp
[|payload_csv]`); per-record checksum waits on stdlib byte IO + fsync.
When packages moves `xiom.durable`'s `src/wal/*` under `xiom.wal`, this
module is the drop-in reference -- take the codec/heal/replay logic and the
probe as the package acceptance test.
