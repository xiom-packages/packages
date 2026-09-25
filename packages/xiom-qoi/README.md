# xiom.qoi

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (20/20); NOT published yet.
> **Scope:** QOI header parsing, flat op-record extraction with byte spans and offsets, end-marker validation, record accessors, a bounded semantic walk and canonical byte-exact re-emission. Pixels are never materialized.
> **Deps:** `xiom.std` only. No FFI in v0.1.

## What it is

`xiom.qoi` is a pure-XIOM codec for the container and op-stream layers of the
Quite OK Image format (QOI), a fast lossless image format:

- a fixed **14-byte header**: the ASCII magic `qoif`, width and height as
  unsigned 32-bit big-endian integers, a channels byte (3 = RGB, 4 = RGBA)
  and a colorspace byte (0 = sRGB with linear alpha, 1 = all channels linear);
- a **data section** that is a stream of ops over a `width * height` pixel
  budget:
  - `INDEX` (`0x00..0x3F`): 6-bit reference to the rolling 64-entry index;
  - `DIFF` (`0x40..0x7F`): three 2-bit signed deltas (-2..1);
  - `LUMA` (`0x80..0xBF`): 6-bit green delta (-32..31) plus a byte with
    4-bit red/blue deltas relative to green (-8..7);
  - `RUN` (`0xC0..0xFD`): a run of 1..62 pixels;
  - `RGB` (`0xFE`): explicit r, g, b;
  - `RGBA` (`0xFF`): explicit r, g, b, a;
- an **8-byte end marker**: seven `0x00` bytes followed by one `0x01`.

Every possible tag byte belongs to exactly one op, so there is no
"unknown op" case. The module works on flat `Vec[UInt8]` buffers, returns
`Result[..., Str]` with deterministic `qoi: `-prefixed messages, and stores
parsing results as **parallel `Vec[Int]` record fields** (no
`Vec[StructType]`) so no pixel buffer is ever allocated.

## Format notes

| Field | Bytes | Encoding |
|---|---|---|
| magic | 0..3 | ASCII `qoif` (113 111 105 102) |
| width | 4..7 | unsigned 32-bit, big-endian, > 0 |
| height | 8..11 | unsigned 32-bit, big-endian, > 0 |
| channels | 12 | 3 or 4 (informative) |
| colorspace | 13 | 0 = sRGB with linear alpha, 1 = all linear (informative) |
| data | 14.. | ops until exactly `width * height` pixels are covered |
| end marker | last 8 | `00 00 00 00 00 00 00 01` |

The total pixel count is capped at 400,000,000 (`qoi_max_pixels()`), the guard
the reference implementation applies; the cap is checked before the
`width * height` product is formed, so no 64-bit overflow is possible. The op
stream is consumed by pixel budget, then the exact marker must follow with no
trailing bytes. The reference decoder's rolling 64-entry index is
zero-initialized and the previous-pixel register it is updated from starts at
`(0, 0, 0, 255)`; this codec documents that but only keeps records.

## API

| Function | Returns | Description |
|---|---|---|
| `qoi_parse(data)` | `Result[QoiStream, Str]` | Validates header, op stream and end marker; returns header fields plus the flat record list. Never materializes pixels. |
| `qoi_width(s)` / `qoi_height(s)` | `Int` | Parsed dimensions. |
| `qoi_channels(s)` / `qoi_colorspace(s)` | `Int` | Header bytes (3/4 and 0/1). |
| `qoi_data_offset(s)` | `Int` | First op offset (always 14). |
| `qoi_pixel_count(s)` | `Int` | `width * height`. |
| `qoi_op_count(s)` | `Int` | Number of op records. |
| `qoi_op_kind(s, i)` | `Int` | Kind code at `i` (0 RGB, 1 RGBA, 2 INDEX, 3 DIFF, 4 LUMA, 5 RUN), or -1. |
| `qoi_op_flags(s, i)` | `Int` | Class flag (raw / index / delta / run), or -1. |
| `qoi_op_offset(s, i)` / `qoi_op_span(s, i)` | `Int` | Absolute tag offset and total byte span (1, 2, 4 or 5), or -1. |
| `qoi_op_a(s, i)`..`qoi_op_d(s, i)` | `Int` | Payload slots (per-kind table in SPEC.md); unused slots are -1. |
| `qoi_run_length(s, i)` | `Int` | Run length 1..62 for RUN ops, else -1. |
| `qoi_emit(s)` | `Result[Vec[UInt8], Str]` | Canonical re-emission from records; byte-identical to any input `qoi_parse` accepted. |
| `qoi_walk(s)` | `Result[QoiWalk, Str]` | Bounded semantic pass: pixel accounting, the canonical INDEX rule, and an integer op-kind checksum. |
| `qoi_max_pixels()` | `Int` | Documented total-pixel cap, 400,000,000. |
| `qoi_header_size()` / `qoi_end_marker_size()` | `Int` | 14 and 8. |
| `qoi_kind_*()` / `qoi_flag_*()` | `Int` | Kind and flag constants. |

