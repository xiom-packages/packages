# xiom.bmp SPEC

## Scope

Pure-XIOM parsing and building of uncompressed BMP images, targeting 24-bit and 32-bit pixel data with the canonical 54-byte header layout (14-byte `BITMAPFILEHEADER` + 40-byte `BITMAPINFOHEADER`).

## Non-goals

Compression (RLE/BITFIELDS), palettes, indexed depths (1/4/8/16-bit), OS/2 DIB variants, ICC/color management, scaling.

## API

```xiom
pub type BmpInfo = { width: Int; height: Int; bits: Int; data_offset: Int; row_bytes: Int; }

pub fn bmp_row_bytes(width: Int, bits: Int) -> Int
pub fn bmp_parse_header(data: &Vec[UInt8]) -> Result[BmpInfo, Str]
pub fn bmp_pixel_rgb(data: &Vec[UInt8], x: Int, y: Int) -> Result[Int, Str]
pub fn bmp_build_24(rgb: &Vec[UInt8], width: Int, height: Int) -> Result[Vec[UInt8], Str]
```

## Semantics

- `height` follows the format: positive = rows stored bottom-up (standard), negative = top-down.
- `bmp_pixel_rgb` uses a top-left origin for every storage order; it ignores the alpha byte on 32-bit images.
- Row stride is always padded to a 4-byte boundary: `bmp_row_bytes`.
- 24-bit pixels are stored B, G, R; 32-bit pixels are stored B, G, R, A.
- `bmp_build_24` writes: `"BM"`, total size, reserved zeros, pixel offset 54, DIB size 40, width, height, planes 1, bits 24, compression 0, image size, 2835 px/m resolution, zero colors/important, then bottom-up padded BGR rows.

## Validation and errors

| Condition | Message |
|---|---|
| buffer < 54 bytes | `bmp: truncated header` |
| bytes 0-1 not `BM` | `bmp: bad magic` |
| DIB header size < 40 | `bmp: unsupported DIB header` |
| width <= 0 or > 1,000,000 | `bmp: invalid width` |
| height 0 or abs(height) > 1,000,000 | `bmp: invalid height` |
| planes != 1 | `bmp: invalid planes` |
| bits not in {24, 32} | `bmp: unsupported bit depth` |
| compression != 0 | `bmp: unsupported compression` |
| pixel data exceeds the buffer | `bmp: pixel data out of bounds` |
| pixel coordinate outside the image | `bmp: pixel out of range` |
| builder size mismatch / bad dimensions | `bmp: pixel buffer size mismatch`, `bmp: invalid width`, `bmp: invalid height` |

## Test plan

18 checks: stride table for widths 1-5 at 24/32 bits; built 2x2 header fields and total size; 2x2 and 3x1 pixel round-trips through the padded layout; byte-level bottom-up and padding inspection; hand-built 32-bit BGRA image; out-of-range coordinates; bad magic, truncation, unsupported depth, compression, planes, oversized width, DIB < 40; negative-height top-down reading; builder size mismatch and zero dimensions; all-pixel 5x7 round-trip.

## Known limitations

- No streaming; the whole image is in memory.
- `bmp_parse_header` does not require the stored file-size field to equal the buffer length (many real-world writers pad it).
- Integer-only API; no dithering or resampling helpers.
