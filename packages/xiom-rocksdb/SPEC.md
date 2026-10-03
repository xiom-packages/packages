# xiom.rocksdb -- specification of the modelled subset

Status: `incubating` (implemented, harness-green with compiler v0.62.2, not
published).
Manifest: `package.xi` (`xiom.rocksdb`, version `0.1.0`).
Module: `src/rocksdb.xi` (`module xiom.rocksdb`).
Depends on `xiom.std` (`xiom.string.compare`; the tests add `xiom.test`,
`xiom.io`, `xiom.string`, `xiom.convert`).
No FFI: the module declares no `extern "C"` blocks and never touches a
filesystem.

This document describes the subset **actually implemented by this
package**: the LSM behaviour model and its deterministic formulas. It is a
model of RocksDB semantics, not a parser of RocksDB files and not a
byte-compatible engine. Every number below is exact.

## Scope

- Keys and values are opaque byte strings (`Vec[UInt8]`); keys must be
  non-empty. Ordering is bytewise: compare bytes, shorter prefix first.
- Entries carry `(column family, key, value, sequence, type)` with type
  `1` = value and `0` = tombstone.
- Internal order everywhere: `(cf ascending, key bytewise ascending,
  sequence descending)`.
- Memtable, WAL, SST (blocks/index/Bloom shape), version/levels,
  compaction, flush, engine KV API, snapshots, column families,
  statistics.
- Full determinism: no clocks, threads, randomness, FFI or I/O. Two runs
  of the same call sequence produce identical states, byte counts, hashes
  and reports.

## Non-goals

- Persistence, file formats, manifests, `CURRENT`, block compression,
  checksums, checksum verification.
- FFI and any RocksDB C API surface.
- Real merge iterators, table caches, key encoding, prefix seeks, prefix
  Bloom, partitioned indexes, filters, compaction filters, ingestion,
  write batches, transactions, merge operator, TTL, delete-range.
- WAL truncation/rotation, column-family drops, atomic flush, best-effort
  recovery.
- Performance realism: all structures are parallel `Vec`s; version lookup
  is linear in files and snapshot materialization is `O(entries^2)`.

## Memtable

`rocksdb_memtable_new(capacity)` creates an empty memtable. `capacity` is
clamped to `>= 64`.

Entry charge: `key.len + value.len + 16` bytes, accumulated in `bytes`
(it never decreases on put; `clear` resets it).

`rocksdb_memtable_put(mt, cf, key, value, seq, ktype)`:

- rejects empty keys, negative sequences and types other than 0/1 with
  `-1` (nothing is mutated);
- inserts at the lower-bound position of `(cf, key, seq)` and returns the
  insertion index;
- assigns the node height
  `rocksdb_memtable_height_for_key(cf, key, seq)` = `1 + trailing zero
  bits` of a 32-bit FNV-1a-style hash of `(cf, key bytes, seq+7)`, capped
  at `12`.

`rocksdb_memtable_is_full` (and `rocksdb_memtable_should_flush`) is true
when `bytes >= capacity`.

`rocksdb_memtable_find(mt, cf, key, snapshot)` returns the index of the
newest entry with the same `(cf, key)` and `seq <= snapshot`, or `-1`. It
is a binary search over the sorted entries; tombstones are returned like
any entry. `rocksdb_memtable_search_steps` returns the number of probes
of that search (0 for an empty key or empty memtable).
`rocksdb_memtable_get` returns `Ok(value)` for the newest visible value
and `Err("rocksdb: not found")` for an absent key or a tombstone.

`rocksdb_memtable_is_sorted` verifies the internal order invariant.
Accessors return `-1` / `0` / an empty `Vec` out of range:
`entry_cf`, `entry_seq`, `entry_type`, `entry_key`, `entry_value`,
`entry_height` (0), `height` (0 when empty), `level_count(h)` (0 for
`h <= 0`; counts nodes with height `>= h`).

## WAL

`rocksdb_wal_new(policy)` clamps `policy` to `0..2`:
`0` NONE, `1` FLUSH, `2` FULL. `rocksdb_wal_policy_name` maps
`0 -> "none"`, `1 -> "flush"`, `2 -> "sync"`, anything else `""`.

Each record charges `key.len + value.len + 16` bytes.

`rocksdb_wal_append(w, cf, key, value, seq, ktype)` rejects empty keys,
negative sequences and unknown types with `-1`. It appends one record and
returns its index. Durability:

| Policy | On append | `synced` after | Counter |
|---|---|---|---|
| 0 none | nothing | unchanged | none |
| 1 flush | flush | `count` | `flushes + 1` |
| 2 sync | sync | `count` | `syncs + 1` |

`rocksdb_wal_sync` always sets `synced = count` and increments `syncs`.
`rocksdb_wal_pending` = `count - synced`; `rocksdb_wal_is_durable(upto)`
is true when `0 <= upto <= min(count, synced)`.

