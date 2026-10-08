# xiom.webp SPEC

Version: 0.1.2 (stable; published on the XIOM registry).

## Scope

Pure-XIOM parsing and validation of the WebP (RIFF) container over flat
`Vec[UInt8]` buffers. The parser walks the chunk stream, validates the file
header, every chunk's declared size, fourcc and padding, the VP8/VP8L
uncompressed headers, the VP8X extended header, the ALPH/ANIM/ANMF structure
and the ICCP/EXIF/XMP presence and sizes. Parsed results are exposed as one
`WebpImage` value with a top-level chunk index and a per-frame index built
from parallel `Vec` fields (no `Vec[StructType]`); no pixel, alpha-plane or
metadata payload is ever decoded.

## Non-goals

No VP8 or VP8L bitstream decode (no coefficient, prediction, filter or
entropy decoding), no alpha-plane decode, no ICC profile parsing, no Exif or
XMP parsing, no canvas rendering or frame composition, no encoding, no
conversion to or from PNG/JPEG/GIF, no streaming or incremental parse, no
FFI, no Float64.

## File layout

```
offset  size  field
0       4     "RIFF" (ASCII 82 73 70 70)
4       4     file size, unsigned 32-bit little-endian
8       4     "WEBP" (ASCII 87 69 66 80)
12      ...   chunk stream, to the end of the buffer
```

`file size` counts the bytes starting at offset 8, so the buffer length must
be exactly `file size + 8`. A buffer whose declared size does not equal its
length is rejected (`webp: riff size mismatch at 4`); trailing data after the
declared size is therefore rejected rather than ignored.

```
chunk := fourcc[4] size(u32 LE) payload[size] pad[1 when size is odd]
```

The chunk size does not include the header or the padding. An odd-size chunk
must be followed by exactly one padding byte whose value is `0`; a missing
padding byte is `webp: truncated padding at <offset>` and a non-zero one is
`webp: invalid padding byte at <offset>`. Every fourcc byte must be printable
ASCII `0x20..0x7E`; anything else is `webp: invalid FourCC at <offset>`.
The fourcc is exposed as a `Str` (only after the printable check, so a NUL
can never truncate it).

## Chunk catalogue

| Fourcc | Kind code | Payload | Validation |
|---|---|---|---|
| `VP8 ` | 1 | lossy bitstream | minimum length 10, start code, key frame, version 0..3, partition fits, non-zero 14-bit dimensions |
| `VP8L` | 2 | lossless bitstream | minimum length 5, `0x2F` signature, version 0 |
| `VP8X` | 3 | extended header, exactly 10 bytes | reserved bits/bytes zero, canvas product <= 2^32-1 |
| `ALPH` | 4 | alpha sub-chunk | minimum length 1, at most one, before the image bitstream |
| `ANIM` | 5 | animation parameters, exactly 6 bytes | at most one, before the first frame |
| `ANMF` | 6 | animation frame, minimum 16 bytes | reserved bits zero, frame inside the canvas, nested sub-chunks padded, exactly one bitstream |
| `ICCP` | 7 | color profile | at most one, before the image data |
| `EXIF` | 8 | Exif metadata | at most one |
| `XMP ` | 9 | XMP metadata | at most one |
| any other | 0 | opaque | recorded in the chunk index; payload never copied or interpreted |

## VP8X (extended header)

```
offset  size  field
0       1     flags
1       3     reserved, MUST be 0
4       3     canvas width - 1, u24 LE
7       3     canvas height - 1, u24 LE
```

Flags byte, bit numbering MSB-first as in the container specification:

| Bit (MSB 0) | Mask | Meaning |
|---|---|---|
| 0..1 | `0xC0` | reserved, MUST be 0 |
| 2 | `0x20` | I: file contains an `ICCP` chunk |
| 3 | `0x10` | L: some frame contains transparency |
| 4 | `0x08` | E: file contains Exif metadata (`EXIF`) |
| 5 | `0x04` | X: file contains XMP metadata (`XMP `) |
| 6 | `0x02` | A: animated file (`ANIM` + `ANMF` are used) |
| 7 | `0x01` | reserved, MUST be 0 |

Reserved bits (`flags & 0xC1`) and non-zero reserved bytes are rejected.
The canvas is `canvas width - 1 + 1` by `canvas height - 1 + 1`, so each
dimension is 1..16,777,216; the product must not exceed `2^32 - 1`. `VP8X`
must be the first chunk of the file (any preceding chunk, known or unknown,
is `webp: VP8X not first`); a second `VP8X` is a duplicate.

