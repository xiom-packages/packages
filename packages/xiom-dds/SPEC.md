# xiom.dds SPEC

## Scope

Pure-XIOM structural codec for DirectDraw Surface (DDS) containers: the
`"DDS "` magic, the fixed 124-byte `DDS_HEADER` with its embedded 32-byte
`DDS_PIXELFORMAT`, the optional 20-byte `DDS_HEADER_DXT10` block selected by
the `DX10` fourCC, the payload offset (128 or 148), and a canonical builder.
The payload is opaque: it is located and copied verbatim, never decoded.

## Non-goals

Pixel, block or mip decoding of any kind (DXT1..DXT5 and DX10 payloads stay
byte runs); mip level or cube-map face slicing; DXGI format interpretation
beyond carrying `dxgiFormat`; format conversion; surface layout computation
(`pitchOrLinearSize` is carried but never recomputed or checked against the
dimensions); legacy palettized, luminance, alpha-only or YUV *data* formats;
streaming I/O; DDS files embedded in other containers.

## Container layout

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `"DDS "` (0x20534444 little-endian) |
| 4 | 4 | `DDS_HEADER.size`, must be 124 |
| 8 | 4 | `flags` (`DDSD_*`) |
| 12 | 4 | `height` |
| 16 | 4 | `width` |
| 20 | 4 | `pitchOrLinearSize` |
| 24 | 4 | `depth` (volume textures; 0 for 2D and cube) |
| 28 | 4 | `mipMapCount` |
| 32 | 44 | `reserved1[11]`, must be all zero in the documented subset |
| 76 | 4 | `DDS_PIXELFORMAT.size`, must be 32 |
| 80 | 4 | pixel format `flags` (`DDPF_*`) |
| 84 | 4 | pixel format `fourCC` (little-endian code, 0 = none) |
| 88 | 4 | `RGBBitCount` |
| 92 | 4 | `RBitMask` |
| 96 | 4 | `GBitMask` |
| 100 | 4 | `BBitMask` |
| 104 | 4 | `ABitMask` |
| 108 | 4 | `caps` (`DDSCAPS_*`) |
| 112 | 4 | `caps2` (`DDSCAPS2_*`) |
| 116 | 4 | `caps3` |
| 120 | 4 | `caps4` |
| 124 | 4 | `reserved2` (retained verbatim, not validated) |

The payload starts at byte 128. When the pixel format uses the `DX10` fourCC,
the 20-byte `DDS_HEADER_DXT10` block sits at bytes 128..148 and the payload
starts at 148:

| Offset | Size | Field |
|---|---|---|
| 128 | 4 | `dxgiFormat` (passed through) |
| 132 | 4 | `resourceDimension` (2, 3 or 4) |
| 136 | 4 | `miscFlag` (passed through) |
| 140 | 4 | `arraySize` (>= 1) |
| 144 | 4 | `miscFlags2` (passed through) |

All multi-byte fields are little-endian.

## Pixel format rules

The two data flags must never be combined:

- `DDPF_FOURCC` set, `DDPF_RGB` clear: `fourCC` must be nonzero. `RGBBitCount`
  and the four masks are carried through untouched (some writers set them for
  YUV codes such as `UYVY`). `DXT1`..`DXT5` and `DX10` are recognized; any
  other nonzero code is accepted and passed through. `DX10` additionally
  requires the 20-byte DXT10 block.
- `DDPF_RGB` set, `DDPF_FOURCC` clear: `fourCC` must be 0. `RGBBitCount`
  must be 16, 24 or 32. The R, G and B masks must be nonzero, pairwise
  disjoint, and each must fit the bit count (<= 2^bits - 1). A nonzero alpha
  mask must be disjoint from the color masks and also fit the bit count.
- Neither flag: `dds: unsupported pixel format` (palettes, luminance, YUV
  data, alpha-only formats are outside the subset).
- Both flags: `dds: conflicting pixel format flags`.

`dds_pixel_format_supported(flags, four_cc)` is the predicate form of the
flag-shape rules: exactly one of `DDPF_FOURCC` (code nonzero) and `DDPF_RGB`
(code zero). It does not repeat the bit-count/mask checks; those are parser
errors.

## Validation rules and order

`dds_parse_header` checks, in this order (tests assert the exact messages):