`rocksdb_wal_replay(w, mt)` applies all records in append order into `mt`
via `rocksdb_memtable_put`, preserving cf/seq/type, and returns the number
applied. `rocksdb_wal_replay_from(start)` replays `[start, count)`;
`rocksdb_wal_replay_range(start, stop)` clamps both ends and replays the
intersection. Record accessors mirror the memtable ones.

## SST table model

`rocksdb_table_build(mt, file_number, block_entries, bloom_bits_per_key,
bloom_hashes)` copies the memtable entries **in memtable order** and
derives:

- data blocks: entry `i` starts a new block when `i % max(block_entries,
  1) == 0`; `block_first[b]` is the entry index of block `b`;
- index: one key per block, equal to the block's full first key;
- Bloom filter: `bitlen = max(64, max(bits_per_key,1) * count)` bits
  (stored in `(bitlen+7)/8` bytes) with `max(bloom_hashes,1)` probes; bit
  `i` of a key is `(h1 + i*h2) % bitlen` where `h1`/`h2` are the 32-bit
  hash of `(cf, key)` salted by 1 and 2; set-bit probing uses division
  and modulo, never shifts;
- `bytes = entry_bytes + index_bytes + bloom_bytes + 4 * block_count`
  where `entry_bytes` charges `key + value + 16` per entry.

`rocksdb_table_find/get` pick the newest entry with the same `(cf, key)`
and `seq <= snapshot`. `rocksdb_table_bloom_may_contain` may return true
for absent keys (false positives) but never false for present keys;
`set_bits`/`fill_permille` expose the shape. Accessors mirror the
memtable; `first_key`/`last_key`/`index_key`/`entry_key` copy keys out.

## Version and levels

`rocksdb_version_new(l0_trigger, level_base_bytes, level_multiplier,
max_levels, block_entries, bloom_bits_per_key, bloom_hashes)` clamps:
`l0_trigger >= 1`, `level_base_bytes >= 1024`, `level_multiplier >= 2`,
`2 <= max_levels <= 7`, `block_entries >= 1`, Bloom sizes `>= 1`.
`next_file_number` starts at `1`.

`rocksdb_version_add_table(v, t, level)` requires a non-empty table and
`0 <= level < max_levels` (else `-1`). Files are kept ordered by
`(level, file_number)`; the per-file entry/index ranges are element
indices into the flattened arrays, while Bloom and min/max ranges are
byte ranges. `level_count` is the highest occupied level + 1 and
`total_bytes` the sum of table bytes.

Size targets: level 0 has none (`level_target_bytes(0) = -1`); level
`n >= 1` targets `level_base_bytes * level_multiplier^(n-1)`.

Scores are per-mille integers:

- level 0: `files * 1000 / l0_trigger`;
- level `n >= 1`: `level_bytes * 1000 / target(n)`.

The bottom level (`max_levels - 1`) and out-of-layout levels always score
0. `rocksdb_version_pick_level` returns the non-bottom level with the
highest score `>= 1000`, ties resolved to the lowest level, or `-1`.

Lookup: `rocksdb_version_find(v, cf, key, snapshot)` checks each file's
`(cf, key)` min/max bounds and Bloom filter (a Bloom false is definitive)
and returns the flattened entry index of the newest visible version, or
`-1`; `rocksdb_version_get` maps that to `Ok(value)` / `Err("rocksdb: not
found")` (tombstones included). `rocksdb_version_find_file(level, cf,
key)` is the structural bounds-only variant.

## Compaction and flush

`rocksdb_version_compact(v, max_rounds, oldest_snapshot)` runs at most
`max_rounds` rounds (0 does nothing; a round that finds no pickable level
or no files stops the loop):

1. `lvl = pick_level(v)`; stop when `-1`.
2. Inputs: at level 0, **all** L0 files; at deeper levels, the oldest
   file (smallest file number). Expand the chosen `(cf, key)` range over
   the inputs.
3. Add every file at `lvl + 1` whose bounds intersect the range.
4. Gather all entries, sort by `(cf, key, seq desc)` and decide retention
   per `(cf, key)` group:
   - `oldest_snapshot < 0` (no live snapshots): keep only the newest
     version; drop it when it is a tombstone and the output lands at the
     bottom level;
   - otherwise: keep every version with `seq > oldest_snapshot` plus the
     newest version with `seq <= oldest_snapshot`.
5. Remove the inputs and, when entries remain, append one new table at
   `lvl + 1` with file number `next_file_number` (incremented).

The report carries rounds, levels picked, input/output files, input/output
entries, dropped entries, bytes in/out and the last target level.

`rocksdb_flush(db)` builds a table from a non-empty memtable with
`db.ver.next_file_number`, adds it to L0, increments the file number,
clears the memtable and updates `flushes`/`flush_bytes`; an empty
memtable or a rejected add returns `-1` (the memtable is preserved).

