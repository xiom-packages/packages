# xiom.pam SPEC

## Scope

Pure-XIOM parsing and building of single-image Netpbm PAM (P7) files, with
opaque samples and opaque tuple types:

- header: `P7`, `WIDTH`, `HEIGHT`, `DEPTH`, `MAXVAL`, zero or more `TUPLTYPE`
  lines, `ENDHDR`, with `#` comment lines and blank lines allowed;
- raster: `width * height * depth` samples, row-major, no padding, one byte
  per sample for `maxval <= 255` and two bytes big-endian for
  `maxval 256..65535`;
- `PamImage` records the header fields plus the raster span
  (`data_offset`, `raster_len`) into the caller's flat `Vec[UInt8]` buffer.

The module never allocates an image type, never interprets sample values, and
never touches the file system.

## Non-goals

Pixel, channel or tuple-type semantics; PBM/PGM/PPM (P1-P6); multi-image
streams; sample scaling, dithering, gamma, color management; compression;
streaming; file IO; rendering.

## API contract

```xiom
pub type PamImage = {
  width: Int;            // 1..1000000
  height: Int;           // 1..1000000
  depth: Int;            // 1..1000000
  maxval: Int;           // 1..65535
  bytes_per_sample: Int; // 1 for maxval <= 255, 2 for maxval 256..65535
  data_offset: Int;      // first raster byte in the source buffer
  raster_len: Int;       // width * height * depth * bytes_per_sample
  tupltypes: Vec[Str];   // TUPLTYPE values, in header order (may be empty)
}

pub fn pam_bytes_per_sample(maxval: Int) -> Int
pub fn pam_width(img: &PamImage) -> Int
pub fn pam_height(img: &PamImage) -> Int
pub fn pam_depth(img: &PamImage) -> Int
pub fn pam_maxval(img: &PamImage) -> Int
pub fn pam_raster_offset(img: &PamImage) -> Int
pub fn pam_raster_len(img: &PamImage) -> Int
pub fn pam_tupltype_count(img: &PamImage) -> Int
pub fn pam_tupltype(img: &PamImage, index: Int) -> Str
pub fn pam_tuple_type(img: &PamImage) -> Str
pub fn pam_parse_header(data: &Vec[UInt8]) -> Result[PamImage, Str]
pub fn pam_raster_copy(data: &Vec[UInt8], img: &PamImage) -> Result[Vec[UInt8], Str]
pub fn pam_build(width: Int, height: Int, depth: Int, maxval: Int, tupltypes: &Vec[Str], raster: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
```

- `pam_parse_header` validates the whole buffer, not just the header fields:
  the bytes after `ENDHDR` must be exactly `raster_len` long. `data_offset` is
  the index immediately after the LF (or CRLF) that terminates `ENDHDR`.
- `pam_tupltype` returns `""` when `index < 0` or
  `index >= pam_tupltype_count`; parsed and built values are never empty, so
  the sentinel is unambiguous.
- `pam_tuple_type` joins the values with one SPACE (the PAM specification's
  concatenation rule) and returns `""` for a header without TUPLTYPE lines.
- `pam_bytes_per_sample` returns `1` for `1..255`, `2` for `256..65535` and
  `0` otherwise; parsed and built images always have `1` or `2`.
- `pam_raster_copy` checks `data_offset >= 0`, `raster_len >= 0` and
  `data_offset + raster_len <= data.len()` before copying.
- Free functions only; no methods, no FFI, no extra dependencies.

## Header grammar

