# xiom.jpeg -- implemented byte format (SPEC)

> **Status:** implemented and conformance-tested on XIOM v0.61.3 (16/16 green).
> **Scope:** JPEG (ITU-T T.81 / ISO/IEC 10918-1) marker and segment layer:
> SOI/EOI framing, APP0..APP15 (JFIF decode, EXIF presence), DQT, SOF0/SOF1/SOF2,
> DHT counts, SOS scan headers, DRI, COM, and raw entropy spans with FF00
> stuffing and RST0..RST7 counting. No entropy decode, no inverse DCT, no
> pixels, no encoder.

This file documents the byte layout that `src/jpeg.xi` actually accepts and
rejects. It is written against the source, not against the format at large:
where the implementation is stricter or looser than T.81, that is called out.
All offsets are absolute byte offsets into the input buffer (`0` = first byte).
All integer fields are unsigned; multi-byte fields are big-endian unless stated
otherwise.

## 1. Overall grammar

```
image   := SOI marker* EOI
marker  := FF (FF)* code
segment := FF code BE16(length) payload[length-2]
```

- `SOI` is `FF D8` and must be the first two bytes of the buffer.
- Fill bytes are allowed inside the `FF (FF)* code` run; the marker code is the
  first non-FF byte.
- A segment's length field counts itself: `length >= 2`, and the payload is
  `length - 2` bytes.
- `EOI` (`FF D9`) is required after at least one frame and one scan. Bytes
  after EOI are allowed and are not parsed (see section 10).

Entropy-coded scan data is never decoded. The parser locates the raw scan span
and records it as an offset/length pair; stuffing bytes and restart markers
inside the span are consumed for framing purposes and counted, never
interpreted.

## 2. Marker offsets

Records and error messages that carry a marker offset use the offset of the
`FF` byte immediately before the marker code:

- regular `FF C0`: the offset of the `FF` (e.g. 2);
- fill run `FF FF C0` at 2: the offset of the *last* `FF` before `C0` (3).

Segment framing errors (`truncated segment`, `invalid segment length`,
`segment length out of bounds`) also report this marker offset. Payload errors
report the absolute offset of the offending field byte (`d + X`, where `d` is
the first payload byte, `d = marker offset + 4` with a single-FF marker).

## 3. Marker dispatch

After the marker code is read, the parser applies this exact table. "length
validated" means the segment framing checks of section 4 run first.

| Code(s) | Marker | Handling |
|---|---|---|
| `0x00` | `FF 00` outside a scan | error `jpeg: invalid marker` at the marker offset |
| `0x01` | TEM | error `jpeg: unsupported marker` at the marker offset (no length read) |
| `0x02..0xBF` | reserved / unknown | length validated, then `jpeg: unsupported marker` |
| `0xC0` | SOF0 baseline | parsed; precision must be exactly 8 |
| `0xC1` | SOF1 extended sequential | parsed; precision 8 or 12 |
| `0xC2` | SOF2 progressive | parsed; precision 8 or 12; sets the progressive flag |
| `0xC3`, `0xC5..0xC7`, `0xC9..0xCB`, `0xCD..0xCF` | lossless / differential / arithmetic frames | error `jpeg: unsupported frame type` at the marker offset (no length read) |
| `0xC4` | DHT | parsed |
| `0xC8` | JPG | length validated, then `jpeg: unsupported marker` |
| `0xCC` | DAC | length validated, then `jpeg: unsupported marker` |
| `0xD0..0xD7` | RST0..RST7 | error `jpeg: unexpected restart marker` at the marker offset (legal only inside scan data, section 8) |
| `0xD8` | SOI | legal only as bytes 0..1; a later occurrence errors `jpeg: unexpected SOI` |
| `0xD9` | EOI | ends parsing; requires a frame (`jpeg: missing SOF`) and a scan (`jpeg: missing SOS`) |
| `0xDA` | SOS | parsed, then scan-data walk (section 8) |
| `0xDB` | DQT | parsed |
| `0xDC` | DNL | length validated, then `jpeg: unsupported marker`; inside scan data it terminates the scan first |
| `0xDD` | DRI | parsed |
| `0xDE`, `0xDF` | DHP, EXP | length validated, then `jpeg: unsupported marker` |
| `0xE0..0xEF` | APP0..APP15 | indexed; APP0 with `JFIF\0` decodes JFIF, APP1 with `Exif\0\0` sets the EXIF flag |
| `0xF0..0xFD` | JPG0..JPG13 | length validated, then `jpeg: unsupported marker`; inside scan data skipped as two bytes (section 8) |
| `0xFE` | COM | indexed, payload opaque |
| `0xFF` | fill | consumed inside `FF (FF)* code` |

