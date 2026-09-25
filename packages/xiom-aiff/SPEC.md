# xiom.aiff -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.aiff`, version `0.1.0`).
Module: `src/aiff.xi` (`module xiom.aiff`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`).
No FFI: the module declares no `extern "C"` blocks.

## Scope

A pure-XIOM (no FFI) AIFF/AIFF-C container header codec:

- `aiff_parse` validates a buffer and returns an `AiffInfo` header plus an
  index of every chunk in file order;
- `aiff_build` emits a complete FORM + COMM + SSND file for AIFF or AIFC;
- `aiff_append_chunk` appends optional/unknown chunks and maintains the FORM
  size field;
- `aiff_encode_sample_rate` / `aiff_decode_sample_rate` implement the 80-bit
  IEEE 754 extended sample-rate field with integer arithmetic;
- `aiff_chunk_count` / `aiff_chunk_id` / `aiff_chunk_offset` /
  `aiff_chunk_size` / `aiff_find_chunk` / `aiff_chunk_data` expose the chunk
  index and raw chunk spans;
- `aiff_sample_data` copies the SSND sample bytes;
- `aiff_is_valid` / `aiff_duration_ms` are convenience readers.

## Non-goals

- Sample data decoding, format conversion, PCM normalization, resampling or
  interleaving. Sample bytes are opaque; the sample size / rate fields are
  metadata only.
- AIFF-C compression codecs (`sowt`, `fl32`, `ACE2`, ...): the compression
  type/name are validated for structure and passed through as strings, but no
  decompression is performed.
- Conversion to/from WAV or any other container.
- Marker/instrument semantics: MARK and INST chunks are indexed as raw spans,
  their internal structures (loop points, MIDI notes) are not parsed.
- Streaming over files/sockets; the API works on in-memory `Vec[UInt8]`.
- Payloads above 4 GiB (all sizes are 32-bit fields).

## Byte layout

All multi-byte fields are BIG-endian (AIFF is a Macintosh/IRCAM format).
Offsets are decimal.

### FORM header (12 bytes)

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | FormID | ASCII `"FORM"` (`46 4f 52 4d`). |
| 4 | 4 | FormSize | u32; must equal `data.len() - 8` exactly. |
| 8 | 4 | FormType | ASCII `"AIFF"` (`41 49 46 46`) or `"AIFC"` (`41 49 46 43`). |
| 12 | ... | Chunks | Chunk framing below, walked to the end of the buffer. |

### Chunk framing and padding

Each chunk is `4` id bytes, a `u32` payload size, the payload, then one zero
pad byte when the payload size is odd (chunks start on even offsets). The
declared size excludes the pad byte. Unknown chunk ids are accepted as long
as every byte is printable ASCII (0x20..0x7E); they are indexed but never
interpreted. The walk must consume the buffer exactly: 1..7 leftover bytes,
or an overrun, are errors.

### COMM chunk (AIFF: 18 bytes; AIFC: 24+ bytes)

Payload offsets (`pos` is the absolute chunk start, so the payload begins at
`pos + 8`):

| Payload offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 2 | numChannels | u16; must be >= 1. |
| 2 | 4 | numSampleFrames | u32. |
| 6 | 2 | sampleSize | u16; must be 1..32. |
| 8 | 10 | sampleRate | 80-bit extended (below). |
| 18 | 4 | compressionType | AIFC only; 4 printable ASCII bytes. |
| 22 | 1 | compressionName length | AIFC only; 1..255. |
| 23 | length | compressionName | AIFC only; printable ASCII. |
| 23+length | 0 or 1 | pad | AIFC only; present when `1 + length` is odd. |

AIFF COMM payloads must be >= 18 bytes, AIFC payloads >= 24 bytes (18 + 4 +
minimum even-length Pascal string); larger payloads are accepted and any
trailing bytes after the Pascal string are ignored. `aiff_parse` synthesizes
`compression_type = "NONE"` and `compression_name = ""` for AIFF.
`aiff_build` writes exactly 18 bytes for AIFF and `18 + 4 + even(1 + len)`
bytes for AIFC (empty name -> `"not compressed"`, type padded/truncated to
4 bytes).

### SSND chunk

| Payload offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | offset | u32; must satisfy `offset <= size - 8` (also `size >= 8`). |
| 4 | 4 | blockSize | u32; passed through, not interpreted. |
| 8 | offset | alignment bytes | Not interpreted (written as zeros by `aiff_build`). |
| 8 + offset | size - 8 - offset | sample data | Copied verbatim by `aiff_sample_data`. |

For a chunk at absolute position `pos`, `ssnd_data_offset = pos + 16 +
offset` and `ssnd_data_size = size - 8 - offset` (the `+16` is the 8-byte
chunk header plus the 8-byte offset/blockSize header).

### 80-bit IEEE 754 extended sample rate

10 big-endian bytes: 1 sign bit, a 15-bit exponent biased by 16383, then 64
mantissa bits whose most significant bit is the explicit integer bit.

| Byte range | Bits | Field | Rule |
|---|---|---|---|
| 0..1 | 15 | sign bit + exponent | Sign must be 0; exponent 0x7FFF is rejected. |
| 2..9 | 64 | mantissa (integer bit + 63 fraction bits) | Value = `M * 2^(exponent - 16383 - 63)`. |

Encoding (`aiff_encode_sample_rate(rate)`):

- `rate <= 0` -> `+0.0`: ten zero bytes.
- `k` = index of the highest set bit of `rate`; exponent field =
  `16383 + k` (no sign bit); mantissa = `rate << (63 - k)` by repeated
  arithmetic doubling, so the explicit integer bit lands on bit 63.
- Exact for every integer rate up to 2^31-1 (the largest rate
  `aiff_decode_sample_rate` accepts); the byte emission is also correct for
  larger non-negative `Int` values.

Pinned encodings (used by the tests):

| Rate (Hz) | Bytes (hex) |
|---|---|
| 0 | `00000000000000000000` |
| 1 | `3fff8000000000000000` |
| 8000 | `400bfa00000000000000` |
| 11025 | `400cac44000000000000` |
| 22050 | `400dac44000000000000` |
| 44100 | `400eac44000000000000` |
| 48000 | `400ebb80000000000000` |
| 96000 | `400fbb80000000000000` |
| 192000 | `4010bb80000000000000` |

Decoding (`aiff_decode_sample_rate(data, offset)`) to integer Hz:

- Err(`aiff: offset out of range`) when `offset < 0` or `offset + 10 >
  data.len()`.
- Sign bit set -> Err(`aiff: bad sample rate`); exponent 0x7FFF (Inf/NaN) ->
  Err(`aiff: bad sample rate`).
- Exponent 0 -> `0` (true zero and pseudo-denormals).
- Otherwise with `s = 16446 - exponent` (bits to shift right) and mantissa
  `M`: `s <= 0` (magnitude >= 2^63) is Err(`aiff: bad sample rate`) unless
  `M == 0`, which yields `0`; `s >= 65` yields `0`; `s == 64` yields `1` when
  the top mantissa bit is set and `0` otherwise; `1 <= s <= 63` yields
  `q + round_bit`, where `q = M >> s` and `round_bit` is bit `s-1` of `M`.
  This is round half up (ties away from zero): the discarded fraction is
  rounded up when it is >= 1/2. If `q` exceeds 2^31-1 the value is
  Err(`aiff: bad sample rate`) (out of the supported range).
- `aiff_parse` additionally rejects a decoded rate of `0` with
  Err(`aiff: zero sample rate`).
- `rate_exact` is true when the stored 10 bytes equal
  `aiff_encode_sample_rate(sample_rate)`.

Rounding examples: `44100.5 -> 44101`, `44099.5 -> 44100`,
`44099.4 -> 44099`.

## Chunk walk (aiff_parse)

1. `data.len() == 0` -> Err(`aiff: empty input`).
2. `data.len() < 12` -> Err(`aiff: truncated form header`).
3. Bytes 0..4 not `"FORM"` -> Err(`aiff: bad FORM magic`).
4. Bytes 8..12 neither `"AIFF"` nor `"AIFC"` -> Err(`aiff: bad form type`).
5. FormSize != `data.len() - 8` -> Err(`aiff: bad FORM size`).
6. Walk chunks from offset 12 to the end. For each chunk at `pos` with
   `remaining = data.len() - pos`:
   - `remaining < 8` -> Err(`aiff: truncated chunk header`);
   - id bytes not all printable ASCII -> Err(`aiff: bad chunk id`);
   - payload size `> remaining - 8` -> Err(`aiff: chunk size overrun`);
   - odd payload without its pad byte -> Err(`aiff: truncated chunk padding`);
   - `"COMM"`: a second one -> Err(`aiff: duplicate COMM`); otherwise the
     COMM payload is validated (see the error catalog);
   - `"SSND"`: a second one -> Err(`aiff: duplicate SSND`); SSND before the
     first COMM -> Err(`aiff: SSND before COMM`); payload `size < 8` or
     `offset > size - 8` -> Err(`aiff: short SSND`); otherwise the data span
     is recorded.
   - The chunk is appended to the index and `pos` advances by
     `8 + size + (size % 2)`.
7. COMM never seen -> Err(`aiff: missing COMM`); SSND never seen ->
   Err(`aiff: missing SSND`).

Optional chunks may appear anywhere (before COMM, between COMM and SSND, or
after SSND); only the COMM-before-SSND order is enforced.

## API signatures

All functions are free functions in module `xiom.aiff`:

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

pub fn aiff_encode_sample_rate(rate: Int) -> Vec[UInt8]
pub fn aiff_decode_sample_rate(data: &Vec[UInt8], offset: Int) -> Result[Int, Str]
pub fn aiff_build(samples: &Vec[UInt8], f: &AiffFormat) -> Vec[UInt8]
pub fn aiff_append_chunk(file: &mut Vec[UInt8], id: Str, payload: &Vec[UInt8]) -> Result[Unit, Str]
pub fn aiff_parse(data: &Vec[UInt8]) -> Result[AiffInfo, Str]
pub fn aiff_is_valid(data: &Vec[UInt8]) -> Bool
pub fn aiff_chunk_count(info: &AiffInfo) -> Int
pub fn aiff_chunk_id(info: &AiffInfo, i: Int) -> Str
pub fn aiff_chunk_offset(info: &AiffInfo, i: Int) -> Int
pub fn aiff_chunk_size(info: &AiffInfo, i: Int) -> Int
pub fn aiff_find_chunk(info: &AiffInfo, id: Str) -> Int
pub fn aiff_chunk_data(data: &Vec[UInt8], info: &AiffInfo, i: Int) -> Result[Vec[UInt8], Str]
pub fn aiff_sample_data(data: &Vec[UInt8], info: &AiffInfo) -> Result[Vec[UInt8], Str]
pub fn aiff_duration_ms(info: &AiffInfo) -> Result[Int, Str]
```

## Semantics

`aiff_build(samples, f)`
: Emits FORM + COMM + SSND (in that order) and writes
  `FormSize = file.len() - 8`. `channels` clamps to 1..65535,
  `sample_frames` and `ssnd_offset`/`ssnd_block_size` clamp to
  0..4294967295, `sample_size` clamps to 1..32; those clamped values are
  recorded. `ssnd_offset` zero bytes are inserted between the SSND header
  and the samples. AIFF ignores the compression fields; AIFC writes the
  type as exactly 4 bytes (space-padded/truncated) and the Pascal name
  (empty -> `"not compressed"`, longer than 255 -> 255 bytes). For AIFC the
  name length byte is `len` and one zero pad byte is added when `len` is
  even.

`aiff_append_chunk(file, id, payload)`
: Validates `file.len() >= 12`, the `"FORM"` magic and a 4-character
  printable `id` before writing anything; then appends the padded chunk and
  rewrites `FormSize = file.len() - 8`.

`aiff_parse(data)`
: Structural walk as described above; returns the COMM fields, the SSND
  span and the chunk index. Error propagation is first-failure-wins in the
  documented order.

`aiff_chunk_count` / `aiff_chunk_id` / `aiff_chunk_offset` /
`aiff_chunk_size` / `aiff_find_chunk`
: Infallible index accessors. Out-of-range ids are `""`, offsets/sizes and
  a missing `find` result are `-1`.

`aiff_chunk_data(data, info, i)`
: Copies chunk `i`'s payload bytes. Err(`aiff: chunk index out of range`)
  for a bad index; Err(`aiff: chunk size overrun`) when the indexed span
  does not fit `data`.

`aiff_sample_data(data, info)`
: Copies `ssnd_data_size` bytes at `ssnd_data_offset`. Err(`aiff: short
  SSND`) when the span does not fit `data`.

`aiff_duration_ms(info)`
: `sample_frames * 1000 / sample_rate` (floor division). Err(`aiff: zero
  sample rate`) when the rate is <= 0 (unreachable from `aiff_parse`).

`aiff_is_valid(data)`
: True iff `aiff_parse` succeeds.

## Error string catalog

| Condition | Error text |
|---|---|
| Zero-length buffer | `aiff: empty input` |
| Buffer shorter than 12 bytes | `aiff: truncated form header` |
| Bytes 0..4 are not `"FORM"` | `aiff: bad FORM magic` |
| Bytes 8..12 are neither `"AIFF"` nor `"AIFC"` | `aiff: bad form type` |
| FormSize != `len - 8` | `aiff: bad FORM size` |
| Fewer than 8 bytes remain for a chunk header | `aiff: truncated chunk header` |
| A chunk id byte is outside 0x20..0x7E | `aiff: bad chunk id` |
| Chunk payload extends past the buffer | `aiff: chunk size overrun` |
| Odd payload and no pad byte before the buffer end | `aiff: truncated chunk padding` |
| A second COMM chunk | `aiff: duplicate COMM` |
| COMM payload shorter than 18 (AIFF) or 24 (AIFC) | `aiff: bad COMM size` |
| COMM channels == 0 | `aiff: zero channels` |
| COMM sampleSize outside 1..32 | `aiff: bad sample size` |
| 80-bit rate non-finite/negative/out of integer range | `aiff: bad sample rate` |
| 80-bit rate decodes to 0 | `aiff: zero sample rate` |
| AIFC compression type byte outside 0x20..0x7E | `aiff: bad compression type` |
| AIFC name empty, overruns the chunk, or non-printable | `aiff: bad compression name` |
| SSND appears before the first COMM | `aiff: SSND before COMM` |
| A second SSND chunk | `aiff: duplicate SSND` |
| SSND payload < 8 bytes or offset > size - 8 | `aiff: short SSND` |
| Walk finished without a COMM chunk | `aiff: missing COMM` |
| Walk finished without an SSND chunk | `aiff: missing SSND` |
| `aiff_chunk_data` index < 0 or >= chunk count | `aiff: chunk index out of range` |
| `aiff_decode_sample_rate` offset < 0 or offset + 10 > len | `aiff: offset out of range` |
| `aiff_append_chunk` target shorter than 12 bytes | `aiff: not a FORM container` |
| `aiff_append_chunk` target magic not `"FORM"`, or `id` not 4 printable chars | `aiff: bad FORM magic` / `aiff: bad chunk id` |
| `aiff_chunk_data` indexed span outside `data` | `aiff: chunk size overrun` |
| `aiff_sample_data` span outside `data` | `aiff: short SSND` |

## Complexity

| Operation | Complexity |
|---|---|
| `aiff_encode_sample_rate` / `aiff_decode_sample_rate` | O(1) |
| `aiff_build` | O(samples.len() + ssnd_offset) |
| `aiff_append_chunk` | O(payload.len()) |
| `aiff_parse` / `aiff_is_valid` | O(data.len()) |
| `aiff_chunk_count` / `aiff_chunk_id` / `aiff_chunk_offset` / `aiff_chunk_size` | O(1) |
| `aiff_find_chunk` | O(chunk count) |
| `aiff_chunk_data` | O(chunk size) |
| `aiff_sample_data` | O(ssnd_data_size) |
| `aiff_duration_ms` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module aiff_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Fixtures are built both by the codec and by an
independent test-side chunk writer, with hand-written hex for the canonical
files. Coverage:

1. pinned 80-bit encodings (0, 1, 8000, 11025, 22050, 44100, 48000, 96000,
   192000; negative -> zero);
2. pinned decodes, zero/pseudo-denormal -> 0, offset bounds;
3. rounding half-up (44100.5 -> 44101, 44099.5 -> 44100, 44099.4 -> 44099)
   and rejection of Inf/negative/out-of-range encodings;
4. encode -> decode round-trip over an integer rate matrix (1 .. 2^31-1);
5. pinned 62-byte AIFF file: every COMM/SSND field, the chunk index, the
   sample copy and the raw COMM payload;
6. pinned 78-byte AIFC file: `"NONE"` / `"not compressed"` pass-through,
   SSND span, chunk index;
7. AIFC compression type/name pass-through with odd/even/empty Pascal
   strings (`"sowt"`, `"abc"`, `"abcd"`, `""` -> `"not compressed"`);
8. `aiff_build` byte-for-byte equals the pinned AIFF fixture;
9. `aiff_build` byte-for-byte equals the pinned AIFC fixture;
10. build -> parse round-trips: AIFF 8/16/24/32-bit mono and stereo, AIFC
    with `"NONE"` and `"sowt"`;
11. odd-sized optional chunks (NAME 3, ANNO 6, `(c) ` 4) appended after
    SSND: sizes, offsets, pad byte, FORM size, raw spans;
12. unknown chunks (`COMT`, binary `FVER` payload) indexed and copied;
    accessors and `aiff_chunk_data` out-of-range errors;
13. odd-sized SSND payload (3 sample bytes): pad byte and sample span;
14. SSND offset/block semantics: zero fill, `ssnd_data_offset`, block-size
    pass-through;
15. FORM errors: empty, 4/11-byte truncations, magic, form type, size
    mismatch (too large and zero);
16. chunk walk errors: truncated chunk header, COMM/SSND size overrun,
    odd-size chunk without a pad byte;
17. missing COMM, missing SSND, duplicate COMM, duplicate SSND, SSND before
    COMM;
18. COMM validation: zero channels, sample size 0/33, zero sample rate, bad
    sample rate, short COMM, AIFC COMM too small (18 and 15 bytes);
19. SSND shorter than 8 bytes and offset beyond the payload;
20. AIFC compression field validation (non-printable type, overlong/empty/
    non-printable name) and non-printable chunk id;
21. `aiff_is_valid` true/false paths and `aiff_duration_ms` (200 ms,
    1000 ms, 0 frames);
22. `aiff_append_chunk` validation errors (short buffer, bad magic, bad id
    length) with the buffer unchanged, plus FORM size maintenance.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.aiff
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Header/container layer only: no sample decoding, no compression codecs
  and no conversion to/from other formats.
- Chunk ids, AIFC compression types and AIFC compression names must be
  printable ASCII; non-printable bytes are rejected (binary payload bytes
  are fine).
- The FORM size field must match `len - 8` exactly and the walk must consume
  the buffer; there is no resynchronization and no tolerance for trailing
  bytes.
- COMM must precede SSND; each may occur only once. Optional chunk order is
  otherwise not enforced.
- AIFF COMM payloads larger than 18 bytes and AIFC payloads larger than
  `18 + 4 + even(1 + name)` are accepted, with the extra bytes indexed but
  ignored.
- COMM is decoded but not cross-checked against the SSND span (a
  `sample_frames` / sampleSize combination that does not match the byte
  count is accepted structurally).
- Decoded sample rates are limited to 0..2^31-1 Hz; larger finite 80-bit
  values are rejected as out of range.
- All sizes are 32-bit; payloads above 4 GiB are not representable.
- Not thread-safe; all values are plain value types.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_info`/`_err_info`/`_ok_comm`/`_err_comm`/`_ok_int`/`_err_int`/
  `_ok_bytes`/`_err_bytes`/`_ok_unit`/`_err_unit` (constructing Results
  directly in other functions miscompiles in this compiler).
- All byte reads go through `(data[pos] as Int) & 0xFF`; UInt8 values are
  never compared against Int constants without widening. The 80-bit
  mantissa is emitted byte by byte with arithmetic modulo/division because
  `& 0xFF` on operands with bit 31 set miscompiles.
- `Str` values are only built from file bytes after a printable-ASCII
  check: `builder.sb_to_str` hands out a NUL-terminated C string, and a raw
  0x00 byte would make the result shorter than the source range and trip
  the builder's length contract at run time.
- `Vec[Str]` elements are read into typed locals and compared with
  `xiom.string.str_compare` (BUG 17: `==` on such Str values lowers to a
  pointer comparison).
- Passing `&result.value` (a struct-field `Vec[UInt8]`) to a `&Vec[UInt8]`
  parameter yields an empty vector; every call site binds the vector to a
  local first.
- `AiffInfo` uses parallel `Vec[Int]` / `Vec[Str]` fields (no
  `Vec[StructType]`) and is constructed inside `aiff_parse`, crossing
  function boundaries only by reference or through `_ok_info`.
- No `Vec[Float64]`: the sample-rate codec is pure integer arithmetic.
- Free functions only; no `extern "C"` blocks (no FFI).
