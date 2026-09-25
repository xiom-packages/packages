# xiom.base32

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) RFC 4648 Base32 encoding/decoding over the
> standard alphabet (`A-Z`, `2-7`) with canonical `=` padding, strict
> validation and case-insensitive decoding.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex`).

## What it is

`xiom.base32` is a small, dependency-light RFC 4648 Base32 codec. Every
function is a free function over flat byte vectors: encoders return canonical
`A-Z2-7` text padded with `=` to a multiple of 8 characters, and the decoder
returns `Result[Vec[UInt8], Str]` with deterministic `base32: `-prefixed error
strings. Decoding accepts lowercase as the same digits and rejects
non-canonical input: unpadded partial groups, misplaced or miscounted `=`
runs, and groups whose unused trailing bits are not zero.

Base32hex (RFC 4648 section 7) is deliberately out of scope, as are base64
and hex (sibling packages own those) and any streaming API.

## Install / use

```
xiom pkg install xiom.base32@0.1.0
```

```xi
use xiom.base32;
use xiom.io;

// Encode: UTF-8 bytes of "foobar" -> "MZXW6YTBOI======"
let bytes = ...;                       // Vec[UInt8]
io.println(base32_encode(&bytes));

match base32_decode("MZXW6YTBOI======") {
  Ok(v)  => { io.println("ok: " + v.len() + " bytes"); },
  Err(e) => { io.println(e); },
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `base32_alphabet()` | `Str` | The 32-character RFC 4648 alphabet `ABCDEFGHIJKLMNOPQRSTUVWXYZ234567`. |
| `base32_encode(data)` | `Str` | Canonical Base32 of `data`, padded with `=` to a multiple of 8 characters. |
| `base32_decode(s)` | `Result[Vec[UInt8], Str]` | Base32 to bytes; strict, case-insensitive, canonical padding required. |
| `base32_is_valid(s)` | `Bool` | True when `base32_decode(s)` would return `Ok` (empty input included). |

## Alphabet and padding

Standard RFC 4648 alphabet, in value order:

```
A B C D E F G H I J K L M N O P Q R S T U V W X Y Z 2 3 4 5 6 7
0 1 2 3 4 5 6 7 8 9 ... 24 25 26 27 28 29 30 31
```

- 5 input bytes become 8 characters; a message is encoded as a whole sequence
  of such groups.
- A final partial group of 1/2/3/4 bytes becomes 2/4/5/7 characters followed
  by 6/4/3/1 `=` characters, so the encoded length is always
  `8 * ceil(n / 5)`. Empty input encodes to `""`.
- The decoder requires that canonical padding: `"MZXW6==="` is valid,
  `"MZXW6"` is `Err("base32: truncated group")`. Input made only of whole
  groups carries no padding (`"MZXW6YTB"` is valid).
- Decoding is case-insensitive: `a-z` map to the same values as `A-Z`
  (RFC 4648 section 6).
- The unused low bits of the final group must be zero; `"MZ======"` is
  `Err("base32: non-canonical trailing bits")`.

## Error model

All decode errors start with the literal prefix `base32: ` and are produced
only by `base32_decode` (and therefore by `base32_is_valid` returning
`false`). Characters are validated left to right, so the first offending
byte decides the message.

| Message | Trigger |
|---|---|
| `base32: invalid character` | Byte outside `A-Z`/`a-z`/`2-7`/`=` (including whitespace), or a non-alphabet byte after the first `=`. |
| `base32: invalid padding position` | An alphabet character after the first `=`. |
| `base32: bad padding count` | `=` present but not exactly 6/4/3/1 for a final group of 2/4/5/7 data characters; `=` after whole groups; leading `=`; total length not a multiple of 8 with padding. |
| `base32: truncated group` | No `=`, and the data length is not a multiple of 8 (unpadded partial group). |
| `base32: non-canonical trailing bits` | The unused low bits of the final group are not zero. |

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.base32
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Standard alphabet only.** No base32hex (RFC 4648 section 7), no z-base-32
  and no custom alphabet parameter.
- **Padding is required for partial groups.** Unpadded tails such as
  `"MZXW6"` are rejected; only whole-group input is unpadded, exactly as the
  RFC emits it.
- **Strict input.** No whitespace skipping, no `-`/`_` aliases, no
  normalization. Digits `0`, `1`, `8`, `9` are invalid characters.
- **Non-canonical encodings are rejected**, not silently normalized: trailing
  bits must be zero and the `=` count must be exact.
- **Bytes only.** There are no `Str`/UTF-8 convenience helpers; callers decode
  to `Vec[UInt8]` and cross the UTF-8 boundary themselves.
- **In-memory only.** No streaming reader/writer and no incremental API;
  every function is O(n) and allocates the whole result.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
