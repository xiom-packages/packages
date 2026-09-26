# xiom.mp3 -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.mp3`, version `0.1.0`).
Module: `src/mp3.xi` (`module xiom.mp3`).
Depends on `xiom.std` (`xiom.string.builder`, `xiom.string.compare`,
`xiom.convert`; the tests add `xiom.test`, `xiom.io`, `xiom.string`,
`xiom.encoding.hex`).
No FFI: the module declares no `extern "C"` blocks and performs no audio
decoding.

## Scope

A pure-XIOM structural parser for MP3 data:

- `mp3_parse_frame_header` validates and decodes one MPEG-1/2/2.5 audio
  frame header, including frame length and samples per frame;
- `mp3_find_frame` locates the first valid frame header at or after an
  offset; `mp3_scan` / `mp3_scan_from` count consecutive complete frames and
  derive total samples and duration;
- `mp3_id3v2_header` parses the 10-byte ID3v2.3/2.4 tag header;
  `mp3_id3v2_frames` walks the frames and collects ids, sizes and text
  payloads, de-escaping whole-tag unsynchronisation;
- `mp3_id3v2_title` / `_artist` / `_album` / `_track` / `_year` / `_genre`
  are convenience readers over TIT2, TPE1, TALB, TRCK, TYER or TDRC, and
  TCON;
- `mp3_id3v1` parses the 128-byte ID3v1 tail tag; `mp3_has_id3v1` and
  `mp3_id3v1_genre_name` are the boolean and genre-name helpers;
- table helpers: `mp3_bitrate_kbps`, `mp3_sample_rate`,
  `mp3_samples_per_frame`, `mp3_frame_length`, `mp3_frame_duration_ms` and
  the name functions `mp3_version_name`, `mp3_layer_name`,
  `mp3_channel_mode_name`, `mp3_emphasis_name`.

## Non-goals

- Audio decoding: no Huffman decoding, no requantisation, no synthesis
  filterbank, no bit-reservoir handling, no CRC verification, no
  side-info/granule parsing beyond the frame header.
- Encoding, transcoding, resampling and writing any file format.
- Free-format frames: the frame length of a free-format stream can only be
  found by scanning for the next sync word; such headers are detected and
  rejected (`mp3: free format at N`), never guessed.
- ID3v2.2 (3-character frame ids) and ID3v2 major versions other than 3 and
  4: rejected.
- ID3v2 extended headers and per-frame (v2.4) unsynchronisation/data-length
  indicators: not implemented; an extended header flag is rejected and
  per-frame flags are ignored.
- Text encodings other than 0 (ISO-8859-1) and 3 (UTF-8): the frame id and
  size are reported, the text is empty.
- ID3v1 genre names beyond the original Winamp set 0..79 (80..147, 255 and
  everything else map to "").
- Streaming over files/sockets; the API works on in-memory `Vec[UInt8]`.

## Byte layout: frame header (4 bytes)

Offsets are within the frame; bit fields are written MSB-first as they
appear on the wire. The module reads them with division and modulo.

| Bits | Field | Meaning |
|---|---|---|
| 31..21 | sync | 11 set bits: `B0 == 0xFF` and `B1 >= 0xE0`. |
| 20..19 | version | `00` MPEG-2.5 (this module: 25), `01` reserved, `10` MPEG-2 (2), `11` MPEG-1 (1). |
| 18..17 | layer | `00` reserved, `01` Layer III (3), `10` Layer II (2), `11` Layer I (1). |
| 16 | protection | `0` a 16-bit CRC follows the header (crc = true), `1` no CRC. |
| 15..12 | bitrate index | `0` free format (rejected), `1..14` table entry, `15` bad (rejected). |
| 11..10 | sample-rate index | `0..2` table entry, `3` reserved (rejected). |
| 9 | padding | `1` one extra byte in the frame. |
| 8 | private | ignored. |
| 7..6 | channel mode | `0` stereo, `1` joint stereo, `2` dual channel, `3` mono. |
| 5..4 | mode extension | exposed raw (0..3). |
| 3 | copyright | exposed as a Bool. |
| 2 | original | exposed as a Bool. |
| 1..0 | emphasis | `0` none, `1` 50/15 ms, `2` reserved, `3` CCITT J.17. Exposed raw; 2 is not rejected. |

