# xiom.leveldb -- byte-level specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3, not
published).
Manifest: `package.xi` (`xiom.leveldb`, version `0.1.0`).
Module: `src/leveldb.xi` (`module xiom.leveldb`).
Depends on `xiom.std` (`xiom.convert`; the tests add `xiom.test`,
`xiom.io`, `xiom.string`, `xiom.string.compare`, `xiom.encoding.hex`).
No FFI: the module declares no `extern "C"` blocks and never touches a
filesystem.

This document describes the byte layouts **actually implemented by this
package**. Where upstream LevelDB has more than one historical layout, both
are implemented and labelled. Sources: the LevelDB on-disk format
documentation (`doc/table_format.md`, `doc/log_format.md`) and the
`table/block*`, `table/format.*`, `db/log_*` sources.

## Scope

- LEB128 varint32/varint64 decode/encode with consumed counts.
- Internal keys (user key + 8-byte tag) and the InternalKeyComparator.
- CRC32C (Castagnoli) with the LevelDB mask.
- Log record headers, the 32 KiB block rule, FIRST/MIDDLE/LAST
  reassembly, optional CRC verification.
- Block entries (prefix compression), the restart array, the 5-byte block
  trailer.
- BlockHandles, the 48-byte table footer in both layouts, index blocks.
- Accessors over parallel `Vec` fields with `-1` / `""` / empty-Vec
  out-of-range conventions.

## Non-goals

- Filesystem and table-file access; `CURRENT`, `MANIFEST`, `.ldb` naming,
  version sets.
- Compression: `compression == 1` (snappy) is reported as a flag only;
  payloads are never decompressed.
- Bloom filters, table cache, merged iterators, key lookup, encoding.
- Writing a complete log or table (only fragment/footer/varint helpers
  are provided, for fixtures and tests).
- Semantic validation of key/value content or sequencing of a whole log
  (each block is fed individually).

## LEB128 varints

`leveldb_parse_varint32(data, pos)` / `leveldb_parse_varint64(data, pos)`
return `LevelDbVarint{ value; size }` where `size` is the consumed byte
count (the "consumed count" of the API).

| Property | varint32 | varint64 |
|---|---|---|
| Max bytes | 5 | 10 |
| Last-byte payload limit | 15 (bits 0..3) | 1 (bit 0) |
| Value range returned | [0, 2^32) | [0, 2^63) |
| Continuation bit | 0x80 on every non-last byte | same |

Rules:

- A byte sequence that runs past `data.len()` before a terminator is
  `truncated`.
- A 5th byte with the continuation bit set, or payload > 15, is
  `overflow` for varint32. A 10th byte with the continuation bit set, or
  payload > 1, is `overflow` for varint64.
- A terminating 10th byte with payload exactly 1 encodes a value >= 2^63,
  which does not fit XIOM `Int`: `value exceeds Int range`.
- Non-canonical encodings (e.g. `80 00` for 0) are accepted, matching
  LevelDB's `GetVarint32`/`GetVarint64`.
- `leveldb_push_varint32` writes nothing and returns false when the value
  is negative or > 4294967295; `leveldb_push_varint64` rejects negative
  values. `leveldb_varint32_size`/`leveldb_varint64_size` return the
  encoded length or -1.

## Internal keys

Stored form: `user_key` bytes (any length >= 0 in the file; encoding
rejects the empty key) followed by an 8-byte little-endian tag:

```
tag = (sequence << 8) | type
byte layout: tag byte i = (tag >> (8*i)) & 0xFF, i = 0..7
```

| Type | Name | Value |
|---|---|---|
| kTypeDeletion | DELETION | 0 |
| kTypeValue | VALUE | 1 |

- `leveldb_internal_key_tag(sequence, ktype)` = `sequence * 256 + ktype`
  for `sequence` in [0, 2^56-1] and `ktype` 0/1, else -1.
- Decode: `sequence = tag / 256` (the high 56 bits), `ktype = tag % 256`.
- A tag with bit 63 set (i.e. `sequence >= 2^55` when `ktype < 256`) is
  rejected as out of `Int` range; the error offset points at the first
  tag byte (`len - 8`).
