# xiom.dds

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (18/18); NOT published yet.
> **Scope:** DirectDraw Surface (DDS) header codec for a documented subset: "DDS " magic, the 124-byte `DDS_HEADER` (with its 32-byte `DDS_PIXELFORMAT`), the optional 20-byte `DDS_HEADER_DXT10` block, payload span access and a canonical builder. No pixel or block decoding.
> **Deps:** `xiom.std` only (the library module imports `xiom.string` for fourCC text). No FFI in v0.1.

## What it is

`xiom.dds` reads and writes the structural parts of DirectDraw Surface
textures: the 4-byte `"DDS "` magic, the fixed 124-byte `DDS_HEADER`, the
embedded 32-byte `DDS_PIXELFORMAT`, the optional 20-byte
`DDS_HEADER_DXT10` block that follows a `DX10` fourCC, and the opaque payload
that starts at byte 128 (or 148 with the DXT10 block). It is a pure-XIOM byte
codec -- no block is decompressed, no mip level is sliced and no format is
converted -- which makes it the right front end for validators, asset
pipelines, metadata inspectors and downstream decoders.

The supported subset is small on purpose:

| Pixel format | Rules |
|---|---|
| uncompressed RGB(A) | `DDPF_RGB`, `RGBBitCount` 16/24/32, nonzero pairwise-disjoint R/G/B masks (plus optional A mask) inside the bit count |
| DXT1..DXT5 | `DDPF_FOURCC` with the fourCC codes `DXT1`, `DXT2`, `DXT3`, `DXT4`, `DXT5`; recognized |
| DX10 | `DDPF_FOURCC` with `DX10`; requires the 20-byte `DDS_HEADER_DXT10` block |
| anything else | any other nonzero fourCC (e.g. `UYVY`, `ATI2`, `BC4U`) is accepted and passed through; `dds_fourcc_recognized` reports whether the codec knows the code |

Other data flags (`DDPF_ALPHA`, `DDPF_YUV`, `DDPF_LUMINANCE`, palettes) are
outside the subset and rejected. Dimensionality is structural only: volume
textures keep `depth`, cube maps keep their `caps2` bits, DX10 arrays keep
`array_size`, and the payload is never split into faces or mip levels.

## API

| Function | Returns | Description |
|---|---|---|
| `dds_parse(data)` | `Result[DdsImage, Str]` | Full-buffer parse: header, DXT10 block when present, payload span. |
| `dds_parse_header(data)` | `Result[DdsHeader, Str]` | Validate the 128-byte prefix and decode every header field. |
| `dds_is_valid(data)` | `Bool` | True when `dds_parse` succeeds. |
| `dds_build_header(h)` | `Result[Vec[UInt8], Str]` | Emit the 128-byte `"DDS "` + `DDS_HEADER` prefix; re-validated through the parser. |
| `dds_build_dx10(d)` | `Result[Vec[UInt8], Str]` | Emit the 20-byte `DDS_HEADER_DXT10` block. |
| `dds_build(img, payload)` | `Result[Vec[UInt8], Str]` | Emit a whole file: prefix, DXT10 block when used, payload verbatim. |
| `dds_payload(data)` | `Result[Vec[UInt8], Str]` | Copy the payload span (empty for a header-only buffer). |
| `dds_fourcc_text(code)` | `Str` | Four characters in file byte order (`DXT1`, `DX10`, `UYVY`, ...); `""` for 0. |
| `dds_fourcc_recognized(code)` | `Bool` | True for DXT1..DXT5 and DX10. |
| `dds_pixel_format_supported(flags, four_cc)` | `Bool` | True when the flag shape is inside the documented subset. |
| `dds_width(img)` / `dds_height(img)` | `Int` | Texture dimensions. |
| `dds_depth(img)` | `Int` | Volume depth: 0 for 2D/cube, >= 1 for volumes. |
| `dds_mipmaps(img)` | `Int` | Stored `mipMapCount` (0 means one level). |
| `dds_fourcc(img)` | `Int` | The pixel format fourCC code (0 when none). |
| `dds_has_dx10(img)` | `Bool` | True when the DXT10 block is present. |
| `dds_dxgi_format(img)` | `Int` | `dxgiFormat` from the DXT10 block. |
| `dds_resource_dimension(img)` | `Int` | `resourceDimension` (2, 3 or 4 when present). |
| `dds_array_size(img)` | `Int` | `arraySize` from the DXT10 block. |
| `dds_misc_flag(img)` / `dds_misc_flags2(img)` | `Int` | The two misc fields. |
| `dds_rgb_bit_count(img)` | `Int` | `RGBBitCount` (0 for fourCC formats). |
| `dds_red_mask(img)` / `dds_green_mask(img)` / `dds_blue_mask(img)` / `dds_alpha_mask(img)` | `Int` | Channel masks (0 for fourCC formats). |
| `dds_payload_offset(img)` | `Int` | 128 without the DXT10 block, 148 with it. |
| `dds_payload_size(img)` | `Int` | Payload length (buffer end minus offset). |

