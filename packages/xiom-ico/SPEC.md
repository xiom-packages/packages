# xiom.ico SPEC

## Scope

Pure-XIOM structural codec for the Windows ICO/CUR container format, covering
the 6-byte `ICONDIR` header, the 16-byte `ICONDIRENTRY` directory records,
the opaque image resources they point at, and a builder that emits canonical
ICONDIR bytes. The codec validates structure, computes the directory size,
decodes every entry field, and hands back exact payload byte slices. No image
payload is ever decoded.

## Non-goals

PNG, BMP/DIB and legacy bitmap/cursor-bitmap payload decoding; rendering,
scaling, resampling or conversion; palette, alpha and DPI interpretation;
icon-theme (`index.theme`) and thumbnail-cache handling; multi-icon theme
bundling; streaming I/O; any use of FFI or external dependencies.

## ICONDIR layout (6 bytes)

| Offset | Size | Field | Rules |
|---|---|---|---|
| 0 | 2 | reserved | little-endian, must be 0 |
| 2 | 2 | type | little-endian, 1 = icon (ICO), 2 = cursor (CUR) |
| 4 | 2 | count | little-endian, 1..65535 image directory entries |

## ICONDIRENTRY layout (16 bytes each)

| Entry offset | Size | Field (ICO) | Field (CUR) | Rules |
|---|---|---|---|---|
| 0 | 1 | width | width | 0 = 256, else 1..255; decoded to 1..256 |
| 1 | 1 | height | height | 0 = 256, else 1..255; decoded to 1..256 |
| 2 | 1 | color count | color count | as stored, 0 = unspecified |
| 3 | 1 | reserved | reserved | must be 0 |
| 4 | 2 | planes | hotspot X | little-endian, 0..65535 |
| 6 | 2 | bit count | hotspot Y | little-endian, 0..65535 |
| 8 | 4 | bytes in resource | bytes in resource | little-endian, > 0, must not exceed the buffer |
| 12 | 4 | resource offset | resource offset | little-endian, at or past the directory, offset + size must fit |

## Region layout

| Region | Start | Length |
|---|---|---|
| ICONDIR | 0 | 6 |
| directory | 6 | `16 * count` |
| resources | per entry `offset` | per entry `bytes` |

The directory ends at `dir_bytes = 6 + 16 * count`. Every resource must start
at or after `dir_bytes` and must fit entirely in the buffer. Resources may
overlap each other and may appear in any order; trailing bytes after the last
resource are ignored. Payloads are pass-through: their contents never affect
validation.

## Derived values

- `width` / `height`: on-disk byte 0 decodes to 256; the builder encodes a
  requested 256 back to 0 and every other value 1..255 verbatim.
- For CUR containers `planes` and `bits` are the hotspot X and hotspot Y
  coordinates, not color planes or bit depth. The codec stores and returns
  them without interpreting the image.
- `dir_bytes = 6 + 16 * count` (`ico_dir_bytes`).

## API

```xiom
pub const ICO_TYPE_ICON: Int = 1;
pub const ICO_TYPE_CURSOR: Int = 2;
pub const ICO_DIR_HEADER_BYTES: Int = 6;
pub const ICO_DIR_ENTRY_BYTES: Int = 16;

pub type IcoInfo = {
  kind: Int;        // ICO_TYPE_ICON or ICO_TYPE_CURSOR
  count: Int;       // 1..65535
  dir_bytes: Int;   // 6 + 16 * count
}

pub type IcoEntry = {
  width: Int;        // 1..256
  height: Int;       // 1..256
  color_count: Int;  // 0..255 as stored
  planes: Int;       // ICO: planes; CUR: hotspot X
  bits: Int;         // ICO: bits per pixel; CUR: hotspot Y
  bytes: Int;        // resource length, > 0
  offset: Int;       // resource offset from the start of the file
}

pub type IcoBuilder = {
  kind: Int;
  widths: Vec[Int];
  heights: Vec[Int];
  color_counts: Vec[Int];
  planes: Vec[Int];
  bits: Vec[Int];
  sizes: Vec[Int];
  payload: Vec[UInt8];
}

pub fn ico_dir_bytes(count: Int) -> Int
pub fn ico_parse_header(data: &Vec[UInt8]) -> Result[IcoInfo, Str]
pub fn ico_parse(data: &Vec[UInt8]) -> Result[IcoInfo, Str]
pub fn ico_entry(data: &Vec[UInt8], i: Int) -> Result[IcoEntry, Str]
pub fn ico_image_data(data: &Vec[UInt8], i: Int) -> Result[Vec[UInt8], Str]
pub fn ico_is_ico(data: &Vec[UInt8]) -> Bool
pub fn ico_is_cur(data: &Vec[UInt8]) -> Bool
pub fn ico_builder_new(kind: Int) -> Result[IcoBuilder, Str]
pub fn ico_builder_count(b: &IcoBuilder) -> Int
pub fn ico_builder_kind(b: &IcoBuilder) -> Int
pub fn ico_builder_add(b: &mut IcoBuilder, image: &Vec[UInt8], width: Int, height: Int, color_count: Int, planes: Int, bit_count: Int) -> Result[Int, Str]
pub fn ico_builder_add_cursor(b: &mut IcoBuilder, image: &Vec[UInt8], width: Int, height: Int, color_count: Int, hotspot_x: Int, hotspot_y: Int) -> Result[Int, Str]
pub fn ico_builder_emit(b: &IcoBuilder) -> Result[Vec[UInt8], Str]
```

