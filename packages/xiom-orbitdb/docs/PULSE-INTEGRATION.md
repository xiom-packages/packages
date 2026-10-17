<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# ORBITDB -> PULSE: consumer integration handshake

> Response to `xiom-pulse/docs/ORBITDB-RELAY-PULSE.md`. Kept current every
> wrap; PULSE re-reads it. ORBITDB is a consumer lane too -- read-only from
> PULSE's tree, never edited.

## 1. Embedding API surface today

**Import path (source today, package later).** There is no registry package
yet (`xiom.db` publish is M6 in `docs/PRODUCTION-PLAN.md`). Consume the
checked-out source: the compiled engine module is `xiom.db.engine`
(`src/engine.xi`), with `xiom.db.wal_file`, `xiom.db.storage.page`,
`xiom.db.storage.page_file`, `xiom.db.storage.tuple` as supporting modules.
A consumer compilation unit needs those source roots visible to the
compiler (the same `use xiom.db.engine;` our own suite uses). The planned
package key is `xiom.db`; version TBD at P-alpha.

Durable facade (`DBFile`) -- the recommended target for PULSE:

```xi
use xiom.db.engine;

// open (validated variant returns Err on bad path/order)
let opened = db_file_open_checked("pulse-data/events.wal", 4);
// ...or plain: var db = db_file_open("pulse-data/events.wal", 4);
var db = db_file_open("pulse-data/events.wal", 4);
if !db_file_put(&mut db, 101, 7) { /* WAL append failed */ }
if !db_file_delete(&mut db, 3) { /* absent or failed */ }
let value = db_file_get(&db, 101);
```

```xi
// ordered range + value-filter query (in-order values)
let window = db_file_range(&db, 100, 200);
var q = query_new();
query_where(&mut q, QueryOp.Gte, 10);   // conditions filter VALUES
query_offset(&mut q, 0);
query_limit(&mut q, 50);
let filtered = db_file_query(&db, &q);
```

```xi
// transactions: log-then-buffer, apply at commit, discard on abort
if !db_file_txn_begin(&mut db) { /* busy */ }
let _ = db_file_txn_put(&mut db, 500, 42);
let _ = db_file_txn_delete(&mut db, 101);
if !db_file_txn_commit(&mut db) { /* failed; buffer retained */ }
// durable boundary: db_file_checkpoint(&mut db) -> anchor LSN
```

In-memory facade (`db_open`/`db_insert`/`db_get`/`db_range`/`db_query`)
exists for tests/embedded state, but PULSE's store seam should use `DBFile`:
it is the crash-tested path (harnesses + 2000-key soak, x2 both platforms).

## 2. Build + link contract

| Item | Status |
|---|---|
| Dependency key/version | `xiom.db` planned; **not published yet** -- consume the source tree now |
| C ABI / `extern` layer | **none today** (pure XIOM); bindings are M6 in the production plan |
| linux-x64 | **supported** -- full lane x2 on WSL Ubuntu (`/mnt/e` and native `/tmp`); all crash harnesses green |
| windows-x64 | **supported** -- full lane x2 on Windows; all crash harnesses green |
| macos-x64 / macos-arm64 | **not tested** -- no runner here; per your note macOS is upstream-blocked for everyone |

Compiler/toolchain the lane is proven on: v0.64.2 (min v0.64.2 -- earlier
versions need the retired C-ORBIT workarounds; see
`docs/COMPILER-FINDINGS-ORBITDB.md`).

## 3. Pin + stability

- **Pin to consume:** the latest wrap commit of this repo. As of this file:
  `ef872b0` (v0.64.2; all compiler workarounds dropped). Any commit on
  `main` after a wrap commit is work-in-progress.
- **Guaranteed today:** put/get/delete on `DBFile`; ordered ranges and
  value-filter queries; checkpoint/reopen; single-active transactions with
  committed/uncommitted classification; torn-tail healing; CRC32C pages;
  process-kill (hard kill) recovery. On-disk formats v1 are documented and
  versioned (`docs/FORMATS.md`).
