# ORBITDB On-Disk Format Specification

> **Status:** v1 of every durable format, current for the committed tree.
> Phase 1 codecs are text-based (one record per line, UTF-8, `\n`); the
> byte-packed replacement is future work behind the stdlib byte-IO row. All
> integers in binary codecs are little-endian i64 (`tuple_push_int_le` /
> `tuple_read_int_le`).

## Version policy

- Every binary codec carries a magic byte and a version byte; v1 readers
  reject unknown magics/versions instead of guessing.
- The text codecs (WAL segment, page file/page log) are versioned at the
  document level: this file pins v1. A format change requires a version bump
  plus a migration (compaction rewrite) and a `FORMATS.md` update in the same
  commit.
- Compatibility note: snapshot files written by the original "generation 0"
  writer (page ids `1..node_count`) remain readable; the generation scheme
  below is a strict superset.
- All readers skip malformed/torn lines rather than failing the file: a torn
  tail is always recoverable, and checksums gate every binary blob.

## 1. CRC32C

`page_compute_checksum(data)` = CRC32C/Castagnoli:

- reflected polynomial `0x82F63B78`; init `0xFFFFFFFF`; per input byte
  `crc ^= byte`, then 8 iterations of `crc = (crc >> 1) ^ 0x82F63B78` when the
  low bit is set (else `crc >>= 1`); final `crc ^ 0xFFFFFFFF`.
- Input is a byte view: each `Int` element contributes its low byte.
- Empty input -> `0`; canonical check `CRC32C("123456789") = 0xE3069283`.
- Adopted from `xiom.hash.crc` once byte packs land (stdlib row).

## 2. WAL segment (`<db path>`)

One record per line:

```
lsn|op|key|value|timestamp[|p0,p1,...]
```

| Field | Meaning |
|-------|---------|
| `lsn` | Strictly increasing positive integer, assigned by the writer. |
| `op` | Op code, table below. |
| `key`, `value` | i64 payload of the write (0 when unused). |
| `timestamp` | i64, currently 0 (reserved for retention). |
| payload | Optional comma-separated i64 list (used by Checkpoint and tagged records). |

Op codes: `1` Insert, `2` Update, `3` Delete, `4` SegmentSeal,
`5` ManifestUpdate, `6` Checkpoint, `7` SnapshotMarker, `8` BeginTxn,
`9` CommitTxn, `10` AbortTxn. Decode maps unknown codes to `Insert`;
`wal_op_is_write` is true only for 1/2/3.

Tagged payloads (M5.3): write records (1/2) may carry a payload whose first
element is a SUBTYPE. Subtype `1` = typed row: the remaining elements are the
tuple-v2 row bytes (FORMATS 5A), each 0..255; the record `value` mirrors the
`key` (the pk). Replay applies the payload as the entry payload; an unknown
subtype on a write record is SKIPPED (fail closed -- never apply an int value
without its data). Plain int writes carry no payload. Checkpoint records keep
their own payload (generation, node_count, order).

Reader rules: a line with fewer than 5 fields or with any non-integer field is
skipped (no diagnostics); a torn final line is skipped and healed by appending
a newline before the next write. `wal_file_open` resumes `next_lsn` from the
last valid record. `wal_file_truncate(path, from_lsn)` rewrites the file
keeping records with `lsn >= from_lsn`, preserving payloads. Never truncate to
empty: the Checkpoint anchor carries the LSN continuity.

## 3. Page file and page log (`<db path>.snap`, general page stores)

The snapshot container has two revisions. **v2 (4096-byte blocks) is the
DEFAULT for new databases since M1.2 S4 (2026-10-13)**; v1 (text page log)
stays fully supported: reads auto-detect either format by the first byte
(`'O'` = 0x4F = v2, anything else = v1), and a v1 file opened through the
default handle migrates to v2 on its next checkpoint (migration-on-write,
atomic rename; the temp is synced before the rename and the directory after).
`db_file_open_cfg(path, order, 1)` pins v1 for writes.

### 3.1 v1 text page log (legacy container)

