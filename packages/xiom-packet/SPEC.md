# xiom.packet -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.packet`, version `0.1.0`).
Module: `src/packet.xi` (`module xiom.packet`).
Depends on `xiom.std`; the library module imports nothing (the tests import
stdlib modules).

## Scope

A pure-XIOM (no FFI) packet framing codec for a documented wire format:

- `packet_frame`: payload -> `[u32 LE length][payload][u32 LE CRC-32]`;
- `packet_parse_all`: whole buffer -> every complete frame payload, in
  order, each CRC-validated;
- `packet_is_valid`: single-frame buffer validation;
- `packet_crc32`: the standard reflected IEEE 802.3 checksum;
- `PacketDecoder`: a streaming buffer for chunked input with
  feed / available / take / buffered state.

## Non-goals

- Compression, encryption, authentication or payload typing; payload bytes
  are opaque.
- Fragmentation/reassembly of logical messages across frames; each frame
  is one payload.
- Streaming sinks or sources: the codec works on in-memory `Vec[UInt8]`
  buffers; chunk boundaries are caller-controlled via `PacketDecoder`.
- CRC-32C (Castagnoli), CRC-64 or other checksums.
- A lookup-table CRC (a table is a performance optimization only; see the
  compiler notes for why this port is table-free).

## Wire format

One frame, byte offsets from the frame start:

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 4 | payload length | unsigned 32-bit little-endian |
| 4 | `len` | payload | bytes verbatim |
| 4 + `len` | 4 | payload CRC-32 | unsigned 32-bit little-endian |

Total frame size = `8 + len`. `len` counts payload bytes only; the length
and CRC fields are not included. A frame with an empty payload is 8 bytes:
`00 00 00 00` + `00 00 00 00` (CRC-32 of the empty byte string is 0).

A buffer of N concatenated frames contains no padding, separator or magic
number: decoding is purely length-driven.

## CRC-32 parameters

| Parameter | Value |
|---|---|
| Width | 32 bits |
| Polynomial (normal) | `0x04C11DB7` |
| Polynomial (reflected) | `0xEDB88320` |
| Initial value | `0xFFFFFFFF` |
| Input reflection | yes (reflected, LSB-first) |
| Output reflection | yes (reflected) |
| Final XOR | `0xFFFFFFFF` |
| Check (`"123456789"`) | `0xCBF43926` (3421780262) |
| Check (`""`) | `0x00000000` (0) |
| Residue (`"123456789"` + CRC) | `0x2144DF1C` (informational) |

Implementations notes: computed bitwise, table-free, with `UInt` state;
the public `packet_crc32` return type is `Int` and carries the unsigned
32-bit value (0..4294967295). This is the same algorithm as zlib/gzip
CRC-32 and the stdlib `xiom.compress.gzip.gzip_crc32`; known-answer vectors
are cross-checked against zlib (`""`, `"a"`, `"abc"`, `"123456789"` and a
300-byte pattern).

## API signatures

All functions are free functions in module `xiom.packet`:

```xi
pub type PacketDecoder = { buf: Vec[UInt8]; pos: Int; }

pub fn packet_crc32(data: &Vec[UInt8]) -> Int
pub fn packet_frame(payload: &Vec[UInt8]) -> Vec[UInt8]
pub fn packet_parse_all(data: &Vec[UInt8]) -> Result[Vec[Vec[UInt8]], Str]
pub fn packet_is_valid(data: &Vec[UInt8]) -> Bool

pub fn packet_decoder_new() -> PacketDecoder
pub fn packet_decoder_feed(d: &mut PacketDecoder, chunk: &Vec[UInt8])
pub fn packet_decoder_available(d: &PacketDecoder) -> Int
pub fn packet_decoder_take(d: &mut PacketDecoder) -> Result[Vec[UInt8], Str]
pub fn packet_decoder_buffered(d: &PacketDecoder) -> Int
```

## Semantics

`packet_frame(payload)`
: Writes `payload.len()` as 4 LE bytes, the payload bytes verbatim, then
  `packet_crc32(payload)` as 4 LE bytes. The documented API bound is a
  payload of at most 2^31-1 bytes.

`packet_parse_all(data)`
: Walks the buffer from offset 0 while bytes remain. For each frame it
  reads the declared length, requires `8 + len` bytes to be present, copies
  the payload, recomputes its CRC-32 and compares it with the stored value.
  `Ok` holds the payloads in frame order. An empty input is an empty `Ok`.
  On the first failure the whole call is `Err` (no partial prefix is
  returned).

`packet_is_valid(data)`
: `true` iff `packet_parse_all(data)` is `Ok` with exactly one frame.
  Empty input, partial frames, CRC corruption and multi-frame buffers are
  all `false`.

`packet_crc32(data)`
: CRC-32 of the whole byte vector, per the parameter table above.

### Decoder state rules

`PacketDecoder` fields (implementation details):

- `buf`: bytes fed but not yet consumed, plus (until the next `feed`) any
  already-consumed prefix. Invariant: consumed bytes, if present, are
  exactly `buf[0 .. pos]`.
- `pos`: index of the first unconsumed byte. Invariant:
  `0 <= pos <= buf.len()`.

State transitions:

- `packet_decoder_new()`: `buf` empty, `pos == 0`.
- `packet_decoder_feed(d, chunk)`: appends `chunk` to `buf` and compacts
  away the consumed prefix (`buf` becomes `old buf[pos..] + chunk`,
  `pos` resets to 0). The decoder therefore never retains bytes that
  `take` already returned. A zero-byte chunk is a no-op. O(buffered + chunk).