Notes:

- The SOF-family rejection list is exactly T.81's SOF codes minus `C0/C1/C2`
  (the parsed ones) and minus `C4/C8/CC` (DHT/JPG/DAC, which reach the generic
  path and are rejected as `jpeg: unsupported marker`).
- At a marker boundary, a byte that is not `FF` is `jpeg: invalid marker` at
  that byte. An `FF` run that reaches the end of the buffer is
  `jpeg: truncated marker` at the first `FF` of the run.

## 4. Segment framing and length semantics

After the code byte at offset `c` (with `after = c + 1`):

| Condition | Result |
|---|---|
| fewer than 2 bytes remain for the length field | `jpeg: truncated segment` at the marker offset |
| `BE16(at after) < 2` | `jpeg: invalid segment length` at the marker offset |
| declared end `after + length` past the buffer | `jpeg: segment length out of bounds` at the marker offset |
| otherwise | payload = `[after + 2, after + length)`, payload length `length - 2` |

`length = 2` is legal (empty payload) for any segment, including APP0 and COM.

APP-specific semantics:

- `jpeg_app_length(img, i)` returns the **declared length field** itself
  (`payload + 2`), not the payload length. It is always >= 2.
- `jpeg_app_data_offset(img, i)` is the absolute offset of the first payload
  byte (`marker offset + 4` with a single-FF marker and a 2-byte length).
- APP payloads stay opaque except APP0/JFIF header decode and APP1/EXIF
  identification; every APP0..APP15 segment is indexed in stream order.
- COM: `jpeg_comment_length` has the same declared-length semantics;
  the comment text is never read.

Worked example (canonical fixture, section 14, test t1): APP0 at 2,
`FF E0 00 10` at 2..5, so `jpeg_app_length = 16` and
`jpeg_app_data_offset = 6`.

### 4.1 APP0 JFIF decode

Triggered when the APP0 payload is at least 5 bytes and starts with
`4A 46 49 46 00` (`"JFIF\0"`). Payload offsets:

| Offset | Size | Field |
|---|---|---|
| +0..+4 | 5 | `"JFIF\0"` identifier |
| +5 | 1 | major version |
| +6 | 1 | minor version |
| +7 | 1 | units: 0 aspect ratio, 1 dots/inch, 2 dots/cm |
| +8..+9 | 2 | density x, BE16, must be > 0 |
| +10..+11 | 2 | density y, BE16, must be > 0 |
| +12 | 1 | thumbnail width `tw` |
| +13 | 1 | thumbnail height `th` |
| +14.. | 3*tw*th | thumbnail RGB bytes (length-checked only) |

Checks in source order: duplicate JFIF APP0 -> `jpeg: duplicate JFIF` at the
marker offset; payload < 14 -> `jpeg: invalid JFIF segment` at the marker
offset; units > 2 -> `jpeg: invalid JFIF units` at the units byte; density
x = 0 or y = 0 -> `jpeg: invalid JFIF density` at the density-x byte;
`14 + 3*tw*th != payload length` -> `jpeg: invalid JFIF segment` at the
marker offset. An APP0 payload that is not `"JFIF\0"` (e.g. `JFXX`) is indexed
but sets no JFIF field.

### 4.2 APP1 EXIF presence

An APP1 payload of at least 6 bytes starting with `45 78 69 66 00 00`
(`"Exif\0\0"`) sets `jpeg_has_exif` and records the marker offset in
`jpeg_exif_offset`. Nothing inside the TIFF body is parsed. There is no
duplicate check: if several EXIF APP1 segments appear, the flag stays set and
the offset reports the **last** one seen.

## 5. SOF0 / SOF1 / SOF2

Payload layout (`d` = first payload byte, `Nf` = component count):

