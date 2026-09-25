# xiom.au -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.au`, version `0.1.0`).
Module: `src/au.xi` (`module xiom.au`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`).
No FFI: the module declares no `extern "C"` blocks.

## Scope

A pure-XIOM (no FFI) Sun/NeXT AU (.snd) audio header codec:

- `au_parse` validates a buffer and returns an `AuInfo` header plus the
  resolved audio span;
- `au_build` emits a complete canonical file (24-byte header + optional info
  + samples verbatim) with a real data-size field;
- `au_build_unknown_size` emits the same layout with the 0xFFFFFFFF
  "unknown size" sentinel;
- `au_encoding_name` / `au_encoding_bits` / `au_encoding_bytes` describe the
  documented encoding table (1..7, 27);
- `au_info_bytes` / `au_info_text` expose the raw info field and its
  printable-ASCII-checked text form;
- `au_data_offset` / `au_data_size` / `au_size_known` / `au_stored_size` /
  `au_channels` / `au_sample_rate` are the header accessors;
- `au_audio_data` copies the audio span; `au_frame_count` / `au_duration_ms`
  derive metadata; `au_is_valid` is the boolean convenience reader.

## Non-goals

- Sample decoding: audio bytes are opaque and copied verbatim. In particular
  there is no mu-law or A-law expansion and no linear/float sample
  conversion.
- Float semantics: encodings 6 and 7 are passed through as raw 32-bit /
  64-bit IEEE-754 payloads; the codec never reads a Float32/Float64 value.
- Other audio formats and containers (WAV, AIFF, ...) and any conversion
  between them.
- G.72x ADPCM encodings (ids 23..26 in the original `audio.h`) and every
  other id outside the documented table: they are rejected, not indexed.
- Streaming over files/sockets; the API works on in-memory `Vec[UInt8]`.
- Payloads above 4 GiB (all header sizes are 32-bit fields).

## Byte layout

All multi-byte fields are BIG-endian. Offsets are decimal.

### Header (24 bytes minimum)

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | magic | ASCII `.snd` (`2E 73 6E 64`). |
| 4 | 4 | data offset | u32; absolute byte offset of the first audio byte; must be >= 24 and <= `data.len()`. |
| 8 | 4 | data size | u32; byte count of the audio data; `0xFFFFFFFF` means unknown. |
| 12 | 4 | encoding | u32; one of the documented ids below. |
| 16 | 4 | sample rate | u32; Hz; must be >= 1. |
| 20 | 4 | channels | u32; must be >= 1. |
| 24 | `data_offset - 24` | info | Optional annotation bytes, preserved raw (see below). |
| `data_offset` | `data_size` | audio | Opaque sample bytes. |

### Encoding table

| Id (dec) | Id (hex) | Name | Bits | Bytes |
|---|---|---|---|---|
| 1 | `0x00000001` | `mu-law 8-bit` | 8 | 1 |
| 2 | `0x00000002` | `linear 8-bit` | 8 | 1 |
| 3 | `0x00000003` | `linear 16-bit` | 16 | 2 |
| 4 | `0x00000004` | `linear 24-bit` | 24 | 3 |
| 5 | `0x00000005` | `linear 32-bit` | 32 | 4 |
| 6 | `0x00000006` | `float 32-bit` | 32 | 4 |
| 7 | `0x00000007` | `double 64-bit` | 64 | 8 |
| 27 | `0x0000001b` | `A-law 8-bit` | 8 | 1 |

Encodings 6 and 7 carry raw IEEE-754 payloads (single and double precision);
they are size metadata only, never decoded. Every other id is unknown:
`au_encoding_name` returns `""`, `au_encoding_bits` / `au_encoding_bytes`
return `0`, and `au_parse` rejects the buffer.

### Info field

The info field is every byte from offset 24 to the data offset. `au_parse`
copies it raw and unchanged; it is never interpreted and never rewritten.
`au_info_text` returns it as a `Str` only when every byte is printable ASCII
(0x20..0x7E), and `Err("au: bad info text")` otherwise; `au_info_bytes`
always returns the raw bytes. `au_build*` writes the bytes of the `info`
argument verbatim (no implicit NUL terminator) and sets
`data_offset = 24 + info.len()`.

### Data-size policy

For a validated header with `off = data_offset`, `n = data.len()` and
`stored = data size field`:

| `stored` | Resolved `data_size` | Condition |
|---|---|---|
| `0xFFFFFFFF` | `n - off` (rest of the buffer) | Always; `size_known = false`. |
| `<= n - off` | `stored` | Accepted; bytes after `off + stored` are ignored. |
| `> n - off` | -- | Err(`au: data size overrun`). |

On success `data_offset + data_size <= data.len()` always holds, and
`au_audio_data` copies exactly that span.

## Validation order (au_parse)

First failure wins, in this exact order:

1. `data.len() == 0` -> Err(`au: empty input`).
2. `data.len() < 24` -> Err(`au: truncated header`).
3. Bytes 0..4 not `.snd` -> Err(`au: bad magic`).
4. Data offset < 24 -> Err(`au: bad data offset`).
5. Data offset > `data.len()` -> Err(`au: data offset past end`).
6. Encoding id unknown -> Err(`au: unknown encoding`).
7. Channels == 0 -> Err(`au: zero channels`).
8. Sample rate == 0 -> Err(`au: zero sample rate`).
9. Data-size policy above -> Err(`au: data size overrun`).

The info field is not validated at parse time (see above). A header whose
data offset equals `data.len()` is valid and yields an empty audio span.

## API signatures

All functions are free functions in module `xiom.au`:

```xi
pub type AuFormat = { encoding: Int; sample_rate: Int; channels: Int; }

pub type AuInfo = {
  encoding: Int; sample_rate: Int; channels: Int;
  size_known: Bool; stored_size: Int;
  data_offset: Int; data_size: Int; info_bytes: Vec[UInt8];
}

pub fn au_encoding_name(encoding: Int) -> Str
pub fn au_encoding_bits(encoding: Int) -> Int
pub fn au_encoding_bytes(encoding: Int) -> Int
pub fn au_parse(data: &Vec[UInt8]) -> Result[AuInfo, Str]
pub fn au_is_valid(data: &Vec[UInt8]) -> Bool
pub fn au_build(samples: &Vec[UInt8], f: &AuFormat, info: Str) -> Vec[UInt8]
pub fn au_build_unknown_size(samples: &Vec[UInt8], f: &AuFormat, info: Str) -> Vec[UInt8]
pub fn au_info_bytes(info: &AuInfo) -> Vec[UInt8]
pub fn au_info_text(info: &AuInfo) -> Result[Str, Str]
pub fn au_data_offset(info: &AuInfo) -> Int
pub fn au_data_size(info: &AuInfo) -> Int
pub fn au_size_known(info: &AuInfo) -> Bool
pub fn au_stored_size(info: &AuInfo) -> Int
pub fn au_channels(info: &AuInfo) -> Int
pub fn au_sample_rate(info: &AuInfo) -> Int
pub fn au_audio_data(data: &Vec[UInt8], info: &AuInfo) -> Result[Vec[UInt8], Str]
pub fn au_frame_count(info: &AuInfo) -> Result[Int, Str]
pub fn au_duration_ms(info: &AuInfo) -> Result[Int, Str]
```

## Semantics

`au_build(samples, f, info)`
: Emits magic, `data_offset = 24 + info.len()`, `data_size =
  samples.len()`, the encoding/rate/channels fields, the info bytes and the
  samples. `encoding` is written as given (unknown ids produce a file
  `au_parse` rejects); `sample_rate` clamps to 0..4294967295 (`0` produces a
  file `au_parse` rejects with `au: zero sample rate`); `channels` clamps to
  1..4294967295; the offset and size fields clamp to the u32 range.

`au_build_unknown_size(samples, f, info)`
: Identical, but the data-size field is the 0xFFFFFFFF sentinel.

`au_parse(data)`
: Structural validation as described above; returns the header fields, the
  raw info bytes and the resolved span.

`au_encoding_name` / `au_encoding_bits` / `au_encoding_bytes`
: Encoding table lookups. Unknown ids return `""` / `0` / `0`;
  `au_encoding_bytes` is `ceil(bits / 8)`.

`au_info_bytes(info)` / `au_info_text(info)`
: Raw copy and printable-ASCII-checked `Str` of the info field.

`au_data_offset` / `au_data_size` / `au_size_known` / `au_stored_size`
: Span and size-field accessors: absolute start, resolved length, whether
  the field was a real size, and the raw field value (0xFFFFFFFF when
  unknown).

`au_channels` / `au_sample_rate`
: Validated header fields.

`au_audio_data(data, info)`
: Copies `data_size` bytes at `data_offset`. Err(`au: data size overrun`)
  when the span does not fit `data` (e.g. `info` was parsed from a different
  or truncated buffer).

`au_frame_count(info)`
: `data_size / (channels * bytes_per_sample)`, floor division (an
  incomplete trailing frame is ignored). Err(`au: zero channels`) when
  channels <= 0, Err(`au: unknown encoding`) when the encoding has no
  documented byte size, Err(`au: data size overrun`) for a negative span.
  `au_parse` never returns such values, so these errors are only reachable
  for hand-built `AuInfo` values.

`au_duration_ms(info)`
: `frames * 1000 / sample_rate`, floor division. Err(`au: zero sample
  rate`) is checked first; `au_frame_count` errors propagate.

`au_is_valid(data)`
: True iff `au_parse` succeeds.

## Error string catalog

| Condition | Error text |
|---|---|
| Zero-length buffer | `au: empty input` |
| Buffer shorter than 24 bytes | `au: truncated header` |
| Bytes 0..4 are not `.snd` | `au: bad magic` |
| Data offset < 24 | `au: bad data offset` |
| Data offset > buffer length | `au: data offset past end` |
| Encoding id not in the table | `au: unknown encoding` |
| Channels field is 0 | `au: zero channels` |
| Sample rate field is 0 | `au: zero sample rate` |
| Declared data size exceeds the remaining bytes | `au: data size overrun` |
| Info field contains a byte outside 0x20..0x7E (au_info_text only) | `au: bad info text` |
| `au_audio_data` span does not fit `data` | `au: data size overrun` |
| `au_frame_count` encoding has no byte size | `au: unknown encoding` |
| `au_frame_count` channels <= 0 | `au: zero channels` |
| `au_duration_ms` sample rate <= 0 | `au: zero sample rate` |

## Complexity

| Operation | Complexity |
|---|---|
| `au_encoding_name` / `au_encoding_bits` / `au_encoding_bytes` | O(1) |
| `au_parse` / `au_is_valid` | O(data_offset) (info copy; O(1) otherwise) |
| `au_build` / `au_build_unknown_size` | O(info.len() + samples.len()) |
| `au_info_bytes` / `au_info_text` | O(info_bytes.len()) |
| `au_data_offset` / `au_data_size` / `au_size_known` / `au_stored_size` | O(1) |
| `au_channels` / `au_sample_rate` | O(1) |
| `au_audio_data` | O(data_size) |
| `au_frame_count` / `au_duration_ms` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module au_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Fixtures are built both by the codec and by an
independent test-side header writer, with hand-written hex for the canonical
files. Coverage:

1. encoding table: all eight names, bit and byte sizes, unknown ids
   (`0`, `8`, `23`, `26`, `28`, `4294967295`) return `""`/`0`/`0`;
2. pinned 28-byte mu-law file: every header field, accessors, empty info,
   audio copy, `au_is_valid`;
3. pinned 35-byte info file: `data_offset = 27`, raw info bytes `"Ada"`,
   `au_info_text`, audio span, 2 frames;
4. unknown-size sentinel: pinned bytes, `size_known = false`,
   `stored_size = 0xFFFFFFFF`, rest-of-buffer span, and the same with info;
5. `au_build` byte-for-byte equals the pinned 28-byte canonical file;
6. `au_build` byte-for-byte equals the pinned 31-byte file with info `"Ada"`;
7. build -> parse round-trips across all eight encodings;
8. info round-trips at lengths 0/1/3/18/11 and empty-info `data_offset = 24`;
9. unknown-size round-trips with and without info across encodings;
10. data-size policy: declared 2 of 4 bytes accepted with a 2-byte span,
    declared 0 accepted, declared 5 is Err(`au: data size overrun`);
11. header errors: empty, 23-byte and 4-byte truncations, bad magic;
12. data offset: 0 and 23 -> `au: bad data offset`; `len + 1` -> past end;
    offset 25 with size 4 -> overrun; offset == len with size 0 and with the
    sentinel -> valid empty span;
13. encoding ids 0, 8, 23, 26, 28, `0xFFFFFFFF` -> `au: unknown encoding`;
14. zero channels and zero sample rate are Err;
15. info is preserved raw while `au_info_text` accepts 0x20..0x7E
    (space, `~`) and rejects 0x00, 0x09 and 0x7F with `au: bad info text`;
16. frame count and duration: mu-law mono 8000 frames = 1000 ms, 16-bit
    stereo 44100 frames = 1000 ms, 5-byte stereo payload floors to 1 frame;
17. hand-built `AuInfo`: unknown encoding, zero channels and zero rate error
    paths;
18. `au_audio_data` rejects a header-only buffer and a truncated buffer, and
    copies the full span otherwise;
19. builder clamping: rate -5 -> 0, channels 0 -> 1, values above 2^32-1 ->
    0xFFFFFFFF, unknown encoding written verbatim;
20. `au_is_valid` true/false paths (valid, empty, junk, truncated);
21. encoding table: remaining names and byte sizes;
22. pinned 30-byte 16-bit stereo file with info `"AU"`: accessors, info
    text, 1 frame, 0 ms, audio bytes.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.au
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Header layer only: no sample decoding, no mu-law/A-law arithmetic, no
  float interpretation, no conversion to/from other formats.
- The info field is written verbatim by the builder (no NUL terminator), and
  `au_info_text` rejects every non-printable byte. Canonically
  NUL-terminated `.snd` annotations are therefore preserved through
  `au_info_bytes` but rejected by `au_info_text` (documented trade-off: the
  codec never hands a byte range containing 0x00 to `sb_to_str`).
- Only encodings 1..7 and 27 are known; G.72x ADPCM ids 23..26 and all
  other ids are rejected.
- A declared data size smaller than the remaining bytes is accepted and the
  trailing bytes are ignored; the span never extends past `data.len()`.
- The data-size field is 32-bit; sample buffers of 2^32 bytes or more are
  not representable.
- `sample_rate` and `channels` are u32 fields on the wire; the builder
  clamps, the parser rejects 0.
- Not thread-safe; all values are plain value types.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_info`/`_err_info`/`_ok_int`/`_err_int`/`_ok_bytes`/`_err_bytes`/
  `_ok_str`/`_err_str` (constructing Results directly in other functions
  miscompiles in this compiler).
- All byte reads go through `(data[pos] as Int) & 0xFF`; UInt8 values are
  never compared against Int constants without widening. Builder bytes are
  emitted with the arithmetic `_byte_of` helper because `& 0xFF` on
  operands with bit 31 set miscompiles.
- `Str` values are built from file bytes only after a printable-ASCII
  check: `builder.sb_to_str` hands out a NUL-terminated C string, so a raw
  0x00 byte would make the result shorter than the source range and trip the
  builder's length contract at run time.
- Struct-field `Vec[UInt8]` values are bound to a local before being passed
  to `&Vec[UInt8]` parameters (passing `&info.info_bytes` directly yields an
  empty vector).
- `AuInfo` uses no parallel vectors, no `Vec[StructType]`, no `Vec[Float64]`
  and no `[T, U]` generics; it is constructed inside `au_parse` and crosses
  function boundaries only by reference or through `_ok_info`.
- Free functions only; no `extern "C"` blocks (no FFI).
