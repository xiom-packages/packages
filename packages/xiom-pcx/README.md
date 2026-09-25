# xiom.pcx

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (18/18); NOT published yet.
> **Scope:** PCX structural codec for a documented subset: 128-byte header parse/build, 16-entry header palette, optional 768-byte VGA palette trailer detection and extraction, RLE pixel-data span location, and validation. No RLE packet is ever expanded and no pixel is decoded.
> **Deps:** `xiom.std` only (the library module imports nothing). No FFI in v0.1.

## What it is

`xiom.pcx` reads and writes the structural parts of ZSoft PCX images: the
128-byte header, the 16 RGB triplets stored inside it, the optional VGA
palette trailer (a `0x0C` marker followed by 768 bytes of 256-colour palette
at the end of the file), and the opaque RLE byte span between the header and
that trailer. It is a pure-XIOM byte codec -- no RLE packet is expanded, no
pixel is rendered, no colour is interpreted. That makes it the right building
block for validators, metadata inspectors, converters and downstream decoders
that want a hardened front end.

The supported subset is small on purpose:

| Palette type | Bits per pixel | Planes | Meaning |
|---|---|---|---|
| 0 or 1 (colour / B&W) | 1 | 1..4 | monochrome / 4 / 8 / 16 colours |
| 0 or 1 | 2 | 1 | 4-colour CGA |
| 0 or 1 | 4 | 1 | 16-colour |
| 0 or 1 | 8 | 1 | 256-colour indexed |
| 0 or 1 | 8 | 3 | 24-bit RGB |
| 0 or 1 | 8 | 4 | 32-bit RGBA |
| 2 (grayscale) | 1 or 8 | 1 | grayscale |

Only RLE encoding (`encoding == 1`) is accepted; PCX files with the unencoded
variant (`encoding == 0`) are rejected as out of subset. Geometry is inclusive
(`width = xmax - xmin + 1`), `bytes_per_line` must be even and at least
`ceil(width * bits_per_pixel / 8)` (larger even values are accepted as
padding), and `palette_type` must be 0, 1 or 2.

## API

| Function | Returns | Description |
|---|---|---|
| `pcx_parse_header(data)` | `Result[PcxHeader, Str]` | Validate the 128-byte header and decode every field. |
| `pcx_build_header(h, palette)` | `Result[Vec[UInt8], Str]` | Emit 128 header bytes from a header and a 48-byte palette; re-validates through the parser. |
| `pcx_parse(data)` | `Result[PcxInfo, Str]` | Full-buffer parse: header, trailer detection, pixel span. |
| `pcx_has_vga_palette(data)` | `Bool` | True when the buffer ends with the 769-byte trailer (marker `0x0C` at `n - 769`). |
| `pcx_pixel_offset(data)` | `Result[Int, Str]` | Offset of the first RLE byte (always 128). |
| `pcx_pixel_length(data)` | `Result[Int, Str]` | Number of RLE bytes before the trailer (or the end of the buffer). |
| `pcx_pixel_data(data)` | `Result[Vec[UInt8], Str]` | Copy the opaque RLE span. |
| `pcx_header_palette(data)` | `Result[Vec[UInt8], Str]` | Copy the 48 raw header-palette bytes (16 RGB triplets). |
| `pcx_header_palette_entry(data, i)` | `Result[Int, Str]` | Packed `0xRRGGBB` of header entry `i` (`0..15`). |
| `pcx_vga_palette(data)` | `Result[Vec[UInt8], Str]` | Copy the 768 trailer bytes; Err when no trailer is present. |
| `pcx_vga_palette_entry(data, i)` | `Result[Int, Str]` | Packed `0xRRGGBB` of trailer entry `i` (`0..255`). |
| `pcx_scanline_bytes(width, bits)` | `Int` | Minimum bytes per scanline per plane: `ceil(width * bits / 8)`. |
| `pcx_decoded_bytes(h)` | `Int` | Decoded image size in bytes: `bytes_per_line * planes * height`. |

## Install / use

```
xiom pkg install xiom.pcx@0.1.0     # consumer
```

Then import the module from any XIOM source file with `use xiom.pcx;`. The
library pulls in nothing but `xiom.std` as a platform dependency.

## Quick start

```xiom
use xiom.pcx;

// Read a whole PCX file (bytes from disk, network, ...).
let parsed = pcx_parse(bytes);
match parsed {
  Ok(info) => {
    // info.header.width, info.header.height, info.header.bits_per_pixel, ...
    // info.pixel_offset .. info.pixel_offset + info.pixel_bytes is the RLE span.
    // info.has_vga_palette tells whether the 768-byte trailer is present.
    let pix = pcx_pixel_data(bytes);   // opaque RLE bytes, never expanded
    if info.has_vga_palette {
      let vga = pcx_vga_palette(bytes);       // 768 bytes
      let c0 = pcx_vga_palette_entry(bytes, 0); // packed 0xRRGGBB
    }
  },
  Err(e) => { /* e is a pcx:-prefixed message, see SPEC.md */ },
}

// Build a 128-byte header for a 320x200 256-colour image.
let h = PcxHeader{
  manufacturer: 10; version: 5; encoding: 1; bits_per_pixel: 8;
  xmin: 0; ymin: 0; xmax: 319; ymax: 199;
  hdpi: 72; vdpi: 72; reserved: 0; color_planes: 1;
  bytes_per_line: 320; palette_type: 1; hscreen: 640; vscreen: 480;
  width: 0; height: 0;
};
let header = pcx_build_header(h, palette48);  // 128 bytes
```

## Error model

Every fallible function returns `Result[..., Str]` with deterministic
messages prefixed `pcx: `. Truncation, wrong manufacturer, unsupported
version or encoding, bad geometry, an odd or too-small bytes-per-line value,
an unsupported plane configuration and a bad palette type each have their own
message; header errors are forwarded unchanged by `pcx_parse` and
`pcx_build_header`. Builder-only range errors (`pcx: invalid palette size`,
`pcx: invalid resolution`, `pcx: invalid screen size`) are documented in
SPEC.md. Palette accessors report `pcx: missing vga palette trailer` when the
trailer is absent and `pcx: palette index out of range` /
`pcx: vga palette index out of range` for out-of-range entries.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.pcx
```

18 conformance checks cover hand-built header decode, exact 128-byte build
pinning and round-trip, header palette bytes and packed entries, VGA trailer
detection and extraction (including marker corruption and the 896/897-byte
boundaries), spans with and without a trailer, truncation of header and pixel
span, manufacturer/encoding/version/geometry/bits/planes/bytes-per-line and
palette-type validation, plane-configuration tables, palette index range
errors, builder range errors, and full files assembled from built headers with
and without the trailer.

## Limitations

- No RLE packet expansion and no pixel decoding of any depth; the pixel span
  is an opaque byte run.
- The unencoded PCX variant (`encoding == 0`) is rejected; only `encoding == 1`
  belongs to the supported subset.
- 2 bpp is supported with one plane only, 8 bpp with 1, 3 or 4 planes; other
  plane/bits combinations are rejected.
- Trailer detection inspects only the length and the byte at `n - 769`; a
  non-trailer file whose byte at that position happens to be `0x0C` is
  reported as carrying a trailer, and the 769 bytes are then treated as
  palette data.
- `bytes_per_line` larger than one scanline is accepted as padding; this
  codec never validates that RLE data actually decodes to that size.
- The reserved header byte and the 54 filler bytes are exposed (reserved) or
  ignored (filler), never validated.
- The whole file is held in memory; there is no streaming API.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