```
image       := "P7" line_end header_line* "ENDHDR" line_end raster
header_line := blank | comment | width | height | depth | maxval | tupltype
blank       := hspace* line_end
comment     := hspace* "#" <any byte except LF>* line_end
width       := hspace* "WIDTH"  hspace+ value hspace* line_end
height      := hspace* "HEIGHT" hspace+ value hspace* line_end
depth       := hspace* "DEPTH"  hspace+ value hspace* line_end
maxval      := hspace* "MAXVAL" hspace+ value hspace* line_end
tupltype    := hspace* "TUPLTYPE" hspace+ tvalue hspace* line_end
value       := digit{1,9}                  ; decimal, no sign
tvalue      := <printable bytes>           ; rest of line, trimmed; no NUL/CTL/DEL
line_end    := LF | CRLF
hspace      := SPACE | TAB
raster      := width*height*depth samples, one sample per tuple member,
               in row-major order, no padding
sample      := 1 byte (maxval 1..255) | 2 bytes big-endian (maxval 256..65535)
```

- Field names are exactly upper case; `width` is an unknown key.
- Fields may appear in any order and interleaved with comments and blanks;
  each of `WIDTH`, `HEIGHT`, `DEPTH`, `MAXVAL` must appear exactly once.
- `TUPLTYPE` may appear zero or more times; each line contributes one value.
- The `P7` magic must be followed immediately by a line ending.
- After the `ENDHDR` line ending the raster starts immediately; the first
  raster byte may be any byte value.
- A bare CR is not a line ending: `CRLF` is the only two-byte terminator, and
  a CR anywhere else in a header line is an ordinary (rejected) control byte.

## Raster size rules

- `bytes_per_sample = 1` when `1 <= maxval <= 255`, `2` when
  `256 <= maxval <= 65535`.
- `raster_len = width * height * depth * bytes_per_sample`; there is no
  row padding and no alignment.
- 16-bit samples are big-endian: the first byte is the most significant.
- A sample's numeric value can exceed `maxval` at this layer; samples are
  opaque bytes and are never range-checked (see Non-goals).
- The buffer must end exactly at `data_offset + raster_len`: fewer bytes is
  `pam: truncated raster`, more is `pam: extra raster bytes`.

## Builder output

`pam_build` emits the deterministic canonical form:

```
P7
WIDTH <width>
HEIGHT <height>
DEPTH <depth>
MAXVAL <maxval>
TUPLTYPE <value>      (once per value, in argument order)
ENDHDR
<raster bytes verbatim>
```

Every line is LF-terminated; no comments are emitted. The raster argument is
copied byte-for-byte and must satisfy the exact-size rule above.

## Validation and errors

| Condition | Message |
|---|---|
| buffer shorter than `P7` + one line ending | `pam: truncated header` |
| bytes 0-1 not `P7` | `pam: bad magic` |
| `P7` not followed by LF/CRLF | `pam: missing newline after magic` |
| EOF before a complete `ENDHDR` line | `pam: missing ENDHDR` |
| first token of a line not `WIDTH`/`HEIGHT`/`DEPTH`/`MAXVAL`/`TUPLTYPE`/`ENDHDR` | `pam: unknown header key` |
| extra tokens after a numeric value, or after `ENDHDR` | `pam: malformed header line` |
| a required field appears twice | `pam: duplicate width`, `duplicate height`, `duplicate depth`, `duplicate maxval` |
| required field absent, value token absent, or value token not decimal | `pam: missing width`, `missing height`, `missing depth`, `missing maxval` |
| width/height/depth `<= 0`, `> 1000000`, or 10+ digits | `pam: invalid width`, `invalid height`, `invalid depth` |
| maxval `<= 0`, `> 65535`, or 10+ digits | `pam: invalid maxval` |
| TUPLTYPE value empty, or any byte `< 32` or `== 127` | `pam: invalid tuple type` |
| raster shorter than `raster_len` | `pam: truncated raster` |
| raster longer than `raster_len` | `pam: extra raster bytes` |
| builder width/height/depth out of range | `pam: invalid width`, `invalid height`, `invalid depth` |
| builder maxval out of range | `pam: invalid maxval` |
| builder `raster` length != `raster_len` | `pam: raster buffer size mismatch` |
| builder tuple type empty, control byte, or leading/trailing SPACE | `pam: invalid tuple type` |
| `pam_raster_copy` span invalid against `data` | `pam: raster out of range` |

Notes:

