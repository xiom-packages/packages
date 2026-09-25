# xiom.qoi SPEC

## Scope

Pure-XIOM parsing, validation, record access and canonical re-emission of the
container and op-stream layers of the Quite OK Image format (QOI) over flat
`Vec[UInt8]` buffers. Parsing produces a flat op record list (parallel
`Vec[Int]` fields on one `QoiStream`); pixels are never materialized.

## Non-goals

No pixel buffer API, no image decode to raw pixels, no PNG/JPEG/conversion
helpers, no rendering, no color management or gamma, no encoder heuristics
(choosing ops for pixels), no streaming or incremental decode, no
`Vec[StructType]`, no FFI, no Float64.

## Exact layout

```
offset  size  field
0       4     magic "qoif" (ASCII 113 111 105 102)
4       4     width,  unsigned 32-bit big-endian
8       4     height, unsigned 32-bit big-endian
12      1     channels: 3 = RGB, 4 = RGBA (informative)
13      1     colorspace: 0 = sRGB with linear alpha, 1 = all channels linear
14      ...   data section: a stream of ops
end-8   8     end marker: seven 0x00 bytes followed by a single 0x01
```

A complete buffer is exactly `14 + sum(op spans) + 8` bytes. The header is
fixed-size; there is no padding anywhere. Channels and colorspace are
informative header bytes: they are validated to 3/4 and 0/1 but do not
restrict which ops may appear in the stream (a `channels = 3` file may contain
RGBA ops and vice versa), matching the reference decoder.

## Ops

Every possible tag byte `0x00..0xFF` belongs to exactly one op class, so an
unknown op cannot occur by construction and there is no "unknown op" error.

| Tag | Op | Span | Payload |
|---|---|---|---|
| `0x00..0x3F` | INDEX | 1 | 6-bit index into the rolling 64-entry index (0..63) |
| `0x40..0x7F` | DIFF | 1 | 2-bit signed dr, dg, db, biased by 2 (each -2..1) |
| `0x80..0xBF` | LUMA | 2 | byte 1: 6-bit signed dg, biased by 32 (-32..31); byte 2: 4-bit signed dr-dg and db-dg, biased by 8 (each -8..7) |
| `0xC0..0xFD` | RUN | 1 | 6-bit run length 1..62 (stored with a bias of -1) |
| `0xFE` | RGB | 4 | r, g, b |
| `0xFF` | RGBA | 5 | r, g, b, a |

Each op covers pixels as follows: INDEX, DIFF, LUMA, RGB and RGBA each produce
exactly one pixel; RUN produces its run length. The reference decoder and
encoder start from the previous pixel `(0, 0, 0, 255)` (opaque black) and
maintain a rolling 64-entry array of previously seen pixels, indexed by
`(r * 3 + g * 5 + b * 7 + a * 11) % 64`; that array is zero-initialized and
the previous-pixel register it is updated from starts at `(0, 0, 0, 255)`.
This module keeps only op records, so it documents those values but never
evaluates an index or a pixel.

## Record model

`QoiStream` holds the header fields plus seven parallel `Vec[Int]` record
vectors with exactly `qoi_op_count()` entries each:

| Vector | Meaning |
|---|---|
| `op_kind` | kind code: 0 RGB, 1 RGBA, 2 INDEX, 3 DIFF, 4 LUMA, 5 RUN |
| `op_offset` | absolute byte offset of the op's tag byte in the parsed buffer |
| `op_span` | total op length including the tag: 1, 1, 1, 2, 4 or 5 |
| `op_a` | RGB/RGBA: r; INDEX: index; DIFF: dr; LUMA: dg; RUN: run length (1..62) |
| `op_b` | RGB/RGBA: g; DIFF: dg; LUMA: dr-dg; unused: -1 |
| `op_c` | RGB/RGBA: b; DIFF: db; LUMA: db-dg; unused: -1 |
| `op_d` | RGBA: a; unused for every other kind: -1 |

## Validation order and end-marker policy

`qoi_parse` applies, in order:

1. fewer than 4 bytes -> `qoi: truncated header`;
2. bytes 0..3 not `qoif` -> `qoi: bad magic`;
3. fewer than 14 bytes -> `qoi: truncated header`;
4. width 0 -> `qoi: zero width`; height 0 -> `qoi: zero height`;
5. dimension cap: the total `width * height` must not exceed
   `qoi_max_pixels()` = 400,000,000; the guard is evaluated as
   `width > cap` then `height > cap / width` (integer division), so the
   product is only formed once it is known to fit in an Int and no u32*u32
   overflow is possible. Violations -> `qoi: dimension overflow`;
6. channels not 3 or 4 -> `qoi: invalid channels`;
7. colorspace not 0 or 1 -> `qoi: invalid colorspace`;
8. the op stream is consumed under the pixel budget `width * height`: ops are
   read until the budget is exactly filled. Running out of bytes before the
   next op or inside an op payload is `qoi: truncated op`; a RUN that would
   push the produced pixel count past the budget is `qoi: run overflow`;
