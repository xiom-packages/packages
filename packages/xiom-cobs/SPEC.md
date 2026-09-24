# xiom.cobs -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.cobs`, version `0.1.0`).
Module: `src/cobs.xi` (`module xiom.cobs`).
Depends on `xiom.std`; the library module imports nothing (the tests import
stdlib modules).

## Scope

A pure-XIOM (no FFI) COBS (Consistent Overhead Byte Stuffing) codec for a
single frame:

- `cobs_encode`: payload -> a 0x00-free frame body;
- `cobs_decode`: frame body -> payload, with structural validation;
- `cobs_encoded_size`: exact encoded length of a payload;
- `cobs_is_encoded`: "contains no 0x00 byte";
- `cobs_max_payload_for`: largest payload that fits a frame of a given
  length.

## Non-goals

- Delimiter handling: `0x00` is the wire frame delimiter, but these helpers
  neither append nor strip it. The caller frames the output
  (`frame + 0x00`) and splits/strips before decoding.
- Streaming/incremental decoding, multi-frame parsing, buffering or
  chunked-input state (use `xiom.packet`'s decoder for length-prefixed
  streaming).
- Checksums, compression, encryption, payload typing. Payload bytes are
  opaque and copied verbatim.
- CRC/parity integration: combine with `xiom.hash.crc` or `xiom.packet`
  when corruption detection is needed.

## Notation and definitions

- A **frame body** is the COBS-encoded byte vector; on the wire a single
  `0x00` byte is appended as the delimiter.
- A **block** is one code byte followed by `code - 1` data bytes.
- A **run** is a maximal sequence of consecutive non-zero input bytes,
  capped at 254 bytes.
- `n` is the payload length in bytes.

## Encoding algorithm

The encoder walks the input left to right and never emits a `0x00`:

1. At position `i`, scan forward while the byte is non-zero and fewer than
   254 bytes have been scanned; that is the block run length `r`
   (`0 <= r <= 254`).
2. Emit the code byte `r + 1`, then the `r` data bytes verbatim.
3. If the scan stopped at end of input, the code byte just emitted is the
   final code byte and encoding is complete.
4. If the scan stopped because the byte at `j` is non-zero (the run hit the
   254 cap), continue at `j` with a new block (step 1).
5. Otherwise `data[j] == 0`:
   - if `r == 254`, the full code byte 255 implies no zero, so emit an
     explicit empty code-1 block for it;
   - if `j` is the last input byte, emit a trailing code-1 block (the
     implied zero needs a following block to be decoded);
   - otherwise continue at `j + 1`; the zero is implied by the code byte
     `r + 1 < 255` when the next block follows.

Normative examples (`xx` = a non-zero byte):

| Input | Encoded | Note |
|---|---|---|
| (empty) | `01` | documented empty frame |
| `b` | `02 b` | |
| `b1 b2` | `03 b1 b2` | |
| `11 22 00 33` | `03 11 22 02 33` | zero splits the codes |
| `11 00 00 00` | `02 11 01 01 01` | each zero gets a short block |
| `00` | `01 01` | |
| `b1..b254` (all non-zero) | `FF b1..b254` | 255 bytes: one full run, no redundant code |
| `b1..b255` (all non-zero) | `FF b1..b254 02 b255` | 257 bytes: extra code byte |
| `b1..b254 00` | `FF b1..b254 01 01` | zero after a full run needs two code bytes |

The maximum overhead is one code byte per 254 payload bytes, plus the final
code byte: `cobs_encoded_size(data) = n + 1` when no full 254-byte run is
followed by more input, and `n + 1 + k` otherwise (`k` = number of such
runs).

The encoder emits the **minimal** form: when the input ends exactly on a
254-byte run boundary, no redundant trailing code byte is emitted. COBS
decoders accept both the minimal form and the padded form where such a frame
ends with an extra `01` (produced by encoders that always close with a code
byte); `cobs_decode` accepts both and yields the same payload.

## Decoding algorithm

1. Scan the whole input; any `0x00` byte is
   `Err("cobs: zero byte in frame")`.
2. Walk the input in blocks: read a code byte `c` (already known non-zero),
   then require `c - 1` further bytes. If fewer remain,
   `Err("cobs: truncated frame")`.
3. Append the `c - 1` data bytes. If `c < 255` and more input bytes remain,
   append one `0x00` (the implied zero).
4. Continue with the next block.

An empty input decodes to an empty `Ok` (documented convenience; a real
frame body always contains at least one code byte).

## Boundary rules

- **Empty payload**: `cobs_encode([]) == [0x01]`; `cobs_decode([]) == Ok([])`
  and `cobs_decode([0x01]) == Ok([])`.
- **254-byte runs**: a run of exactly 254 non-zero bytes is one block with
  code byte 255 and no implied zero. A run of 255 non-zero bytes starts a
  second block (code 2 + one byte).