| Payload offset | Size | Field |
|---|---|---|
| +0 | 1 | precision `P` |
| +1..+2 | 2 | height, BE16 |
| +3..+4 | 2 | width, BE16 |
| +5 | 1 | `Nf` |
| +6+3i | 1 | component id `Ci` |
| +7+3i | 1 | sampling `Hi<<4 | Vi` |
| +8+3i | 1 | quant table id `Tqi` |

Rules and messages:

| Rule | Message, offset |
|---|---|
| only one SOF per stream | `jpeg: duplicate SOF`, marker offset |
| payload >= 6 and exactly `6 + 3*Nf` | `jpeg: invalid SOF length`, marker offset |
| `Nf != 0` (no other bound; `Nf` may be up to 255 as long as the length matches) | `jpeg: invalid component count`, `d+5` |
| SOF0: `P == 8`; SOF1/SOF2: `P == 8` or `P == 12` | `jpeg: invalid precision`, `d` |
| width != 0 | `jpeg: zero frame dimension`, `d+3` |
| height != 0 | `jpeg: zero frame dimension`, `d+1` |
| `Hi` in 1..4 and `Vi` in 1..4 (nibbles of the sampling byte) | `jpeg: invalid sampling factor`, `d+7+3i` |
| `Tqi` <= 3 | `jpeg: invalid quant table id`, `d+8+3i` |
| component ids unique within the frame (any byte value allowed otherwise) | `jpeg: duplicate component id`, `d+6+3i` |

`jpeg_frame_marker` reports 192/193/194; `jpeg_is_progressive` is true only
for 194. Width and height are reported as stored (1..65535).

SOF-family codes outside `C0/C1/C2` are rejected before the length field is
read (section 3): lossless `C3`, differential `C5..C7`, arithmetic
`C9..CB`, differential-arithmetic `CD..CF` -> `jpeg: unsupported frame type`.
`C8` (JPG) and `CC` (DAC) are not in that early list; they are length-checked
and then rejected as `jpeg: unsupported marker`.

## 6. DQT quantization tables

A DQT payload is a sequence of tables, parsed until the payload is consumed:

| Offset | Size | Field |
|---|---|---|
| +0 | 1 | `Pq<<4 | Tq` |
| +1.. | 64 x 1 (Pq=0) or 64 x 2 (Pq=1) | quantization values |

Rules: `Pq` <= 1 (`jpeg: invalid DQT precision` at the info byte); `Tq` <= 3
(`jpeg: invalid DQT table id` at the info byte); each 8-bit value is one byte
(1..255), each 16-bit value is BE16 (1..65535), and a value of 0 is
`jpeg: zero quant value` at that value's absolute offset. A table whose 64/128
value bytes do not fit the payload is `jpeg: truncated DQT table` at the info
byte. An empty payload is `jpeg: empty DQT` at the marker offset.

The index stores one entry per table in `quant_id` / `quant_precision` /
`quant_value_offset`; values are appended to the flat `quant_values` vector in
stream order (64 per table). `jpeg_quant_value(img, t, k)` returns value `k`
as stored -- T.81 stores DQT values in zig-zag order and this parser does not
reorder them -- and is -1 outside the table's 64-value window. Table ids are
not checked for uniqueness across segments.

## 7. DHT Huffman table counts

A DHT payload is a sequence of tables, parsed until the payload is consumed:

| Offset | Size | Field |
|---|---|---|
| +0 | 1 | `Tc<<4 | Th` |
| +1..+16 | 16 | code counts `Li` |
| +17.. | sum(Li) | symbol bytes (opaque) |

Rules: `Tc` <= 1 (`jpeg: invalid DHT class`), `Th` <= 3
(`jpeg: invalid DHT table id`), sum of the 16 counts <= 256
(`jpeg: DHT symbol count overflow`), all at the info byte offset; fewer than
17 bytes for a table header or a symbol list that does not fit is
`jpeg: truncated DHT` at the info byte. An empty payload is
`jpeg: empty DHT` at the marker offset.

The index stores class (0 DC, 1 AC), id (0..3), the symbol count and the flat
offset into `dht_counts` (16 counts per table). **Symbol bytes are never
stored or exposed**: they are only counted and checked for presence. Huffman
code tables are never built.

