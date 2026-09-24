# xiom.ogg -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.ogg`, version `0.1.0`).
Module: `src/ogg.xi` (`module xiom.ogg`).
Depends on `xiom.std` (declared; the module imports nothing from it).
No FFI: the module declares no `extern "C"` blocks.

## Scope

A pure-XIOM reader for the Ogg container page layer:

- `ogg_parse_pages` walks pages, validates their structure and returns an
  `OggPages` index (offset, size, header flags, granule, serial, sequence);
- `ogg_crc32` computes the Ogg CRC-32 checksum of a buffer;
- `ogg_page_crc_ok` verifies one indexed page against its stored checksum;
- `ogg_page_count` / `ogg_page_offset` / `ogg_page_serial` are infallible
  accessors.

## Non-goals

- Codec payload parsing: Vorbis, Opus, Theora and any other codec, and the
  Ogg packet layer (packet boundaries across continued pages) are out of
  scope. Pages with the "continued packet" flag are indexed but not
  reassembled.
- Page building / checksum setting: there is no writer (the placeholder's
  `pages` writer and `streams`/`seek` inventory items are not part of this
  port).
- Logical bitstream demultiplexing, BOS/EOS pairing, granule ordering:
  `serials`/`sequences`/`flags` are exposed raw.
- Multiplexing, seeking, resync after corruption, Skeleton metadata.
- Streaming over files/sockets; the API works on in-memory `Vec[UInt8]`.

## Byte layout (page header, 27 bytes + segment table + body)

All multi-byte fields are little-endian. Offsets are decimal.

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | capture | ASCII `"OggS"` (`4f 67 67 53`); required. |
| 4 | 1 | version | Must be 0. |
| 5 | 1 | header type | Raw flag byte: `0x01` continued, `0x02` BOS, `0x04` EOS. |
| 6 | 8 | granule position | u64; values >= 2^63 clamp to Int max (see below). |
| 14 | 4 | serial | u32 bitstream serial number (unsigned). |
| 18 | 4 | sequence | u32 page sequence number (unsigned). |
| 22 | 4 | checksum | u32; NOT validated by `ogg_parse_pages`. |
| 26 | 1 | segment count | `nsegs`, 0..255. |
| 27 | `nsegs` | segment table | Lacing values; body size = their sum. |
| 27 + `nsegs` | `sum(lacing)` | body | Not interpreted. |

Page size = 27 + nsegs + sum(lacing values). `sizes[i]` records this total;
`offsets[i]` is the absolute position of the page's byte 0.

## Walk rules (ogg_parse_pages)

1. `data.len() == 0` is `Err("ogg: empty input")`.
2. At each page start `pos`, with `remaining = data.len() - pos`:
   - `remaining < 27`: on the first page (pos == 0) this is
     `Err("ogg: truncated page header")`; afterwards it is
     `Err("ogg: truncated page header")` when `remaining >= 4` and the
     remainder starts with `"OggS"`, and `Err("ogg: trailing garbage")`
     otherwise.
   - capture bytes not `"OggS"`: `Err("ogg: bad capture pattern")` on the
     first page, `Err("ogg: trailing garbage")` afterwards.
   - version byte != 0: `Err("ogg: unsupported version")`.
   - `nsegs > remaining - 27`: `Err("ogg: truncated segment table")`.
   - `sum(lacing) > remaining - 27 - nsegs`: `Err("ogg: truncated page
     data")`.
   - otherwise the page is appended to the index and `pos` advances by the
     page size; the walk finishes successfully when it reaches
     `data.len()` exactly.
3. Trailing bytes that do not form another complete page are an error: the
   parser never silently ignores bytes after the last page.

Granule positions are read as unsigned 64-bit values. Any value with bit 63
set -- including the common `0xFFFFFFFFFFFFFFFF` ("-1") encoding of pages
with no completed packet -- is clamped to Int max (9223372036854775807).
Values below 2^63 (including all realistic granule positions) are returned
exactly.

## CRC-32 parameters

