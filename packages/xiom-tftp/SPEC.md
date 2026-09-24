# xiom.tftp -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.tftp`, version `0.1.0`).
Module: `src/tftp.xi` (`module xiom.tftp`).
Depends on `xiom.std`; the library module imports only
`xiom.string.builder` (the tests import stdlib modules).

## Scope

A pure-XIOM (no FFI) codec for the five RFC 1350 packet types:

- `tftp_build_rrq` / `tftp_build_wrq`: request packets;
- `tftp_build_data` / `tftp_build_ack` / `tftp_build_error`: data,
  acknowledgement and error packets;
- `tftp_op`: opcode-only inspection of any packet;
- `tftp_parse_rq` / `tftp_parse_data` / `tftp_parse_ack` /
  `tftp_parse_error`: typed parsing with a stable error catalog;
- `tftp_is_last_block`: the "payload < 512" final-block rule.

## Non-goals

- Sockets, sessions, retransmission, timeouts, ports or the
  lock-step/exchange state machine; this is the packet layer only.
- RFC 2347 option negotiation (blksize, timeout, tsize, windowsize) and
  RFC 2348 variable block sizes.
- netascii/mail translation; `mode` is carried as an opaque string.
- Filename validation (path traversal, OS-specific rules) or NUL/UTF-8
  validation of user strings.
- Server or client convenience wrappers.

## Wire format

All multi-byte fields are unsigned **big-endian**.

| Opcode | Packet | Layout (byte offsets) |
|---|---|---|
| 1 | RRQ | `0..2` opcode `0x0001`; `2..` filename bytes; `0x00`; mode bytes; `0x00` |
| 2 | WRQ | `0..2` opcode `0x0002`; `2..` filename bytes; `0x00`; mode bytes; `0x00` |
| 3 | DATA | `0..2` opcode `0x0003`; `2..4` block; `4..end` payload bytes |
| 4 | ACK | `0..2` opcode `0x0004`; `2..4` block |
| 5 | ERROR | `0..2` opcode `0x0005`; `2..4` error code; `4..` message bytes; `0x00` |

Examples (hex):

- RRQ `"hello.txt"`, mode `"octet"`:
  `00 01 68 65 6c 6c 6f 2e 74 78 74 00 6f 63 74 65 74 00` (18 bytes).
- DATA block 1, payload `01 02 03`: `00 03 00 01 01 02 03` (7 bytes).
- ACK block 0: `00 04 00 00`.
- ERROR code 1, `"File not found"`:
  `00 05 00 01 46 69 6c 65 20 6e 6f 74 20 66 6f 75 6e 64 00`.

**Opcode field.** The full 16-bit value is validated: only `0x0001` ..
`0x0005` are known; any other value (including `0x0000`) is
`tftp: unknown opcode`.

**Block numbers and error codes.** Unsigned 16-bit values, 0..65535. The
builders clamp out-of-range `Int` arguments: `< 0` becomes 0, `> 65535`
becomes 65535. Parsers return the raw 16-bit value.

**Strings.** Filenames, modes and error messages are copied byte-for-byte
(no UTF-8 validation). On build, an embedded `0x00` is not rejected and
will produce a malformed packet. On parse, the first `0x00` ends the
string.

**DATA payload.** Everything after the 4-byte header; length-counted, so
`0x00` bytes are payload, not terminators. Payload length is not validated
against the classic 512-byte maximum (RFC 2348 block sizes are a caller
concern).

## API signatures

All functions are free functions in module `xiom.tftp`:

```xi
pub fn tftp_build_rrq(filename: Str, mode: Str) -> Vec[UInt8]
pub fn tftp_build_wrq(filename: Str, mode: Str) -> Vec[UInt8]
pub fn tftp_build_data(block: Int, payload: &Vec[UInt8]) -> Vec[UInt8]
pub fn tftp_build_ack(block: Int) -> Vec[UInt8]
pub fn tftp_build_error(code: Int, message: Str) -> Vec[UInt8]

pub fn tftp_op(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn tftp_parse_rq(data: &Vec[UInt8]) -> Result[(Str, Str), Str]
pub fn tftp_parse_data(data: &Vec[UInt8]) -> Result[(Int, Vec[UInt8]), Str]
pub fn tftp_parse_ack(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn tftp_parse_error(data: &Vec[UInt8]) -> Result[(Int, Str), Str]
pub fn tftp_is_last_block(data: &Vec[UInt8]) -> Result[Bool, Str]
```