- **Zeros at the start**: the leading zero is implied by a code-1 block
  (`00 05 -> 01 02 05`).
- **Zeros at the end**: a trailing zero gets an explicit trailing code-1
  block (`05 00 -> 02 05 01`).
- **Zero after a full run**: the code byte 255 implies no zero, so the zero
  is encoded by an explicit empty code-1 block
  (`b1..b254 00 -> FF .. 01 01`).
- **Consecutive zeros**: each zero contributes one short block
  (`00 00 00 -> 01 01 01 01`).
- **Padded final block**: `[FF][254 bytes][01]` decodes like
  `[FF][254 bytes]`; the trailing code-1 block adds no payload and no zero.

## Size helpers

- `cobs_encoded_size(data)`: exact length, always identical to
  `cobs_encode(data).len()`. Empty input -> 1.
- `cobs_max_payload_for(frame_len)`: largest `n` whose worst-case encoded
  frame (all payload bytes non-zero) fits in `frame_len`:
  `n + 1 + (n - 1) / 254 <= frame_len` for `n >= 1` (integer division).
  `frame_len <= 1` -> 0; the result is never negative. Payloads containing
  zeros may be shorter than the bound but never longer for the same `n`.

  | `frame_len` | 0, 1 | 2 | 3 | 254 | 255 | 256 | 257 | 510 | 512 |
  |---|---|---|---|---|---|---|---|---|---|
  | max payload | 0 | 1 | 2 | 253 | 254 | 254 | 255 | 508 | 509 |

- `cobs_is_encoded(data)`: `true` iff no byte is `0x00` (vacuously true for
  empty input). Necessary but not sufficient for decodability: truncated
  code bytes are still rejected by `cobs_decode`.

## Error string catalog

| Condition | Error text |
|---|---|
| Any input byte is `0x00` | `cobs: zero byte in frame` |
| A code byte declares more payload bytes than remain | `cobs: truncated frame` |

Both strings are stable API. `cobs_decode` returns only these two errors.

## Complexity

| Operation | Complexity |
|---|---|
| `cobs_encode` | O(n) time, O(encoded) space |
| `cobs_decode` | O(frame) time, O(payload) space |
| `cobs_encoded_size` | O(n) time, O(1) space |
| `cobs_is_encoded` | O(n) time, O(1) space |
| `cobs_max_payload_for` | O(1) time/space |

A decoded payload is never longer than its frame body
(`sum(code_i - 1) <= frame_len - block_count`).

## Test plan

`tests/test_conformance.xi` (`module cobs_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. empty input -> `[01]`, decodes back to empty;
2. single non-zero byte -> `[02, b]`;
3. two non-zero bytes -> `[03, b1, b2]`;
4. `0x00` in the middle splits the codes (`[02 11 02 22]`);
5. input starting with `0x00` -> leading code `01`;
6. input ending with `0x00` -> trailing code `01`;
7. 254 non-zero bytes -> exactly 255 output bytes, first byte `FF`;
8. 255 non-zero bytes -> 257 output bytes with an extra code byte;
9. all-zero input `00 00 00` -> `[01 01 01 01]`;
10. standard vectors `[03 11 22 02 33]` and `[02 11 01 01 01]`;
11. round-trips for every length 0..300 (`i % 256` pattern);
12. round-trips for every length 0..300 (zero every 7th byte);
13. encoded frames never contain `0x00`;
14. decode rejects any `0x00` byte with the exact message;
15. truncated code bytes -> Err with the exact message (plus a valid
    control);
16. `encoded_size` exact at empty/zero/254/255/trailing-zero cases and for
    a mixed 300-byte payload;
17. `is_encoded` boundary values (empty true, zero-containing false);
18. `max_payload_for` boundary values (0, 1, 2, 3, 253..257, 510, 512, and
    negative input);
19. `max_payload_for` property sweep for 2 <= frame_len <= 600 (the result
    fits and one more byte does not);
20. decoder accepts the padded `[FF][254 bytes][01]` form of a full run.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.cobs
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_bytes`/`_err_bytes` (constructing `Result` values directly inside
  other functions miscompiles in this compiler).
- The encoder performs no retroactive vector writes: each block is scanned
  to completion before its code byte is pushed, so no placeholder fixups or
  `Vec` index assignments are needed.
- Every `Vec[UInt8]` element read is widened with `as Int` before use.
- Str equality in the tests goes through
  `xiom.string.compare.str_compare` (BUG 17 discipline); the library
  itself never compares `Str` values.
- The package declares no `extern "C"` blocks (no FFI).

## Known limitations

- Single frame per call; no delimiter handling, multi-frame parsing or
  streaming decoder state.
- The decoder accepts both the minimal and the padded form of a full final
  run (documented above); it does not attempt to require one canonical
  form.
- No checksum or integrity guarantee; COBS is a transparency transform.
- Whole payloads and frames are materialized in memory.
- Not thread-safe; free functions over value types.
