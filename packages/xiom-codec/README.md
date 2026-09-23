# xiom.codec

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) base64, base64url, base32 and hex
> encoding/decoding per RFC 4648, plus strict `Str` <-> UTF-8 byte
> conversion.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex`).

## What it is

`xiom.codec` is a small, dependency-light byte-text codec module. Encoders
return the RFC 4648 canonical form for the selected alphabet; decoders return
`Result` values with deterministic `codec: `-prefixed error strings. The
`Str` <-> byte helpers give callers a strict UTF-8 boundary (overlong forms,
surrogates and code points above U+10FFFF are rejected).

## API

| Function | Returns | Description |
|---|---|---|
| `codec_str_to_bytes(s)` | `Vec[UInt8]` | UTF-8 bytes of `s`, verbatim. |
| `codec_bytes_to_str(data)` | `Result[Str, Str]` | Strict UTF-8 decode; `Err("codec: invalid UTF-8")` on malformed input. |
| `codec_b64_encode(data)` | `Str` | RFC 4648 section 4: `A-Z a-z 0-9 + /`, `=` padded. |
| `codec_b64_decode(s)` | `Result[Vec[UInt8], Str]` | Standard alphabet; ASCII whitespace ignored; well-formed or absent padding. |
| `codec_b64url_encode(data)` | `Str` | RFC 4648 section 5: `A-Z a-z 0-9 - _`, NO padding. |
| `codec_b64url_decode(s)` | `Result[Vec[UInt8], Str]` | Accepts `-`/`_` and `+`/`/`; padding optional. |
| `codec_base32_encode(data)` | `Str` | RFC 4648 section 6: `A-Z 2-7`, `=` padded to a multiple of 8. |
| `codec_base32_decode(s)` | `Result[Vec[UInt8], Str]` | Case-insensitive; padding optional; invalid => `Err`. |
| `codec_hex_encode(data)` | `Str` | Lowercase hex, two digits per byte. |
| `codec_hex_decode(s)` | `Result[Vec[UInt8], Str]` | Case-insensitive; odd length or non-hex => `Err`. |

Error catalog (all decode errors start with `codec: `):

| Message | Raised by |
|---|---|
| `codec: invalid UTF-8` | `codec_bytes_to_str` |
| `codec: invalid base64 character` | `codec_b64_decode`, `codec_b64url_decode` |
| `codec: invalid base64 padding` | `codec_b64_decode`, `codec_b64url_decode` |
| `codec: invalid base32 character` | `codec_base32_decode` |
| `codec: invalid base32 padding` | `codec_base32_decode` |
| `codec: invalid hex character` | `codec_hex_decode` |
| `codec: odd-length hex input` | `codec_hex_decode` |

## Usage

```xi
use xiom.codec;
use xiom.io;

let bytes = codec_str_to_bytes("foobar");
io.println(codec_b64_encode(&bytes));       // Zm9vYmFy
io.println(codec_b64url_encode(&bytes));    // Zm9vYmFy
io.println(codec_base32_encode(&bytes));    // MZXW6YTBOI======
io.println(codec_hex_encode(&bytes));       // 666f6f626172

let back = codec_b64_decode("Zm9vYmFy");
match back {
  Ok(v) => {
    let txt = codec_bytes_to_str(&v);
    if txt.is_ok { io.println(txt.value); }   // foobar
  },
  Err(e) => { io.println(e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.codec
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a
final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **RFC 4648 only.** No MIME base64 (no line breaks), no bcrypt/XX/crypt
  variants, no Crockford base32, no base32hex.
- **No streaming.** All functions work on in-memory `Vec[UInt8]`/`Str`
  values; there is no reader/writer cursor and no incremental API.
- **Padding is optional on decode** (all four decoders): explicit `=` must
  be well-formed and complete the final quantum, but correctly sized input
  without padding is accepted. Trailing bits of a partial tail are ignored,
  so non-canonical encodings decode (documented in SPEC.md).
- **Whitespace** is ignored by the base64/base64url decoders only (TAB, LF,
  VT, FF, CR, space). Base32 and hex decoders reject whitespace.
- **Hex** accepts no `0x` prefix, separators or `:` (MAC-style) forms.
- **UTF-8 conversion is strict and total**: any byte string is accepted by
  `codec_str_to_bytes`, but `codec_bytes_to_str` rejects malformed UTF-8
  rather than repairing it (no lossy replacement).
- **Empty input** encodes to `""` and decodes to an empty `Vec[UInt8]`.
- Pure XIOM: no FFI, no file I/O, no registry integration.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
