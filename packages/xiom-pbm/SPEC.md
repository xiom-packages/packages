# xiom.pbm SPEC

## Scope

Pure-XIOM parsing and building of the two bitmap Netpbm variants, one bit per
pixel with `0` = white and `1` = black:

- **P1** -- ASCII raster of `0`/`1` digits separated by arbitrary whitespace;
- **P4** -- binary raster, rows padded with zero bits to whole bytes, most
  significant bit first.

Rasters live in flat `Vec[UInt8]` buffers; the module never allocates an image
type and never touches the file system.

## Non-goals

PGM/PPM/PAM (P2/P3/P5/P6/P7), multi-image streams, 16-bit samples, scaling,
resampling, dithering, compression, palettes, color management, file IO,
streaming.

## API

```xiom
pub type PbmImage = {
  format: Int;      // 1 = ASCII (P1), 4 = binary (P4)
  width: Int;       // 1..1000000
  height: Int;      // 1..1000000
  data_offset: Int; // first raster byte (P4) or first raster digit (P1)
}

pub fn pbm_row_bytes(width: Int) -> Int
pub fn pbm_width(img: &PbmImage) -> Int
pub fn pbm_height(img: &PbmImage) -> Int
pub fn pbm_format(img: &PbmImage) -> Int
pub fn pbm_parse_header(data: &Vec[UInt8]) -> Result[PbmImage, Str]
pub fn pbm_bit(data: &Vec[UInt8], x: Int, y: Int) -> Int
pub fn pbm_build_p1(bits: &Vec[UInt8], width: Int, height: Int, bits_per_line: Int, comment: Str) -> Result[Vec[UInt8], Str]
pub fn pbm_build_p4(bits: &Vec[UInt8], width: Int, height: Int, comment: Str) -> Result[Vec[UInt8], Str]
```

## Header grammar

```
image     := magic ws+ width sep height tail_p4 | tail_p1
magic     := "P1" | "P4"
width     := digit{1,9}          ; value 1..1000000
height    := digit{1,9}          ; value 1..1000000
sep       := ( whitespace | comment )+
ws        := SPACE | TAB | LF | CR | VT | FF   ; bytes 32, 9, 10, 13, 11, 12
comment   := '#' <any byte except LF>* LF?     ; runs to the end of the line
tail_p4   := ws1 "raw raster: pbm_row_bytes(width) * height bytes"
tail_p1   := sep? "raster: width*height 0/1 digits separated by whitespace"
```

After the magic there must be at least one whitespace byte (a comment alone is
not accepted directly after the magic). Comments may appear in any separator
between header tokens, including between the height token and a P1 raster. For
P4 exactly one whitespace byte separates the height token from the raster;
`data_offset` is the index right after it. Once a P1 raster has started only
`0`/`1` digits and Netpbm whitespace are accepted -- `#` is data there.

## P4 padding rules

- Row stride is `pbm_row_bytes(width) = (width + 7) / 8` bytes.
- Bit `x` of row `y` lives in byte `data_offset + y * stride + x / 8` at bit
  position `7 - (x % 8)` within that byte (MSB first; `x = 0` is `0x80`).
- The unused low bits of the final byte of every row are padding.
  `pbm_build_p4` always writes them as `0`; `pbm_parse_header` and `pbm_bit`
  never read them, so input padding may hold any value.
- The raster is exactly `stride * height` bytes. Fewer bytes are
  `pbm: truncated raster`; any non-whitespace byte after the raster is
  `pbm: extra tokens`. Trailing whitespace is accepted.

## Semantics

- Coordinates are row-major with a top-left origin; `pbm_bit(data, x, y)`
  returns `0` (white) or `1` (black).
- `pbm_bit` returns the documented sentinel `-1` when `(x, y)` is outside the
  image **or** when `data` does not parse as a P1/P4 image; callers that need
  to distinguish the two call `pbm_parse_header` first.
- `pbm_parse_header` fully validates the raster, so `pbm_bit` on data that has
  already parsed cannot fail for in-range coordinates.
- `pbm_build_p4` writes `"P4\n"`, an optional comment line, `"<w> <h>\n"`,
  then the packed rows with zero padding and no trailing byte.
- `pbm_build_p1` writes `"P1\n"`, an optional comment line, `"<w> <h>\n"`,
  then one `0`/`1` digit per pixel, single spaces between digits, wrapped to
  `bits_per_line` digits per LF-terminated line (values `< 1` clamp to `1`)
  and always terminated by exactly one LF.
