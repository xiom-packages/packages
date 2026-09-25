# xiom.tga SPEC

## Scope

Pure-XIOM structural codec for Truevision TGA (Targa) files, covering the
TGA 1.0 18-byte header and the TGA 2.0 26-byte footer, the optional image ID
field, the optional color map data block, and the location of the image data
for the seven standard image type codes. Rasters are never decoded; the codec
validates structure, computes uncompressed raster lengths, and hands back
exact byte slices.

## Non-goals

Pixel decoding of any depth, RLE packet encode/decode, color map entry
interpretation, extension area field parsing (gamma, key color, software ID,
author, comments, ...), developer directory parsing, TGA 1.0 interleaved
images (descriptor bits 6-7), multi-image containers, streaming I/O, and
scaling or color management.

## Header layout (18 bytes)

| Offset | Size | Field | Rules |
|---|---|---|---|
| 0 | 1 | image ID length | 0..255 |
| 1 | 1 | color map type | 0 = absent, 1 = present |
| 2 | 1 | image type | 0, 1, 2, 3, 9, 10 or 11 |
| 3 | 2 | color map first entry index | little-endian, 0..65535 |
| 5 | 2 | color map length | little-endian, entries, 0..65535 |
| 7 | 1 | color map entry size | 15, 16, 24 or 32 bits when a map is present |
| 8 | 2 | X origin | little-endian, 0..65535 |
| 10 | 2 | Y origin | little-endian, 0..65535 |
| 12 | 2 | width | little-endian, 0..65535 |
| 14 | 2 | height | little-endian, 0..65535 |
| 16 | 1 | pixel depth | 0, 8, 15, 16, 24 or 32 bits |
| 17 | 1 | image descriptor | bits 0-3 attribute bits, bit 4 right-to-left, bit 5 top-to-bottom, bits 6-7 reserved |

## Footer layout (26 bytes, at the end of a v2 file)

| Footer offset | File offset | Size | Field |
|---|---|---|---|
| 0 | n-26 | 4 | extension area offset, little-endian, 0 = absent |
| 4 | n-22 | 4 | developer area offset, little-endian, 0 = absent |
| 8 | n-18 | 16 | ASCII `TRUEVISION-XFILE` |
| 24 | n-2 | 1 | ASCII `.` |
| 25 | n-1 | 1 | NUL (`0x00`) |

## Region layout

| Region | Start | Length |
|---|---|---|
| header | 0 | 18 |
| image ID | 18 | `id_length` |
| color map data | `18 + id_length` | `cmap_length * ceil(cmap_entry_bits / 8)` |
| image data | `cmap_offset + cmap_bytes` | uncompressed: `ceil(pixel_depth / 8) * width * height`; type 0: 0; RLE types: unknown |
| extension area | `extension_offset` | opaque, bounds-checked only |
| developer area | `developer_offset` | opaque, bounds-checked only |
| footer | `n - 26` | 26 (v2 only) |

Trailing bytes beyond the declared uncompressed raster are allowed: v2 files
carry extension and developer areas and padding between the raster and the
footer, and v1 files may carry vendor data.

## Version detection

A buffer is version 2 if and only if it is at least 26 bytes long and bytes
`n-18 .. n-1` are exactly `TRUEVISION-XFILE.` followed by NUL. Every other
buffer is version 1. TGA 1.0 by definition has no footer, so a missing v2
signature is only an error for `tga_parse_footer` (which, by contract, parses
a footer and requires one); `tga_parse` and `tga_detect_version` treat a
missing signature as version 1.

## Field rules

| Image type | Pixel depth | Color map type | Dimensions |
|---|---|---|---|
| 0 | must be 0 | must be 0 with `cmap_length == 0` | width = height = 0 |
| 1, 9 | 8 or 16 | must be 1 | width > 0, height > 0 |
| 2, 10 | 15, 16, 24 or 32 | 0 or 1 | width > 0, height > 0 |
| 3, 11 | 8 or 16 | 0 or 1 | width > 0, height > 0 |

Color map rules:

- `color_map_type` must be 0 or 1.
- `color_map_type == 1` requires `cmap_length > 0` and an entry size of 15,
  16, 24 or 32 bits, and the color map data must fit in the buffer.
- `color_map_type == 0` requires `cmap_length == 0`.
- Image types 1 and 9 require a color map. Image types 2, 3, 10 and 11 accept
  a present color map and pass it through untouched (the map is unused for
  those types).

Derived values:

