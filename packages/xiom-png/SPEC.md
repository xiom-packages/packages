# xiom.png SPEC

## Scope

Pure-XIOM parsing and structural validation of PNG (W3C PNG 1.2, RFC 2083)
containers over flat `Vec[UInt8]` buffers: the 8-byte signature, the chunk
stream with big-endian lengths and CRC-32, the IHDR field grammar, and the
ancillary chunks `PLTE`, `tRNS`, `gAMA`, `pHYs`, `sRGB`, `tEXt`, `zTXt` and
`iTXt`. Results are exposed as parallel `Vec` fields on `PngImage` plus
accessor functions; `Vec[StructType]` is not used.

## Non-goals

No pixel decode, no zlib/DEFLATE inflation, no filtering or Adam7
de-interlacing, no encoder or builder, no ICC/gamma color management, no
`iCCP`/`cHRM`/`bKGD`/`sBIT`/`sPLT`/`hIST`/`tIME`/APNG interpretation, no
streaming, no `Vec[StructType]`, no FFI, no `Float64`.

## Exact layout

```
signature := 89 50 4E 47 0D 0A 1A 0A          (8 bytes)
chunk     := BE32(length) type[4] data[length] BE32(crc32(type data))
image     := signature chunk* IHDR must be the first chunk and IEND the last
```

| Offset in chunk | Size | Field |
|---|---|---|
| +0 | 4 | data length, unsigned 32-bit big-endian; at most 2^31-1 (2147483647) |
| +4 | 4 | chunk type: four ASCII letters A-Z/a-z; third byte must be uppercase (reserved bit 0) |
| +8 | length | chunk data |
| +8+length | 4 | CRC-32 of `type` followed by `data`, unsigned 32-bit big-endian |

A complete chunk is at least 12 bytes. The chunk index records for every
chunk: `chunk_type` (the 4-letter type as a `Str`), `chunk_offset` (absolute
offset of the length field), `chunk_length` (declared data length),
`chunk_data_offset` (`chunk_offset + 8`) and `chunk_crc` (the stored CRC,
already verified).

## CRC-32

Standard IEEE 802.3 / zlib CRC-32, implemented locally with the reflected
polynomial `0xEDB88320`, initial register `0xFFFFFFFF` and final XOR
`0xFFFFFFFF`. Check values: `"123456789"` -> `0xCBF43926` (3421780262), the
empty buffer -> 0. `png_crc32(data)` exposes the primitive. Complexity:
O(data.len()) with an 8-step inner loop per byte.

## Chunk type validation

All four type bytes must be ASCII letters (`A-Z`, `a-z`); the third byte must
be uppercase (bit 5 clear, the PNG reserved bit). Violations are
`png: invalid chunk type at <pos+4>`. Unknown types that pass this check are
accepted and indexed, regardless of whether they are critical or ancillary;
they are never interpreted.

## IHDR (must be the first chunk, exactly once, data length 13)

| Offset in data | Size | Field | Validation |
|---|---|---|---|
| +0 | 4 | width | 1..2147483647, else `png: invalid width at <offset>` |
| +4 | 4 | height | 1..2147483647, else `png: invalid height at <offset>` |
| +8 | 1 | bit depth | legal for the color type (table below) |
| +9 | 1 | color type | one of 0, 2, 3, 4, 6 |
| +10 | 1 | compression method | must be 0 |
| +11 | 1 | filter method | must be 0 |
| +12 | 1 | interlace method | 0 (none) or 1 (Adam7) |

Color type and bit depth are validated in that order: an unknown color type
is `png: invalid color type at <data+9>` before the depth is considered.

| Color type | Meaning | Legal bit depths |
|---|---|---|
| 0 | grayscale | 1, 2, 4, 8, 16 |
| 2 | truecolor RGB | 8, 16 |
| 3 | indexed | 1, 2, 4, 8 |
| 4 | grayscale + alpha | 8, 16 |
| 6 | RGBA | 8, 16 |

The parser never derives pixels or expected IDAT sizes from these fields.

## Ancillary chunks

Each helper returns `""` on success or the documented message; validation
order is exactly the order of the checks listed here. `p` is the chunk
offset, `d` the data offset.

### PLTE -- palette

