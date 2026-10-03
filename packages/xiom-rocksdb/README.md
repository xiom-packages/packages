# xiom.rocksdb

> **Status:** `incubating` -- conformance-tested (24/24); not yet published.
> **Scope:** a pure-XIOM LSM storage-engine *model* -- memtable
> (skiplist-shaped ordering, size accounting), WAL (records, sync policy,
> replay), SST files (sorted data blocks + index + Bloom-filter shape),
> level structure (L0..Ln, size targets, scores, compaction triggers),
> compaction/flush scheduling (deterministic picker, bounded rounds),
> key/value API (get/put/delete/range scan/snapshot iterator), snapshots
> and sequence numbers, column families, statistics. No FFI and no disk
> I/O: persistence and RocksDB file formats are non-goals.
> **Deps:** `xiom.std` only (`xiom.string.compare`; tests add `xiom.test`,
> `xiom.io`, `xiom.string`, `xiom.convert`).

## What it is

`xiom.rocksdb` models the *behaviour* of a RocksDB-style log-structured
merge tree entirely in memory and entirely deterministically: no result
depends on anything but the arguments and the prior call sequence. Keys
and values are opaque `Vec[UInt8]` byte strings (keys must be non-empty);
all ordering is bytewise (lexicographic, shorter-first).

- **Memtable** (`rocksdb_memtable_*`): entries sorted by
  `(column family ascending, key ascending, sequence descending)`; each
  entry charges `key + value + 16` bytes against a byte capacity (raised
  to at least 64) and gets a deterministic skiplist node height in `1..12`
  derived from a 32-bit hash of `(cf, key, seq)`
  (`rocksdb_memtable_height_for_key`). Lookups are lower-bound binary
  searches (`rocksdb_memtable_find`), with
  `rocksdb_memtable_search_steps` exposing the comparison count; the
  skiplist shape is observable through `rocksdb_memtable_height`,
  `rocksdb_memtable_level_count` and `rocksdb_memtable_entry_height`.
- **WAL model** (`rocksdb_wal_*`): append-only records carrying
  `(cf, key, value, seq, type)`; sync policy NONE (0, only explicit syncs),
  FLUSH (1, every append reaches the OS) or FULL (2, every append is
  durable). `synced` is the durable watermark, `pending` the un-synced
  tail; `rocksdb_wal_replay(_from/_range)` rebuilds a memtable from the
  log, preserving cf, sequence and type (tombstones included).