One page per line:

```
page_id|len|checksum|b0,b1,...,b(len-1)
```

- `len` = number of payload bytes (max 4096 per page); each `b` is 0..255.
- `checksum` = CRC32C of the payload (section 1); `Page.is_valid` recomputes
  and compares. Lines with malformed shape, wrong `len`, or a bad checksum are
  not pages.
- **Atomic store**: `page_file_write` upserts one page by rewriting the file
  into a temp and renaming (unlisted pages survive); `page_file_write_batch`
  replaces the entire page set with one rename (all-or-nothing).
- **Append-only log**: `page_log_append` appends a new version of a page in
  O(1); readers take the latest valid occurrence per id
  (`page_log_read_all`); `page_log_len` counts raw entries for compaction
  decisions; `page_log_heal_tail` terminates a torn trailing line before the
  next append (O(1) since S4: `file_last_byte` + `append_line_sync`).
  Compaction rewrites one version per page via `page_file_write_batch`.

### 3.2 v2 block container (default)

Frozen wire format: [docs/BYTE-PAGE-FORMAT-V2.md](BYTE-PAGE-FORMAT-V2.md).
The file is a sequence of 4096-byte blocks, addressed by block index:

```
block 0          header slot A
block 1          header slot B
block 2..N       page blocks (append order; free blocks are KIND_FREE)
```

| Field / rule | Value |
|---|---|
| Block size | 4096 bytes; 40-byte common header (kind, generation, page id, payload len, payload CRC32C) |
| Page payload | ≤ 4056 bytes (40-byte header + 4056 = 4096) |
| Header slot payload | 64 bytes (committed generation, block count, order, ...) |
| Header commit | written to the INACTIVE slot with the highest generation; the first commit mirrors into both slots (single-torn-slot fallback) |
| Page visibility | a page is invisible until a header commit with generation ≥ its own lands; readers resolve the newest valid occurrence per page id at ≤ the active generation |
| Torn safety | CRC per block; torn page blocks are skipped; a torn header slot falls back to the other slot; incremental rewrites repeat the same generation so a crash cannot lose the only version |
| Compaction | `block_store_compact`: one block per live page at a new generation in a temp, single atomic rename (temp synced before, directory after) |
| Sync | every commit path (WAL ack, checkpoint anchor, compaction publishes) fsyncs via `sync_io.sync_fd`; rename publishes add `sync_io.fsync_dir` (stdlib waves 115/118) |

**Incremental checkpoint** (both containers): append new versions of only the
DIRTY nodes, then commit (generation header page / header slot) LAST; an
uncommitted trailing generation is ignored on load. Compaction is triggered
on physical growth (entries > node count + 64) and DEFERS while a snapshot
pin is live (M3; `db_file_compaction_deferrals`).

## 4. Snapshot / checkpoint codec v1

Snapshot files are page logs (section 3) holding the B-tree node set:

```
page 0                  header
page g*2^32 + i + 1     node i as of generation g
```

### Header page (44 bytes)

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | magic `'O'` = `0x4F` |
| 1 | 1 | version = `1` |
| 2 | 1 | kind `'H'` = `0x48` |
| 3 | 1 | reserved (`0`) |
| 4 | 8 | `root` node index (LE) |
| 12 | 8 | `order` (LE, `>= 3`) |
| 20 | 8 | `node_count` (LE, `1 <= n < 2^32`) |
| 28 | 8 | `checkpoint_lsn` (LE; snapshot is consistent through this LSN) |
| 36 | 8 | `generation` (LE) |

### Node page (28-byte header + fields)

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | magic `'O'` = `0x4F` |
| 1 | 1 | node version: `1` (legacy, no payload section) or `2` (M5.3) |
| 2 | 1 | kind `'N'` = `0x4E` |
| 3 | 1 | `is_leaf` (0/1) |
| 4 | 8 | `key_count` (LE) |
| 12 | 8 | `child_count` (LE) |
| 20 | 8 | reserved (`0`) |
| 28 | 8*`key_count` | keys (LE) |
| ... | 8*`key_count` | values (LE; typed rows mirror the key) |
| ... | 8*`child_count` | child node indexes (LE) |
| ... | 8 | `payload_count` (LE, version 2 only; equals `key_count`) |
| ... | per entry | `payload_len` (LE) + `payload_len` bytes (bare/row bytes, 0..255) |