1. `seen_plte` -> `png: duplicate PLTE at p`
2. length < 3, > 768 or not a multiple of 3 -> `png: invalid PLTE length at p`
3. color type 0 or 4 -> `png: PLTE not allowed at p`
4. after IDAT -> `png: PLTE after IDAT at p`
5. after tRNS -> `png: PLTE after tRNS at p`
6. color type 3 and entries (`length/3`) > `2^bit_depth` ->
   `png: PLTE too large for bit depth at p`
7. Store the raw payload. For color type 3 a missing PLTE is detected at the
   end of the stream: `png: missing PLTE`.

### tRNS -- transparency

1. `seen_trns` -> `png: duplicate tRNS at p`
2. color type 4 or 6 -> `png: tRNS not allowed at p`
3. after IDAT -> `png: tRNS after IDAT at p`
4. color type 3: before PLTE -> `png: tRNS before PLTE at p`; length must be
   1..palette entries -> `png: invalid tRNS length at p`
5. color type 0: length must be 2; color type 2: length must be 6 ->
   `png: invalid tRNS length at p`
6. Store the raw payload.

### gAMA -- gamma

1. `seen_gama` -> `png: duplicate gAMA at p`
2. length != 4 -> `png: invalid gAMA length at p`
3. after PLTE or IDAT -> `png: gAMA after PLTE or IDAT at p`
4. value 0 -> `png: invalid gAMA value at d`
5. Store the integer value (scaled by 100000; `png_gamma` returns it).

### pHYs -- physical pixel dimensions

1. `seen_phys` -> `png: duplicate pHYs at p`
2. length != 9 -> `png: invalid pHYs length at p`
3. after IDAT -> `png: pHYs after IDAT at p`
4. unit byte > 1 -> `png: invalid pHYs unit at d+8`
5. Store pixels-per-unit X, Y and the unit (0 unknown, 1 metre).

### sRGB -- standard RGB color space

1. `seen_srgb` -> `png: duplicate sRGB at p`
2. length != 1 -> `png: invalid sRGB length at p`
3. after PLTE or IDAT -> `png: sRGB after PLTE or IDAT at p`
4. intent > 3 -> `png: invalid sRGB intent at d`
5. Store the intent (0 perceptual, 1 relative colorimetric, 2 saturation,
   3 absolute colorimetric).

### tEXt -- keyword + Latin-1 text

Payload is `keyword 00 text`. Validation:

1. no 0x00 -> `png: missing keyword separator at d`
2. keyword length 1..79 and every keyword byte printable Latin-1
   (`0x20..0x7E` or `0xA1..0xFF`) -> `png: invalid text keyword at d`
3. text bytes must be NUL-free printable Latin-1:
   `0x09`, `0x0A`, `0x0D`, `0x20..0x7E` or `0xA0..0xFF` ->
   `png: invalid text at <text offset>`
4. Store keyword and text as `Str` (safe because the range is NUL-free).

### zTXt -- keyword + zlib-compressed text

Payload is `keyword 00 method compressed`. Validation:

1. keyword and separator as for tEXt (same messages)
2. method byte must be present and 0 -> `png: invalid zTXt method at <sep+1>`
3. Store the keyword; the compressed bytes are never inflated and
   `png_text_value` is `""`. `png_text_offset`/`png_text_length` give the raw
   span for callers that want to inflate.

### iTXt -- keyword + UTF-8 text

Payload is `keyword 00 flag method language 00 translated 00 text`.
Validation:

1. keyword and separator as for tEXt
2. flag must be 0 or 1 -> `png: invalid iTXt flag at <sep+1>`
3. method must be present and 0 -> `png: invalid iTXt method at <sep+2>`
4. language tag must be NUL-terminated -> `png: missing language separator`;
   every language byte printable ASCII (`0x20..0x7E`) ->
   `png: invalid iTXt language tag at <language offset>`
5. translated keyword must be NUL-terminated ->
   `png: missing translated keyword separator`; strict UTF-8 ->
   `png: invalid iTXt translated keyword at <offset>`
6. flag 0: text must be strict UTF-8 and NUL-free -> `png: invalid text at
   <offset>`; flag 1: bytes are stored raw and `png_text_value` is `""`

