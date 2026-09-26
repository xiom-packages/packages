# xiom.sparse -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.sparse`, version `0.1.0`).
Module: `src/sparse.xi` (`module xiom.sparse`).
Depends on `xiom.std`; the library module uses `xiom.convert` for the
version string (tests add `xiom.test`, `xiom.io`, `xiom.string`,
`xiom.string.compare`, `xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) codec for Android sparse images:

- `sparse_parse` validates the 28-byte file header, walks every 12-byte
  chunk header and body, enforces the declared chunk/block totals and
  returns a flat `SparseImage` index (five parallel vectors; no Vec of
  structs);
- header accessors: version (major/minor/"major.minor"), file/chunk header
  sizes, block size, total blocks/chunks, image checksum, expanded size;
- chunk accessors: count, type, block count, body offset/length, fill value
  and the running block offset of each chunk;
- `sparse_build` emits a canonical header plus chunk headers/bodies from
  parallel vectors, validating everything before writing a byte;
- deterministic `Err(Str)` messages for malformed input and invalid builder
  arguments.

## Non-goals

- Sparse-to-raw expansion writing: fill and don't-care chunks are indexed
  and counted, never materialized. `sparse_expanded_size` reports the size
  only.
- Filesystem semantics: no ext4/f2fs knowledge, no image writing, no
  padding-to-block rules beyond what the format itself declares.
- Compressed variants (brotli/gzip) or vendor-specific chunk types beyond
  the four documented ones.
- Image checksum computation/verification: `image_checksum` is opaque and
  crc32 chunks are never checked against anything.
- Backup/duplicate metadata, streaming/incremental parsing: the whole image
  is an in-memory `Vec[UInt8]`.

## Byte-level layout

File header, 28 bytes, all little-endian:

| Offset | Width | Field | Value |
|---|---|---|---|
| 0 | 4 | magic | `0xED26FF3A` |
| 4 | 2 | major version | 1 |
| 6 | 2 | minor version | 0 |
| 8 | 2 | file header size | 28 |
| 10 | 2 | chunk header size | 12 |
| 12 | 4 | block size | nonzero, multiple of 4 |
| 16 | 4 | total blocks | u32 |
| 20 | 4 | total chunks | u32 |
| 24 | 4 | image checksum | u32, raw |

Chunk header, 12 bytes, all little-endian:

| Offset | Width | Field |
|---|---|---|
| 0 | 2 | chunk type |
| 2 | 2 | reserved (must be 0) |
| 4 | 4 | chunk size |
| 8 | 4 | total size in bytes (chunk header + body) |

Chunk types and bodies:

| Type | Value | chunk size | Body | Blocks counted |
|---|---|---|---|---|
| raw | `0xCAC1` | blocks | `blocks * block_size` data bytes | chunk size |
| fill | `0xCAC2` | blocks | 4-byte fill value (u32 LE) | chunk size |
| don't-care | `0xCAC3` | blocks | none | chunk size |
| crc32 | `0xCAC4` | 4 (bytes) | 4-byte CRC (u32 LE) | 0 |

`total size` must equal `12 + body length` in all four cases: raw is
`12 + blocks * block_size`, fill is 16, don't-care is 12 and crc32 is 16.
The header's `total blocks` must equal the sum of the non-crc32 block
counts, and `total chunks` must equal the number of chunks in the file.

## API signatures

All functions are free functions in module `xiom.sparse` (no self methods):

```xi
pub type SparseImage = {
  major: Int; minor: Int;
  file_header_size: Int; chunk_header_size: Int;
  block_size: Int; total_blocks: Int; total_chunks: Int;
  image_checksum: Int;
  chunk_types: Vec[Int]; chunk_blocks: Vec[Int];
  data_offsets: Vec[Int]; data_lengths: Vec[Int];
  fill_values: Vec[Int];
}

pub fn sparse_parse(data: &Vec[UInt8]) -> Result[SparseImage, Str]
pub fn sparse_major_version(t: &SparseImage) -> Int
pub fn sparse_minor_version(t: &SparseImage) -> Int
pub fn sparse_version(t: &SparseImage) -> Str
pub fn sparse_file_header_size(t: &SparseImage) -> Int
pub fn sparse_chunk_header_size(t: &SparseImage) -> Int
pub fn sparse_block_size(t: &SparseImage) -> Int
pub fn sparse_total_blocks(t: &SparseImage) -> Int
pub fn sparse_total_chunks(t: &SparseImage) -> Int
pub fn sparse_image_checksum(t: &SparseImage) -> Int
pub fn sparse_chunk_count(t: &SparseImage) -> Int
pub fn sparse_chunk_type(t: &SparseImage, i: Int) -> Int
pub fn sparse_chunk_blocks(t: &SparseImage, i: Int) -> Int
pub fn sparse_chunk_data_offset(t: &SparseImage, i: Int) -> Int
pub fn sparse_chunk_data_length(t: &SparseImage, i: Int) -> Int
pub fn sparse_chunk_fill_value(t: &SparseImage, i: Int) -> Int
pub fn sparse_chunk_block_offset(t: &SparseImage, i: Int) -> Int
pub fn sparse_expanded_size(t: &SparseImage) -> Int
pub fn sparse_build(block_size: Int, chunk_types: &Vec[Int], chunk_blocks: &Vec[Int], chunk_bodies: &Vec[Vec[UInt8]], image_checksum: Int) -> Result[Vec[UInt8], Str]
```

Public constants: `SPARSE_CHUNK_RAW` (51905), `SPARSE_CHUNK_FILL` (51906),
`SPARSE_CHUNK_DONT_CARE` (51907), `SPARSE_CHUNK_CRC32` (51908),
`SPARSE_MAGIC` (3978755898 = 0xED26FF3A), `SPARSE_FILE_HEADER_SIZE` (28),
`SPARSE_CHUNK_HEADER_SIZE` (12).

## Semantics

`sparse_parse(data)`
: Validates the header in the order below, then walks chunks while fewer
  than `total_chunks` have been read and `pos < data.len()`. Every chunk
  push keeps the five parallel vectors in lockstep. On `Err` nothing is
  returned (no partial index). A 28-byte image with `total_chunks = 0` and
  `total_blocks = 0` yields `Ok` with an empty index. Zero-block raw/fill/
  don't-care chunks are legal (they add nothing); crc32 `chunk size` must be
  4 and declares 0 blocks.

`sparse_chunk_count(t)`
: The minimum length of the five parallel vectors. For a parsed image that
  is the chunk count; for a hand-built table with drifted vectors it bounds
  every accessor safely.

`sparse_chunk_data_offset` / `sparse_chunk_data_length`
: Absolute byte span of the body in the parse buffer. Raw: the data bytes;
  fill: the 4-byte fill value; don't-care: the position where a body would
  start with length 0; crc32: the 4-byte CRC. `-1` out of range.

`sparse_chunk_fill_value(t, i)`
: The stored u32 for fill chunks, `-1` for every other type or a bad index.

`sparse_chunk_block_offset(t, i)`
: Sum of `chunk_blocks` for chunks `0..i-1` (crc32 adds 0): the first
  chunk is 0, and the value at `sparse_chunk_count(t)` would be the total.
  `-1` out of range. O(i).

`sparse_expanded_size(t)`
: `total_blocks * block_size`; `-1` when either field is negative or the
  product cannot be represented in a signed 64-bit Int.

`sparse_build(...)`
: Validates in order: block size; checksum range; the three vector lengths;
  then per chunk, in order: known type, block count in `0..2^32-1`, crc32
  blocks == 0, body length consistency (raw: exact multiple of `block_size`
  and quotient equal to the block count; fill/crc32: exactly 4 bytes;
  don't-care: exactly 0), accumulating the non-crc32 block sum. Finally the
  sum must fit a u32. Only then is the image emitted, so an `Err` never
  yields partial bytes: the header is magic/major 1/minor 0/28/12/block
  size/computed total blocks/chunk count/`image_checksum`, and each chunk
  gets reserved 0, `chunk size` = blocks (crc32: 4) and total size
  `12 + body_len`, followed by the body bytes verbatim. An all-raw image is
  the canonical case; the builder is general so any parsed index can be
  re-emitted (the test fixture includes all four types).

## Parse validation order (first failure wins)

1. `data.len() < 28` -> `sparse: truncated header`
2. magic != 0xED26FF3A -> `sparse: bad magic`
3. major != 1 or minor != 0 -> `sparse: unsupported version`
4. file header size != 28 -> `sparse: bad file header size`
5. chunk header size != 12 -> `sparse: bad chunk header size`
6. block size < 1 or `% 4 != 0` -> `sparse: bad block size`
7. per chunk: fewer than 12 remaining bytes -> `sparse: truncated chunk header`
8. per chunk: type not in {0xCAC1..0xCAC4} -> `sparse: unknown chunk type`
9. per chunk: reserved != 0 -> `sparse: nonzero chunk reserved`
10. per chunk: total size < 12 -> `sparse: bad chunk total size`
11. per chunk: body does not fit the remaining bytes -> `sparse: chunk overruns buffer`
12. per chunk: body inconsistent with the type/chunk size -> `sparse: bad chunk size`
13. after the walk: parsed chunks != `total_chunks` -> `sparse: chunk count mismatch`
14. leftover bytes after the last chunk -> `sparse: trailing bytes`
15. summed non-crc32 blocks != `total_blocks` -> `sparse: block count mismatch`

## Error string catalog

| Condition | Error text |
|---|---|
| Parse: buffer shorter than 28 bytes | `sparse: truncated header` |
| Parse: magic mismatch | `sparse: bad magic` |
| Parse: version other than 1.0 | `sparse: unsupported version` |
| Parse: file header size != 28 | `sparse: bad file header size` |
| Parse: chunk header size != 12 | `sparse: bad chunk header size` |
| Parse: block size 0 or not a multiple of 4 | `sparse: bad block size` |
| Parse: partial chunk header | `sparse: truncated chunk header` |
| Parse: unknown chunk type | `sparse: unknown chunk type` |
| Parse: nonzero chunk reserved field | `sparse: nonzero chunk reserved` |
| Parse: chunk total size < 12 | `sparse: bad chunk total size` |
| Parse: body does not fit the buffer | `sparse: chunk overruns buffer` |
| Parse: body/type/size inconsistency (see above) | `sparse: bad chunk size` |
| Parse: fewer chunks than declared | `sparse: chunk count mismatch` |
| Parse: bytes after the last declared chunk | `sparse: trailing bytes` |
| Parse: block sum != header total | `sparse: block count mismatch` |
| Build: block size 0, negative or not a multiple of 4 | `sparse: bad block size` |
| Build: checksum outside 0..2^32-1 | `sparse: bad image checksum` |
| Build: vector lengths differ | `sparse: chunk vector mismatch` |
| Build: unknown chunk type | `sparse: unknown chunk type` |
| Build: block count negative/oversized, or crc32 blocks != 0 | `sparse: bad chunk blocks` |
| Build: body length inconsistent with the type | `sparse: bad chunk body` |
| Build: non-crc32 block sum exceeds 2^32-1 | `sparse: too many blocks` |

## Complexity

| Operation | Complexity |
|---|---|
| `sparse_parse` | O(data.len()) |
| header accessors / type, blocks, span, fill | O(1) |
| `sparse_chunk_block_offset` | O(i) |
| `sparse_expanded_size` | O(1) |
| `sparse_build` | O(total body bytes) |

## Test plan

`tests/test_conformance.xi` (`module sparse_tests`, 24 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. fixture header fields: version 1.0, header sizes, block size 4, 6
   blocks, 4 chunks, checksum 0x44332211, 92 bytes, expanded size 24;
2. raw/fill/don't-care/crc32 types and block counts (crc32 = 0 blocks);
3. body spans 40/60/76/88 and running block offsets 0/2/5/6;
4. exact body slices: raw data, 4-byte fill value, empty don't-care,
   4-byte crc32;
5. the exported type constants, magic and header sizes;
6. parse -> rebuild reproduces the fixture byte-for-byte;
7. `sparse_build` from explicit vectors equals the fixture byte-for-byte;
8. canonical all-raw build at block size 4096: pinned header bytes, 12340
   bytes, spans 40/4148, lengths 4096/8192, block offsets, expanded 12288;
9. a 28-byte zero-chunk header parses empty; one extra byte is trailing;
10. buffers shorter than 28 bytes: truncated header (0/20/27);
11. partial chunk headers: truncated chunk header (30/39);
12. truncated bodies: chunk overruns buffer (40/47/60/88/91);
13. ending between chunks with fewer chunks: chunk count mismatch
    (28/48/64/76);
14. trailing bytes: appended bytes and a shrunken declared count; an
    inflated count is a chunk count mismatch;
15. bad magic and versions other than 1.0;
16. file header size != 28 and chunk header size != 12;
17. block size 0/2/6/0xFFFFFFFF are all bad block size;
18. unknown chunk types and nonzero reserved fields on several chunks;
19. chunk total size below 12 is bad chunk total size;
20. body/size mismatches for all four types (raw quotient, raw remainder,
    fill, don't-care, crc32 chunk size and body);
21. block sum mismatch (5/7/0 vs 6);
22. out-of-range accessors return -1; fill values only for fill chunks;
23. builder error catalog (block size, checksum, vector mismatch, unknown
    type, bad blocks, bad bodies) plus too many blocks;
24. builder round-trip of fill/don't-care/crc32 chunks with a 5-block total.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.sparse
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No sparse-to-raw expansion writing; fill/don't-care chunks are index
  entries only.
- The image checksum is stored raw and never verified; crc32 chunk values
  are exposed through the span accessors but never recomputed.
- Trailing bytes are rejected strictly; images padded past the last chunk
  fail with `sparse: trailing bytes`.
- Only version 1.0 of the format is accepted.
- Block size is only checked nonzero and a multiple of 4.
- `SparseImage` stores offsets into the parse buffer; the buffer must stay
  alive for body reads.
- Validation stops at the first failure; one error message at a time.
- `sparse_chunk_count` for a hand-built table with drifted vectors is the
  vector minimum (safe bound), not the header count.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_image`/`_err_image`/`_ok_bytes`/`_err_bytes` (constructing Result
  payloads in other functions miscompiles in this compiler).
- All little-endian extraction/packing is arithmetic (modulo/division)
  because `& 0xFF` on operands with bit 31 set miscompiles (same bug
  documented in `xiom.gpt`, `xiom.convert.base58` and `xiom.msgpack`).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic.
- Raw body consistency is checked with `body % block_size` and
  `body / block_size` instead of a multiplication, so no parser/builder
  arithmetic can overflow a signed Int.
- Str values in the tests are compared through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a Str read from a
  `Vec` lowers to a pointer comparison); the module itself performs no
  string comparison.
- All chunk vector pushes happen together in one place; the accessors guard
  each vector separately and `_row_count` provides the safe minimum.
- The package declares no `extern "C"` blocks (no FFI).
