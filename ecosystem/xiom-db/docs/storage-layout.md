# Storage Layout

> **Status:** Phase 0 — entirely in-memory. This document describes the current in-memory representation and the intended on-disk layout it is designed to become. No file format exists yet.

The storage layer (`src/storage/`) owns bytes: pages, the buffer that caches them, the free-space accounting that places rows, and the tuple codec that turns rows into bytes.

## Page — `storage/page.xi`

```
Page = { id: UInt64, data: Vec[UInt8], checksum: UInt32 }
```

- `Page.new(id, data, checksum)` — `requires: data.len() <= 4096` (a page must fit its block).
- `Page.is_valid()` — recomputes the checksum over `data` and compares. This is the **on-read integrity gate**; a mismatch means corruption.
- `page_compute_checksum(data)` — seals a buffer before caching.

The current checksum is an additive rolling sum (cheap, order-independent). **Phase 1** upgrades it to CRC32C for real torn-write detection.

## BufferPool — `storage/page.xi`

```
BufferPool = { pages: Vec[Option[Page]], capacity, hits, misses }
```

- Direct-mapped: a page lives in slot `id % capacity`. O(1) lookup, but collisions evict.
- `BufferPool.new(capacity)` — `requires: capacity >= 1` (needs a non-zero modulus).
- `put` / `get` track `hits` / `misses`; `hit_ratio` reports effectiveness.
- **Phase 1** replaces the direct-mapped slot + naive eviction with an associative frame table and a clock/LRU replacer (mirroring `xiom.core.storage.buffer_pool`).

## StorageEngine — `storage/page.xi`

Binds a `DatabaseConfig` to a `BufferPool`. `cache_page` / `lookup_page` are the only ways higher layers interact with pages. This is the seam where the real `xiom.core.storage.pager` plugs in during Phase 1.

## Tuple codec — `storage/tuple.xi`

```
Row = { id: UInt64, data: Vec[Int] }
```

- `Row.get_column` / `set_column` / `column_count` — bounds-checked column access.
- `tuple_encode(row) -> Vec[Int]` — current flat form: `[id, len, col0, col1, ...]`.
- `tuple_decode(buf) -> DbResult[Row]` — validates length framing; returns `Err(Corruption)` on malformed input.

`ResultSet { columns: Vec[Str], rows: Vec[Row] }` is the columnar container returned by higher layers. (Note: the column vector uses the correct `Vec[Str]` bracket syntax; the previous `Vec<Str>` form was a bug and has been fixed.)

**Phase 1** replaces the flat-integer codec with a byte-packed, length-prefixed record that respects `DatabaseConfig.page_size` and the column types declared in the catalog.

## Free-space map — `storage/free_space_map.xi` *(scaffold)*

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
┌──────────── data file ────────────┐   ┌──────── wal segment ────────┐
│ page 0 │ page 1 │ page 2 │  ...    │   │ rec │ rec │ rec │  ... (fsync)│
└────────┴────────┴────────┴─────────┘   └─────────────────────────────┘
   each page = 4 KiB block                append-only, LSN-ordered
   B-tree nodes + heap tuples             (see wal-and-recovery.md)
   CRC32C footer per page
```

Every module in this layer is a swap-in seam: replacing the in-memory body with a durable one leaves the index, WAL, and query layers untouched.