## VP8 (lossy bitstream)

The parser reads only the uncompressed header of the frame:

```
offset  size  field
0       3     frame tag, u24 LE
              bit 0: key-frame flag (0 = key frame, 1 = inter-frame)
              bits 1..3: version (0..3 valid, 4..7 reserved)
              bit 4: show-frame flag
              bits 5..23: first-partition size in bytes
3       3     start code, exactly 0x9D 0x01 0x2A
6       2     width:  14 bits width, 2 bits horizontal scale (u16 LE)
8       2     height: 14 bits height, 2 bits vertical scale (u16 LE)
```

Checks: payload length >= 10 (`webp: invalid VP8 length`), start code
(`webp: invalid VP8 start code`), key-frame bit 0 (`webp: invalid VP8 frame
tag`), version <= 3 (`webp: invalid VP8 version`),
`10 + first-partition-size <= payload size` (`webp: invalid VP8 partition
size`), and both 14-bit dimensions non-zero (`webp: invalid VP8 dimensions`).
The show-frame bit and the two 2-bit scale fields are recorded (scale bits
are ignored) but not rejected; no coefficient or macroblock data is touched.

## VP8L (lossless bitstream)

```
offset  size  field
0       1     signature, exactly 0x2F
1       4     bit field, u32 LE
              bits 0..13:  width - 1
              bits 14..27: height - 1
              bit 28:      alpha-is-used hint
              bits 29..31: version, MUST be 0
```

Checks: payload length >= 5 (`webp: invalid VP8L length`), the `0x2F`
signature (`webp: invalid VP8L signature`), version 0 (`webp: invalid VP8L
version`). The width and height are `field + 1`, so each is 1..16,384. The
alpha hint is informational and recorded as-is. No image stream is decoded.

## ALPH (alpha sub-chunk)

An opaque payload of at least 1 byte (the first byte carries the reserved,
pre-processing, filtering and compression method fields). The parser records
presence, fourcc offset and size only; the method fields and the alpha
bitstream are never interpreted. At most one top-level `ALPH` may appear and
it must precede the top-level image chunk. Inside an `ANMF` frame at most one
`ALPH` may appear and it must precede the frame bitstream. A frame whose
bitstream is `VP8L` may still carry `ALPH` (the container specification says
SHOULD NOT, not MUST), which is accepted and documented.

## ANIM (animation parameters)

```
offset  size  field
0       4     background color, [Blue, Green, Red, Alpha] byte order
4       2     loop count, u16 LE (0 = loop forever)
```

Exactly 6 bytes, at most one per file, and it must appear before the first
`ANMF`. The background color is exposed as a raw LE32 plus four byte
accessors.

## ANMF (animation frame)

```
offset  size  field
0       3     frame X, u24 LE (pixel X = value * 2)
3       3     frame Y, u24 LE (pixel Y = value * 2)
6       3     frame width - 1, u24 LE
9       3     frame height - 1, u24 LE
12      3     duration in milliseconds, u24 LE
15      1     flags: 6 reserved bits MUST be 0, bit 1 = blending method B,
              bit 0 = disposal method D
16      ...   frame data: padded sub-chunks
```

Checks: payload length >= 16 (`webp: invalid ANMF length`), reserved bits
`flags & 0xFC == 0` (`webp: reserved ANMF bits`), and, when a `VP8X` canvas
is known, `frame X * 2 + frame width <= canvas width` and the analogous
vertical bound (`webp: frame outside canvas`). The frame X/Y values are
exposed in pixels (already multiplied by 2); width and height are stored
values + 1; the duration is milliseconds.

Frame data is a nested RIFF sub-chunk stream, each nested chunk padded to an
even boundary with a zero pad byte, walked from payload offset 16 to the end
of the `ANMF` payload:

* at most one `ALPH`, before the bitstream (`webp: duplicate frame alpha`,
  `webp: frame alpha after image`, `webp: invalid ALPH length` when empty);
* exactly one `VP8 ` or `VP8L` bitstream (`webp: multiple frame image
  chunks`, `webp: ANMF missing image data` when none is present), validated
  with the same VP8/VP8L rules above;
* any other fourcc is an opaque nested unknown chunk: counted per frame but
  never copied or interpreted.

