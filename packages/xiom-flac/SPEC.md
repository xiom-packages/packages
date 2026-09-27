# xiom.flac -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.flac`, version `0.1.0`).
Module: `src/flac.xi` (`module xiom.flac`).
Depends on `xiom.std` (`xiom.string.builder`, `xiom.convert`,
`xiom.encoding.hex`; the tests add `xiom.test`, `xiom.io`, `xiom.string`,
`xiom.string.compare`).
No FFI: the module declares no `extern "C"` blocks and performs no audio
decoding.

## Scope

A pure-XIOM structural parser for native FLAC streams:

- `flac_parse_metadata` validates the stream marker and walks every
  metadata block, exposing the block index, STREAMINFO fields, padding
  total, application ids/lengths, seek entries, Vorbis comments, cue-sheet
  summaries and the picture summary;
- `flac_parse_streaminfo`, `flac_parse_vorbis_comment` and
  `flac_parse_picture` parse single payloads directly;
- `flac_parse_frame_header` decodes and validates one audio frame header,
  including the UTF-8 coded frame/sample number and the CRC-8 byte;
- `flac_utf8_size`, `flac_parse_utf8_number` and `flac_crc8` are the
  standalone number/checksum helpers;
- `flac_block_size_for_code`, `flac_sample_rate_for_code`,
  `flac_bits_per_sample_for_code`, `flac_channel_assignment_channels`,
  `flac_channel_assignment_name`, `flac_metadata_type_name` and
  `flac_blocking_strategy_name` are table/name helpers;
- the `flac_*` accessors read the parallel-vector fields of the metadata
  result with `-1` (Int) / `""` (Str) out-of-range conventions.

## Non-goals

- Audio decoding: no subframe decoding, no Rice/residual decoding, no
  predictor reconstruction, no stereo decorrelation, no frame-footer CRC-16
  verification, no sample output.
- Frame navigation: the parser reads one header at a requested offset; it
  does not search for sync words or walk frames.
- CRC-8 enforcement: a mismatch is reported via `crc8_ok`, never rejected.
- Semantic validation of STREAMINFO (rate/bits/block-size plausibility,
  min <= max ordering) and of UTF-8 text in comments/descriptions.
- CUESHEET field exposure: the payload is length-checked only.
- PICTURE data access, MD5 verification against decoded audio, ID3 tags,
  Ogg FLAC mapping (this is the native stream format only).
- Encoding, transcoding, file I/O and streaming (in-memory buffers only).

## Stream marker

The stream starts with the four ASCII bytes `fLaC` (0x66 0x4C 0x61 0x43)
at offset 0.

## Metadata block header (4 bytes)

| Byte | Bits | Field |
|---|---|---|
| 0 | 7 | last-metadata-block flag (1 = last) |
| 0 | 6..0 | block type (0..6 defined, 7..126 invalid, 127 forbidden) |
| 1..3 | 23..0 | 24-bit big-endian payload length |

Payload length counts the bytes after this 4-byte header. Types:

| Type | Name | Payload |
|---|---|---|
| 0 | STREAMINFO | 34 bytes, mandatory, first block, at most one |
| 1 | PADDING | arbitrary bytes; only the length is reported |
| 2 | APPLICATION | 4-byte registered id + data (>= 4 bytes total) |
| 3 | SEEKTABLE | n * 18-byte entries |
| 4 | VORBIS_COMMENT | little-endian vendor + comments |
| 5 | CUESHEET | fixed part + tracks + indices |
| 6 | PICTURE | picture metadata + data |

The walk stops after the block whose last-block flag is set. `audio_offset`
(= `metadata_size`) is the first byte after that block; audio frames and
any trailing bytes are not inspected by `flac_parse_metadata`.

## STREAMINFO (34 bytes)

Offsets are within the payload (no 4-byte block header).