Public constants cover the magic, the fixed offsets/sizes, the `DDSD_*`,
`DDPF_*`, `DDSCAPS*` flag bits and the six fourCC codes (`DDS_FOURCC_DXT1` ..
`DDS_FOURCC_DX10`).

## Install / use

```
xiom pkg install xiom.dds@0.1.0     # consumer
```

Then import the module from any XIOM source file with `use xiom.dds;`. The
library pulls in nothing but `xiom.std` as a platform dependency.

## Quick start

```xiom
use xiom.dds;

// Inspect a DDS file (bytes from disk, network, ...).
let parsed = dds_parse(bytes);
match parsed {
  Ok(img) => {
    // img.header.width, dds_width(&img), dds_fourcc_text(dds_fourcc(&img)), ...
    // img.data_offset..img.data_offset + img.data_bytes is the opaque payload.
    // dds_has_dx10(&img) tells whether the DXT10 block was present.
    let fmt = dds_fourcc_text(dds_fourcc(&img));   // "" for uncompressed RGB
  },
  Err(e) => { /* e is a dds:-prefixed message, see SPEC.md */ },
}

// Rebuild a file: dds_build round-trips a parsed image byte-for-byte.
let payload = dds_payload(bytes);
match payload {
  Ok(p) => {
    let out = dds_build(&img, &p);
  },
  Err(e) => { /* handle */ },
}

// Build a canonical uncompressed header yourself.
let h = DdsHeader{
  size: 124;
  flags: DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT + DDSD_PITCH;
  height: 64; width: 32; pitch_or_linear_size: 96; depth: 0; mip_map_count: 0;
  pixel_format: DdsPixelFormat{
    size: 32; flags: DDPF_RGB; four_cc: 0; rgb_bit_count: 24;
    r_mask: 0x00FF0000; g_mask: 0x0000FF00; b_mask: 0x000000FF; a_mask: 0;
  };
  caps: DDSCAPS_TEXTURE; caps2: 0; caps3: 0; caps4: 0; reserved2: 0;
};
let prefix = dds_build_header(&h);   // 128 bytes, DXT10 block not included
```

## Error model

Every fallible function returns `Result[..., Str]` with deterministic
`dds: `-prefixed messages. Truncation, bad magic, wrong size fields,
nonzero `reserved1`, missing required flags, conflicting pitch flags, zero or
oversized dimensions, depth/mipmap flag mismatches, volume-without-depth,
pixel-format flag and mask inconsistencies, and DXT10 field errors each have
their own message; the builder adds field range errors and the two
cross-checks (`dds: dx10 flag mismatch`, `dds: payload size mismatch`). The
full catalog and the validation order are in SPEC.md.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.dds
```

18 conformance checks cover the pinned little-endian prefix bytes, all RGB
accessors, payload span/copy and truncation, the fourCC text/recognition
tables, DXT1..DXT5 plus DX10 and pass-through fourCC fixtures, byte-for-byte
`dds_build` round-trips with and without the DXT10 block, and every
validation rule in the error catalog.

## Limitations

- No pixel, block, DXT or mip decoding; the payload is one opaque span, so
  cube-map faces and mip levels are not sliced apart.
- No format conversion, color management or surface layout computation
  (`pitchOrLinearSize` is carried, never recomputed).
- The documented subset is strict: `reserved1` must be zero, the four
  required `DDSD_*` flags must be set, palettes/luminance/YUV flag shapes
  are rejected, and dimensions are capped at 1,000,000.
- `dxgiFormat` is passed through without a known-format table; only
  `resourceDimension` (2..4) and `arraySize` (>= 1) are validated.
- The whole buffer is in memory; there is no streaming API.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