- Comparator (`leveldb_internal_key_compare`): user keys bytewise
  ascending; for equal user keys the **larger tag sorts first** (higher
  sequence first; at equal sequence, VALUE before DELETION).

## CRC32C and the LevelDB mask

- Polynomial: Castagnoli, reflected form **0x82F63B78** (2197175160);
  init **0xFFFFFFFF**; final xor **0xFFFFFFFF**; bit-serial, no table.
- `leveldb_crc32c(data, start, size)` returns the u32 value as an `Int`,
  or -1 when the range is out of bounds.
- Mask (upstream `crc32c::Mask`, `kMaskDelta = 0xA282EAD8`):
  `masked = ((crc >> 15) | (crc << 17)) + kMaskDelta`, all in u32
  arithmetic (mod 2^32); `kMaskDelta = 2726488792`.
- Unmask: `rot = masked - kMaskDelta (mod 2^32)`,
  `crc = (rot >> 17) | (rot << 15)`.
- `leveldb_crc32c_masked` is raw CRC then mask.
- Known-answer vectors used by the tests:
  `crc32c("") = 0`, `crc32c("123456789") = 0xE3069283`,
  `mask(0) = 0xA282EAD8`, `masked("123456789") = 0xC78AB0E5`.

## Log records

### Physical header (7 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | masked CRC32C of the payload, u32 LE |
| 4 | 2 | payload length, u16 LE |
| 6 | 1 | record type |

| Type | Name |
|---|---|
| 1 | FULL |
| 2 | FIRST |
| 3 | MIDDLE |
| 4 | LAST |

Any other type byte (including 0) is rejected by
`leveldb_parse_log_header`; the feed loop screens an all-zero header
before calling it (see below). The CRC covers the fragment payload only,
not the header.

### 32 KiB block rule

Log files are sequences of 32768-byte blocks (the last may be short).
A physical fragment never crosses a block boundary unless the writer
split the logical record: when the remaining block space is less than
7 bytes, the writer zero-fills to the boundary; otherwise it emits a
fragment whose header + payload fits the remainder.
`leveldb_log_block_remainder(pos) = 32768 - (pos % 32768)` (a full block
when `pos` is block-aligned); `leveldb_log_fits_in_block(pos, n)` is
`7 + n <= remainder`.

### Reassembly (`leveldb_log_feed`)

State: `{ have_partial; partial; start }`. Feeding one block:

1. Walk from `pos = 0`. If `pos + 7 > block.len()`, stop.
2. If the 7 bytes at `pos` are all zero, stop (trailer; the remaining
   bytes are not inspected, matching upstream leniency).
3. Parse the header (type must be 1..4; `pos + 7 + length` must fit).
4. If `check_crc`, verify the stored masked CRC against the fragment
   payload.
5. Dispatch:
   - FULL: error if a partial record is open; otherwise emit the payload
     as a complete record.
   - FIRST: error if a partial record is open; otherwise open one with
     this payload and `start = base + pos`.
   - MIDDLE: error if none is open; otherwise append.
   - LAST: error if none is open; otherwise append and emit the joined
     payload. `starts` is the FIRST header offset; `ends` is one past the
     LAST header + payload.
6. `pos += 7 + length` and repeat.
7. After the loop (only when no zero trailer was seen) any remaining
   bytes (necessarily fewer than 7) must be zero, else
   `log: nonzero trailer at <abs>`.

`leveldb_log_finish` rejects a state that still has an open partial
record (`log: incomplete fragmented record at <start>`); a real log may
only end between records.

`LevelDbLogBatch` carries the completed records (`payloads`, `rtypes`,
`starts`, `ends`) and the next state (`next_have`, `next_partial`,
`next_start`; `next_start` is -1 when no record is open). Offsets are
absolute: the caller passes `block_base` (0, 32768, ...).

## Block format

Body = entries, then the restart array. The 5-byte trailer follows the
body but is **not** part of the BlockHandle size.

### Entry

