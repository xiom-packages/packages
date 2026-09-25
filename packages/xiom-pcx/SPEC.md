# xiom.pcx SPEC

## Scope

Pure-XIOM structural codec for ZSoft PCX images covering a documented subset:
the exact 128-byte header (parse and build), the 16-entry header palette, the
optional 769-byte VGA palette trailer at the end of the file, the RLE
pixel-data span between the header and the trailer, and validation of the
geometry, bytes-per-line, palette-type and plane/bits rules. Pixel data is
never decoded: the span is located and copied as opaque bytes.

## Non-goals

RLE packet encode/decode, pixel rendering or conversion of any depth, colour
management or scaling, the unencoded PCX variant (`encoding == 0`), streaming
I/O, multi-image containers, and validation of the RLE stream contents beyond
its span.

## Header layout (128 bytes)

| Offset | Size | Field | Rules |
|---|---|---|---|
| 0 | 1 | manufacturer | must be 10 (`0x0A`) |
| 1 | 1 | version | 0..5 (0 = 2.5, 5 = 3.0+) |
| 2 | 1 | encoding | must be 1 (RLE); 0 = unencoded is out of subset |
| 3 | 1 | bits per pixel per plane | 1, 2, 4 or 8 |
| 4 | 2 | xmin | little-endian, 0..65535 |
| 6 | 2 | ymin | little-endian, 0..65535 |
| 8 | 2 | xmax | little-endian, >= xmin |
| 10 | 2 | ymax | little-endian, >= ymin |
| 12 | 2 | hdpi | little-endian, 0..65535 |
| 14 | 2 | vdpi | little-endian, 0..65535 |
| 16 | 48 | header palette | 16 RGB triplets, entry `i` at `16 + 3*i` |
| 64 | 1 | reserved | informational; parsed and exposed, never validated |
| 65 | 1 | color planes | 1..4, constrained by the plane/bits table |
| 66 | 2 | bytes per line | little-endian, per plane: even and >= one scanline |
| 68 | 2 | palette type | 0/1 = colour or black-and-white, 2 = grayscale |
| 70 | 2 | h screen size | little-endian, 0..65535 |
| 72 | 2 | v screen size | little-endian, 0..65535 |
| 74 | 54 | filler | ignored on parse, zeroed on build |

Derived values:

- `width = xmax - xmin + 1` (PCX geometry is inclusive), 1..65536.
- `height = ymax - ymin + 1`, 1..65536.
- `pcx_scanline_bytes(width, bits) = ceil(width * bits / 8)`, the minimum
  `bytes_per_line`; larger even values are accepted as line padding.
- `pcx_decoded_bytes(h) = bytes_per_line * color_planes * height`.

`pcx_build_header` always writes manufacturer 10 and reserved 0, zeroes the 54
filler bytes, copies the 48 palette bytes verbatim, and ignores the derived
`width`/`height` fields of the input (they are recomputed by re-parsing).

## Trailer layout (769 bytes at the end of a file)

| Offset from `n - 769` | Size | Field |
|---|---|---|
| 0 | 1 | marker `0x0C` (12) |
| 1 | 768 | VGA palette: 256 RGB triplets, entry `i` at `n - 768 + 3*i` |

Detection (`pcx_has_vga_palette`) is: the buffer is at least 128 + 769 = 897
bytes long and byte `n - 769` equals 12. Requiring room for the header keeps
the marker out of the header for short buffers. The marker byte is not
validated beyond equality, and the palette bytes are not interpreted.

## Plane/bits table

| Palette type | Bits | Planes | Meaning |
|---|---|---|---|
| 0 or 1 | 1 | 1..4 | monochrome, 4-colour, 8-colour, 16-colour |
| 0 or 1 | 2 | 1 | 4-colour CGA |
| 0 or 1 | 4 | 1 | 16-colour |
| 0 or 1 | 8 | 1 | 256-colour indexed |
| 0 or 1 | 8 | 3 | 24-bit RGB |
| 0 or 1 | 8 | 4 | 32-bit RGBA |
| 2 | 1 | 1 | grayscale |
| 2 | 8 | 1 | grayscale |

Any other combination is `pcx: invalid plane configuration`. Palette type 2
with `color_planes != 1` is rejected by the same rule.

## Region layout

