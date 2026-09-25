# xiom.ktx SPEC

## Scope

Pure-XIOM structural codec for KTX 1 texture containers (the Khronos "KTX 11"
format). It covers:

- the exact 12-byte file identifier;
- the 64-byte header (little- or big-endian), including the endianness
  marker, the GL type/format fields, dimensions and the layout counts;
- the key/value metadata region: `u32 keyAndValueByteSize` +
  NUL-terminated printable-ASCII key + opaque value bytes, each pair padded
  to a 4-byte boundary, indexed into flat parallel vectors with absolute
  value spans;
- the mipmap-level records of non-array (`numberOfArrayElements == 0`),
  non-cubemap (`numberOfFaces == 1`) textures: `u32 imageSize` + image data,
  4-byte aligned between levels;
- validation (identifier, endianness, zero width, `glTypeSize` 1..8, faces
  1/6, key/value structure, level sizes within the buffer);
- a builder that emits the canonical 64-byte little-endian header with
  `bytesOfKeyValueData` pinned to 0 (no key/value data is emitted).

Pixel data is never decoded, compression metadata is never interpreted, and
KTX 2 files are not supported.

## Non-goals

- No texture or pixel decoding of any kind; image bytes are located and
  copied only.
- No KTX 2 ("KTX 20") support: such files are detected and rejected with a
  dedicated message.
- No interpretation of `glInternalFormat` / compression schemes.
- No per-level span computation for array textures or cubemaps: their
  headers and key/value regions parse, but `ktx_parse` rejects them.
- No streaming I/O, no mipmap generation, no texture upload, no filesystem
  access.

## Identifier layout (12 bytes)

| Offset | Byte | Meaning |
|---|---|---|
| 0 | `0xAB` | non-ASCII lead byte |
| 1 | `0x4B` ('K') | |
| 2 | `0x54` ('T') | |
| 3 | `0x58` ('X') | |
| 4 | `0x20` (space) | |
| 5 | `0x31` ('1') | KTX 1 |
| 6 | `0x31` ('1') | KTX 1 |
| 7 | `0xBB` | matching angle byte |
| 8 | `0x0D` (CR) | |
| 9 | `0x0A` (LF) | |
| 10 | `0x1A` | control-Z |
| 11 | `0x0A` (LF) | |

KTX 2 files store `0x20 0x32 0x30` (' 20') at bytes 5..7 and are rejected
with `ktx: ktx2 not supported`. Any other mismatch is `ktx: bad identifier`.
Buffers shorter than 12 bytes are `ktx: truncated header`.

## Header layout (64 bytes total)

All multi-byte fields use the endianness selected by the marker.

| Offset | Size | Field | Rules |
|---|---|---|---|
| 0 | 12 | identifier | exact bytes above |
| 12 | 4 | endianness | `0x04030201` read little-endian = little-endian file; `0x01020304` read little-endian = big-endian file |
| 16 | 4 | glType | carried through; 0 marks a compressed texture |
| 20 | 4 | glTypeSize | accepted range 1..8 |
| 24 | 4 | glFormat | carried through |
| 28 | 4 | glInternalFormat | opaque compression metadata |
| 32 | 4 | glBaseInternalFormat | carried through |
| 36 | 4 | pixelWidth | must be >= 1 (zero is `ktx: invalid width`) |
| 40 | 4 | pixelHeight | carried through (0 for 1D textures) |
| 44 | 4 | pixelDepth | carried through (0 for 1D/2D textures) |
| 48 | 4 | numberOfArrayElements | 0 = non-array; nonzero is out of `ktx_parse` scope |
| 52 | 4 | numberOfFaces | 1 or 6, else `ktx: invalid face count` |
| 56 | 4 | numberOfMipmapLevels | 0 means "generate a full pyramid" and is read as 1 level |
| 60 | 4 | bytesOfKeyValueData | total key/value region size, including size fields and padding |

### Endianness

The marker is always read as a little-endian u32. The byte patterns are:

- bytes `01 02 03 04` -> value `0x04030201` -> every field is little-endian;
- bytes `04 03 02 01` -> value `0x01020304` -> every field is big-endian.

Any other value is `ktx: bad endianness`. `KtxHeader.endianness` stores the
observed marker value and `KtxHeader.big_endian` is the derived flag. The
builder always writes the little-endian form.

### Height/depth shape rules

The specification's shape rules (1D requires height and depth 0, 2D requires
depth 0) are not enforced: `pixelHeight` and `pixelDepth` are carried through
without validation. Only `pixelWidth == 0` is rejected.

