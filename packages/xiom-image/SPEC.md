# xiom.image SPEC

## Scope

Pure-XIOM unified image front end for the ecosystem:

1. **format**: magic-byte sniffing and metadata extraction for BMP, PNG, JPEG,
   GIF, PPM (P6) and TGA (heuristic);
2. **decode**: a unified pipeline that sniffs then dispatches explicitly to the
   documented codec subset -- BMP 24/32-bit and PPM P6;
3. **encode**: a unified pipeline that dispatches explicitly to BMP 24-bit,
   BMP 32-bit or PPM P6;
4. **convert**: pixel-format and color-space conversion over a packed RGBA8
   pixel model.

No FFI, no cross-package imports, no I/O, no floating point: every function is
a pure function of its arguments and deterministic.

## Non-goals

Compressed or palettized decoding (PNG deflate/filters, JPEG DCT/Huffman, GIF
LZW, TGA RLE/palettes), animation, streaming, scaling, blending, ICC/color
management, 16-bit or floating-point samples, P3 ASCII PPM input, PPM comments.

## Data model

```xiom
pub type RgbaImage = { width: Int; height: Int; stride: Int; pixels: Vec[UInt8]; }
pub type ImageMeta = { width: Int; height: Int; format: Int; bits: Int; }
pub type BmpHeader = { width: Int; height: Int; bits: Int; data_offset: Int; row_bytes: Int; }
pub type PpmHeader = { width: Int; height: Int; maxval: Int; data_offset: Int; }
```

- `RgbaImage`: packed RGBA8, one byte per channel. Pixel `(x, y)` starts at
  byte `y * stride + x * 4`, in R, G, B, A order. Invariants: `width >= 1`,
  `height >= 1`, `stride >= width * 4`, `pixels.len() == stride * height`.
  Padding bytes in a row are never read or written by any kernel.
- Producers (`image_new_rgba`, `image_rgb_to_rgba`, `image_gray_to_rgba`,
  `image_bgra_to_rgba`, `image_copy`, both decoders) return compact images with
  `stride == width * 4`. `image_from_rgba` adopts an arbitrary conforming
  stride; the conversions skip padding and therefore accept strided inputs.
- `ImageMeta.bits` is the on-disk bit depth: BMP 24/32, PNG IHDR bit depth,
  GIF 8, PPM 8, JPEG 8, TGA pixel depth.
- `BmpHeader.height` is signed: positive = bottom-up rows (standard), negative
  = top-down storage. `row_bytes` is the padded stride
  `((width * bits + 31) / 32) * 4`.
- `PpmHeader.data_offset` is the first raster byte (after the single whitespace
  byte terminating maxval).

## API

```xiom
pub const IMG_FMT_UNKNOWN: Int = -1;
pub const IMG_FMT_BMP: Int = 0;
pub const IMG_FMT_PNG: Int = 1;
pub const IMG_FMT_JPEG: Int = 2;
pub const IMG_FMT_GIF: Int = 3;
pub const IMG_FMT_PPM: Int = 4;
pub const IMG_FMT_TGA: Int = 5;
pub const IMG_ENC_BMP24: Int = 0;
pub const IMG_ENC_BMP32: Int = 1;
pub const IMG_ENC_PPM: Int = 2;

pub fn image_format_name(fmt: Int) -> Str
pub fn image_sniff(data: &Vec[UInt8]) -> Int
pub fn image_meta(data: &Vec[UInt8]) -> Result[ImageMeta, Str]

pub fn image_bmp_header(data: &Vec[UInt8]) -> Result[BmpHeader, Str]
pub fn image_ppm_header(data: &Vec[UInt8]) -> Result[PpmHeader, Str]

pub fn image_new_rgba(width: Int, height: Int, r: Int, g: Int, b: Int, a: Int) -> Result[RgbaImage, Str]
pub fn image_from_rgba(width: Int, height: Int, stride: Int, pixels: Vec[UInt8]) -> Result[RgbaImage, Str]
pub fn image_width(img: &RgbaImage) -> Int
pub fn image_height(img: &RgbaImage) -> Int
pub fn image_stride(img: &RgbaImage) -> Int
pub fn image_get_rgba(img: &RgbaImage, x: Int, y: Int) -> Int
pub fn image_set_rgba(img: &mut RgbaImage, x: Int, y: Int, r: Int, g: Int, b: Int, a: Int) -> Bool
pub fn image_copy(img: &RgbaImage) -> RgbaImage

pub fn image_rgba_to_rgb(img: &RgbaImage) -> Vec[UInt8]
pub fn image_rgb_to_rgba(rgb: &Vec[UInt8], width: Int, height: Int, a: Int) -> Result[RgbaImage, Str]
pub fn image_rgba_to_gray(img: &RgbaImage) -> Vec[UInt8]
pub fn image_gray_to_rgba(gray: &Vec[UInt8], width: Int, height: Int) -> Result[RgbaImage, Str]
pub fn image_rgba_to_bgra(img: &RgbaImage) -> Vec[UInt8]
pub fn image_bgra_to_rgba(bgra: &Vec[UInt8], width: Int, height: Int) -> Result[RgbaImage, Str]

pub fn image_decode_bmp(data: &Vec[UInt8]) -> Result[RgbaImage, Str]
pub fn image_decode_ppm(data: &Vec[UInt8]) -> Result[RgbaImage, Str]
pub fn image_decode(data: &Vec[UInt8]) -> Result[RgbaImage, Str]
pub fn image_encode_bmp24(img: &RgbaImage) -> Result[Vec[UInt8], Str]
pub fn image_encode_bmp32(img: &RgbaImage) -> Result[Vec[UInt8], Str]
pub fn image_encode_ppm(img: &RgbaImage) -> Result[Vec[UInt8], Str]
pub fn image_encode(img: &RgbaImage, target: Int) -> Result[Vec[UInt8], Str]
```