## 8. SOS and the scan-data walk

### 8.1 SOS payload

| Payload offset | Size | Field |
|---|---|---|
| +0 | 1 | `Ns` |
| +1+2k | 1 | component id `Ck` |
| +2+2k | 1 | `Td<<4 | Ta` |
| +1+2Ns | 1 | spectral selection start `Ss` |
| +2+2Ns | 1 | spectral selection end `Se` |
| +3+2Ns | 1 | `Ah<<4 | Al` |

Rules and messages:

| Rule | Message, offset |
|---|---|
| SOF must precede SOS | `jpeg: SOS before SOF`, marker offset |
| payload >= 1 and exactly `1 + 2*Ns + 3` | `jpeg: invalid SOS length`, marker offset |
| `Ns` in 1..4 | `jpeg: invalid scan component count`, `d` |
| each selector names a frame component | `jpeg: unknown scan component`, selector byte (`d+1+2k`) |
| no selector repeats within the scan | `jpeg: duplicate scan component`, selector byte |
| `Td` <= 3 | `jpeg: invalid DC table selector`, `d+2+2k` |
| `Ta` <= 3 | `jpeg: invalid AC table selector`, `d+2+2k` |
| `Ss` <= 63, `Se` <= 63, `Ss` <= `Se` | `jpeg: invalid spectral selection`, `Ss` byte |
| `Ah` <= 13, `Al` <= 13 | `jpeg: invalid successive approximation`, `Ah/Al` byte |
| baseline (SOF0/SOF1): `Ss == 0`, `Se == 63`, `Ah == Al == 0` | `jpeg: invalid spectral selection` at the `Ss`/`Se` byte; `jpeg: invalid successive approximation` at the `Ah/Al` byte |
| progressive (SOF2): `Ss == 0` requires `Se == 0`; and `Ah == 0` or `Ah == Al + 1` | `jpeg: invalid spectral selection` at the `Ss` byte; `jpeg: invalid successive approximation` at the `Ah/Al` byte |

Interleaved (`Ns > 1`) and non-interleaved scans are both accepted. Whether
every component is eventually covered, and whether progressive refinement
scans appear in a legal order, is an entropy-level rule and is not enforced.

### 8.2 Scan-data walk (FF handling)

The walk starts at the first byte after the declared SOS segment
(`send = after + seglen`), which is `jpeg_scan_data_offset`. At each step:

| Byte at position `di` | Action |
|---|---|
| not `FF` | advance 1 |
| `FF` and `di + 1 >= n` (last byte) | `jpeg: truncated marker` at `di` |
| `FF 00` | stuffed FF: advance 2 |
| `FF D0..D7` | restart marker: count it, advance 2 |
| `FF FF` | fill: advance 1 (the next `FF` is re-examined, so a run collapses toward the code) |
| `FF` + terminator code | stop; `di` is `jpeg_scan_marker_offset` |
| `FF` + any other code | advance 2 (consumed, not a terminator) |

The terminator set is exactly `C0..CF`, `D8..DF`, `E0..EF` and `FE` (all
SOF/DHT/JPG/DAC codes, SOI/EOI/SOS/DQT/DNL/DRI/DHP/EXP, APP0..15, COM).
Notably:

- `FF 00` inside a scan is stuffing, not a body byte;
- RST markers are consumed and counted, never interpreted;
- fill `FF` bytes inside scan data are consumed one at a time;
- unrecognized codes (`02..BF`, `F0..FD`) are skipped as two bytes rather than
  terminating the scan -- e.g. the sequence `FF FF 0B FF D9` consumes the
  first `FF` as fill, skips `FF 0B` as an unknown pair, and terminates at
  `FF D9` (pinned by test t16);
- `FF DC` (DNL) terminates the scan and is then rejected by the marker
  dispatcher as `jpeg: unsupported marker`.

If the buffer ends without a terminator, the result is `jpeg: missing EOI` at
the buffer length. A scan with zero entropy bytes is legal: the terminator may
start immediately at `jpeg_scan_data_offset`, in which case
`jpeg_scan_data_length` is 0 and `jpeg_scan_marker_offset` equals the data
offset.

