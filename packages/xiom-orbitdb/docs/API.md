# ORBITDB Public API Reference

> **Status:** current for the committed tree (compiler v0.64.7; all C-ORBIT
> compiler workarounds reverted except the documented C-ORBIT-12 position
> tuple). Signatures are
> the `pub` surface of the compiled modules; `requires:` contracts are noted
> where they gate behavior. Error semantics: functions returning `DbResult[T]`
> (`Result[T, DbError]`) never panic; `Option[Int]` means absence, and
> `Bool`/`Int` returns encode success/failure (`-1` is the sentinel for
> "rejected" on `Int`-returning checkpoint calls).

Module map (compiled units): `xiom.db.engine` (the facade: `DBFile` + the
file-backed public API, re-exporting the implementation modules below),
`xiom.db.engine.core` (in-memory WAL/Query/planner, legacy `Engine`,
shared DBFile helpers), `xiom.db.engine.snapshot` (v1/v2 checkpoint codec,
compaction, snapshot pins), `xiom.db.engine.txn` (durable transaction window
+ savepoints), `xiom.db.index.btree` (B-tree, NodeStore, COW pins, v2 pager cache), `xiom.db.index.node_page` (node page codec),
`xiom.db.wal_file` (durable WAL
segment), `xiom.db.storage.page` (page, checksum, buffer pool, storage
engine), `xiom.db.storage.page_file` (durable page file + page log),
`xiom.db.storage.block` (byte-page v2 codec, pure),
`xiom.db.storage.byte_io` (byte-IO shim seam), `xiom.db.storage.block_store`
(byte-page v2 block store), `xiom.db.secondary_index` (value-ordered
secondary index, M4.2),
`xiom.db.storage.tuple` (row codec, result set), `xiom.db.storage.free_space_map`,
`xiom.db.error`, `xiom.db.config`, `xiom.db.ids`, `xiom.db.contracts`,
`xiom.db.catalog.schema`, `xiom.db.catalog.schema_validator`,
`xiom.db.txn.transaction`.

---

## Durable file-backed database -- `DBFile` (`xiom.db.engine`)

`DBFile` is the durable facade: WAL-before-ack writes, snapshot + tail
recovery, incremental checkpoints, and single-active transactions. File
layout: `<path>` = WAL segment, `<path>.snap` = snapshot page log.