| Field | Encoding |
|---|---|
| shared | varint32: prefix bytes taken from the previous key |
| non_shared | varint32: key bytes stored here |
| value_length | varint32 |
| key bytes | `non_shared` bytes |
| value bytes | `value_length` bytes |

The full key is `prev_key[0..shared] + stored bytes`. `entry_bytes` in
`LevelDbBlockEntry` is the total consumed size (3 varints + key + value).
A `shared` larger than the previous key is rejected.

### Restart array

```
entry*
restart_offset_0: uint32 LE
...
restart_offset_{k-1}: uint32 LE
num_restarts: uint32 LE     <-- at the very end of the block
```

Upstream LevelDB stores the offsets **before** the count (the package
brief lists the fields as "count + offsets", which is the logical
description, not the byte order; this parser follows the upstream byte
order so real tables parse). `entries_end = len - 4 - 4 * num_restarts`,
and `num_restarts = 0` is invalid. Each offset must be `<= entries_end`
and strictly increasing; the first must be 0. While walking entries every
restart offset must land exactly on an entry boundary, and the entry
there must have `shared == 0` (restart points store the key in full).
An empty block has `entries_end == 0` with `num_restarts == 1` and
offset 0.

### Trailer (5 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | compression: 0 = none, 1 = snappy (flag only), else error |
| 1 | 4 | masked CRC32C of the block body, u32 LE |

`leveldb_block_trailer_crc_ok` recomputes the CRC over the body; for
compressed bodies it returns false (no decompression).

## BlockHandle

LEB128 encoding, used inside index values and (modern) footers:

```
offset: varint64
size:   varint64
```

