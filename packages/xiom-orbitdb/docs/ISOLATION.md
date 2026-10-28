# Isolation & Multi-Handle Model

> **Decision record (D3, updated 2026-10-11):** ORBITDB is **single-writer**.
> A handle that has fallen behind another writer refuses its writes; readers
> see the state from their open time. The **M3 minimal subset** (2026-10-11)
> adds in-process stable snapshots (pins + copy-on-write writes) and
> transaction savepoints -- mechanics, limits and evidence: `docs/MVCC.md`.
> Multi-process locks and version GC remain deferred (prerequisites below).
> This file is the reference for the multi-handle rules enforced by
> `db_file_open` plus the stale-handle guard.

## Current model

1. **Single writer.** A database path (`<path>` + `<path>.snap`) must have at
   most one *writing* handle at a time -- in one process or several.
2. **Stale-write refusal (optimistic guard, no lock file).** Every `DBFile`
   records the WAL segment size at its last own write (`wal_bytes`). Each
   write path -- `db_file_put` / `db_file_delete`, all `db_file_txn_*`, and
   `db_file_checkpoint` -- first checks `io.file_size(path) == wal_bytes` and
   refuses (`false` / `-1`) on a mismatch. The first writer wins; the other
   handle must `db_file_open` again before writing. Crash-safe by
   construction: there is no persistent lock that a hard kill could leave
   behind. Read-only use of a stale handle is safe and sees the state from
   its open time; only writes are refused.
3. **Open-time consistency.** `db_file_open` loads the newest committed
   snapshot generation and replays the WAL tail, so a handle's tree is a
   consistent image of the database at open (plus its own later writes).
4. **Transactions (D2).** One active transaction per handle; operations are
   logged as they happen but applied only at commit; a crash before commit
   discards them; a dangling window is finalized with an Abort record on
   open. No cross-transaction isolation is needed while writers are
   serialized. **Savepoints (M3):** a marker inside the active transaction;
   `restore` trims the buffered ops and splices the WAL window
   (Abort + Begin + re-log) so replay agrees with the buffer; commit/abort
   release it. Single level per transaction.
5. **Snapshot pins (M3 minimal subset).** `db_file_snapshot_begin` captures
   `{root, lsn, generation}` (a `DBSnapshot`); while pins exist, every write
   path copy-on-writes the nodes it touches so a pinned view never changes;
   reads through `db_file_snapshot_get/range/count` walk the pinned root.
   Pins are handle-local and in-memory (a reopen starts with none).
   Checkpoint compaction defers while a pin is live (`compaction_deferred`,
   incremental appends continue), and `db_file_min_pinned_lsn` is the hook
   the M1.1b deferred-free list will consume.

## What this is not

- Not cross-process MVCC: pins are per-handle; a reader process still opens
  its own handle (open-time snapshot). No per-key version chains and no
  transaction-id visibility arrays over pages.
- Not a lock: nothing stops a second process from opening the same path; the
  guard only prevents *interleaved writes* from corrupting the segment once
  the sizes diverge. Any external append is detected on the next write.
- No version GC yet: old node versions stay in the arena while their pin is
  live (and are serialized by the next checkpoint); the M1.1b free list
  becomes allocatable only below `db_file_min_pinned_lsn`.

## MVCC (landed parts vs deferred)

Landed 2026-10-11 (M3 minimal subset): in-process snapshot pins with
copy-on-write writes, snapshot reads, savepoints, compaction refusal while
pinned, deferred-free hook. Still deferred:

1. **Multi-process coordination** -- advisory locks need the stdlib
   `file_lock` row (S3 on the critical path).
2. **Pager-backed versioned reads** (C3/M1.1b): lazy node load + a bounded
   cache turn pins into a disk-generation contract; the compaction refusal
   is already the guard that keeps a pinned generation resolvable from the
   file. **Status 2026-10-19:** v2 snapshots are lazily loaded through a
   256-frame clock cache (dirty-frame spill at the uncommitted generation);
   deferred free / version GC remains open (M1.1b A5).
