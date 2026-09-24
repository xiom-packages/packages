# xiom.pack

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM format-string binary packing and unpacking of
> fixed-width integer fields (`u8`/`s8`/`b8`, `u16`/`s16`, `u32`/`s32`,
> `u64`/`s64`, little- and big-endian) over in-memory `Vec[UInt8]` buffers.
> **Deps:** `xiom.std` only (`xiom.string`; the tests add `xiom.test`,
> `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`). No FFI.

## What it is

`xiom.pack` is a small, dependency-free codec in the spirit of Python's
`struct` / Ruby's `Array#pack`: a format string names the fields and their
byte order, `pack_format` writes them into a fresh `Vec[UInt8]`, and
`unpack_format` reads them back at an explicit offset. `pack_size` and
`pack_token_size` pre-size buffers, and twelve convenience appenders push a
single integer field onto an existing buffer.

Errors are deterministic strings (`Err("pack: ...")`, full catalog below).
Only integers are supported -- no floats, no strings, no nesting; see
Limitations.

## API

| Function | Returns | Description |
|---|---|---|
| `pack_format(fmt, values)` | `Result[Vec[UInt8], Str]` | Encode one `Int` per token, in order. |
| `unpack_format(fmt, data, offset)` | `Result[Vec[Int], Str]` | Decode the tokens from `data` at `offset`. |
| `pack_size(fmt)` | `Result[Int, Str]` | Total encoded byte size of `fmt`. |
| `pack_token_size(token)` | `Int` | Byte width of one token; `0` when unknown. |
| `pack_u16_le(out, v)` / `pack_u16_be(out, v)` | `()` | Append the low 2 bytes. |
| `pack_s16_le(out, v)` / `pack_s16_be(out, v)` | `()` | Append the low 2 bytes (two's complement). |
| `pack_u32_le(out, v)` / `pack_u32_be(out, v)` | `()` | Append the low 4 bytes. |
| `pack_s32_le(out, v)` / `pack_s32_be(out, v)` | `()` | Append the low 4 bytes (two's complement). |
| `pack_u64_le(out, v)` / `pack_u64_be(out, v)` | `()` | Append the low 8 bytes. |
| `pack_s64_le(out, v)` / `pack_s64_be(out, v)` | `()` | Append the low 8 bytes (two's complement). |

The appenders are **masked to width**: no range validation, higher bits are
dropped (e.g. `pack_u16_le(&out, 0x12345)` appends `45 23`).

Errors: `pack: token count mismatch`, `pack: unknown token '<token>'`,
`pack: <token> out of range`, `pack: negative offset`,
`pack: truncated data` (see `SPEC.md` for the full catalog).

## Token table

`fmt` is a sequence of tokens separated by one or more spaces; leading and
trailing spaces are ignored, so `""` and `"   "` mean zero fields.

| Token | Bytes | Accepted range | Notes |
|---|---|---|---|
| `u8` | 1 | `0 .. 255` | |
| `s8` | 1 | `-128 .. 127` | two's complement |
| `b8` | 1 | `0 .. 1` | boolean byte; decode maps any nonzero byte to `1` |
| `u16le` / `u16be` | 2 | `0 .. 65535` | least-significant byte first / last |
| `s16le` / `s16be` | 2 | `-32768 .. 32767` | two's complement |
| `u32le` / `u32be` | 4 | `0 .. 4294967295` | |
| `s32le` / `s32be` | 4 | `-2147483648 .. 2147483647` | two's complement |
| `u64le` / `u64be` | 8 | `0 .. 2^64-1` as a bit pattern | `Int -1` is `2^64-1`; decode returns that bit pattern |
| `s64le` / `s64be` | 8 | `INT64_MIN .. INT64_MAX` | two's complement |

Examples: `u16le` of `0x1234` is `34 12`; `u16be` of `0x1234` is `12 34`;
`s8` of `-1` is `ff`; `u32` of `0xffffffff` is `ff ff ff ff` in both byte
orders.

## Usage

```xi
use xiom.pack;

let fmt = "u8 u16le s32be";
var values = Vec[Int].new();
values.push(7);
values.push(0x1234);
values.push(-2);

let packed = pack_format(fmt, &values);
if packed.is_ok {
  let bytes: Vec[UInt8] = packed.value;      // 07 34 12 ff ff ff fe
  let back = unpack_format(fmt, &bytes, 0);
  if back.is_ok {
    let fields: Vec[Int] = back.value;       // 7, 0x1234, -2
  }
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.pack
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Integers only.** There is no support for floats (no IEEE-754 bitcast in
  XIOM v0.61.3), strings, byte blobs, nested records, arrays or alignment/
  padding. Only the 15 scalar tokens above are recognized.
- **Fixed widths only.** Widths are 1/2/4/8 bytes; there is no dynamic or
  arbitrary-precision integer mode.
- **`u64` is a bit pattern.** The platform `Int` is signed 64-bit, so
  `pack_format` accepts every `Int` for `u64*` and writes its 64-bit
  two's-complement pattern; decoding a value with bit 63 set returns the same
  negative `Int` (so `2^64-1` round-trips as `-1`).
- **`b8` canonicalisation.** Decoding maps any nonzero byte to `1`; only
  `0`/`1` are accepted when encoding.
- The appenders do not range-check or return a `Result`; they mask to width.
- No streaming over sockets/files: the API works on in-memory `Vec[UInt8]`.
- Not thread-safe; the functions are plain free functions over values.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