1. `data.len() < 128` -> `dds: truncated header`.
2. Bytes 0..3 not `"DDS "` -> `dds: bad magic`.
3. Header size != 124 -> `dds: invalid header size`.
4. Any of `reserved1[0..11]` nonzero -> `dds: nonzero reserved1`.
5. `(flags & (DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT))`
   not all set -> `dds: missing required flags`.
6. `DDSD_PITCH` and `DDSD_LINEARSIZE` both set -> `dds: conflicting pitch flags`.
7. `height == 0` or `height > 1000000` -> `dds: invalid height`.
8. `width == 0` or `width > 1000000` -> `dds: invalid width`.
9. `depth > 0` without `DDSD_DEPTH` -> `dds: depth without DDSD_DEPTH`.
10. `DDSD_DEPTH` set with `depth == 0` -> `dds: invalid depth`.
11. `mipMapCount > 0` without `DDSD_MIPMAPCOUNT` -> `dds: mipmaps without DDSD_MIPMAPCOUNT`.
12. `DDSD_MIPMAPCOUNT` set with `mipMapCount == 0` -> `dds: invalid mipmap count`.
13. Pixel format: size != 32 -> `dds: invalid pixel format size`; then the
    flag-shape and mask rules above.
14. `(caps2 & DDSCAPS2_VOLUME)` set with `depth == 0` -> `dds: volume without depth`.

`dds_parse` runs the header checks, then when the fourCC is `DX10`:

15. `data.len() < 148` -> `dds: truncated dx10 header`.
16. `resourceDimension` outside 2..4 -> `dds: invalid resource dimension`.
17. `arraySize == 0` -> `dds: invalid array size`.

Then it computes `data_offset` (128 or 148) and
`data_bytes = data.len() - data_offset`; the payload may be empty.

## API

```xiom
pub type DdsPixelFormat = {
  size: Int; flags: Int; four_cc: Int; rgb_bit_count: Int;
  r_mask: Int; g_mask: Int; b_mask: Int; a_mask: Int;
}

pub type DdsHeader = {
  size: Int; flags: Int; height: Int; width: Int; pitch_or_linear_size: Int;
  depth: Int; mip_map_count: Int; pixel_format: DdsPixelFormat;
  caps: Int; caps2: Int; caps3: Int; caps4: Int; reserved2: Int;
}

pub type DdsDxt10 = {
  dxgi_format: Int; resource_dimension: Int; misc_flag: Int;
  array_size: Int; misc_flags2: Int;
}

pub type DdsImage = {
  header: DdsHeader; dx10: DdsDxt10; has_dx10: Bool;
  data_offset: Int; data_bytes: Int;
}

pub fn dds_parse(data: &Vec[UInt8]) -> Result[DdsImage, Str]
pub fn dds_parse_header(data: &Vec[UInt8]) -> Result[DdsHeader, Str]
pub fn dds_is_valid(data: &Vec[UInt8]) -> Bool
pub fn dds_build_header(h: &DdsHeader) -> Result[Vec[UInt8], Str]
pub fn dds_build_dx10(d: &DdsDxt10) -> Result[Vec[UInt8], Str]
pub fn dds_build(img: &DdsImage, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn dds_payload(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str]

pub fn dds_width(img: &DdsImage) -> Int
pub fn dds_height(img: &DdsImage) -> Int
pub fn dds_depth(img: &DdsImage) -> Int
pub fn dds_mipmaps(img: &DdsImage) -> Int
pub fn dds_fourcc(img: &DdsImage) -> Int
pub fn dds_has_dx10(img: &DdsImage) -> Bool
pub fn dds_dxgi_format(img: &DdsImage) -> Int
pub fn dds_resource_dimension(img: &DdsImage) -> Int
pub fn dds_array_size(img: &DdsImage) -> Int
pub fn dds_misc_flag(img: &DdsImage) -> Int
pub fn dds_misc_flags2(img: &DdsImage) -> Int
pub fn dds_rgb_bit_count(img: &DdsImage) -> Int
pub fn dds_red_mask(img: &DdsImage) -> Int
pub fn dds_green_mask(img: &DdsImage) -> Int
pub fn dds_blue_mask(img: &DdsImage) -> Int
pub fn dds_alpha_mask(img: &DdsImage) -> Int
pub fn dds_payload_offset(img: &DdsImage) -> Int
pub fn dds_payload_size(img: &DdsImage) -> Int

pub fn dds_fourcc_text(code: Int) -> Str
pub fn dds_fourcc_recognized(code: Int) -> Bool
pub fn dds_pixel_format_supported(flags: Int, four_cc: Int) -> Bool
```