The recorded span
`[jpeg_scan_data_offset, jpeg_scan_data_offset + jpeg_scan_data_length)` is
**raw**: it still contains stuffing bytes, restart markers and fill FFs, and it
ends exactly at the terminating marker's `FF`. `jpeg_scan_restart_count` is
the number of RST markers consumed inside the span.

## 9. DRI and restart semantics

- DRI payload must be exactly 2 bytes (segment length 4): a BE16 restart
  interval. Any other payload length is `jpeg: invalid DRI length` at the
  marker offset.
- Several DRI segments are allowed. The interval stored is the **last** one
  seen; `jpeg_dri_count` counts the segments; `jpeg_has_dri` is true when at
  least one was seen; `jpeg_restart_interval` is -1 when none was seen.
- Interval 0 is legal and does not clear the DRI state.
- The parser never checks that `jpeg_scan_restart_count` matches the interval,
  that RSTn markers cycle in order, or that RST markers appear at all; those
  are entropy-level rules.
- RST markers outside scan data (marker position) are rejected as
  `jpeg: unexpected restart marker` (section 3).

## 10. EOI and trailing bytes

- `jpeg_eoi_offset` is the `FF` byte before the `D9` code.
- Reaching EOI before any SOF is `jpeg: missing SOF` at the EOI marker offset;
  with a frame but no SOS it is `jpeg: missing SOS` at the EOI marker offset.
- End of buffer with no EOI after a frame is `jpeg: missing EOI` at the buffer
  length; with no frame at all it is `jpeg: missing SOF` at the buffer length.
- Bytes after EOI are not parsed and not validated; `jpeg_trailing_bytes` is
  `total_bytes - (eoi_offset + 2)` (so fill `FF` bytes consumed as part of the
  EOI marker run are not counted as trailing).

## 11. Validation order

1. buffer length >= 2 and bytes 0..1 = `FF D8` (else `jpeg: missing SOI`);
2. marker loop: read a marker run and dispatch by code (section 3);
3. segment framing for every segment that has a length field (section 4);
4. per-marker payload validation (SOF, DQT, DHT, DRI, SOS, APP/COM), in file
   order; the first error in file order is reported;
5. after SOS, the scan-data walk (section 8.2);
6. EOI and end-of-input checks (section 10).

The parser never skips a segment it cannot parse: an unknown marker is an
error, not a skip. Only bytes after EOI are ignored.

## 12. Error catalog

Every failure message has the form `<base> at <offset>`; the table lists the
base text, the condition, and the offset. Marker offsets are defined in
section 2; `d` is the first payload byte; `n` is the buffer length.