## Sniffing rules

| Format | Test, in order | Result |
|---|---|---|
| BMP | `42 4D` at 0 | `IMG_FMT_BMP` |
| PNG | `89 50 4E 47 0D 0A 1A 0A` at 0 | `IMG_FMT_PNG` |
| JPEG | `FF D8 FF` at 0 | `IMG_FMT_JPEG` |
| GIF | `GIF87a` or `GIF89a` at 0 | `IMG_FMT_GIF` |
| PPM | `P6` at 0 | `IMG_FMT_PPM` |
| TGA | v2 footer signature `TRUEVISION-XFILE.\0` in the last 26 bytes, or an 18-byte header with color-map type <= 1, an image type of 1/2/3/9/10/11 consistent with the color-map type, a matching pixel depth (15/16/24/32 for true-color, 8/16 otherwise) and non-zero width/height | `IMG_FMT_TGA` |
| otherwise | -- | `IMG_FMT_UNKNOWN` |

TGA has no leading magic; the header heuristic is deliberately last and is
documented as a classification, not a validation. Formats with exact
signatures always win.

## Metadata semantics

- **BMP**: full header validation (see codec subset), then width/height/bits.
- **PNG**: 8-byte signature already matched; requires >= 24 bytes and an
  `IHDR` type at bytes 12..15; width/height are big-endian at 16..23, bit depth
  byte 24.
- **JPEG**: scans marker segments from offset 2 for the first SOF marker
  (C0-C3, C5-C7, C9-CB, CD-CF); height/width are big-endian inside the segment.
  Standalone markers (01, D0-D9) carry no length; a segment length < 2 aborts.
- **GIF**: width/height are little-endian at bytes 6..9; bits is reported 8.
- **PPM**: strict P6 header parse; bits is reported 8.
- **TGA**: width/height little-endian at 12..15, bits = pixel depth byte 16.

## Documented codec subset

### BMP 24/32-bit

Canonical 14-byte `BITMAPFILEHEADER` + 40-byte `BITMAPINFOHEADER`
(`data_offset` is taken from the file header). Constraints enforced:
`dib >= 40`, `1 <= width <= 1000000`, `0 < abs(height) <= 1000000`, planes = 1,
bits = 24 or 32, compression = 0, and `data_offset + row_bytes * abs(height)`
within the buffer.

- Decode reads B, G, R (and A for 32-bit) per pixel, converts to packed RGBA
  (24-bit alpha = 255), flips bottom-up storage to the top-left origin, and
  skips 4-byte row padding.
- Encode emits `"BM"`, total size (`54 + row_bytes * height`), reserved zeros,
  pixel offset 54, DIB size 40, width, height, planes 1, bits, compression 0,
  image size, 2835 px/m resolution, zero colors/important, then bottom-up rows
  of B, G, R (and A) with zero padding. 32-bit output preserves alpha.

### PPM P6

Strict grammar: `P6`, whitespace, decimal width, whitespace, decimal height,
whitespace, decimal maxval, exactly one whitespace byte, raster. No comments
are supported; each decimal token is at most 9 digits. `maxval` must be in
1..255, and decode additionally requires exactly 255 (no rescaling).
Dimensions are capped at 1000000 and `data_offset + width * height * 3` must
fit. Encode always writes the canonical header `P6\n<w> <h>\n255\n` followed by
top-down RGB.

## Conversions

| Function | Transform |
|---|---|
| `image_rgba_to_rgb` | drop alpha, compact rows (skips stride padding) |
| `image_rgb_to_rgba` | insert constant alpha; `pixels.len()` must equal `w*h*3` |
| `image_rgba_to_gray` | `(77*R + 150*G + 29*B + 128) / 256` (Rec.601, truncating integer division; alpha ignored) |
| `image_gray_to_rgba` | replicate sample into R, G, B; alpha 255 |
| `image_rgba_to_bgra` / `image_bgra_to_rgba` | swap bytes 0 and 2, keep alpha at byte 3 |

Reference luma values: red 77, green 149, blue 29, white 255, black 0.

## Validation and errors

All errors are `Result[..., Str]` with an `image: ` prefix.