Strict UTF-8 means RFC 3629: valid lead/continuation sequences only, no
overlong forms, no surrogates (U+D800..U+DFFF), no codepoints above U+10FFFF
and no NUL. This validator is implemented inside `xiom.png` because the
stdlib `xiom.utf8.utf8_validate` classifies unrecognized lead bytes
(0x80..0xBF standalone, 0xF8..0xFF) as valid one-byte sequences.

## Ordering rules

Checked as chunks appear, in stream order:

1. the first chunk after the signature must be IHDR (`png: missing IHDR at 8`),
   and IHDR appears once (`png: duplicate IHDR`);
2. PLTE precedes IDAT and follows tRNS;
3. tRNS precedes IDAT and, for color type 3, follows PLTE;
4. gAMA precedes PLTE and IDAT;
5. sRGB precedes PLTE and IDAT;
6. pHYs precedes IDAT;
7. text chunks may appear anywhere (before or after IDAT);
8. IEND has length 0 and is the final chunk.

At the end of the stream, in order: `png: missing IEND`, `png: missing IDAT`,
`png: missing PLTE` (color type 3 only). Multiple IDAT chunks are accepted
and are not required to be adjacent; IDAT payloads are never inspected.

## Error catalog

| Message (offsets absolute unless noted) | Condition |
|---|---|
| `png: truncated signature` | fewer than 8 bytes |
| `png: bad signature at n` | first mismatching signature byte |
| `png: truncated chunk at n` | fewer than 12 bytes for the next chunk, declared length+data+CRC past the buffer, or fewer than 20 bytes total |
| `png: chunk length overflow at n` | declared data length above 2^31-1, checked before any offset arithmetic |
| `png: invalid chunk type at n` | non-letter type byte or lowercase reserved third byte |
| `png: crc mismatch at n` | stored CRC differs; `n` is the CRC field offset |
| `png: missing IHDR at 8` | first chunk is not IHDR |
| `png: duplicate IHDR at n` | second IHDR |
| `png: invalid IHDR length at n` | IHDR length is not 13 |
| `png: invalid width at n` / `png: invalid height at n` | dimension 0 or above 2^31-1 |
| `png: invalid color type at n` | color type not in 0/2/3/4/6 |
| `png: invalid bit depth at n` | depth illegal for the color type |
| `png: invalid compression method at n` | IHDR compression != 0 |
| `png: invalid filter method at n` | IHDR filter != 0 |
| `png: invalid interlace method at n` | IHDR interlace not 0/1 |
| `png: duplicate PLTE at n`; `png: invalid PLTE length at n`; `png: PLTE not allowed at n`; `png: PLTE after IDAT at n`; `png: PLTE after tRNS at n`; `png: PLTE too large for bit depth at n` | PLTE rules |
| `png: duplicate tRNS at n`; `png: tRNS not allowed at n`; `png: tRNS after IDAT at n`; `png: tRNS before PLTE at n`; `png: invalid tRNS length at n` | tRNS rules |
| `png: duplicate gAMA at n`; `png: invalid gAMA length at n`; `png: gAMA after PLTE or IDAT at n`; `png: invalid gAMA value at n` | gAMA rules |
| `png: duplicate pHYs at n`; `png: invalid pHYs length at n`; `png: pHYs after IDAT at n`; `png: invalid pHYs unit at n` | pHYs rules |
| `png: duplicate sRGB at n`; `png: invalid sRGB length at n`; `png: sRGB after PLTE or IDAT at n`; `png: invalid sRGB intent at n` | sRGB rules |
| `png: missing keyword separator at n` | text chunk without NUL after the keyword |
| `png: invalid text keyword at n` | keyword empty, > 79 bytes or non-printable |
| `png: invalid text at n` | text bytes violate the per-kind encoding rules |
| `png: invalid zTXt method at n`; `png: invalid iTXt flag at n`; `png: invalid iTXt method at n` | compression fields |
| `png: missing language separator at n`; `png: invalid iTXt language tag at n`; `png: missing translated keyword separator at n`; `png: invalid iTXt translated keyword at n` | iTXt sub-fields |
| `png: invalid IEND length at n` | IEND length != 0 |
| `png: data after IEND at n` | bytes after a complete IEND |
| `png: missing IEND` / `png: missing IDAT` / `png: missing PLTE` | end-of-stream requirements |

