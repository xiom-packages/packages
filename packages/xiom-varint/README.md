# xiom.varint

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM unsigned LEB128 varints and zigzag signed varints
> over in-memory `Vec[UInt8]` buffers, with encoded-size and canonicality
> helpers.
> **Deps:** `xiom.std` only (the module itself imports nothing; the tests add
> `xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`).
> No FFI.

## What it is

`xiom.varint` is a small, dependency-free codec for LEB128 varints:

- **unsigned LEB128** (`varint_encode_u` / `varint_decode_u`) with a
  maximum of 10 bytes, covering the full 64-bit domain;
- **zigzag signed varints** (`varint_encode_zigzag` /
  `varint_decode_zigzag`) mapping `0, -1, 1, -2, 2, ...` to
  `0, 1, 2, 3, 4, ...` before LEB128 encoding;
- **size and canonicality helpers** (`varint_size_u`,
  `varint_is_canonical_u`) for pre-sizing buffers and rejecting overlong
  forms such as `0x80 0x00`.

Encoders are pure functions returning fresh `Vec[UInt8]` values; decoders
read a `&Vec[UInt8]` at an explicit offset and return
`Result[(value, next offset), Str]` with deterministic error strings.
See `SPEC.md` for the byte-level rules and the full error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `varint_encode_u(n)` | `Vec[UInt8]` | Unsigned LEB128 of `n`; empty for `n < 0`. |
| `varint_encode_zigzag(n)` | `Vec[UInt8]` | Zigzag LEB128 of signed `n`. |
| `varint_decode_u(data, off)` | `Result[(Int, Int), Str]` | Unsigned value and next offset at `off`. |
| `varint_decode_zigzag(data, off)` | `Result[(Int, Int), Str]` | Zigzag value and next offset at `off`. |
| `varint_size_u(n)` | `Int` | Encoded byte count; `0` for `n < 0`. |
| `varint_is_canonical_u(data, off)` | `Bool` | True when the encoding at `off` is minimal. |

Errors: `Err("varint: negative offset")`,
`Err("varint: truncated")`, `Err("varint: overflow")` (full catalog in
`SPEC.md`).

## Encoding table

Unsigned LEB128: 7 payload bits per byte, least significant group first,
bit 7 is the continuation flag.

| Value | Encoded bytes |
|---|---|
| `0` | `00` |
| `1` | `01` |
| `127` | `7f` |
| `128` | `80 01` |
| `300` | `ac 02` |
| `624485` | `e5 8e 26` |
| `2^32-1` | `ff ff ff ff 0f` |
| `2^63-1` | `ff ff ff ff ff ff ff ff 7f` |

Zigzag maps signed values to unsigned before LEB128:
`zigzag(n) = 2n` for `n >= 0`, `zigzag(n) = -2n - 1` for `n < 0`.

| Signed value | Zigzag | Encoded bytes |
|---|---|---|
| `0` | `0` | `00` |
| `-1` | `1` | `01` |
| `1` | `2` | `02` |
| `-2` | `3` | `03` |
| `2` | `4` | `04` |
| `INT64_MAX` | `2^64-2` | `fe ff ff ff ff ff ff ff ff 01` |
| `INT64_MIN` | `2^64-1` | `ff ff ff ff ff ff ff ff ff 01` |

## Usage

```xi
use xiom.varint;

let bytes = varint_encode_zigzag(-300);   // 2 bytes
let r = varint_decode_zigzag(&bytes, 0);
if r.is_ok {
  let pair = r.value;
  let value: Int = pair.0;                // -300
  let next: Int = pair.1;                 // 2
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.varint
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **64-bit domain only.** Unsigned values are limited to 64 bits: decoding
  a value with bit 63 set returns the same two's-complement bit pattern
  interpreted as a signed `Int` (the platform `Int` is signed 64-bit), and
  encodings that would need more than 10 bytes are rejected with
  `varint: overflow`. There is no `uint128`/arbitrary-precision mode.
- **No signed LEB128 variants** (the DWARF/WebAssembly *signed* LEB128
  encoding used for signed integers of unbounded width). Only unsigned
  LEB128 and zigzag are provided; signed inputs must go through
  `varint_encode_zigzag` / `varint_decode_zigzag`.
- `varint_encode_u` has no error channel: `n < 0` returns an empty vector
  and `varint_size_u` returns 0.
- Non-minimal encodings are accepted by the decoders; callers who need
  canonical form must check `varint_is_canonical_u`.
- Not thread-safe; the functions are plain free functions over values.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