| Condition | Message |
|---|---|
| BMP buffer < 54 bytes | `image: truncated bmp header` |
| BMP bytes 0-1 not `BM` | `image: bad bmp magic` |
| BMP DIB size < 40 | `image: unsupported bmp dib header` |
| BMP width <= 0 or > 1,000,000 | `image: invalid bmp width` |
| BMP height 0 or abs > 1,000,000 | `image: invalid bmp height` |
| BMP planes != 1 | `image: invalid bmp planes` |
| BMP bits not 24/32 | `image: unsupported bmp bit depth` |
| BMP compression != 0 | `image: unsupported bmp compression` |
| BMP raster beyond buffer | `image: bmp pixel data out of bounds` |
| PPM < 3 bytes or header ends early | `image: truncated ppm header` |
| PPM magic != `P6` | `image: bad ppm magic` |
| PPM token separator missing | `image: missing ppm whitespace` |
| PPM width/height/maxval token missing | `image: missing ppm width` / `height` / `maxval` |
| PPM width/height 0 or > 1,000,000 | `image: invalid ppm width` / `image: invalid ppm height` |
| PPM maxval outside 1..255 | `image: unsupported ppm maxval` |
| PPM raster beyond buffer | `image: truncated ppm pixel data` |
| PNG < 24 bytes or missing IHDR | `image: truncated png header` / `image: missing png ihdr` |
| PNG zero dimensions | `image: invalid png dimensions` |
| JPEG without a valid SOF | `image: jpeg frame header not found` |
| GIF < 10 bytes or zero dimensions | `image: truncated gif header` / `image: invalid gif dimensions` |
| TGA < 18 bytes or zero dimensions | `image: truncated tga header` / `image: invalid tga dimensions` |
| Sniff found nothing | `image: unknown format` |
| decode of PNG/JPEG/GIF/TGA/unknown | `image: unsupported format for decode` |
| PPM decode with maxval != 255 | `image: unsupported ppm maxval` |
| encode target not `IMG_ENC_*` | `image: unsupported format for encode` |
| Constructor non-positive width/height | `image: invalid width` / `image: invalid height` |
| Channel outside 0..255 | `image: channel out of range` |
| `stride < width * 4` | `image: invalid stride` |
| Buffer length != expected | `image: pixel buffer size mismatch` |
| Encoded BMP size exceeds 32 bits | `image: image too large` |

`image_get_rgba` returns `-1` and `image_set_rgba` returns `false` for
out-of-range coordinates; `image_set_rgba` also returns `false` for channel
values outside 0..255.

## Bounds, caps and determinism

- Every dimension is capped at 1,000,000; every raster is required to fit the
  input buffer before a decode loop starts, so loop counts are bounded by the
  buffer length. The JPEG scan advances by at least one byte per iteration and
  stops once fewer than 10 bytes remain.
- Integer division is truncation toward zero; all divisions in this module act
  on non-negative values (pixel bytes, strides, dimensions).
- Byte reads are widened as `(b as Int) & 0xFF`, so pixel bytes >= 128 never
  sign-extend.

## Test plan

24 checks in `tests/test_conformance.xi`, no external files:

1. format names for all six formats and unknown;
2. sniff of an encoded BMP;
3. PNG signature + IHDR metadata;
4. JPEG SOI sniff + APP0/SOF0 segment scan;
5. GIF89a logical screen metadata;
6. PPM sniff + metadata + `image_decode` round trip;
7. TGA heuristic sniff + header metadata (and all-zero header rejection);
8. empty/text buffers sniff unknown and fail metadata;
9. BMP 24-bit round trip through the unified pipeline;
10. BMP 32-bit round trip preserving low alpha;
11. BMP 24-bit canonical header, bottom-up order, padding bytes;
12. negative-height (top-down) BMP parse + decode;
13. PPM P6 canonical header/raster byte layout;
14. unified `image_encode` dispatch and invalid-target/broken-image rejection;
15. decode rejection for PNG/JPEG/empty;
16. BMP truncated header + bad magic;
17. BMP unsupported depth, compression, zero width, truncated raster;
18. BMP metadata fields;
19. BMP 32-bit header fields and BGRA order;
20. 3px-wide BMP row padding (12-byte stride) round trip;
21. `image_rgba_to_rgb` stride compaction and `image_rgba_to_bgra` swap;
22. RGB/gray expansion to opaque RGBA + mismatch rejection;
23. Rec.601 luma for primaries, white, black;
24. BGRA round trip and pixel set/get bounds.

## Known limitations

- Compression, palettes and sub-byte depths are out of scope; unsupported
  inputs are rejected at header validation, never partially decoded.
- Sniffing cannot distinguish some arbitrary 18-byte buffers from TGA; callers
  that need certainty should require a format code from a trusted source.
- BMP `data_offset` is not required to be >= 54; non-canonical offsets that
  still bound the raster correctly are accepted.
- PPM comments would break the strict header parse and are documented as
  unsupported.