Nested truncation is `webp: truncated frame chunk at <offset>`, nested
padding errors use the same messages as top-level chunks. No nested
bitstream is decoded.

## ICCP / EXIF / XMP

Opaque payloads: presence, fourcc offset and size are exposed, nothing is
interpreted. Each may appear at most once (`webp: duplicate ICCP`, `webp:
duplicate EXIF`, `webp: duplicate XMP`). `ICCP` must appear before the image
data (`webp: ICCP after image data`); `EXIF` and `XMP ` may appear in any
position after the extended header, matching the container rule that metadata
chunks MAY appear out of order. A zero-length payload is accepted.

## Unknown chunks

A chunk whose fourcc is not in the catalogue is recorded in the top-level
chunk index with kind 0 and its fourcc, offsets, size and padding state, and
is never interpreted. The declared size must fit the enclosing stream and the
fourcc must be printable ASCII, so the work and the memory are bounded by the
input length (each chunk consumes at least 8 bytes). Unknown nested chunks
inside `ANMF` are counted per frame (`frame_nested_count`,
`frame_unknown_count`) and likewise ignored. Position is not restricted: an
unknown chunk may appear anywhere, including before `VP8X` (which then fails
with `webp: VP8X not first`, since `VP8X` must be the first chunk).

## Validation order

`webp_parse` applies, in order:

1. buffer length below 4 -> `webp: truncated header at 0`;
2. bytes 0..3 not `RIFF` -> `webp: bad magic at <first mismatch>`;
3. buffer length below 12 -> `webp: truncated header at 0`;
4. bytes 8..11 not `WEBP` -> `webp: bad magic at <first mismatch>`;
5. declared size + 8 != buffer length -> `webp: riff size mismatch at 4`;
6. chunk walk from offset 12 while the cursor is below the buffer length:
   * header or payload beyond the buffer -> `webp: truncated chunk at <offset>`;
   * non-printable fourcc byte -> `webp: invalid FourCC at <offset>`;
   * odd size without a padding byte -> `webp: truncated padding at <offset>`;
   * non-zero padding byte -> `webp: invalid padding byte at <offset>`;
   * per-kind validation (VP8X, VP8, VP8L, ALPH, ANIM, ANMF, ICCP, EXIF,
     XMP) as documented above; the index record is appended only after the
     chunk validates;
7. post-walk consistency:
   * no `VP8X`: any of `ALPH`/`ICCP`/`EXIF`/`XMP `/`ANIM`/`ANMF` present ->
     `webp: metadata chunk without VP8X at <offset>` (checked in that order);
     no image chunk -> `webp: missing image data at 12`;
   * `VP8X` animation flag set: missing `ANIM` -> `webp: animation flag
     without ANIM at <vp8x offset>`, no frames -> `webp: animation without
     frames at <anim offset>`, top-level image -> `webp: image chunk in
     animation at <image offset>`, top-level `ALPH` -> `webp: ALPH chunk in
     animation at <alph offset>`;
   * `VP8X` animation flag clear: `ANIM` present -> `webp: animation chunk
     without flag at <anim offset>`, frames present -> `webp: animation
     frame without flag at <first frame offset>`, no image -> `webp: missing
     image data at 12`, then flag/chunk agreement: `ICCP` without the ICC
     bit -> `webp: ICCP without ICC flag at <iccp offset>`, ICC bit without
     `ICCP` -> `webp: ICC flag without ICCP at <vp8x offset>`, the same pair
     for EXIF and XMP, `ALPH` without the alpha bit -> `webp: ALPH without
     alpha flag at <alph offset>`, and alpha bit with a `VP8 ` image and no
     `ALPH` -> `webp: alpha flag without ALPH at <vp8x offset>` (a `VP8L`
     image carries its alpha internally, so the flag without `ALPH` is
     accepted there).

All offsets in messages are absolute buffer offsets; `<offset>` for chunk
errors is the fourcc offset, for padding errors the padding byte offset, and
for payload-content errors the payload (data) offset. Length errors report
the payload offset as well.

## Error catalog

