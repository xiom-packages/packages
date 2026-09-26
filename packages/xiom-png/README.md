# xiom.png

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (17/17); NOT published yet.
> **Scope:** PNG (W3C PNG 1.2) container parsing and validation: signature, chunk stream, CRC-32, IHDR, PLTE, tRNS, gAMA, pHYs, sRGB, tEXt/zTXt/iTXt and IEND. Structure only; pixels and image data are never decoded.
> **Deps:** `xiom.std` only (`xiom.string.builder`, `xiom.convert`). No FFI in v0.1.

## What it is

`xiom.png` is a pure-XIOM container codec for the Portable Network Graphics
format. It works on flat `Vec[UInt8]` buffers and validates:

- the 8-byte signature `89 50 4E 47 0D 0A 1A 0A`;
- the chunk grammar `BE32(length) type[4] data[length] BE32(crc32(type data))`;
- every chunk CRC-32 (IEEE, polynomial `0xEDB88320`, implemented locally, no
  table);
- the critical chunks `IHDR`, `IDAT`, `PLTE` and `IEND`, and the ancillary
  chunks `tRNS`, `gAMA`, `pHYs`, `sRGB`, `tEXt`, `zTXt` and `iTXt`;
- chunk ordering (`IHDR` first and once, `PLTE` before `IDAT`, `tRNS` after
  `PLTE`, `gAMA`/`sRGB` before `PLTE`/`IDAT`, `pHYs` before `IDAT`, `IEND`
  last with nothing after it);
- the IHDR field grammar: dimensions, color type, bit depth, compression,
  filter and interlace, including the legal (color type, bit depth) matrix;
- text encoding before any `Str` is built: keywords and tEXt text must be
  printable NUL-free Latin-1, iTXt text and translated keywords must be
  strict RFC 3629 UTF-8 with no NUL, and zTXt/compressed iTXt payloads are
  never turned into strings.

Unknown chunk types are structurally validated (letters, reserved bit,
length cap, CRC) and indexed, but never interpreted. `IDAT` payloads are
opaque: no zlib inflation, no filtering, no interlace handling, no pixels.

## Format notes

| Part | Bytes | Encoding |
|---|---|---|
| signature | 0..7 | `89 50 4E 47 0D 0A 1A 0A` |
| chunk length | +0..3 | unsigned 32-bit big-endian, at most 2^31-1 |
| chunk type | +4..7 | four ASCII letters, third letter uppercase |
| chunk data | +8.. | `length` bytes |
| chunk CRC | +8+length | CRC-32 of type+data, big-endian |

Chunk CRC-32 is the standard IEEE/zlib CRC: init `0xFFFFFFFF`, reflected
polynomial `0xEDB88320`, final XOR `0xFFFFFFFF`. The check value of
`"123456789"` is `0xCBF43926` (`3421780262`); the empty buffer hashes to `0`.

## Chunk support

| Chunk | Role | Rules enforced |
|---|---|---|
| `IHDR` | header | first chunk, exactly once, length 13, dimensions 1..2^31-1, legal color type/bit depth, compression 0, filter 0, interlace 0/1 |
| `PLTE` | palette | once, length 3..768 and a multiple of 3, not for color types 0/4, before `IDAT` and after `tRNS`, entries <= 2^bit_depth for color type 3, required for color type 3 |
| `IDAT` | image data | at least one, before `IEND`, payload opaque (multiple IDATs accepted, not required to be adjacent) |
| `IEND` | terminator | exactly 12 bytes, zero-length, last chunk, no bytes after it |
| `tRNS` | transparency | once, before `IDAT`, after `PLTE` for color type 3; length 2 (gray), 6 (truecolor) or 1..palette entries (indexed); forbidden for color types 4/6 |
| `gAMA` | gamma | once, length 4, non-zero, before `PLTE` and `IDAT` |
| `pHYs` | pixel size | once, length 9, unit 0/1, before `IDAT` |
| `sRGB` | color space | once, length 1, intent 0..3, before `PLTE` and `IDAT` |
| `tEXt` | text | keyword 1..79 printable Latin-1 bytes, NUL separator, NUL-free printable text |
| `zTXt` | compressed text | same keyword rules, compression method must be 0; compressed bytes kept raw and never inflated |
| `iTXt` | UTF-8 text | keyword, flag 0/1, method 0, printable-ASCII language tag, UTF-8 translated keyword, UTF-8 text (when uncompressed) |

