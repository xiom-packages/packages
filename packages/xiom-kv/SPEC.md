# xiom.kv 0.1.0 -- specification

Embedded log-structured key-value store. Pure XIOM, `xiom.std` only. Single
writer per file-name prefix; crash-consistent (no fsync exists in the
toolchain).

## 1. Scope and guarantees

- Append-only segment files with CRC32C-framed records; deletes are
  tombstone records; reopen rebuilds the in-memory index with
  last-write-wins.
- `kv_reopen` is crash-safe: a torn final record (body does not fit before
  EOF) is never applied; the newest segment is repaired and a fresh segment
  id+1 is created so later bytes cannot fuse with the torn record.
- Durability is crash-consistency only: there is no fsync/flush/truncate in
  the toolchain (all stubs). An acknowledged write may be lost on a power
  failure; the file state remains readable.
- The single-writer rule is unenforced: no file locks exist. One owner per
  prefix.

## 2. On-disk format (little-endian)

Files: `<prefix>seg-<10-digit-id>.kv`, temp `<prefix>seg-<id>.tmp`, optional
`<prefix>snapshot.kv` (temp `<prefix>snapshot.tmp`); abandoned segments are
renamed to `<name>.bad` and ignored.

Segment header (28 bytes):

| offset | size | field |
| --- | --- | --- |
| 0 | 4 | magic u32 `0x4B565831` (1263949873) |
| 4 | 2 | version u16 = 1 |
| 6 | 2 | flags u16: bit0 snapshot, bit1 compacted |
| 8 | 8 | segment_id u64 (snapshot: base_seg) |
| 16 | 8 | created_unix u64 (snapshot: base_off) |
| 24 | 4 | header_crc u32 = crc32c(first 24 bytes) |

Record (16 + key_len + value_len bytes):

| offset | size | field |
| --- | --- | --- |
| 0 | 4 | crc u32 = crc32c(flags || key_len || value_len || key || value) |
| 4 | 4 | flags u32: bit0 tombstone |
| 8 | 4 | key_len u32 |
| 12 | 4 | value_len u32 |
| 16 | key_len | key bytes |
| 16+key_len | value_len | value bytes |

Caps: key length in 1..4096 (`kv: key too large`), value length <= 64 MiB
(`kv: value too large`). Any record whose body does not fit before EOF is a
torn tail and is never applied.

Snapshot files use the segment header with the snapshot flag; `segment_id`
holds `base_seg` and `created_unix` holds `base_off` (the base segment's
append offset when the snapshot was taken). Snapshot records are ordinary
put records (`flags` bit0 clear).

## 3. Algorithms

### 3.1 Discovery

Segment ids are discovered by probing `<prefix>seg-<id>.kv` for `id = 1..`
with `io.file_exists`, stopping after 32 consecutive misses (hard cap
1,000,000 probes). This replaces list/filter-by-suffix because
`io.list_dir` is unusable on the pinned runtime (section 6). Ids are
therefore found in ascending order; in normal operation (and after a crashed
compaction, which removes old ids in ascending order) the id set is a short
contiguous run with at most single-id gaps from abandoned segments.

### 3.2 Open / reopen

1. Validate `dir` (non-empty, `io.is_dir`) and `seg_max >= 64`.
2. Load `<prefix>snapshot.kv` when present and fully valid (header + framing
   + CRCs); apply its records with the internal snapshot file marker. An
   invalid snapshot is ignored entirely; segments are authoritative.
3. Discover segment ids. For each ascending:
   - skip ids `< base_seg` when a snapshot was loaded;
   - start at offset 28 (or at `base_off` for the base segment);
   - invalid header: newest -> abandon (rename to `.bad`) + create id+1;
     older -> `kv: corrupt segment header: <name>`;
   - parse records: structural check + CRC32C. Damage stops the scan; newest
     -> rewrite the file with its valid prefix, create id+1; older ->
     `kv: corrupt record: <name> at <off>`;
   - clean newest -> it becomes the active append segment (`seg_len` = file
     size).
4. No segment at/after the snapshot base -> create a fresh segment
   (`max(newest_id, base_seg) + 1`, or 1 for an empty store).

### 3.3 Writes