| Parameter | Value |
|---|---|
| Width | 32 bits |
| Polynomial | `0x04C11DB7` |
| Initial value | `0x00000000` |
| Input reflection | No |
| Output reflection | No |
| Final xor | `0x00000000` |
| Processing order | MSB-first (bit 31 of the register first) |
| Return type | non-negative `Int` (0..4294967295) |

Pinned check values (cross-checked with an independent implementation and
against the CRC-32/MPEG-2 known-answer test 0x0376E6E7 for the same
polynomial with init `0xFFFFFFFF`):

| Buffer | CRC |
|---|---|
| `""` | 0 |
| `"123456789"` (ASCII) | 2309065087 (`0x89A1897F`) |
| bytes `0x00..0x0F` | 4233616773 (`0xFC57DD85`) |
| one-page fixture, 29 bytes, checksum field zeroed | 3609392314 (`0xD722F4BA`) |

`ogg_page_crc_ok(data, page_index)` recomputes the CRC over exactly
`[offset, offset + size)` of page `page_index` with the 4 stored checksum
bytes (page-relative offsets 22..25) read as zero, then compares the result
with the stored little-endian u32 at offsets 22..25. It returns
`Ok(true)`/`Ok(false)`; Err carries the `ogg_parse_pages` error for an
invalid walk, or `Err("ogg: page index out of range")` for
`page_index < 0` or `page_index >= ogg_page_count(p)`.

## API signatures

All functions are free functions in module `xiom.ogg`:

```xi
pub type OggPages = {
  offsets: Vec[Int];
  sizes: Vec[Int];
  flags: Vec[Int];
  granules: Vec[Int];
  serials: Vec[Int];
  sequences: Vec[Int];
}

pub fn ogg_parse_pages(data: &Vec[UInt8]) -> Result[OggPages, Str]
pub fn ogg_page_count(p: &OggPages) -> Int
pub fn ogg_page_offset(p: &OggPages, i: Int) -> Int
pub fn ogg_page_serial(p: &OggPages, i: Int) -> Int
pub fn ogg_crc32(data: &Vec[UInt8]) -> Int
pub fn ogg_page_crc_ok(data: &Vec[UInt8], page_index: Int) -> Result[Bool, Str]
```

## Semantics

`ogg_parse_pages(data)`
: Structural walk as described above. Records page offsets/sizes, raw header
  type flags, clamped granule positions, unsigned serials and unsigned
  sequences in stream order. Does not validate checksums.

`ogg_page_count(p)`
: `p.offsets.len()`.

`ogg_page_offset(p, i)`
: Byte offset of page `i`; `-1` when `i < 0` or `i >= ogg_page_count(p)`.

`ogg_page_serial(p, i)`
: Unsigned 32-bit serial of page `i`; `-1` when `i` is out of range.

`ogg_crc32(data)`
: Ogg CRC-32 over every byte of `data` as-is (no byte is masked), returned
  as a non-negative `Int`.

`ogg_page_crc_ok(data, page_index)`
: `ogg_parse_pages(data)`, then range-check `page_index`, then compare the
  stored checksum with the recomputed page CRC (checksum bytes zeroed).

## Error string catalog

| Condition | Error text |
|---|---|
| Zero-length buffer | `ogg: empty input` |
| First page capture != `"OggS"` | `ogg: bad capture pattern` |
| Version byte != 0 | `ogg: unsupported version` |
| First page shorter than 27 bytes, or a later remainder that starts with `"OggS"` and is shorter than 27 bytes | `ogg: truncated page header` |
| Remaining bytes after a complete page that do not start a page header (1..26-byte non-`OggS` remainder, or capture mismatch) | `ogg: trailing garbage` |
| Segment table does not fit in the remaining bytes | `ogg: truncated segment table` |
| Lacing sum does not fit in the remaining bytes | `ogg: truncated page data` |
| `ogg_page_crc_ok` index < 0 or >= page count | `ogg: page index out of range` |

`ogg_page_crc_ok` propagates the `ogg_parse_pages` error (first failure
wins) when the buffer is not a valid walk.

## Complexity

| Operation | Complexity |
|---|---|
| `ogg_parse_pages` | O(data.len()) |
| `ogg_page_count` / `ogg_page_offset` / `ogg_page_serial` | O(1) |
| `ogg_crc32` | O(data.len()) |
| `ogg_page_crc_ok` | O(data.len() + page size) |

