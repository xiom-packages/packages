# xiom.au

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** Sun/NeXT AU (`.snd`) audio header codec: big-endian 24-byte
> header, optional info field, audio span with the unknown-size sentinel.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`).
> No FFI, no sample decoding.

## What it is

`xiom.au` parses and builds the structural layer of Sun/NeXT AU audio files:
the big-endian magic `.snd`, the absolute data offset (>= 24), the data size
(with the `0xFFFFFFFF` "unknown, runs to end of buffer" sentinel), the
encoding id, the sample rate and the channel count. Every byte between
offset 24 and the data offset is the optional info/annotation field, which is
preserved raw and exposed as text only when it is printable ASCII.

The encoding table covers `1` mu-law 8-bit, `2` linear 8-bit, `3` linear
16-bit, `4` linear 24-bit, `5` linear 32-bit, `6` float 32-bit and `7`
double 64-bit (both raw IEEE-754 pass-through) and `27` A-law 8-bit. Audio
bytes are opaque: no mu-law/A-law arithmetic and no sample conversion is
performed. See SPEC.md for the byte layout, the data-size policy and the
full error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `au_build(samples, f, info)` | `Vec[UInt8]` | Canonical file: 24-byte header, info bytes, samples; `data_size = samples.len()`, `data_offset = 24 + info.len()`. |
| `au_build_unknown_size(samples, f, info)` | `Vec[UInt8]` | Same, with the `0xFFFFFFFF` unknown-size sentinel. |
| `au_parse(data)` | `Result[AuInfo, Str]` | Full structural validation; returns the header plus the resolved audio span. |
| `au_is_valid(data)` | `Bool` | True when `au_parse` succeeds. |
| `au_encoding_name(encoding)` | `Str` | Name from the table; `""` for unknown ids. |
| `au_encoding_bits(encoding)` | `Int` | Bits per sample; `0` for unknown ids. |
| `au_encoding_bytes(encoding)` | `Int` | Bytes per sample (`ceil(bits / 8)`); `0` for unknown ids. |
| `au_info_bytes(info)` | `Vec[UInt8]` | Raw copy of the info field. |
| `au_info_text(info)` | `Result[Str, Str]` | Info as text when every byte is printable ASCII; Err otherwise. |
| `au_data_offset(info)` | `Int` | Absolute offset of the first audio byte. |
| `au_data_size(info)` | `Int` | Resolved span length. |
| `au_size_known(info)` | `Bool` | False when the size field was the sentinel. |
| `au_stored_size(info)` | `Int` | Raw data-size field (`0xFFFFFFFF` when unknown). |
| `au_channels(info)` | `Int` | Channel count. |
| `au_sample_rate(info)` | `Int` | Sample rate in Hz. |
| `au_audio_data(data, info)` | `Result[Vec[UInt8], Str]` | Copy of the audio span. |
| `au_frame_count(info)` | `Result[Int, Str]` | `data_size / (channels * bytes_per_sample)`, floor division. |
| `au_duration_ms(info)` | `Result[Int, Str]` | `frames * 1000 / sample_rate`, floor division. |

Types:

```xi
pub type AuFormat = { encoding: Int; sample_rate: Int; channels: Int; }

pub type AuInfo = {
  encoding: Int; sample_rate: Int; channels: Int;
  size_known: Bool; stored_size: Int;
  data_offset: Int; data_size: Int; info_bytes: Vec[UInt8];
}
```

Errors: `au: empty input`, `au: truncated header`, `au: bad magic`,
`au: bad data offset`, `au: data offset past end`, `au: unknown encoding`,
`au: zero channels`, `au: zero sample rate`, `au: data size overrun`,
`au: bad info text` (see SPEC.md).

## Usage

```xi
use xiom.au;
use xiom.io;
use xiom.convert;

let f = AuFormat{ encoding: 1; sample_rate: 8000; channels: 1 };

var pcm = Vec[UInt8].new();
pcm.push(0 as UInt8);
pcm.push(128 as UInt8);

let file = au_build(&pcm, &f, "created by xiom.au");   // 24 + 18 + 2 bytes
let pr = au_parse(&file);
if pr.is_ok {
  let info = pr.value;
  io.println("offset:   " + convert.int_to_string(au_data_offset(&info)));
  io.println("size:     " + convert.int_to_string(au_data_size(&info)));
  io.println("encoding: " + au_encoding_name(info.encoding));
  io.println("rate:     " + convert.int_to_string(au_sample_rate(&info)));
  let text = au_info_text(&info);
  if text.is_ok { io.println("info:     " + text.value); }
}

// Unknown data size: the span resolves to the rest of the buffer.
let draft = au_build_unknown_size(&pcm, &f, "");
let p2 = au_parse(&draft);
if p2.is_ok { io.println("draft bytes: " + convert.int_to_string(au_data_size(&p2.value))); }
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.au
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Header layer only**: audio bytes are copied verbatim, never decoded.
  There is no mu-law or A-law expansion, no linear/float conversion, no
  resampling and no conversion to other formats.
- **Encodings 1..7 and 27 only**: the G.72x ADPCM ids 23..26 and every
  other id are rejected with `au: unknown encoding`.
- **Info field**: written verbatim by the builder (no implicit NUL
  terminator); `au_info_text` rejects every byte outside 0x20..0x7E, so
  canonically NUL-terminated annotations are preserved raw but cannot be
  converted to text.
- **Data-size policy**: the `0xFFFFFFFF` sentinel means "rest of buffer"; a
  declared size larger than the remaining bytes is rejected; a smaller
  declared size is accepted and trailing bytes are ignored.
- **32-bit sizes**: the data offset and data size fields cannot represent
  files of 4 GiB or more.
- `sample_rate` and `channels` are u32 on the wire; the builder clamps
  channels to >= 1 and the parser rejects zero values.
- Not thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
