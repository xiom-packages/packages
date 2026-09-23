# xiom.codec -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.codec`, version `0.1.0`).
Module: `src/codec.xi` (`module xiom.codec`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`). No FFI.

## 1. Scope

Ten free functions over `Vec[UInt8]` and `Str`:

```xi
pub fn codec_str_to_bytes(s: Str) -> Vec[UInt8]
pub fn codec_bytes_to_str(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn codec_b64_encode(data: &Vec[UInt8]) -> Str
pub fn codec_b64_decode(s: Str) -> Result[Vec[UInt8], Str]
pub fn codec_b64url_encode(data: &Vec[UInt8]) -> Str
pub fn codec_b64url_decode(s: Str) -> Result[Vec[UInt8], Str]
pub fn codec_base32_encode(data: &Vec[UInt8]) -> Str
pub fn codec_base32_decode(s: Str) -> Result[Vec[UInt8], Str]
pub fn codec_hex_encode(data: &Vec[UInt8]) -> Str
pub fn codec_hex_decode(s: Str) -> Result[Vec[UInt8], Str]
```

All scanning is byte-wise. Every raw byte read through `xiom.string.byte_at`
(or a `Vec[UInt8]` element) is widened to `Int` with the `& 0xFF` mask before
comparisons and arithmetic. Complexity is O(n) over the input length for
every function; encoding performs one final allocation per result `Str`
(`xiom.string.builder.sb_to_str`).

## 2. Alphabets

| Codec | Alphabet | Padding on encode | Case on decode |
|---|---|---|---|
| base64 (RFC 4648 §4) | `A-Z a-z 0-9 + /` | `=` to a multiple of 4 | exact |
| base64url (RFC 4648 §5) | `A-Z a-z 0-9 - _` | none | exact |
| base32 (RFC 4648 §6) | `A-Z 2-7` | `=` to a multiple of 8 | case-insensitive |
| hex | `0-9 a-f` | n/a | case-insensitive |

Value maps: base64 `A-Z`=0..25, `a-z`=26..51, `0-9`=52..61, `+`/`-`=62,
`/`/`_`=63; base32 `A-Z`/`a-z`=0..25, `2`..`7`=26..31; hex `0-9`/`a-f`/
`A-F`=0..15.

`codec_b64url_decode` accepts BOTH `-`/`_` and `+`/`/` (cross-decoding).
`codec_b64_decode` accepts only the standard `+`/`/`.

## 3. Encoding rules

- `codec_b64_encode`: 3-byte groups become 4 characters; a 1-byte tail
  becomes 2 characters + `==`; a 2-byte tail becomes 3 characters + `=`.
- `codec_b64url_encode`: same grouping, `-`/`_` alphabet, no padding
  (output length `4*floor(n/3)` + 2 or 3 for a 1- or 2-byte tail).
- `codec_base32_encode`: 5-byte groups become 8 characters; the output is
  always padded with `=` to a multiple of 8 characters.
- `codec_hex_encode`: two lowercase digits per byte.
- Empty input encodes to `""` for all four encoders.
- Encoders are total (no error case) and never validate their input.

## 4. Decoding rules

Common validation (all four decoders):

1. `=` is only legal in a trailing run; a data character after `=` is
   `codec: invalid <codec> padding`.
2. When padding is present it must complete the final quantum, i.e.
   `(data_len + pad) % quantum == 0` and the pad count must match the data
   tail (base64: 3+1 or 2+2; base32: 7+1, 5+3, 4+4 or 2+6).
3. Base64 data lengths of 1 (mod 4) and base32 data lengths of 1, 3 or 6
   (mod 8) are impossible and rejected.
4. Padding is **optional**: unpadded input with a valid tail is accepted
   (e.g. `"Zg"` and `"MY"`).
5. Trailing bits of a partial tail are ignored, so non-canonical encodings
   decode to the same bytes as their canonical form (documented limitation;
   the decoders do not enforce strict RFC 4648 canonical trailing bits).

Per codec:

- `codec_b64_decode` / `codec_b64url_decode`: ASCII whitespace (TAB 9,
  LF 10, VT 11, FF 12, CR 13, space 32) is ignored anywhere in the input.
- `codec_base32_decode`: case-insensitive; whitespace is NOT ignored.
- `codec_hex_decode`: even length required; whitespace and separators are
  NOT ignored; empty input yields `Ok(empty)`.

Decoded bytes are never UTF-8 validated; use `codec_bytes_to_str` at the
boundary.

## 5. Str <-> bytes

- `codec_str_to_bytes(s)` returns the raw UTF-8 bytes of `s` (identity
  mapping, total).
- `codec_bytes_to_str(data)` validates `data` against RFC 3629 before
  copying. Rejected: stray continuation bytes (0x80-0xBF), invalid lead
  bytes (0xC0, 0xC1, 0xF5-0xFF), truncated sequences, overlong forms
  (`C0 80`, `E0 80 80`, `F0 80 80 80`, ...), UTF-16 surrogates
  (`ED A0 80`-`ED BF BF`) and code points above U+10FFFF (`F4 90+`).

## 6. Error catalog

All decode errors start with the literal prefix `codec: `; they are produced
only by the four decoders and by `codec_bytes_to_str`.

| Message | Trigger |
|---|---|
| `codec: invalid UTF-8` | `codec_bytes_to_str`: malformed UTF-8 as above. |
| `codec: invalid base64 character` | `codec_b64_decode`/`codec_b64url_decode`: byte outside the accepted alphabet (after whitespace removal). |
| `codec: invalid base64 padding` | `codec_b64_decode`/`codec_b64url_decode`: data after `=`, pad > 2, `(core+pad) % 4 != 0`, or a data tail of 1 (mod 4). |
| `codec: invalid base32 character` | `codec_base32_decode`: byte outside `A-Z a-z 2-7`. |
| `codec: invalid base32 padding` | `codec_base32_decode`: data after `=`, pad not in {1,3,4,6} or not completing the 8-character quantum, or a data tail in 1/3/6 (mod 8). |
| `codec: invalid hex character` | `codec_hex_decode`: byte outside `0-9 a-f A-F`. |
| `codec: odd-length hex input` | `codec_hex_decode`: odd `s.len()`. |

## 7. Test plan

`tests/test_conformance.xi` (module `codec_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Expected byte vectors are built with the stdlib
`xiom.encoding.hex` decoder; all Str equality uses
`xiom.string.compare.str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | base64 encode vectors | `""`, `f`->`Zg==`, `fo`->`Zm8=`, `foo`->`Zm9v`, `foobar`->`Zm9vYmFy` |
| t2 | base64 decode vectors | inverse of t1 including empty input |
| t3 | base64 round-trip | lengths 0..8, deterministic bytes incl. >= 0x80 |
| t4 | base64 padding errors | `Zg=`, `Zg===`, `=`, `Zm9v=`, data-after-pad `Zg==Zg==`, `Z=Z` |
| t5 | base64 invalid chars | `!`, `$`, `.`, `-` (standard) and a non-ASCII byte are Err |
| t6 | base64 whitespace | whitespace anywhere is ignored (` Zm9v `, CRLF, tab/newline runs) |
| t7 | base64 optional padding | empty -> Ok empty; `Zg`, `Zm8` decode |
| t8 | base64url encode | no padding; `[fb ef be]`->`----` vs standard `++++`; `[ff]`->`_w` |
| t9 | base64url decode | both alphabets (`----` and `++++`), padded and unpadded |
| t10 | base64url errors | bad char, bad padding, `====`, standard-only chars rejected by standard decode |
| t11 | base32 encode vectors | `f`->`MY======`, `fo`->`MZXQ====`, `foo`->`MZXW6===`, `foobar`->`MZXW6YTBOI======` |
| t12 | base32 decode vectors | inverse of t11 including empty input |
| t13 | base32 case-insensitive | all-lower and mixed-case decode |
| t14 | base32 optional padding | `MY`, `MZXQ`, `MZXW6`, `MZXW6YTB`, `MZXW6YTBOI` |
| t15 | base32 errors | `M`, `MY=`, `MY=====`, data-after-pad, `M1`, `MY!`, `========` |
| t16 | base32 round-trip | lengths 0..8 |
| t17 | hex encode | lowercase output, empty input, high bytes (`000f10ff`) |
| t18 | hex decode | upper, lower, mixed, empty input |
| t19 | hex errors | odd length (`abc`, `0`), non-hex (`0g`, `zz`), embedded space |
| t20 | hex round-trip | lengths 0..8 |
| t21 | bytes_to_str valid | empty, ASCII, 2-byte `é`, 4-byte U+1F600 (length 4) |
| t22 | bytes_to_str invalid | `ff`, `80`, truncated `c3`, surrogate `eda080`, overlong `f0808080` |
| t23 | str_to_bytes | `A`->`41`, empty, `é`->`c3a9`, `foobar` bytes |
| t24 | full pipeline | str -> bytes -> all four codecs -> bytes -> str round trip |

## 8. Known limitations

- **No canonical-form enforcement.** Non-zero trailing bits in a partial
  tail are accepted (e.g. `Zh==` decodes to `f`); encoders always emit the
  canonical form.
- **No strict-padding mode.** Callers that require padded input must check
  the encoded length themselves; decoders accept unpadded input by design.
- **No streaming, no in-place decode**; everything is in-memory.
- **base64url decode accepts standard characters** (`+`, `/`); it is not a
  strict base64url-only parser.
- **Whitespace policy differs by codec** (base64 family ignores it, base32
  and hex do not).
- **No lossy UTF-8 repair** (`codec_bytes_to_str` never substitutes
  U+FFFD).
- **Local UTF-8 validator.** `xiom.utf8.utf8_validate` in the pinned
  v0.61.3 stdlib accepts stray bytes >= 0x80 (e.g. `0xFF` or a lone `0x80`)
  as 1-byte "ASCII" sequences; this module therefore carries a strict local
  RFC 3629 validator instead of delegating to it.

## 9. Compiler / stdlib notes

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch, no `Vec[Float64]`.
- `Ok`/`Err` for the `Result`-returning functions are constructed only in
  the leaf helpers `_ok_str`/`_err_str`/`_ok_bytes`/`_err_bytes`.
- Bytes read from `Vec[UInt8]` or `byte_at` are always widened with
  `(x as Int) & 0xFF` before comparison/arithmetic.
- Int values read from `Vec[Int]` are bound with explicit `let v: Int = ...`.
- No `==` on `Str` values anywhere (tests route every comparison through
  `str_compare`, BUG 17).