| Bytes | Field |
|---|---|
| 0..1 | minimum block size in samples, u16 BE |
| 2..3 | maximum block size in samples, u16 BE |
| 4..6 | minimum frame size in bytes, u24 BE (0 = unknown) |
| 7..9 | maximum frame size in bytes, u24 BE (0 = unknown) |
| 10..17 | sample rate / channels / bits per sample / total samples (bitfields below) |
| 18..33 | MD5 of the unencoded audio, 16 bytes |

Bitfield extraction (p[k] = byte k, all fields MSB-first):

| Field | Bits | Formula |
|---|---|---|
| sample rate | 20 | `p[10]*4096 + p[11]*16 + p[12]/16` |
| channels - 1 | 3 | `(p[12]/2) % 8` |
| bits per sample - 1 | 5 | `(p[12]%2)*16 + p[13]/16` |
| total samples | 36 | `(p[13]%16)*4294967296 + BE32(p[14..17])` |

`md5_hex` renders bytes 18..33 as 32 lowercase hex characters. Values are
reported as stored; a zero sample rate or a one-bit bit depth is legal
output of the parser.

## PADDING, APPLICATION, SEEKTABLE

- **PADDING**: contributes its full declared length to
  `flac_padding_bytes`; contents are not validated.
- **APPLICATION**: the first 4 payload bytes are the application id
  (truncated at the first 0x00 when exposed), the rest is the data;
  `app_data_lengths[i] = length - 4`. A payload shorter than 4 bytes is
  Err(`flac: short application block at N`).
- **SEEKTABLE**: the payload length must be a multiple of 18
  (Err(`flac: bad seektable length at N`) otherwise). Each entry is

  | Bytes | Field |
  |---|---|
  | 0..7 | sample number, u64 BE (`0xFFFFFFFFFFFFFFFF` = placeholder) |
  | 8..15 | byte offset, u64 BE (`0xFFFFFFFFFFFFFFFF` = placeholder) |
  | 16..17 | number of samples in the target frame, u16 BE |

  Values with bit 63 set are clamped to `Int` max (9223372036854775807);
  other u64 values are exact.

## VORBIS_COMMENT

All lengths are unsigned 32-bit little-endian.

```
u32 vendor_length
vendor_length bytes vendor
u32 comment_count
comment_count x { u32 length; length bytes comment }
```

The payload must be consumed exactly: a field overrun, a comment overrun
or any trailing byte is Err(`flac: vorbis comment overrun at N`). Strings
stop at the first 0x00 (the stored length is still consumed); other bytes
are copied verbatim, so UTF-8 passes through unvalidated. Multiple
VORBIS_COMMENT blocks are accepted: every block appends to `comments`,
while `vendor` is the vendor of the last block parsed.

## CUESHEET (opaque, length-checked)

Fixed part, 396 bytes:

| Bytes | Field |
|---|---|
| 0..127 | media catalog number (not exposed) |
| 128..135 | lead-in samples, u64 BE (not exposed) |
| 136 | bit 7 is-CD; bits 6..0 + 258 bytes reserved (not exposed) |
| 395 | track count, u8 (must describe the rest of the payload) |

Each track is 36 bytes (u64 offset, u8 number, 12-byte ISRC, flags, 13
reserved bytes, u8 index count), then each index point is 12 bytes (u64
offset, u8 number, 3 reserved bytes). The walk must land exactly on the
end of the payload:

- length < 396, a track header past the end, an index run past the end, or
  a walk that does not consume the payload exactly ->
  Err(`flac: bad cuesheet length at N`, N = block header offset).

On success `cue_track_counts[i]` is the declared track count and
`cue_lengths[i]` the payload length.

## PICTURE

All numeric fields are unsigned 32-bit big-endian.

```
u32 type
u32 mime_length; mime_length bytes mime
u32 description_length; description_length bytes description
u32 width
u32 height
u32 depth
u32 colors
u32 data_length; data_length bytes data
```

The payload must be consumed exactly. Overruns, underruns and trailing
bytes are Err(`flac: picture block overrun at N`). `mime` and
`description` stop at the first 0x00 when exposed; the data bytes are not
copied and only `data_length` is reported.