Validation order (`mp3_parse_frame_header`, first failure wins):

1. `offset < 0` -> Err(`mp3: offset out of range`).
2. `offset + 4 > data.len()` -> Err(`mp3: truncated frame header at N`).
3. sync mismatch -> Err(`mp3: bad sync at N`).
4. version bits `01` -> Err(`mp3: reserved version at N`).
5. layer bits `00` -> Err(`mp3: reserved layer at N`).
6. bitrate index 15 -> Err(`mp3: bad bitrate index at N`).
7. bitrate index 0 -> Err(`mp3: free format at N`).
8. sample-rate index 3 -> Err(`mp3: bad sample rate index at N`).
9. defensive: computed length <= 0 -> Err(`mp3: bad frame length at N`)
   (unreachable after steps 3..8).

### Bitrate table (kbps)

| Index | MPEG-1 L1 | MPEG-1 L2 | MPEG-1 L3 | MPEG-2/2.5 L1 | MPEG-2/2.5 L2/L3 |
|---|---|---|---|---|---|
| 0 | free | free | free | free | free |
| 1 | 32 | 32 | 32 | 32 | 8 |
| 2 | 64 | 48 | 40 | 48 | 16 |
| 3 | 96 | 56 | 48 | 56 | 24 |
| 4 | 128 | 64 | 56 | 64 | 32 |
| 5 | 160 | 80 | 64 | 80 | 40 |
| 6 | 192 | 96 | 80 | 96 | 48 |
| 7 | 224 | 112 | 96 | 112 | 56 |
| 8 | 256 | 128 | 112 | 128 | 64 |
| 9 | 288 | 160 | 128 | 144 | 80 |
| 10 | 320 | 192 | 160 | 160 | 96 |
| 11 | 352 | 224 | 192 | 176 | 112 |
| 12 | 384 | 256 | 224 | 192 | 128 |
| 13 | 416 | 320 | 256 | 224 | 144 |
| 14 | 448 | 384 | 320 | 256 | 160 |
| 15 | bad | bad | bad | bad | bad |

`mp3_bitrate_kbps` returns the table value, `0` for index 0 (free), and
`-1` for index 15, an out-of-range index, or an unknown version/layer.

### Sample-rate table (Hz)

| Index | MPEG-1 | MPEG-2 | MPEG-2.5 |
|---|---|---|---|
| 0 | 44100 | 22050 | 11025 |
| 1 | 48000 | 24000 | 12000 |
| 2 | 32000 | 16000 | 8000 |
| 3 | reserved | reserved | reserved |

`mp3_sample_rate` returns 0 for index 3, an out-of-range index, or an
unknown version. The reserved index is rejected earlier by the header
parser.

### Samples per frame and frame length

| Version | Layer I | Layer II | Layer III |
|---|---|---|---|
| MPEG-1 | 384 | 1152 | 1152 |
| MPEG-2 | 384 | 1152 | 576 |
| MPEG-2.5 | 384 | 1152 | 576 |

Frame length in bytes (`kbps` in kbit/s, `rate` in Hz, `pad` is 0 or 1;
integer floor division):

| Version/layer | Formula |
|---|---|
| Layer I (all versions) | `(12 * kbps * 1000 / rate + pad) * 4` |
| Layer II (all versions) | `144 * kbps * 1000 / rate + pad` |
| Layer III MPEG-1 | `144 * kbps * 1000 / rate + pad` |
| Layer III MPEG-2/2.5 | `72 * kbps * 1000 / rate + pad` |

`mp3_frame_length` returns 0 when the length cannot be computed
(bitrate <= 0, sample rate <= 0, unknown version/layer).
`mp3_frame_duration_ms` is `samples_per_frame * 1000 / sample_rate`
(floor); 0 when the rate is <= 0.

## Buffer scan

`mp3_find_frame(data, start)`:

1. `start < 0` or `start > data.len()` -> Err(`mp3: offset out of range`).
2. Walk `pos` from `start` while `pos + 4 <= data.len()`. A position is a
   candidate when `B0 == 0xFF`, `B1 >= 0xE0`, version bits != `01`, layer
   bits != `00`, bitrate index != 15 and sample-rate index != 3; anything
   else advances `pos` by one.