- **SST model** (`rocksdb_table_*`): `rocksdb_table_build` partitions
  sorted entries into data blocks of at most `block_entries` entries,
  records one index key per block (the block's full first key) and builds
  a Bloom filter over every `(cf, key)` with `max(64, bits_per_key *
  entries)` bits and a fixed hash count. `bytes` = entry bytes + index
  bytes + Bloom bytes + 4 per block. `rocksdb_table_find/get` resolve the
  newest version at or below a snapshot.
- **Version / levels** (`rocksdb_version_*`): files flattened in
  `(level, file number)` order with per-file entry ranges, index ranges,
  Bloom ranges and `(cf, key)` min/max bounds. Level targets grow by
  `base * multiplier^(level-1)`; scores are per-mille (`L0 files * 1000 /
  trigger`, `Ln bytes * 1000 / target`) and `rocksdb_version_pick_level`
  picks the highest score >= 1000, ties to the lowest level, never the
  bottom level. Lookups use the stored bounds and Bloom filter (a Bloom
  `false` is definitive).
- **Compaction** (`rocksdb_version_compact`): deterministic, bounded by
  `max_rounds`. Each round picks a level, selects all L0 files (or the
  oldest file at deeper levels) plus every file at level+1 whose bounds
  intersect, merges them into one new table at level+1 and removes the
  inputs. With `oldest_snapshot = -1` only the newest version of each
  `(cf, key)` is kept and bottom-level tombstones are dropped; otherwise
  every version above the snapshot plus the newest version at or below it
  is kept. `rocksdb_maintenance` runs one bounded pass: flush when full,
  then up to `max_rounds` compactions.
- **Engine** (`rocksdb_put/get/delete/...`): one shared sequence counter;
  writes append to the WAL (subject to its policy) then insert into the
  memtable; reads merge the memtable with every version file and pick the
  highest sequence at or below the snapshot. `rocksdb_flush` turns a
  non-empty memtable into a new L0 file. `rocksdb_get` returns
  `Err("rocksdb: not found")` for absent keys and for tombstones;
  `rocksdb_lookup` distinguishes `1` value / `0` tombstone / `-1` absent.
- **Snapshots, column families, statistics**: snapshots are sequence
  numbers (`rocksdb_snapshot_create/release`, `rocksdb_oldest_snapshot`);
  column families are id namespaces over one sequence (default id 0 is
  `"default"`); `rocksdb_stats` reports puts, deletes, gets,
  hits/misses, flushes, compactions, flush/compact bytes, WAL syncs,
  snapshot creations, iterator creations and scans.

## Honest caveats

- **A model, not a store.** Nothing here touches a file, a thread or a
  clock. Sizes, hashes and "compactions" are deterministic simulations
  with documented formulas; they are not RocksDB's byte-level formats and
  not a performance replica.
- **Model-scale complexity.** Version lookup scans files linearly and
  snapshot iterators materialize and insertion-sort the visible entries
  (`O(entries^2)`); fine for modelling and tests, not for production
  datasets.
- **Snapshot retention floor.** Compaction is only snapshot-safe for
  snapshots at or above the `oldest_snapshot` passed in. Release snapshots
  or they pin versions (which keeps compactions honest but grows files).
- **Simplified compaction.** One output table per round; L0 compactions
  take all L0 files; the bottom level is never picked. No leveled
  sub-compactions, no compression, no table deletion scheduling, no WAL
  truncation after flush.
- **Simplified Bloom.** One bit array per table with `max(64, bits*keys)`
  bits and double hashing; no cache-local blocked Bloom, no prefix
  seeks, no whole-key filtering options.
- **No advanced KV features.** No write batches, transactions, merge
  operator, TTL, delete-range, prefix iteration, compaction filters or
  SST ingestion; `Int` sequences, keys and values only as byte strings.

## API

| Function group | Returns | Description |
|---|---|---|
| `rocksdb_memtable_new/put/clear` | `RocksDbMemtable` / `Int` | Write buffer; `put` returns the sorted index or -1. |
| `rocksdb_memtable_find/search_steps/get` | `Int` / `Result[Vec[UInt8], Str]` | Newest version at a snapshot. |
| `rocksdb_memtable_count/bytes/capacity/is_full/should_flush` | `Int` / `Bool` | Size accounting. |
| `rocksdb_memtable_height/level_count/entry_height/height_for_key/is_sorted` | `Int` / `Bool` | Skiplist shape. |
| `rocksdb_memtable_entry_cf/seq/type/key/value` | `Int` / `Vec[UInt8]` | Entry accessors (-1 / empty out of range). |
| `rocksdb_wal_new/append/sync/replay(_from/_range)` | `RocksDbWal` / `Int` | Records and replay. |
| `rocksdb_wal_count/bytes/synced/pending/syncs/flushes/policy/is_durable` | `Int` / `Bool` | Durability watermark. |
| `rocksdb_wal_entry_cf/seq/type/key/value` | `Int` / `Vec[UInt8]` | Record accessors. |
| `rocksdb_table_build` | `RocksDbTable` | Blocks + index + Bloom from a memtable. |
| `rocksdb_table_find/get` | `Int` / `Result[Vec[UInt8], Str]` | Table lookup at a snapshot. |
| `rocksdb_table_count/bytes/file_number/block_count/first_key/last_key` | `Int` / `Vec[UInt8]` | Table shape. |
| `rocksdb_table_block_first/index_key` | `Int` / `Vec[UInt8]` | Data-block layout. |
| `rocksdb_table_bloom_may_contain/bitlen/hashes/keys/set_bits/fill_permille` | `Bool` / `Int` | Bloom shape and probe. |
| `rocksdb_table_entry_cf/seq/type/key/value` | `Int` / `Vec[UInt8]` | Entry accessors. |
| `rocksdb_version_new/add_table` | `RocksDbVersion` / `Int` | Level structure. |
| `rocksdb_version_find/get/find_file` | `Int` / `Result` | Cross-level lookup. |
| `rocksdb_version_level_file_count/level_bytes/level_target_bytes/score/pick_level/needs_compaction` | `Int` / `Bool` | Targets, scores, picker. |
| `rocksdb_version_compact` | `RocksDbCompactionReport` | Bounded deterministic compaction. |
| `rocksdb_version_file_level/number/bytes/entry_count/first_key/last_key` | accessors | File metadata. |
| `rocksdb_db_new/new_default` | `RocksDbDb` | Engine construction. |
| `rocksdb_put(_cf)/delete(_cf)/get(_cf)/get_at/lookup` | `Int` / `Result` | Key/value API. |
| `rocksdb_flush/should_flush/maintenance` | `Int` / `Bool` | Flush and bounded scheduling. |
| `rocksdb_create_column_family/id/name/count` | `Int` / `Str` | Column families. |
| `rocksdb_snapshot_create/release/count/oldest` | `Int` / `Bool` | Snapshots. |
| `rocksdb_iter_create/first/next/seek/valid/key/value/seq/count/pos/cf/snapshot` | iterator | Materialized snapshot iterator. |
| `rocksdb_scan/scan_count/key/value/seq/truncated` | `RocksDbScan` / accessors | Bounded range scan. |
| `rocksdb_stats/db_sequence/db_memtable_count/.../version` | `RocksDbStats` / `Int` / `Str` | Statistics and module version. |

## Usage

```xiom
use xiom.rocksdb;

var db = rocksdb_db_new_default();
rocksdb_put(&mut db, &key, &value);          // returns the write sequence
let snap = rocksdb_snapshot_create(&mut db);
rocksdb_delete(&mut db, &key);
// reads at the old snapshot still see the value
let old = rocksdb_get_at(&mut db, 0, &key, snap);
// flush + bounded compaction: flush when full, then <= 4 rounds
let actions = rocksdb_maintenance(&mut db, 4);
// snapshot iterator and range scan
var it = rocksdb_iter_create(&mut db, 0, rocksdb_db_sequence(&db));
let n = rocksdb_scan(&mut db, 0, &lo, &hi, 100, rocksdb_db_sequence(&db));
```

## Conformance

`tests/test_conformance.xi` runs 24 in-test synthetic checks (no external
files): memtable ordering/duplicates/accounting, skiplist shape,
snapshot visibility and tombstones, WAL sync policies and replay, SST
blocks/index/Bloom/byte accounting, table lookup, level structure and
targets, per-mille scores and the picker, multi-level lookup, compaction
(L0->L1, bounded rounds, bottom-level tombstone drop, snapshot-safe
dedup, deep overlap selection), engine put/get/delete/lookup/statistics,
column families, snapshots, the iterator, range scans, flush and
maintenance, Bloom-integrated reads after flush, and defaults.

```
.\scripts\port.ps1 -Package xiom-rocksdb -TimeoutSec 60
```

Expected: 24 `[PASS]` lines, `xiom.rocksdb: all tests passed`, then
`port: PASS (program_exit=0)`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
