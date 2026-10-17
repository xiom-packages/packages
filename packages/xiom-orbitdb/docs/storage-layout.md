<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# Storage Layout

> **Status:** Phase 0/1 -- the pager layer is still in-memory, but two durable text codecs exist: the page file (`storage/page_file.xi`, CRC32C-verified, atomic rewrite) and the checkpoint snapshot built on it (see `wal-and-recovery.md`). The target layout below is the fixed-block form these seams will be swapped for.

The storage layer (`src/storage/`) owns bytes: pages, the buffer that caches them, the free-space accounting that places rows, and the tuple codec that turns rows into bytes.

## Page -- `storage/page.xi`

```
Page = { id: UInt64, data: Vec[UInt8], checksum: UInt32 }
```

- `Page.new(id, data, checksum)` -- `requires: data.len() <= 4096` (a page must fit its block).
- `Page.is_valid()` -- recomputes the checksum over `data` and compares. This is the **on-read integrity gate**; a mismatch means corruption.
- `page_compute_checksum(data)` -- seals a buffer before caching.

The current checksum is an additive rolling sum (cheap, order-independent). **Phase 1** upgrades it to CRC32C for real torn-write detection.

## BufferPool -- `storage/page.xi`

```
BufferPool = { frames, frame_ids, present, ref_bits, pins,
               capacity, hand, hits, misses, evictions, rejects }
```

- Associative frame table (parallel vectors, no `Vec[Option]` element writes --
  C-ORBIT-02): a page is addressed by id, not by `id % capacity`.
- **Clock (second-chance) replacer**: a referenced frame gets its bit cleared
  and one more round; the first unreferenced, unpinned frame is evicted.
  Bounded to two full sweeps per insert.
- **Pinning**: `pin_page` / `unpin_page` / `pin_count`; pinned frames are never
  evicted. If every frame is pinned, `put` returns `false` (page not cached)
  and `rejects` increments.
- Statistics: `hits` / `misses` (get-side), `evictions`, `rejects`;
  `hit_ratio` reports get effectiveness.
- `BufferPool.new(capacity)` -- `requires: capacity >= 1`.
- **Phase 1** routes these frames through `xiom.core.storage.pager`; the
  replacer + pinning semantics live here already.

## StorageEngine -- `storage/page.xi`

Binds a `DatabaseConfig` to a `BufferPool`. `cache_page` / `lookup_page` are the only ways higher layers interact with pages. This is the seam where the real `xiom.core.storage.pager` plugs in during Phase 1.

## Tuple codec -- `storage/tuple.xi`

```
Row = { id: UInt64, data: Vec[Int] }
```

- `Row.get_column` / `set_column` / `column_count` -- bounds-checked column access.
- `tuple_encode(row) -> Vec[Int]` -- current flat form: `[id, len, col0, col1, ...]`.
- `tuple_decode(buf) -> DbResult[Row]` -- validates length framing; returns `Err(Corruption)` on malformed input.

`ResultSet { columns: Vec[Str], rows: Vec[Row] }` is the columnar container returned by higher layers. (Note: the column vector uses the correct `Vec[Str]` bracket syntax; the previous `Vec<Str>` form was a bug and has been fixed.)

**Phase 1** replaces the flat-integer codec with a byte-packed, length-prefixed record that respects `DatabaseConfig.page_size` and the column types declared in the catalog.

## Durable page file v1 -- `storage/page_file.xi`

One line per page (UTF-8 text; bytes are 0..255 integers):

```
page_id|len|checksum|b0,b1,...
```

| Function | Semantics |
|----------|-----------|
| `page_file_write(pf, page)` | Upsert one page; unlisted pages survive. Rebuilds the file into a temp and atomically replaces it. |
| `page_file_write_batch(pf, pages)` | Replace the **entire** page set in one temp write + atomic rename. All-or-nothing; the snapshot install path. |
| `page_file_read(pf, id)` | One page by id; torn/malformed/checksum-invalid lines are not pages. |
| `page_file_read_all(pf)` | Every valid page in file order from a single scan (whole-set loaders). |
| `page_file_sync(pf)` | Durability seam; no-op until the stdlib fsync wrapper lands. |

The same file doubles as an **append-only page log** for incremental writes:

| Function | Semantics |
|----------|-----------|
| `page_log_append(pf, page)` | Append one page version (O(1)). Later entries for the same id are newer. |
| `page_log_read_all(pf)` | Latest version per page id (last occurrence wins); malformed/checksum-invalid lines skipped. |
| `page_log_len(pf)` | Raw well-formed entry count (compaction trigger measures physical growth). |
| `page_log_heal_tail(pf)` | Terminate a torn trailing line so the next append cannot merge with it. |

Commit rule: a writer appends new versions of only the pages that changed
(since M1.1 the checkpoint drives this from the NodeStore dirty flags, not a
byte diff) and then appends the header page **last**; a reader resolves the
newest committed version (see the generation scheme under checkpoint snapshot
layout). Compaction rewrites one version per page with
`page_file_write_batch`.

Integrity is CRC32C over the byte view (`Page.is_valid`); a structurally complete but checksum-invalid line is dropped on read. `tuple_push_int_le` / `tuple_read_int_le` (exported from `storage/tuple.xi`) are the shared little-endian integer helpers for every on-disk codec.

### Checkpoint snapshot layout (`db_file_checkpoint`)

The checkpoint snapshot is an append-only page log (`<wal path>.snap`) holding
the B-tree node set:

```
page 0                  header: root, order, node_count, lsn, generation
page g*2^32 + i + 1     B-tree node i as of generation g
```

Node codec v1: magic `'O'`, version 1, kind byte `'H'` (header) / `'N'` (node),
then little-endian i64 fields (LE helpers exported from `storage/tuple.xi`).
A checkpoint appends new versions of only the **dirty** nodes (every tree
mutation marks its nodes in the NodeStore; a successful commit clears the
flags), then appends the header page **last** as the commit point; readers
resolve, per node, the
newest generation <= the committed header generation, so pages from an
uncommitted crash window are ignored and the previous snapshot stays fully
valid. When the log grows past `node_count + 64` entries it is compacted with
one version per page through `page_file_write_batch` (atomic).
`db_file_checkpoint` then appends the WAL Checkpoint anchor and truncates the
segment to keep it. See `wal-and-recovery.md`.

## Free-space map -- `storage/free_space_map.xi` *(scaffold)*

```
FreeSpaceMap = { page_free: Vec[Int] }
```

Tracks remaining free bytes per page so the inserter can place a tuple without scanning every page:

- `fsm_register_page(free_bytes) -> PageId`
- `fsm_record_used(page, used)`
- `fsm_find_page(needed) -> Option[PageId]` (current: linear first-fit)

**Phase 1** replaces the linear scan with a compact FSM tree keyed by `PageId` for O(log n) best-fit placement, persisted next to the pager's page table.

## Intended on-disk layout (target)

```
+------------ data file ------------+   +-------- wal segment --------+
| page 0 | page 1 | page 2 |  ...    |   | rec | rec | rec |  ... (fsync)|
`--------+--------+--------+---------+   `-----------------------------+
   each page = 4 KiB block                append-only, LSN-ordered
   B-tree nodes + heap tuples             (see wal-and-recovery.md)
   CRC32C footer per page
```

Every module in this layer is a swap-in seam: replacing the in-memory body with a durable one leaves the index, WAL, and query layers untouched.
