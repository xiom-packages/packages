# xiom.pptx -- specification

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

## 1. Scope

`xiom.pptx` reads and writes a **minimal PowerPoint PresentationML subset**
packaged in a self-implemented ZIP container. The module is split into three
logical libraries:

| Lib | Responsibility |
|---|---|
| `pptx-slide` | slide/shape model, integer-EMU geometry |
| `pptx-write` | ZIP writer + PresentationML part serialization |
| `pptx-read` | ZIP reader + PresentationML parsing back into the model |

Out of scope, by design: rendering, themes, fonts, colours, images, tables,
charts, notes, masters, layouts, transitions, animations, encryption,
macros, ZIP64, zip archive encryption, data descriptors and ZIP comments
beyond skipping them during the EOCD scan.

## 2. Data model

```xiom
pub type PptxPresentation = {
  width_emu: Int;
  height_emu: Int;
  slide_count: Int;
  shape_slide: Vec[Int];       // owner slide per shape
  shape_kind: Vec[Int];        // 0 = text box
  shape_x: Vec[Int];           // EMU
  shape_y: Vec[Int];           // EMU
  shape_w: Vec[Int];           // EMU, > 0
  shape_h: Vec[Int];           // EMU, > 0
  shape_text_off: Vec[Int];    // byte span into `text`
  shape_text_len: Vec[Int];
  text: Vec[UInt8];            // shared UTF-8 text pool, NUL-free
}
```

All shape vectors are kept in lockstep (same length, one push per shape);
`_pres_consistent` rejects drift before serialization. There is no
`Vec[StructType]` and no `Vec[Float64]` anywhere in the module.

**Geometry units.** EMU (English Metric Units) as `Int`: 1 inch = 914400,
1 mm = 36000, 1 point = 12700. Conversions truncate toward zero; negative
inputs keep that rule (no ceil idiom).

**Slides.** `pptx_add_slide` increments `slide_count`; shapes reference their
slide by index. Slide `N` (1-based) maps to part `ppt/slides/slideN.xml`.

**Shapes.** Only kind 0 (rectangular text box) exists. `pptx_add_text_box`
requires a valid slide index, `w > 0`, `h > 0`, and text without NUL or
XML-illegal control bytes.

**Caps.** 10000 slides, 100000 shapes, 1 MiB text per shape, 4096 ZIP
entries, 256 MiB writer payload pool, 8 MiB per decoded part, 1048576
DEFLATE blocks per stream. Exceeding a cap is an error, never a silent
truncation.

## 3. API

```
model      pptx_presentation_new(width_emu, height_emu)
           pptx_presentation_new_default()            // 12192000 x 6858000
           pptx_add_slide(&mut pres) -> Result[Int, Str]
           pptx_add_text_box(&mut pres, slide, x, y, w, h, text) -> Result[Int, Str]
accessors  pptx_slide_count, pptx_shape_count, pptx_slide_shape_count
           pptx_slide_shape(pres, slide, nth) -> Result[Int, Str]
           pptx_shape_slide/kind/x/y/width/height(pres, shape) -> Result[Int, Str]
           pptx_shape_text(pres, shape) -> Result[Str, Str]
           pptx_shape_kind_name(kind) -> Str            // "text_box" | "unknown"
           pptx_presentation_width/height(pres) -> Int
geometry   pptx_mm_to_emu, pptx_emu_to_mm, pptx_inches_to_emu,
           pptx_emu_to_inches, pptx_points_to_emu, pptx_emu_to_points
serialize  pptx_presentation_to_bytes(pres)                // method 8 (deflate)
           pptx_presentation_to_bytes_stored(pres)         // method 0 (stored)
           pptx_presentation_to_bytes_method(pres, method) // 0 or 8
parse      pptx_presentation_from_bytes(data) -> Result[PptxPresentation, Str]
zip write  zip_writer_new, zip_writer_add(&mut w, name, data, method),
           zip_writer_entry_count, zip_writer_finish(&w)
zip read   zip_read(data) -> Result[ZipArchive, Str]
           zip_entry_count/find/name/method/crc/size/compressed_size/local_offset
           zip_entry_data -> Result[Vec[UInt8], Str]
           zip_crc32(data) -> Int
inflate    zip_inflate_fixed(data, max_out) -> Result[Vec[UInt8], Str]
```

All `&mut` arguments are written explicitly at every call site.

## 4. ZIP container subset

### 4.1 Writer

For each entry, in order:

* local file header (signature `0x04034b50`, version 20, flags 0, method,
  time/date 0, CRC-32, compressed size, uncompressed size, name length,
  extra length 0, name, data);
* central directory header (`0x02014b50`, same facts, local offset);
* end-of-central-directory record (`0x06054b50`, no comment).

Methods: `0` = STORED, `8` = DEFLATE. DEFLATE payloads come from
`xiom.compress.deflate.deflate_compress_level`: level 6 (fixed-Huffman)
for inputs up to 64 KiB, level 0 (stored DEFLATE blocks) above, because the
stdlib fixed-Huffman matcher is O(n²). CRC-32 is
`xiom.compress.gzip.gzip_crc32` over the uncompressed payload.

Entry names must be non-empty, <= 255 bytes, printable ASCII without
backslash, relative and free of `..`.

### 4.2 Reader

* EOCD is located by scanning backwards up to 65557 bytes for
  `0x06054b50`; the comment length must end the file exactly.
