# xiom.flac

> **Status:** `incubating` -- implemented and green on the local harness
> (compiler v0.61.3, 18/18 conformance checks), NOT yet published to the
> XIOM registry.
> **Scope:** FLAC structural parser: the "fLaC" stream marker, every
> metadata block type (STREAMINFO, PADDING, APPLICATION, SEEKTABLE,
> VORBIS_COMMENT, CUESHEET, PICTURE) and the audio frame header (sync,
> block/sample-rate codes with their extra bytes, channel assignment,
> sample size, UTF-8 coded frame/sample number, CRC-8). No audio decoding.
> **Deps:** `xiom.std` only (`xiom.string.builder`, `xiom.convert`,
> `xiom.encoding.hex`; tests add `xiom.test`, `xiom.io`, `xiom.string`,
> `xiom.string.compare`).
> No FFI.

## What it is

`xiom.flac` parses the structural layer of native FLAC streams:

- **Metadata walk** (`flac_parse_metadata`): validates the 4-byte "fLaC"
  marker, then walks the metadata block chain -- 4-byte header (last-block
  flag, 7-bit type, 24-bit big-endian length) plus payload -- until the
  last-block flag. Types 7..126 are rejected as invalid and 127 as
  forbidden; truncation, overrun and out-of-order STREAMINFO are rejected
  with byte offsets. The result carries the block index (offset, type,
  length per block), the offset where audio frames begin, and every parsed
  payload.
- **STREAMINFO** (`flac_parse_streaminfo` on the 34-byte payload, or via
  the flattened fields of `flac_parse_metadata`): 16-bit min/max block
  size, 24-bit min/max frame size, 20-bit sample rate, 3-bit channels-1,
  5-bit bits-per-sample-1, 36-bit total samples and the 16-byte MD5 as
  32 lowercase hex characters.
- **PADDING / APPLICATION**: total padding bytes; each application block's
  4-byte id and data length.
- **SEEKTABLE**: every 18-byte entry decomposed into sample number, byte
  offset and target-frame sample count; 64-bit placeholders
  (`0xFFFFFFFFFFFFFFFF`) are reported as `Int` max.
- **VORBIS_COMMENT** (`flac_parse_vorbis_comment` standalone, or merged
  into the metadata result): little-endian vendor length + vendor,
  comment count + per-comment length and text. Strings are truncated at
  the first 0x00; other bytes pass through unchanged (UTF-8 is not
  validated).
- **CUESHEET**: opaque but length-checked -- the 396-byte fixed part and
  the track/index walk must consume the payload exactly; the track count
  and payload length are exposed.
- **PICTURE** (`flac_parse_picture` standalone, or as an index-aligned
  summary in the metadata result): type, MIME, description, width,
  height, colour depth, indexed-colour count and data length. Picture
  data itself is not copied or inspected.
- **Frame headers** (`flac_parse_frame_header`): the 14-bit sync
  (0x3FFE), reserved bit, blocking strategy, block-size code (with the
  optional 8/16-bit extra field), sample-rate code (with the optional
  8/16-bit extra field), channel assignment (independent 0..7,
  left/side 8, right/side 9, mid/side 10), sample-size code, UTF-8 coded
  frame/sample number (1..7 bytes, continuation bytes validated, overlong
  forms rejected) and the CRC-8 byte. A CRC mismatch is reported through
  `crc8_ok`, not treated as a hard error.
- **Helpers**: `flac_utf8_size`, `flac_parse_utf8_number`, `flac_crc8`
  (polynomial 0x07, initial 0, MSB-first) and the table/name functions
  `flac_block_size_for_code`, `flac_sample_rate_for_code`,
  `flac_bits_per_sample_for_code`, `flac_channel_assignment_channels`,
  `flac_channel_assignment_name`, `flac_metadata_type_name`,
  `flac_blocking_strategy_name`.