| Region | Start | Length |
|---|---|---|
| header | 0 | 128 |
| pixel data (RLE stream, opaque) | 128 | `trailer_offset - 128`, at least 1 |
| VGA palette trailer | `n - 769` | 769 (only when detected) |

`trailer_offset` is `n - 769` when the trailer is present, else `n`. A pixel
span shorter than one byte (for example a 128-byte header-only buffer, or a
897-byte buffer that is only header + trailer) is `pcx: truncated pixel data`.
Trailing bytes are otherwise allowed: without a trailer the whole tail after
the header is the pixel span.

## Validation order

`pcx_parse_header`:

1. buffer shorter than 128 bytes -> `pcx: truncated header`
2. manufacturer != 10 -> `pcx: bad manufacturer`
3. version > 5 -> `pcx: unsupported version`
4. encoding != 1 -> `pcx: unsupported encoding`
5. bits per pixel not 1/2/4/8 -> `pcx: invalid bits per pixel`
6. xmax < xmin, then ymax < ymin -> `pcx: invalid geometry`
7. color planes not 1..4 -> `pcx: invalid color planes`
8. bytes_per_line odd, then bytes_per_line < scanline bytes ->
   `pcx: invalid bytes per line`
9. palette type not 0/1/2 -> `pcx: invalid palette type`
10. bits/planes pair (and palette type 2 plane count) not in the table ->
    `pcx: invalid plane configuration`

`pcx_parse` runs the header validation first, then the trailer detection, then
the one-byte minimum span. `pcx_build_header` runs its own on-disk range
checks in this order -- palette size, version, encoding, bits per pixel, xmin,
ymin, xmax, ymax, hdpi, vdpi, color planes, bytes per line, palette type,
hscreen, vscreen -- assembles the 128 bytes, and re-validates them through
`pcx_parse_header`, forwarding its message unchanged (so reversed geometry,
odd `bytes_per_line`, bad plane combinations and the rest surface with the
parser message).

## API

```xiom
pub type PcxHeader = {
  manufacturer: Int; version: Int; encoding: Int; bits_per_pixel: Int;
  xmin: Int; ymin: Int; xmax: Int; ymax: Int; hdpi: Int; vdpi: Int;
  reserved: Int; color_planes: Int; bytes_per_line: Int; palette_type: Int;
  hscreen: Int; vscreen: Int; width: Int; height: Int;
}

pub type PcxInfo = {
  header: PcxHeader;
  has_vga_palette: Bool;
  trailer_offset: Int;   // n - 769 when present, else n
  pixel_offset: Int;     // always 128
  pixel_bytes: Int;      // trailer_offset - 128, at least 1
}

pub fn pcx_scanline_bytes(width: Int, bits_per_pixel: Int) -> Int
pub fn pcx_decoded_bytes(h: &PcxHeader) -> Int
pub fn pcx_parse_header(data: &Vec[UInt8]) -> Result[PcxHeader, Str]
pub fn pcx_build_header(h: &PcxHeader, palette: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn pcx_parse(data: &Vec[UInt8]) -> Result[PcxInfo, Str]
pub fn pcx_has_vga_palette(data: &Vec[UInt8]) -> Bool
pub fn pcx_pixel_offset(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn pcx_pixel_length(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn pcx_pixel_data(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn pcx_header_palette(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn pcx_header_palette_entry(data: &Vec[UInt8], index: Int) -> Result[Int, Str]
pub fn pcx_vga_palette(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn pcx_vga_palette_entry(data: &Vec[UInt8], index: Int) -> Result[Int, Str]
```

### Contract notes

- `pcx_parse_header` validates the 128 header bytes and the rules above. It
  does not require pixel data or a trailer to be present.
- `pcx_build_header` writes exactly 128 bytes; `palette` must be exactly 48
  bytes. The manufacturer is pinned to 10 and reserved to 0.
- `pcx_parse` requires at least one pixel byte; it does not validate the RLE
  stream.
- `pcx_pixel_offset` returns 128; `pcx_pixel_length` returns the RLE byte
  count; `pcx_pixel_data` copies that span. All three run the full parse.
- `pcx_header_palette` / `pcx_header_palette_entry` validate the header only.
  Entry indices are 0..15 and pack as `r * 65536 + g * 256 + b`.
- `pcx_vga_palette` / `pcx_vga_palette_entry` validate the header and then
  require a detected trailer. Entry indices are 0..255.
- `pcx_has_vga_palette` inspects only the length and the marker byte.
- All functions are free functions; no pixel data is interpreted.

