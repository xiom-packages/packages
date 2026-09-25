# xiom.woff -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.woff`, version `0.1.0`).
Module: `src/woff.xi` (`module xiom.woff`).
Depends on `xiom.std`; the library module imports `xiom.string` only (tests
add `xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) structural codec for the WOFF 1.0 font container
(W3C Recommendation 13 December 2012):

- `woff_parse` validates the 44-byte header, the 20-byte table directory
  entries, the directory/block arithmetic and the metadata/private block
  spans, and returns a flat `Woff` index (parallel Vecs, one slot per
  directory entry);
- accessors read the header and per-entry fields back;
- `woff_find_tag` / `woff_find_tag_str` look a table up by tag
  (first match);
- `woff_table_data`, `woff_meta_copy` and `woff_priv_copy` copy the stored
  raw bytes of a span;
- `woff_build` emits the canonical uncompressed container (one directory
  entry per table, `compLength == origLength`, zero padding);
- deterministic `Err(Str)` messages for malformed containers and invalid
  builder input.

## Non-goals

- zlib decompression or recompression: compressed tables and metadata are
  kept raw (`woff_table_is_compressed` is the documented predicate).
- sfnt table parsing, checksum verification, `head`/`DSIG` semantics.
- WOFF2 (different header/signature; `wOF2` is rejected as a bad
  signature).
- Extended metadata XML parsing; `metaOrigLength` is exposed, never
  verified.
- Canonicalising a foreign container: directory order, gaps between table
  spans and padding byte values are not normalised.
- Streaming/incremental parsing: the whole file is an in-memory
  `Vec[UInt8]`.
- Font subsetting, table reordering, checksum recomputation.

## Byte-level layout

`WOFFHeader`, 44 bytes, every multi-byte field big-endian:

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | signature | must be `wOFF` (0x77 0x4F 0x46 0x46) |
| 4 | 4 | flavor | sfnt version; any 32-bit value accepted |
| 8 | 4 | length | total file size; must equal the buffer length exactly |
| 12 | 2 | numTables | 0..4096 (`woff_max_tables()`) |
| 14 | 2 | reserved | must be 0 |
| 16 | 4 | totalSfntSize | `12 + 16*numTables + sum(align4(origLength))` |
| 20 | 2 | majorVersion | exposed; no behavior depends on it |
| 22 | 2 | minorVersion | exposed; no behavior depends on it |
| 24 | 4 | metaOffset | metadata offset, 0 when absent |
| 28 | 4 | metaLength | compressed metadata length, 0 when absent |
| 32 | 4 | metaOrigLength | uncompressed metadata length; never verified |
| 36 | 4 | privOffset | private data offset, 0 when absent |
| 40 | 4 | privLength | private data length, 0 when absent |

The table directory follows immediately at offset 44: `numTables` entries
of 20 bytes each, `dir_end = 44 + 20*numTables`.

| Entry offset | Size | Field |
|---|---|---|
| +0 | 4 | tag (four bytes, each in 0x20..0x7E) |
| +4 | 4 | offset of the table data |
| +8 | 4 | compLength (stored bytes, padding excluded) |
| +12 | 4 | origLength (uncompressed bytes, padding excluded) |
| +16 | 4 | origChecksum (exposed, never verified) |

The rest of the file is the table data (each table zero-padded to a
4-byte boundary), then the optional metadata block, then the optional
private block. All offsets and lengths are bytes; table offsets, metadata
offsets and private offsets are 4-byte aligned when present.

## API signatures

All functions are free functions in module `xiom.woff` (no self methods):

```xi
pub type Woff = {
  flavor: Int;
  length: Int;
  total_sfnt_size: Int;
  major_version: Int;
  minor_version: Int;
  meta_offset: Int;
  meta_length: Int;
  meta_orig_length: Int;
  priv_offset: Int;
  priv_length: Int;
  tags: Vec[Int];
  offsets: Vec[Int];
  comp_lengths: Vec[Int];
  orig_lengths: Vec[Int];
  checksums: Vec[Int];
}

pub fn woff_max_tables() -> Int
pub fn woff_parse(data: &Vec[UInt8]) -> Result[Woff, Str]
pub fn woff_flavor(w: &Woff) -> Int
pub fn woff_length(w: &Woff) -> Int
pub fn woff_num_tables(w: &Woff) -> Int
pub fn woff_total_sfnt_size(w: &Woff) -> Int
pub fn woff_major_version(w: &Woff) -> Int
pub fn woff_minor_version(w: &Woff) -> Int
pub fn woff_table_tag(w: &Woff, i: Int) -> Int
pub fn woff_table_offset(w: &Woff, i: Int) -> Int
pub fn woff_table_comp_length(w: &Woff, i: Int) -> Int
pub fn woff_table_orig_length(w: &Woff, i: Int) -> Int
pub fn woff_table_checksum(w: &Woff, i: Int) -> Int
pub fn woff_table_is_compressed(w: &Woff, i: Int) -> Bool
pub fn woff_find_tag(w: &Woff, tag: Int) -> Int
pub fn woff_find_tag_str(w: &Woff, tag: Str) -> Int
pub fn woff_has_metadata(w: &Woff) -> Bool
pub fn woff_has_private(w: &Woff) -> Bool
pub fn woff_meta_offset(w: &Woff) -> Int
pub fn woff_meta_length(w: &Woff) -> Int
pub fn woff_meta_orig_length(w: &Woff) -> Int
pub fn woff_priv_offset(w: &Woff) -> Int
pub fn woff_priv_length(w: &Woff) -> Int
pub fn woff_table_data(data: &Vec[UInt8], w: &Woff, i: Int) -> Result[Vec[UInt8], Str]
pub fn woff_meta_copy(data: &Vec[UInt8], w: &Woff) -> Result[Vec[UInt8], Str]
pub fn woff_priv_copy(data: &Vec[UInt8], w: &Woff) -> Result[Vec[UInt8], Str]
pub fn woff_build(flavor: Int, tags: &Vec[Int], datas: &Vec[Vec[UInt8]], checksums: &Vec[Int]) -> Result[Vec[UInt8], Str]
pub fn woff_tag_of(s: Str) -> Int
```

## Validation order (pinned)

`woff_parse(data)` with `n = data.len()` checks, in this exact order:

1. `n < 44` -> `woff: truncated header`;
2. signature mismatch -> `woff: bad signature` (checked before `length`);
3. `length != n` -> `woff: length mismatch`;
4. `reserved != 0` -> `woff: nonzero reserved`;
5. `numTables > 4096` -> `woff: too many tables`;
6. `dir_end > n` -> `woff: truncated directory`;
7. for each entry `i = 0..numTables-1`, in file order:
   a. tag bytes outside 0x20..0x7E -> `woff: invalid table tag`;
   b. `compLength > origLength` -> `woff: compressed length exceeds original`;
   c. `compLength == 0 && origLength > 0` -> `woff: zero compLength with nonzero origLength`;
   d. `offset % 4 != 0` -> `woff: unaligned table offset`;
   e. `offset < dir_end || offset > n` -> `woff: table offset out of range`;
   f. `compLength > n - offset` -> `woff: table data out of bounds`;
8. `totalSfntSize` mismatch -> `woff: bad total sfnt size`;
9. any two nonempty table spans overlap -> `woff: overlapping tables`;
10. when `metaLength > 0`: alignment, then bounds (`metaOffset < dir_end`,
    `metaOffset > n`, `metaLength > n - metaOffset`), then overlap with a
    nonempty table span -> `woff: unaligned metadata offset`,
    `woff: metadata out of bounds`, `woff: metadata overlaps table`;
11. when `privLength > 0`: the same three checks with
    `woff: unaligned private offset`, `woff: private data out of bounds`,
    `woff: private data overlaps table`;
12. when both blocks are present and their spans intersect ->
    `woff: metadata overlaps private data`.

On `Err` no partial index is returned.

## Semantics

`woff_parse(data)`
: Empty/other failure modes are as in the order above. A parsed `Woff` has
  `length == data.len()`, `woff_num_tables` equal to the header
  `numTables`, and parallel Vecs of exactly that length. Zero tables are
  structurally valid (a 44-byte file with `totalSfntSize == 12`); SFNT
  semantics are out of scope.

`woff_table_tag` / `woff_table_offset` / `woff_table_comp_length` /
`woff_table_orig_length` / `woff_table_checksum`
: Return the recorded `Int` (tags in 0x20202020..0x7E7E7E7E, offsets and
  lengths in 0..4294967295) or `-1` for `i < 0` / `i >= numTables`. The
  sentinel is unambiguous: every recorded value is non-negative.

`woff_table_is_compressed(w, i)`
: The documented predicate: `true` when `compLength < origLength`, i.e.
  the stored bytes are zlib data kept raw. Equal lengths mean stored
  uncompressed (`false`), including an empty zero-length table; `false`
  for an out-of-range `i`.

`woff_find_tag(w, tag)` / `woff_find_tag_str(w, tag)`
: Linear scan in directory order; the first matching entry index wins.
  Returns `-1` when absent (or, for the string form, when `tag` is not
  exactly four bytes in 0x20..0x7E). Tags are not unique and not sorted;
  both are tolerated.

`woff_tag_of(s)`
: Big-endian `Int` of the four bytes of `s` when `s` is exactly four bytes
  in 0x20..0x7E, otherwise `-1` (including `""`, 3-byte and 5-byte
  strings). The inverse (Int to `Str`) is not offered because this package
  never builds `Str` values from bytes.

`woff_table_data(data, w, i)`
: `Err("woff: index out of range")` for a bad `i`; the recorded span is
  bounds-checked against `data` (`Err("woff: table data out of bounds")`
  when negative or beyond `data.len()`) and exactly `compLength` bytes are
  copied. The bytes are verbatim: when `woff_table_is_compressed` is true
  they are the zlib stream, never inflated.

`woff_meta_copy(data, w)` / `woff_priv_copy(data, w)`
: `Err("woff: no metadata")` / `Err("woff: no private data")` when the
  length field is 0 (the offset field is then ignored, even if nonzero);
  otherwise a bounds-checked verbatim copy of `metaLength` /
  `privLength` bytes with the block-specific bounds message.

`woff_build(flavor, tags, datas, checksums)`
: Validation order: flavor range, then `datas.len() == tags.len()`, then
  `checksums.len() == tags.len()`, then the table cap, then per entry tag
  range followed by checksum range. Nothing is emitted unless every check
  passes. Emit: the 44-byte header (signature, flavor, exact length,
  numTables, reserved 0, computed totalSfntSize, major/minor 0, zero
  metadata/private fields), one directory entry per table in the given
  order (`offset` = running 4-byte-aligned cursor starting at `dir_end`,
  `compLength = origLength = datas[i].len()`, supplied checksum), then each
  table's bytes verbatim followed by 0..3 zero padding bytes. Zero tables
  yield the 44-byte header alone (`length == 44`, `totalSfntSize == 12`).

## Error string catalog

| Condition | Error text |
|---|---|
| `woff_parse`: buffer shorter than 44 bytes | `woff: truncated header` |
| `woff_parse`: first four bytes not `wOFF` | `woff: bad signature` |
| `woff_parse`: `length` field != buffer length | `woff: length mismatch` |
| `woff_parse`: reserved field nonzero | `woff: nonzero reserved` |
| `woff_parse`: `numTables` above 4096 | `woff: too many tables` |
| `woff_parse`: `44 + 20*numTables` exceeds the buffer | `woff: truncated directory` |
| `woff_parse`: a tag byte outside 0x20..0x7E | `woff: invalid table tag` |
| `woff_parse`: `compLength > origLength` | `woff: compressed length exceeds original` |
| `woff_parse`: `compLength == 0 && origLength > 0` | `woff: zero compLength with nonzero origLength` |
| `woff_parse`: `offset % 4 != 0` | `woff: unaligned table offset` |
| `woff_parse`: `offset` outside `dir_end..n` | `woff: table offset out of range` |
| `woff_parse`: `offset + compLength > n` | `woff: table data out of bounds` |
| `woff_parse`: `totalSfntSize` != the formula | `woff: bad total sfnt size` |
| `woff_parse`: two nonempty table spans intersect | `woff: overlapping tables` |
| `woff_parse`: `metaLength > 0` and `metaOffset % 4 != 0` | `woff: unaligned metadata offset` |
| `woff_parse`: `metaLength > 0` and the span is outside `dir_end..n` | `woff: metadata out of bounds` |
| `woff_parse`: metadata span intersects a table span | `woff: metadata overlaps table` |
| `woff_parse`: `privLength > 0` and `privOffset % 4 != 0` | `woff: unaligned private offset` |
| `woff_parse`: `privLength > 0` and the span is outside `dir_end..n` | `woff: private data out of bounds` |
| `woff_parse`: private span intersects a table span | `woff: private data overlaps table` |
| `woff_parse`: metadata and private spans intersect | `woff: metadata overlaps private data` |
| `woff_table_data`: `i` outside `0..numTables-1` | `woff: index out of range` |
| `woff_table_data`: recorded span does not fit `data` | `woff: table data out of bounds` |
| `woff_meta_copy`: no metadata block | `woff: no metadata` |
| `woff_meta_copy`: recorded span does not fit `data` | `woff: metadata out of bounds` |
| `woff_priv_copy`: no private block | `woff: no private data` |
| `woff_priv_copy`: recorded span does not fit `data` | `woff: private data out of bounds` |
| `woff_build`: `flavor < 0` or `flavor > 4294967295` | `woff: flavor out of range` |
| `woff_build`: `datas`/`checksums` length differs from `tags` | `woff: table vectors length mismatch` |
| `woff_build`: more than 4096 tables | `woff: too many tables` |
| `woff_build`: a tag is not 4 bytes in 0x20..0x7E | `woff: invalid table tag` |
| `woff_build`: a checksum outside 0..4294967295 | `woff: checksum out of range` |

## Pinned policies and tolerated deviations

- **Length policy (strict):** `length` must equal the buffer length
  exactly. Both a truncated buffer and trailing bytes after the declared
  end are `woff: length mismatch`; there is no trailing-byte tolerance.
- **Zero-length tables:** `compLength == 0` with `origLength == 0` is a
  valid empty table (empty raw copy, `woff_table_is_compressed` false,
  never overlaps another span). `compLength == 0` with `origLength > 0` is
  rejected (no decompressor could produce bytes from an empty stream).
- **Compression predicate:** `compLength < origLength` means compressed,
  kept raw; `compLength == origLength` (including 0 == 0) means stored
  uncompressed. `origLength` is never cross-checked against a decompressed
  size because this codec never decompresses.
- **Overlap policy (reject):** nonempty table spans must be pairwise
  disjoint, must not intersect the metadata or private span, and the
  metadata and private spans must not intersect each other. A zero-length
  span never overlaps.
- **Directory order (tolerated):** entries are not required to be sorted
  by tag, tags may repeat, and `woff_find_tag` uses first-match. `woff_build`
  emits entries in the caller's order and does not sort.
- **Gaps and padding (tolerated):** table spans need not be gap-free and
  padding byte values are not inspected; only bounds, alignment and
  overlap are validated. A table offset equal to `n` is accepted for a
  zero-length table.
- **Block placement (tolerated):** a present metadata block need not begin
  immediately after the last table, and a present private block is not
  required to end exactly at EOF; only alignment, bounds and overlap are
  checked.
- **Absent-block fields (tolerated):** when `metaLength` is 0 the
  `metaOffset` field is ignored (even when nonzero or out of range); the
  same holds for `privLength` / `privOffset`.
- **Unverified fields:** `metaOrigLength` and every `origChecksum` are
  exposed as numbers and never validated.

## Complexity

| Operation | Complexity |
|---|---|
| `woff_parse` | O(n + numTables^2), numTables <= 4096 |
| accessors / `woff_max_tables` / predicates | O(1) |
| `woff_find_tag` / `woff_find_tag_str` | O(numTables) |
| `woff_table_data` | O(compLength) |
| `woff_meta_copy` / `woff_priv_copy` | O(block length) |
| `woff_build` | O(total table bytes) |

## Test plan

`tests/test_conformance.xi` (`module woff_tests`, 24 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

| # | Check |
|---|---|
| 1 | build -> parse of 3 tables (`OS/2`, `cmap`, `glyf`) pins flavor, length 120, numTables, totalSfntSize 76, tags, offsets 104/108/112, lengths, checksum 0xFFFFFFFF, the uncompressed predicate, tag lookups, block absence and exact table bytes. |
| 2 | single-table build emits the canonical 68-byte layout with every header field, directory field and the data pinned at its offset. |
| 3 | multi-table build pins padded offsets 104/108/112, zero padding bytes at 107/110/111/117/118/119, and that a nonzero padding byte is not inspected on parse. |
| 4 | 0- and 43-byte buffers are truncated headers; a bare 44-byte buffer, `wOF2` (WOFF2) and a below-header declared length hit `bad signature` / `length mismatch` in order. |
| 5 | length policy: overstated length, truncated buffer and a trailing byte are all `woff: length mismatch`. |
| 6 | reserved 1 and 256 are both `woff: nonzero reserved`. |
| 7 | `numTables` 4097 is `too many tables`; 5 and 4096 (directory overrun) are `truncated directory`. |
| 8 | tag bytes 0x1F, 0x00 and 0x7F are `invalid table tag`. |
| 9 | `compLength` 5 > `origLength` 4 is `compressed length exceeds original`. |
| 10 | offset 66 is `unaligned table offset`. |
| 11 | offset 40 (below the directory end) and 72 (past the buffer) are `table offset out of range`. |
| 12 | a 5-byte span at the 4-byte tail is `table data out of bounds`. |
| 13 | `totalSfntSize` 28, 36 and 33 are all `bad total sfnt size`. |
| 14 | two entries sharing offset 84 and a partial 84..92 / 88..92 overlap are `overlapping tables`. |
| 15 | zero-length tables: `0/0` accepted (empty copy, not compressed), an empty table sharing another entry's offset is accepted, an offset equal to the buffer end is accepted, and `0` compLength with `origLength` 4 is rejected. |
| 16 | `compLength 2 < origLength 6` parses, is flagged compressed, and copies the 2 raw bytes. |
| 17 | metadata fixture: `has_metadata`, offsets/lengths/origLength, raw 6-byte copy, absent private block error; a zero `metaLength` with a nonzero/out-of-range `metaOffset` parses as no metadata. |
| 18 | metadata errors: unaligned 66, bounds 60/72/76 and table overlap at 64. |
| 19 | private fixture: both blocks parse with correct spans and raw copies; a private span that does not reach EOF is tolerated; unaligned, bounds and table-overlap errors fire. |
| 20 | metadata 68..74 intruding into private 72..76 is `metadata overlaps private data`. |
| 21 | accessors and `woff_table_is_compressed` return `-1`/`false` out of range; copiers return `index out of range` and short-buffer bounds errors; absent-block copy errors; duplicate `glyf` tags parse with first-match lookup. |
| 22 | `woff_tag_of` pins `glyf`, `OS/2`, `~~~~`, space-containing 4-byte tags accepted, and rejects 3/5/0-byte strings and 0x7F/0x01 bytes. |
| 23 | an empty build is a 44-byte header (numTables 0, totalSfntSize 12) that parses to zero tables with `-1`/error accessors. |
| 24 | builder errors: flavor -1/2^32, vector length mismatches, tags 0/-1/0x1F414141, checksums -1/2^32, and 4097 tables. |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.woff
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No zlib: compressed tables and metadata are opaque raw bytes; the
  decompressed-size rule (`decompress(compLength bytes) == origLength`) is
  not verifiable here and is only partially approximated by the strict
  `compLength <= origLength` and zero-length rules.
- No sfnt semantics: no table directory cross-check against the sfnt
  offset table, no `head` checksum, no `DSIG` handling.
- WOFF2 is rejected as a bad signature, not parsed.
- Tolerance list above (order, duplicates, gaps, padding values, block
  placement, ignored absent-block offsets) is broader than a strict
  canonicaliser; round-tripping a foreign container byte-for-byte is only
  guaranteed via the raw spans, not by re-serialising.
- `woff_build` writes uncompressed tables, WOFF version 0.0 and no
  metadata/private blocks; it is not a general WOFF writer.
- `woff_parse` is O(numTables^2) worst case; bounded by the documented
  4096-entry cap.
- Whole-file in memory; no streaming or partial validation.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_woff`/`_err_woff`/`_ok_bytes`/`_err_bytes` (constructing a `Result`
  with a struct payload in another function miscompiles in this compiler).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering `Int` arithmetic; all multi-byte fields are read/written
  arithmetically (modulo/division with a negative-remainder correction)
  because `& 0xFF` on values with bit 31 set miscompiles.
- `_align4` uses `((v + 3) / 4) * 4`, exact for the non-negative
  `origLength` values it receives (integer division truncates toward
  zero).
- The five parallel directory Vecs are appended only in lockstep, one
  push per field per entry; tags never repeat a `push` without the other
  four.
- `Str` values are compared through `string.str_compare`; `==` on a `Str`
  read from a `Vec` lowers to a pointer comparison (BUG 17).
- The package declares no `extern "C"` blocks (no FFI) and no new
  dependencies; `deps` stays `{ "xiom.std": ">=0.60.0 <1.0.0" }`.