- `attribute_bits = descriptor & 0x0F`, `origin_bits = (descriptor >> 4) & 0x03`.
- `bytes_per_pixel = ceil(pixel_depth / 8)`; 15- and 16-bit pixels occupy two
  bytes each, 24-bit three, 32-bit four, 8-bit one.
- Descriptor bits 6-7 are ignored on parse and written as zero by
  `tga_build_header`.

## API

```xiom
pub type TgaHeader = {
  id_length: Int; color_map_type: Int; image_type: Int; cmap_first: Int;
  cmap_length: Int; cmap_entry_bits: Int; x_origin: Int; y_origin: Int;
  width: Int; height: Int; pixel_depth: Int; attribute_bits: Int;
  origin_bits: Int;
}

pub type TgaFooter = { extension_offset: Int; developer_offset: Int; }

pub type TgaImage = {
  header: TgaHeader;
  version: Int;            // 1 or 2
  id_offset: Int;          // always 18
  cmap_offset: Int;        // 18 + id_length
  cmap_bytes: Int;
  data_offset: Int;
  data_bytes: Int;         // uncompressed length, 0 for type 0, -1 for RLE
  extension_offset: Int;   // 0 when absent
  developer_offset: Int;   // 0 when absent
}

pub fn tga_parse_header(data: &Vec[UInt8]) -> Result[TgaHeader, Str]
pub fn tga_build_header(h: &TgaHeader) -> Result[Vec[UInt8], Str]
pub fn tga_parse_footer(data: &Vec[UInt8]) -> Result[TgaFooter, Str]
pub fn tga_build_footer(extension_offset: Int, developer_offset: Int) -> Result[Vec[UInt8], Str]
pub fn tga_has_footer(data: &Vec[UInt8]) -> Bool
pub fn tga_detect_version(data: &Vec[UInt8]) -> Int
pub fn tga_parse(data: &Vec[UInt8]) -> Result[TgaImage, Str]
pub fn tga_id_field(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn tga_color_map_data(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn tga_image_data(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn tga_data_bytes(h: &TgaHeader) -> Int
pub fn tga_bytes_per_pixel(pixel_depth: Int) -> Int
pub fn tga_is_rle(image_type: Int) -> Bool
```

### Contract notes

- `tga_parse_header` validates the 18 header bytes and the field rules above.
  It does not require the image ID, color map data or raster to be present.
- `tga_build_header` checks every field against its on-disk width, assembles
  the 18 bytes, and re-validates them through the same parser, forwarding its
  message. Descriptor bits 6-7 are zeroed.
- `tga_parse` walks the layout in order: header, image ID, color map, raster,
  then v2 footer. Uncompressed rasters must fit entirely in the buffer; an RLE
  raster only has to start inside the buffer. Non-zero v2 area offsets must
  leave at least two bytes inside the buffer (room for the area size field).
- `tga_parse_footer` requires the exact signature; a buffer shorter than 26
  bytes is `tga: truncated footer`, and a missing/corrupt signature is
  `tga: missing v2 signature`.
- `tga_id_field` and `tga_color_map_data` validate the header plus just the
  ID/color map region; they do not require the raster.
- `tga_image_data` runs the full parse (so raster bounds are enforced), then
  rejects RLE types because their length is unknown.
- `tga_build_footer` accepts offsets in 0..4294967295 (0 = absent).
- All functions are free functions; no pixel data is interpreted.

## Error catalog

| Condition | Message |
|---|---|
| buffer shorter than 18 bytes | `tga: truncated header` |
| image type not 0/1/2/3/9/10/11 | `tga: unknown image type` |
| color map type not 0 or 1 | `tga: invalid color map type` |
| image type 0 with a color map, or color map type 0 with `cmap_length != 0` | `tga: unexpected color map` |
| pixel depth not allowed for the image type (including type 0 with depth != 0) | `tga: unsupported pixel depth` |
| width 0 with a raster type, or width != 0 with image type 0 | `tga: invalid width` |
| height 0 with a raster type, or height != 0 with image type 0 | `tga: invalid height` |
| image type 1/9 without a color map | `tga: color map required for image type` |
| color map type 1 with `cmap_length == 0` | `tga: invalid color map length` |
| color map entry size not 15/16/24/32 with a map present | `tga: invalid color map entry size` |
| buffer shorter than `18 + id_length` | `tga: truncated image id` |
| color map data beyond the buffer | `tga: truncated color map` |
| uncompressed raster beyond the buffer, or no byte at `data_offset` for RLE | `tga: truncated image data` |
| footer parse on a buffer shorter than 26 bytes | `tga: truncated footer` |
| no exact v2 signature in the trailing 26 bytes | `tga: missing v2 signature` |
| v2 extension offset != 0 and > n-2 | `tga: extension area out of bounds` |
| v2 developer offset != 0 and > n-2 | `tga: developer area out of bounds` |
| `tga_image_data` on image type 9/10/11 | `tga: image data length unknown for RLE` |
| builder `id_length` outside 0..255 | `tga: invalid image id length` |
| builder `cmap_first` outside 0..65535 | `tga: invalid color map first index` |
| builder `x_origin` / `y_origin` outside 0..65535 | `tga: invalid x origin`, `tga: invalid y origin` |
| builder `attribute_bits` outside 0..15 | `tga: invalid attribute bits` |
| builder `origin_bits` outside 0..3 | `tga: invalid origin bits` |
| builder footer offset negative or above 2^32-1 | `tga: invalid extension offset`, `tga: invalid developer offset` |

