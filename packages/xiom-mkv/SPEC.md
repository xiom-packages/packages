# xiom.mkv -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.mkv`, version `0.1.0`).
Module: `src/mkv.xi` (`module xiom.mkv`).
Depends on `xiom.std`; the library module imports `xiom.string.builder`,
`xiom.string.compare` and `xiom.utf8`.

This document describes the byte-level format this package actually parses:
an EBML stream whose DocType is `matroska` or `webm`, walked down to the
Segment's `Info` and `Tracks` elements and the spans of the Segment's
top-level `Cluster` elements. Anything else is skipped, not interpreted.

## 1. EBML VINTs

Element IDs and sizes are variable-length integers (VINTs) of 1..8 bytes. The
first byte's most significant set bit is the width marker:

| First byte | Width | Marker value |
|---|---|---|
| `0x80..0xFF` | 1 | `0x80` (2^7) |
| `0x40..0x7F` | 2 | `0x4000` (2^14) |
| `0x20..0x3F` | 3 | `0x200000` (2^21) |
| `0x10..0x1F` | 4 | `0x10000000` (2^28) |
| `0x08..0x0F` | 5 | 2^35 |
| `0x04..0x07` | 6 | 2^42 |
| `0x02..0x03` | 7 | 2^49 |
| `0x01` | 8 | 2^56 |

Rules implemented (`mkv_vint_id`, `mkv_vint_size`, and the width functions):

- An ID keeps its marker bits: the decoded value is the big-endian integer of
  all `width` bytes (`Segment` = `0x18538067`, `TrackEntry` = `0xAE`).
- A size strips the marker bits: `value - 2^(7*width)`.
- A size whose data bits are all one (`2^(7*width) - 1`, i.e. `0xFF`,
  `0x7FFF`, ...) is the EBML unknown-size sentinel and is reported as
  `-1` (`MKV_SIZE_UNKNOWN`).
- An ID whose data bits are all zero (`0x80`, `0x4000`, ...) is the reserved
  encoding and is rejected: `mkv: invalid vint`.
- A first byte of `0x00` means a VINT wider than 8 bytes: `mkv: invalid
  vint`.
- A VINT whose bytes cross the buffer (or the enclosing element) end is
  `mkv: truncated vint` (inside `_element`) or `mkv: truncated element` (when
  the element header crosses its container).
- An unknown-size VINT has a valid width (`2` for `0x7FFF`, `3` for
  `0x3FFFFF`, ...); `mkv_vint_size_width` reports it.

The arithmetic is exact for every width through 8 bytes; size values above
2^63-1 could only arise from an 8-byte VINT with data bits above 2^55, which
is not exercised by any element this module accepts.

## 2. Element layout

```
element := ID-VINT  SIZE-VINT  body[SIZE]
```

- A known size must fit entirely inside its parent (Segment, EBML header,
  Info, Tracks, TrackEntry, Video, Audio) and the buffer. A declared size that
  crosses a parent end is `mkv: truncated element`; a Segment whose declared
  size crosses the buffer is `mkv: truncated segment`.
- An unknown size (`-1`) is legal on the Segment and on top-level Cluster
  elements only. On any other element it is `mkv: unknown-size element`.
- Elements this module does not know are skipped by their declared size,
  provided the size is known and fits.

## 3. Top level

```
stream := EBML-header  Void*  Segment
```

- `EBML-header` (ID `0x1A45DFA3`) must come first, with a known non-zero size
  (`mkv: bad ebml header size` otherwise; a different first ID is
  `mkv: not an ebml stream`). Its children:

| ID | Element | Default | Validation |
|---|---|---|---|
| `0x4286` | EBMLVersion | 1 | >= 1 |
| `0x42F7` | EBMLReadVersion | 1 | must be 1 (`mkv: unsupported ebml version`) |
| `0x42F2` | EBMLMaxIDLength | 4 | 1..4 |
| `0x42F3` | EBMLMaxSizeLength | 8 | 1..8 |
| `0x4282` | DocType | -- | `matroska` or `webm` (`mkv: bad doctype`) |
| `0x4287` | DocTypeVersion | 1 | >= 1 |
| `0x4288` | DocTypeReadVersion | 1 | >= 1 and <= DocTypeVersion |

  A violation of the version/limit rules is `mkv: bad ebml header`.
- `Void` (`0xEC`) elements may precede the Segment and are skipped by size.
- `Segment` (ID `0x18538067`) is required after the optional Voids; a
  different element or a missing Segment is `mkv: segment not found`. The
  Segment size may be known (children bounded by it) or unknown (children run
  to the buffer end). Parsing stops after the first Segment; trailing bytes
  are ignored.

## 4. Segment children