## Metadata validation order (first failure wins)

`flac_parse_metadata` checks, in order:

1. empty buffer -> Err(`flac: empty input`)
2. fewer than 4 bytes -> Err(`flac: truncated stream marker at 0`)
3. bytes 0..3 != `fLaC` -> Err(`flac: bad stream marker at 0`)
4. per block: block header position == end of buffer without a last-block
   flag -> Err(`flac: missing last metadata block at N`)
5. fewer than 4 bytes of block header remain -> Err(`flac: truncated
   block header at N`)
6. type 127 -> Err(`flac: forbidden block type at N`)
7. type 7..126 -> Err(`flac: invalid block type at N`)
8. declared payload past the end of the buffer -> Err(`flac: block
   overrun at N`)
9. first block type != 0 -> Err(`flac: missing streaminfo at N`)
10. later block with type 0 -> Err(`flac: duplicate streaminfo at N`)
11. STREAMINFO length != 34 -> Err(`flac: bad streaminfo length at N`)
12. APPLICATION length < 4 -> Err(`flac: short application block at N`)
13. SEEKTABLE length not a multiple of 18 -> Err(`flac: bad seektable
    length at N`)
14. VORBIS_COMMENT structural error -> Err(`flac: vorbis comment overrun
    at N`)
15. PICTURE structural error -> Err(`flac: picture block overrun at N`)
16. CUESHEET structural error -> Err(`flac: bad cuesheet length at N`)

In every per-block error N is the offset of that block's 4-byte header.
`flac_parse_streaminfo` uses the same messages with N = 0 for a payload
that is not exactly 34 bytes; the standalone
`flac_parse_vorbis_comment`/`flac_parse_picture` wrappers use N = 0 for
every structural error.

## Frame header

Offsets are within the header; bit fields are written MSB-first as they
appear on the wire. The module reads them with division and modulo.

| Byte | Bits | Field |
|---|---|---|
| 0 | 7..0 | sync high bits: must be 0xFF |
| 1 | 7..2 | sync low bits: must be 111110 (byte 1 in 0xF8..0xFB) |
| 1 | 1 | reserved, must be 0 |
| 1 | 0 | blocking strategy: 0 fixed (frame number), 1 variable (sample number) |
| 2 | 7..4 | block-size code |
| 2 | 3..0 | sample-rate code |
| 3 | 7..4 | channel assignment |
| 3 | 3..1 | sample-size code |
| 3 | 0 | reserved, must be 0 |
| 4.. | 1..7 | UTF-8 coded frame/sample number |
| + | 0/1/2 | optional block-size extra (codes 6/7) |
| + | 0/1/2 | optional sample-rate extra (codes 12/13/14) |
| + | 1 | CRC-8 of everything above (poly 0x07, init 0, MSB-first) |

The sync code is 14 bits: `0b11111111111110` (0x3FFE); on the wire this is
byte 0 = 0xFF and byte 1 bits 7..2 = 0b111110.

### Block-size code

| Code | Block size in samples |
|---|---|
| 0 | reserved (rejected) |
| 1 | 192 |
| 2 | 576 |
| 3 | 1152 |
| 4 | 2304 |
| 5 | 4608 |
| 6 | 8-bit (value + 1) follows |
| 7 | 16-bit (value + 1) follows |
| 8 | 256 |
| 9 | 512 |
| 10 | 1024 |
| 11 | 2048 |
| 12 | 4096 |
| 13 | 8192 |
| 14 | 16384 |
| 15 | 32768 |

`flac_block_size_for_code` returns 0 for code 0, -1 for codes 6/7 (extra
field follows, value unknown without the bytes) and the table value
otherwise.

### Sample-rate code

