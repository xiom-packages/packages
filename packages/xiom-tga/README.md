# xiom.tga

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (18/18); NOT published yet.
> **Scope:** Truevision TGA structural codec for a documented subset: 18-byte header parse/build, 26-byte v2 footer parse/build and version detection, image ID / color map / uncompressed raster location, and validation. No pixel decoding.
> **Deps:** `xiom.std` only (the library module imports nothing). No FFI in v0.1.

## What it is

`xiom.tga` reads and writes the structural parts of Truevision TGA (Targa)
files: the 18-byte header, the optional image ID field, the optional color map
data block, the uncompressed raster region, and the TGA 2.0 footer that carries
the `TRUEVISION-XFILE.` signature. It is a pure-XIOM byte codec -- no pixel is
ever decoded, no color map entry is interpreted, and no RLE packet is
expanded. That makes it the right building block for validators, converters,
metadata inspectors, and downstream decoders that want a hardened front end.

The supported subset is small on purpose:

| Image type | Meaning | Pixel depth | Color map |
|---|---|---|---|
| 0 | no image data | must be 0 | must be absent; width = height = 0 |
| 1 | uncompressed, color-mapped | 8 or 16 | required |
| 2 | uncompressed, true-color | 15, 16, 24 or 32 | optional (pass-through) |
| 3 | uncompressed, black-and-white | 8 or 16 | optional (pass-through) |
| 9 | RLE, color-mapped | 8 or 16 | required |
| 10 | RLE, true-color | 15, 16, 24 or 32 | optional (pass-through) |
| 11 | RLE, black-and-white | 8 or 16 | optional (pass-through) |

Image ID bytes and color map bytes are copied verbatim. For uncompressed types
the raster length is computed exactly (`bytes_per_pixel * width * height`); for
RLE types only the raster offset is located, because the packet stream has no
declared length. Extension and developer areas are bounds-checked but opaque.

## API

| Function | Returns | Description |
|---|---|---|
| `tga_parse_header(data)` | `Result[TgaHeader, Str]` | Validate the 18-byte header and decode every field. |
| `tga_build_header(h)` | `Result[Vec[UInt8], Str]` | Emit 18 header bytes; validates field ranges and the same cross-field rules as the parser. |
| `tga_parse(data)` | `Result[TgaImage, Str]` | Full-buffer parse: header, ID, color map, raster bounds, v2 footer. |
| `tga_parse_footer(data)` | `Result[TgaFooter, Str]` | Validate the trailing 26 bytes and return both 32-bit area offsets. |
| `tga_build_footer(ext, dev)` | `Result[Vec[UInt8], Str]` | Emit the 26-byte footer with the pinned signature. |
| `tga_has_footer(data)` | `Bool` | True when the buffer ends with the exact v2 signature plus NUL. |
| `tga_detect_version(data)` | `Int` | 2 with a valid v2 footer, 1 otherwise (TGA 1.0 has no footer). |
| `tga_id_field(data)` | `Result[Vec[UInt8], Str]` | Copy the image ID bytes (empty when `id_length` is 0). |
| `tga_color_map_data(data)` | `Result[Vec[UInt8], Str]` | Copy the color map bytes (empty when no map is declared). |
| `tga_image_data(data)` | `Result[Vec[UInt8], Str]` | Copy the uncompressed raster; RLE types are rejected. |
| `tga_data_bytes(h)` | `Int` | Raster length: exact for uncompressed, 0 for type 0, `-1` for RLE. |
| `tga_bytes_per_pixel(depth)` | `Int` | `ceil(depth / 8)`; 0 for depth 0. |
| `tga_is_rle(image_type)` | `Bool` | True for types 9, 10 and 11. |

## Install / use

```
xiom pkg install xiom.tga@0.1.0     # consumer
```

Then import the module from any XIOM source file with `use xiom.tga;`. The
library pulls in nothing but `xiom.std` as a platform dependency.

## Quick start

```xiom
use xiom.tga;

// Read a whole TGA file (bytes from disk, network, ...).
let parsed = tga_parse(bytes);
match parsed {
  Ok(img) => {
    // img.header.width, img.header.height, img.header.pixel_depth, ...
    // img.data_offset + img.data_bytes is the uncompressed raster region.
    // img.version is 1 or 2; img.extension_offset is 0 when absent.
    let id = tga_id_field(bytes);
    let cmap = tga_color_map_data(bytes);
  },
  Err(e) => { /* e is a tga:-prefixed message, see SPEC.md */ },
}

// Build a header + footer and assemble a version 2 file yourself.
let h = TgaHeader{
  id_length: 0; color_map_type: 0; image_type: 2; cmap_first: 0;
  cmap_length: 0; cmap_entry_bits: 0; x_origin: 0; y_origin: 0;
  width: 320; height: 200; pixel_depth: 24; attribute_bits: 0; origin_bits: 2;
};
let header = tga_build_header(h);   // 18 bytes
let footer = tga_build_footer(0, 0); // 26 bytes, signature included
```

## Error model

Every fallible function returns `Result[..., Str]` with deterministic messages
prefixed `tga: `. Structural failures are distinguished from truncation:
unknown image type, inconsistent color map fields, zero dimensions, invalid
depth per type, and truncation of each declared region each have their own
message. Builder-only range errors (for example `tga: invalid image id
length`) are documented in SPEC.md. `tga_image_data` returns
`tga: image data length unknown for RLE` for types 9/10/11 instead of guessing
a length.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.tga
```

18 conformance checks cover header field decode, little-endian header/footer
byte pinning, signature-exact v2 detection, v1/v2 full parses, ID/color
map/raster slices, depth and RLE helpers, unknown image types, zero
dimensions, the type 0 rules, per-type depth validation, color map
consistency, region truncation, footer signature errors, RLE location
semantics, offset bounds, all seven supported image types, and a full
build-then-parse v2 round-trip.

## Limitations

- No pixel decoding: 15/16/24/32-bit samples, color map entries and RLE
  packets stay opaque byte runs.
- No extension area field parsing (gamma, aspect ratio, software ID, author,
  key color, ...) and no developer directory parsing.
- No RLE raster length; `tga_image_data` rejects RLE types.
- Descriptor bits 6-7 (TGA 1.0 interleaving) are ignored on parse and written
  as zero on build.
- v2 area offsets are bounds-checked only: a non-zero offset must leave at
  least two bytes inside the buffer; area contents are never inspected.
- The whole file is held in memory; there is no streaming API.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