| Call | Returns | Semantics |
|------|---------|-----------|
| `db_file_open(path, order)` | `DBFile` | Open/create; load newest committed snapshot generation, replay WAL records with `lsn > checkpoint_lsn`, heal torn tails. Caller-validated input (see below for the checked variant). |
| `db_file_open_cfg(path, order, page_format)` | `DBFile` | Same, with the snapshot container for WRITES: `1` = v1 text page log (default), `2` = v2 byte blocks (M1.2). Reads always auto-detect the on-disk format; a v1 file is migrated on the next v2 checkpoint. |
| `db_file_migrate_snapshot(path)` | `Bool` | Migrate an existing v1 snapshot to v2 in place (idempotent; absent/already-v2 is a trivial success). |
| `db_path_valid(path)` | `Bool` | Non-empty, `<= 4096` chars, no CR/LF (the codecs are line-oriented). |
| `db_file_open_checked(path, order)` | `Result[DBFile, DbError]` | Validated open; `Err(ConstraintViolation)` on an invalid path or `order < 3`, else `Ok` from `db_file_open`. |
| `db_file_close(db)` | `Unit` | Release the held append fd (the handle stays usable; the next write reopens lazily). Call before deleting/renaming the DB file from the same process. |
| `db_file_open_checked_cfg(path, order, page_format)` | `Result[DBFile, DbError]` | Validated open with an explicit snapshot container (`1`/`2`); reads still auto-detect. |
| `db_file_open_locked_checked(path, order)` / `db_file_open_locked_checked_cfg(path, order, page_format)` | `Result[DBFile, DbError]` | **M3 shard open:** takes an exclusive whole-file advisory lock on `<path>.lock` (one holder per process; `Err(StorageError)` when held), then the checked open. Release with `db_file_unlock(path)` or process exit. |
| `db_file_unlock(path)` / `db_file_is_locked(path)` | `Bool` | Release / query this process's shard lock. |
| `db_file_create_index(db, name)` | `Bool` | Build a handle-scoped secondary index over VALUES (M4.2): (value, pk) sorted entries; false for empty/duplicate names. Rebuild after open (not yet durable). |
| `db_file_create_index_from_def(db, def)` | `Bool` | Catalog tie-in: accepts an `IndexDef` with `column == 0` (the value column) and `unique == false`. |
| `db_file_drop_index(db, name)` | `Bool` | Drop the named index. |
| `db_file_index_count(db)` / `db_file_index_name(db, at)` | `Int` / `Str` | Index directory (`""` for an out-of-range slot). |
| `db_file_index_range(db, name, lo, hi)` | `Vec[Int]` | Primary keys whose values fall in [lo, hi], in (value, pk) order. |
| `db_file_put(db, key, value)` | `Bool` | Upsert; appends WAL first, then mutates the tree. `false` on WAL failure or while a transaction is active. |
| `db_file_delete(db, key)` | `Bool` | Delete; `false` when the key is absent, on WAL failure, or while a transaction is active. |
| `db_file_get(db, key)` | `Option[Int]` | Point lookup. |
| `db_file_put_typed(db, key, payload)` | `Bool` | M5.3 typed-row upsert: opaque row BYTES (0..255; e.g. a tuple-v2 row from `schema_row_encode`); WAL record carries subtype 1 + the bytes, `value` mirrors the key. Refused above `db_file_typed_payload_max(db.order)`, while a transaction is active, on a latched/stale handle, or for non-byte elements. Non-transactional in S3. |
| `db_file_get_typed(db, key)` | `Option[Vec[Int]]` | The stored payload; `None` when the key is absent or the entry is a plain int row (read those with `db_file_get`). |
| `db_file_typed_payload_max(order)` | `Int` | Payload budget so a full node page fits both snapshot containers (1978 bytes at order 3, 1308 at order 4, 973 at order 5). |
| `db_file_range(db, low, high)` | `Vec[Int]` | Values for keys in `[low, high]` inclusive, in key order (`requires: low <= high`). |
| `db_file_range_pairs(db, low, high)` | `Vec[(Int, Int)]` | `(key, value)` pairs in `[low, high]` inclusive, key order (`requires: low <= high`). Admin/Station range views. |
| `db_file_query(db, query)` | `Vec[Int]` | Value-filter query; same semantics as `db_query` / `query_execute` (conditions filter VALUES). |
| `db_file_size(db)` | `Int` | Number of keys. |
| `db_file_last_lsn(db)` | `Int` | Highest WAL LSN assigned (0 = empty). |
| `db_file_checkpoint(db)` | `Int` | Commit a checkpoint; returns the anchor LSN, or `-1` (snapshot failure, or a transaction is active). |
| `db_file_set_durability(db, mode)` / `db_file_durability(db)` | `Bool` / `Int` | 0 = normal (ack without a flush; sync at checkpoint only), 1 = immediate (REAL fsync at every commit ack; default, M1.2 S4). |
| `db_file_set_two_phase(db, on)` / `db_file_two_phase(db)` | `Bool` | Immediate-only: flush the WAL before a checkpoint publishes its snapshot header (redb-style 2PC). |
| `db_file_failed(db)` | `Bool` | Handle latched after a failed flush/commit; writers refuse until the handle is reopened. |
| `db_file_flush(db)` | `Bool` | Explicit flush of the WAL path; latches on failure. |
| `db_file_maybe_checkpoint(db, limit)` | `Int` | Checkpoint when `limit` records accumulated (`requires: limit >= 1`); anchor LSN or `-1`. |
| `db_file_txn_active(db)` | `Bool` | Transaction open? |
| `db_file_txn_begin(db)` | `Bool` | Start a transaction (`false` if one is active). |
| `db_file_txn_put(db, key, value)` | `Bool` | Buffered upsert inside the transaction. |
| `db_file_txn_delete(db, key)` | `Bool` | Buffered (idempotent) delete inside the transaction. |
| `db_file_txn_commit(db)` | `Bool` | Append `CommitTxn`, then apply the buffered ops to the tree. |
| `db_file_txn_abort(db)` | `Bool` | Append `AbortTxn`; discard the buffer. |
| `db_file_txn_savepoint(db)` | `Bool` | M3: record a rollback marker at the current buffer length (single level; requires an active transaction). |
| `db_file_txn_savepoint_restore(db)` | `Bool` | Roll back to the savepoint: trim the buffer and splice the WAL window (Abort + Begin + re-log of the kept ops). The savepoint stays active (SQL `ROLLBACK TO SAVEPOINT`). |
| `db_file_txn_savepoint_release(db)` | `Bool` | Drop the marker (commit/abort release it implicitly too). |
| `db_file_txn_savepoint_active(db)` | `Bool` | Marker present? |
| `db_file_snapshot_begin(db)` | `DBSnapshot` | M3: pin the current committed state as a stable read view `{id, root, lsn, generation}`. While pins exist, writes copy-on-write the nodes they touch, so the pinned view never changes. Handle-local; read-committed (buffered txn ops invisible). |
| `db_file_snapshot_end(db, id)` | `Bool` | Release a pin (`false` for an unknown id). |
| `db_file_snapshot_get(db, id, key)` / `db_file_snapshot_get_typed(db, id, key)` | `Option[...]` | Point read on the pinned view (`None` outside a live pin). |
| `db_file_snapshot_range(db, id, low, high)` | `Vec[Int]` | Range read on the pinned view, key order (empty for an unknown pin or `low > high`). |
| `db_file_snapshot_count(db, id)` | `Int` | Key count on the pinned view (`-1` outside a live pin). |
| `db_file_snapshot_pins(db)` | `Int` | Live pin count. |
| `db_file_min_pinned_lsn(db)` | `Int` | Oldest pinned WAL LSN (`-1` = none); the deferred-free hook for the M1.1b pager. |
| `db_file_snap_generation(db)` | `Int` | Last committed snapshot generation (0 = none, set on open and after every checkpoint). |
| `db_file_compaction_deferrals(db)` | `Int` | Checkpoints that would have compacted but deferred because a pin was live (incremental appends continue; docs/MVCC.md). |

