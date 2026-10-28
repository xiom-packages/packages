<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# M3 minimal subset: snapshot pins + savepoints (design note, 2026-10-11)

> **LANDED 2026-10-11** (engine `ed901cb`): pins, COW writes, deferred
> compaction, savepoints and the evidence ladder below all shipped. Suite
> 159/159 x2 Win + WSL, `probe_mvcc.xi` 36 checks GREEN x2 both, fuzz
> section (l) OK x2 both, db_crash 25/25 x2 both. One implementation note
> grew out of it: nested Vec storage is SHARED by struct assignment and
> element assignment writes through the shared buffer (compiler finding
> **C-ORBIT-09**, bundle `docs/repro/vec-copy-alias/`), so `cow_shadow`
> builds shadows through `node_deep_copy`, which rebuilds every vector.
>
> **Scope.** The first actionable slice of M3 ("Concurrency / MVCC",
> `docs/PRODUCTION-PLAN.md` sec. 6). In-process stable snapshots via
> **pinned generations + copy-on-write writes**, and a **savepoint** slice on
> the durable transaction buffer. The single-writer model of `docs/ISOLATION.md`
> stays the base: no multi-process locks (blocked on the stdlib `file_lock`
> row), no threads (the platform has none today), no per-page version chains,
> no version GC (the free list itself is M1.1b).

## 1. Why not redb's mechanism verbatim

The reference study (`docs/REFERENCE-STUDY.md` sec. 2) maps redb's snapshot
model onto us: "snapshot = COW root `{root, checksum, length}` captured under
the header lock and registered by transaction id; readers never lock the
writer" and "savepoint = pinned read txn + saved user root; restore = root
swap + free everything allocated since". Those mechanisms assume **pages are
immutable and writes path-copy into fresh pages** (`redb btree_base.rs:115-128,
savepoint.rs:29-54,111-127; transactions.rs:1400-1495,1437-1468`).

Our engine mutates the fully-resident node arena **in place**, and our durable
transactions **buffer until commit** (D2, `docs/ISOLATION.md`). So we ADAPT:

| Redb mechanism | ORBITDB M3 minimal subset |
|---|---|
| Snapshot = COW root + pinned txn id | **Pin** = `{id, root, lsn, generation}` over our arena; readers read the pinned root |
| Writers path-copy (their tree is always COW) | Writes path-copy **only while a pin exists** (`cow_shadow`); the no-pin fast path stays in-place |
| Freelist deferred below oldest reader txid | Old versions stay in the append-only arena; **deferred-free hook** = `db_file_min_pinned_lsn` for the M1.1b free list |
| Compaction refuses while a pin exists | `snap_flush`/`snap_flush_v2` **defer the compaction branch** while pinned (counter `compaction_deferred`); incremental appends continue |
| Savepoint = pinned root, restore = root swap | Savepoints are **txn-scoped buffer markers**; restore trims `txn_ops` and splices the WAL window (Abort + Begin + re-log) — crash-consistent by the existing window classification |

bbolt's model corroborates the COW rule (`internal/freelist/shared.go:56-87`;
meta swap as the only commit point): while a reader can see an old root, the
writer must never mutate a node that old root can reach. We get the same
guarantee by construction (below) without a freelist.

No on-disk format changes: pins and births are **handle-memory** state. The
snapshot file, WAL records and node codecs are untouched; a reopen simply
starts with zero pins (a dropped pin is not observable after reopen).

## 2. Snapshot pinning

### 2.1 Capture

`db_file_snapshot_begin(db) -> DBSnapshot{id, root, lsn, generation}`

- `root` — the live arena root at capture (the current tree, as applied).
- `lsn` — the highest WAL LSN at capture (diagnostic version stamp; records
  from an *open* transaction are in the WAL but **not** in the pinned view —
  pins are read-committed).
- `generation` — the last committed snapshot generation (`0` = none), tracked
  per handle (`snap_generation`, set on open and after every checkpoint).
- `id` — monotone `pin_clock` value; `db_file_snapshot_end(db, id)` releases.

Pins live in `NodeStore.pins` (handle-local). Reads:
`db_file_snapshot_get/_typed/_range/_count(db, id, ...)` walk `pin.root` with
the existing read-only walkers — the same node code the live tree uses.

### 2.2 The COW rule (the load-bearing part)

Every pushed node carries a **birth epoch** (`births[i]`), and `pin_clock`
increments on every pin creation. Invariants:

1. A node reachable from a pin created at clock `k` has `birth <= k` (it
   existed at capture). A node with `birth > pin_clock` **cannot** be in any
   live pin's view.
2. `ns_push` stamps `birth = pin_clock + 1` — fresh nodes are mutable in place
   until a **newer** pin makes them protected.
3. `cow_shadow(tree, idx)`: identity when no pins exist or
   `births[idx] > pin_clock`; otherwise copy the node to a fresh slot (birth =
   `pin_clock + 1`) and return the copy. **The copy is a `node_deep_copy`:**
   plain struct assignment shares the nested `Vec` storage, and element
   assignment through the "copy" writes through to the source buffer
   (C-ORBIT-09), which would corrupt the pinned original. Callers must store
   the result in the (already fresh) parent's child pointer, or in
   `tree.root`.

