# xiom.leveldb

> **Status:** `incubating` -- conformance-tested (18/18); published at `v0.1.2` on the XIOM registry.
> **Scope:** LevelDB storage-format parser: LEB128 varints, internal keys,
> log records (7-byte header, 32 KiB block rule, FIRST/MIDDLE/LAST
> reassembly, masked CRC32C), SSTable block structure (prefix-compressed
> entries, restart array, 5-byte trailer), BlockHandles, the 48-byte table
> footer and index-block entries. No filesystem access, no compression
> beyond the one compression-flag byte, no key-value store behaviour.
> **Deps:** `xiom.std` only (`xiom.convert`; tests add `xiom.test`,
> `xiom.io`, `xiom.string`, `xiom.string.compare`, `xiom.encoding.hex`).
> No FFI.

## What it is

`xiom.leveldb` is a pure-XIOM structural parser for the byte formats that
LevelDB writes. It operates on in-memory `Vec[UInt8]` buffers; it never
opens a file and never interprets a key-value workload.

- **Varints** (`leveldb_parse_varint32`, `leveldb_parse_varint64`):
  unsigned LEB128 with a consumed-byte count. A 32-bit varint accepts at
  most 5 bytes (5th payload <= 15); a 64-bit varint at most 10 bytes (10th
  payload <= 1). Errors carry the byte offset. Over-long (non-canonical)
  encodings of small values are accepted, as in LevelDB. Because XIOM
  `Int` is signed, 64-bit values with bit 63 set are rejected as
  `varint64: value exceeds Int range` (real LevelDB sequences, lengths and
  offsets are far below 2^63).
- **Internal keys** (`leveldb_parse_internal_key`,
  `leveldb_internal_key_encode`): user-key bytes followed by the 8-byte
  little-endian tag `sequence << 8 | type`, with type `1` VALUE / `0`
  DELETION and the upstream `InternalKeyComparator` in
  `leveldb_internal_key_compare` (user key ascending, then tag descending).
- **Log records** (`leveldb_parse_log_header`, `leveldb_log_feed`,
  `leveldb_log_finish`): the 7-byte physical header (masked CRC32C u32 LE,
  u16 LE length, type byte FULL 1 / FIRST 2 / MIDDLE 3 / LAST 4), the
  32 KiB block-boundary rule (`leveldb_log_block_remainder`,
  `leveldb_log_fits_in_block`) and a feed-based reassembler: pass one
  block plus the carried state, receive the records completed in that
  block plus the next state. Fragment sequencing is enforced and every
  fragment's masked CRC32C can be verified (or skipped, for damaged
  files).
- **CRC32C** (`leveldb_crc32c`, `leveldb_crc32c_masked`,
  `leveldb_mask_crc32c`, `leveldb_unmask_crc32c`): Castagnoli with the
  reflected polynomial 0x82F63B78, init/final-xor 0xFFFFFFFF, plus the
  LevelDB rotation mask (rotate right 15, add 0xA282EAD8 modulo 2^32).
  Verified against the standard CRC-32C known-answer vectors.
- **Block entries** (`leveldb_parse_block_entry`,
  `leveldb_parse_block_entries`): the shared / non-shared / value-length
  varint triple, prefix-compressed key reconstruction from the previous
  key, the consumed byte count, and a whole-block iterator that walks
  entries while checking that every restart offset lands on an entry
  boundary with a zero shared length.
- **Restart array** (`leveldb_parse_block_restarts`): u32 LE entry offsets
  followed by the u32 LE restart count at the very end of the block (the
  upstream LevelDB order; see SPEC.md).
- **Block trailer** (`leveldb_parse_block_trailer`,
  `leveldb_block_trailer_crc_ok`): compression-type byte (0 = none,
  1 = snappy flag only) plus the masked CRC32C of the block body.
- **BlockHandles and footer** (`leveldb_block_handle_encode/decode`,
  `leveldb_parse_footer`, `leveldb_parse_footer_varint`,
  `leveldb_build_footer`, `leveldb_build_footer_varint`,
  `leveldb_footer_check`): the 48-byte footer with its magic
  `0xdb4775248b80fb57`, in both the fixed-width (u64 LE fields) and the
  LEB128 handle layouts, plus a range check against a table file size.
- **Index blocks** (`leveldb_parse_index_block`): the same entry layout as
  a data block, with every value decoded as exactly one bounded
  BlockHandle; the metaindex block has the same structure and can be
  parsed with the same function.

## Honest caveats

- **No decompression.** A snappy block trailer (compression flag 1) is
  parsed as a flag; its CRC cannot be recomputed from the compressed body,
  so `leveldb_block_trailer_crc_ok` returns false for such blocks.
- **Fixed-width footer.** The fixed-width 48-byte layout (u64 LE handles)
  in `leveldb_parse_footer`/`leveldb_build_footer` is the older LevelDB
  layout and is implemented because the package brief names it
  explicitly. Modern LevelDB writes the LEB128 variant, which
  `leveldb_parse_footer_varint`/`leveldb_build_footer_varint` handle.
- **Int range.** Any stored u64 with bit 63 set (tag, handle, varint64) is
  rejected instead of truncated. Sequences above 2^55-1 are therefore
  out of scope.
- **Lenient zero header.** In `leveldb_log_feed`, a full 7-byte all-zero
  physical header ends the walk and the bytes after it are not inspected
  (matching the upstream reader); only a short (< 7 bytes) nonzero tail is
  rejected.
