# xiom.msgpack

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM MessagePack encoding and decoding for the supported
> subset: nil, bool, Int, Str, and array/map headers.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`).
> No FFI.

## What it is

`xiom.msgpack` is a minimal, dependency-light MessagePack codec. Encoders
return the exact minimal byte encoding for each value; the decoder is a
cursor (`MsgpackReader`) over a `Vec[UInt8]` that returns `Result` values
with deterministic error strings. Binaries, extension types, floats and
container *elements* are out of scope (see Limitations).

## API

| Function | Returns | Description |
|---|---|---|
| `msgpack_encode_nil()` | `Vec[UInt8]` | `0xc0`. |
| `msgpack_encode_bool(b)` | `Vec[UInt8]` | `0xc2` / `0xc3`. |
| `msgpack_encode_int(n)` | `Vec[UInt8]` | Minimal int: fixint, uint8/16/32/64, int8/16/32/64. |
| `msgpack_encode_str(s)` | `Vec[UInt8]` | fixstr / str8 / str16 / str32 header + UTF-8 bytes. |
| `msgpack_encode_array_header(n)` | `Vec[UInt8]` | fixarray / array16 / array32 count header. |
| `msgpack_encode_map_header(n)` | `Vec[UInt8]` | fixmap / map16 / map32 count header. |
| `msgpack_reader_new(data)` | `MsgpackReader` | Cursor at position 0. |
| `msgpack_reader_pos(r)` | `Int` | Bytes consumed so far. |
| `msgpack_reader_remaining(r)` | `Int` | Unread bytes. |
| `msgpack_read_int(&mut r)` | `Result[Int, Str]` | fixint / uint8-64 / int8-64. |
| `msgpack_read_str(&mut r)` | `Result[Str, Str]` | fixstr / str8 / str16 / str32 (payload bytes verbatim). |
| `msgpack_read_bool(&mut r)` | `Result[Bool, Str]` | `0xc2` / `0xc3`. |
| `msgpack_read_array_len(&mut r)` | `Result[Int, Str]` | Array element count from the header. |
| `msgpack_read_map_len(&mut r)` | `Result[Int, Str]` | Map pair count from the header. |
| `msgpack_peek_type(r)` | `Result[Int, Str]` | Raw format byte without advancing. |

Errors: `Err("msgpack: truncated buffer")`,
`Err("msgpack: unexpected type 0xNN")` (see SPEC.md for the full catalog).

## Usage

```xi
use xiom.msgpack;
use xiom.io;

let bytes = msgpack_encode_int(300);          // cd 01 2c
var r = msgpack_reader_new(bytes);
let v = msgpack_read_int(&mut r);             // Ok(300)
match v {
  Ok(n) => { io.println("value: " + xiom.convert.int_to_string(n)); },
  Err(e) => { io.println("decode error: " + e); },
}
io.println("remaining: " + xiom.convert.int_to_string(msgpack_reader_remaining(&r))); // 0
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.msgpack
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a
final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No float32/float64.** `msgpack_encode_float64` (`0xcb`) is intentionally
  NOT implemented: XIOM v0.61.3 has no `Int <-> Float64` bitcast intrinsic
  (`xiom.num.float` is a documented zero-returning stub), so the exact
  IEEE-754 big-endian payload cannot be produced without FFI. Decoding
  `0xca`/`0xcb` is likewise rejected as an unexpected type.
- **No bin (0xc4/0xc5/0xc6), ext (0xc7-0xc9, 0xd4-0xd8), or timestamps.**
- **No float format bytes, no reserved 0xc1.**
- Container **elements are not decoded**: `msgpack_read_array_len` /
  `msgpack_read_map_len` consume only the header and return the count; the
  caller reads the elements with the appropriate `msgpack_read_*` calls.
- Array/map counts are limited to 2^32-1; a negative or larger count passed
  to a header encoder yields an empty `Vec` (there is no byte encoding).
- `msgpack_read_str` copies payload bytes verbatim and does not validate
  UTF-8 (matching the `xiom.encoding.hex` decode precedent).
- `uint64` payloads above 2^63-1 wrap to the same two's-complement `Int`
  bit pattern (the platform `Int` is signed 64-bit).
- `msgpack: negative length` is part of the documented error catalog but is
  unreachable: no MessagePack count or length header carries a sign.
- Not thread-safe; readers are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