9. exactly 8 bytes must remain: fewer -> `qoi: truncated end marker`, bytes
   other than 7 * 0x00 + 0x01 -> `qoi: bad end marker`, and bytes after a
   valid marker -> `qoi: trailing data`.

The end marker is exact and terminal: this codec is stricter than the
reference decoder, which stops after `width * height` pixels and ignores the
trailing 8 bytes. Because ops are consumed by pixel budget (not by scanning
for a zero pattern), a run of `0x00` INDEX ops is parsed as ops for as long as
the budget requires, and the marker is never mistaken for data.

## Pixel cap

`qoi_max_pixels()` returns 400,000,000, the guard the reference implementation
applies (worst case 5 bytes per pixel is about 2 GB). It bounds the op-scan
work and keeps every count, product and offset well inside the signed 64-bit
Int. The cap is on the product, not on either axis: `20000 x 20000` is
accepted, `20000 x 20001` is `qoi: dimension overflow`.

## API contract

```xiom
pub type QoiStream = {
  width: Int; height: Int; channels: Int; colorspace: Int;
  op_kind: Vec[Int]; op_offset: Vec[Int]; op_span: Vec[Int];
  op_a: Vec[Int]; op_b: Vec[Int]; op_c: Vec[Int]; op_d: Vec[Int];
}
pub type QoiWalk = { op_count: Int; pixel_count: Int; checksum: Int; }

pub fn qoi_max_pixels() -> Int
pub fn qoi_header_size() -> Int
pub fn qoi_end_marker_size() -> Int
pub fn qoi_kind_rgb() -> Int
pub fn qoi_kind_rgba() -> Int
pub fn qoi_kind_index() -> Int
pub fn qoi_kind_diff() -> Int
pub fn qoi_kind_luma() -> Int
pub fn qoi_kind_run() -> Int
pub fn qoi_flag_raw() -> Int
pub fn qoi_flag_index() -> Int
pub fn qoi_flag_delta() -> Int
pub fn qoi_flag_run() -> Int

pub fn qoi_parse(data: &Vec[UInt8]) -> Result[QoiStream, Str]

pub fn qoi_width(s: &QoiStream) -> Int
pub fn qoi_height(s: &QoiStream) -> Int
pub fn qoi_channels(s: &QoiStream) -> Int
pub fn qoi_colorspace(s: &QoiStream) -> Int
pub fn qoi_data_offset(s: &QoiStream) -> Int
pub fn qoi_pixel_count(s: &QoiStream) -> Int
pub fn qoi_op_count(s: &QoiStream) -> Int
pub fn qoi_op_kind(s: &QoiStream, i: Int) -> Int
pub fn qoi_op_flags(s: &QoiStream, i: Int) -> Int
pub fn qoi_op_offset(s: &QoiStream, i: Int) -> Int
pub fn qoi_op_span(s: &QoiStream, i: Int) -> Int
pub fn qoi_op_a(s: &QoiStream, i: Int) -> Int
pub fn qoi_op_b(s: &QoiStream, i: Int) -> Int
pub fn qoi_op_c(s: &QoiStream, i: Int) -> Int
pub fn qoi_op_d(s: &QoiStream, i: Int) -> Int
pub fn qoi_run_length(s: &QoiStream, i: Int) -> Int

pub fn qoi_emit(s: &QoiStream) -> Result[Vec[UInt8], Str]
pub fn qoi_walk(s: &QoiStream) -> Result[QoiWalk, Str]
```

Semantics:

- `qoi_parse` never materializes pixels; it validates the header, the op span
  rules, the pixel budget and the exact end marker, and returns the record
  list. `qoi_data_offset` is always 14.
- `qoi_pixel_count` is `width * height` (the op records must account for
  exactly that many pixels).
- Record accessors are O(1). `qoi_op_kind`, `qoi_op_flags`,
  `qoi_op_offset`, `qoi_op_span`, `qoi_op_a`..`qoi_op_d` and
  `qoi_run_length` return -1 when `i` is outside `[0, qoi_op_count())` or when
  the requested slot is unused. `qoi_run_length` is the run length only for
  RUN ops, else -1. `qoi_op_flags` maps RGB/RGBA to `qoi_flag_raw()`, INDEX
  to `qoi_flag_index()`, DIFF/LUMA to `qoi_flag_delta()` and RUN to
  `qoi_flag_run()` (the flag is a class, not a unique kind id).
- `qoi_emit` rebuilds header + op bytes + end marker from the records alone.
  It requires the seven vectors to be parallel, the header fields valid and
  every record consistent with its kind (span, payload ranges) and with the
  pixel budget; otherwise `Err("qoi: invalid record")`. For any buffer
  `qoi_parse` accepts, the emitted bytes are byte-identical to the input.
- `qoi_walk` is the optional bounded semantic pass described below.

## Walk semantics and checksum

`qoi_walk` validates the records without materializing pixels:

- record consistency as in `qoi_emit` (`qoi: invalid record`);
- the produced pixel count never exceeds `width * height`: a RUN past the
  budget is `qoi: run overflow`, a single-pixel op past it is
  `qoi: pixel count overflow`, and ending below the budget is
  `qoi: pixel count mismatch`;