| ID | Element | Handling |
|---|---|---|
| `0x1549A966` | Info | parsed (section 5) |
| `0x1654AE6B` | Tracks | parsed (section 6) |
| `0x1F43B675` | Cluster | recorded and skipped (section 7) |
| `0x114D9B74` | SeekHead | skipped |
| `0x1C53BB6B` | Cues | skipped |
| `0x1941A469` | Attachments | skipped |
| `0x1043A770` | Chapters | skipped |
| `0x1254C367` | Tags | skipped |
| `0xEC` | Void | skipped |
| `0xBF` | CRC-32 | skipped |
| any other | unknown | skipped when sized |

Multiple Info/Tracks elements are accepted; the last Info element parsed wins
for the scalar Info fields, and every TrackEntry encountered in every Tracks
element is appended in document order.

## 5. Info

| ID | Element | Type | Result |
|---|---|---|---|
| `0x2AD7B1` | TimestampScale | UInt | nanoseconds per timestamp unit; 0 is `mkv: bad timestamp scale` |
| `0x4489` | Duration | Float | fixed-point in 1/1000 timestamp unit |
| `0x4D80` | MuxingApp | UTF-8 | `mkv_muxing_app` |
| `0x5741` | WritingApp | UTF-8 | `mkv_writing_app` |
| `0x7BA9` | Title | UTF-8 | `mkv_title` |

Defaults when Info or a field is absent: TimestampScale `1000000`, Duration
`-1` (absent), all strings `""`; `mkv_info_offset` is `-1` when the Segment
has no Info element.

### 5.1 UInt fields

A Matroska UInt of `size` bytes (0..8) is the big-endian unsigned value;
`size` 0 is 0, and a width above 8 is `mkv: bad integer width`. A width-8
value with bit 63 set wraps to the same two's-complement `Int` bit pattern
(no accepted field in this module reaches that range).

### 5.2 Float fields

An EBML Float is 0, 4 (binary32) or 8 (binary64) bytes, big-endian sign /
exponent / mantissa. Decoding is integer-only (no `Float64`, no
`Vec[Float64]`):

- `value = (-1)^sign * (2^(mantissa_bits) + mantissa) * 2^(exponent - bias -
  mantissa_bits)`, where the bias is 127 (4-byte) or 1023 (8-byte) and the
  mantissa width is 23 or 52 bits.
- The result is scaled to milli-units, `round(sign * value * 1000)` with ties
  rounded half away from zero (`_scale_milli`).
- Zero-length floats are 0. The zero exponent (denormal/zero) decodes to 0,
  since any denormal magnitude is below 0.0005.
- The all-ones exponent (infinity/NaN) is `mkv: bad float`; any width other
  than 0, 4 or 8 is `mkv: bad float`.
- Magnitudes whose scaling leaves the signed `Int` range are
  `mkv: float overflow`.

`mkv_duration_milli_units` returns Duration * 1000 in timestamp units
(`-1` absent). `mkv_duration_nanos` returns
`milli_units * TimestampScale / 1000` and `mkv_duration_millis` returns
`milli_units * TimestampScale / 1000000`; both truncate toward zero and
return `-1` when Duration is absent. `SamplingFrequency` uses the same
milli-unit scaling into `mkv_track_audio_sampling_millihz`.

### 5.3 Text fields

A text field is copied out only after validation:

- the span must lie in the buffer;
- it must contain no `0x00` byte (`mkv: bad text field`), because
  `xiom.string.builder.sb_to_str` aborts on NUL;
- it must be well-formed UTF-8 per `xiom.utf8.utf8_validate`
  (`mkv: bad text field`).

Empty text is the empty string.

## 6. Tracks

`Tracks` contains `TrackEntry` (`0xAE`) children; other children are skipped.
A TrackEntry with a TrackNumber of 0 (absent or zero) is
`mkv: bad track number`.

| ID | Element | Type | Track accessor |
|---|---|---|---|
| `0xD7` | TrackNumber | UInt | `mkv_track_number` |
| `0x73C5` | TrackUID | UInt | `mkv_track_uid` |
| `0x83` | TrackType | UInt | `mkv_track_type` |
| `0x86` | CodecID | UTF-8 | `mkv_track_codec_id` |
| `0x536E` | Name | UTF-8 | `mkv_track_name` |
| `0x22B59C` | Language | UTF-8 | `mkv_track_language` |
| `0x22B59D` | LanguageIETF | UTF-8 | `mkv_track_language_ietf` |
| `0xE0` | Video | container | section 6.1 |
| `0xE1` | Audio | container | section 6.2 |

`TrackType` is stored verbatim: 1 video, 2 audio, 3 complex, 17 subtitle are
the documented values, but any value is reported. Absent numeric fields are
0; `mkv_track_offset` is the offset of the TrackEntry element ID.

Each track's fields are parsed into locals first and all pushed together at
the end, so the parallel vectors always have the same length; every accessor
additionally guards index range and the store exposes the minimum length
across the pools as the count.

### 6.1 Video (`0xE0`) and Audio (`0xE1`)

| Container | ID | Element | Type | Track accessor |
|---|---|---|---|---|
| Video | `0xB0` | PixelWidth | UInt | `mkv_track_video_width` |
| Video | `0xBA` | PixelHeight | UInt | `mkv_track_video_height` |
| Audio | `0xB5` | SamplingFrequency | Float | `mkv_track_audio_sampling_millihz` |
| Audio | `0x9F` | Channels | UInt | `mkv_track_audio_channels` |

