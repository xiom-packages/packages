# xiom.base58

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) Base58 encoding/decoding over the Bitcoin
> alphabet, with Bitcoin leading-zero handling and a strict UTF-8 boundary.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex`).

## What it is

`xiom.base58` is a small, dependency-light Base58 codec. Encoders return
canonical Bitcoin-alphabet text; decoders return `Result` values with
deterministic `base58: `-prefixed error strings. Leading zero bytes map to
leading `'1'` characters and back (the Bitcoin convention), and the `Str`
helpers cross the UTF-8 boundary with strict validation.

Base58Check is intentionally out of scope: it requires a 4-byte
double-SHA-256 checksum, and SHA-256 is not available in the pinned v0.61.3
compiler.

## API

| Function | Returns | Description |
|---|---|---|
| `base58_alphabet()` | `Str` | The 58-character Bitcoin alphabet. |
| `base58_encode(data)` | `Str` | Base58 of `data`; each leading `0x00` becomes a leading `'1'`. |
| `base58_decode(s)` | `Result[Vec[UInt8], Str]` | Base58 to bytes; leading `'1'`s become `0x00` bytes. |
| `base58_is_valid(s)` | `Bool` | True when every byte is in the alphabet (empty input is valid). |
| `base58_encode_str(s)` | `Str` | Base58 of the UTF-8 bytes of `s`. |
| `base58_decode_str(s)` | `Result[Str, Str]` | Decode to `Str`; invalid UTF-8 => `Err`. |

Error catalog (all decode errors start with `base58: `):

| Message | Raised by |
|---|---|
| `base58: invalid character` | `base58_decode`, `base58_decode_str` |
| `base58: invalid UTF-8` | `base58_decode_str` |

## Alphabet

```
123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
```

The Bitcoin alphabet omits `0` (zero), `O` (uppercase o), `I` (uppercase i)
and `l` (lowercase L) to avoid visual ambiguity.

## Usage

```xi
use xiom.base58;
use xiom.io;

io.println(base58_encode_str("Hello World"));  // JxF12TrwUP45BMd

let back = base58_decode("JxF12TrwUP45BMd");
match back {
  Ok(v) => { io.println(base58_encode(&v)); },
  Err(e) => { io.println(e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.base58
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Bitcoin alphabet only.** No Flickr, Ripple or Monero alphabets; there is
  no alphabet parameter.
- **No Base58Check.** The 4-byte double-SHA-256 checksum variant is not
  implemented because SHA-256 is not available in the pinned v0.61.3
  compiler; this module is not a drop-in for checksummed Bitcoin addresses.
- **Strict decoding.** Only the 58 alphabet characters are accepted: no
  whitespace, sign, padding or alias normalization. The first invalid byte
  yields `Err("base58: invalid character")`.
- **Leading-zero semantics.** `encode({0x00})` is `"1"` and `decode("1")` is
  `{0x00}`; empty input encodes to `""` and decodes to an empty vector.
- **Non-canonical input is preserved.** Each extra leading `'1'` round-trips
  to an extra leading zero byte (`encode(decode("11"))` is `"11"`).
- **In-memory only.** No streaming reader/writer and no incremental API;
  complexity is `O(n^2)` worst case in both directions.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
