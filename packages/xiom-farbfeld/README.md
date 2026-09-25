# xiom.farbfeld

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (17/17); NOT published yet.
> **Scope:** farbfeld header parsing, exact raster-size validation, RGBA pixel/channel/span accessors, and canonical building from flat channel buffers.
> **Deps:** `xiom.std` only. No FFI in v0.1.

## What it is

`xiom.farbfeld` is a pure-XIOM codec for the farbfeld image format, a
lossless 16-bit RGBA interchange format designed to be trivial to parse:

- a fixed **16-byte header**: the ASCII magic `farbfeld`, then width and
  height as unsigned 32-bit big-endian integers;
- a raster of `width * height` pixels, each **8 bytes**: four unsigned 16-bit
  big-endian channels in R, G, B, A order;
- no compression, no padding, no alignment, no metadata -- exactly
  `16 + 8 * width * height` bytes in total.

The module works on flat `Vec[UInt8]` buffers, returns `Result[..., Str]` with
deterministic `farbfeld: `-prefixed messages, and never premultiplies or
color-manages channel data. `FarbfeldPixel` exposes the four channels as Ints
in `0..65535`.

## Format notes

| Field | Bytes | Encoding |
|---|---|---|
| magic | 0..7 | ASCII `farbfeld` (102 97 114 98 102 101 108 100) |
| width | 8..11 | unsigned 32-bit, big-endian, 1..1000000 |
| height | 12..15 | unsigned 32-bit, big-endian, 1..1000000 |
| raster | 16.. | `width * height` pixels, row-major, 8 bytes each |

Per pixel the byte order is `BE16(R) BE16(G) BE16(B) BE16(A)`. Pixels are
stored row-major with a top-left origin and no row padding. A complete buffer
must be exactly `16 + 8 * width * height` bytes: a shorter buffer is
truncated, a longer one carries extra data. `farbfeld_max_dim()` returns the
documented per-axis cap (1,000,000), which keeps every `8 * width * height`
product and every offset far inside the 64-bit Int range.

## API

| Function | Returns | Description |
|---|---|---|
| `farbfeld_parse_header(data)` | `Result[FarbfeldImage, Str]` | Validates magic, dimensions and the exact raster size; returns `{ width, height, data_offset: 16 }`. |
| `farbfeld_width(img)` / `farbfeld_height(img)` | `Int` | Parsed dimensions. |
| `farbfeld_data_offset(img)` | `Int` | First raster byte (always 16). |
| `farbfeld_pixel_count(img)` | `Int` | `width * height`. |
| `farbfeld_row_bytes(img)` | `Int` | `width * 8`. |
| `farbfeld_raster_len(img)` | `Int` | `width * height * 8`. |
| `farbfeld_pixel_offset(img, x, y)` | `Int` | Byte offset of a pixel (top-left origin), or the documented `-1` sentinel when out of range. |
| `farbfeld_pixel_rgba(data, x, y)` | `Result[FarbfeldPixel, Str]` | Four channels as Ints in `0..65535`; out-of-range coordinates are an error. |
| `farbfeld_pixel_channel(data, x, y, c)` | `Result[Int, Str]` | One channel; `c` is 0=R, 1=G, 2=B, 3=A. |
| `farbfeld_row_copy(data, img, y)` | `Result[Vec[UInt8], Str]` | Copy one `width * 8`-byte row. |
| `farbfeld_raster_copy(data, img)` | `Result[Vec[UInt8], Str]` | Copy the exact raster span, guarded against the buffer length. |
| `farbfeld_build(rgba, width, height)` | `Result[Vec[UInt8], Str]` | Canonical emit from `width * height * 4` flat channel values, each 0..65535. |
| `farbfeld_build_raw(be_rgba, width, height)` | `Result[Vec[UInt8], Str]` | Canonical emit from `width * height * 8` pre-encoded big-endian bytes, copied verbatim. |
| `farbfeld_max_dim()` | `Int` | Documented per-axis cap, 1,000,000. |

## Usage

```xiom
use xiom.farbfeld;

let channels = Vec[Int].new();          // width * height * 4 values
channels.push(65535); channels.push(0); channels.push(32768); channels.push(65535);

match farbfeld_build(channels, 1, 1) {
  Ok(bytes) => { /* write bytes */ },
  Err(e)    => { /* farbfeld: ... */ },
}

match farbfeld_parse_header(bytes) {
  Ok(img) => {
    match farbfeld_pixel_rgba(bytes, 0, 0) {
      Ok(p) => { /* p.r, p.g, p.b, p.a are Ints in 0..65535 */ },
      Err(e) => { /* handle */ },
    }
  },
  Err(e) => { /* handle */ },
}
```

## Error model

Every failure is `Err(Str)` with a deterministic message:

| Message | Condition |
|---|---|
| `farbfeld: truncated header` | Fewer than 8 bytes, or 8..15 bytes with valid magic. |
| `farbfeld: bad magic` | At least 8 bytes and bytes 0..7 are not `farbfeld`. |
| `farbfeld: zero width` / `farbfeld: zero height` | A dimension field is 0. |
| `farbfeld: invalid width` / `farbfeld: invalid height` | A builder dimension is negative. |
| `farbfeld: dimension overflow` | A dimension exceeds `farbfeld_max_dim()` (1,000,000). |
| `farbfeld: truncated pixels` | Fewer than `8 * width * height` raster bytes. |
| `farbfeld: extra pixel data` | More than `8 * width * height` raster bytes. |
| `farbfeld: pixel out of range` | A pixel coordinate is outside the image. |
| `farbfeld: channel index out of range` | A channel selector is not 0..3. |
| `farbfeld: channel out of range` | A builder channel value is not 0..65535. |
| `farbfeld: channel buffer size mismatch` | `rgba.len() != width * height * 4`. |
| `farbfeld: raster buffer size mismatch` | `be_rgba.len() != width * height * 8`. |
| `farbfeld: raster out of range` | A forged image's span falls outside the buffer. |
| `farbfeld: row out of range` | A row index is outside `0..height-1`. |

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.farbfeld
```

17 conformance tests: 2x2 build/parse/span round-trip, hand-built 1x1 decode,
pinned canonical emit (1x1 zeros and 1x1 maximum channels), magic and
header-truncation ordering, exact raster size (short, long, header-only), zero
and negative dimensions for both builders, the 1,000,000 cap on both axes plus
u32-max overflow, out-of-range pixel coordinates and the `-1` offset sentinel,
channel selection and index validation, builder size mismatches, channel range
validation at 0 and 65535, max-channel round-trip, a wide 1x7 raster, raw
byte-exact builds, big-endian header bytes, span/row guards, and the inclusive
1,000,000-pixel cap.

## Limitations

- Every pixel accessor re-parses and re-validates the full buffer; the API is
  designed for correctness, not for hot loops over large rasters.
- The whole image must be in memory; there is no streaming, incremental or
  partial decode.
- No premultiplication, no color management, no gamma handling, and alpha is
  never interpreted: channels are raw unsigned values.
- No PNG/JPEG/Netpbm conversion helpers and no rendering.
- Single image only: trailing bytes after the exact raster are rejected as
  `farbfeld: extra pixel data`, so concatenated images do not parse.
- 16-bit channels only, as the format defines; there is no 8-bit path.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