| Message base | Condition | Offset |
|---|---|---|
| `jpeg: missing SOI` | buffer < 2 bytes, or bytes 0..1 are not `FF D8` | 0 |
| `jpeg: invalid marker` | marker-position byte is not `FF`; or code `0x00` (`FF 00` outside a scan) | that byte / the FF before the 0x00 code |
| `jpeg: truncated marker` | `FF` run reaches EOF in marker position; or an `FF` in scan data is the last byte | first FF of the run / the FF in scan data |
| `jpeg: unexpected SOI` | second `FF D8` in marker position | marker offset |
| `jpeg: unexpected restart marker` | `FF D0..D7` in marker position | marker offset |
| `jpeg: unsupported frame type` | `FF C3, C5..C7, C9..CB, CD..CF` | marker offset |
| `jpeg: truncated segment` | fewer than 2 bytes after the code for the length field | marker offset |
| `jpeg: invalid segment length` | length field < 2 | marker offset |
| `jpeg: segment length out of bounds` | declared segment end past the buffer | marker offset |
| `jpeg: unsupported marker` | `FF 01` before any length read; or an unhandled code after length validation (`C8`, `CC`, `DC`, `DE`, `DF`, `F0..FD`, reserved `02..BF`) | marker offset |
| `jpeg: missing SOF` | EOI before any SOF; or EOF with no frame | EOI marker offset / `n` |
| `jpeg: missing SOS` | EOI with a frame but no SOS | EOI marker offset |
| `jpeg: missing EOI` | EOF at a marker boundary after a frame; or scan data reaches EOF unterminated | `n` |
| `jpeg: duplicate SOF` | a second SOF | marker offset |
| `jpeg: invalid SOF length` | payload < 6, or != `6 + 3*Nf` | marker offset |
| `jpeg: invalid component count` | `Nf == 0` | `d+5` |
| `jpeg: invalid precision` | SOF0 `P != 8`; SOF1/SOF2 `P` not 8/12 | `d` |
| `jpeg: zero frame dimension` | width = 0 | `d+3` |
| `jpeg: zero frame dimension` | height = 0 | `d+1` |
| `jpeg: invalid sampling factor` | H or V nibble outside 1..4 | `d+7+3i` |
| `jpeg: invalid quant table id` | `Tq > 3` | `d+8+3i` |
| `jpeg: duplicate component id` | `Ci` repeats an earlier frame component | `d+6+3i` |
| `jpeg: empty DQT` | DQT payload length 0 | marker offset |
| `jpeg: invalid DQT precision` | `Pq > 1` | `d+i` |
| `jpeg: invalid DQT table id` | `Tq > 3` | `d+i` |
| `jpeg: truncated DQT table` | fewer than 64/128 value bytes remain | `d+i` |
| `jpeg: zero quant value` | a quantization value is 0 | value byte |
| `jpeg: empty DHT` | DHT payload length 0 | marker offset |
| `jpeg: truncated DHT` | fewer than 17 bytes for a table header, or symbol list does not fit | `d+i` |
| `jpeg: invalid DHT class` | `Tc > 1` | `d+i` |
| `jpeg: invalid DHT table id` | `Th > 3` | `d+i` |
| `jpeg: DHT symbol count overflow` | sum of the 16 counts > 256 | `d+i` |
| `jpeg: invalid DRI length` | DRI payload != 2 | marker offset |
| `jpeg: SOS before SOF` | SOS with no preceding SOF | marker offset |
| `jpeg: invalid SOS length` | payload < 1, or != `1 + 2*Ns + 3` | marker offset |
| `jpeg: invalid scan component count` | `Ns == 0` or `Ns > 4` | `d` |
| `jpeg: unknown scan component` | selector not in the frame component list | `d+1+2k` |
| `jpeg: duplicate scan component` | selector repeated within the scan | `d+1+2k` |
| `jpeg: invalid DC table selector` | `Td > 3` | `d+2+2k` |
| `jpeg: invalid AC table selector` | `Ta > 3` | `d+2+2k` |
| `jpeg: invalid spectral selection` | `Ss`/`Se` > 63, `Ss > Se`; baseline `Ss != 0` or `Se != 63`; progressive `Ss == 0` with `Se != 0` | `Ss`/`Se` byte |
| `jpeg: invalid successive approximation` | `Ah`/`Al` > 13; baseline `Ah`/`Al` != 0; progressive `Ah != 0` and `Ah != Al+1` | `Ah/Al` byte |
| `jpeg: duplicate JFIF` | second APP0 carrying `JFIF\0` | marker offset |
| `jpeg: invalid JFIF segment` | JFIF payload < 14, or != `14 + 3*tw*th` | marker offset |
| `jpeg: invalid JFIF units` | units byte > 2 | `d+7` |
| `jpeg: invalid JFIF density` | density x = 0 or density y = 0 | `d+8` |

45 distinct message bases. For `Err` values returned by `jpeg_parse` the offset
is always >= 0; the internal success sentinel (offset -1) never escapes.

## 13. Result conventions

- `jpeg_parse` returns `Result[JpegImage, JpegError]`; a failed parse carries
  `jpeg_error_message` and `jpeg_error_offset`.
- Index accessors return `-1` when an index is out of range, `Bool` accessors
  return `false`; there is no panic path in the accessor layer.
- Flat stores are window-checked: `jpeg_quant_value` requires
  `base + 64 <= quant_values.len()`, `jpeg_dht_count` requires
  `base + 16 <= dht_counts.len()`, and the scan-selector accessors require
  `k < jpeg_scan_component_count(s)` and the selector window to fit.
- `JpegImage` is normally obtained from a successful `jpeg_parse` (the
  conformance tests also build an empty literal directly to exercise accessor
  sentinels). It stores everything in parallel `Vec[Int]` fields (51 fields,
  no `Vec[Str]` anywhere).