Transaction limits: single active transaction per handle, no isolation/MVCC
(readers see committed state), no auto-retry. Checkpoint and auto-commit
writes are rejected mid-transaction. See `wal-and-recovery.md` for the crash
ordering and `FORMATS.md` for the record layout.

Snapshot pins (M3 minimal subset): `db_file_snapshot_begin` freezes the
current committed state; writes continue (copy-on-write of the touched node
paths) and the pinned view stays exact until `db_file_snapshot_end`. Pins are
handle-local and in-memory (a reopen starts with none), there is no version
GC yet (old versions accumulate until the pin releases), and checkpoint
compaction defers while any pin is live. Savepoints are transaction-scoped.
Full model + limits: `docs/MVCC.md`.

Multi-handle safety: every write path (`db_file_put`/`delete`, all
`db_file_txn_*`, `db_file_checkpoint`) is refused when the WAL segment changed
since this handle's last own write (stale-handle guard, `wal_bytes`) --
reopen to continue as the writer. `false` / `-1` signals the refusal. See
`docs/ISOLATION.md` for the single-writer model.

## B-tree index (`xiom.db.engine`)

`BTree = { root, order, nodes }` -- a flat node array; `BTreeNode = { keys,
values, children, is_leaf }`. Order must be `>= 3` (`valid_btree_order`).