| Message | Condition |
|---|---|
| `webp: truncated header at 0` | fewer than 12 bytes (or fewer than 4 with any content) |
| `webp: bad magic at <off>` | wrong byte in `RIFF` (0..3) or `WEBP` (8..11) |
| `webp: riff size mismatch at 4` | declared size + 8 != buffer length |
| `webp: truncated chunk at <off>` | chunk header or payload runs past the buffer |
| `webp: invalid FourCC at <off>` | a fourcc byte is outside 0x20..0x7E |
| `webp: truncated padding at <off>` | odd-size chunk without its padding byte |
| `webp: invalid padding byte at <off>` | padding byte is not 0 |
| `webp: duplicate VP8X at <off>` | second `VP8X` |
| `webp: VP8X not first at <off>` | `VP8X` after any other chunk |
| `webp: invalid VP8X length at <off>` | `VP8X` payload size != 10 |
| `webp: reserved VP8X bits at <off>` | `flags & 0xC1 != 0` |
| `webp: reserved VP8X bytes at <off>` | one of the three reserved bytes != 0 |
| `webp: canvas too large at <off>` | canvas product above 2^32 - 1 |
| `webp: invalid VP8 length at <off>` | VP8 payload shorter than 10 bytes |
| `webp: invalid VP8 start code at <off>` | bytes 3..5 not 0x9D 0x01 0x2A |
| `webp: invalid VP8 frame tag at <off>` | key-frame flag not 0 (inter frame) |
| `webp: invalid VP8 version at <off>` | version bits 4..7 |
| `webp: invalid VP8 partition size at <off>` | `10 + partition` exceeds the payload |
| `webp: invalid VP8 dimensions at <off>` | 14-bit width or height is 0 |
| `webp: invalid VP8L length at <off>` | VP8L payload shorter than 5 bytes |
| `webp: invalid VP8L signature at <off>` | first byte not 0x2F |
| `webp: invalid VP8L version at <off>` | version bits not 0 |
| `webp: duplicate ALPH at <off>` | second top-level `ALPH` |
| `webp: invalid ALPH length at <off>` | empty `ALPH` payload |
| `webp: ALPH after image at <off>` | top-level `ALPH` after the image chunk |
| `webp: duplicate ANIM at <off>` | second `ANIM` |
| `webp: ANIM after ANMF at <off>` | `ANIM` after the first frame |
| `webp: invalid ANIM length at <off>` | `ANIM` payload size != 6 |
| `webp: invalid ANMF length at <off>` | `ANMF` payload shorter than 16 bytes |
| `webp: reserved ANMF bits at <off>` | `flags & 0xFC != 0` |
| `webp: frame outside canvas at <off>` | frame rectangle exceeds the canvas |
| `webp: truncated frame chunk at <off>` | nested sub-chunk runs past the frame payload |
| `webp: duplicate frame alpha at <off>` | second nested `ALPH` |
| `webp: frame alpha after image at <off>` | nested `ALPH` after the bitstream |
| `webp: multiple frame image chunks at <off>` | second nested VP8/VP8L |
| `webp: ANMF missing image data at <off>` | frame without a nested bitstream |
| `webp: duplicate ICCP at <off>` | second `ICCP` |
| `webp: ICCP after image data at <off>` | `ICCP` after the image chunk |
| `webp: duplicate EXIF at <off>` | second `EXIF` |
| `webp: duplicate XMP at <off>` | second `XMP ` |
| `webp: multiple image chunks at <off>` | second top-level VP8/VP8L |
| `webp: metadata chunk without VP8X at <off>` | ALPH/ICCP/EXIF/XMP/ANIM/ANMF in a simple file |
| `webp: missing image data at 12` | no image chunk (and, for extended, no frame) |
| `webp: image chunk in animation at <off>` | top-level image in an animated file |
| `webp: ALPH chunk in animation at <off>` | top-level `ALPH` in an animated file |
| `webp: animation flag without ANIM at <off>` | animation bit but no `ANIM` |
| `webp: animation without frames at <off>` | animation bit and `ANIM` but no `ANMF` |
| `webp: animation chunk without flag at <off>` | `ANIM` but animation bit clear |
| `webp: animation frame without flag at <off>` | `ANMF` but animation bit clear |
| `webp: ICCP without ICC flag at <off>` | `ICCP` present, ICC bit clear |
| `webp: ICC flag without ICCP at <off>` | ICC bit set, no `ICCP` |
| `webp: EXIF without EXIF flag at <off>` | `EXIF` present, EXIF bit clear |
| `webp: EXIF flag without EXIF at <off>` | EXIF bit set, no `EXIF` |
| `webp: XMP without XMP flag at <off>` | `XMP ` present, XMP bit clear |
| `webp: XMP flag without XMP at <off>` | XMP bit set, no `XMP ` |
| `webp: ALPH without alpha flag at <off>` | top-level `ALPH`, alpha bit clear |
| `webp: alpha flag without ALPH at <off>` | alpha bit set, `VP8 ` image, no `ALPH` |