## Result model

`PngImage` carries:

- validated IHDR: `width`, `height`, `bit_depth`, `color_type`, `compression`,
  `filter`, `interlace`;
- the chunk index: `chunk_type` (`Vec[Str]`), `chunk_offset`, `chunk_length`,
  `chunk_data_offset`, `chunk_crc` (parallel `Vec[Int]`);
- PLTE/tRNS state: `has_plte`, `palette` (raw bytes), `has_trns`, `trns`;
- decoded values or -1 when absent: `gamma`, `phys_x`, `phys_y`, `phys_unit`,
  `srgb_intent`;
- the text index: `text_kind`, `text_offset`, `text_length`,
  `text_keyword`, `text_value`, `text_lang`, `text_translated`,
  `text_compressed`, `text_method` (all parallel; one entry per tEXt/zTXt/iTXt
  chunk, aligned pushes only).

Accessors return `-1` (Int) or `""` (Str) when an index is out of range.
Because `chunk_type`, `png_text_keyword`, `png_text_value`,
`png_text_language` and `png_text_translated` return values read from
`Vec[Str]`, callers must compare them with
`xiom.string.compare.str_compare`, not with `==` (v0.61.3 lowers such `==` to
a pointer comparison).

## API contract

```xiom
pub fn png_signature_size() -> Int             // 8
pub fn png_chunk_header_size() -> Int          // 8
pub fn png_chunk_crc_size() -> Int             // 4
pub fn png_min_chunk_size() -> Int             // 12
pub fn png_max_chunk_length() -> Int           // 2147483647
pub fn png_text_kind_text() -> Int             // 0
pub fn png_text_kind_ztxt() -> Int             // 1
pub fn png_text_kind_itxt() -> Int             // 2

pub fn png_crc32(data: &Vec[UInt8]) -> Int
pub fn png_parse(data: &Vec[UInt8]) -> Result[PngImage, Str]
pub fn png_is_png(data: &Vec[UInt8]) -> Bool

pub fn png_width(img: &PngImage) -> Int
pub fn png_height(img: &PngImage) -> Int
pub fn png_bit_depth(img: &PngImage) -> Int
pub fn png_color_type(img: &PngImage) -> Int
pub fn png_compression(img: &PngImage) -> Int
pub fn png_filter(img: &PngImage) -> Int
pub fn png_interlace(img: &PngImage) -> Int

pub fn png_chunk_count(img: &PngImage) -> Int
pub fn png_chunk_type(img: &PngImage, i: Int) -> Str
pub fn png_chunk_offset(img: &PngImage, i: Int) -> Int
pub fn png_chunk_length(img: &PngImage, i: Int) -> Int
pub fn png_chunk_data_offset(img: &PngImage, i: Int) -> Int
pub fn png_chunk_crc(img: &PngImage, i: Int) -> Int

pub fn png_has_palette(img: &PngImage) -> Bool
pub fn png_palette_entries(img: &PngImage) -> Int
pub fn png_palette_byte(img: &PngImage, i: Int) -> Int
pub fn png_has_trns(img: &PngImage) -> Bool
pub fn png_trns_len(img: &PngImage) -> Int
pub fn png_gamma(img: &PngImage) -> Int
pub fn png_phys_x(img: &PngImage) -> Int
pub fn png_phys_y(img: &PngImage) -> Int
pub fn png_phys_unit(img: &PngImage) -> Int
pub fn png_srgb_intent(img: &PngImage) -> Int

pub fn png_text_count(img: &PngImage) -> Int
pub fn png_text_kind(img: &PngImage, i: Int) -> Int
pub fn png_text_keyword(img: &PngImage, i: Int) -> Str
pub fn png_text_value(img: &PngImage, i: Int) -> Str
pub fn png_text_language(img: &PngImage, i: Int) -> Str
pub fn png_text_translated(img: &PngImage, i: Int) -> Str
pub fn png_text_compressed(img: &PngImage, i: Int) -> Int
pub fn png_text_method(img: &PngImage, i: Int) -> Int
pub fn png_text_offset(img: &PngImage, i: Int) -> Int
pub fn png_text_length(img: &PngImage, i: Int) -> Int
```

## Test matrix