## API

| Function | Returns | Description |
|---|---|---|
| `png_parse(data)` | `Result[PngImage, Str]` | Full structural validation; returns header fields, a chunk index, the raw PLTE/tRNS payloads, decoded gAMA/pHYs/sRGB values and a text index. |
| `png_is_png(data)` | `Bool` | Signature check only. |
| `png_crc32(data)` | `Int` | Standard CRC-32 over a whole buffer (0..4294967295). |
| `png_width` / `png_height` | `Int` | Validated IHDR dimensions. |
| `png_bit_depth` / `png_color_type` | `Int` | Validated IHDR bytes. |
| `png_compression` / `png_filter` / `png_interlace` | `Int` | Always 0 / 0 / 0 or 1. |
| `png_chunk_count(img)` | `Int` | Number of chunks in the index. |
| `png_chunk_type(img, i)` | `Str` | 4-letter type, `""` out of range (compare with `str_compare`). |
| `png_chunk_offset` / `png_chunk_length` / `png_chunk_data_offset` / `png_chunk_crc` | `Int` | Absolute offsets, declared length and verified CRC; -1 out of range. |
| `png_has_palette` / `png_palette_entries` / `png_palette_byte(img, i)` | `Bool`/`Int` | PLTE presence, entry count and raw byte (`-1` out of range). |
| `png_has_trns` / `png_trns_len` | `Bool`/`Int` | tRNS presence and raw length. |
| `png_gamma` / `png_phys_x` / `png_phys_y` / `png_phys_unit` / `png_srgb_intent` | `Int` | Decoded values, `-1` when the chunk is absent. |
| `png_text_count(img)` | `Int` | Number of tEXt/zTXt/iTXt entries. |
| `png_text_kind(img, i)` | `Int` | 0 tEXt, 1 zTXt, 2 iTXt, `-1` out of range. |
| `png_text_keyword` / `png_text_value` / `png_text_language` / `png_text_translated` | `Str` | Validated strings (`""` out of range or not applicable; compressed payloads yield `""`). |
| `png_text_compressed` / `png_text_method` | `Int` | Stored flag and method; `-1` out of range. |
| `png_text_offset` / `png_text_length` | `Int` | Raw chunk data span; `-1` out of range. |
| `png_signature_size` / `png_chunk_header_size` / `png_chunk_crc_size` / `png_min_chunk_size` / `png_max_chunk_length` | `Int` | 8 / 8 / 4 / 12 / 2147483647. |
| `png_text_kind_text` / `png_text_kind_ztxt` / `png_text_kind_itxt` | `Int` | 0 / 1 / 2. |

## Usage

```xiom
use xiom.png;

match png_parse(bytes) {
  Ok(img) => {
    // Validated IHDR.
    let w = png_width(&img);
    let h = png_height(&img);
    let px = png_color_type(&img);        // 0, 2, 3, 4 or 6

    // Chunk index: IHDR .. IEND in stream order.
    var i = 0;
    while (i < png_chunk_count(&img)) {
      let t: Str = png_chunk_type(&img, i);
      // Compare with str_compare, never == on a Vec[Str] element.
      i = i + 1;
    }

    if (png_has_palette(&img)) {
      let entries = png_palette_entries(&img);
    }
    if (png_text_count(&img) > 0) {
      let kw: Str = png_text_keyword(&img, 0);
      let v: Str = png_text_value(&img, 0);   // "" for zTXt / compressed iTXt
    }
  },
  Err(e) => { /* png: bad signature at 3, png: crc mismatch at 29, ... */ },
}

// CRC-32 helper (same primitive the parser uses).
let crc = png_crc32(chunk_type_and_data);
```

## Error model

Every failure is `Err(Str)` with a deterministic message; structural and
ordering failures carry the absolute byte offset of the offending field.