- Sentinel values on a successfully parsed image: `restart_interval = -1` when
  no DRI was seen, `exif_offset = -1` when no EXIF APP1 was seen,
  `has_jfif = 0`, `progressive = 0/1`, `dri_count = 0`.

## 14. Canonical fixture (test t1)

`tests/test_conformance.xi` pins this 146-byte baseline stream byte by byte:

| Offset | Bytes | Content |
|---|---|---|
| 0 | `FF D8` | SOI |
| 2 | `FF E0 00 10` | APP0, declared length 16 |
| 6 | `4A 46 49 46 00 01 02 01 01 2C 01 2C 00 00` | `"JFIF\0"`, v1.2, units 1, 300x300, no thumbnail |
| 20 | `FF DB 00 43` | DQT, declared length 67 |
| 24 | `00` + 64 values | table 0, 8-bit, `value[i] = ((5+i) mod 255) + 1` |
| 89 | `FF C0 00 0B` | SOF0, declared length 11 |
| 93 | `08 00 03 00 02 01 01 11 00` | P=8, height=3, width=2, Nf=1, C1=1, H/V=1x1, Tq=0 |
| 102 | `FF C4 00 14` | DHT, declared length 20 |
| 106 | `00 01 00... 00` + symbol `00` | DC table 0, count[0]=1, one symbol |
| 124 | `FF DD 00 04` | DRI, declared length 4 |
| 128 | `00 02` | restart interval 2 |
| 130 | `FF DA 00 08` | SOS, declared length 8 |
| 134 | `01 01 00 00 3F 00` | Ns=1, C1/TdTa=0, Ss=0, Se=63, Ah/Al=0 |
| 140 | `AA FF 00 BB` | raw scan span (4 bytes, `FF 00` is stuffing) |
| 144 | `FF D9` | EOI (total bytes 146) |

Pinned derived values include: `scan_data_offset = 140`, `scan_data_length = 4`,
`scan_restart_count = 0`, `scan_marker_offset = 144`, `app_length = 16`,
`app_data_offset = 6`, `quant_value(0, 0) = 6`, `quant_value(0, 63) = 69`,
`eoi_offset = 144`, `total_bytes = 146`, `trailing_bytes = 0`.

## 15. Test matrix (tests/test_conformance.xi)

All fixtures are built in-test as synthetic byte buffers; no external files.
Each test ends with one `assert(true, ...)` whose names are listed below.

