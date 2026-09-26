# xiom.tftp -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.tftp`, version `0.1.0`, category `network`).
Module: `src/tftp.xi` (`module xiom.tftp`).
Depends on `xiom.std`; the library module imports `xiom.string` and
`xiom.string.builder` (the tests additionally use `xiom.test`, `xiom.io`,
`xiom.string.compare` and `xiom.encoding.hex`).

## 1. Scope

A pure-XIOM (no FFI, no sockets) codec for the six TFTP packet kinds:

- RRQ (1) / WRQ (2): read and write requests, including the RFC 2347
  option extension (RFC 2348 `blksize`, RFC 2349 `timeout` and `tsize`,
  plus pass-through options such as `windowsize`);
- DATA (3): block number plus payload;
- ACK (4): block number;
- ERROR (5): RFC 1350 error code plus message;
- OACK (6): option acknowledgement (RFC 2347).

Per-kind parsers and builders, a whole-packet dispatcher, a canonical
emitter, flat-storage accessors and a stable `tftp: ...` error catalog.
All 16-bit fields are unsigned big-endian.

## 2. Non-goals

- Sockets, ports, sessions, the lock-step state machine, retransmission
  timers/timeouts and duplicate-block detection: this is the packet layer.
- netascii/mail content translation. The mode string is validated and
  canonicalized, but payload bytes are never converted.
- `windowsize` and any future option semantics: known options are only
  matched and range-checked; everything else is carried verbatim.
- Netascii CR/LF rules, filename path validation, UTF-8 validation and
  charset checks on error messages.