| Message | Condition |
|---|---|
| `png: truncated signature` | Fewer than 8 bytes. |
| `png: bad signature at <n>` | Byte `n` of the signature mismatches. |
| `png: truncated chunk at <n>` | Fewer than 12 bytes remain, or the declared data/CRC runs past the buffer, or fewer than 20 bytes total (no room for a chunk). |
| `png: chunk length overflow at <n>` | Declared data length above 2^31-1. |
| `png: invalid chunk type at <n>` | Type bytes are not A-Z/a-z, or the reserved bit (third byte uppercase) is set. |
| `png: crc mismatch at <n>` | Stored CRC-32 differs from the computed CRC; `n` is the CRC field offset. |
| `png: missing IHDR at 8` / `png: duplicate IHDR at <n>` | First chunk is not IHDR / a second IHDR appears. |
| `png: invalid IHDR length at <n>` | IHDR data length is not 13. |
| `png: invalid width at <n>` / `png: invalid height at <n>` | Dimension is 0 or above 2^31-1. |
| `png: invalid color type at <n>` | Color type is not 0, 2, 3, 4 or 6. |
| `png: invalid bit depth at <n>` | Bit depth is not legal for the color type. |
| `png: invalid compression method` / `filter method` / `interlace method` at `<n>` | Field is not 0 / 0 / 0 or 1. |
| `png: PLTE ...` / `png: tRNS ...` / `png: gAMA ...` / `png: pHYs ...` / `png: sRGB ...` | Per-chunk length, allowance, ordering, duplicate and value rules; see SPEC.md. |
| `png: missing PLTE` | Color type 3 without any PLTE. |
| `png: missing keyword separator at <n>` | A text chunk has no NUL after its keyword. |
| `png: invalid text keyword at <n>` | Keyword is empty, longer than 79 bytes or non-printable. |
| `png: invalid text at <n>` | tEXt text is not NUL-free printable Latin-1, or iTXt text is not strict UTF-8. |
| `png: invalid zTXt method at <n>` | zTXt compression method is not 0. |
| `png: invalid iTXt flag at <n>` / `method` / `language tag` / `translated keyword` | iTXt field rules. |
| `png: invalid IEND length at <n>` | IEND data length is not 0. |
| `png: data after IEND at <n>` | Bytes follow a complete IEND chunk. |
| `png: missing IEND` / `png: missing IDAT` | No terminator / no image data. |

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.png
```

17 conformance tests build every fixture in-test (no external data files):
minimal 1x1 parse with pinned offsets and CRCs; all 15 legal color-type/bit
depth combos plus six illegal ones; every signature byte; IHDR position,
length, duplicate, zero/overflow dimensions and method bytes; CRC tampering
on IHDR and IDAT; truncation, oversize length and missing terminators; IEND
and ordering rules; unknown chunks and invalid type bytes; PLTE, tRNS, gAMA,
pHYs and sRGB matrices; tEXt/zTXt/iTXt happy paths and malformed encodings;
the accessor sentinel table and the contiguous chunk-offset chain;
zero-length chunk policy; and the 2^31-1 length guard plus standard CRC
vectors.

## Limitations

- Parse-only: there is no PNG encoder/builder in v0.1.
- No pixel decode: IDAT bytes are opaque (no zlib inflate, no unfiltering,
  no Adam7 de-interlacing) and no image dimensions are derived from them.
- No ICC profiles (`iCCP`), `cHRM`, `bKGD`, `sBIT`, `sPLT`, `hIST`, `tIME`,
  `iTXt` inflation or APNG chunks; those are indexed only when they are valid
  unknown chunks.
- Stricter than the PNG 1.2 letter in documented places: text strings must be
  NUL-free and printable (no other C0 controls besides TAB/LF/CR), `gAMA`
  value 0 is rejected, and chunk data lengths above 2^31-1 are rejected
  before any buffer arithmetic.
- The whole buffer must be in memory; there is no streaming parser.
- `Vec[StructType]` is not used (v0.61.3 limitation): results are exposed as
  parallel `Vec` fields plus accessor functions.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