Both containers are walked exactly one level deep; other children (and
children of the containers that are not listed) are skipped by size.

## 7. Clusters

Cluster payloads are never decoded. For each top-level Cluster:

- Known size: the span is `[element offset, data offset + size)`; the next
  Segment child starts at `data offset + size`.
- Unknown size: the end is found by scanning forward byte by byte from the
  payload for the next ID in the recognised Segment-level set (SeekHead,
  Info, Tracks, Cluster, Cues, Attachments, Chapters, Tags, Void, CRC-32)
  whose ID and size VINTs parse and whose declared size (when known) fits the
  remaining region. The first such candidate wins; when none is found the
  Cluster ends at the Segment end (or the buffer end for an unknown-size
  Segment).

Recorded per Cluster: element offset, data offset, declared size (`-1` for
unknown), exclusive end offset and an unknown-size flag. The boundary scan is
a heuristic: frame payload bytes that happen to form a valid candidate ID and
size can truncate a reported Cluster span early. This is accepted and
documented; no frame byte is interpreted otherwise.

## 8. Error catalog

| Message | Raised when |
|---|---|
| `mkv: truncated vint` | a VINT's bytes cross the buffer (or `pos` is out of range) |
| `mkv: invalid vint` | first byte `0x00` (width > 8) or a reserved ID (data bits all zero) |
| `mkv: truncated element` | an element header or body crosses its parent/buffer, or an empty buffer is parsed |
| `mkv: unknown-size element` | unknown-size encoding on anything but Segment/Cluster |
| `mkv: not an ebml stream` | the buffer does not start with the EBML header ID |
| `mkv: bad ebml header size` | EBML header size is unknown or zero |
| `mkv: bad ebml header` | version/max-length fields out of range, or DocTypeReadVersion > DocTypeVersion |
| `mkv: unsupported ebml version` | EBMLReadVersion != 1 |
| `mkv: bad doctype` | DocType absent or not `matroska`/`webm` |
| `mkv: segment not found` | no Segment after the header and Voids |
| `mkv: truncated segment` | Segment size crosses the buffer |
| `mkv: bad integer width` | integer element wider than 8 bytes |
| `mkv: bad float` | Float width not 0/4/8, or an all-ones exponent |
| `mkv: float overflow` | Float magnitude leaves the signed Int range when scaled |
| `mkv: bad text field` | NUL or invalid UTF-8 in a text element |
| `mkv: bad timestamp scale` | TimestampScale is 0 |
| `mkv: bad track number` | TrackEntry with TrackNumber 0 or absent |

The whole `mkv_parse` call is `Err` on any failure; no partial `MkvFile` is
returned.

## 9. Test plan (`tests/test_conformance.xi`, 20 checks)

Synthetic buffers only; every fixture is built in-test from VINT/element
helpers. Coverage:

1. VINT ID decode (1/3/4-byte, marker bits kept).
2. VINT size decode (1..4-byte, marker stripped).
3. Unknown-size sentinels for widths 1..8 and an 8-byte size.
4. Zero first byte, reserved ID patterns, truncation, out-of-range widths.
5. `mkv_is_file` sniff and its 5-byte minimum.
6. EBML header fields, Segment offset/size, Info offset.
7. DocType: webm accepted; bad, missing and empty DocType rejected;
   EBMLReadVersion != 1 rejected.
8. Info defaults with empty and absent Info.
9. Full Info: TimestampScale, float32 Duration, apps, UTF-8 Title, unknown
   child skipped.
10. Duration floats: binary32/binary64, 0.5, negative, zero-length.
11. Video TrackEntry: UID, CodecID, Name, Language, LanguageIETF, Video
    dimensions, unknown child skipped.
12. Audio TrackEntry: float64 SamplingFrequency, Channels, BitDepth skipped.
13. Three entries (video/audio/subtitle 17): order, offsets, index guards.
14. Known-size clusters: spans, payload ends, frames not decoded, Tags after
    them still parsed.
15. Unknown-size clusters: boundary at the next valid top-level ID, at the
    buffer end, and rejection of a fake in-frame candidate that does not
    validate.
16. Malformed: truncated element, zero-byte ID, unknown-size header/element,
    integer width > 8, TrackEntry without TrackNumber.
17. Truncated input: empty buffer, header-only streams, oversized Segment,
    and buffer prefixes of a valid file.
18. VINT round-trip: sizes across width boundaries, unknown sentinels for
    widths 1..8, the Matroska ID table, canonical encodings of 63 and 0.
19. Validation: NUL and invalid UTF-8 text, bad floats in Info and Audio,
    zero TimestampScale.
20. Guarded accessors on an empty store (no Info/Tracks/Clusters).

Run:

```powershell
.\scripts\port.ps1 -Package xiom.mkv
```