- Server/client convenience wrappers or negotiation policy (which options
  to accept is the caller's decision).

## 3. Wire format

All multi-byte fields are unsigned **big-endian**.

| Opcode | Packet | Layout |
|---|---|---|
| 1 | RRQ | `[u16 1][filename][0x00][mode][0x00]` then option TLVs |
| 2 | WRQ | `[u16 2][filename][0x00][mode][0x00]` then option TLVs |
| 3 | DATA | `[u16 3][u16 block][payload]` |
| 4 | ACK | `[u16 4][u16 block]` (exactly 4 bytes) |
| 5 | ERROR | `[u16 5][u16 code][message][0x00]` |
| 6 | OACK | `[u16 6]` then at least one option TLV |

An option TLV is `[name][0x00][value][0x00]` with a non-empty printable
ASCII name. Examples (hex):

- RRQ `"hello.txt"`, mode `"octet"`:
  `0001 68656c6c6f2e747874 00 6f63746574 00` (18 bytes).
- RRQ `"f.bin"` + `blksize=1428`:
  `0001 662e62696e 00 6f63746574 00 626c6b73697a65 00 31343238 00`.
- DATA block 1, payload `01 02 03`: `0003 0001 010203` (7 bytes).
- ACK block 0: `0004 0000`.
- ERROR code 1, `"File not found"`:
  `0005 0001 46696c65206e6f7420666f756e64 00`.
- OACK `blksize=512`:
  `0006 626c6b73697a65 00 353132 00`.

**Strings.** Filenames, modes, option names, option values and error
messages are copied byte-for-byte; no UTF-8 validation anywhere. At the
XIOM ABI a `Str` is NUL-terminated and cannot embed `0x00`: on parse the
first `0x00` ends a field, and no encoder can ever place a NUL inside one.

**DATA payload.** Everything after the 4-byte header, length-counted, so
`0x00` bytes are payload, not terminators. RFC 1350 uses 0..512 payload
bytes by default (0 is the legal final block of an exact-multiple
transfer); RFC 2348 allows anything up to 65464 at the negotiated block
size. This codec enforces only the protocol hard maximum: a payload of
0..65464 bytes parses and builds, and more is `tftp: payload too long`.
The default/negotiated size distinction is exposed by
`tftp_is_last_block`.

**Block numbers and error codes.** Unsigned 16-bit values, 0..65535.
Builders clamp out-of-range `Int` arguments (`< 0` becomes 0, `> 65535`
becomes 65535); parsers return the raw 16-bit value. Block numbers may
repeat on the wire: a re-sent DATA or ACK is accepted exactly like any
other packet, because duplicate/retransmission state is a session concern
(the re-sent block policy is "no state, no rejection").

**Modes (RFC 1350).** `netascii`, `octet` and `mail` are accepted
case-insensitively (`OCTET`, `Octet`, ...) and stored/emitted canonically
lowercase. Any other mode is `tftp: bad mode`. `mail` is legacy and is
carried, not implemented.

## 4. Options (RFC 2347/2348/2349)

Option names are matched case-insensitively. Known names are stored and
emitted in canonical lowercase; unknown names and all values pass through
verbatim. Known option values must be canonical decimal: one or more
digits, no leading zero unless the value is exactly `"0"` (`"08"`,
`" 8"`, `"-1"`, `"8x"` are all rejected).

| Name | Value rule | Error |
|---|---|---|
| `blksize` | canonical decimal, 8..65464 | `tftp: bad block size` |
| `timeout` | canonical decimal, 1..255 | `tftp: bad option value` |
| `tsize` | canonical decimal, 0..4294967295 | `tftp: bad option value` |
| anything else | any value bytes (non-empty printable name) | `tftp: bad option name` only for a bad name |

Notes:

- `tsize` 0 is legal (a WRQ asks for the size with 0). The 4294967295
  ceiling is the 32-bit protocol maximum (65535 blocks x 65464 bytes =
  4290204840 fits).
- `windowsize` (RFC 7440) and any future option are **pass-through**:
  accepted, preserved in wire order, re-emitted verbatim, never
  interpreted.
- Duplicate option names are not rejected: every TLV is validated and
  preserved independently, in wire order. Negotiation policy (which
  options to accept, at most once) belongs to the caller.
- Empty option values are legal only for unknown names; the known
  options above reject an empty value.

## 5. Flat storage model

A parsed packet is a single `TftpPacket` value with no nested structs and
no `Vec[StructType]`:

| Field | Meaning |
|---|---|
| `opcode` | 1..6 |
| `filename`, `mode` | RRQ/WRQ; `""` otherwise; mode canonical lowercase |
| `block` | DATA/ACK block number; 0 otherwise |
| `error_code`, `error_message` | ERROR; 0/`""` otherwise |
| `payload` | DATA payload bytes; empty otherwise |
| `option_names`, `option_values` | parallel pools, one entry per TLV, RRQ/WRQ/OACK |

The option pools are flat: the valid range is the index range
`0..tftp_option_count(p)-1`, and `tftp_option_name(p, i)` always belongs
to `tftp_option_value(p, i)`. Pools cannot drift through the public API
(the builders validate equal lengths with `tftp: option pool mismatch`,
and `tftp_option_count` returns 0 on drift). Callers are expected to use
the accessors, not the fields.

## 6. API

All functions are free functions in module `xiom.tftp`:

```xi
pub fn tftp_build_rrq(filename: Str, mode: Str, option_names: &Vec[Str], option_values: &Vec[Str]) -> Result[Vec[UInt8], Str]
pub fn tftp_build_wrq(filename: Str, mode: Str, option_names: &Vec[Str], option_values: &Vec[Str]) -> Result[Vec[UInt8], Str]
pub fn tftp_build_data(block: Int, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn tftp_build_ack(block: Int) -> Result[Vec[UInt8], Str]
pub fn tftp_build_error(code: Int, message: Str) -> Result[Vec[UInt8], Str]
pub fn tftp_build_oack(option_names: &Vec[Str], option_values: &Vec[Str]) -> Result[Vec[UInt8], Str]

pub fn tftp_emit(p: &TftpPacket) -> Result[Vec[UInt8], Str]

pub fn tftp_op(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn tftp_parse_rrq(data: &Vec[UInt8]) -> Result[TftpPacket, Str]
pub fn tftp_parse_wrq(data: &Vec[UInt8]) -> Result[TftpPacket, Str]
pub fn tftp_parse_data(data: &Vec[UInt8]) -> Result[TftpPacket, Str]
pub fn tftp_parse_ack(data: &Vec[UInt8]) -> Result[TftpPacket, Str]
pub fn tftp_parse_error(data: &Vec[UInt8]) -> Result[TftpPacket, Str]
pub fn tftp_parse_oack(data: &Vec[UInt8]) -> Result[TftpPacket, Str]
pub fn tftp_parse(data: &Vec[UInt8]) -> Result[TftpPacket, Str]

pub fn tftp_opcode(p: &TftpPacket) -> Int
pub fn tftp_opcode_name(op: Int) -> Str
pub fn tftp_filename(p: &TftpPacket) -> Str
pub fn tftp_mode(p: &TftpPacket) -> Str
pub fn tftp_block(p: &TftpPacket) -> Int
pub fn tftp_error_code(p: &TftpPacket) -> Int
pub fn tftp_error_name(code: Int) -> Str
pub fn tftp_error_message(p: &TftpPacket) -> Str
pub fn tftp_option_count(p: &TftpPacket) -> Int
pub fn tftp_option_name(p: &TftpPacket, i: Int) -> Str
pub fn tftp_option_value(p: &TftpPacket, i: Int) -> Str
pub fn tftp_payload_len(p: &TftpPacket) -> Int
pub fn tftp_payload_byte(p: &TftpPacket, i: Int) -> Int
pub fn tftp_payload_copy(p: &TftpPacket) -> Vec[UInt8]
pub fn tftp_is_last_block(p: &TftpPacket, blksize: Int) -> Bool
```

Public constants: `TFTP_OPCODE_RRQ`..`TFTP_OPCODE_OACK`,
`TFTP_BLKSIZE_MIN` (8), `TFTP_BLKSIZE_MAX` (65464), `TFTP_TIMEOUT_MIN`
(1), `TFTP_TIMEOUT_MAX` (255), `TFTP_TSIZE_MAX` (4294967295),
`TFTP_DEFAULT_BLKSIZE` (512).

## 7. Semantics

`tftp_op(data)`
: Big-endian opcode of `data` when it is 1..6. Pure.

`tftp_parse_<kind>(data)`
: Parse exactly one packet of that kind. Every parser validates
  `data.len() >= 2` and the opcode kind first, then the kind's structure.
  The whole buffer must be consumed: ACK is exactly 4 bytes, ERROR ends
  exactly at the message NUL, RRQ/WRQ/OACK consume complete filename/
  mode/TLV fields with no leftover bytes (an unterminated trailing field
  is `tftp: missing NUL`). Parsers return a fresh `TftpPacket`;
  the input vector is untouched.

`tftp_parse(data)`
: Dispatch on the opcode: `short packet` / `unknown opcode`, then the
  matching per-kind parser. The per-kind parser's `not an X` branch is
  unreachable through the dispatcher.

`tftp_emit(p)`
: Canonical emitter: dispatches on `p.opcode` and re-encodes with the
  builder rules (mode and known option names lowercase, values and
  unknown names verbatim, block/code clamped, payload cap enforced).
  `tftp_parse(tftp_emit(p))` is `Ok` whenever `p` describes a valid
  packet, and canonical wire bytes survive parse->emit byte-for-byte.
  Any other opcode is `tftp: unknown opcode`.

`tftp_error_name(code)`
: `0` "not defined", `1` "file not found", `2` "access violation",
  `3` "disk full", `4` "illegal operation", `5` "unknown transfer id",
  `6` "file already exists", `7` "no such user"; anything else "unknown".
  Parsing accepts any unsigned 16-bit code.

Accessor sentinels: `tftp_option_name`/`tftp_option_value` return `""` and
`tftp_payload_byte` returns `-1` when the index is out of range;
`tftp_block`, `tftp_error_code` and `tftp_payload_len` return 0 for
opcodes that do not own them; `tftp_filename`/`tftp_mode`/
`tftp_error_message` return `""` for other opcodes.

`tftp_is_last_block(p, blksize)`
: `true` when `p` is DATA and `payload_len < effective_blksize`, where
  the effective size is `blksize` if it is 8..65464 and 512
  (`TFTP_DEFAULT_BLKSIZE`) otherwise. Always `false` for non-DATA. This
  is the only place the classic 512 default appears; duplicate blocks are
  not tracked.

## 8. Error catalog

All strings are stable API and start with `tftp: `.

| Error text | Emitted by | Condition |
|---|---|---|
| `tftp: short packet` | `tftp_op`, all parsers | fewer bytes than the opcode header or the kind's fixed part |
| `tftp: unknown opcode` | `tftp_op`, `tftp_parse`, `tftp_emit` | opcode outside 1..6 |
| `tftp: not an RRQ` | `tftp_parse_rrq` | opcode is not 1 (2..6 or unknown) |
| `tftp: not a WRQ` | `tftp_parse_wrq` | opcode is not 2 |
| `tftp: not a DATA packet` | `tftp_parse_data` | opcode is not 3 |
| `tftp: not an ACK` | `tftp_parse_ack` | opcode is not 4 |
| `tftp: not an ERROR packet` | `tftp_parse_error` | opcode is not 5 |
| `tftp: not an OACK` | `tftp_parse_oack` | opcode is not 6 |
| `tftp: missing NUL` | RQ/OACK/ERROR parsers | a filename, mode, option name, option value or message runs to the end without `0x00` |
| `tftp: trailing bytes` | `tftp_parse_ack`, `tftp_parse_error` | ACK longer than 4 bytes; ERROR bytes after the message NUL |
| `tftp: bad filename` | RQ builders/parsers | filename empty or containing a byte outside 0x20..0x7E |
| `tftp: bad mode` | RQ builders/parsers | mode is not netascii/octet/mail (case-insensitive) |
| `tftp: bad option name` | option rules (build/parse/emit) | option name empty or containing a byte outside 0x20..0x7E |
| `tftp: bad block size` | option rules (build/parse/emit) | `blksize` value not canonical decimal in 8..65464 |
| `tftp: bad option value` | option rules (build/parse/emit) | `timeout` not canonical decimal in 1..255, or `tsize` not canonical decimal in 0..4294967295 |
| `tftp: option pool mismatch` | `tftp_build_rrq/wrq/oack`, `tftp_emit` | names/values pools have different lengths |
| `tftp: payload too long` | `tftp_build_data`, `tftp_parse_data`, `tftp_emit` | DATA payload longer than 65464 bytes |
| `tftp: empty OACK` | `tftp_build_oack`, `tftp_parse_oack`, `tftp_emit` | OACK with no option TLV (pools empty / bare 2-byte packet) |

Precedence for every parser: length first, then opcode kind, then
structure in wire order (filename NUL -> filename content -> mode NUL ->
mode content -> TLVs left to right). The first error wins.

## 9. Complexity

| Operation | Complexity |
|---|---|
| `tftp_build_*`, `tftp_emit` | O(bytes written) |
| `tftp_op`, ACK parse, `tftp_is_last_block`, accessors except copy | O(1) |
| RQ/OACK/ERROR parse | O(packet) |
| DATA parse, `tftp_payload_copy` | O(payload) |

No allocation happens on an error path; successful parses allocate fresh
`Str`/`Vec` values. Packets are copied by value like any other XIOM value.

## 10. Test plan

`tests/test_conformance.xi` (`module tftp_tests`, 24 named checks; the
hello-style `main` prints `[PASS]`/`[FAIL]` per check with direct
dispatch, a summary line, and returns the failure count). Coverage:

1. RRQ `hello.txt`/octet exact 18 bytes, accessors, opcode name;
2. WRQ `upload.bin`/octet exact 19 bytes;
3. mode case-insensitive on parse/build, canonical lowercase output,
   invalid mode rejected;
4. RRQ with `blksize`/`timeout`/`tsize` TLVs: exact bytes and accessors;
5. OACK with two TLVs: exact bytes and accessors;
6. OACK edge cases: empty OACK, partial TLV missing NUL, empty value
   for an unknown name;
7. option ranges: blksize 8/65464 accepted, 0/7/65465/`08`/empty/`8x`
   rejected; timeout 1/255 accepted, 0/256 rejected; tsize 0/2^32-1
   accepted, `007`/2^32/`-1` rejected;
8. unknown options (`windowsize`) pass through and known names
   canonicalize; pool mismatch rejected; non-printable option name;
9. DATA block 1 / payload `010203` exact bytes;
10. empty DATA payload is 4 bytes, parses empty, is last; short headers
    and wrong opcode rejected;
11. payload 65464 round-trips, 65465 rejected on build and parse;
12. ACK 0/1/65535 exact bytes, clamping, trailing bytes and short input
    rejected;
13. ERROR exact bytes, empty message, code clamping, the 0..7 name table
    and "unknown" beyond it;
14. ERROR trailing bytes / missing NUL / short / wrong opcode;
15. `tftp_op` accepts 1..6 and rejects 0/7/65535/empty;
16. canonical emitter: uppercase mode and `BLKSIZE` become lowercase,
    unknown mixed-case name survives byte-for-byte;
17. all six packet kinds round-trip parse->emit byte-for-byte;
18. filename validation: empty, TAB, DEL and 0x80 bytes rejected, build
    and parse;
19. DATA payload with NUL and high bytes survives verbatim;
20. `tftp_is_last_block`: 512 default, 1428 negotiated, invalid sizes
    fall back to 512, non-DATA false;
21. missing NUL for filename, mode, option name, option value, message;
22. exact-size policy: ACK/ERROR trailing bytes, OACK partial TLV,
    option-filled RRQ parses exactly;
23. out-of-range accessors return `""`/`-1` sentinels;
24. per-kind parsers reject other opcodes with their stable `not an X`
    errors (including unknown opcodes).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.tftp
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## 11. Known limitations

- Packet layer only: no sockets, sessions, retransmission timers,
  duplicate detection or out-of-order handling; re-sent blocks are
  accepted without state.
- No netascii/mail translation; payload bytes are never converted.
- `windowsize` and future options are pass-through with no semantics.
- Option duplication: every TLV is validated and preserved; uniqueness
  and negotiation policy are left to the caller.
- Strings are copied verbatim: no UTF-8 validation, and a `Str` cannot
  carry `0x00` by construction.
- Only the protocol hard maximum (65464) is enforced on DATA payloads;
  the effective block size is the caller's negotiation result.
- Not thread-safe; all values are plain `TftpPacket`/`Vec`/`Str`.

## 12. Compiler notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers
  (`_ok_packet`, `_err_packet`, `_ok_bytes`, `_err_bytes`, `_ok_int`,
  `_err_int`); option pools are filled through `&mut` parameters and are
  never returned inside tuples.
- Every `Vec[UInt8]` read is widened with `(data[pos] as Int) & 0xFF`
  before comparison; packing is division/modulo arithmetic only.
- `Str` values read from `Vec[Str]` pools are bound to typed locals and
  are compared byte-wise (`_eq_ci`), never with `==` (BUG 17).
- `&struct.field`/`&result.value` are bound to typed locals before being
  passed as `&Vec`/`&mut Vec` parameters.
- No function builds a `Vec` inside a match arm over a tuple-Result;
  there are no match arms and no tuple-Result payloads at all.
- The module declares no `extern "C"` blocks (no FFI).