`tga_build_header` also forwards every parser message above (`unknown image
type`, `unsupported pixel depth`, `invalid width`, `invalid height`, color map
messages) after its own range checks.

## Validation order

`tga_parse_header`: truncation, color map type, image type, type 0 rules,
per-type pixel depth, width, height, color map requirements, color map
presence/length/entry size. `tga_parse`: header, image ID, color map, raster,
footer. `tga_parse_footer`: truncation, signature, extension bounds, developer
bounds. Tests assert exact messages so this order stays observable.

## Test matrix

| # | Check |
|---|---|
| 1 | Hand-built 2x3 24-bit header decodes all 13 fields, including descriptor attribute/origin split. |
| 2 | `tga_build_header` pins all 18 little-endian bytes and round-trips a color-mapped header. |
| 3 | `tga_build_footer` pins the 26-byte layout (including `TRUEVISION-XFILE.` + NUL) and round-trips, plus 32-bit LE byte order. |
| 4 | `tga_has_footer` / `tga_detect_version`: v2, v1, short buffers, corrupt terminator and corrupt signature byte. |
| 5 | v1 uncompressed true-color file: every offset (`id`/`cmap`/`data`), version 1, raster ending at buffer end. |
| 6 | v2 color-mapped file with image ID: offsets 18/22/28, ID/color-map/raster slices, 8-bit indices. |
| 7 | Empty ID for `id_length == 0`; raster slices byte-match the source; 4x2 32-bit raster length 32. |
| 8 | `tga_bytes_per_pixel`, `tga_is_rle` and `tga_data_bytes` tables, including -1 for RLE. |
| 9 | Unknown image types 4, 5, 8, 12, 255 rejected by header parse and full parse. |
| 10 | Zero width/height rejected; type 0 accepts only all-zero dimensions/depth and no map. |
| 11 | Pixel depth per type: true-color 8/0, color-mapped 24, grayscale 24/0 rejected; 8/16/15/32 accepted. |
| 12 | Color map consistency: required map, zero length, bad entry size, unexpected map, bad map type; pass-through map accepted. |
| 13 | Truncation: header (0/17 bytes), image ID, color map, uncompressed raster. |
| 14 | Footer parse: 25-byte buffer, all-zero tail, corrupt NUL, corrupt signature byte. |
| 15 | RLE: `data_bytes == -1`, `tga_image_data` rejected, empty RLE raster truncated, RLE with map/footer located. |
| 16 | Extension/developer offsets: small values round-trip, `n-2` boundary accepted, `n-1`/oversized rejected. |
| 17 | All seven image types parse in valid buffers (type 0, 1, 2, 3, 9, 10, 11). |
| 18 | Full build-then-parse v2 round-trip: header, ID, raster, footer offsets, nested header fields and signature position. |

## Known limitations

- 15- and 16-bit pixel depths are counted as two bytes per pixel; the
  attribute-bit convention of 16-bit true-color pixels is not interpreted.
- RLE raster length cannot be computed; `tga_image_data` rejects those types
  and the footer is still detected (the packet stream may overlap trailing
  areas in malformed files).
- Extension and developer areas are bounds-checked only: a non-zero offset
  must leave at least two bytes inside the buffer, but the area contents are
  never parsed, and offsets pointing into the header or raster are accepted.
- A v2 footer is required to be the final 26 bytes; a file with trailing junk
  after the footer is reported as version 1.
- The whole buffer is in memory; there is no streaming API.