`leveldb_block_handle_decode(data, pos, limit)` is bounded: both varints
must terminate at or before `limit` (e.g. the index entry's value region).
`encoded_len` reports the consumed bytes. `leveldb_block_handle_encode`
returns false for negative fields.

## Table footer (48 bytes)

### Fixed-width layout

`leveldb_parse_footer` / `leveldb_build_footer`:

| Offset | Size | Field |
|---|---|---|
| 0 | 8 | metaindex offset, u64 LE |
| 8 | 8 | metaindex size, u64 LE |
| 16 | 8 | index offset, u64 LE |
| 24 | 8 | index size, u64 LE |
| 32 | 8 | zero padding |
| 40 | 8 | magic `0xdb4775248b80fb57`, u64 LE (bytes 57 FB 80 8B 24 75 47 DB) |

This is the older LevelDB layout; the package brief names it explicitly,
so it is implemented and round-trips.

### LEB128 layout (modern LevelDB)

`leveldb_parse_footer_varint` / `leveldb_build_footer_varint`:

| Offset | Size | Field |
|---|---|---|
| 0 | varint pair | metaindex BlockHandle (offset, size) |
| after it | varint pair | index BlockHandle (offset, size) |
| ..40 | up to 40 | zero padding |
| 40 | 8 | magic, as above |

`leveldb_footer_check(footer, file_size)` requires each handle to be
non-negative and `[offset, offset + size)` to lie inside
`[0, file_size)`; out-of-range handles are errors, not clamps.

## Index block

An index (or metaindex) block uses exactly the data-block entry layout
and restart array; every value must decode as exactly one BlockHandle
bounded by its own value region. Empty values, truncated handles and
handles with trailing bytes inside the value are rejected. A zero-entry
index block is valid (empty table).

## Validation order and Int-range policy

- Footer: length -> magic -> padding -> handle Int ranges (fixed) /
  length -> magic -> handles -> padding (varint).
- Log header: truncation -> record type -> payload overrun; then CRC
  (when requested) and sequencing.
- Block entry: varints -> shared bound -> key bound -> value bound.
- Any stored 64-bit quantity with bit 63 set (internal-key tag, footer
  handle field, varint64 value) is rejected as `exceeds Int range`
  instead of wrapping, because XIOM `Int` is a signed 64-bit type.

## Error catalog

All errors are `Str` messages with the offending byte offset appended as
`... at <off>`.

| Group | Messages |
|---|---|
| varint32 | `varint32: truncated`, `varint32: overflow` |
| varint64 | `varint64: truncated`, `varint64: overflow`, `varint64: value exceeds Int range` |
| internal key | `internal key: empty user key`, `internal key: bad sequence`, `internal key: bad type`, `internal key: too short`, `internal key: tag exceeds Int range` |
| log header | `log header: truncated`, `log header: bad record type`, `log record: length overruns block` |
| log feed | `log: crc mismatch`, `log: unexpected FULL in fragmented record`, `log: FIRST while fragment open`, `log: MIDDLE without FIRST`, `log: LAST without FIRST`, `log: nonzero trailer`, `log: incomplete fragmented record` |
| block entry | `block entry: truncated`, `block entry: overflow`, `block entry: shared beyond previous key`, `block entry: key overrun`, `block entry: value overrun` |
| block restarts | `block restarts: truncated`, `block restarts: zero count`, `block restarts: bad count`, `block restarts: offset out of range`, `block restarts: first offset is not zero`, `block restarts: offsets not increasing` |
| block walk | `block: restart offset misses entry boundary`, `block: restart entry with shared bytes`, `block: restart index out of range` |
| block trailer | `block trailer: truncated`, `block trailer: unknown compression` |
| block handle | `block handle offset: truncated/overflow/value exceeds Int range`, `block handle size: truncated/overflow/value exceeds Int range` |
| footer | `footer: truncated`, `footer: bad magic`, `footer: nonzero padding`, `footer: metaindex/index offset/size exceeds Int range`, `footer: bad metaindex handle`, `footer: bad index handle`, `footer: metaindex/index handle out of range`, `footer: negative file size` |
| index block | `index: empty block handle`, `index: bad block handle`, `index: block handle overrun` |

Table/name helpers (`leveldb_log_record_type_name`,
`leveldb_internal_key_type_name`) return `""` for unknown codes instead of
erroring, and the accessor functions return -1 / "" / an empty Vec when
indexed out of range.

## Test matrix

`tests/test_conformance.xi`, 18 checks, all synthetic buffers:

| # | Check | Covers |
|---|---|---|
| 1 | varint32 boundaries, consumed counts, round-trip | 0, 127, 128, 255, 65535, 16384, 2^28-1, 2^28, 2^32-1, non-canonical 80 00, encoder bounds |
| 2 | varint64 boundaries, Int-range and overflow rejection | 0, 128, 2^40, 2^63-1 (9 bytes), 10-byte 2^63, overflow, truncation, size helper |
| 3 | varint malformed inputs and byte-offset errors | truncated at 0/1/2, overflow at 0, offset reporting |
| 4 | internal keys | encode/decode round-trip, hand-built tag, type table, comparator order, too short, tag range |
| 5 | CRC32C vectors, mask/unmask, range | KATs, 256-byte agreement with the local reference, round trips, invalid ranges |
| 6 | log header | fields, stored CRC, fragment CRC, type table, truncation/bad type/overrun |
| 7 | log feed FULL + trailers | base offsets, `next_*`, CRC on/off, short zero trailer, nonzero trailer, all-zero block |
| 8 | FIRST/MIDDLE/LAST across blocks | carried partial, LAST, starts/ends, finish |
| 9 | sequencing, CRC and length errors | MIDDLE/LAST without FIRST, FULL while open, FIRST while open, bad type, overrun |
| 10 | 32 KiB boundary | remainder, fits, exact fill, crossing header |
| 11 | block entry | shared prefix, consumed counts, value offsets, all bounds errors |
| 12 | restart array | valid parse, zero/bad count, first-not-zero, non-increasing, out-of-range, empty block |
| 13 | block iteration | parallel vectors, keys/values, restart indices, boundary-miss and shared-at-restart errors, `at_restart` |
| 14 | block trailer | flag 0/1, CRC ok/corrupt, unknown compression, truncation |
| 15 | footer fixed | round-trip, magic, padding, truncation, Int range, `footer_check` |
| 16 | footer varint | round-trip, raw handle bytes, bounded handles, padding, magic |
| 17 | index block | handles, keys, empty value, trailing bytes, truncated handle, empty index |
| 18 | block handle | encode/decode, bounds, overflow, negative rejection, version |
