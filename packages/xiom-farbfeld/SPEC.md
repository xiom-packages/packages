# xiom.farbfeld SPEC

## Scope

Pure-XIOM parsing, validation, pixel/channel/span access and canonical building
of single-image farbfeld buffers over flat `Vec[UInt8]` storage.

## Non-goals

Rendering, PNG/JPEG/Netpbm conversion, color management, gamma, palettes,
premultiplication, alpha interpretation, 8-bit channel paths, streaming or
partial decode, multi-image concatenation, compression.

## Exact layout

```
offset  size       field
0       8          magic "farbfeld" (ASCII 0x66 0x61 0x72 0x62 0x66 0x65 0x6C 0x64)
8       4          width,  unsigned 32-bit big-endian
12      4          height, unsigned 32-bit big-endian
16      8*w*h      raster: width*height pixels, row-major, top-left origin
```

Per pixel the bytes are `BE16(R) BE16(G) BE16(B) BE16(A)`, in that order.
There is no padding, alignment or metadata anywhere; a complete buffer must be
exactly `16 + 8*width*height` bytes long.

## Dimensions

- width and height are read as unsigned 32-bit big-endian values.
- 0 is rejected on either axis: `farbfeld: zero width`, `farbfeld: zero height`.
- The documented cap for both axes is 1,000,000 (`farbfeld_max_dim()`), so
  `8*width*height <= 8*10^12`, which cannot overflow the 64-bit Int used for
  offsets and products. A header field (or builder argument) above the cap is
  `farbfeld: dimension overflow`; a negative builder argument is
  `farbfeld: invalid width` / `farbfeld: invalid height`.
- A header that passes the cap check but declares more raster bytes than the
  buffer holds is `farbfeld: truncated pixels`; fewer is
  `farbfeld: extra pixel data`.

## API contract

```xiom
pub type FarbfeldImage = { width: Int; height: Int; data_offset: Int; }
pub type FarbfeldPixel = { r: Int; g: Int; b: Int; a: Int; }

pub fn farbfeld_max_dim() -> Int
pub fn farbfeld_width(img: &FarbfeldImage) -> Int
pub fn farbfeld_height(img: &FarbfeldImage) -> Int
pub fn farbfeld_data_offset(img: &FarbfeldImage) -> Int
pub fn farbfeld_pixel_count(img: &FarbfeldImage) -> Int
pub fn farbfeld_row_bytes(img: &FarbfeldImage) -> Int
pub fn farbfeld_raster_len(img: &FarbfeldImage) -> Int
pub fn farbfeld_pixel_offset(img: &FarbfeldImage, x: Int, y: Int) -> Int
pub fn farbfeld_parse_header(data: &Vec[UInt8]) -> Result[FarbfeldImage, Str]
pub fn farbfeld_pixel_rgba(data: &Vec[UInt8], x: Int, y: Int) -> Result[FarbfeldPixel, Str]
pub fn farbfeld_pixel_channel(data: &Vec[UInt8], x: Int, y: Int, c: Int) -> Result[Int, Str]
pub fn farbfeld_row_copy(data: &Vec[UInt8], img: &FarbfeldImage, y: Int) -> Result[Vec[UInt8], Str]
pub fn farbfeld_raster_copy(data: &Vec[UInt8], img: &FarbfeldImage) -> Result[Vec[UInt8], Str]
pub fn farbfeld_build(rgba: &Vec[Int], width: Int, height: Int) -> Result[Vec[UInt8], Str]
pub fn farbfeld_build_raw(be_rgba: &Vec[UInt8], width: Int, height: Int) -> Result[Vec[UInt8], Str]
```

Semantics, in the order the implementation applies them:

- `farbfeld_parse_header`: `n < 8` is `truncated header`; then the magic is
  checked (`bad magic`); then `n < 16` is `truncated header`; then width and
  height are decoded and validated (`zero width`/`zero height`/
  `dimension overflow`); finally the raster length is compared exactly
  (`truncated pixels`/`extra pixel data`). A parsed image always has
  `data_offset == 16`.
- `farbfeld_width`, `farbfeld_height`, `farbfeld_data_offset`,
  `farbfeld_pixel_count` (`w*h`), `farbfeld_row_bytes` (`w*8`) and
  `farbfeld_raster_len` (`w*h*8`) are pure field derivations; they are safe on
  a forged image and do not touch the buffer.
- `farbfeld_pixel_offset`: `x` or `y` outside the image (including negatives)
  returns the documented sentinel `-1`; every in-range offset is `>= 16`.
- `farbfeld_pixel_rgba`: parses and validates the buffer, then checks the
  coordinate against the parsed dimensions (`pixel out of range`); parse
  errors are propagated unchanged. Channels are read as big-endian 16-bit
  values and returned in `0..65535`.
