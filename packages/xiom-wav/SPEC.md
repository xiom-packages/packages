# xiom.wav -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.wav`, version `0.1.0`).
Module: `src/wav.xi` (`module xiom.wav`).
Depends on `xiom.std` (`xiom.string.builder`).

## Scope

A pure-XIOM (no FFI) builder and reader for canonical PCM (RIFF/WAVE) audio
files:

- `wav_build_pcm` emits the exact 44-byte canonical header plus the PCM
  payload;
- `wav_header_parse` validates a buffer and returns the `WavFormat`
  (channels, sample rate, bits per sample);
- `wav_pcm_data` copies the `data` chunk bytes;
- `wav_frame_count` / `wav_duration_ms` derive frame and time metadata;
- `wav_is_valid` reports structural validity;
- `wav_le_u32` is a bounds-checked unsigned little-endian read for tests
  and tools.

## Non-goals

- WAVE_FORMAT_EXTENSIBLE (`0xFFFE`), IEEE float (3), A-law/mu-law (6/7),
  ADPCM and every other non-PCM format.
- Non-canonical chunk orders, extra chunks (LIST/fact/cue/...), chunk
  padding rules and RIFF nesting.
- Sample conversion, resampling, normalization, interleaving helpers.
- Streaming over files/sockets; the API works on in-memory `Vec[UInt8]`.
- Payloads above 4 GiB (all sizes are 32-bit fields).

## Byte layout (canonical header, 44 bytes)

All multi-byte fields are little-endian. Offsets are decimal.

| Offset | Size | Field | Value / rule |
|---|---|---|---|
| 0 | 4 | ChunkID | ASCII `"RIFF"` (`52 49 46 46`). |
| 4 | 4 | ChunkSize | u32 = `36 + data_size`; must equal `len - 8`. |
| 8 | 4 | Format | ASCII `"WAVE"` (`57 41 56 45`). |
| 12 | 4 | Subchunk1ID | ASCII `"fmt "` (`66 6d 74 20`). |
| 16 | 4 | Subchunk1Size | u32 = 16. |
| 20 | 2 | AudioFormat | u16 = 1 (PCM). |
| 22 | 2 | NumChannels | u16; `wav_build_pcm` clamps to 1..65535. |
| 24 | 4 | SampleRate | u32 (Hz). |
| 28 | 4 | ByteRate | u32 = `SampleRate * NumChannels * BitsPerSample / 8`. |
| 32 | 2 | BlockAlign | u16 = `NumChannels * BitsPerSample / 8`. |
| 34 | 2 | BitsPerSample | u16; one of 8, 16, 24, 32. |
| 36 | 4 | Subchunk2ID | ASCII `"data"` (`64 61 74 61`). |
| 40 | 4 | Subchunk2Size | u32 = `data_size`; must satisfy `44 + data_size <= len`. |
| 44 | `data_size` | Payload | PCM bytes copied verbatim. |

Worked example -- 1 channel, 8000 Hz, 16-bit, empty payload (44 bytes):

```
52 49 46 46 24 00 00 00 57 41 56 45 66 6d 74 20
10 00 00 00 01 00 01 00 40 1f 00 00 80 3e 00 00
02 00 10 00 64 61 74 61 00 00 00 00
```

## API signatures

All functions are free functions in module `xiom.wav`:

```xi
pub type WavFormat = { channels: Int; sample_rate: Int; bits_per_sample: Int; }

pub fn wav_build_pcm(pcm: &Vec[UInt8], f: &WavFormat) -> Vec[UInt8]
pub fn wav_header_parse(data: &Vec[UInt8]) -> Result[WavFormat, Str]
pub fn wav_pcm_data(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn wav_frame_count(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn wav_duration_ms(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn wav_is_valid(data: &Vec[UInt8]) -> Bool
pub fn wav_le_u32(data: &Vec[UInt8], offset: Int) -> Result[Int, Str]
```

## Semantics

`wav_build_pcm(pcm, f)`
: Emits exactly `44 + pcm.len()` bytes. `f.channels` is clamped to
  1..65535 and `f.bits_per_sample` is clamped into {8, 16, 24, 32} by
  rounding **up** to the next width (0..8 -> 8, 9..16 -> 16, 17..24 -> 24,
  25..32 and above -> 32). The clamped values are recorded in the header
  and drive `byte_rate` and `block_align`. `f.sample_rate` is written as
  given (unsigned 32-bit field).

`wav_header_parse(data)`
: Validates in this order (first failure wins): `len >= 44`; `"RIFF"`;
  `"WAVE"`; `"fmt "` tag and `Subchunk1Size == 16`; `AudioFormat == 1`;
  `BitsPerSample in {8, 16, 24, 32}`; `ChunkSize == len - 8`; `"data"`
  tag; `44 + Subchunk2Size <= len`. Success returns the stored
  `channels`, `sample_rate` and `bits_per_sample`. A structural zero
  channel count or zero rate is **not** rejected here.

`wav_pcm_data(data)`
: Runs the same validation, then copies exactly `data_size` bytes from
  offset 44 into a fresh vector. Trailing bytes after the data chunk are
  ignored (never copied).