## Validation rules

| Function | Accepts | Rejects with |
|---|---|---|
| `tftp_op` | >= 2 bytes and opcode 1..5 | `truncated header` (< 2 bytes), `unknown opcode` (else) |
| `tftp_parse_rq` | opcode 1/2, NUL-terminated filename and mode | `truncated header`, `unknown opcode`, `not an RRQ or WRQ`, `missing NUL terminator` |
| `tftp_parse_data` | opcode 3, >= 4 bytes | `truncated header`, `unknown opcode`, `not a DATA packet`, `truncated packet` (< 4 bytes) |
| `tftp_parse_ack` | opcode 4, exactly 4 bytes | `truncated header`, `unknown opcode`, `not an ACK`, `bad ACK length` |
| `tftp_parse_error` | opcode 5, >= 5 bytes, NUL-terminated message | `truncated header`, `unknown opcode`, `not an ERROR packet`, `truncated packet` (< 5 bytes), `missing NUL terminator` |
| `tftp_is_last_block` | same acceptance as `tftp_parse_data` | the `parse_data` errors above |

Order of checks for every parser: opcode header first (`truncated header`
/ `unknown opcode`), then opcode kind (`not an ...`), then structure
(lengths, terminators). Trailing bytes after the mode terminator in an
RRQ/WRQ are ignored (RFC 2347 options); bytes after the message terminator
in an ERROR packet are ignored.

## Semantics

`tftp_build_*`
: Produce the exact wire bytes described above. `filename`/`mode`/
  `message` bytes are appended with `xiom.string.builder.sb_push_str`
  (verbatim, no escaping). Block and code arguments are clamped with
  `_clamp_u16`.

`tftp_op(data)`
: Reads the big-endian 16-bit header and returns it when it is 1..5.
  Pure: the input vector is untouched.

`tftp_parse_rq(data)`
: Returns `Ok((filename, mode))`. The filename runs from offset 2 to the
  first `0x00`; the mode from just after it to the next `0x00`. Both may
  be empty. `Ok` carries fresh `Str` values (bytes copied verbatim).

`tftp_parse_data(data)`
: Returns `Ok((block, payload))` where `payload` is a fresh copy of
  `data[4..]` (possibly empty). Block is the raw unsigned 16-bit value.

`tftp_parse_ack(data)`
: Returns `Ok(block)`. The packet must be exactly 4 bytes.

`tftp_parse_error(data)`
: Returns `Ok((code, message))`. `code` is the raw unsigned 16-bit value
  (0 is legal); `message` runs from offset 4 to the first `0x00` and may
  be empty.

`tftp_is_last_block(data)`
: `Ok(true)` when `data` is a DATA packet with fewer than 512 payload
  bytes; `Ok(false)` for 512 or more. Because it is a pure function of
  packet length, a DATA packet with a 512-byte payload is never "last"
  under classic mode; a negotiated smaller block size is out of scope.

## Error string catalog

All error strings are stable API and start with `tftp: `.

| Error text | Emitted by | Condition |
|---|---|---|
| `tftp: truncated header` | all parsers | fewer than 2 bytes for the opcode field |
| `tftp: unknown opcode` | all parsers | big-endian opcode outside 1..5 |
| `tftp: not an RRQ or WRQ` | `tftp_parse_rq` | opcode is not 1 or 2 |
| `tftp: not a DATA packet` | `tftp_parse_data`, `tftp_is_last_block` | opcode is not 3 |
| `tftp: not an ACK` | `tftp_parse_ack` | opcode is not 4 |
| `tftp: not an ERROR packet` | `tftp_parse_error` | opcode is not 5 |
| `tftp: truncated packet` | `tftp_parse_data`, `tftp_parse_error`, `tftp_is_last_block` | DATA < 4 bytes, ERROR < 5 bytes |
| `tftp: bad ACK length` | `tftp_parse_ack` | ACK length is not exactly 4 |
| `tftp: missing NUL terminator` | `tftp_parse_rq`, `tftp_parse_error` | a string field runs to the end without `0x00` |

