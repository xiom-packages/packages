# xiom.aiff

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** AIFF/AIFF-C container header codec: FORM/COMM/SSND parsing and
> building, 80-bit extended sample rate, chunk index with raw spans.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`).
> No FFI, no sample decoding.

## What it is

`xiom.aiff` parses and builds the structural layer of AIFF and AIFF-C audio
containers: the big-endian FORM header (`AIFF` or `AIFC`), the mandatory COMM
chunk (channels, sample frames, sample size and the 80-bit IEEE extended
sample rate), the mandatory SSND chunk (offset, block size and the sample
byte span) and an index of every chunk in file order. Optional chunks --
NAME, AUTH, ANNO, `(c) `, MARK, INST, COMT, FVER and unknown ids -- are
preserved as raw spans; odd-sized chunks are padded to even lengths as the
format requires.

The sample rate is encoded and decoded with integer arithmetic only (no
`Vec[Float64]`): integer rates up to 2^31-1 round-trip exactly, non-integer
encoded rates decode to the nearest integer Hz with ties rounded up, and
`aiff.rate_exact` reports whether the stored value was exact. See SPEC.md for
the byte layout tables, the 80-bit bit-level rules and the full error
catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `aiff_build(samples, f)` | `Vec[UInt8]` | Complete AIFF/AIFC file: FORM + COMM + SSND (+ pad); clamps channels to 1..65535, frames/SSND fields to u32, sample size to 1..32. |
| `aiff_append_chunk(file, id, payload)` | `Result[Unit, Str]` | Appends one padded chunk and rewrites the FORM size field. |
| `aiff_parse(data)` | `Result[AiffInfo, Str]` | Full structural validation; returns the header plus the chunk index. |
| `aiff_is_valid(data)` | `Bool` | True when `aiff_parse` succeeds. |
| `aiff_encode_sample_rate(rate)` | `Vec[UInt8]` | 10 big-endian bytes of the 80-bit extended encoding; `rate <= 0` encodes as +0.0. |
| `aiff_decode_sample_rate(data, offset)` | `Result[Int, Str]` | Decodes 10 bytes to integer Hz (round half up); Err on Inf/NaN, negative and out-of-range values or offsets. |
| `aiff_chunk_count(info)` | `Int` | Number of indexed chunks. |
| `aiff_chunk_id(info, i)` | `Str` | 4-character id of chunk `i`; `""` when out of range. |
| `aiff_chunk_offset(info, i)` | `Int` | Absolute offset of chunk `i`'s id byte; `-1` when out of range. |
| `aiff_chunk_size(info, i)` | `Int` | Declared payload size of chunk `i` (pad excluded); `-1` when out of range. |
| `aiff_find_chunk(info, id)` | `Int` | Index of the first chunk with the given id; `-1` when absent. |
| `aiff_chunk_data(data, info, i)` | `Result[Vec[UInt8], Str]` | Copy of chunk `i`'s raw payload bytes. |
| `aiff_sample_data(data, info)` | `Result[Vec[UInt8], Str]` | Copy of the SSND sample bytes. |
| `aiff_duration_ms(info)` | `Result[Int, Str]` | `sample_frames * 1000 / sample_rate`, floor division. |

Types:

```xi
pub type AiffFormat = {
  aifc: Bool; channels: Int; sample_frames: Int; sample_size: Int;
  sample_rate: Int; compression_type: Str; compression_name: Str;
  ssnd_offset: Int; ssnd_block_size: Int;
}

pub type AiffInfo = {
  aifc: Bool; channels: Int; sample_frames: Int; sample_size: Int;
  sample_rate: Int; rate_exact: Bool;
  compression_type: Str; compression_name: Str;
  ssnd_offset: Int; ssnd_block_size: Int;
  ssnd_data_offset: Int; ssnd_data_size: Int;
  chunk_ids: Vec[Str]; chunk_offsets: Vec[Int]; chunk_sizes: Vec[Int];
}
```

Errors: `aiff: empty input`, `aiff: truncated form header`,
`aiff: bad FORM magic`, `aiff: bad form type`, `aiff: bad FORM size`,
`aiff: truncated chunk header`, `aiff: bad chunk id`,
`aiff: chunk size overrun`, `aiff: truncated chunk padding`,
`aiff: duplicate COMM`, `aiff: bad COMM size`, `aiff: zero channels`,
`aiff: bad sample size`, `aiff: bad sample rate`, `aiff: zero sample rate`,
`aiff: bad compression type`, `aiff: bad compression name`,
`aiff: SSND before COMM`, `aiff: duplicate SSND`, `aiff: short SSND`,
`aiff: missing COMM`, `aiff: missing SSND`,
`aiff: chunk index out of range`, `aiff: offset out of range`,
`aiff: not a FORM container` (see SPEC.md).

## Usage

```xi
use xiom.aiff;
use xiom.io;
use xiom.convert;

let f = AiffFormat{
  aifc: false;
  channels: 1;
  sample_frames: 8000;
  sample_size: 16;
  sample_rate: 8000;
  compression_type: "";
  compression_name: "";
  ssnd_offset: 0;
  ssnd_block_size: 0;
};

var pcm = Vec[UInt8].new();
pcm.push(0 as UInt8);
pcm.push(128 as UInt8);

var file = aiff_build(&pcm, &f);              // 56 bytes: 54 header + 2 samples
let pr = aiff_parse(&file);
if pr.is_ok {
  io.println("channels: " + convert.int_to_string(pr.value.channels));
  io.println("rate:     " + convert.int_to_string(pr.value.sample_rate));
  io.println("exact:    " + convert.bool_to_string(pr.value.rate_exact));
  let sd = aiff_sample_data(&file, &pr.value);
  io.println("samples:  " + convert.int_to_string(sd.value.len()));
}

// Optional chunk: "NAME" with the odd 3-byte payload "Ada".
var name = Vec[UInt8].new();
name.push(65 as UInt8);
name.push(100 as UInt8);
name.push(97 as UInt8);
let appended = aiff_append_chunk(&mut file, "NAME", &name);
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.aiff
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Header/container layer only**: sample bytes are copied verbatim, never
  decoded, converted or decompressed. AIFF-C compression types (`NONE`,
  `sowt`, `fl32`, ...) are passed through as strings; no codec is
  implemented.
- **No WAV/other-format conversion** and no resampling or normalization.
- **Printable chunk ids only**: chunk ids and AIFC compression types/names
  must be printable ASCII (0x20..0x7E); other bytes are rejected with
  `aiff: bad chunk id` / `aiff: bad compression type` /
  `aiff: bad compression name`. Binary payloads are unaffected.
- **Canonical structural rules**: the FORM size field must equal
  `len - 8`, COMM must precede SSND, and each of COMM and SSND may appear
  once. Optional chunk position is not otherwise enforced; all chunks are
  indexed where they appear.
- **Trailing bytes are rejected**: the chunk walk must consume the buffer
  exactly (no resync, no partial final chunk).
- The builder writes COMM immediately followed by SSND;
  `aiff_append_chunk` appends after them. `sample_frames` and the SSND
  block size are written as given, not derived.
- Decoded rates are limited to `0..2^31-1` Hz; the 80-bit encoder is exact
  for integer rates up to 2^31-1 and still emits correct bytes above that,
  but such rates are rejected on decode as out of range.
- Sizes are 32-bit fields; payloads above 4 GiB are out of scope.
- Not thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