## Key/value region

The region occupies `bytesOfKeyValueData` bytes starting at offset 64. The
total must be a multiple of 4 (every `imageSize` field must stay 4-byte
aligned); otherwise `ktx: unaligned key/value data`.

Each pair, in stream order:

| Field | Size | Rules |
|---|---|---|
| `keyAndValueByteSize` | 4 | must be >= 1 and fit inside the declared region |
| key | 1..n | NUL-terminated; non-empty; every byte printable ASCII `0x20..0x7E` |
| value | 0..n | opaque; any byte values, including NUL and >= 0x80 |
| `valuePadding` | 0..3 | zero bytes so the next pair starts 4-byte aligned; not counted by `keyAndValueByteSize` |

Derived values for pair `i`:

- `value_offsets[i]` = absolute offset of the first value byte
  (`pair_body + key_len + 1`).
- `value_bytes[i]` = `keyAndValueByteSize - key_len - 1`; 0 is valid.
- The next pair starts at the alignment of the pair body.

Validation:

1. region beyond the buffer -> `ktx: truncated key/value data`;
2. region size not a multiple of 4 -> `ktx: unaligned key/value data`;
3. pair size 0, empty key, or a key byte outside `0x20..0x7E` ->
   `ktx: invalid key`;
4. no NUL inside the declared pair -> `ktx: missing key terminator`;
5. the declared pair (or its padding) exceeding the region ->
   `ktx: bad key/value size`.

Keys beginning with `KTX` / `ktx` are reserved by the specification for
defined keys (for example `KTXorientation`); this codec applies the printable
range alone and does not reject them. Duplicate keys are not detected.

## Level layout (supported textures only)

`ktx_parse` computes level spans only when `numberOfArrayElements == 0` and
`numberOfFaces == 1`. Anything else is `ktx: unsupported level layout`; use
`ktx_parse_header` and `ktx_parse_key_values` for those files.

For each of the effective `max(numberOfMipmapLevels, 1)` levels, starting at
`data_offset = 64 + bytesOfKeyValueData`:

| Field | Size | Meaning |
|---|---|---|
| `imageSize` | 4 | byte count of this level's single image (no array/face multiplication) |
| image data | `imageSize` | opaque; located and copyable, never decoded |
| `mipPadding` | 0..3 | zero bytes so the next `imageSize` is 4-byte aligned; required only when another level follows |

Validation:

- missing `imageSize` field -> `ktx: truncated level data`;
- image data beyond the buffer -> `ktx: truncated level data`;
- an intermediate level that leaves no room for the next `imageSize` ->
  `ktx: truncated level data`;
- padding after the final level is optional; bytes after the final image are
  otherwise ignored.

`imageSize == 0` is structurally accepted (the codec assigns no format
semantics to image sizes). `KtxInfo.data_bytes` counts `data_offset` through
the end of the last level's image data; padding after the final level is not
counted.

## Validation order

`ktx_parse_header`:

1. buffer shorter than 12 bytes -> `ktx: truncated header`;
2. identifier is KTX 2 -> `ktx: ktx2 not supported`, any other mismatch ->
   `ktx: bad identifier`;
3. buffer shorter than 64 bytes -> `ktx: truncated header`;
4. endianness marker neither `0x04030201` nor `0x01020304` ->
   `ktx: bad endianness`;
5. `glTypeSize` outside 1..8 -> `ktx: invalid type size`;
6. `numberOfFaces` other than 1 or 6 -> `ktx: invalid face count`;
7. `pixelWidth == 0` -> `ktx: invalid width`.

`ktx_parse`: header (above), then the layout gate
(`ktx: unsupported level layout`), then the key/value region, then the level
records.

`ktx_build_header`: range checks every unsigned 32-bit field
(`ktx: field out of range`), then `glTypeSize` 1..8
(`ktx: invalid type size`), `numberOfFaces` 1/6
(`ktx: invalid face count`) and `pixelWidth >= 1` (`ktx: invalid width`),
assembles 64 bytes, and re-validates them through `ktx_parse_header`,
forwarding its messages unchanged.

## API