Public constants: `DDS_MAGIC`, `DDS_HEADER_SIZE` (124),
`DDS_PIXEL_FORMAT_SIZE` (32), `DDS_DATA_OFFSET` (128), `DDS_DX10_OFFSET`
(148), the `DDSD_*`, `DDPF_*`, `DDSCAPS*` bits, and `DDS_FOURCC_DXT1` ..
`DDS_FOURCC_DXT5`, `DDS_FOURCC_DX10`.

### Contract notes

- `dds_parse_header` requires only the 128-byte prefix; the DXT10 block and
  payload are not required.
- `dds_parse` returns the DXT10 block zeroed when absent; `has_dx10` is
  derived from `DDPF_FOURCC` + the `DX10` code, never from the buffer length.
- `dds_fourcc_text` renders the code's four bytes in file byte order; bytes
  outside 0x20..0x7E render as `.`. Code 0 and codes above 2^32-1 return `""`.
- `dds_build_header` requires `h.size == 124` and `pf.size == 32`, writes
  `reserved1` as zero, range-checks every field to 0..4294967295, and
  re-validates the assembled bytes through `dds_parse_header`, forwarding its
  message unchanged. `reserved2` is emitted from the struct.
- `dds_build_dx10` range-checks all five fields, then requires
  `resource_dimension` in 2..4 and `array_size >= 1`.
- `dds_build` requires `img.has_dx10` to agree with the fourCC, requires
  `payload.len() == img.data_bytes`, emits prefix + optional DXT10 block +
  payload, and re-parses the result, so a successful build always parses back
  to the same header fields.
- `dds_payload` runs the full parse first, then copies
  `data_offset..data.len()`.
- All functions are free functions; no function is named `log`; no
  `Vec[StructType]` is declared.

## Error catalog

| Condition | Message |
|---|---|
| buffer shorter than 128 bytes | `dds: truncated header` |
| bytes 0-3 are not `DDS ` | `dds: bad magic` |
| `DDS_HEADER.size` != 124 | `dds: invalid header size` |
| any `reserved1` dword nonzero | `dds: nonzero reserved1` |
| required `DDSD_CAPS/HEIGHT/WIDTH/PIXELFORMAT` missing | `dds: missing required flags` |
| `DDSD_PITCH` and `DDSD_LINEARSIZE` both set | `dds: conflicting pitch flags` |
| width 0 or > 1,000,000 | `dds: invalid width` |
| height 0 or > 1,000,000 | `dds: invalid height` |
| `depth > 0` without `DDSD_DEPTH` | `dds: depth without DDSD_DEPTH` |
| `DDSD_DEPTH` with `depth == 0` | `dds: invalid depth` |
| `mipMapCount > 0` without `DDSD_MIPMAPCOUNT` | `dds: mipmaps without DDSD_MIPMAPCOUNT` |
| `DDSD_MIPMAPCOUNT` with `mipMapCount == 0` | `dds: invalid mipmap count` |
| pixel format size != 32 | `dds: invalid pixel format size` |
| `DDPF_FOURCC` and `DDPF_RGB` both set | `dds: conflicting pixel format flags` |
| `DDPF_FOURCC` with code 0 | `dds: missing fourCC` |
| `DDPF_RGB` with a nonzero code | `dds: unexpected fourCC` |
| RGB bit count not 16/24/32 | `dds: unsupported RGB bit count` |
| any RGB mask zero | `dds: invalid RGB masks` |
| color/alpha masks overlap | `dds: overlapping color masks` |
| mask exceeds 2^bits - 1 | `dds: color mask out of range` |
| neither `DDPF_FOURCC` nor `DDPF_RGB` | `dds: unsupported pixel format` |
| `DDSCAPS2_VOLUME` with `depth == 0` | `dds: volume without depth` |
| `DX10` fourCC with fewer than 148 bytes | `dds: truncated dx10 header` |
| `resourceDimension` outside 2..4 | `dds: invalid resource dimension` |
| `arraySize == 0` | `dds: invalid array size` |
| builder struct `size` != 124 | `dds: invalid header size` |
| builder pixel format `size` != 32 | `dds: invalid pixel format size` |
| builder field outside 0..4294967295 | `dds: flags out of range`, `dds: height out of range`, `dds: width out of range`, `dds: pitch out of range`, `dds: depth out of range`, `dds: mipmap count out of range`, `dds: pixel format flags out of range`, `dds: fourCC out of range`, `dds: RGB bit count out of range`, `dds: red mask out of range`, `dds: green mask out of range`, `dds: blue mask out of range`, `dds: alpha mask out of range`, `dds: caps out of range`, `dds: caps2 out of range`, `dds: caps3 out of range`, `dds: caps4 out of range`, `dds: reserved2 out of range`, `dds: dxgi format out of range`, `dds: resource dimension out of range`, `dds: misc flag out of range`, `dds: array size out of range`, `dds: misc flags2 out of range` |
| `img.has_dx10` disagrees with the fourCC | `dds: dx10 flag mismatch` |
| `payload.len()` != `img.data_bytes` | `dds: payload size mismatch` |

