# xiom.ppm

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (18/18); NOT published yet.
> **Scope:** Netpbm PPM (P3 ASCII and P6 binary) header parsing, 8-bit P6 pixel access with a top-left origin, and canonical P3/P6 builders.
> **Deps:** `xiom.std` only. No FFI in v0.1.

## API

| Function | Description |
|----------|-------------|
| `ppm_parse_header(data)` | Parses magic `P3`/`P6`, width, height and maxval (whitespace-separated decimal tokens, `#` comments skipped) and returns `PpmImage` with the validated `data_offset` |
| `ppm_pixel_rgb(data, x, y)` | Returns `0xRRGGBB` for a **top-left origin** coordinate; P6 with `maxval <= 255` only |
| `ppm_build_p6(rgb, width, height)` | Builds `"P6\n<w> <h>\n255\n"` plus raw RGB bytes (no padding) |
| `ppm_build_p3(rgb, width, height, samples_per_line)` | Builds `"P3\n<w> <h>\n255\n"` plus decimal samples, one space between samples, wrapped to `samples_per_line` (values `< 1` clamp to 1) and LF-terminated |
| `ppm_sample_count(img)` | `width * height * 3` |

Errors are `Result[..., Str]` with `ppm: `-prefixed messages. For P6, `data_offset` is the first raster byte; for P3 it is the first sample token.

## Format notes

- The header is `P3`/`P6`, then width, height and maxval as decimal tokens separated by Netpbm whitespace (SPACE, TAB, LF, CR, VT, FF). A `#` comment runs to the end of the line and acts as a separator.
- After maxval, a P6 raster starts right after exactly one whitespace byte. For P6 with `maxval > 255` the parser expects two bytes per sample and rejects pixel access.
- P3 stores samples as ASCII decimals for the same 8-bit values; its `data_offset` points at the first character of the first sample.
- Pixels are row-major, top-left origin, three samples per pixel (R, G, B). PPM rows have no padding.

## Usage

```xiom
use xiom.ppm;

let built = ppm_build_p6(pixels_rgb_top_down, 320, 200);
match built {
  Ok(bytes) => { /* write bytes, or parse them back */ },
  Err(e) => { /* handle ppm: invalid ... */ },
}

match ppm_parse_header(bytes) {
  Ok(img) => { /* img.width, img.height, img.maxval, img.data_offset */ },
  Err(e) => { /* handle */ },
}
```

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.ppm
```

18 conformance tests cover P6/P3 header fields and offsets, comments, all six whitespace kinds, maxval and magic validation, truncation, exact padding-free P6 bytes, out-of-range coordinates, 16-bit and P3 accessor rejection, exact builder headers/lengths, pinned P3 wrapping, size-mismatch and dimension errors, sample counts, and an all-pixel 5x7 round-trip.

## Limitations

- 8-bit samples only for pixel access (`maxval <= 255`); 16-bit P6 headers parse but `ppm_pixel_rgb` returns `ppm: 16-bit samples unsupported`.
- P3/P6 only: no PGM (P2/P5), no PBM (P1/P4), no PAM (P7).
- No streaming, scaling, dithering, or color-space conversion; the whole raster is in memory.
- `ppm_build_p3` always emits `maxval 255` and never writes comments.
