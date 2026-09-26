# xiom.mp3

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** MP3 structural parser: MPEG-1/2/2.5 audio frame headers,
> consecutive-frame scan with duration, ID3v2.3/2.4 text tags and ID3v1
> tail tags. No audio decoding.
> **Deps:** `xiom.std` only (`xiom.string.builder`, `xiom.string.compare`,
> `xiom.convert`; tests add `xiom.test`, `xiom.io`, `xiom.string`,
> `xiom.encoding.hex`).
> No FFI.

## What it is

`xiom.mp3` parses the structural layer of MPEG-1/2/2.5 audio data:

- **Frame headers** (`mp3_parse_frame_header`): the 11-bit sync, version
  (MPEG-1, MPEG-2, MPEG-2.5), layer (I/II/III), bitrate index with the
  full per-version/layer table, sample-rate index with the per-version
  table, padding, channel mode, mode extension, copyright/original/
  emphasis, CRC flag, and the computed frame length and samples per frame.
- **Buffer scan** (`mp3_find_frame`, `mp3_scan`, `mp3_scan_from`): find
  the first valid frame, count consecutive complete frames, derive total
  samples and duration in whole milliseconds, and detect free-format
  frames and trailing corruption. A leading ID3v2 tag is skipped and a
  trailing ID3v1 tag ends the scan cleanly.
- **ID3v2.3/2.4** (`mp3_id3v2_header`, `mp3_id3v2_frames`): the 10-byte
  header (version, revision, flags, syncsafe size), every frame's id and
  stored size, text frames (TIT2/TPE1/TALB/TRCK/TYER/TDRC/TCON and any
  other `T...` frame) with latin1/UTF-8 encoding bytes, and whole-tag
  unsynchronisation de-escaping. Convenience readers: `mp3_id3v2_title`,
  `_artist`, `_album`, `_track`, `_year`, `_genre`.
- **ID3v1** (`mp3_id3v1`, `mp3_has_id3v1`, `mp3_id3v1_genre_name`): the
  128-byte tail tag with the ID3v1.1 track byte and the original genre
  names 0..79.

Frame durations are reported as integer milliseconds (no `Float64`
anywhere): `mp3_frame_duration_ms` and the scan's `duration_ms` use floor
division of `samples * 1000 / sample_rate`. See SPEC.md for the bit-level
layout tables, formulas, validation order and the complete error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `mp3_parse_frame_header(data, offset)` | `Result[Mp3FrameHeader, Str]` | Decode and validate the 4-byte header at `offset`. |
| `mp3_frame_length(version, layer, kbps, rate, pad)` | `Int` | Frame size formula; 0 when not computable. |
| `mp3_frame_duration_ms(header)` | `Int` | `samples_per_frame * 1000 / sample_rate` (floor). |
| `mp3_bitrate_kbps(version, layer, index)` | `Int` | Table lookup; 0 free, -1 bad. |
| `mp3_sample_rate(version, index)` | `Int` | Table lookup; 0 reserved/unknown. |
| `mp3_samples_per_frame(version, layer)` | `Int` | 384 / 1152 / 576; 0 unknown. |
| `mp3_version_name(version)` | `Str` | `"MPEG-1"`, `"MPEG-2"`, `"MPEG-2.5"` or `""`. |
| `mp3_layer_name(layer)` | `Str` | `"Layer I"` ... or `""`. |
| `mp3_channel_mode_name(mode)` | `Str` | `"stereo"`, `"joint stereo"`, `"dual channel"`, `"mono"`. |
| `mp3_emphasis_name(emphasis)` | `Str` | Name or `""`. |
| `mp3_find_frame(data, start)` | `Result[Int, Str]` | Offset of the first valid frame; free format and no-frame are errors. |
| `mp3_scan(data)` | `Result[Mp3Scan, Str]` | Skip a leading ID3v2 tag, then scan consecutive frames. |
| `mp3_scan_from(data, start)` | `Result[Mp3Scan, Str]` | Same, from an explicit offset. |
| `mp3_id3v2_header(data)` | `Result[Mp3Id3v2Info, Str]` | 10-byte ID3v2.3/2.4 header with decoded flags. |
| `mp3_id3v2_frames(data)` | `Result[Mp3Id3v2Frames, Str]` | Frame walk: ids, sizes, texts. |
| `mp3_id3v2_frame_count(frames)` | `Int` | Number of recorded frames. |
| `mp3_id3v2_frame_id(frames, i)` | `Str` | Frame id or `""`. |
| `mp3_id3v2_frame_size(frames, i)` | `Int` | Stored size or `-1`. |
| `mp3_id3v2_frame_text(frames, i)` | `Str` | Decoded text or `""`. |
| `mp3_id3v2_find(frames, id)` | `Int` | Index of the first frame with `id`, or `-1`. |
| `mp3_id3v2_text(frames, id)` | `Str` | Text of the first frame with `id`, or `""`. |
| `mp3_id3v2_title/artist/album/track/year/genre(data)` | `Result[Str, Str]` | Convenience readers (year: TYER then TDRC). |
| `mp3_has_id3v1(data)` | `Bool` | True when `TAG` sits 128 bytes from the end. |
| `mp3_id3v1(data)` | `Result[Mp3Id3v1, Str]` | Parse the 128-byte tail tag. |
| `mp3_id3v1_genre_name(genre)` | `Str` | Winamp genre 0..79 or `""`. |