`wav_frame_count(data)`
: Runs the same validation, derives `block_align = channels * bits / 8`
  (the stored BlockAlign field is not trusted), and returns
  `data_size / block_align` (floor division). Err("wav: zero block align")
  when the derived align is 0 (0 channels).

`wav_duration_ms(data)`
: Runs the same validation; Err("wav: zero sample rate") when the stored
  rate is 0; Err("wav: zero block align") when the derived align is 0;
  otherwise `frames * 1000 / sample_rate` (floor division, whole
  milliseconds).

`wav_is_valid(data)`
: `true` iff the `wav_header_parse` validation succeeds.

`wav_le_u32(data, offset)`
: Returns byte0 + byte1*256 + byte2*65536 + byte3*16777216 (each byte
  0..255) as an `Int`. Err("wav: offset out of range") when `offset < 0`
  or `offset + 4 > len`.

## Error string catalog

| Condition | Error text |
|---|---|
| Buffer shorter than 44 bytes | `wav: truncated header` |
| Bytes 0..4 are not `"RIFF"` | `wav: bad RIFF magic` |
| Bytes 8..12 are not `"WAVE"` | `wav: bad WAVE magic` |
| Bytes 12..16 are not `"fmt "` or Subchunk1Size != 16 | `wav: bad fmt chunk` |
| AudioFormat != 1 | `wav: non-PCM format` |
| BitsPerSample not in {8,16,24,32} | `wav: invalid bits per sample` |
| ChunkSize != len - 8 | `wav: riff size mismatch` |
| Bytes 36..40 are not `"data"` | `wav: bad data chunk` |
| 44 + Subchunk2Size > len | `wav: data chunk out of range` |
| Derived block align is 0 (channels == 0) | `wav: zero block align` |
| Stored sample rate is 0 | `wav: zero sample rate` |
| `wav_le_u32` offset < 0 or offset + 4 > len | `wav: offset out of range` |

`wav_pcm_data`, `wav_frame_count` and `wav_duration_ms` propagate the
structural errors from the catalog above (their `Result` error is the
first validation failure).

## Complexity

| Operation | Complexity |
|---|---|
| `wav_build_pcm` | O(pcm.len()) |
| `wav_header_parse` / `wav_is_valid` | O(1) |
| `wav_pcm_data` | O(data_size) |
| `wav_frame_count` / `wav_duration_ms` | O(1) |
| `wav_le_u32` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module wav_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Coverage:

1. exact 44-byte header for 1ch/8000Hz/16-bit empty PCM (hand-written hex);
2. build -> parse round-trip, 8-bit mono;
3. build -> parse round-trip, 16-bit mono (plus the RIFF size field);
4. build -> parse round-trip, 24-bit stereo;
5. build -> parse round-trip, 32-bit stereo;
6. PCM payload preserved byte-for-byte (incl. bytes >= 128);
7. 1600-byte 16-bit 8kHz mono payload -> 800 frames, 100 ms;
8. byte_rate (176400 for 44.1k stereo 16-bit) and block_align fields;
9. channels and bits_per_sample clamping (0 / 7 / 12 / 33 / -5);
10. truncated header (0, 43, 10 bytes) is Err, incl. `wav_pcm_data`;
11. bad RIFF magic (bytes 0 and 3) is Err;
12. bad WAVE magic (bytes 8 and 11) is Err;
13. non-PCM format tags (3 and 0) are Err;
14. bits_per_sample 12 / 1 / 64 are Err;
15. fmt chunk size != 16 and bad `fmt ` tag are Err;
16. RIFF size field mismatch (100 and 0) is Err;
17. data chunk tag corruption and data size beyond the buffer are Err;
18. `wav_is_valid` true for a built file, false for empty/junk/corrupt/truncated;
19. `wav_le_u32` known bytes (8000, 2^32-1, 2^31) and out-of-range offsets;
20. zero block align (0 channels) and zero sample rate are Err;
21. empty PCM: 0 frames, 0 ms, empty data copy;
22. all four bit widths round-trip mono and stereo.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.wav
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Canonical 44-byte PCM layout only; WAVE_FORMAT_EXTENSIBLE and float
  formats are rejected with the documented errors.
- Other chunks and trailing bytes are ignored; the `data` chunk must be at
  offset 36.
- `wav_header_parse` accepts 0 channels / 0 sample rate structurally; the
  derived readers return the zero-division errors.
- The stored BlockAlign / ByteRate fields are not validated; derived
  metadata is recomputed from channels, rate and bits.
- All sizes are 32-bit; payloads above 4 GiB are not representable.
- No thread safety; plain value types only.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_int`/`_err_int`/`_ok_bytes`/`_err_bytes`/`_ok_fmt`/`_err_fmt`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- All little-endian byte extraction is arithmetic (modulo/division)
  because `& 0xFF` on operands with bit 31 set miscompiles (same bug
  documented in `xiom.msgpack` and `xiom.convert.base58`).
- Byte comparisons go through `data[pos] as Int` against small Int
  constants; UInt8 constants >= 128 are never used in comparisons.
- `str_compare` lives in `xiom.string.compare`, not in the `xiom.string`
  umbrella; the tests import both. Err strings are compared with
  `str_compare` (BUG 17: `==` between Str values read from a `Vec` lowers
  to a pointer compare).
- The module declares no `extern "C"` blocks (no FFI).