Decode is strict: magic/version/kind, exact length (`28 + 16*key_count +
8*child_count` for version 1; `+ 8 + sum(8 + payload_len)` for version 2), sane
counts, `is_leaf` implies `child_count == 0`, internal nodes have children,
every payload length lies inside the buffer, no trailing bytes; every child
index must address a loaded node. Version 1 pages decode with empty payloads
(no rewrite needed).

Payload budget: a typed row's payload must keep its largest node page inside
the smaller container budget (v2 block payload capacity, 4056 bytes):
`db_file_typed_payload_max(order) = (4056 - (28 + 24*(order-1) + 8*order)) /
(order-1)` -- e.g. 1978 bytes at order 3, 1308 at order 4, 973 at order 5.
`db_file_put_typed` refuses larger payloads up front, and payload elements
must be bytes (0..255) -- both are hard write rules, not checkpoint-time
surprises.

### Generation commit rule

- A checkpoint appends new versions of only the changed nodes at generation
  `g = committed_generation + 1`, then appends the header page **last**: the
  highest-generation valid header commits the snapshot.
- Readers resolve each node as the newest generation `<=` the active header
  generation; pages from an uncommitted newer generation are ignored, so a
  crash mid-checkpoint leaves the previous snapshot fully valid.
- If leftovers of an uncommitted generation are detected, the next checkpoint
  performs a full write of the new generation (no diff), preventing a stale
  page from becoming the only version.
- Compaction runs when the raw log exceeds `node_count + 64` entries: one
  version of every node plus the header at the next generation, installed with
  `page_file_write_batch` (atomic).

## 5. Tuple codec v1

```
byte 0        magic 0xDB
byte 1        version 1
byte 2        field_count = data.len() + 1   (1..255)
byte 3        0x01 (type: i64 id)
bytes 4..11   id                              (LE i64)
for each column:
  byte t      0x01 (type: i64)
  bytes t+1..  value                          (LE i64)
```

- Total length must equal `3 + 9 * field_count`.
- Decode rejects (Corruption) any magic/version/count/type/length violation;
  no partial rows. Encode rejects rows above 255 fields
  (`ConstraintViolation`); `tuple_encode` returns an empty buffer instead
  (empty is never valid v1).
- Page budget: callers use `tuple_fits_page` / the `Page` 4096-byte contract;
  snapshots embed no tuples today.

## 5A. Tuple codec v2 (typed values, M5.1) -- ADDITIVE

The typed-value model and its row codec. v1 (section 5) stays readable and
frozen; the version byte discriminates (v1 bytes never decode as v2 and
vice versa). Codec: `src/storage/tuple.xi` (`TValue`, `TypedRow`,
`tuple2_*` functions).

```
byte 0        magic 0xDB
byte 1        version 2
byte 2        field_count = values.len() + 1   (1..255)
field 0       tagged id -- MUST be tag 0x01 (VInt)
fields 1..    tagged values, each:
  byte t      tag
  tag 0x00    VNull   (no payload)
  tag 0x01    VInt    (8 bytes LE i64)
  tag 0x02    VFloat  (8 bytes IEEE-754 f64, little-endian)
  tag 0x03    VText   (u32 LE byte length + UTF-8 bytes, byte-exact)
  tag 0x04    VBlob   (u32 LE byte length + raw bytes 0..255)
```

Typed value model (M5):

| Kind | Tag | Payload | Notes |
|------|-----|---------|-------|
| Null | 0x00 | -- | SQL NULL analog |
| Int | 0x01 | 8B LE i64 | same LE helper as v1 |
| Float | 0x02 | 8B IEEE-754 f64 LE | bit-exact incl. -0.0/NaN; never decimal text |
| Text | 0x03 | u32 len + UTF-8 | byte-exact; `Str.len()` IS the byte count |
| Blob | 0x04 | u32 len + bytes | elements 0..255 enforced on encode |

