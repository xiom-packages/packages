# xiom.bmp

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (18/18); NOT published yet.
> **Scope:** Uncompressed BMP (24-bit and 32-bit) header parsing, pixel access with top-left origins, and a minimal 24-bit builder.
> **Deps:** `xiom.std` only. No FFI in v0.1.

## API

| Function | Description |
|----------|-------------|
| `bmp_parse_header(data)` | Validates the file header plus 40-byte DIB header and returns `BmpInfo` (width, height, bits, data offset, row stride) |
| `bmp_pixel_rgb(data, x, y)` | Returns `0xRRGGBB` for a **top-left origin** coordinate; handles bottom-up rows and 4-byte row padding; 32-bit BGRA ignores alpha |
| `bmp_build_24(rgb, width, height)` | Builds a standard 24-bit BMP from top-down RGB triples (bottom-up storage and padding are emitted for you) |
| `bmp_row_bytes(width, bits)` | Row stride in bytes: `((width * bits + 31) / 32) * 4` |

Errors are `Result[..., Str]` with `bmp: `-prefixed messages. `BmpInfo.height` is positive for bottom-up storage (the standard) and negative for top-down storage.

## Usage

```xiom
use xiom.bmp;
let img = bmp_build_24(pixels_rgb_top_down, 320, 200);
match img {
  Ok(bytes) => { /* write bytes, or parse them back */ },
  Err(e) => { /* handle */ },
}
```

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.bmp
```

18 conformance tests cover the stride table, 24/32-bit parsing, bottom-up byte layout, padding, out-of-range pixels, malformed headers, and an all-pixel 5x7 round-trip.

## Limitations

- Uncompressed BMP only: no RLE, no palettes, no 1/4/8/16-bit depths, no ICC profiles.
- `bmp_build_24` emits a canonical 40-byte DIB header; the file-size field is written correctly but `bmp_parse_header` does not require it to match the buffer length.
- Pixels are byte-addressed; there is no scaling, blending, or color-space conversion.