| Call | Returns | Semantics |
|------|---------|-----------|
| `btree_new(order)` | `BTree` | Empty tree with a single leaf. |
| `btree_insert(tree, key, value)` | `Bool` | `true` iff the key was absent (upsert is caller's job). |
| `btree_delete(tree, key)` | `Bool` | `true` iff the key was present. |
| `btree_search(tree, key)` | `Option[Int]` | Point lookup. |
| `btree_range_query(tree, low, high)` | `Vec[Int]` | Values in key order (`requires: low <= high`). |
| `btree_min(tree)` / `btree_max(tree)` | `Option[Int]` | **Value** at the smallest/largest key (`None` when empty). |
| `btree_size(tree)` / `btree_to_vec(tree)` | `Int` / `Vec[Int]` | Key count / all values in key order. |

## In-memory engine and database (`xiom.db.engine`)

`Engine` = B-tree + in-memory WAL. `Database` = `Engine` + config + open flag;
the `Database` facade is separate from `DBFile` (durable) today.

| Area | Calls |
|------|-------|
| Engine | `engine_new(order)`; `engine_insert` / `engine_update` / `engine_delete` / `engine_get` / `engine_query` / `engine_range_query` / `engine_size` / `engine_wal_size`; `engine_recover()` (replay in-memory WAL); `engine_flush_wal()` (drop WAL after data is durable in RAM); `engine_truncate_wal(before_timestamp)`. |
| Database | `db_open(order)` / `db_open_with(config)`; `db_insert` / `db_update` / `db_delete` / `db_get` / `db_range` / `db_query` / `db_size` / `db_recover` / `db_close`; closed handles reject reads and writes. |
| In-memory WAL | `wal_new()` / `wal_append(entry)` / `wal_replay(tree)` / `wal_clear()` / `wal_truncate(before_timestamp)` / `wal_len()` / `wal_is_empty()` / `wal_entry_count(op_filter)`; `wal_entry_new(op, key, value, timestamp)`; `WALOpType` = `InsertOp` / `UpdateOp` / `DeleteOp`. |

## Query builder (`xiom.db.engine`)

`Query = { conditions, limit, offset }`; `QueryOp` = `Eq` / `Neq` / `Lt` /
`Lte` / `Gt` / `Gte`.

| Call | Semantics |
|------|-----------|
| `query_new()` | Empty query (no conditions, no limit/offset). |
| `query_where(q, op, value)` | Add an AND-ed condition on **values**. |
| `query_limit(q, limit)` | Truncate results (`requires: limit > 0`). |
| `query_offset(q, offset)` | Skip matches (`requires: offset >= 0`). |
| `query_order(q, order)` | Result order (M4.2): 0 = key ascending (default), 1 = value ascending, 2 = value descending; ties keep key order, ordering runs before offset/limit (`requires: order in 0..2`). |
| `query_execute(q, tree)` | Evaluate against a `BTree`: in-order scan, filter, order, offset, limit. |
| `query_condition_count` / `query_has_limit` / `query_has_offset` / `query_order_kind` / `query_reset` | Introspection/reset. |
| `query_plan_full_scan()` / `plan_query(q, tree)` / `plan_query_with_index(q, tree, has_index)` / `execute_plan(plan, q, tree)` | Planner: key bounds pick PointLookup/IndexRange (M4.1); with an index and a usable value condition (not Neq) it picks IndexValue over the condition-derived [low, high] (M4.2); key bounds keep precedence; otherwise full scan. |

## Durable WAL segment (`xiom.db.wal_file`)

`WALFile = { path, next_lsn, heal_needed }`; `WALRecord = { lsn, op, key,
value, payload, timestamp }`; `WALOpKind` codes 1..10 (see `FORMATS.md`).

| Call | Returns | Semantics |
|------|---------|-----------|
| `wal_file_open(path)` | `WALFile` | Create/open; resume `next_lsn` from the last valid record; heal a torn tail once. |
| `wal_file_append(w, op, key, value)` / `wal_file_append_tagged(w, op, key, value, payload, timestamp)` | `Int` | Append; new LSN or `-1`. |
| `wal_file_flush(w)` | `Bool` | Real fsync of the segment (sync_io.sync_fd; M1.2 S4). |
| `wal_file_replay(path)` | `Vec[WALRecord]` | Every well-formed record in file order; malformed/torn lines skipped. |
| `wal_file_len(path)` / `wal_file_last_lsn(path)` | `Int` | Record count / last valid LSN. |
| `wal_file_truncate(path, from_lsn)` | `Bool` | Keep records with `lsn >= from_lsn` (atomic rewrite; payloads preserved). |
| `wal_file_heal_tail(path)` | `Bool` | Terminate a torn trailing line. |
| `wal_file_next_lsn(w)` | `Int` | Next LSN to assign. |
| `wal_op_code` / `wal_op_from_code` / `wal_op_is_write` | `Int` / `WALOpKind` / `Bool` | Codec helpers (unknown codes map to `Insert` on decode). |

## Pages, checksum, buffer pool, storage engine (`xiom.db.storage.page`)

| Call | Returns | Semantics |
|------|---------|-----------|
| `Page.new(id, data, checksum)` | `Page` | `requires: data.len() <= 4096`. |
| `Page.is_valid()` | `Bool` | Stored checksum equals fresh CRC32C of `data`. |
| `page_compute_checksum(data)` | `Int` | CRC32C (Castagnoli); empty -> 0; KAT `0xE3069283` for `"123456789"`. |
| `BufferPool.new(capacity)` | `BufferPool` | `requires: capacity >= 1`. |
| `BufferPool.put(pool, page)` | `Bool` | Upsert; clock eviction; `false` when every frame is pinned (`rejects++`). |
| `BufferPool.get(pool, page_id)` | `Option[Page]` | Hit: `hits++` + reference bit; miss: `misses++`. |
| `BufferPool.pin_page` / `unpin_page` | `Bool` | Pinned frames are never evicted; `pin_count` reads the count. |
| `BufferPool.hit_ratio(pool)` | `Float64` | `hits / (hits + misses)` (0.0 when empty). |
| `StorageEngine.new(config)` | `StorageEngine` | Config + pool. |
| `StorageEngine.cache_page(eng, page)` | `Bool` | Cache (false when all pinned). |
| `StorageEngine.lookup_page(eng, page_id)` | `Option[Page]` | Lookup updating ref bits/stats. |

Statistics fields: `hits`, `misses`, `evictions`, `rejects`.

## Durable page file + page log (`xiom.db.storage.page_file`)

`PageFile = { path }`. Line format and versioning: `FORMATS.md`.

| Call | Returns | Semantics |
|------|---------|-----------|
| `page_file_open(path)` | `PageFile` | Handle. |
| `page_file_read(pf, id)` / `page_file_read_all(pf)` | `Option[Page]` / `Vec[Page]` | Valid pages by id / all valid pages in file order. |
| `page_file_write(pf, page)` | `Bool` | Upsert one page; unlisted pages survive; atomic rewrite. |
| `page_file_write_batch(pf, pages)` | `Bool` | Replace the whole page set; atomic rename. |
| `page_file_ids(pf)` / `page_file_count(pf)` | `Vec[Int]` / `Int` | Valid page ids / count. |
| `page_file_sync(pf)` | `Bool` | Real fsync of the page file (M1.2 S4). |
| `page_log_append(pf, page)` | `Bool` | Append one page version (O(1)). |
| `page_log_read_all(pf)` | `Vec[Page]` | Latest version per id (last valid occurrence wins). |
| `page_log_len(pf)` | `Int` | Raw well-formed entry count. |
| `page_log_heal_tail(pf)` | `Bool` | Terminate a torn trailing line. |

## Block codec v2 (`xiom.db.storage.block`)

Pure codec for the 4096-byte block format (M1.2 S1; design
`BYTE-PAGE-FORMAT-V2.md`). Byte convention: `Vec[Int]` with elements 0..255
(the value rule; the byte-IO shim converts at the file boundary). No IO.

| Call | Returns | Semantics |
|------|---------|-----------|
| `block_size()` / `block_payload_capacity()` | `Int` | 4096 / 4056. |
| `block_encode_page(generation, page_id, payload)` | `Vec[Int]` | One page block; EMPTY vector for invalid input (element outside 0..255, payload over capacity). |
| `block_decode_page(bytes)` | `Option[BlockPage]` | Strict: 4096 bytes, magic/version/kind, reserved zero, length range, CRC32C, zero padding. |
| `block_encode_header(h)` / `block_decode_header(bytes)` | `Vec[Int]` / `Option[BlockHeader]` | Header slot (64-byte payload); decode cross-checks `committed_generation` vs the block stamp and `page_id == 0`. |
| `block_decode(bytes)` | `Option[BlockView]` | Any kind (`'H'` / `'P'` / `'F'`). |
| `block_kind_is_free(bytes)` | `Bool` | `'F'` fast path for the store scan (no CRC). |

## Byte-IO shim (`xiom.db.storage.byte_io`)

The seam between the storage layer and `io.*`. **Swapped to the real stdlib
byte primitives in M1.2 S4 (2026-10-13; stdlib waves 115/118):** no O(file)
fallbacks remain. Byte convention `Vec[Int]` elements 0..255 (converted to
`Vec[UInt8]` only inside this module). Until the next compiler pin re-vendors
stdlib/runtime, run with `XIOM_RUNTIME_DIR=<stdlib>/runtime` (scripts/dev-env.*
sets it).

| Call | Returns | Semantics |
|------|---------|-----------|
| `byteio_read_at(path, offset, len)` | `Option[Vec[Int]]` | `io.read_at`; None on IO error or short read. |
| `byteio_write_at(path, offset, data)` | `Bool` | `io.write_at`; creates the file, zero-fills past EOF. |
| `byteio_append(path, data)` | `Bool` | `io.append_file_bytes` (binary append). |
| `byteio_file_size(path)` | `Int` | `io.file_size`; 0 when the file is missing. |
| `byteio_truncate(path, len)` | `Bool` | `io.truncate_file` (cut, or zero-extend). |
| `byteio_sync(path)` | `Bool` | REAL fsync (`sync_io.sync_fd`); skip-with-success when the file is missing; fault-gated (`syncfail` latches the engine handle). |
| `byteio_sync_dir(path)` | `Bool` | `sync_io.fsync_dir` of the path's parent (rename durability; ungated). |

## Block store v2 (`xiom.db.storage.block_store`)

Append-only 4096-byte block store with two generation-stamped header slots
(design `BYTE-PAGE-FORMAT-V2.md`): page appends are invisible until a header
commit covers their generation; the latest generation per page_id wins; the
first commit mirrors both slots, later commits alternate. `BlockStore`
fields (`ids` / `blocks` / `gens` directory, `header`, `active_slot`,
`committed`, `block_count`) are public.

| Call | Returns | Semantics |
|------|---------|-----------|
| `block_store_open(path)` | `BlockStore` | Rebuild the committed view (header-slot pick + block scan). |
| `block_store_put(bs, generation, page_id, payload)` | `Int` | Append one page version; block index or -1. Own writes visible in-process. |
| `block_store_commit(bs, header)` | `Bool` | Commit at `header.committed_generation`; non-increasing generations rejected. |
| `block_store_read(bs, page_id)` | `Option[BlockPage]` | Current version for the id. |
| `block_store_has` / `block_store_count` / `block_store_pages` / `block_store_blocks` | `Bool` / `Int` / `Vec[Int]` / `Int` | Directory queries + file block count. |
| `block_store_compact(bs, generation)` | `Bool` | One block per live page at a new generation, temp+rename. |
| `block_store_sync(bs)` | `Bool` | REAL fsync of the store file (M1.2 S4). |

## Tuples (`xiom.db.storage.tuple`)

| Call | Returns | Semantics |
|------|---------|-----------|
| `Row.new(id, data)` / `Row.get_column(row, i)` / `Row.set_column(row, i, v)` / `Row.column_count(row)` | `Row` / `Option[Int]` / `Bool` / `Int` | Flat i64 row. |
| `tuple_encode_checked(row)` | `DbResult[Vec[Int]]` | Codec v1 bytes; `Err(ConstraintViolation)` above 255 fields. |
| `tuple_encode(row)` | `Vec[Int]` | Convenience; empty buffer when not encodable. |
| `tuple_decode(buf)` | `DbResult[Row]` | Strict: magic/version/count/length/type bytes; `Err(Corruption)` on any violation. |
| `tuple_encoded_len(row)` / `tuple_fits_page(row, page_size)` | `Int` / `Bool` | Size helpers. |
| `tuple_push_int_le(out, v)` / `tuple_read_int_le(buf, at)` | -- / `Int` | Shared LE i64 helpers (also used by the snapshot node codec). |
| `TValue` (`VNull`/`VInt`/`VFloat`/`VText`/`VBlob`) | enum | M5 typed-value model; construct as `TValue.VInt(5)` etc., inspect via the accessors below (consumers should not pattern-match: m225/C-ORBIT-07 hygiene). |
| `tuple2_encode_row_checked(id, values)` | `DbResult[Vec[Int]]` | Codec v2 row; `Err(ConstraintViolation)` above 255 fields / u32 lengths / non-byte blob elements. |
| `tuple2_decode_row(buf)` | `DbResult[TypedRow]` | Strict v2 decode (whole-buffer byte check, exact length, `VInt` id field); rejects v1 bytes. |
| `tuple2_read_value(buf, at)` | `DbResult[TValue]` | One tagged value; consumed length is `tuple2_value_len(v)`. The position-tuple shape `(TValue, Int)` stays retired: with an enum error type both are enums and v0.64.5 still miscompiles (C-ORBIT-12; bundle `docs/repro/enum-tuple-codegen/repro_enum_tuple_enum_error.xi`). |
| `tuple2_value_len(v)` / `tuple2_encoded_len(values)` / `tuple2_fits_page(values, page_size)` | `Int` / `Int` / `Bool` | Size helpers (page budget gate). |
| `tuple2_kind` / `tuple2_is_null` / `tuple2_int_value` / `tuple2_float_value` / `tuple2_text_value` / `tuple2_blob_value` | `Int` / `Bool` / `Option[...]` | Accessors (kind tag + per-kind extraction). |
| `tuple2_compare(a, b)` | `Int` | Total order for typed predicates: Null < numeric (Int/Float compared numerically; `VInt(1)` equals `VFloat(1.0)`) < Text (bytewise) < Blob (element-wise); NaN sorts first and equals itself. `0` is equality. |
| `typed_query_new` / `typed_query_where(q, col, op, literal)` / `typed_query_limit` / `typed_query_offset` | `TypedQuery` | Builder (conditions ANDed; `op` is `QueryOp.Eq`..`Gte`; `literal` is a `TValue`). |
| `db_file_query_typed(db, q)` | `Vec[Int]` | Matching primary keys in key order. Conditions are ANDed and use `tuple2_compare` semantics (no SQL 3-valued logic); `col` indexes the decoded row values, `col = -1` is the row id; plain int rows and undecodable payloads never match; offset/limit apply to the matches. |
| `ResultSet.new(columns)` / `add_row` / `row_count` / `column_count` / `get_row` | -- | In-memory result materialization. |

## Schema rows (`xiom.db.catalog.schema` + `xiom.db.catalog.schema_row`)

| Function | Returns | Notes |
|----------|---------|-------|
| `ColumnDef.new(name, col_type)` / `ColumnDef.optional(name, col_type, default)` | `ColumnDef` | Non-nullable / nullable column; `col_type` is `ColumnType.IntType` / `FloatType` / `BoolType` / `StringType` / `BytesType`. |
| `Schema.new(table, cols, pk)` / `Schema.column_index(schema, name)` | `Schema` / `Option[Int]` | Catalog metadata (purity + shape validation in `schema_validator`). |
| `column_type_code(t)` | `Int` | Stable column-type code (1..5); compare codes instead of pattern-matching the enum (m225/C-ORBIT-07). |
| `schema_row_value_ok(col, v)` | `Bool` | `TValue` admissibility incl. nullability and the bool 0/1 domain. |
| `schema_row_validate(schema, values)` | `DbResult[Bool]` | Arity + kind + nullability + pk-is-`VInt` rules; `SchemaMismatch` / `ConstraintViolation`. |
| `schema_row_key(schema, values)` | `DbResult[Int]` | The pk int (the future storage key); validates first. |
| `schema_row_encode(schema, values)` | `DbResult[Vec[Int]]` | Validate + tuple v2 row (id = pk). |
| `schema_row_decode(schema, buf)` | `DbResult[TypedRow]` | Codec + schema checks; id/pk mismatch = `Corruption`; schema drift = `SchemaMismatch`/`ConstraintViolation`. |
| `schema_row_error_code(e)` | `Int` | 1 NotFound .. 6 Corruption (consumer-safe comparison). |

Persistence of typed rows is specified in `docs/TYPED-VALUES-STORAGE.md`
(container decision; engine slice M5.3). Kind mapping: Int->`VInt`,
Float->`VFloat`, Bool->`VInt` 0/1, String->`VText`, Bytes->`VBlob`.

## Free-space map (`xiom.db.storage.free_space_map`)

`free_space_map_new()`; `fsm_register_page(fsm, capacity)`; `fsm_record_used` /
`fsm_record_free` / `fsm_free_bytes` / `fsm_capacity_of`; `fsm_find_page(fsm,
needed)` (best-fit: tightest, then lowest id); `fsm_page_count` /
`fsm_total_free` / `fsm_validate`. `PageId` here is the FSM's slot id (see
`free_space_map.xi` header for the distinct `ids.PageId` bridge).