## Complexity

| Operation | Complexity |
|---|---|
| `tftp_build_*` | O(bytes written) time/space |
| `tftp_op` | O(1) |
| `tftp_parse_rq` | O(packet) |
| `tftp_parse_data` | O(payload) time/space |
| `tftp_parse_ack` | O(1) |
| `tftp_parse_error` | O(message) |
| `tftp_is_last_block` | O(1) |

No allocation on the error paths; each successful parse copies its string
and/or payload bytes into fresh values.

## Test plan

`tests/test_conformance.xi` (`module tftp_tests`, 24 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. RRQ `hello.txt`/`octet` exact 18 bytes and opcode 1;
2. WRQ `upload.bin`/`octet` exact 19 bytes and opcode 2;
3. empty filename / empty mode encode and parse back;
4. filename and mode with spaces round-trip;
5. DATA block 1 / payload `010203` exact bytes and round-trip;
6. empty DATA payload is 4 bytes, parses empty, is last;
7. 512-byte payload round-trips, exact header/tail bytes, not last;
8. 511-byte payload round-trips, is last;
9. ACK 0 / 1 / 65535 exact bytes and round-trip;
10. `build_data`/`build_ack` clamp negative and > 65535 blocks;
11. ERROR code 1 / `File not found` exact bytes and round-trip;
12. ERROR code 0 with empty message;
13. unicode filename bytes preserved exactly (`héllo/文件.bin`);
14. `parse_rq` round-trips WRQ; rejects wrong type, unknown opcode,
    unterminated filename and unterminated mode;
15. `tftp_op` accepts 1..5; rejects 0, 6, 65535, 1-byte and empty input;
16. `parse_data` round-trips payload with `0x00` and high bytes; rejects
    wrong type, 2-byte and 3-byte buffers, empty input;
17. `parse_ack` round-trips 0/300/65535; rejects wrong type, 5-byte and
    3-byte lengths, empty input;
18. `parse_error` round-trips; rejects wrong type, 2-byte/4-byte buffers,
    unterminated message, empty input;
19. `is_last_block`: empty and 511 payloads last, 512 not;
20. 511-byte DATA packet is exactly 515 bytes end to end;
21. `is_last_block` propagates `not a DATA packet` / `truncated packet` /
    `truncated header`;
22. `parse_rq` ignores RFC 2347 option bytes after the mode;
23. DATA block 65535 exact header bytes and round-trip;
24. all five packet types round-trip end to end.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.tftp
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Packet layer only: no sockets, sessions, retransmission, timeouts,
  duplicate detection or out-of-order handling.
- Octet mode by convention; `mode` is not validated, defaulted or
  translated.
- No RFC 2347 option parsing/negotiation; option bytes are skipped on
  parse.
- Classic 512-byte block assumption in `tftp_is_last_block` only.
- Strings are copied verbatim in both directions: no NUL validation on
  build, no UTF-8 validation on parse.
- Not thread-safe; all values are plain `Vec[UInt8]`/`Str`.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_ok_int`, `_err_int`, `_ok_bool`, `_err_bool`, `_ok_rq`, `_err_rq`,
  `_ok_data`, `_err_data`, `_ok_error`, `_err_error`); constructing
  `Result` values directly inside other functions miscompiles in this
  compiler.
- No function builds a `Vec` inside a match arm over a tuple-Result (the
  shape the stdlib probe `p_result_tuple_vec_loop` shows mis-laying out
  the payload). `_copy_bytes` is a plain loop in a helper, and
  `_ok_data` constructs the tuple outside any match.
- All big-endian packing/unpacking is arithmetic (division/modulo); every
  byte read is cast to `Int` before comparison, so no `UInt8` is compared
  against a literal >= 128.
- Str fields use `xiom.string.builder.sb_push_str` / `sb_to_str` (the
  proven one-allocation pattern; see `xiom-bson`).
- The tests route every `Str` comparison through
  `xiom.string.compare.str_compare` (BUG 17 discipline: `==` on `Str`
  values read from a `Vec` lowers to a pointer comparison) and use typed
  `let` for byte reads.
- The package declares no `extern "C"` blocks (no FFI).