### Contract notes

- `ico_parse_header` validates the 6 header bytes and the directory size. It
  does not inspect entries or payloads.
- `ico_parse` runs `ico_parse_header` and then validates every entry in
  directory order; its `IcoInfo` is the same value the header call returns.
- `ico_entry` runs the full `ico_parse` validation (so a malformed buffer
  fails there first) and then decodes one entry; `i` must be `0 .. count-1`.
- `ico_image_data` copies `bytes` bytes from `offset`; the copy is exact and
  never interpreted.
- `ico_is_ico` / `ico_is_cur` classify valid headers only: a malformed header
  yields `false`, not an error.
- The builder keeps one flat `payload` vector plus parallel `Vec[Int]`
  fields; `ico_builder_add` and `ico_builder_add_cursor` validate every
  argument, append nothing on error, and return the new 1-based count.
- `ico_builder_emit` recomputes `count` from the appended images and every
  `offset` from scratch (`6 + 16 * count` for the first resource, then each
  next resource immediately after the previous one). Emitting twice yields
  identical bytes.
- The builder caps the image count at 65535 (the on-disk count is 16-bit),
  each payload at 4294967295 bytes (the on-disk size is 32-bit) and each
  dimension at 1..256.
- All functions are free functions; there are no methods and no global
  mutable state.

## Validation order

`ico_parse_header`: truncation (buffer < 6) -> reserved word -> resource
type -> zero count -> directory size. `ico_parse`: header, then per entry in
directory order: entry reserved byte -> size > 0 -> size <= buffer length ->
offset >= `dir_bytes` -> `offset + size <= buffer length`. `ico_entry` /
`ico_image_data`: full parse, then index range. `ico_builder_emit`: count > 0
-> parallel vector lengths -> kind -> non-empty recorded sizes -> payload
consistency -> per-entry field ranges. Tests assert exact messages so this
order stays observable.

## Error catalog

| Condition | Message |
|---|---|
| buffer shorter than 6 bytes | `ico: truncated header` |
| header reserved word != 0 | `ico: invalid reserved field` |
| header type not 1 or 2 | `ico: unknown resource type` |
| header count == 0 | `ico: zero image count` |
| `6 + 16 * count > data.len()` (including huge counts) | `ico: directory out of bounds` |
| entry reserved byte != 0 | `ico: invalid entry reserved field` |
| entry resource size == 0 | `ico: empty image resource` |
| entry resource size > whole buffer | `ico: entry size out of bounds` |
| entry offset < `dir_bytes` | `ico: image data overlaps directory` |
| `offset + size > data.len()` | `ico: image data out of bounds` |
| entry/payload index negative or >= count | `ico: entry index out of range` |
| builder kind not 1 or 2 (`ico_builder_new`) | `ico: unknown resource type` |
| `ico_builder_add` on a cursor builder | `ico: not an icon builder` |
| `ico_builder_add_cursor` on an icon builder | `ico: not a cursor builder` |
| builder width < 1 or > 256 | `ico: invalid width` |
| builder height < 1 or > 256 | `ico: invalid height` |
| builder color count < 0 or > 255 | `ico: invalid color count` |
| builder planes/hotspot X < 0 or > 65535 | `ico: invalid planes or hotspot x` |
| builder bit count/hotspot Y < 0 or > 65535 | `ico: invalid bit count or hotspot y` |
| builder payload empty | `ico: empty image resource` |
| builder payload larger than 2^32-1 | `ico: image resource too large` |
| builder already holds 65535 images | `ico: too many images` |
| `ico_builder_emit` on an empty builder | `ico: zero image count` |
| `ico_builder_emit` with mismatched parallel vectors or payload length | `ico: builder is inconsistent` |
| `ico_builder_emit` with a corrupted kind | `ico: unknown resource type` |
| `ico_builder_emit` with corrupted entry fields | the append catalog above |