- Strict decode: every buffer element must be byte-like (0..255) for the
  WHOLE row; exact total length (no trailing bytes); field 0 must decode as
  VInt; payloads must lie inside the buffer; u32 length fields. Any
  violation -> `Err(Corruption)`, no partial rows.
- Encode (`tuple2_encode_row_checked`): rejects >255 fields, text/blob
  lengths above u32, and blob elements outside 0..255
  (`ConstraintViolation`).
- Budget: `tuple2_encoded_len(values)` = 3 + 9 + sum(value lengths);
  `tuple2_fits_page(values, page_size)` is the caller gate. Value lengths:
  null 1, int/float 9, text/blob 5 + byte length.
- Migration notes: no automatic rewrite. v1 snapshots/WALs keep v1 rows.
  When the engine integration slice lands (schema-driven storage), new
  writes use v2 while readers keep accepting both; the flip is gated per
  container exactly like `page_format` 2. `tuple_decode` (v1) rejects v2
  bytes and `tuple2_decode_row` rejects v1 -- the version byte is the
  discriminator. **Engine persistence contract (container decision):
  `docs/TYPED-VALUES-STORAGE.md`** -- WAL rides the existing tagged-payload
  records (subtype 1), snapshot node pages grow a payload section at
  version 3, int users keep byte-identical records.

## 6. Database file set

| File | Format |
|------|--------|
| `<path>` | WAL segment (section 2) |
| `<path>.snap` | Snapshot page log (sections 3 + 4) |
| `<path>.lock` | M3 shard-lock sentinel (advisory `file_lock`; never deleted while a lock may be held) |
| temp files | `<name>.tmp` during atomic rewrites; safe to ignore/remove after a crash |

Locking: `db_file_open_locked_checked[_cfg]` takes an exclusive advisory lock
on `<path>.lock` (one holder per process); release with `db_file_unlock(path)`
or process exit. The Station owns one shard per actor and holds this lock for
its lifetime.

## 7. ORBITWIRE v1 (Station wire protocol)

The Station's network protocol is documented in full at
`station/docs/ORBITWIRE.md`; this section is the format-registry summary.

- **Transport:** raw TCP (loopback by default), one session per connection.
  Not HTTP; the admin HTTP plane remains PULSE.
- **Frame:** `magic "OBW1" (4) | version u8 | kind u8 | flags u8 |
  reserved u8 | header_len u32 | payload_len u32 | typed header | payload |
  CRC32C u32`, all integers little-endian. CRC32C covers bytes
  `[4, end-4)` with the section 1 polynomial/init/final.
- **Header:** `u16 field_count`, then `u8 tag, u8 type, u16 value_len,
  value`; types INT (i64 LE), BOOL, TEXT (UTF-8), BYTES. Unknown tags are
  ignored; unknown types/trailing bytes are protocol errors.
- **Ops (v1):** HELLO/AUTH/PING/BEGIN/PUT/GET/RANGE/QUERY/COMMIT/ABORT/
  CLOSE, plus additive DELETE/CHECKPOINT. `QUERY` carries typed plan intent
  (conditions/bounds/order/limit/offset); no SQL text.
- **Payloads:** row stream (`RANGE`) and value stream (`QUERY`); typed rows
  carry the tuple-v2 row bytes (`FORMATS.md` 5A) opaquely, so every `TValue`
  kind round-trips.
- **Versioning:** `PROTO_VERSION=1`; header tags are additive, op/error codes
  are stable, frame prefix frozen for v1. A version change is a new wire
  section (v2) with a migration note here.
- **KAT:** a 61-byte PING request with header length 38, payload `01 02 03`
  and CRC `0xcb3dcd44` (LE bytes `44 cd 3d cb`); the exact hex and the full
  limits/error tables are pinned in `station/docs/ORBITWIRE.md` and checked
  by `station/tests/protocol_suite.xi`.