- Both builders take `bits` as `width * height` row-major `0`/`1` bytes;
  a length mismatch is `pbm: bit buffer size mismatch` and any value above `1`
  is `pbm: non-binary bit`.

## Comment emission

- An empty `comment` emits no comment line.
- A non-empty `comment` is emitted as one line, `"# " + comment + LF`,
  immediately after the magic line and before the dimensions.
- Every byte of `comment` must be printable ASCII (`32..126`) or `>= 128`;
  any byte `< 32` or `127` (LF, CR, NUL, TAB, DEL, ...) is rejected with
  `pbm: invalid comment` so the emitted header stays a single well-formed
  line. Non-ASCII UTF-8 bytes pass through unchanged.

## Validation and errors

| Condition | Message |
|---|---|
| buffer shorter than magic, or magic-only buffer | `pbm: truncated header` |
| bytes 0-1 not `P1`/`P4` | `pbm: bad magic` |
| byte 2 is not whitespace | `pbm: missing whitespace after magic` |
| width token missing / non-decimal | `pbm: missing width` |
| width <= 0, > 1,000,000, or 10+ digits | `pbm: invalid width` |
| height token missing / non-decimal | `pbm: missing height` |
| height <= 0, > 1,000,000, or 10+ digits | `pbm: invalid height` |
| P4: height followed by a non-whitespace byte, or EOF | `pbm: missing whitespace after height` / `pbm: truncated raster` |
| P4: raster shorter than `pbm_row_bytes(width) * height` | `pbm: truncated raster` |
| P4: non-whitespace byte after the raster | `pbm: extra tokens` |
| P1: no raster digits, or fewer than `width * height` | `pbm: truncated raster` |
| P1: a raster byte is neither `0`/`1` nor whitespace (includes `#`) | `pbm: non-binary digit` |
| P1: more than `width * height` digits | `pbm: extra tokens` |
| builder width/height <= 0 or > 1,000,000 | `pbm: invalid width`, `pbm: invalid height` |
| builder `bits` length != `width * height` | `pbm: bit buffer size mismatch` |
| builder bit value > 1 | `pbm: non-binary bit` |
| builder comment contains a byte < 32 or == 127 | `pbm: invalid comment` |

## Test plan

20 checks: built 2x2 P4 header/offset/row bytes and all four bits; built 2x2 P1
canonical literal and bits; comments before/between/after header tokens on
both formats with exact offsets; CR/LF/TAB/SPACE/VT/FF separators (P1 and P4);
bad magic (`P2`, `P5`, `X1`, high byte), missing whitespace after magic,
1-byte and magic-only truncation; missing width/height with comments
interspersed; zero, oversized (1,000,001) and 10-digit dimensions; non-binary
digits (`2`, `x`), extra P1 digits, extra P4 byte, accepted trailing
whitespace; truncated rasters for P1 and P4; P4 padding for 1/2/3/8/9-bit rows;
P1 arbitrary whitespace (adjacent digits, TAB/CR/LF, doubled spaces); 5x3 P4
independent row padding and all-pixel accessor; P1->P4->P1 semantic and
byte-exact round trip for canonical input; canonical P1/P4 byte pinning and
idempotence; `pbm_build_p1` wrapping for `bits_per_line` 0/2/4/100; builder
size mismatch, non-binary bits, non-positive dimensions and invalid comments;
comment emission literals and the empty-comment case; `pbm_bit` sentinel for
negative/overflowing coordinates, malformed and empty buffers; `pbm_row_bytes`
boundaries 0/-3/1/7/8/9/1000000; comments being header-only for P1; the exact
1,000,000-width cap accepted for P4 and 1,000,001 rejected.

## Known limitations

- Dimensions are capped at 1,000,000 per axis and the raster must fit in
  memory; there is no streaming.
- Concatenated (multi-image) PBM streams are not supported: trailing
  non-whitespace bytes after the first image are `pbm: extra tokens`.
- P4 padding bits are not validated on input; canonical builds always zero
  them.
- `pbm_bit` re-parses the header per call; P4 lookups are constant-time after
  that, P1 lookups scan up to the requested digit.
- No file IO, scaling, rotation, inversion, or P1<->P4 conversion helper:
  callers move bits through `pbm_bit` plus the builders.