- `packet_decoder_available(d)`: scans from `pos`, counting frames whose
  declared length is fully buffered. Stops at the first incomplete frame
  (a partial tail does not hide later complete frames, but bytes after an
  incomplete frame cannot be a valid frame start because decoding is
  length-driven). Does not verify CRCs. O(frames).
- `packet_decoder_take(d)`:
  - no complete frame -> `Err("packet: no complete frame")`, state
    unchanged (nothing consumed, nothing removed);
  - a complete frame with a valid CRC -> `Ok(payload)`, `pos` advances past
    the frame (`8 + len` bytes);
  - a complete frame with a bad CRC -> `Err("packet: crc mismatch")` and
    `pos` **advances past the corrupt frame**, so the decoder
    resynchronizes on the following bytes. The corrupt payload is not
    returned.
- `packet_decoder_buffered(d)`: `buf.len() - pos` (unconsumed bytes).

## Error string catalog

| Condition | Error text |
|---|---|
| Fewer than 4 bytes remain for a length field, or fewer than `8 + len` bytes remain for the declared frame | `packet: truncated frame` |
| A structurally complete frame's payload CRC-32 differs from the stored value | `packet: crc mismatch` |
| `packet_decoder_take` with no structurally complete frame buffered | `packet: no complete frame` |

`packet_parse_all` returns only the first two; `packet_decoder_take` only
the last two. All three strings are stable API.

## Complexity

| Operation | Complexity |
|---|---|
| `packet_crc32` | O(n) time (8 bit-steps/byte), O(1) space |
| `packet_frame` | O(payload) time/space |
| `packet_parse_all` | O(bytes) time, O(total payload) space |
| `packet_is_valid` | same as `packet_parse_all` |
| `packet_decoder_new` | O(1) |
| `packet_decoder_feed` | O(buffered + chunk) time/space (compaction) |
| `packet_decoder_available` | O(buffered) worst case, O(frames) typical |
| `packet_decoder_take` | O(frame bytes) |
| `packet_decoder_buffered` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module packet_tests`, 24 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. `packet_crc32("")` is 0;
2. `packet_crc32("123456789")` is 0xCBF43926 (3421780262);
3. zlib vectors `"a"` (3904355907) and `"abc"` (891568578);
4. high-bit bytes `ff 00 80 7f 01` (0x32D37EBE);
5. exact 11-byte frame for payload `{1,2,3}`;
6. empty-payload frame is 8 zero bytes and parses back;
7. exact 13-byte frame for the high-bit payload;
8. `parse_all` single frame;
9. `parse_all` multiple frames keeps order;
10. `parse_all` of empty input is an empty `Ok`;
11. trailing partial frame -> `packet: truncated frame`;
12. CRC-corrupted frame -> `packet: crc mismatch`;
13. valid frame followed by a partial frame -> whole-call `Err`;
14. `packet_is_valid` accepts exactly one CRC-valid frame;
15. decoder: whole-frame feed -> available/take/buffered;
16. decoder: byte-by-byte feed completes only on the last byte;
17. decoder: two frames in one chunk decode in order;
18. decoder: partial 3-byte header is not a frame until completed;
19. decoder: take with no complete frame Errs and consumes nothing;
20. decoder: partial tail is held until completed;
21. 300-byte payload round-trips through frame/parse_all (CRC 0x3ABCFCEE);
22. decoder: corrupt frame Errs, then resyncs on the next good frame;
23. 300-byte frame LE length prefix and LE CRC trailer bytes;
24. decoder: feed compacts the consumed prefix and keeps decoding.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.packet
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Single-frame payload length is bounded by 2^31-1 bytes (documented API
  bound; the u32 length field could represent more, but `Int` lengths and
  in-memory buffers make larger frames impractical).
- CRC-32 detects accidental corruption only; it is not a cryptographic
  integrity or authenticity mechanism.
- No compression, encryption, payload typing or cross-frame reassembly.
- `packet_parse_all` is all-or-nothing on a bad frame (no valid prefix).
- `packet_decoder_available` reports structural completeness, not CRC
  validity.
- Decoder buffers grow with unconsumed input; there is no size cap (the
  caller enforces one).
- Not thread-safe; decoders are plain value types.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_bytes`/`_err_bytes`/`_ok_frames`/`_err_frames` (constructing
  `Result` values directly inside other functions miscompiles in this
  compiler).
- The CRC-32 loop keeps its state in a `UInt` local and uses only `^`,
  `>>` and `& 1`. This mirrors the verified stdlib
  `xiom.compress.gzip._gzip_crc32_impl`: the `& 0xFF`-on-bit-31-set and
  module-level `[256]`-table forms miscompile or mis-materialize in
  v0.61.3.
- All u32 little-endian packing/unpacking is arithmetic
  (modulo/division), so no masking of values with bit 31 set is needed.
- Read-only helpers take `&Vec[UInt8]`; mutating decoder entries take
  `&mut PacketDecoder`. The tests route the read-only accessors through
  `&mut` wrappers (`dec_available`, `dec_buffered`) so no function mixes a
  `&local` call with a later `&mut local` call (advisory E001).
- Str equality goes through `xiom.string.compare.str_compare` (BUG 17
  discipline); the library itself never compares `Str` values.
- The package declares no `extern "C"` blocks (no FFI).