`dds_build_header` also forwards every parser message above after its own
range checks.

## Test matrix

| # | Check |
|---|---|
| 1 | Builder pins the 128-byte little-endian prefix (magic, sizes, flags, dimensions, zeroed `reserved1`, pixel format, caps) and round-trips every field. |
| 2 | RGB accessors report width, height, depth, mipmaps, fourCC, bit count, all four masks and payload span. |
| 3 | Payload span is `offset..end`; the copy is byte-exact; a 100-byte buffer is a truncated header. |
| 4 | fourCC text (`DXT1`..`DXT5`, `DX10`, `ATI2`, `BC4U`, `UYVY`, dots for non-printable, `""` for 0), recognition table and the supported-shape predicate. |
| 5 | DXT1 file parses with zeroed masks, correct flags and the text accessor. |
| 6 | Fixture with every accepted fourCC: DXT1..DXT5, DX10 and three pass-through codes all parse and round-trip. |
| 7 | DX10 file: 148-byte prefix, block fields, offset 148, byte-for-byte `dds_build` reproduction. |
| 8 | Non-DX10 file: 152-byte build, byte-for-byte `dds_build` reproduction, deterministic header builder. |
| 9 | Truncation (127), corrupt magic (two positions), header size 123, pixel format size 31, nonzero `reserved1`, retained/re-emitted `reserved2`. |
| 10 | Missing `DDSD_CAPS`/`DDSD_WIDTH`, and `DDSD_PITCH` + `DDSD_LINEARSIZE` conflict. |
| 11 | Width/height 0 and above the 1,000,000 cap. |
| 12 | Depth/mipmap flag mismatches, volume-without-depth, and valid volume/mipmap round-trips. |
| 13 | FOURCC without code, FOURCC + RGB, neither flag, RGB with a code, 8-bit and 0-bit RGB. |
| 14 | Zero, overlapping and out-of-range RGB masks; valid 16-bit 565 masks. |
| 15 | DX10 truncation at 128 and 147 bytes, dimension 0/5, array size 0, empty payload. |
| 16 | Builder range errors (width, height, fourCC, size, forwarded bit count) and DX10 semantic errors. |
| 17 | `dds_build` rejects a DX10 flag mismatch, a payload size mismatch and forwards DX10 field errors. |
| 18 | Header-only buffers parse at both offsets with empty payloads and empty copies. |

## Known limitations

- The payload is a single opaque span; cube-map faces, mip levels and DX10
  array slices are not separated, and no length cross-check against
  dimensions, pitch or format exists.
- `reserved1` is strict (must be zero) and not retained; `reserved2` is
  retained and re-emitted but never validated.
- Dimensions are capped at 1,000,000; `depth` and `mipMapCount` are checked
  against their flags but not otherwise bounded.
- `dxgiFormat` has no known-format table; only `resourceDimension` and
  `arraySize` are validated.
- Palettized (8-bit) RGB, `DDPF_LUMINANCE`, `DDPF_ALPHA` and non-fourCC YUV
  files are rejected; the corresponding fourCC codes pass through untouched.
- The whole buffer is in memory; there is no streaming API.