3. **Version GC**: landed in M1.1b A5 (retire points + pin epochs +
   reachability GC compaction; the post-GC store is a fresh `ns_new_paged`).
4. **In-engine threading**: multiple threads sharing one DBFile remains
   deferred; the ST0 decision is the engine-actor model below.

Until the deferred parts land, correctness comes from serializing writers; a
reader that needs a frozen view opens its own handle or pins a snapshot
in-process.

## Cross-process shard ownership (M3, landed 2026-10-20)

- `db_file_open_locked_checked[_cfg]` takes an exclusive **whole-file
  advisory lock** on a dedicated `<path>.lock` sentinel (`xiom.os.lock`,
  stdlib wave 152). One lock per process; a second locked open returns
  `Err(StorageError)`; release with `db_file_unlock(path)` or by exiting the
  process (release-or-die).
- The sentinel is created once and **never deleted while a lock may be
  held**: the lock is attached to the inode, so renaming/deleting the path
  detaches it. The DB/WAL/snapshot files are never locked -- checkpoints
  rename the snapshot.
- Advisory only: a non-cooperating process can still read/write the file;
  the embedded `db_file_open` keeps the optimistic stale-handle guard. The
  Station opens each shard with the locked API (one writer per shard).
- **Cross-process readers/pins are not supported.** A reader that needs a
  frozen view uses a snapshot copy/backup, or lives inside the owning process
  (the Station's engine actor captures pins). This is the M3 contract.
- Evidence: `tests/probes/probe_lock.xi` (parent holds -> child sees HELD;
  release -> child acquires; child acquires and exits -> parent reacquires)
  PASS on Windows + WSL; `tests/suite/dbfile.xi` locked-open test.
## Detectable vs undetectable (tests)

`tests/suite/dbfile.xi` (stale-handle test) + `tests/suite/typed_mvcc.xi` pin the behavior: the stale-handle test (two
handles -> the second's `put`, `delete`, `txn_begin` and `checkpoint` are
refused after the first writes; a fresh open works; the final reopen sees
exactly the surviving keys) and the M3 tests (snapshot isolation, order-3
COW churn vs models, checkpoint stability, savepoint basic/guards/crash
windows, typed pins). `tests/probes/probe_mvcc.xi` (36 checks) and fuzz
section (l) extend the isolation coverage (three interleaved pins, compaction
deferral, savepoint matrix, random op/pin/savepoint/reopen streams vs a
model). Undetectable by design: a read-only stale handle (safe), and two
handles that never interleave writes.

## Threads decision (ST0, recorded 2026-10-19)

**Decision: one engine-actor thread per `DBFile`/shard; a `DBFile` never
crosses threads. Scale-out is process-per-shard, not shared-handle threads.**

- **Runtime evidence:** `xiom.thread.spawn` creates real OS threads and
  `xiom.sync.mutex` serializes across them -- 4 threads x 10,000
  mutex-guarded increments = 40,000 on v0.64.8 Windows + WSL
  (`tests/probes/probe_threads.xi`).
- **Engine facts:** read paths mutate the pager cache (frame loads, clock
  refs, dirty spills); writes mutate the tree/WAL; pins and transaction state
  are handle-local; the stale-handle guard assumes one writer; there is no
  cross-process file lock yet (M3 remainder).
- **Model:** session/network threads accept, parse and frame; they enqueue
  commands to the shard's engine thread, which owns the `DBFile` and executes
  reads/writes/snapshot captures. Responses return through the session. No
  engine handle is shared. This is the SQLite "serialized connection + one
  writer" shape made explicit, with the pager cache owned by the actor.
- **Scale-out:** process-per-shard (each process owns its file) once M3
  `file_lock` + cross-process pins land. Thread-per-connection sharing one
  handle stays deferred until in-engine synchronization and the language's
  Send/Sync enforcement (m363).
- **Consequences:** per-actor memory is predictable (bounded pager cache);
  ST3's mixed reader/writer harness drives the actor; Station reader
  snapshots are captured and read inside the actor.