`kv_put`/`kv_put_bytes` encode one record, `fs_append` it to the active
segment, update `seg_len` and the key slot (seg/off/vlen/tomb), and rotate to
a header-only id+1 segment when `seg_len >= seg_max`. `kv_delete` appends a
tombstone (value_len 0), idempotent, returning whether the key was live.
Every call opens, appends and closes the file; there are no shared handles.

### 3.4 Reads

Map lookup; absent or tombstoned -> `Ok(None)`. Otherwise
`fs_read_range(off + 16 + key.len(), vlen)` with an exact length check
(`kv: short read`), then `Str::from_utf8` for the `Str` API.

### 3.5 Compaction

Remove stale `<id>.tmp` files (discovered ids, the target id, the base+1 crash
target and `snapshot.tmp`); write `<id+1>.tmp` = compacted header + all live
entries in first-write order (values re-read, slots updated); `fs_write`
truncates then fills it; `io.rename` to `<id+1>.kv` (atomic replace); remove
older segment files in ascending id order, then `snapshot.kv`. Rebuild
`entries`/`live_map`/`order` (tombstones dropped, indices renumbered).

A crash during the removals leaves an id-contiguous readable set, and the
compacted segment always has the highest id, so last-write-wins resolves to
the compacted data on the next open.

### 3.6 Snapshot (optional, shipped)

`kv_snapshot` writes `<prefix>snapshot.tmp` (snapshot-flagged header with
base_seg = active id, base_off = active `seg_len`, one put record per live
entry) and renames it to `<prefix>snapshot.kv`. Reopen applies the snapshot
first, then replays the base segment from `base_off` and all newer segments,
so records written after the snapshot win. Snapshot never removes segments; a
lost/corrupt snapshot degrades to a full replay.

## 4. Public API

```
pub type KvEntry = { key: Str; seg: Int; off: Int; vlen: Int; tomb: Bool; }
pub type KvStore = { dir: Str; prefix: Str; entries: Vec[KvEntry]; live_map: StringMap;
                     order: Vec[Int]; count: Int; seg_id: Int; seg_len: Int; seg_max: Int; }
```

- `kv_open(dir, prefix, seg_max) -> Result[KvStore, Str]`
- `kv_reopen(&mut KvStore) -> Result[Unit, Str]`
- `kv_put(&mut, key, value) -> Result[Unit, Str]`
- `kv_put_bytes(&mut, key, &Vec[UInt8]) -> Result[Unit, Str]`
- `kv_get(&KvStore, key) -> Result[Option[Str], Str]`
- `kv_get_bytes(&KvStore, key) -> Result[Option[Vec[UInt8]], Str]`
- `kv_delete(&mut, key) -> Result[Bool, Str]`
- `kv_contains(&KvStore, key) -> Bool`
- `kv_count(&KvStore) -> Int`
- `kv_keys(&KvStore) -> Vec[Str]` (first-write order; a re-inserted key keeps
  its original position)
- `kv_compact(&mut) -> Result[Unit, Str]`
- `kv_snapshot(&mut) -> Result[Unit, Str]`
- `kv_close(&mut)` -- no-op; all handles are per-operation

Constants: `KV_MAGIC`, `KV_VERSION`, `KV_HEADER_SIZE` (28),
`KV_RECORD_FIXED` (16), `KV_KEY_MAX` (4096), `KV_VALUE_MAX` (67108864),
`KV_FLAG_SNAPSHOT`, `KV_FLAG_COMPACTED`, `KV_RECORD_TOMBSTONE`,
`KV_MODULE_VERSION`.

Every error message starts `kv: `. Defined messages: `kv: empty directory`,
`kv: directory not found: <dir>`, `kv: seg_max too small`, `kv: empty key`,
`kv: key too large`, `kv: value too large`, `kv: cannot stat: <path>`,
`kv: cannot read: <path>`, `kv: short read`, `kv: append failed: <name>`,
`kv: cannot create segment: <name>`, `kv: cannot abandon segment: <name>`,
`kv: cannot repair segment: <name>`, `kv: corrupt segment header: <name>`,
`kv: corrupt record: <name> at <off>`, `kv: compact write failed: <name>`,
`kv: compact rename failed: <name>`, `kv: snapshot write failed`,
`kv: snapshot rename failed`.