- A value token that starts with a non-digit (for example `-1` or `x`) is
  reported as *missing*; a decimal value outside the allowed range is
  *invalid*. At most 9 digits are accumulated, so hostile long numbers cannot
  overflow.
- Because `ENDHDR` terminates the header, a buffer that runs out first always
  reports `pam: missing ENDHDR`, even when required fields are also missing.
- `pam: extra raster bytes` is how concatenated (multi-image) PAM streams are
  rejected; single-image scope is deliberate.

## Test matrix

20 checks in `tests/test_conformance.xi`:

| # | Test | Covers |
|---|---|---|
| 1 | built 2x2x3 RGB PAM parses with an exact raster span | canonical build bytes, fields, `data_offset`/`raster_len`, span copy, TUPLTYPE |
| 2 | minimal header without TUPLTYPE parses and rebuilds exactly | tuple-free build (no TUPLTYPE line), empty join, `""` sentinels |
| 3 | comments, blank lines and CRLF line endings are handled | `#` lines, indented comments, blank lines, CRLF offsets |
| 4 | 16-bit samples are two bytes big-endian | `MAXVAL 65535`, 2-byte samples, byte order, `pam_bytes_per_sample` bounds |
| 5 | multiple TUPLTYPE lines are preserved in order | two lines, order, join with one space, rebuild |
| 6 | only P7 followed by LF or CRLF is accepted | P6/P8/high-byte magic, empty/1-byte/magic-only buffers, `P7X`, `P7\rX` |
| 7 | every required key is required and ENDHDR terminates the header | each missing key, EOF without ENDHDR, unterminated ENDHDR line |
| 8 | required keys may not repeat | duplicates of all four fields |
| 9 | non-positive and oversized dimensions and maxval are rejected | 0, `-1`, 1000001, 10-digit, maxval 0/65536/6-digit |
| 10 | malformed lines, unknown keys and bad tuple types are rejected | unknown/lowercase keys, trailing tokens, empty/space-only/tab/NUL tuples |
| 11 | rasters shorter than width*height*depth*bytes-per-sample are rejected | one byte short, header only, 1 byte of a 16-bit sample |
| 12 | rasters longer than the computed size are rejected | one extra byte, trailing LF, concatenated second image |
| 13 | 16-bit 2x1x2 PAM round-trips byte-exactly | 8 raster bytes incl. 0x00/0x80/0xFF, rebuild from accessors |
| 14 | free key order, CRLF and comments canonicalize deterministically | odd field order, interior-space TUPLTYPE, canonical output pin |
| 15 | pam_build validates dimensions, maxval, raster size and tuple types | all builder error conditions plus exact-size success |
| 16 | pam_raster_offset/len and pam_raster_copy expose exactly the raster | odd key order, exact span, forged offset/length guards |
| 17 | the 255/256 bytes-per-sample boundary is exact | maxval 1/255/256, big-endian raster, truncated 16-bit |
| 18 | widened byte comparisons treat >= 128 values correctly | 0x00/0x7F/0x80/0xFE/0xFF raster bytes |
| 19 | pam_tupltype indexing and sentinels are exact | 3 values, index == count and negative indices |
| 20 | dimensions are capped at 1000000 | 1,000,000-wide parse and 1,000,001 rejection |

## Known limitations

- Single image per buffer; no multi-image stream support.
- Dimensions capped at 1,000,000 per axis, `maxval` capped at 65,535; the
  whole raster and header live in memory.
- Comment placement is line-based, matching the PAM specification: a `#`
  inside a TUPLTYPE value is data, and `ENDHDR # comment` is malformed.
- TUPLTYPE bytes are restricted to 32..126 and `>= 128` (no control bytes) so
  every parsed value reserializes exactly; interior spaces are preserved.
- Samples are never interpreted or rescaled; depth/tuple-type consistency is
  not validated.
- `pam_parse_header` fully validates the raster, but only for the single
  buffer passed in; there is no incremental or streaming parse.