Everything is integer arithmetic -- no `Float64` anywhere. `sample_rate`
and `bits_per_sample` of a frame header are 0 when the code says "from
STREAMINFO"; take those from the metadata result. See SPEC.md for the
bit-level layout tables, the validation order and the complete error
catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `flac_parse_metadata(data)` | `Result[FlacMetadata, Str]` | Marker + full metadata block walk; flattened payloads. |
| `flac_audio_offset(m)` | `Int` | Offset where audio frames begin. |
| `flac_metadata_size(m)` | `Int` | Total metadata size (marker included). |
| `flac_block_count(m)` | `Int` | Number of metadata blocks. |
| `flac_block_offset/type/length(m, i)` | `Int` | Per-block index (`-1` when out of range). |
| `flac_padding_bytes(m)` | `Int` | Total PADDING payload. |
| `flac_application_count(m)` | `Int` | Number of APPLICATION blocks. |
| `flac_application_id/data_length(m, i)` | `Str`/`Int` | Id (NUL-truncated) and data length. |
| `flac_seek_count(m)` | `Int` | Number of SEEKTABLE entries. |
| `flac_seek_sample/offset/frame_samples(m, i)` | `Int` | Entry fields; 64-bit values clamped to `Int` max. |
| `flac_vendor(m)` | `Str` | Vendor of the last VORBIS_COMMENT block parsed. |
| `flac_comment_count(m)` | `Int` | Comments across all VORBIS_COMMENT blocks. |
| `flac_comment(m, i)` | `Str` | Comment `i`, or `""`. |
| `flac_cuesheet_count(m)` | `Int` | Number of CUESHEET blocks. |
| `flac_cuesheet_track_count/length(m, i)` | `Int` | Declared tracks and payload length. |
| `flac_picture_count(m)` | `Int` | Number of PICTURE blocks. |
| `flac_picture_type/mime/description/width/height/depth/colors/data_length(m, i)` | `Int`/`Str` | Picture summary fields (`-1`/`""` when out of range). |
| `flac_parse_streaminfo(block)` | `Result[FlacStreamInfo, Str]` | Parse a 34-byte STREAMINFO payload. |
| `flac_parse_vorbis_comment(payload)` | `Result[FlacVorbisComment, Str]` | Parse one VORBIS_COMMENT payload. |
| `flac_parse_picture(payload)` | `Result[FlacPicture, Str]` | Parse one PICTURE payload. |
| `flac_parse_frame_header(data, offset)` | `Result[FlacFrameHeader, Str]` | Decode and validate one frame header. |
| `flac_utf8_size(first)` | `Int` | Lead-byte length 1..7, or `-1`. |
| `flac_parse_utf8_number(data, offset)` | `Result[Int, Str]` | Decode a UTF-8 coded number. |
| `flac_crc8(data, start, size)` | `Int` | CRC-8 (poly 0x07); `-1` when the range is invalid. |
| `flac_block_size_for_code(code)` | `Int` | `0` reserved, `-1` extra field follows, else the size. |
| `flac_sample_rate_for_code(code)` | `Int` | `0` from STREAMINFO, `-1` extra follows, `-2` invalid. |
| `flac_bits_per_sample_for_code(code)` | `Int` | `0` from STREAMINFO, `-1` reserved. |
| `flac_channel_assignment_channels/name(a)` | `Int`/`Str` | Derived channel count / assignment name. |
| `flac_metadata_type_name(t)` | `Str` | `"STREAMINFO"` ... `"PICTURE"`, else `""`. |
| `flac_blocking_strategy_name(s)` | `Str` | `"fixed"`, `"variable"`, else `""`. |

Types:

```xi
pub type FlacStreamInfo = {
  min_block_size: Int; max_block_size: Int; min_frame_size: Int;
  max_frame_size: Int; sample_rate: Int; channels: Int;
  bits_per_sample: Int; total_samples: Int; md5_hex: Str;
}

pub type FlacVorbisComment = { vendor: Str; comments: Vec[Str]; }

pub type FlacPicture = {
  picture_type: Int; mime: Str; description: Str; width: Int;
  height: Int; depth: Int; colors: Int; data_length: Int;
}

pub type FlacFrameHeader = {
  blocking_strategy: Int; block_size_code: Int; sample_rate_code: Int;
  channel_assignment: Int; sample_size_code: Int; channels: Int;
  block_size: Int; sample_rate: Int; bits_per_sample: Int;
  number: Int; number_bytes: Int; crc8: Int; crc8_ok: Bool;
  header_size: Int;
}

pub type FlacMetadata = {
  metadata_size: Int; audio_offset: Int; has_streaminfo: Bool;
  min_block_size: Int; max_block_size: Int; min_frame_size: Int;
  max_frame_size: Int; sample_rate: Int; channels: Int;
  bits_per_sample: Int; total_samples: Int; md5_hex: Str;
  block_offsets: Vec[Int]; block_types: Vec[Int]; block_lengths: Vec[Int];
  padding_bytes: Int;
  app_ids: Vec[Str]; app_data_lengths: Vec[Int];
  seek_samples: Vec[Int]; seek_offsets: Vec[Int]; seek_frame_samples: Vec[Int];
  vendor: Str; comments: Vec[Str];
  cue_track_counts: Vec[Int]; cue_lengths: Vec[Int];
  picture_types: Vec[Int]; picture_mimes: Vec[Str];
  picture_descriptions: Vec[Str]; picture_widths: Vec[Int];
  picture_heights: Vec[Int]; picture_depths: Vec[Int];
  picture_colors: Vec[Int]; picture_data_lengths: Vec[Int];
}
```