3. The first candidate with bitrate index 0 -> Err(`mp3: free format at N`).
4. The first candidate with bitrate index 1..14 -> Ok(N).
5. No candidate at all (including `start == data.len()`) ->
   Err(`mp3: no frame found`).

`mp3_scan_from(data, start)` uses `mp3_find_frame`, parses the first frame
and rejects a first frame whose declared payload does not fit the buffer
with Err(`mp3: truncated frame at N`). It then counts the first frame and
every following frame while:

- the next 4 bytes parse as a header with the same version, layer and
  sample rate (bitrate may change: VBR is accepted), and
- the complete frame (declared length) fits in the buffer.

The scan stops cleanly at the end of the buffer or at a trailing ID3v1 tag
(exactly 128 remaining bytes starting with `TAG`). Any other stop -
unparseable bytes, a partial frame, a mismatched version/layer/sample rate
- sets `corrupted = true`. `trailing_bytes = data.len() - end_offset`;
`total_samples = frame_count * samples_per_frame`;
`duration_ms = total_samples * 1000 / sample_rate` (floor). Frame offsets
and lengths are index-aligned in the parallel vectors `frame_offsets` and
`frame_lengths`.

`mp3_scan(data)` skips a valid leading ID3v2 tag (scan starts at
`total_size`; a malformed tag propagates its error) and otherwise scans
from 0.

## Byte layout: ID3v2 header (10 bytes at offset 0)

| Offset | Size | Field |
|---|---|---|
| 0 | 3 | magic `ID3` (`49 44 33`). |
| 3 | 1 | major version: 3 or 4 only. |
| 4 | 1 | revision (exposed raw). |
| 5 | 1 | flags: bit 7 unsynchronisation, bit 6 extended header, bit 5 experimental, bit 4 footer (v2.4). |
| 6 | 4 | tag size, syncsafe: four bytes with the high bit clear, each contributing 7 bits (`b6*2^21 + b7*2^14 + b8*2^7 + b9`). |
| 10 | size | tag payload (frames and padding). |

`total_size = 10 + size`; a v2.4 footer is outside the size field per the
spec and only reported through the `footer` flag. Validation order in
`mp3_id3v2_header`:

1. `data.len() < 10` -> Err(`mp3: truncated id3v2 header at 0`).
2. magic mismatch -> Err(`mp3: bad id3v2 magic at 0`).
3. version not 3 or 4 -> Err(`mp3: unsupported id3v2 version at 3`).
4. a size byte >= 128 -> Err(`mp3: bad syncsafe size at N`), N = 6..9.
5. `10 + size > data.len()` -> Err(`mp3: id3v2 size overrun at 6`).

### ID3v2 frames

The payload (offsets 10..10+size) is copied into a logical body; when the
unsynchronisation flag is set, every `FF 00` pair is de-escaped to a single
`FF` during that copy (stored frame sizes describe the logical stream, so
they still apply). The walk then repeats:

- fewer than 10 bytes remain, or the next 4 id bytes are all zero
  (padding) -> stop;
- a v2.4 size byte with its high bit set -> Err(`mp3: bad id3v2 frame size
  at N`);
- a zero size -> stop;
- payload end past the logical body -> Err(`mp3: id3v2 frame overrun at
  N`);
- otherwise record id (4 bytes, stopped at a NUL), stored size, and - for
  frames whose first id byte is `T` with encoding byte 0 or 3 - the text
  from payload offset 1..size-1, stopped at the first NUL; then advance by
  `10 + size`.

v2.3 frame sizes are plain big-endian u32; v2.4 frame sizes are syncsafe.
Frame-level error offsets N are offsets into the logical
(de-unsynchronised) tag payload; header-level error offsets are absolute
buffer offsets. The extended header flag is rejected before the walk:
Err(`mp3: unsupported id3v2 extended header at 5`). Frame flag bytes are
read but not interpreted.

Text frame ids used by the convenience readers: TIT2 (title), TPE1
(artist), TALB (album), TRCK (track), TYER (v2.3 year) or TDRC (v2.4
year), TCON (genre). All lookups compare ids with
`string.compare.str_compare`.