- **Experimental / may change before 0.3:** all API signatures (pre-1.0);
  the query planner; value types (int only today); memory behavior (tree is
  fully resident); multi-process access (optimistic single-writer guard, no
  OS locks yet); everything about MVCC (not started).
- **On-disk layout:** `<path>` = WAL segment; `<path>.snap` = snapshot page
  log (append-only generations). Backup = copy both files while writes are
  quiescent (stop the writer, or checkpoint then copy; the pair is the
  unit). Restore = put both files back before opening. Never truncate the
  WAL to empty (LSN continuity lives in the anchor record).

## 4. Consumer-affecting findings and lifecycle

| Kind | Note |
|---|---|
| **Crash guarantee** | `kill -9` (process kill) is covered: committed writes survive, torn tails heal, uncommitted txn windows are discarded and finalized with an Abort record. **Power loss is not yet covered** -- no fsync (stdlib row is a stub); treat as OS write-back. Do not promise PULSE's crash guarantee beyond process kill until we wire it. |
| **Threads/global state** | No globals. One `DBFile` handle owns its state; PULSE single-threaded is a perfect fit. No cross-handle coordination beyond the stale-write guard. |
| **Memory under sustained writes** | Tree + snapshot diff are fully resident; heap grows with the key count (no eviction yet -- M1.2). Bounded-memory soak is a P-alpha gate, not met today. |
| **Open findings (ours)** | Format/API limits rather than bugs: int-only keys/values; no secondary indexes (full scan queries); no fsync; single-writer. Compiler caveat that consumers can hit: module-qualify enum variants when a same-named enum is anywhere in the program (m225 consumer scope; see findings doc). |
| **Known-good baseline** | Suite 120/120 x2, WAL/page/DB crash harnesses x2, fuzz + soak: `docs/SESSION.md` state section. |

## 5. Conformance test proposal (acceptance gate for `probe_pkg_orbitdb`)

1. **Roundtrip + reopen:** open -> put N=1k keys -> verify every key ->
   checkpoint -> reopen -> verify; repeat x2.
2. **Hard-kill recovery:** writer puts keys, hard-kill mid-writes, append a
   torn tail, reopen -> prefix verified -> put more -> reopen -> N+1.
3. **Transaction classification:** (a) begin -> put -> commit -> kill ->
   verify committed keys present; (b) begin -> put -> kill (no commit) ->
   verify keys absent and the DB accepts writes after reopen.
4. **Query edges:** range on empty/absent bounds; value filter with
   offset/limit past the end; min/max; all-queries deterministic order.
5. **Error paths:** empty/CR/LF path rejected; order < 3 rejected; a second
   handle's writes refused after the first writes; stale checkpoint refused.
6. **Sustained load (size follow-up):** 10k keys with checkpoint cadence,
   reopen time + query correctness; extend to 100k once M1.2 lands.

Expected evidence: exit 0 on both platforms; the probe is the gate.

## 6. Cross-project asks (ORBITDB -> PULSE)

1. Confirm the driver mapping: `open` -> `db_file_open_checked`; `exec` ->
   `db_file_put`/`db_file_delete` (auto-commit) or the `db_file_txn_*`
   block; `query` -> `db_file_range` / `db_file_query`; `tx` -> begin/commit/
   abort. Tell us where your shape diverges; we adapt.
2. Does the JSONL-event-store replacement need **ordered full scans or
   cursors**? We have `btree_to_vec`-style materialization today; a cursor
   API is on the plan. Your answer sets its priority.
3. Do events carry **text/float values**? Types v2 (M5) is gated on real
   demand; a one-line "yes, we need strings + timestamps" moves it up.
4. Confirm the durability bar for the store seam: process-kill only today;
   we will ping when fsync lands (then power-loss recovery becomes a gate).
5. Send the probe scenario list divergence + your fleet harness contract;
   we will treat your probe as our acceptance test and fix reds with
   minimal repros through the relay.

Cross-lane: the same handshake has been written for the XVECTOR lane
(`docs/XVECTOR-INTEGRATION.md`; relay archived) so the
hybrid retrieval example (rows in ORBITDB, embeddings in XVECTOR) can be
stand up alongside your 0.3 drivers.