## Container kinds

| Kind | Code | Layout |
|---|---|---|
| simple | 0 | no `VP8X`; exactly one top-level `VP8 `/`VP8L`; canvas = image dimensions |
| extended | 1 | `VP8X` with the animation bit clear; one top-level `VP8 `/`VP8L`; canvas from `VP8X` |
| animated | 2 | `VP8X` with the animation bit set; `ANIM` plus one or more `ANMF`; canvas from `VP8X`; no top-level image or `ALPH` |

For extended static files the canvas dimensions are taken from `VP8X` and the
image dimensions from the bitstream header; the parser records both but does
not require them to be equal. Frame rectangles are required to fit the canvas.

## Public API contract

```xiom
pub type WebpImage = {
  kind: Int; size: Int; riff_size: Int;
  has_vp8x: Int; vp8x_offset: Int; flags: Int;
  flag_icc: Int; flag_alpha: Int; flag_exif: Int; flag_xmp: Int; flag_animation: Int;
  canvas_width: Int; canvas_height: Int;
  has_image: Int; image_format: Int; image_offset: Int; image_data_offset: Int;
  image_size: Int; image_width: Int; image_height: Int;
  vp8_version: Int; vp8_show_frame: Int; vp8_first_part_size: Int;
  vp8l_alpha: Int; vp8l_version: Int;
  has_alph: Int; alph_offset: Int; alph_size: Int;
  has_iccp: Int; iccp_offset: Int; iccp_size: Int;
  has_exif: Int; exif_offset: Int; exif_size: Int;
  has_xmp: Int; xmp_offset: Int; xmp_size: Int;
  has_anim: Int; anim_offset: Int; anim_background: Int; anim_loop_count: Int;
  chunk_fourcc: Vec[Str]; chunk_offset: Vec[Int]; chunk_size: Vec[Int];
  chunk_data_offset: Vec[Int]; chunk_padding: Vec[Int]; chunk_kind: Vec[Int];
  frame_x: Vec[Int]; frame_y: Vec[Int]; frame_width: Vec[Int]; frame_height: Vec[Int];
  frame_duration: Vec[Int]; frame_blend: Vec[Int]; frame_dispose: Vec[Int];
  frame_offset: Vec[Int]; frame_size: Vec[Int]; frame_format: Vec[Int];
  frame_data_offset: Vec[Int]; frame_data_size: Vec[Int];
  frame_has_alpha: Vec[Int]; frame_nested_count: Vec[Int]; frame_unknown_count: Vec[Int];
}

pub fn webp_parse(data: &Vec[UInt8]) -> Result[WebpImage, Str]
pub fn webp_is_webp(data: &Vec[UInt8]) -> Bool

pub fn webp_header_size() -> Int                 // 12
pub fn webp_chunk_header_size() -> Int           // 8
pub fn webp_vp8x_size() -> Int                   // 10
pub fn webp_anim_size() -> Int                   // 6
pub fn webp_anmf_header_size() -> Int            // 16
pub fn webp_max_canvas_dimension() -> Int        // 16777216
pub fn webp_max_dimension_14() -> Int            // 16384
pub fn webp_kind_simple() -> Int                 // 0
pub fn webp_kind_extended() -> Int               // 1
pub fn webp_kind_animated() -> Int               // 2
pub fn webp_chunk_other() -> Int                 // 0
pub fn webp_chunk_vp8() -> Int                   // 1
pub fn webp_chunk_vp8l() -> Int                  // 2
pub fn webp_chunk_vp8x() -> Int                  // 3
pub fn webp_chunk_alph() -> Int                  // 4
pub fn webp_chunk_anim() -> Int                  // 5
pub fn webp_chunk_anmf() -> Int                  // 6
pub fn webp_chunk_iccp() -> Int                  // 7
pub fn webp_chunk_exif() -> Int                  // 8
pub fn webp_chunk_xmp() -> Int                   // 9
pub fn webp_format_none() -> Int                 // 0
pub fn webp_format_vp8() -> Int                  // 1
pub fn webp_format_vp8l() -> Int                 // 2
pub fn webp_mask_icc() -> Int                    // 0x20
pub fn webp_mask_alpha() -> Int                  // 0x10
pub fn webp_mask_exif() -> Int                   // 0x08
pub fn webp_mask_xmp() -> Int                    // 0x04
pub fn webp_mask_animation() -> Int              // 0x02
pub fn webp_mask_reserved() -> Int               // 0xC1
pub fn webp_mask_anmf_reserved() -> Int          // 0xFC
```