## Usage

```xiom
use xiom.qoi;

match qoi_parse(bytes) {
  Ok(q) => {
    // q.op_kind / q.op_offset / q.op_span / q.op_a..op_d are parallel vectors.
    let n = qoi_op_count(&q);
    let px = qoi_pixel_count(&q);          // width * height
    if (qoi_op_kind(&q, 0) == qoi_kind_run()) {
      let run = qoi_run_length(&q, 0);     // 1..62
    }
    match qoi_walk(&q) {
      Ok(w) => { /* w.pixel_count == px, w.checksum is documented */ },
      Err(e) => { /* qoi: repeated index, ... */ },
    }
  },
  Err(e) => { /* qoi: bad magic, qoi: truncated op, ... */ },
}

match qoi_emit(&q) {
  Ok(same_bytes) => { /* byte-identical to the parsed input */ },
  Err(e) => { /* qoi: invalid record */ },
}
```

## Error model

Every failure is `Err(Str)` with a deterministic message:

| Message | Condition |
|---|---|
| `qoi: truncated header` | Fewer than 4 bytes, or 4..13 bytes with valid magic. |
| `qoi: bad magic` | At least 4 bytes and bytes 0..3 are not `qoif`. |
| `qoi: zero width` / `qoi: zero height` | A dimension field is 0. |
| `qoi: dimension overflow` | `width * height` exceeds 400,000,000 (including any u32 value that cannot fit). |
| `qoi: invalid channels` | The channels byte is not 3 or 4. |
| `qoi: invalid colorspace` | The colorspace byte is not 0 or 1. |
| `qoi: truncated op` | The buffer ends before the next op or inside an op payload. |
| `qoi: run overflow` | A RUN would push the produced pixel count past the budget. |
| `qoi: truncated end marker` | Fewer than 8 bytes remain after the op stream. |
| `qoi: bad end marker` | The trailing 8 bytes are not 7 * `0x00` + `0x01`. |
| `qoi: trailing data` | Bytes follow a valid end marker. |
| `qoi: invalid record` | Emitter/walker: non-parallel vectors, bad kind/span/payload, or an op budget inconsistent with the header. |
| `qoi: repeated index` | Walker: two consecutive INDEX ops address the same index. |
| `qoi: pixel count overflow` / `qoi: pixel count mismatch` | Walker: records produce more / fewer pixels than `width * height`. |

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.qoi
```

20 conformance tests: 1x1 RGB round-trip; all six op kinds with payload,
span, offset and flag checks; out-of-range sentinels; header truncation and
magic ordering; zero dimensions; the inclusive 400,000,000-pixel cap and
u32-max overflow; channels/colorspace validation; mid-op truncation; RUN
overflow and exact fills; end-marker variants; canonical byte-pinned emit;
emitter rejection of forged records; walk counts, checksums (67, 6, 9, 182,
3) and repeated-index rejection; boundary tags for every op; payload extremes
0/255; channels/op pass-through; budget-driven parsing of marker-looking
zeroes; and the offset chain from 14 to the marker.

## Limitations

- The whole buffer must be in memory; no streaming or partial decode.
- No pixels: this is a container/op-stream codec. Rolling-index reconstruction
  and wraparound delta application are left to callers.
- No encoder from pixels; `qoi_emit` only re-emits an existing record list.
- No PNG/JPEG conversion and no rendering.
- The walk accepts consecutive RUN ops (the reference decoder accepts them)
  and does not simulate the rolling index.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