```xiom
pub type KtxHeader = {
  endianness: Int; big_endian: Bool; gl_type: Int; gl_type_size: Int;
  gl_format: Int; gl_internal_format: Int; gl_base_internal_format: Int;
  pixel_width: Int; pixel_height: Int; pixel_depth: Int;
  array_elements: Int; faces: Int; mipmap_levels: Int; kv_bytes: Int;
}

pub type KtxKeyValues = {
  count: Int; keys: Vec[Str]; value_offsets: Vec[Int]; value_bytes: Vec[Int];
}

pub type KtxInfo = {
  header: KtxHeader; kv: KtxKeyValues; kv_offset: Int; data_offset: Int;
  level_count: Int; size_offsets: Vec[Int]; image_sizes: Vec[Int];
  data_bytes: Int;
}

pub const KTX_ID_BYTES: Int = 12
pub const KTX_HEADER_BYTES: Int = 64
pub const KTX_ENDIAN_LE: Int = 0x04030201
pub const KTX_ENDIAN_BE: Int = 0x01020304
pub const KTX_TYPE_SIZE_MIN: Int = 1
pub const KTX_TYPE_SIZE_MAX: Int = 8

pub fn ktx_is_ktx(data: &Vec[UInt8]) -> Bool
pub fn ktx_parse_header(data: &Vec[UInt8]) -> Result[KtxHeader, Str]
pub fn ktx_build_header(h: &KtxHeader) -> Result[Vec[UInt8], Str]
pub fn ktx_parse_key_values(data: &Vec[UInt8]) -> Result[KtxKeyValues, Str]
pub fn ktx_parse(data: &Vec[UInt8]) -> Result[KtxInfo, Str]
pub fn ktx_level_count(h: &KtxHeader) -> Int
pub fn ktx_is_compressed(h: &KtxHeader) -> Bool
pub fn ktx_is_cubemap(h: &KtxHeader) -> Bool
pub fn ktx_is_array(h: &KtxHeader) -> Bool
pub fn ktx_data_offset(h: &KtxHeader) -> Int
pub fn ktx_width(h: &KtxHeader) -> Int
pub fn ktx_height(h: &KtxHeader) -> Int
pub fn ktx_depth(h: &KtxHeader) -> Int
pub fn ktx_gl_type(h: &KtxHeader) -> Int
pub fn ktx_gl_format(h: &KtxHeader) -> Int
pub fn ktx_gl_internal_format(h: &KtxHeader) -> Int
pub fn ktx_gl_base_internal_format(h: &KtxHeader) -> Int
pub fn ktx_kv_count(kv: &KtxKeyValues) -> Int
pub fn ktx_kv_key(kv: &KtxKeyValues, i: Int) -> Str
pub fn ktx_kv_value_offset(kv: &KtxKeyValues, i: Int) -> Int
pub fn ktx_kv_value_bytes(kv: &KtxKeyValues, i: Int) -> Int
pub fn ktx_kv_value(data: &Vec[UInt8], kv: &KtxKeyValues, i: Int) -> Result[Vec[UInt8], Str]
pub fn ktx_level_offset(info: &KtxInfo, i: Int) -> Int
pub fn ktx_level_size(info: &KtxInfo, i: Int) -> Int
pub fn ktx_payload_offset(info: &KtxInfo, i: Int) -> Int
pub fn ktx_level_data(data: &Vec[UInt8], info: &KtxInfo, i: Int) -> Result[Vec[UInt8], Str]
```

### Contract notes

- `ktx_is_ktx` checks the 12 identifier bytes only; KTX 2 returns false.
- `ktx_parse_header` needs only the 64 header bytes; it does not require a
  key/value region or level records to be present.
- `ktx_build_header` always emits exactly 64 bytes: identifier, canonical
  little-endian marker, fields little-endian, `bytesOfKeyValueData` 0. The
  `endianness`, `big_endian` and `kv_bytes` fields of `h` are ignored (a
  big-endian header is never built).
- `ktx_parse_key_values` works for every header shape; only pair structure is
  validated.
- `ktx_parse` requires the supported flat layout and the full level chain.
- `ktx_kv_key` returns "" out of range; `ktx_kv_value_offset`,
  `ktx_kv_value_bytes`, `ktx_level_offset`, `ktx_level_size` and
  `ktx_payload_offset` return -1 out of range.
- `ktx_kv_value` and `ktx_level_data` copy spans out of the caller's buffer;
  indexing errors and buffer truncation have distinct messages.
- All functions are free functions; no pixel data is interpreted and no
  global state is used.

## Error catalog