* Central directory entries are walked sequentially with signature, bounds,
  and size checks; names are copied into a byte pool.
* For every entry the local header is re-read and cross-checked: signature,
  data-descriptor flag, method, name length and name bytes must match the
  central directory.
* Entry data is copied at parse time and decompressed on demand:
  * method 0: size equality is enforced;
  * method 8: `xiom.compress.deflate.deflate_decompress_capped` first; if
    that fails, the local `zip_inflate_fixed` decoder handles STORED and
    fixed-Huffman blocks.
* After decompression the declared uncompressed size and the stored CRC-32
  are enforced. A mismatch is an error.

**Documented limitation.** Dynamic-Huffman DEFLATE blocks (BTYPE 2) are
**not** decoded when the stdlib inflater rejects them (dynamic tables with
repeat codes 16/17/18 currently fail in `xiom.compress.deflate`). The local
fallback rejects BTYPE 2 with
`pptx: deflate: dynamic-huffman blocks unsupported`. All streams produced by
this module decompress correctly because the writer only emits fixed-Huffman
or stored blocks; most third-party writers emit dynamic blocks and are
therefore rejected for those entries.

## 5. PresentationML subset

Written parts (in this ZIP order):

| Part | Content |
|---|---|
| `[Content_Types].xml` | defaults `rels`/`xml`, overrides for presentation + each slide |
| `_rels/.rels` | `rId1` -> `ppt/presentation.xml` (officeDocument) |
| `ppt/presentation.xml` | `p:sldIdLst` (`p:sldId id=256+N r:id=rId(N+1)`), `p:sldSz`, `p:notesSz` |
| `ppt/_rels/presentation.xml.rels` | `rIdN` -> `slides/slideN.xml` (slide) |
| `ppt/slides/slideN.xml` | `p:sld` / `p:cSld` / `p:spTree` with one `p:sp` per text box |

A shape is written as `p:sp` with `p:nvSpPr` (`cNvPr id`, name
`TextBox K`), `p:spPr` (`a:xfrm`/`a:off`/`a:ext`, `a:prstGeom prst="rect"`,
`a:noFill`) and `p:txBody` (`a:p`/`a:r`/`a:t`). Text is XML-escaped
(`&amp; &lt; &gt; &quot; &apos;`); tab, LF and CR pass through; every other
control byte is rejected. Non-ASCII text is stored as UTF-8 bytes and
round-trips byte-exactly.

Reader behaviour:

* `ppt/presentation.xml` and `ppt/_rels/presentation.xml.rels` are
  mandatory; each `p:sldId r:id` must resolve to a relationship whose
  `Type` ends in `/slide`; the target is resolved relative to `ppt/`
  (or used as-is when absolute) and must not contain `..`.
* `p:sldSz` overrides the default canvas; it must have positive `cx`/`cy`.
* Every slide part is parsed: each `p:sp` must contain `a:off x/y`,
  `a:ext cx/cy` (decimal integers) and an `a:t` text node; unknown XML and
  unknown elements are ignored.
* Numeric character references (`&#...;`) are rejected: the writer never
  emits them and the subset parser does not guess.

## 6. Error cases

All errors are `Err("pptx: ...")` strings:

| Error | Trigger |
|---|---|
| `not a zip archive (no end of central directory)` | too small / no EOCD / truncated archive |
| `zip end record does not end the file` | comment length mismatch |
| `zip entry count exceeds cap` | > 4096 entries |
| `zip central directory out of bounds` / `truncated central directory` | bad offsets/sizes |
| `bad central directory signature` / `bad local header signature` | corrupt signatures |
| `zip data descriptors unsupported` | flag bit 3 set |
| `unsupported zip compression method` | method not 0/8 |
| `zip local and central methods differ` / `zip local and central names differ` | header cross-check |
| `zip entry data out of bounds` / `stored entry size mismatch` | size/offset violations |
| `zip entry uncompressed size mismatch` / `zip entry crc mismatch` | payload integrity |
| `dynamic-huffman blocks unsupported` | BTYPE 2 with stdlib decode failure |
| `deflate: ...` | malformed STORED/fixed stream in the local inflater |
| `missing part ppt/presentation.xml` / `...presentation.xml.rels` | absent required parts |
| `not a presentationml presentation part` / `...slide part` | root element mismatch |
| `missing slide part <path>` | rels point at an absent part |
| `sldId references unknown relationship` | dangling `r:id` |
| `relationship target escapes package` | `..` in target |
| `malformed integer attribute` / `integer attribute out of range` | geometry attrs |
| `shape missing a:off/a:ext/a:t text` / `unterminated shape element` | malformed shape |
| `unsupported xml entity` / `control character in xml text` | text decoding |
| `part contains control byte` / `part contains NUL byte` | whole-part validation |
| `slide index out of range` / `shape index out of range` | model accessors |
| `shape size must be positive` / `text contains control character` / `text exceeds size cap` | model input validation |
| `slide limit reached` / `shape limit reached` / `zip entry limit reached` | caps |

## 7. Verification

`tests/test_conformance.xi` (26 checks, no external files) covers the model,
geometry, both entry methods, ZIP structure, CRC/method tampering, the local
inflater (fixed, stored, dynamic rejection), escaping and UTF-8 round trips,
and the parse error cases listed above.