- the canonical-encoder rule from the reference implementation: two
  consecutive INDEX ops must not address the same index
  (`qoi: repeated index`). Consecutive RUN ops are accepted, because the
  reference decoder accepts them.

On success it returns `QoiWalk{ op_count, pixel_count, checksum }` with
`pixel_count == width * height` and

```
checksum = sum over i of (kind_i + 1) * (i + 1), modulo 2^32
```

where `kind_i` is the kind code of op `i`. This is a documented integer
checksum of the op-kind sequence (order-sensitive, additive, masked to 32
bits), not a pixel hash and not a cryptographic digest; it uses Int
arithmetic only (no Float64).

## Error catalog

| Condition | Message |
|---|---|
| fewer than 4 bytes, or 4..13 bytes with valid magic | `qoi: truncated header` |
| at least 4 bytes and bytes 0..3 are not `qoif` | `qoi: bad magic` |
| width field 0 | `qoi: zero width` |
| height field 0 | `qoi: zero height` |
| `width * height` above 400,000,000 (incl. any u32 axis that cannot fit) | `qoi: dimension overflow` |
| channels byte not 3 or 4 | `qoi: invalid channels` |
| colorspace byte not 0 or 1 | `qoi: invalid colorspace` |
| buffer ends before the next op, or inside an op payload | `qoi: truncated op` |
| a RUN would push the produced pixel count past the budget | `qoi: run overflow` |
| fewer than 8 bytes remain after the op stream | `qoi: truncated end marker` |
| the 8 remaining bytes are not 7 * 0x00 + 0x01 | `qoi: bad end marker` |
| bytes follow a valid end marker | `qoi: trailing data` |
| record vectors not parallel, kind/span/payload range invalid, op budget inconsistent | `qoi: invalid record` |
| walk: two consecutive INDEX ops to the same index | `qoi: repeated index` |
| walk: single-pixel ops exceed the budget | `qoi: pixel count overflow` |
| walk: fewer pixels produced than the budget | `qoi: pixel count mismatch` |

## Test matrix

| # | Check |
|---|---|
| 1 | 1x1 RGB file parses with exact header/op metadata and re-emits byte-exactly. |
| 2 | All six op kinds in one stream: kinds, slots, spans, offsets, flags, run length. |
| 3 | Out-of-range record accessors return the -1 sentinel. |
| 4 | Header truncation and magic validated in order (empty, 3-byte, magic-only, 10-byte, bad magic, header-only). |
| 5 | Zero width/height rejected before channels, colorspace and any op scanning. |
| 6 | 400,000,000-pixel cap inclusive on the exact boundary and overflow-safe above it (incl. u32 max). |
| 7 | Channels 3/4 and colorspace 0/1 are the only accepted values, with channels checked first. |
| 8 | Buffers ending inside the op section (RGB, RGBA, LUMA payloads, budget shortfall, no ops) are `truncated op`. |
| 9 | RUN overflow rejected at 1, 3 and 62 pixels past the budget; exact fills accepted and re-emitted. |
| 10 | End marker: truncated, wrong last byte, non-zero middle byte, trailing data. |
| 11 | Canonical emit pins the header bytes, channels/colorspace, first op, marker and byte-exact round-trip. |
| 12 | Emitter rejects kind 9, stray slot d, wrong span, pixel-budget mismatch, RUN mismatch, zero dimension and drifted vectors; accepts a hand-built RUN record. |
| 13 | Walk returns op count, pixel count and the documented checksum (67 for the six-op stream, 6 for a single RUN). |
| 14 | Consecutive INDEX ops: same index is `repeated index`, different indices and INDEX-then-RGB are fine. |
| 15 | Walk pixel accounting: RUN overflow, under-production mismatch, mid-stream overflow. |
| 16 | Extreme tag boundaries (INDEX 0/63, DIFF 0x40/0x7F, LUMA 0x80 0x00 / 0xBF 0xFF, RUN 1/62) decode to documented payloads; checksum 182. |
| 17 | Channel payload extremes (0 and 255) survive parse, walk and re-emit. |
| 18 | The channels byte does not restrict which ops may appear (RGBA under channels 3, RGB under channels 4). |
| 19 | The pixel budget, not marker-looking zeroes, bounds the op stream; emitted zeros round-trip; walk flags the repeat. |
| 20 | Op offsets chain contiguously from 14 to the marker start; per-op flags match kinds. |

## Known limitations

- The whole buffer must be in memory; there is no streaming or partial decode.
- Pixels are never materialized: reconstructing pixel values (rolling index,
  previous-pixel seed, wraparound deltas) is the caller's concern.
- No encoder: `qoi_emit` re-emits records and cannot turn pixels into a
  canonical minimal op stream.
- No conversion to or from PNG/JPEG/any other format and no rendering.
- The walk enforces the "valid encoder" INDEX rule but accepts consecutive
  RUN ops (the reference decoder accepts them); it is not a full spec-audit
  of an arbitrary encoder.
