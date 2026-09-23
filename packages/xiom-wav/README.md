# xiom.wav

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** canonical PCM WAV (RIFF) header parsing, building and metadata.
> **Deps:** `xiom.std` only (`xiom.string.builder`; tests add `xiom.test`,
> `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`). No FFI.

## What it is

`xiom.wav` builds and reads the canonical 44-byte PCM (audio format 1) WAV
header plus the raw `data` chunk. `wav_build_pcm` emits the exact byte
layout from a `WavFormat` and a PCM payload; `wav_header_parse` validates a
buffer and returns the format; `wav_pcm_data`, `wav_frame_count` and
`wav_duration_ms` expose the payload and derived metadata with
`Result`-based errors. All multi-byte fields are little-endian and are
written and read arithmetically (no FFI, no bit tricks). See SPEC.md for
the byte-level layout, validation rules and the full error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `wav_build_pcm(pcm, f)` | `Vec[UInt8]` | 44-byte canonical header + payload verbatim; channels clamped to 1..65535, bits clamped to {8,16,24,32}. |
| `wav_header_parse(data)` | `Result[WavFormat, Str]` | Validates RIFF/WAVE, the 16-byte `fmt ` PCM chunk, bits, RIFF size and data bounds; returns the format. |
| `wav_pcm_data(data)` | `Result[Vec[UInt8], Str]` | Copy of the `data` chunk bytes. |
| `wav_frame_count(data)` | `Result[Int, Str]` | `data_size / block_align`; block_align is derived as `channels * bits / 8`. |
| `wav_duration_ms(data)` | `Result[Int, Str]` | `frames * 1000 / sample_rate`, floor division. |
| `wav_is_valid(data)` | `Bool` | True when `wav_header_parse` succeeds. |
| `wav_le_u32(data, offset)` | `Result[Int, Str]` | Unsigned little-endian 32-bit read; Err on out-of-range offsets. |

`WavFormat = { channels: Int; sample_rate: Int; bits_per_sample: Int; }`.

Errors: `Err("wav: truncated header")`, `Err("wav: bad RIFF magic")`,
`Err("wav: bad WAVE magic")`, `Err("wav: bad fmt chunk")`,
`Err("wav: non-PCM format")`, `Err("wav: invalid bits per sample")`,
`Err("wav: riff size mismatch")`, `Err("wav: bad data chunk")`,
`Err("wav: data chunk out of range")`, `Err("wav: zero block align")`,
`Err("wav: zero sample rate")`, `Err("wav: offset out of range")`
(see SPEC.md).

## Usage

```xi
use xiom.wav;
use xiom.io;
use xiom.convert;

let f = WavFormat{ channels: 1; sample_rate: 8000; bits_per_sample: 16 };
var pcm = Vec[UInt8].new();
pcm.push(0 as UInt8);
pcm.push(128 as UInt8);

let file = wav_build_pcm(&pcm, &f);            // 46 bytes: 44 header + 2 payload
match wav_header_parse(&file) {
  Ok(fmt) => {
    io.println("channels: " + convert.int_to_string(fmt.channels));
    io.println("rate:     " + convert.int_to_string(fmt.sample_rate));
  },
  Err(e) => { io.println("error: " + e); },
}
io.println("ms: " + convert.int_to_string(wav_duration_ms(&file).value)); // 0
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.wav
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Canonical PCM layout only**: the `fmt ` chunk must be exactly 16 bytes
  with audio format 1 at offset 12 and the `data` chunk must start at
  offset 36. WAVE_FORMAT_EXTENSIBLE, float/ADPCM/mu-law formats and
  non-canonical chunk orders are rejected.
- **No other chunks**: LIST/fact/cue/etc. are neither parsed nor emitted;
  bytes after the `data` chunk are ignored by the readers.
- **No sample conversion, resampling or float support.**
- `wav_header_parse` accepts a structurally valid header with 0 channels or
  a 0 sample rate; `wav_frame_count` / `wav_duration_ms` report
  `wav: zero block align` / `wav: zero sample rate` for those.
- Multi-byte sizes are 32-bit fields; payloads above 4 GiB are out of
  scope.
- Not thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