- **Structure only.** No manifest/CURRENT/version-set parsing, no bloom
  filters, no table cache, no iterator that merges blocks, no encoding.

## API

| Function | Returns | Description |
|---|---|---|
| `leveldb_parse_varint32/64(data, pos)` | `Result[LevelDbVarint, Str]` | LEB128 decode; `value` + `size`. |
| `leveldb_push_varint32/64(dst, value)` | `Bool` | Append an encoding; false when out of range. |
| `leveldb_varint32_size/64_size(value)` | `Int` | Encoded length, or -1 when invalid. |
| `leveldb_crc32c(data, start, size)` | `Int` | Raw CRC32C (u32), or -1 out of range. |
| `leveldb_crc32c_masked(data, start, size)` | `Int` | Masked CRC32C as stored on disk. |
| `leveldb_mask_crc32c/unmask_crc32c(x)` | `Int` | The LevelDB rotation mask and its inverse. |
| `leveldb_internal_key_encode(user_key, sequence, ktype)` | `Result[Vec[UInt8], Str]` | User key + LE tag. |
| `leveldb_parse_internal_key(key)` | `Result[LevelDbInternalKey, Str]` | Split user key and tag. |
| `leveldb_internal_key_user_key/sequence/type(k)` | `Vec[UInt8]`/`Int`/`Int` | Accessors. |
| `leveldb_internal_key_compare(a, b)` | `Int` | InternalKeyComparator order. |
| `leveldb_bytewise_compare(a, b)` | `Int` | Bytewise compare, -1/0/1. |
| `leveldb_parse_log_header(block, pos)` | `Result[LevelDbLogHeader, Str]` | CRC, length, type. |
| `leveldb_log_fragment_crc_ok(block, pos)` | `Bool` | Masked CRC of one fragment. |
| `leveldb_log_state_new()` | `LevelDbLogState` | Empty reassembly state. |
| `leveldb_log_feed(block, base, state, check_crc)` | `Result[LevelDbLogBatch, Str]` | Complete records + next state. |
| `leveldb_log_finish(state)` | `Result[Int, Str]` | Reject a dangling partial record. |
| `leveldb_log_block_size/remainder(pos)` | `Int` | 32768 / bytes left in the block. |
| `leveldb_log_fits_in_block(pos, n)` | `Bool` | Header + payload fits. |
| `leveldb_parse_block_entry(body, pos, limit, prev)` | `Result[LevelDbBlockEntry, Str]` | One prefix-compressed entry. |
| `leveldb_parse_block_restarts(body)` | `Result[LevelDbBlockRestarts, Str]` | Restart offsets + entries_end. |
| `leveldb_parse_block_entries(body)` | `Result[LevelDbBlockEntries, Str]` | Whole block in parallel vectors. |
| `leveldb_block_entry_at_restart(body, j)` | `Result[LevelDbBlockEntry, Str]` | Jump to a restart point. |
| `leveldb_block_entries_*` | accessors | count / key / value / shared / offsets / restart index. |
| `leveldb_parse_block_trailer(trailer, pos)` | `Result[LevelDbBlockTrailer, Str]` | Compression flag + CRC. |
| `leveldb_block_trailer_crc_ok(body, t)` | `Bool` | Recompute the body CRC. |
| `leveldb_block_handle_encode/decode` | `Bool` / `Result[LevelDbBlockHandle, Str]` | LEB128 varint64 pair. |
| `leveldb_parse_footer(data)` | `Result[LevelDbFooter, Str]` | 48-byte fixed-width footer. |
| `leveldb_parse_footer_varint(data)` | `Result[LevelDbFooter, Str]` | 48-byte LEB128 footer. |
| `leveldb_build_footer(_varint)(...)` | `Vec[UInt8]` | Build a 48-byte footer. |
| `leveldb_footer_check(f, file_size)` | `Result[Int, Str]` | Handle ranges inside the file. |
| `leveldb_table_magic_ok(data, pos)` | `Bool` | Magic `0xdb4775248b80fb57`. |
| `leveldb_parse_index_block(body)` | `Result[LevelDbIndex, Str]` | Index/metaindex entries. |
| `leveldb_index_count/key/handle(e, i)` | accessors | Keys and bounded BlockHandles. |

## Usage

```xiom
use xiom.leveldb;

// Walk one 32 KiB log block, verifying CRCs.
let state = leveldb_log_state_new();
let batch = leveldb_log_feed(&block, 0, &state, true);
if batch.is_ok {
  // batch.value.payloads / rtypes / starts / ends; then carry
  // batch.value.next_* into the next call, and leveldb_log_finish at EOF.
}

// Decode a BlockHandle value inside an index entry.
let handle = leveldb_block_handle_decode(&index_entry, value_offset, value_offset + value_len);
```

## Conformance

`tests/test_conformance.xi` runs 18 synthetic-buffer checks: varint
boundaries and malformed cases, internal keys and the comparator, pinned
CRC32C vectors (including `123456789` -> 0xE3069283 and its LevelDB-masked
form 0xC78AB0E5), log headers, FULL and fragmented reassembly across two
blocks, log error sequencing, the 32 KiB boundary, block entries, restart
arrays, whole-block iteration, trailers, both footer layouts, BlockHandles
and index blocks. The suite also carries an independent bit-serial CRC32C
reference and compares it against the library over a 256-byte sequence.
