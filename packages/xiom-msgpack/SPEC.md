# xiom.msgpack -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.msgpack`, version `0.1.0`).
Module: `src/msgpack.xi` (`module xiom.msgpack`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`).

## Scope

A pure-XIOM (no FFI) MessagePack codec for a documented subset:

- encoders returning the exact minimal byte encoding for nil, bool, Int,
  Str, and array/map count headers;
- a mutable reader cursor (`MsgpackReader`) with `Result`-returning
  decoders for Int, Str, Bool, array headers and map headers;
- cursor introspection (`pos`, `remaining`) and raw format-byte peeking;
- deterministic error strings for truncation and unexpected format bytes.

## Non-goals

- Float32/float64 (`0xca`/`0xcb`): encoding requires an IEEE-754 bitcast
  that does not exist in XIOM v0.61.3 (see Known limitations).
- Bin (`0xc4`/`0xc5`/`0xc6`), ext (`0xc7`-`0xc9`, `0xd4`-`0xd8`), and
  MessagePack timestamp extensions.
- Container *element* decoding: array/map readers consume headers only.
- Str UTF-8 validation (payload bytes are copied verbatim).
- Streaming over sockets/files; this codec works on in-memory
  `Vec[UInt8]` buffers.
- A generic `Value` tree with recursive encode/decode.
- Canonical-form enforcement across non-minimal encodings on decode (the
  decoder accepts any valid encoding of a supported type).

## Byte-level format table (supported encoders)

All multi-byte integers in headers are big-endian. "Minimal" means the
encoder always picks the first applicable row.

| Value | Format byte(s) | Payload |
|---|---|---|
| nil | `0xc0` | -- |
| false | `0xc2` | -- |
| true | `0xc3` | -- |
| Int `0..127` | `0x00..0x7f` (positive fixint) | value in the format byte |
| Int `-32..-1` | `0xe0..0xff` (negative fixint) | value in the format byte |
| Int `128..255` | `0xcc` | 1 byte unsigned |
| Int `256..65535` | `0xcd` | 2 bytes unsigned |
| Int `65536..4294967295` | `0xce` | 4 bytes unsigned |
| Int `>= 4294967296` | `0xcf` | 8 bytes unsigned |
| Int `-128..-33` | `0xd0` | 1 byte signed (two's complement) |
| Int `-32768..-129` | `0xd1` | 2 bytes signed |
| Int `-2147483648..-32769` | `0xd2` | 4 bytes signed |
| Int `< -2147483648` | `0xd3` | 8 bytes signed |
| Str len `0..31` | `0xa0..0xbf` (fixstr) | len in the format byte, then bytes |
| Str len `32..255` | `0xd9` | 1-byte len, then bytes |
| Str len `256..65535` | `0xda` | 2-byte len, then bytes |
| Str len `65536..4294967295` | `0xdb` | 4-byte len, then bytes |
| array count `0..15` | `0x90..0x9f` (fixarray) | count in the format byte |
| array count `16..65535` | `0xdc` | 2-byte count |
| array count `65536..4294967295` | `0xdd` | 4-byte count |
| map count `0..15` | `0x80..0x8f` (fixmap) | count in the format byte |
| map count `16..65535` | `0xde` | 2-byte count |
| map count `65536..4294967295` | `0xdf` | 4-byte count |

Not supported (decoders report `unexpected type 0xNN`): `0xc1`,
`0xc4`-`0xc6` (bin), `0xc7`-`0xc9` (ext), `0xca`/`0xcb` (float),
`0xd4`-`0xd8` (fixext).

## API signatures

All functions are free functions in module `xiom.msgpack`:

```xi
pub type MsgpackReader = { data: Vec[UInt8]; pos: Int; }

pub fn msgpack_encode_nil() -> Vec[UInt8]
pub fn msgpack_encode_bool(b: Bool) -> Vec[UInt8]
pub fn msgpack_encode_int(n: Int) -> Vec[UInt8]
pub fn msgpack_encode_str(s: Str) -> Vec[UInt8]
pub fn msgpack_encode_array_header(n: Int) -> Vec[UInt8]
pub fn msgpack_encode_map_header(n: Int) -> Vec[UInt8]

pub fn msgpack_reader_new(data: Vec[UInt8]) -> MsgpackReader
pub fn msgpack_reader_pos(r: &MsgpackReader) -> Int
pub fn msgpack_reader_remaining(r: &MsgpackReader) -> Int
pub fn msgpack_peek_type(r: &MsgpackReader) -> Result[Int, Str]
pub fn msgpack_read_int(r: &mut MsgpackReader) -> Result[Int, Str]
pub fn msgpack_read_str(r: &mut MsgpackReader) -> Result[Str, Str]
pub fn msgpack_read_bool(r: &mut MsgpackReader) -> Result[Bool, Str]
pub fn msgpack_read_array_len(r: &mut MsgpackReader) -> Result[Int, Str]
pub fn msgpack_read_map_len(r: &mut MsgpackReader) -> Result[Int, Str]
```

`msgpack_encode_float64` is intentionally absent (see Known limitations).

## Semantics

`msgpack_encode_array_header(n)` / `msgpack_encode_map_header(n)`
: For `n < 0` or `n > 4294967295` there is no MessagePack count encoding;
  these return an **empty** `Vec[UInt8]` (caller error; the API cannot
  return `Err`). Otherwise the minimal fix/16/32-bit header.

`msgpack_read_int(r)`
: Accepts positive/negative fixint, uint8/16/32/64 and int8/16/32/64.
  `uint64` values above 2^63-1 are returned as the same two's-complement
  bit pattern interpreted as a signed `Int` (the platform `Int` is signed
  64-bit); no error is raised for that case.

`msgpack_read_str(r)`
: Accepts fixstr, str8, str16, str32. The payload is copied into a fresh
  `Str` via `xiom.string.builder.sb_to_str` (bytes verbatim, no UTF-8
  validation).

`msgpack_read_bool(r)` / `msgpack_read_array_len(r)` / `msgpack_read_map_len(r)`
: Container readers consume only the header and return the count; elements
  are decoded by the caller.

`msgpack_peek_type(r)` / `msgpack_reader_pos` / `msgpack_reader_remaining`
: Read-only; no cursor change. `remaining` is clamped at 0.

Cursor/error-state contract
: On `Err`, `msgpack_read_*` may have advanced `pos` past the format byte
  (never past the missing payload); the state is unspecified. Successful
  reads always leave `pos` immediately after the consumed value.

## Error string catalog

| Condition | Error text |
|---|---|
| Cursor past the end; not enough bytes for a format byte, header or payload | `msgpack: truncated buffer` |
| Format byte not accepted by the requested reader | `msgpack: unexpected type 0xNN` (`NN` = two lowercase hex digits, e.g. `0xc0`) |
| Reserved (unreachable): a count/length header would be negative | `msgpack: negative length` |

`msgpack: negative length` is **unreachable** in this implementation: all
MessagePack count and length headers are unsigned, so the decoder cannot
construct a negative length. It is documented here for catalog completeness
only.

## Complexity

| Operation | Complexity |
|---|---|
| all `msgpack_encode_*` | O(payload bytes) |
| `msgpack_reader_new` / `pos` / `remaining` / `peek_type` | O(1) |
| `msgpack_read_int` / `read_bool` / `read_array_len` / `read_map_len` | O(1) |
| `msgpack_read_str` | O(strlen) |

## Test plan

`tests/test_conformance.xi` (`module msgpack_tests`, 24 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. nil and bool encodings (`c0` / `c2` / `c3`);
2. positive fixint boundaries (0, 1, 127);
3. negative fixint boundaries (-1, -32);
4. uint8/uint16 boundaries (128, 255, 256, 65535);
5. uint32/uint64 boundaries (65536, 2^32-1, 2^32);
6. int8/int16 boundaries (-33, -128, -129, -32768);
7. int32/int64 boundaries incl. INT64_MIN;
8. fixstr encodings (empty, "abc", 31-byte payload);
9. str8 encodings (32-byte and 255-byte payloads);
10. str16 encodings (256-byte and 300-byte payloads);
11. array header encodings (fix, 16, 32);
12. map header encodings (fix, 16, 32);
13. negative / > 2^32-1 counts encode as an empty vector;
14. reader round-trips every int boundary;
15. reader round-trips str payloads (UTF-8, length boundaries);
16. reader round-trips bool; `peek_type` is non-advancing;
17. cursor position advances over an int + str + bool stream;
18. truncated int payloads are `Err`;
19. truncated str headers/payloads are `Err`;
20. wrong-type reads are `Err` with the exact `0xNN` message;
21. truncation error text and empty-reader state;
22. `read_array_len` / `read_map_len` decode fix/16/32 headers;
23. truncated array/map headers are `Err`;
24. str8/str16 round-trips at the 255/256-byte boundaries.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.msgpack
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Known limitations

- **No float64/float32.** `msgpack_encode_float64` (`0xcb`) is dropped
  because XIOM v0.61.3 has no `Int <-> Float64` bitcast intrinsic: the
  `xiom.num.float` helpers (`float_bits` / `bits_to_float`) are documented
  zero-returning stubs. The exact IEEE-754 big-endian payload cannot be
  produced in pure XIOM, and FFI is out of scope, so the function is
  intentionally omitted. Decoding `0xca`/`0xcb` returns
  `msgpack: unexpected type 0xca` / `0xcb`.
- No bin/ext/timestamp support; no recursive `Value` tree.
- Container readers return counts only; nested containers require explicit
  element reads by the caller.
- `msgpack_read_str` does not validate UTF-8.
- `uint64 > 2^63-1` decodes as the wrapped signed bit pattern.
- Header encoders silently return an empty vector for counts outside
  `0..2^32-1`.
- The reader is a plain value type; no thread safety.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_int`/`_err_int`/`_ok_str`/`_err_str`/`_ok_bool`/`_err_bool`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- All big-endian byte extraction is arithmetic (modulo/division) because
  `& 0xFF` on operands with bit 31 set miscompiles (same bug documented in
  `xiom.convert.base58`).
- `str_compare` lives in `xiom.string.compare`, not in the `xiom.string`
  umbrella; the tests import both. Str payloads are compared with
  `str_compare` (BUG 17: `==` between Str values read from a `Vec` lowers
  to a pointer compare).
- Advisory E001 ("cannot borrow as mutable while immutably borrowed") fires
  when a `&local` call is followed by a `&mut local` call in one function.
  The read-only reader accessors are routed through `_peek_byte_mut` in the
  library and through `&mut` helpers in the tests; the harness run is
  warning-free.
- Str materialization from bytes uses the stdlib
  `xiom.string.builder.sb_to_str` (single allocation, ownership transfer);
  the package itself declares no `extern "C"` blocks (no FFI).