| Test | Pinned name | Covers |
|---|---|---|
| t1 | canonical baseline image decodes every field exactly | the 146-byte fixture of section 14, every accessor and offset |
| t2 | SOI validation and classification sentinels hold | empty/1-byte/PNG buffers -> `missing SOI at 0`; `FFD8`-only -> `missing SOF at 2`; `jpeg_is_jpeg` sentinels |
| t3 | APP index, JFIF decode and EXIF presence are exact | APP1 Exif + APP0 JFIF + APP2 + APP13 index order, offsets and declared lengths; JFIF v1.1 with a 1x1 thumbnail; units 3, density 0, missing thumbnail bytes, duplicate JFIF rejects; `JFXX` APP0 indexed but not decoded |
| t4 | DQT table index, values and malformed payloads are exact | two 8-bit tables in one segment (ids 0/2, value offsets 0/64), one 16-bit table id 3 (301..364), empty/precision/id/truncation/zero-value rejects |
| t5 | SOF0/SOF1/SOF2 decode and every SOF rule rejects correctly | 7x5 SOF0, 12-bit SOF1, SOF2 sampling 2x2; length mismatch, Nf 0, precision 12 (SOF0) / 10 (SOF1), zero width/height, sampling 0/5, Tq 4, duplicate component id, SOF3, duplicate SOF |
| t6 | SOS selection, approximation and ordering rules are exact | SOS before SOF, Ns/length mismatch, Ns 0 and 5, unknown and duplicate selectors, Td/Ta 4; baseline Ss/Se/Ah and progressive DC-scan, Ah 14, Ah != Al+1 rejects at exact offsets; valid refinement Ss=1/Se=63/Ah=1/Al=0 accepted |
| t7 | stuffing, restart markers and a between-scan DHT decode exactly | two-scan 76-byte fixture: scan 0 DC with `FF 00` and three RSTs, DHT between scans, scan 1 with one RST; span offsets/lengths, EOI at 74 |
| t8 | marker grammar, segment bounds and fill bytes behave exactly | `FF 00` outside scan, second SOI, RST at top level, SOF3 before length, DAC/TEM unsupported, non-FF byte, lone FF and FF run at EOF, missing/invalid/out-of-bounds length, empty APP0 legal, fill FF before SOF shifts offsets |
| t9 | EOI presence, trailing bytes and missing-SOF/SOS precedence hold | two trailing bytes counted, EOF after SOF -> `missing EOI at 15`, SOF+EOI -> `missing SOS at 15`, SOI+EOI -> `missing SOF at 2`, APP0+EOI -> `missing SOF at 6` |
| t10 | COM segments are indexed without being interpreted | two COM segments (5-byte and empty payload): offsets 2/11, lengths 7/2, sentinels; comments are not APP segments |
| t11 | DRI interval, replacement and length rules are exact | interval 4; two DRIs (2 then 8) last-wins with count 2; payload != 2 rejected; interval 0 legal |
| t12 | DHT counts, symbol sums and malformed payloads are exact | two tables in one segment (DC id 0, 3 symbols; AC id 3, 1 symbol), count offsets 0/16, per-count reads and sentinels; overflow 257, truncated symbol list, class 2, id 4, empty DHT, partial second table |
| t13 | constants, accessor sentinels and error accessors hold | all 10 constants; every accessor sentinel on an empty image; error message non-empty and offset 2 |
| t14 | a 4:2:0 frame and its scan selectors decode exactly | Y 2x2 Tq0 + Cb/Cr 1x1 Tq1, three selectors with mixed Td/Ta; selector 3 returns -1; unknown fourth selector rejected at offset 30 |
| t15 | scan spans, zero-length scans and in-scan EOF are exact | zero-length scan (data offset 25, length 0, marker offset 25); EOF in scan data -> `missing EOI at 27`; lone FF -> `truncated marker at 26`; FF run at EOF -> `truncated marker at 26` |
| t16 | stuffing, fill bytes and all RST0..RST7 markers are consumed exactly | eight RST markers, `FF 00` stuffing and the `FF FF 0B` fill/unknown-pair sequence; span length 31, restart count 8, terminator at 56, total 58 |

## 16. Non-goals and documented permissiveness

- No entropy decode: DHT symbol bytes are not stored, no Huffman codes are
  built, no coefficients or pixels are produced; no encoder exists.
- Only SOF0/SOF1/SOF2 are accepted; the remaining SOF-family codes
  (C3, C5..C7, C9..CB, CD..CF) and JPG/DAC/DNL/DHP/EXP are rejected
  (DNL terminates a scan before being rejected as a marker).
- JFIF thumbnail bytes are length-checked only; EXIF bodies are opaque;
  APPn/COM payloads other than the JFIF/EXIF identifiers are opaque.
- Restart interval vs. scan content is not validated; RST ordering is not
  validated; cross-scan component coverage and progressive refinement ordering
  are not validated.
- DQT table ids and DHT table ids are not checked for duplicates or for
  consistency with the frame/scan selectors.
- Trailing bytes after EOI are allowed and counted.
- The whole buffer must be in memory; there is no streaming interface.

## 17. Implementation notes

- Single module `xiom.jpeg`; the only stdlib import is `xiom.convert`
  (`int_to_string` for offset-carrying messages).
- Pure XIOM, no FFI, no data files; every byte read is widened with
  `(data[i] as Int) & 0xFF`.
- Identifiers (JFIF/EXIF markers, component ids) are compared byte-wise; no
  byte range is ever turned into a `Str`.
- The parser uses an internal accumulator with `Vec[Int]` parallel fields and
  appends through helpers so sibling vectors cannot drift; the public
  `JpegImage` exposes the same vectors plus scalar fields.
- `Ok`/`Err` construction is confined to tiny leaf helpers (`_ok_img`,
  `_fail_img`); in-parser success is an internal `JpegError` with offset -1.
- Complexity is O(input bytes) time and O(number of segments/tables/scans)
  indexed state; the raw scan bytes are referenced, not copied.