## Byte layout: ID3v1 tail tag (128 bytes at `data.len() - 128`)

| Offset | Size | Field |
|---|---|---|
| 0 | 3 | `TAG` (`54 41 47`). |
| 3 | 30 | title, NUL padded. |
| 33 | 30 | artist, NUL padded. |
| 63 | 30 | album, NUL padded. |
| 93 | 4 | year, NUL padded. |
| 97 | 30 | comment; ID3v1.1 splits it. |
| 127 | 1 | genre byte (0..255). |

Fields are converted to `Str` up to the first NUL. ID3v1.1 is detected when
byte 125 (comment offset 28) is 0 and byte 126 (comment offset 29) is
nonzero; then `track = byte 126` (1..255), `has_track = true`, and the
comment is 28 bytes. Otherwise the full 30-byte comment is used,
`track = 0`, `has_track = false`. `mp3_id3v1_genre_name` maps 0..79 to the
original Winamp names (80..147 extensions and 255 map to "").

Validation order in `mp3_id3v1`:

1. empty buffer -> Err(`mp3: empty input`).
2. `data.len() < 128` -> Err(`mp3: truncated id3v1 tag (128 bytes
   required)`).
3. missing `TAG` at `data.len() - 128` -> Err(`mp3: no id3v1 tag at N`),
   N = `data.len() - 128`.

`mp3_has_id3v1` is the boolean form (false below 128 bytes).

## API signatures

All functions are free functions in module `xiom.mp3`:

```xi
pub type Mp3FrameHeader = {
  version: Int; layer: Int; bitrate_kbps: Int; sample_rate: Int;
  padding: Bool; crc: Bool; channel_mode: Int; mode_extension: Int;
  copyright: Bool; original: Bool; emphasis: Int;
  frame_length: Int; samples_per_frame: Int;
}

pub type Mp3Scan = {
  start: Int; offset: Int; frame_count: Int; end_offset: Int;
  trailing_bytes: Int; version: Int; layer: Int; sample_rate: Int;
  bitrate_kbps: Int; channel_mode: Int; samples_per_frame: Int;
  total_samples: Int; duration_ms: Int; corrupted: Bool;
  frame_offsets: Vec[Int]; frame_lengths: Vec[Int];
}

pub type Mp3Id3v2Info = {
  version: Int; revision: Int; flags: Int; payload_size: Int;
  total_size: Int; unsynchronised: Bool; extended_header: Bool;
  experimental: Bool; footer: Bool;
}

pub type Mp3Id3v2Frames = { ids: Vec[Str]; sizes: Vec[Int]; texts: Vec[Str]; }

pub type Mp3Id3v1 = {
  title: Str; artist: Str; album: Str; year: Str; comment: Str;
  track: Int; has_track: Bool; genre: Int;
}

pub fn mp3_version_name(version: Int) -> Str
pub fn mp3_layer_name(layer: Int) -> Str
pub fn mp3_channel_mode_name(mode: Int) -> Str
pub fn mp3_emphasis_name(emphasis: Int) -> Str
pub fn mp3_sample_rate(version: Int, index: Int) -> Int
pub fn mp3_bitrate_kbps(version: Int, layer: Int, index: Int) -> Int
pub fn mp3_samples_per_frame(version: Int, layer: Int) -> Int
pub fn mp3_frame_length(version: Int, layer: Int, bitrate_kbps: Int, sample_rate: Int, padding: Bool) -> Int
pub fn mp3_parse_frame_header(data: &Vec[UInt8], offset: Int) -> Result[Mp3FrameHeader, Str]
pub fn mp3_frame_duration_ms(header: &Mp3FrameHeader) -> Int
pub fn mp3_find_frame(data: &Vec[UInt8], start: Int) -> Result[Int, Str]
pub fn mp3_scan_from(data: &Vec[UInt8], start: Int) -> Result[Mp3Scan, Str]
pub fn mp3_scan(data: &Vec[UInt8]) -> Result[Mp3Scan, Str]
pub fn mp3_id3v2_header(data: &Vec[UInt8]) -> Result[Mp3Id3v2Info, Str]
pub fn mp3_id3v2_frames(data: &Vec[UInt8]) -> Result[Mp3Id3v2Frames, Str]
pub fn mp3_id3v2_frame_count(frames: &Mp3Id3v2Frames) -> Int
pub fn mp3_id3v2_frame_id(frames: &Mp3Id3v2Frames, i: Int) -> Str
pub fn mp3_id3v2_frame_size(frames: &Mp3Id3v2Frames, i: Int) -> Int
pub fn mp3_id3v2_frame_text(frames: &Mp3Id3v2Frames, i: Int) -> Str
pub fn mp3_id3v2_find(frames: &Mp3Id3v2Frames, id: Str) -> Int
pub fn mp3_id3v2_text(frames: &Mp3Id3v2Frames, id: Str) -> Str
pub fn mp3_id3v2_title(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn mp3_id3v2_artist(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn mp3_id3v2_album(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn mp3_id3v2_track(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn mp3_id3v2_year(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn mp3_id3v2_genre(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn mp3_has_id3v1(data: &Vec[UInt8]) -> Bool
pub fn mp3_id3v1(data: &Vec[UInt8]) -> Result[Mp3Id3v1, Str]
pub fn mp3_id3v1_genre_name(genre: Int) -> Str
```