## Errors, config, ids, contracts

- `DbError` = `NotFound` / `DuplicateKey` / `ConstraintViolation` / `IOError` /
  `Corruption` / `StorageError`; `to_string`, `is_retryable` (only
  `StorageError`).
- `DatabaseConfig` = `{ page_size, buffer_pool_capacity, wal_enabled,
  btree_order }`; `DatabaseConfig.default()` (4096/64/true/4);
  `database_config_validate`.
- `ids`: `RowId` / `TableId` / `PageId` newtypes with `row_id`,
  `row_id_value`, `row_id_eq`, `row_id_next`, `table_id`, `table_id_value`,
  `table_id_eq`, `row_id_to_page_id`.
- `contracts`: `valid_btree_order`, `valid_key`, `sorted_keys`,
  `valid_range`, `non_decreasing`.
- `txn`: the in-memory `Transaction` state machine (`new`, `add_op`,
  `commit`, `abort`, `is_active`) used by the facade path; the durable
  transaction path is `db_file_txn_*` above.

## Compiler pin

The public API is compiled with **v0.64.2** with **all C-ORBIT workarounds
reverted** (C-ORBIT-01..05 RESOLVED; see `COMPILER-FINDINGS-ORBITDB.md`,
which also carries the open C-ORBIT-06 phantom-import finding). Re-test the
repro bundles before bumping the toolchain.