Types:

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
```

Version is 1, 2 or 25 (MPEG-2.5); layer is 1, 2 or 3. Errors carry byte
offsets, e.g. `mp3: bad sync at 1234`, `mp3: free format at 57`,
`mp3: id3v2 frame overrun at 42`, `mp3: no id3v1 tag at 8128`
(see SPEC.md).

## Usage

```xi
use xiom.mp3;
use xiom.io;
use xiom.convert;

// ... data: Vec[UInt8] holding an MP3 file ...

let sr = mp3_scan(&data);
if sr.is_ok {
  let s = sr.value;
  io.println("frames:   " + convert.int_to_string(s.frame_count));
  io.println("codec:    " + mp3_version_name(s.version) + " " + mp3_layer_name(s.layer));
  io.println("bitrate:  " + convert.int_to_string(s.bitrate_kbps) + " kbps");
  io.println("rate:     " + convert.int_to_string(s.sample_rate) + " Hz");
  io.println("duration: " + convert.int_to_string(s.duration_ms) + " ms");
  if s.corrupted { io.println("warning: trailing bytes are not frames"); }
}

let title = mp3_id3v2_title(&data);
if title.is_ok { io.println("title:  " + title.value); }

let v1 = mp3_id3v1(&data);
if v1.is_ok {
  io.println("artist: " + v1.value.artist);
  io.println("genre:  " + mp3_id3v1_genre_name(v1.value.genre));
}

// One frame header, straight from the bytes.
let h = mp3_parse_frame_header(&data, 0);
if h.is_ok {
  io.println("frame bytes: " + convert.int_to_string(h.value.frame_length));
  io.println("samples:     " + convert.int_to_string(h.value.samples_per_frame));
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.mp3
```

Expected: the section-4 namespace check passes, 21 `[PASS]` lines, and a
final `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No audio decoding**: only structure is parsed. There is no Huffman
  decoding, requantisation, synthesis filterbank, bit-reservoir handling
  or CRC verification, and no side-info/granule inspection beyond the
  frame header.
- **Free format rejected**: a frame whose bitrate index is 0 has no
  length in its header; `mp3_parse_frame_header`, `mp3_find_frame` and
  the scan report `mp3: free format at N` instead of guessing.
- **ID3v2.3/2.4 only**: v2.2 (3-character ids) and other majors are
  rejected; extended headers are rejected; only the whole-tag
  unsynchronisation flag is de-escaped (v2.4 per-frame unsynchronisation
  and data-length indicators are ignored).
- **Text frames**: only encodings 0 (latin1) and 3 (UTF-8) are decoded;
  text stops at the first NUL, so multi-value frames keep only the first
  string. Frame ids are reported as stored.
- **ID3v1 genre names** cover the original 0..79 set; 80..147 and 255
  return `""`.
- **Duration is structural**: it assumes the first frame's sample rate
  and samples per frame for the whole counted run (a change stops the
  scan as corruption) and is not a decoded sample count.
- **In-memory buffers only**: no streaming, no file I/O.
- Not thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