## Error string catalog

| Condition | Error text |
|---|---|
| Negative frame offset; find/scan start < 0 or > `data.len()` | `mp3: offset out of range` |
| Fewer than 4 bytes at the frame offset | `mp3: truncated frame header at N` |
| `B0 != 0xFF` or `B1 < 0xE0` | `mp3: bad sync at N` |
| Version bits `01` | `mp3: reserved version at N` |
| Layer bits `00` | `mp3: reserved layer at N` |
| Bitrate index 15 | `mp3: bad bitrate index at N` |
| Bitrate index 0 (free format) | `mp3: free format at N` |
| Sample-rate index 3 | `mp3: bad sample rate index at N` |
| Computed length <= 0 (defensive) | `mp3: bad frame length at N` |
| No candidate frame header found | `mp3: no frame found` |
| First scanned frame incomplete | `mp3: truncated frame at N` |
| ID3v2 buffer shorter than 10 bytes | `mp3: truncated id3v2 header at 0` |
| Missing `ID3` magic | `mp3: bad id3v2 magic at 0` |
| ID3v2 major version not 3 or 4 | `mp3: unsupported id3v2 version at 3` |
| ID3v2 size byte >= 128 | `mp3: bad syncsafe size at N` |
| Declared ID3v2 tag past the buffer | `mp3: id3v2 size overrun at 6` |
| Extended header flag set | `mp3: unsupported id3v2 extended header at 5` |
| v2.4 frame size byte >= 128 | `mp3: bad id3v2 frame size at N` |
| ID3v2 frame payload past the tag | `mp3: id3v2 frame overrun at N` |
| ID3v1 buffer empty | `mp3: empty input` |
| ID3v1 buffer shorter than 128 bytes | `mp3: truncated id3v1 tag (128 bytes required)` |
| Missing `TAG` at `data.len() - 128` | `mp3: no id3v1 tag at N` |

N is the byte offset where the condition was detected: absolute in the
buffer for frame/scan and ID3v2 header errors, offset into the logical tag
payload for ID3v2 frame errors, and `data.len() - 128` for ID3v1.

## Complexity