## Test plan

`tests/test_conformance.xi` (`module ogg_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Fixtures are hand-built byte by byte, an
independent bit-serial reference CRC is implemented in the test file, and
CRC constants are pinned. Coverage:

1. one page (29 bytes): offset/size/flags/granule/serial/sequence pinned;
2. two pages (31 + 32 bytes): offsets `[0, 31]`, sizes, flags `[2, 4]`,
   granules `[960, 1920]`, serials, sequences `[0, 1]` pinned;
3. pinned CRC values: empty -> 0, `"123456789"` -> 2309065087, bytes
   0..15 -> 4233616773;
4. independent bit-serial reference CRC agrees with `ogg_crc32` (including
   the pinned one-page fixture CRC 3609392314);
5. flipping a covered byte changes the CRC (start, end, page body);
6. `crc_ok` true for a correct page, false for a corrupted body and for a
   zeroed stored checksum;
7. `crc_ok` verifies both pages of a two-page stream;
8. version != 0 (1 and 255) is `ogg: unsupported version`, on the first and
   second page, including `crc_ok` propagation;
9. truncated page header (1, 4 and 26 bytes) is Err;
10. truncated segment table (nsegs raised, 27-byte and 59-byte cuts) is Err;
11. truncated page data (28-byte cut, 540/541-byte cut, 62-byte cut) is Err;
12. trailing garbage (`"junk"`, 10 zero bytes, 2 zero bytes, corrupted
    second-page capture) is Err;
13. a partial second page starting with `"OggS"` is a truncated header;
14. empty input is Err, including `crc_ok` propagation;
15. bad capture pattern on the first page (bytes 0 and 3) is Err;
16. out-of-range accessors return -1 and `page_count` tracks pages;
17. `crc_ok` out-of-range indices (-1, 2, 99) are Err;
18. zero-segment page (size 27, flags 6, serial 99, sequence 7) is valid and
    CRC-verifiable; pinned CRC 4017816242;
19. 511-byte body across lacing values 255+255+1 (size 541) parses and
    verifies; pinned CRC 1086650952;
20. granule clamping: `0xFFFFFFFFFFFFFFFF` -> Int max, an 8-byte value
    below 2^63 survives exactly;
21. three multiplexed pages keep order, offsets `[0, 29, 59]`, serials
    `[11, 22, 11]`, sequences `[0, 0, 1]`, flags `[2, 2, 4]`;
22. `crc_ok` on a stream with a corrupted second page: page 0 true, page 1
    false, page 2 true.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.ogg
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Structure + checksum only: no codec payload parsing and no packet layer.
- No writer: pages cannot be built and checksums cannot be set.
- Granule positions >= 2^63 (including `-1`) are clamped to Int max rather
  than exposed as negative values.
- `ogg_parse_pages` never validates the checksum; a page with a bad
  checksum parses successfully unless `ogg_page_crc_ok` is called.
- The parser requires the buffer to contain whole pages only; it does not
  resync after corruption or tolerate a partial final page as a valid walk
  (any incomplete or trailing bytes are Err).
- Serial/sequence grouping into logical streams is not performed; all
  fields are raw.
- Not thread-safe; all values are plain value types.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_pages`/`_err_pages`/`_ok_bool`/`_err_bool` (constructing Results
  directly in other functions miscompiles in this compiler).
- All byte reads go through `(data[pos] as Int) & 0xFF`; UInt8 values are
  never compared against Int constants without widening.
- The CRC register is kept in an `Int` and normalized with
  `crc >= 2147483648` / `crc - 2147483648` instead of `& 0xFF` on values
  with bit 31 set (a form documented to miscompile in v0.61.3); the
  arithmetic form is exact and always yields a non-negative result.
- `OggPages` (six Vec fields) is constructed inside `ogg_parse_pages` and
  crosses function boundaries only by reference or through `_ok_pages`.
- `Str` comparisons in tests go through `xiom.string.compare.str_compare`
  (BUG 17: `==` on Str values read from a Vec lowers to a pointer
  comparison).
- No module-level const arrays and no `use` statements in the library
  module.