Errors carry byte offsets: the block header offset for per-block structural
errors, the frame offset for frame-header errors, and precise byte offsets
for UTF-8 number errors -- e.g. `flac: bad stream marker at 0`,
`flac: invalid block type at 42`, `flac: vorbis comment overrun at 92`,
`flac: truncated frame header at 4110`, `flac: invalid utf8 number at 4115`
(see SPEC.md for the full catalog).

## Usage

```xi
use xiom.flac;
use xiom.io;
use xiom.convert;

// ... data: Vec[UInt8] holding a FLAC file ...

let mr = flac_parse_metadata(&data);
if mr.is_ok {
  let m = mr.value;
  io.println("blocks:   " + convert.int_to_string(flac_block_count(&m)));
  io.println("rate:     " + convert.int_to_string(m.sample_rate) + " Hz");
  io.println("channels: " + convert.int_to_string(m.channels));
  io.println("bits:     " + convert.int_to_string(m.bits_per_sample));
  io.println("samples:  " + convert.int_to_string(m.total_samples));
  io.println("md5:      " + m.md5_hex);
  io.println("audio at: " + convert.int_to_string(m.audio_offset));

  var i = 0;
  while i < flac_comment_count(&m) {
    io.println("comment:  " + flac_comment(&m, i));
    i = i + 1;
  }
  if flac_picture_count(&m) > 0 {
    io.println("cover:    " + flac_picture_mime(&m, 0) + " " +
      convert.int_to_string(flac_picture_width(&m, 0)) + "x" +
      convert.int_to_string(flac_picture_height(&m, 0)));
  }

  // First audio frame header sits at the audio offset.
  let fr = flac_parse_frame_header(&data, m.audio_offset);
  if fr.is_ok {
    let h = fr.value;
    io.println("frame:    block=" + convert.int_to_string(h.block_size) +
      " number=" + convert.int_to_string(h.number));
    io.println("stereo:   " + flac_channel_assignment_name(h.channel_assignment));
    if !h.crc8_ok {
      io.println("warning:  frame header CRC-8 mismatch");
    }
  }
} else {
  io.println("flac: " + mr.error);
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.flac
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No audio decoding**: only structure is parsed. There is no subframe
  decoding, no residual (Rice) decoding, no predictor reconstruction, no
  stereo decorrelation and no frame-footer CRC-16 verification; the
  compressed frame body is never inspected.
- **Frame headers only**: `flac_parse_frame_header` reads one header at
  `offset`; it does not locate frames or walk them through a stream.
- **CRC-8 is reported, not enforced**: a mismatching header CRC sets
  `crc8_ok = false` and the header is still returned (useful for damaged
  streams); it is not an error.
- **STREAMINFO is mandatory and must be first**: streams without it, with
  a duplicate or with a payload length other than 34 bytes are rejected.
- **CUESHEET is opaque**: the track/index walk is length-checked exactly,
  but the media catalog number, lead-in, track offsets, ISRCs, flags and
  index points are not exposed.
- **PICTURE data is not exposed**: only the declared data length; the
  bytes stay in the source buffer.
- **Strings are byte strings**: comment/description/MIME/vendor bytes are
  copied verbatim up to the first 0x00; UTF-8 validity, NUL-free storage
  and multi-value disambiguation are the caller's concern.
- **No semantic validation of STREAMINFO**: zero sample rates, min block
  sizes below 16 or inconsistent min/max fields are reported as stored.
- **In-memory buffers only**: no streaming, no file I/O, no encoder.
- **Whole-metadata model**: metadata is parsed into arrays; very large
  SEEKTABLEs/PICTURE descriptions allocate proportionally.
- Not thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