| Operation | Complexity |
|---|---|
| table lookups, name functions, `mp3_frame_length`, `mp3_frame_duration_ms` | O(1) |
| `mp3_parse_frame_header` | O(1) |
| `mp3_find_frame` | O(data.len() - start) |
| `mp3_scan_from` / `mp3_scan` | O(scanned bytes) |
| `mp3_id3v2_header` | O(1) |
| `mp3_id3v2_frames` | O(payload_size) |
| frame accessors / `mp3_id3v2_find` / `mp3_id3v2_text` | O(1) / O(frame_count) |
| ID3v2 convenience readers | O(payload_size) |
| `mp3_has_id3v1` / `mp3_id3v1` / `mp3_id3v1_genre_name` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module mp3_tests`, 21 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Every fixture is a synthetic byte buffer built
in-test by an independent fixture-side writer (no external data files).

1. pinned MPEG-1 Layer III 128 kbps/44100 header (all fields, padded+CRC
   variant, names, 26 ms frame duration);
2. frame-length formulas across MPEG-1 L1/L2/L3, MPEG-2 L3/L2 and
   MPEG-2.5 L3/L1 with padding and helper edge cases;
3. all five bitrate tables, indices 0..14, pinned in-test;
4. bitrate edges: free index, index 15, invalid version/layer, header
   rejection;
5. sample-rate tables for all three versions; reserved index rejection;
6. samples-per-frame table and version/layer/channel/emphasis names;
7. frame header errors: truncation at several offsets, bad sync, reserved
   version/layer;
8. `mp3_find_frame`: junk scan, bounds, free format, no-frame paths;
9. `mp3_scan` of 10 CBR frames: count, offsets/lengths, duration 261 ms;
10. scan stops: trailing junk, partial tail, truncated last frame,
    mismatched sample rate, truncated first frame, single frame;
11. VBR mix counting and explicit scan start offsets;
12. leading ID3v2 skipped by `mp3_scan`, trailing ID3v1 recognized,
    malformed ID3v2 propagates;
13. ID3v2 header fields for v2.3/v2.4, syncsafe size 256, full error
    catalog;
14. ID3v2.3 text frames TIT2/TPE1/TALB/TRCK/TYER/TCON: ids, sizes, texts,
    accessors, convenience readers;
15. ID3v2.4 syncsafe frame size 130, TDRC year, bad frame size, frame
    overrun, extended header rejection;
16. unsynchronisation de-escape (`FF 00` -> `FF`) with byte-exact text;
17. ID3v1.1 tail: fields, track byte, genre byte and genre names;
18. ID3v1.0 tail and the id3v1 error catalog;
19. malformed/truncated scan inputs and offset errors;
20. text details: NUL stop, unsupported encoding, non-text frames;
21. frame duration and scan duration floor arithmetic.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.mp3
```

Last verified: compiler 0.61.3,
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Structural parsing only: no audio decoding, CRC checking, or sample
  output.
- Free-format frames are rejected, never length-scanned.
- ID3v2: only major versions 3 and 4; extended headers rejected; only the
  whole-tag unsynchronisation flag is de-escaped (v2.4 per-frame
  unsynchronisation and data-length indicators are ignored); only text
  encodings 0 and 3 are decoded; text stops at the first NUL, so
  multi-value text frames keep only the first string; frame ids are
  reported as stored (nonstandard ids included).
- ID3v1 genre names cover 0..79 only; the 80..147 extension list and 255
  map to "".
- `duration_ms` assumes the samples-per-frame and sample rate of the first
  frame for the whole counted run (a stream that changes them stops the
  run as corruption); it is a structural estimate, not a decoded length.
- An ID3v1 tail tag terminates the scan cleanly but is not part of
  `frame_offsets`; `trailing_bytes` reports its 128 bytes.
- Not thread-safe; all values are plain value types.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_header`/`_err_header`/`_ok_scan`/`_err_scan`/`_ok_id3v2`/
  `_err_id3v2`/`_ok_frames`/`_err_frames`/`_ok_v1`/`_err_v1`/`_ok_int`/
  `_err_int`/`_ok_str`/`_err_str` (constructing Results directly in other
  functions miscompiles in this compiler).
- All byte reads go through `(data[pos] as Int) & 0xFF`; bit fields are
  extracted with division and modulo, never with shifts or `&` on signed
  values.
- `Str` values are built from file bytes only with `builder.sb_to_str`
  and only when no 0x00 can end up inside them: the result is a
  NUL-terminated C string, and a raw 0x00 would silently truncate it and
  trip the builder's `result.len() == sb.len()` contract at run time. Text
  and id helpers therefore stop at the first NUL.
- Structs use parallel `Vec` fields, never `Vec[StructType]`; every
  `frame_offsets` push mirrors a `frame_lengths` push.
- Str values read from `Vec[Str]` are only compared with
  `string.compare.str_compare`.
- Free functions only; no `extern "C"` blocks (no FFI), no methods, no
  lambdas, no `Vec[Float64]`.