| Code | Sample rate |
|---|---|
| 0 | from STREAMINFO (the header parser reports 0) |
| 1 | 88200 |
| 2 | 176400 |
| 3 | 192000 |
| 4 | 8000 |
| 5 | 16000 |
| 6 | 22050 |
| 7 | 24000 |
| 8 | 32000 |
| 9 | 44100 |
| 10 | 48000 |
| 11 | 96000 |
| 12 | 8-bit value in kHz follows (x1000) |
| 13 | 16-bit value in Hz follows |
| 14 | 16-bit value in tens of Hz follows (x10) |
| 15 | forbidden (rejected) |

`flac_sample_rate_for_code` returns 0 for code 0, -1 for codes 12..14 and
-2 for code 15 (and for out-of-range codes).

### Channel assignment

| Value | Meaning | Derived channels |
|---|---|---|
| 0..7 | independent (assignment + 1 channels) | 1..8 |
| 8 | left/side stereo | 2 |
| 9 | right/side stereo | 2 |
| 10 | mid/side stereo | 2 |
| 11..15 | reserved (rejected) | - |

`flac_channel_assignment_channels` returns -1 for 11..15;
`flac_channel_assignment_name` returns `"independent"`,
`"left/side stereo"`, `"right/side stereo"`, `"mid/side stereo"` or `""`.

### Sample-size code

| Code | Bits per sample |
|---|---|
| 0 | from STREAMINFO (the header parser reports 0) |
| 1 | 8 |
| 2 | 12 |
| 3 | reserved (rejected) |
| 4 | 16 |
| 5 | 20 |
| 6 | 24 |
| 7 | 32 |

`flac_bits_per_sample_for_code` returns 0 for code 0 and -1 for code 3.

### UTF-8 coded number