## Error catalog

| Condition | Message |
|---|---|
| buffer shorter than 128 bytes | `pcx: truncated header` |
| manufacturer != 10 | `pcx: bad manufacturer` |
| version > 5 | `pcx: unsupported version` |
| encoding != 1 | `pcx: unsupported encoding` |
| bits per pixel not 1/2/4/8 | `pcx: invalid bits per pixel` |
| xmax < xmin or ymax < ymin (zero or negative geometry) | `pcx: invalid geometry` |
| color planes not 1..4 | `pcx: invalid color planes` |
| bytes_per_line odd or below `pcx_scanline_bytes(width, bits)` | `pcx: invalid bytes per line` |
| palette type not 0/1/2 | `pcx: invalid palette type` |
| bits/planes pair not in the table (including palette type 2 with planes != 1) | `pcx: invalid plane configuration` |
| fewer than one byte between header and trailer (or end of buffer) | `pcx: truncated pixel data` |
| `pcx_vga_palette` / entry accessor without a trailer | `pcx: missing vga palette trailer` |
| header palette entry index outside 0..15 | `pcx: palette index out of range` |
| VGA palette entry index outside 0..255 | `pcx: vga palette index out of range` |
| `pcx_build_header` with a palette that is not 48 bytes | `pcx: invalid palette size` |
| builder hdpi/vdpi outside 0..65535 | `pcx: invalid resolution` |
| builder hscreen/vscreen outside 0..65535 | `pcx: invalid screen size` |

`pcx_build_header` also forwards every parser message above (`unsupported
version`, `unsupported encoding`, `invalid bits per pixel`, `invalid
geometry`, `invalid color planes`, `invalid bytes per line`, `invalid palette
type`, `invalid plane configuration`) after its own range checks.

## Test matrix

| # | Check |
|---|---|
| 1 | Hand-built 1x1 8bpp header decodes every field, including derived width/height. |
| 2 | `pcx_build_header` pins all 128 bytes (LE fields, palette, reserved, filler) and round-trips. |
| 3 | Header palette bytes copy and `0xRRGGBB` entries for index 0/15, plus index range errors. |
| 4 | VGA trailer detection, offset, extraction of all 768 bytes and packed entry 0/255, index 256 error. |
| 5 | Without a trailer: span runs to the file end, palette accessors report the missing trailer. |
| 6 | Marker corruption extends the span; 896/897-byte detection boundaries; zero-byte span rejected. |
| 7 | Truncated header (empty, 127 bytes) and header-only buffer (`truncated pixel data`). |
| 8 | Manufacturer 0/11/255 rejected, 10 accepted. |
| 9 | Encoding 0/2/255 rejected, 1 accepted. |
| 10 | Versions 0..5 accepted, 6 and 255 rejected. |
| 11 | Reversed and wrapped geometry rejected; inclusive width/height and max-coordinate 1x1 accepted. |
| 12 | `bytes_per_line` odd/zero/too-small rejected, even padding accepted; `pcx_scanline_bytes` table. |
| 13 | Bits per pixel 0/3/16/255 rejected, 1/2/4/8 accepted. |
| 14 | Planes 0/5/255 rejected; invalid 2/4/8-bit two-plane combinations rejected; valid 1/3/4-plane combinations accepted. |
| 15 | Palette type 3/255/1000 rejected; grayscale 1bpp/8bpp accepted, grayscale 4bpp/3-plane rejected. |
| 16 | Span accessors (`pixel_offset`, `pixel_length`, `pixel_data`, `pcx_decoded_bytes`) with and without a trailer. |
| 17 | Builder range errors: version, encoding, geometry, bytes per line, planes, palette type, resolution, screen size, palette size; valid input Ok. |
| 18 | Full round-trip: built header + RLE bytes + optional trailer, field-for-field, palette and span byte-match. |

## Known limitations

- No RLE decode; the pixel span is opaque, so a stream that does not decode to
  `pcx_decoded_bytes` of output is not detected.
- Trailer detection is positional and marker-only: a file without a trailer
  whose byte at `n - 769` happens to be `0x0C` is misdetected as carrying one.
- 2 bpp with multiple planes and 4 bpp with multiple planes are rejected even
  though some encoders emit them.
- Reserved and filler header bytes are not validated; the reserved byte is
  exposed for callers that care.
- The whole buffer is in memory; there is no streaming API.