| # | Check |
|---|---|
| 1 | Minimal 1x1 gray PNG: header fields, three-chunk index, pinned offsets/lengths/data offsets, IHDR type string and stored-vs-computed CRC. |
| 2 | All 15 legal (color type, bit depth) combos parse; illegal depths (1/16/0) and color types (1/5/7) are rejected; interlace 1 decodes. |
| 3 | Empty, 7-byte and signature-only buffers; each of the 8 signature bytes mutated reports its own offset. |
| 4 | First chunk must be IHDR; IHDR length 12; duplicate IHDR; width 0 / height 0 / width 2^31; compression 1, filter 1, interlace 2. |
| 5 | CRC tampering in IHDR data, IHDR CRC field, IDAT data and IDAT CRC field, with exact CRC-offset messages. |
| 6 | Truncation inside the IHDR, inside IDAT data, at a missing CRC field; a buffer ending after IDAT is `missing IEND`; 9-byte buffer. |
| 7 | Byte after IEND; IEND with data; IHDR+IEND missing IDAT; two IDATs accepted; PLTE after IDAT. |
| 8 | Unknown chunks (zero-length, before and after IDAT) are indexed; lowercase reserved third byte and a digit type byte are rejected. |
| 9 | PLTE happy path, after IDAT, duplicate, lengths 0/2/4, forbidden for gray/gray+alpha, too large for bit depth, after tRNS, missing for indexed. |
| 10 | tRNS indexed happy path, before PLTE, too long/zero length, gray lengths, truecolor lengths, forbidden for RGBA, duplicate, after IDAT. |
| 11 | gAMA value, length 3, value 0, after PLTE, duplicate; pHYs values, length 8, unit 2; sRGB intent, length 2, intent 4, duplicate, after IDAT. |
| 12 | tEXt happy path (keyword/text/offset/length), empty text, 79/80-byte keywords, missing separator, empty keyword, control byte, NUL, TAB accepted, 0xFF accepted, 0x80 keyword rejected, text after IDAT. |
| 13 | zTXt happy path with binary payload (`png_text_value` stays `""`), method 1, missing method, missing separator, empty payload, keyword validation. |
| 14 | iTXt UTF-8 happy path, compressed flag, flag 2, method 1, missing language separator, invalid language byte, invalid translated keyword, invalid UTF-8 text, NUL in text, missing separator. |
| 15 | Accessor sentinels for every index-taking function and the contiguous chunk offset/data chains ending exactly at the buffer length. |
| 16 | Zero-length chunks: empty IDAT accepted (alone and before a data IDAT), empty text payloads, empty PLTE and empty gray tRNS rejected. |
| 17 | Constant table, `png_max_chunk_length()` = 2^31-1, 2^31-1 in a tiny buffer is truncation while 2^31 and u32-max are length overflow, standard CRC vectors (0xCBF43926 and 0). |

## Implementation notes (v0.61.3)

- `Ok`/`Err` are constructed only in the leaf helpers `_ok_img`/`_err_img`.
- Every `Vec[UInt8]` read is widened and masked: `(data[i] as Int) & 0xFF`
  (the signature starts with 0x89).
- Every `Vec[Int]`/`Vec[Str]` element read is bound to a typed local.
- `Str` values are built only from validated NUL-free ranges.
- Parallel vectors are pushed only through `_push_chunk`/`_push_text`, so
  drift is structurally impossible.
- No `Vec[Float64]`, no methods, no lambdas, no table-driven dispatch.
- Int division truncates toward zero; offsets are never formed before the
  length cap check, so no arithmetic overflow is possible.

## Known limitations

- The whole buffer must be in memory; there is no streaming parser.
- IDAT payloads are opaque: no zlib inflate, no unfiltering, no Adam7
  de-interlacing, no pixel output, no encoder.
- Unknown chunks (including invalid combinations of known private chunks)
  are indexed but not semantically audited; their payloads are not stored.
- Text byte classes are stricter than the PNG 1.2 letter in the interest of
  safe `Str` construction: NUL and control bytes other than TAB/LF/CR are
  rejected in tEXt text.
- `sRGB` and `iCCP` coexistence, chromaticity consistency checks and the
  `gAMA`-before-`sRGB` recommendation are not audited; only the ordering
  rules in this document are enforced.