`rocksdb_maintenance(db, max_rounds)` = flush when `should_flush`, then
`rocksdb_version_compact(db.ver, max_rounds, oldest_snapshot(db))`;
returns the action count (flush + rounds) and accumulates compaction
statistics.

## Engine API

`rocksdb_db_new(...)` clamps component parameters and creates the default
column family id `0` named `"default"`; `rocksdb_db_new_default()` uses
4096-byte memtable, L0 trigger 4, 256 KiB base target, x10 multiplier,
7 levels, 4-entry blocks, 10 Bloom bits / 3 hashes, WAL FLUSH policy.
The sequence starts at 0.

Writes:

- `rocksdb_put(_cf)` / `rocksdb_delete(_cf)` assign `seq = sequence + 1`,
  reject unknown cf ids and empty keys with `-1`, append to the WAL first
  (subject to policy) and then insert into the memtable; `put` type 1,
  `delete` type 0. `puts`/`deletes` counters increment on success.
- Reads: `rocksdb_lookup(cf, key, snapshot)` returns `1` (live value),
  `0` (newest visible entry is a tombstone) or `-1` (nothing visible);
  `rocksdb_get_at` returns the value or `Err("rocksdb: not found")`.
  Both count `gets`, and `hits` when a visible entry exists (including a
  tombstone) / `misses` otherwise. `rocksdb_get`/`get_cf` read at the
  current sequence.
- `rocksdb_get` on an empty key is `not found` (writes reject it).

Column families: `rocksdb_create_column_family` rejects empty and
duplicate names with `-1`; ids start at 1. `column_family_id(name) ->
id | -1`; `column_family_name(id) -> name | ""`; all families share the
sequence and the memtable/version (entries are namespaced by cf id).

Snapshots: `rocksdb_snapshot_create` returns the current sequence and
records it; `release(seq)` removes the first match and returns whether it
did; `oldest_snapshot` is the minimum live snapshot or `-1`.

Iterators and scans: `rocksdb_iter_create(db, cf, snapshot)` materializes
the newest visible version of every key of `cf` at `snapshot` (tombstones
and superseded versions removed) in bytewise key order; `iter_valid` is
`0 <= pos < count`; `seek` moves to the first key `>= target`; out-of-
range accessors return `-1` / empty `Vec`. `rocksdb_scan(db, cf, min_key,
max_key, limit, snapshot)` includes keys with `min_key <= key <= max_key`
(inclusive; an empty `max_key` means unbounded), returns at most `limit`
entries (`limit <= 0` = unlimited) and sets `truncated` when the limit
stopped a scan that had more matching entries. Iterator creation counts
`iterator_creates`; scans count `scans` (and also create an iterator).

Statistics: `puts`, `deletes`, `gets`, `hits`, `misses`, `flushes`,
`compactions`, `flush_bytes`, `compact_bytes`, `wal_syncs` (WAL full
syncs performed by append policy or explicit calls), `snapshots`,
`iterator_creates`, `scans`. `rocksdb_version() = "0.1.0"`.

## Error catalogue

| Condition | Result |
|---|---|
| `memtable_put` / `wal_append`: empty key, `seq < 0`, type not 0/1 | `-1`, no mutation |
| `memtable_find` / `search_steps`: empty key | `-1` / `0` |
| `memtable_get`: absent key or tombstone | `Err("rocksdb: not found")` |
| `table_build` on an empty memtable | empty table (`count = 0`) |
| `version_add_table`: empty table or level outside `0..max_levels-1` | `-1`, no mutation |
| `version_find/get`: absent or tombstone | `-1` / `Err("rocksdb: not found")` |
| `version_compact`: `max_rounds <= 0`, no score `>= 1000`, no files | 0 rounds, state unchanged |
| `flush`: empty memtable or rejected add | `-1`, memtable preserved |
| `put/delete(_cf)`: unknown cf or empty key | `-1`, no sequence consumed |
| `create_column_family`: empty or duplicate name | `-1` |
| `snapshot_release`: sequence not live | `false` |
| Out-of-range accessors | `-1` / `0` / `""` / empty `Vec` as documented |

There are no panics, no aborts and no hidden global state.

## Invariants (pinned by the conformance suite)

1. Memtable and version files keep `(cf, key, seq desc)` order; every
   parallel array push is mirrored across its siblings.
2. `memtable.bytes` and `wal.bytes` equal the documented per-entry
   charges; table `bytes` equals the documented formula.
3. `version.total_bytes` equals the sum of surviving `file_bytes` after
   every add, removal and compaction.
4. A Bloom `false` never hides a present `(cf, key)` (verified by
   reading back every flushed key through the engine).
5. Compaction never loses a version needed by a snapshot at or above
   `oldest_snapshot`, and drops bottom-level tombstones only when no
   snapshot is live.
6. The compactor is deterministic: same version + same arguments ->
   same report and resulting state; `max_rounds` bounds the work.