The coded number follows the classic UTF-8 prefix pattern (RFC 2279-style
ranges, FLAC's "coded number"):

| Bytes | Lead byte | Min value | Max value |
|---|---|---|---|
| 1 | `0xxxxxxx` | 0 | 0x7F |
| 2 | `110xxxxx` | 0x80 | 0x7FF |
| 3 | `1110xxxx` | 0x800 | 0xFFFF |
| 4 | `11110xxx` | 0x10000 | 0x1FFFFF |
| 5 | `111110xx` | 0x200000 | 0x3FFFFFF |
| 6 | `1111110x` | 0x4000000 | 0x7FFFFFFF |
| 7 | `11111110` | 0x80000000 | 0xFFFFFFFFF |

Validation: the lead byte must be a valid form (0x80..0xBF continuation
bytes used as a lead and 0xFF are invalid); every following byte must be
0x80..0xBF; a value below the minimum for its length is overlong. With the
fixed-blocksize strategy the decoded frame number must fit 31 bits
(<= 0x7FFFFFFF); the variable-blocksize sample number may use the full
36-bit range.

Errors (`N` = number start for truncated/overlong/invalid-lead, the
offending byte for a bad continuation):

| Error | Condition |
|---|---|
| `flac: offset out of range` | offset < 0 |
| `flac: truncated utf8 number at N` | coded bytes leave the buffer |
| `flac: invalid utf8 number at N` | bad lead byte or bad continuation byte |
| `flac: overlong utf8 number at N` | value below the minimum for its length |

### CRC-8

Parameters: polynomial 0x07 (x^8 + x^2 + x + 1), initial value 0x00,
MSB-first, no input/output reflection, no final xor. The stored byte is
computed over every header byte from the sync code up to (not including)
the CRC byte itself. `flac_crc8(data, start, size)` computes it over any
range and returns -1 for a negative/invalid range. Check vectors used by
the suite: empty -> 0, `"123456789"` -> 0xF4 (244), single `0xFF` -> 0xF3
(243), single `0x80` -> 0x89 (137), bytes `FF F8 C9 08 00` -> 0x95 (149).

A mismatch between the stored byte and the recomputation is reported
(`crc8`, `crc8_ok`); the header is still returned successfully.

## Frame-header validation order (first failure wins)

1. `offset < 0` -> Err(`flac: offset out of range`)
2. fewer than 4 bytes from `offset` -> Err(`flac: truncated frame header
   at N`, N = offset)
3. byte 0 != 0xFF or byte 1 outside 0xF8..0xFB -> Err(`flac: bad sync at
   N`)
4. byte 1 bit 1 set -> Err(`flac: reserved bit set at N`)
5. block-size code 0 -> Err(`flac: reserved block size at N`)
6. sample-rate code 15 -> Err(`flac: reserved sample rate at N`)
7. channel assignment 11..15 -> Err(`flac: reserved channel assignment at
   N`)
8. sample-size code 3 -> Err(`flac: reserved sample size at N`)
9. byte 3 bit 0 set -> Err(`flac: reserved bit set at N`)
10. UTF-8 number errors as above
11. fixed strategy and number > 2^31-1 -> Err(`flac: frame number out of
    range at N`, N = number start)
12. each optional extra field and the CRC byte must be inside the buffer
    -> Err(`flac: truncated frame header at N`) otherwise

On success `header_size` is the total header length in bytes, CRC
included.

## Test matrix

`tests/test_conformance.xi` prints one `[PASS]` line per check; every
fixture is built in-test (no external data files).

| Test | Covers |
|---|---|
| t1 | STREAMINFO fields, MD5 hex, single-block index, marker-only stream |
| t2 | STREAMINFO edge values: min 16 / max 65535 blocks, 24-bit frame sizes, 192 kHz, 8 channels, 32 bps, 36-bit total samples, MD5 all-FF |
| t3 | empty input, truncated/bad marker, missing last block, truncated header, block overrun, missing/duplicate STREAMINFO |
| t4 | block type 7/126 invalid, 127 forbidden, STREAMINFO length 33/35, non-STREAMINFO first block |
| t5 | PADDING accumulation and APPLICATION id/length, short payload, NUL-truncated id |
| t6 | SEEKTABLE two entries, 0xFFFF.. placeholders clamped, empty table, length % 18 |
| t7 | VORBIS_COMMENT vendor/comments, empty vendor+list, NUL-truncated comment, vendor overrun, trailing byte |
| t8 | PICTURE fields, two pictures, out-of-range accessors, data overrun, trailing byte, short payload |
| t9 | CUESHEET minimal valid walk, short payload, index-count overrun, trailing byte |
| t10 | six-block stream in order: index offsets/types/lengths and every payload |
| t11 | pinned fixed-blocksize header `FF F8 C9 08 00 95` (CRC 149 pin + reference) |
| t12 | variable strategy, 8-bit block-size extra, 8-bit kHz sample-rate extra, mid/side, 24 bps; 16-bit extra + tens-of-Hz rate + left/side + STREAMINFO bps; missing extras |
| t13 | UTF-8 coded numbers 1..7 bytes (pinned encodings and boundaries), overlong/invalid/truncated forms, offsets |
| t14 | block-size/sample-rate/bits-per-sample tables, channel assignments, type and strategy names |
| t15 | bad sync, both reserved bits, reserved codes, truncation at each field, fixed-strategy number range vs variable-strategy acceptance |
| t16 | CRC-8 pinned vectors, bounds guard, 0..255 cross-check against the independent reference, mismatch flag |
| t17 | empty-collection accessors and range guards (`-1`/`""`) |
| t18 | end-to-end stream (metadata + first frame at `audio_offset`), standalone payload parsers |

## Complexity and implementation notes

- `flac_parse_metadata` is O(metadata size); `flac_parse_frame_header`,
  `flac_parse_utf8_number` and every table helper are O(1);
  `flac_crc8` is O(size).
- Ok/Err values are only constructed in the small leaf helpers at the top
  of the module (v0.61.3 miscompiles direct construction elsewhere).
- `Vec[StructType]` is not used: metadata block entries, seek entries,
  cue-sheet summaries and pictures are index-aligned parallel vectors,
  with every push mirrored on its siblings.
- Str values read from `Vec[Str]` are only compared by callers with
  `xiom.string.compare.str_compare`.
- All arithmetic is integer; no `Float64` is used anywhere.