Semantics:

- `webp_is_webp` checks only the 12-byte `RIFF`/`WEBP` header (no size
  validation, no chunk walk).
- `webp_parse` never materializes pixels or metadata; it validates the
  structure and returns the index. `kind` is derived after all post-walk
  checks pass.
- `webp_size` is the input length and `webp_riff_size` the declared field
  (always `webp_size - 8` on success).
- `webp_image_offset` is the fourcc offset; `webp_image_data_offset` the
  payload offset; `webp_image_size` the payload size. All are -1 when there
  is no top-level image (always the case in animated files).
- Chunk accessors return -1 (Int) or "" (Str) outside
  `[0, webp_chunk_count())`; the returned fourcc must be compared with
  `xiom.string.compare.str_compare`, never with `==`.
- Frame accessors return -1 outside `[0, webp_frame_count())`.
  `frame_offset` is the `ANMF` chunk fourcc offset, `frame_size` the `ANMF`
  payload size, `frame_data_offset`/`frame_data_size` the nested bitstream
  payload location. `frame_format` is 1 VP8 or 2 VP8L.
- Absent optional values use -1 as sentinel (`vp8_version`, `vp8l_alpha`,
  `iccp_size`, `anim_offset`, ...). `anim_loop_count` 0 means "loop forever".

## Test matrix

| # | Check |
|---|---|
| 1 | Minimal lossy file: header, riff size, kind simple, canvas from image, VP8 fields, chunk index and offsets. |
| 2 | Minimal lossless file: VP8L dims, alpha hint, version, odd-size padding flag, absent VP8 fields as -1. |
| 3 | Unknown `XYZW` chunk kept opaque; odd-size padding advances the walk to the next chunk exactly. |
| 4 | Header validation order: empty, 3-byte, 8-byte, bad `RIFF` byte, bad `WEBP` byte, small and large declared size. |
| 5 | Truncated chunk header, truncated payload, missing padding byte, non-printable fourcc. |
| 6 | Non-zero padding byte rejected; zero padding byte accepted. |
| 7 | VP8: short payload, bad start code, inter frame, reserved version, zero dimension, oversized partition. |
| 8 | VP8L: short payload, bad signature, non-zero version, 16384x16384 maximum, 1x1 minimum. |
| 9 | Full extended static file: VP8X, ICCP, ALPH, VP8, EXIF, XMP with exact offsets/sizes/padding. |
| 10 | Extended VP8L file with a trailing unknown chunk (opaque, exact offsets). |
| 11 | VP8X: wrong length, reserved flag bit, reserved byte, canvas product cap (65535x65536 boundary accepted, 65536x65536 rejected), duplicate, not-first. |
| 12 | VP8X flag/chunk agreement in both directions for ICC, EXIF, XMP, alpha; VP8L alpha without ALPH accepted. |
| 13 | Animated file: ANIM background/loop, two frames with full per-frame metadata, nested VP8+ALPH and VP8L, offsets and nested counts. |
| 14 | ANIM/ANMF: wrong lengths, duplicate ANIM, ANIM after ANMF, animation flag without ANIM, ANIM without flag, frame outside canvas, reserved bits, missing bitstream, truncated nested chunk. |
| 15 | ANMF nested rules: duplicate ALPH, ALPH after image, two bitstreams, zero-length ALPH, non-zero nested padding, truncation, unknown nested chunk accepted and counted. |
| 16 | Container-kind guards: image/ALPH in animation, ANIM without frames, frame without flag, missing image data (extended and simple), ALPH without VP8X, multiple image chunks. |
| 17 | Duplicate ICCP, EXIF and XMP rejected. |
| 18 | Out-of-range accessors return -1 and "" (chunk and frame indices, negative and above count). |
| 19 | All public constants and masks match the specification. |
| 20 | 14-bit dimension extremes, canvas boundary, exact chunk chain from 12 to EOF, `riff_size == size - 8`, `webp_is_webp` classification. |