`ico_entry` and `ico_image_data` forward every parser message unchanged, and
`ico_builder_emit` forwards the append catalog for corrupted entries; tests
assert the exact text.

## Wire examples

A minimal one-image ICO built by the library (23 bytes) is:

| Bytes | Meaning |
|---|---|
| `00 00 01 00 01 00` | ICONDIR: reserved 0, type 1, count 1 |
| `00 00 00 00 00 00 01 00 01 00 00 00 16 00 00 00` | 256x256 (both sentinels), color count 0, reserved 0, planes 0, bits 0, size 1, offset 22 |
| `xx` | the single opaque payload byte |

## Test matrix

| # | Check |
|---|---|
| 1 | `ico_dir_bytes` table (0/1/2/65535) plus hand-built 2-image header byte decode and `ico_parse_header` fields. |
| 2 | Entry decode of a 2-image ICO: every field, including the 0-as-256 width/height sentinel. |
| 3 | Payload slices byte-match the declared spans of both entries. |
| 4 | CUR fixture: type 2, hotspot X/Y in the planes/bit-count words, payload slice, `ico_is_cur` / `ico_is_ico`. |
| 5 | `ico_builder_new`: kinds 0, 3, 255 and -1 rejected; kinds 1 and 2 accepted and reported. |
| 6 | Builder emit for two images: 48-byte layout, header/entry byte positions, offsets 38 and 42, payload round-trip, parse-back. |
| 7 | 256x256 writes both dimension sentinels and round-trips; 1x1 is verbatim. |
| 8 | Builder boundaries: width/height 0 and 257, color count -1 and 256, planes/bit count -1 and 65536, empty payload; maxima accepted; no partial append. |
| 9 | Cursor builder: `ico_builder_add_cursor` stores hotspots, `ico_builder_add` on CUR and `add_cursor` on ICO are rejected, emit round-trips as CUR. |
| 10 | The 65535-image count cap: the first 65535 adds are Ok, the 65536th is `ico: too many images`. |
| 11 | Header errors: empty/5-byte truncation, non-zero reserved, types 0/3/255, zero count, huge count 0xFFFF, a directory that exceeds a 21-byte buffer. |
| 12 | Entry errors: non-zero entry reserved, zero size, size above the buffer, offset inside the directory, offset + size overrun; untouched fixture is Ok. |
| 13 | Index bounds for entry and payload accessors (-1, == count, far above count) and parser-error forwarding. |
| 14 | `ico_is_ico` / `ico_is_cur` for ICO, CUR, short and zero-count buffers. |
| 15 | Three-image build (16/256/48 widths, sizes 3/5/7): deterministic emit, offsets 54/57/62, field-for-field and payload-for-payload parse-back. |
| 16 | `ico_builder_emit` guards: empty builder, payload/size mismatch, parallel length mismatch, zero recorded size, tampered width/color count/kind. |

## Known limitations

- Payload bytes are opaque: PNG chunk structure, BMP headers, palettes and
  alpha data are never inspected, so an ICO whose payloads are corrupt is
  still structurally accepted.
- Resources may overlap each other and may appear in any order; only
  resources overlapping the directory are rejected. Trailing bytes after the
  last resource are allowed.
- Cursor hotspot coordinates are stored and returned as-is; the format does
  not require them to lie inside the image, and this codec does not enforce
  it.
- The whole buffer is in memory; there is no streaming API.
- The builder accepts at most 65535 images and 4 GiB-1 bytes per payload,
  matching the fixed on-disk field widths.
