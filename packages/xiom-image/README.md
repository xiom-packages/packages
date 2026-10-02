# xiom.image

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** unified image front door: magic-byte format sniffing, metadata
> extraction, a packed RGBA8 pixel model with explicit stride, RGBA/RGB/gray/
> BGRA conversion, and a documented pure proof codec subset (BMP 24/32-bit
> decode+encode, PPM P6 decode+encode). PNG/JPEG/GIF/TGA are recognized and
> described but not decoded.
> **Deps:** `xiom.std` only (the library module itself imports nothing; the
> tests use `xiom.test` and `xiom.io`). No FFI, no cross-package imports.

## What it is

`xiom.image` is the shared dispatcher layer for image bytes in the ecosystem.
It exists so consumers do not each re-implement signature checks, dimension
extraction and channel shuffling, and so the pixel conventions are written down
once:

- **Sniffing** classifies BMP, PNG, JPEG, GIF, PPM (P6) and TGA from magic
  bytes (TGA via a structural header heuristic), returning an `IMG_FMT_*` code.
- **Metadata** extracts width, height, bit depth and format without decoding
  the raster (PNG IHDR, GIF logical screen descriptor, JPEG SOF scan, PPM/P6
  header, TGA header, BMP DIB header).
- **Pixel model** is packed RGBA8 in a row-major `Vec[UInt8]` with explicit
  `width`, `height` and `stride`; every producer here compacts to
  `stride == width * 4`.
- **Conversion** covers RGBA -> RGB (alpha dropped), RGB -> RGBA (constant
  alpha), RGBA -> gray (Rec.601 integer luma), gray -> RGBA, and the RGBA <->
  BGRA channel swap.
- **Proof codecs** decode BMP 24/32-bit (bottom-up and top-down, padded rows)
  and PPM P6 (maxval 255), and encode BMP 24-bit, BMP 32-bit and PPM P6.

## Libs inventory

| Lib | Description | Key API |
|-----|-------------|---------|
| `format` | Format sniffing and image metadata extraction | `image_sniff`, `image_format_name`, `image_meta`, `image_bmp_header`, `image_ppm_header` |
| `decode` | Unified image decode pipeline with format detection | `image_decode`, `image_decode_bmp`, `image_decode_ppm` |
| `encode` | Unified image encode pipeline to a target format | `image_encode`, `image_encode_bmp24`, `image_encode_bmp32`, `image_encode_ppm` |
| `convert` | Pixel format and color space conversion | `image_rgba_to_rgb`, `image_rgb_to_rgba`, `image_rgba_to_gray`, `image_gray_to_rgba`, `image_rgba_to_bgra`, `image_bgra_to_rgba` |
| `pixel` | Packed RGBA8 model, constructors, accessors | `RgbaImage`, `image_new_rgba`, `image_from_rgba`, `image_get_rgba`, `image_set_rgba`, `image_copy` |

## API

| Function | Returns | Description |
|---|---|---|
| `image_sniff(data)` | `Int` | `IMG_FMT_*` code from magic bytes |
| `image_format_name(fmt)` | `Str` | `"bmp"`, `"png"`, ..., `"unknown"` |
| `image_meta(data)` | `Result[ImageMeta, Str]` | width/height/format/bits without decoding |
| `image_bmp_header(data)` | `Result[BmpHeader, Str]` | validated 14+40-byte BMP header |
| `image_ppm_header(data)` | `Result[PpmHeader, Str]` | strict P6 header + raster offset |
| `image_new_rgba(w, h, r, g, b, a)` | `Result[RgbaImage, Str]` | uniform packed RGBA image |
| `image_from_rgba(w, h, stride, pixels)` | `Result[RgbaImage, Str]` | adopt a strided buffer |
| `image_width/height/stride(img)` | `Int` | accessors |
| `image_get_rgba(img, x, y)` | `Int` | packed `0xRRGGBBAA`, `-1` out of range |
| `image_set_rgba(img, x, y, r, g, b, a)` | `Bool` | false out of range/bad channel |
| `image_copy(img)` | `RgbaImage` | deep copy compacted to `stride == width * 4` |
| `image_rgba_to_rgb(img)` | `Vec[UInt8]` | compact RGB triplets |
| `image_rgb_to_rgba(rgb, w, h, a)` | `Result[RgbaImage, Str]` | expand with constant alpha |
| `image_rgba_to_gray(img)` | `Vec[UInt8]` | Rec.601 luma `(77R + 150G + 29B + 128) / 256` |
| `image_gray_to_rgba(gray, w, h)` | `Result[RgbaImage, Str]` | expand to opaque RGBA |
| `image_rgba_to_bgra(img)` | `Vec[UInt8]` | channel swap, alpha kept |
| `image_bgra_to_rgba(bgra, w, h)` | `Result[RgbaImage, Str]` | inverse channel swap |
| `image_decode(data)` | `Result[RgbaImage, Str]` | unified decode (sniff + explicit dispatch) |
| `image_decode_bmp(data)` | `Result[RgbaImage, Str]` | BMP 24/32-bit |
| `image_decode_ppm(data)` | `Result[RgbaImage, Str]` | PPM P6 (maxval 255) |
| `image_encode(img, target)` | `Result[Vec[UInt8], Str]` | unified encode (`IMG_ENC_*`) |
| `image_encode_bmp24/bmp32/ppm(img)` | `Result[Vec[UInt8], Str]` | concrete encoders |

Types: `RgbaImage`, `ImageMeta`, `BmpHeader`, `PpmHeader`. Format codes:
`IMG_FMT_UNKNOWN/BMP/PNG/JPEG/GIF/PPM/TGA`; encoder targets:
`IMG_ENC_BMP24/BMP32/PPM`.

Errors are `Result[..., Str]` with `image: `-prefixed messages; see `SPEC.md`
for the full catalog.

## Usage

```xiom
use xiom.image;

let fmt = image_sniff(bytes);              // IMG_FMT_BMP / ... / IMG_FMT_UNKNOWN
match image_meta(bytes) {
  Ok(m) => { /* m.width, m.height, m.format, m.bits */ },
  Err(e) => { /* handle */ },
}
match image_decode(bytes) {
  Ok(img) => { /* rgba_1x1 = image_get_rgba(&img, 0, 0) */ },
  Err(e) => { /* unsupported or malformed */ },
}
```

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom-image
```

24 conformance checks, no external files: every fixture is built in memory
(hand-assembled signatures and headers plus encoder output). Coverage includes
all six sniff paths, metadata extraction for five containers, JPEG SOF0
scanning, BMP 24/32 round trips, bottom-up/top-down storage, 4-byte row
padding, PPM header byte layout, stride compaction, channel conversion, luma
values for primaries, pixel bounds, and malformed-header rejection.

## Limitations

- PNG, JPEG, GIF and TGA payloads are sniffed and described only; no pixels are
  decoded from them (their codecs live in their own packages).
- BMP subset: uncompressed 24/32-bit, canonical 40-byte DIB header; no RLE,
  palettes, 1/4/8/16-bit depths, BITFIELDS or ICC profiles.
- PPM subset: binary P6, maxval 255 for decode, no comments in the header,
  no P3 or 16-bit samples.
- TGA sniffing is a documented heuristic (v2 footer signature or a consistent
  18-byte header), not a decode.
- Integer-only, whole-buffer API: no streaming, scaling, blending or ICC.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