## Known limitations

- The whole buffer must be in memory; there is no streaming or partial parse.
- No bitstream decode: VP8 partitions, VP8L streams, alpha planes, ICC/Exif/
  XMP payloads and unknown chunk payloads are never read beyond their
  structural headers. `VP8 ` scale bits are ignored (recorded dimensions are
  the 14-bit values, not multiplied by the scale).
- The parser is intentionally stricter than the RIFF "ignore trailing data"
  allowance: the declared size must match the buffer length exactly.
- Padding bytes must be zero (RIFF MUST); readers that tolerate garbage
  padding bytes will disagree on such files.
- Extended static image dimensions are not required to equal the VP8X canvas
  dimensions; only animated frame rectangles are bounds-checked.
- `ALPH` inside a `VP8L` frame is accepted even though the container
  specification marks it SHOULD NOT.
- Metadata ordering is enforced only where the specification says MUST
  (`ICCP` before image data, `ANIM` before `ANMF`, `ALPH` before the
  bitstream); `EXIF`/`XMP ` order is free.
- No encoder, no re-emission, no conversion to or from other formats.

## Contracts (batch #46 hardening pass, 2026-10-08)

Runtime-checkable `ensures:` clauses (25, across the 15 functions below) were
added to `src/webp.xi` in the batch #46 hardening pass (compiler v0.64.1;
`package.xi` is left for the coordinator to bump at integration). All are
`ensures:` with no `requires:`, so the accepted-input domain is unchanged.
Every clause is enforced as a runtime check; the 20-check conformance suite
exercises every contracted entry point with the clauses active and no clause
trapped, so none was dropped. Two consecutive green `& .\scripts\port.ps1
-Package xiom.webp -TimeoutSec 90` runs ended `port: PASS (passed=20
failed=0 program_exit=0 exit=0)` (42.01 s and 42.97 s). None is claimed
Z3-provable: `xiom-verify` was not run for this module, so the Z3-provable
column is "no" throughout.

Clause inputs are parameters and plain struct-parameter fields only; no clause
indexes a vector, reads a `Vec` element, compares a `Str`, uses a module
constant, or reads a `&mut` parameter. The one cross-call (`webp_parse`'s
clauses call `webp_is_webp(data)`) is definitional and non-re-entrant:
`webp_is_webp` never reaches `webp_parse`. Guards keep the proven families:
Boolean guard pairs (`webp_is_webp`, `webp_has_vp8x`), exact formulas
(`result == img.kind`, the four ANIM background bytes, `webp_chunk_count`,
`webp_frame_count`), sentinel/guard pairs (`result == -1`,
`result.len() == 0`, `result is Err` / `result is Ok`).

| Function | Clauses | Guarantee (abridged) | Z3-provable | Runtime-checked |
|---|---|---|---|---|
| `webp_parse` | 2 | not a RIFF/WEBP header => `Err`; `Ok` => RIFF/WEBP header valid | no | yes |
| `webp_is_webp` | 2 | fewer than 12 bytes => false; true => at least 12 bytes | no | yes |
| `webp_kind` | 1 | `result == img.kind` | no | yes |
| `webp_has_vp8x` | 2 | true iff `img.has_vp8x != 0` | no | yes |
| `webp_flag_icc` | 1 | `result == img.flag_icc` | no | yes |
| `webp_anim_background_blue` | 1 | `result == img.anim_background % 256` | no | yes |
| `webp_anim_background_green` | 1 | `result == (img.anim_background / 256) % 256` | no | yes |
| `webp_anim_background_red` | 1 | `result == (img.anim_background / 65536) % 256` | no | yes |
| `webp_anim_background_alpha` | 1 | `result == (img.anim_background / 16777216) % 256` | no | yes |
| `webp_chunk_count` | 1 | `result == img.chunk_fourcc.len()` | no | yes |
| `webp_chunk_fourcc` | 2 | out-of-range index => `result.len() == 0` | no | yes |
| `webp_chunk_offset` | 3 | out-of-range index => `-1`; `!= -1` => in range | no | yes |
| `webp_frame_count` | 1 | `result == img.frame_x.len()` | no | yes |
| `webp_frame_x` | 3 | out-of-range index => `-1`; `!= -1` => in range | no | yes |
| `webp_frame_format` | 3 | out-of-range index => `-1`; `!= -1` => in range | no | yes |