- `farbfeld_pixel_channel`: identical validation to `farbfeld_pixel_rgba`;
  `c` outside `0..3` is `channel index out of range`, checked after the pixel
  coordinate, and `0 = R, 1 = G, 2 = B, 3 = A`.
- `farbfeld_row_copy`: `y` outside `0..height-1` is `row out of range`; the
  computed span is then guarded against `data.len()`, and a span that does not
  fit is `raster out of range`. The result is exactly `width * 8` bytes.
- `farbfeld_raster_copy`: copies exactly `width * height * 8` bytes starting
  at `data_offset`; negative or out-of-buffer spans are
  `raster out of range` (for forged or stale images).
- `farbfeld_build`: validates dimensions (`zero`/`invalid`/`dimension
  overflow`), then `rgba.len() == width*height*4`
  (`channel buffer size mismatch`), then every value in `0..65535`
  (`channel out of range`). Nothing is emitted unless the whole buffer
  validates. The emit is the 16-byte header followed by each channel as two
  big-endian bytes in flat order.
- `farbfeld_build_raw`: the same dimension and error rules; the raster must be
  exactly `width*height*8` bytes (`raster buffer size mismatch`) and is copied
  verbatim, big-endian bytes are not interpreted.

## Error catalog

| Condition | Message |
|---|---|
| buffer shorter than 8 bytes | `farbfeld: truncated header` |
| magic mismatch on an at-least-8-byte buffer | `farbfeld: bad magic` |
| 8..15 bytes with valid magic | `farbfeld: truncated header` |
| width field 0, or builder width 0 | `farbfeld: zero width` |
| height field 0, or builder height 0 | `farbfeld: zero height` |
| builder width < 0 | `farbfeld: invalid width` |
| builder height < 0 | `farbfeld: invalid height` |
| width or height above 1,000,000 | `farbfeld: dimension overflow` |
| raster shorter than `8*w*h` | `farbfeld: truncated pixels` |
| raster longer than `8*w*h` | `farbfeld: extra pixel data` |
| pixel coordinate outside the image | `farbfeld: pixel out of range` |
| channel selector outside `0..3` | `farbfeld: channel index out of range` |
| builder channel value outside `0..65535` | `farbfeld: channel out of range` |
| `rgba.len() != w*h*4` | `farbfeld: channel buffer size mismatch` |
| `be_rgba.len() != w*h*8` | `farbfeld: raster buffer size mismatch` |
| row index outside `0..height-1` | `farbfeld: row out of range` |
| forged span outside the buffer | `farbfeld: raster out of range` |

## Test matrix

| # | Check |
|---|---|
| 1 | 2x2 channel ramp builds to 48 bytes, parses with exact metadata, decodes all four pixels and span-copies the raster. |
| 2 | Hand-built 1x1 header plus 8 bytes decodes to (1, 2, 3, 4) through pixel and channel accessors. |
| 3 | Canonical 1x1 emit is pinned byte-for-byte for all-zero and all-65535 channels. |
| 4 | Wrong first/last magic byte, 7-byte, magic-only 8-byte, 15-byte and bad-magic 8-byte buffers hit the documented messages in order. |
| 5 | Exact raster size: 47 bytes truncated, 49 bytes extra, header-only truncated. |
| 6 | Zero width/height and negative dimensions rejected by parser and both builders. |
| 7 | 1,000,000 cap on both axes, u32 max overflow, `farbfeld_max_dim()` value. |
| 8 | Out-of-range pixel coordinates, the `-1` offset sentinel, and header-error propagation. |
| 9 | Channel selection 0..3 and channel-index errors; pixel errors take precedence. |
| 10 | Builder size mismatches for channels and raw bytes, exact sizes accepted. |
| 11 | Channel range rejection at -1 and 65536; 0 and 65535 accepted. |
| 12 | 1x1 maximum channels round-trip byte-exactly and raster-copy to 0xFF. |
| 13 | Wide 1x7 raster round-trips channel by channel; the single row spans the raster; row 1 rejected. |
| 14 | `farbfeld_build_raw` copies pre-encoded bytes verbatim; big-endian decode checked. |
| 15 | Big-endian header bytes pinned at offsets 8..15; 2x3 row offsets and rows. |
| 16 | Row copies and span guards: bad rows, forged positive/negative offsets, empty buffer. |
| 17 | Inclusive cap: a 1000000x1 exact-size raster parses; one past the cap is `-1`. |

## Known limitations

- Every pixel accessor re-parses and re-validates the whole buffer; no cached
  decode is offered in v0.1.
- The whole image must be in memory; no streaming or partial decode.
- Channels are raw values; no premultiplication, color management or alpha
  interpretation.
- No conversion to or from other image formats and no rendering.
- Single image only: concatenated buffers fail with `extra pixel data`.