| Condition | Message |
|---|---|
| buffer shorter than 12 bytes, or identifier-less buffer shorter than 64 bytes | `ktx: truncated header` |
| bytes 5..7 are "20" (KTX 2 identifier) | `ktx: ktx2 not supported` |
| any other identifier mismatch | `ktx: bad identifier` |
| endianness marker neither `0x04030201` nor `0x01020304` | `ktx: bad endianness` |
| `glTypeSize` outside 1..8 | `ktx: invalid type size` |
| `numberOfFaces` not 1 and not 6 | `ktx: invalid face count` |
| `pixelWidth == 0` | `ktx: invalid width` |
| key/value region beyond the buffer (parse or accessor) | `ktx: truncated key/value data` |
| `bytesOfKeyValueData` not a multiple of 4 | `ktx: unaligned key/value data` |
| pair size 0, empty key, or non-printable key byte | `ktx: invalid key` |
| pair size or its padding exceeds the declared region | `ktx: bad key/value size` |
| no NUL terminator inside a pair | `ktx: missing key terminator` |
| `ktx_parse` on an array or cubemap header | `ktx: unsupported level layout` |
| missing imageSize, image data beyond the buffer, or an intermediate level without room for the next imageSize | `ktx: truncated level data` |
| builder field outside 0..`2^32-1` | `ktx: field out of range` |
| builder `glTypeSize` outside 1..8 | `ktx: invalid type size` |
| builder `numberOfFaces` not 1/6 | `ktx: invalid face count` |
| builder `pixelWidth == 0` | `ktx: invalid width` |
| `ktx_kv_value` index outside `0..count-1` | `ktx: key/value index out of range` |
| `ktx_level_data` index outside `0..level_count-1` | `ktx: level index out of range` |

## Test matrix

| # | Check |
|---|---|
| 1 | Hand-built LE header decodes every field and every accessor. |
| 2 | Big-endian header decodes every field; `big_endian` true; compressed glType 0. |
| 3 | Identifier is exact: each of the 12 bytes corrupted in turn is rejected; empty/11-byte/identifier-only buffers are truncated; KTX 2 gets its own message. |
| 4 | Markers `0x04030201` (LE) and `0x01020304` (BE) are accepted; unknown marker rejected. |
| 5 | `glTypeSize` 1..8 accepted; 0, 9, 255, `2^32-1` rejected. |
| 6 | Faces 1/6 accepted (cubemap flag); 0/2/5/7/255 rejected. |
| 7 | Zero width rejected; 1x0 1D and 1x1x1 3D accepted; max u32 width kept. |
| 8 | The specification api/gles2 key/value example round-trips with exact spans. |
| 9 | Multiple pairs (different padding lengths, empty value) index with flat spans; levels start after the region. |
| 10 | Printable-key rule: missing NUL, empty key, control/DEL/high bytes rejected; space key accepted; opaque value bytes copied verbatim. |
| 11 | Region bounds/alignment: region beyond buffer, non-multiple-of-4, oversized pair and zero-size pair each get their message; a padded pair fits. |
| 12 | Level records locate imageSize/payload offsets and copy image bytes across 4-byte padding. |
| 13 | `numberOfMipmapLevels == 0` reads as 1; a three-level chain parses. |
| 14 | Level truncation (missing imageSize, oversized image, cut second imageSize) is exact; unpadded final level accepted. |
| 15 | Cubemap and array headers parse; whole parse is rejected as out of scope; cubemap key/value data still parses. |
| 16 | Builder emits the exact 64 canonical bytes (identifier, LE marker, every field, zero kv bytes) and round-trips; a level appends cleanly. |
| 17 | Builder range checks cover type size, faces, width, negative and `2^32` overflow fields. |
| 18 | LE and BE files round-trip with key/value pairs and two levels each, field-for-field. |
| 19 | Accessors report out-of-range indices and short buffers with exact messages. |

## Known limitations

- No pixel decoding; image bytes are opaque.
- KTX 2 files are rejected, not converted.
- Array and cubemap files parse their header and key/value region only;
  `ktx_parse` does not compute their level spans.
- `glInternalFormat` values carry no semantics here; nothing knows whether a
  texture is compressed beyond the `glType == 0` marker.
- The shape rules for 1D/2D textures (height/depth zero) are not enforced.
- `imageSize` values are not checked against `pixelWidth`/`pixelHeight` or
  any block-size rule.
- Keys are restricted to printable ASCII even though the format allows
  arbitrary UTF-8; values are unrestricted.
- Duplicate keys and the reserved `KTX`/`ktx` prefixes are not policed.
- Bytes after the final level are ignored; no trailing-data validation is
  performed.
- The whole file is held in memory; there is no streaming API.