All write paths route through this discipline — the exact sites:

- `btree_insert_payload`: shadow the root (a full root goes to `split_root`,
  which only *reads* the old root and pushes fresh halves, so it needs no
  copy); `insert_nonfull` re-reads and shadows the child before descending;
  `split_child` shadows the child before mutating it.
- `btree_delete`: shadow the root after the existence check;
  `delete_from_node` shadows the child on the descent path; `fill_child`
  (pass-through), `merge_children` (left child), `borrow_from_left/right`
  (child + sibling) shadow before touching; `remove_from_internal` shadows the
  donor after reading the predecessor/successor (reads see identical content).
- Every `ns_set` target is therefore either pushed or shadowed **in the same
  operation**. Protected nodes are never written; pinned views are frozen.

Cost model: O(path length) extra pushes per write while pinned; O(1) check on
the fast path. Old versions accumulate in the arena until the pin is released
(no GC yet — see sec. 5).

### 2.3 Compaction refusal

While `pins.len() > 0`, `db_file_checkpoint` still runs (incremental appends +
anchor + WAL truncation — pins read the arena, not the file), but the
compaction branch is deferred: `compaction_deferred` increments and the page
log keeps growing instead of being rewritten. Once the last pin is released,
the next checkpoint compacts normally. The v1-handle-on-v2-file path (a full
batch rewrite) defers by refusing that checkpoint (`-1` + counter) while
pinned. Rationale: a future lazy/paged reader resolves its generation **from
the file**; compaction must not drop generations a live pin could still need
(`docs/BYTE-PAGE-FORMAT-V2.md`, M1.1b).

## 3. Savepoints (txn-scoped)

Semantics (SQL `SAVEPOINT` / redb): a marker inside the **active transaction**;
`restore` discards everything after it and keeps the marker; `release` drops
it; commit/abort release it implicitly. Single level per transaction
(nesting = follow-on).

Mechanism for our buffered txns:

1. `db_file_txn_savepoint` records `sp_marker = txn_ops.len()`.
2. `db_file_txn_savepoint_restore` trims `txn_ops` to the marker, then
   **splices the WAL window**: append `AbortTxn` (closes the current window —
   replay discards it), append `BeginTxn` (fresh window), re-log the kept ops
   verbatim. Replay then reconstructs exactly the trimmed buffer; a crash at
   any point lands in the existing classification: an unterminated window is
   dropped, a committed one applies precisely the kept ops.
3. `db_file_txn_savepoint_release` clears the marker.

Why not a root swap: our transaction never applies ops to the tree before
commit, so there is nothing to "undo" in the tree; the buffer **is** the
uncommitted state. The splice keeps the durable artifact (WAL) and the
in-memory buffer in agreement — the property the crash harness checks.

## 4. Evidence ladder (what proves it)

- Suite (`tests/suite/typed_mvcc.xi`): pin isolation + reads; COW under
  order-3 churn vs a model captured at pin time; nested pins; pin across
  checkpoint/reopen; savepoint trim/restore/release + guards; savepoint crash
  windows via reopen; snap-generation bookkeeping.
- Probe `tests/probes/probe_mvcc.xi`: seeded randomized churn under multiple
  interleaved pins vs per-pin models; forced compaction deferral (page-log
  entry counting) + post-release compaction; savepoint splice matrix across
  reopen; guard matrix; typed pins.
- Fuzz `probe_fuzz.xi` section (l): random op/pin/savepoint/reopen streams vs
  an independent model (keys/values copied at pin time; live tree + every
  live pin verified after every op).
- Regression at every wrap: suite x2 Win + WSL, db_crash five scenarios x2
  (the splice rides the same window classification), fuzz OK x2.

**Landed results (2026-10-11):** suite 159/159 x2 Win + WSL (7 new tests);
`probe_mvcc.xi` 36 checks GREEN x2 both (three pins over 600 ops + two
checkpoints; compaction deferral forced with 81 checkpoints + post-release
shrink; savepoint matrix C1-C5; typed pins); fuzz section (l) OK x2 both;
db_crash 25/25 x2 both.

## 5. Limits (documented, not hidden)

- Pins are **handle-local and in-memory**: a different process/handle has its
  own pins; cross-process snapshot reads wait for M1.1b lazy load + stdlib
  locks (M3 proper).
- No version GC: arena grows while pins are held and long pin lifetimes grow
  the file at the next checkpoint (all nodes are serialized). Pending-free
  deferral is prepared via `db_file_min_pinned_lsn`.
- One writer per handle (unchanged); "concurrent" today means interleaved
  API use in one process, which is exactly what the pins make safe.
- `lsn` on a pin during an open txn is the last appended LSN (diagnostic);
  the pinned *data* is the read-committed tree.