Complexity: map operations O(1) amortized; put/delete O(key+value) plus one
append; get O(value); reopen O(probed ids + bytes read); compact and snapshot
O(live bytes).

## 5. Verified stdlib surface (v0.64.0, used by this package)

`xiom.io`: `file_exists` :290, `is_dir` :308, `rename` :399 (atomic replace
via the runtime shim), `remove_file` :372, `join_paths` :770 (`/` only),
`time_now` :459, `list_dir` :335 (see section 6), `read_file_bytes` :942 /
`write_file_bytes` :914 (available; not used, section 6).

`xiom.io.fs`: `fs_write` :50 (truncates), `fs_append` :80 (creates),
`fs_read_range` :244 (short at EOF; length-checked by callers), `fs_size`
:215, `fs_temp_dir` :357 (tests), `fs_read` :36 (available; not used,
section 6).

`xiom.collect.stringmap`: `string_map_new` :51, `put` :103, `get` :128,
`contains` :138, `remove` :146, `size` :173 (Int values, O(1)).

`xiom.serialize.endian`: `write_u16/u32/u64_le` :30/:38/:48,
`read_u16/u32/u64_le` :93/:103/:115.

`xiom.hash.crc`: `crc32c` :107 (Castagnoli; verified 0xE3069283 for
"123456789").

`xiom.string`: `byte_at` :289, `str_starts_with` :99, `str_ends_with` :110,
`str_compare` :127 (also `xiom.string.compare.str_compare` compare.xi:28),
`str_repeat` (tests); `str_slice` :50 and `xiom.string.builder` :33-95 are
available but unused. `xiom.convert.int.int_to_base` is used for decimal
segment ids and test fixtures.

No `fsync`/`flush` exists (stubs), and no `truncate`/`remove_dir`/file-lock
API exists.

## 6. Toolchain deviations (forced; report material)

1. **`io.list_dir` entry names are corrupted** on the pinned v0.64.0 Windows
   runtime: every entry name comes back as a garbage numeric string with
   `len() == 0` (observed with both the 19k-entry temp root and a fresh
   2-entry directory), so list/filter-by-suffix cannot be used. Discovery is
   implemented by probing `io.file_exists` for `seg-<id>.kv` ids 1.. with a
   32-miss stop rule (section 3.1). Consequences: open cost is O(max id), and
   foreign `.tmp`/files are simply invisible. The stdlib smoke test only
   checks `list_dir` counts, which is why this gap is not caught upstream.
2. **`fs_read`/`io.read_file_bytes` trip a false `ensures` violation at
   io.xi:943** (`result is Ok => result.len() >= 0`, evaluated on a `Result`)
   in multi-module programs on this runtime; the same call succeeds in
   minimal probes, so it is a contract-checker/codegen interaction. Whole-file
   reads use `fs_size` + `fs_read_range` + an exact length check instead.
3. **`Str` stops at the first NUL byte.** `Str::from_utf8([0,255,65]).len()`
   is 0 (NUL-terminated representation). `kv_get` is therefore a text API;
   `kv_get_bytes` is the exact-byte API. Values written with embedded NUL
   bytes are stored losslessly and read back exactly through the bytes API.
4. No `fsync`/`flush`/`truncate`/file locks: durability is crash-consistency
   only and the single-writer rule is unenforced (section 1).

## 7. Tests

`tests/test_conformance.xi` (28 checks) uses `fs_temp_dir()` with a per-run
prefix `xiomkv-<time>-<tag>-`, never creates directories, and cleans every
fixture with `io.remove_file` (ids 1..64 probed; snapshot and tmp names).
Covered: header bytes; put/get/overwrite/delete; contains/count/keys order;
reopen persistence; exact byte roundtrip; torn-tail repair (with a
length-bearing torn record that must not fuse); CRC corruption ignored on the
newest segment and rejected on an older one; bad-header abandon on the newest
and error on older; compaction (live set, single new segment, old removal,
stale tmp cleanup); rotation across segments and header-only rotated
segments; snapshot roundtrip, post-snapshot replay, corrupt-snapshot
fallback, snapshot+compact; determinism across two stores; key limits; open
validation; close no-op; the `kv: short read` guard; and `kv_keys` returning
an independent vector. Assertions use stable values only (no timestamps).
