# xiom.base58 -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.base58`, version `0.1.0`).
Module: `src/base58.xi` (`module xiom.base58`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`). No FFI.

## 1. Scope

Six free functions over `Vec[UInt8]` and `Str`:

```xi
pub fn base58_alphabet() -> Str
pub fn base58_encode(data: &Vec[UInt8]) -> Str
pub fn base58_decode(s: Str) -> Result[Vec[UInt8], Str]
pub fn base58_is_valid(s: Str) -> Bool
pub fn base58_encode_str(s: Str) -> Str
pub fn base58_decode_str(s: Str) -> Result[Str, Str]
```

All scanning is byte-wise. Every raw byte read through `xiom.string.byte_at`
or from a `Vec[UInt8]` is widened to `Int` with the `& 0xFF` mask before
comparisons and arithmetic. Complexity is `O(n^2)` worst case for encode and
decode (long division / multiply-add over the whole buffer per digit);
`base58_is_valid` is `O(n * 58)` worst case (alphabet scan per character).

## 2. Alphabet

```
123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
```

58 characters. Value map: `1`..`9` = 0..8, `A`..`Z` (minus `I`, `O`) =
9..32, `a`..`z` (minus `l`) = 33..57. The characters `0`, `O`, `I` and `l`
are not representable; any other byte (including ASCII whitespace, `+`, `/`
and non-ASCII bytes) is invalid.

## 3. Base58Check is out of scope

Base58Check appends a 4-byte double-SHA-256 checksum to the payload.
SHA-256 is not available in the pinned v0.61.3 compiler (32-bit bitwise ops
with the high bit set miscompile and there is no bitcast intrinsic), so this
package implements raw Base58 only. The stdlib `xiom.convert.base58`
module's `base58check_*` functions use an Adler-32 fallback and are likewise
not Bitcoin-interoperable.

## 4. Encoding

`base58_encode(data)` treats `data` as a big-endian unsigned integer:

1. Count the leading `0x00` bytes (`zeros`).
2. Copy the bytes into a working `Vec[Int]`.
3. Starting at the first non-zero byte, repeatedly long-divide the working
   value by 58, collecting the remainders (least significant digit first)
   and trimming leading zero bytes after each pass until the remaining
   prefix is zero.
4. Emit `zeros` copies of `'1'` (alphabet index 0), then the collected
   remainders from most to least significant.

Properties:

- `encode({})` = `""`.
- Each leading `0x00` byte yields exactly one leading `'1'`.
- The all-zero input `{0, ..., 0}` (n bytes) encodes to `"1"` repeated n
  times.
- Minimal length: the most significant emitted digit is never alphabet index
  0 unless the value is zero (in which case only the leading-zero run is
  emitted).
- Total: no error case; the encoder never validates its input.

## 5. Decoding

`base58_decode(s)`:

1. Count the leading `'1'` characters (`zeros`).
2. For every remaining character, map it to its alphabet value; an unknown
   byte returns `Err("base58: invalid character")`.
3. Accumulate `value = value * 58 + digit` in little-endian base-256 space
   (one multiply-add pass per digit over the accumulator).
4. Emit `zeros` copies of `0x00`, then the accumulator bytes from most to
   least significant (no leading zero bytes).

Properties:

- `decode("")` = `Ok({})`.
- `decode("1")` = `Ok({0x00})`; `decode("111")` = `Ok({0x00, 0x00, 0x00})`.
- `decode("2")` = `Ok({0x01})`.
- The accumulator invariant keeps every partial product below
  `256 * 58 + 57`, so no `& 0xFF` widening of a high-bit value is ever
  performed.
- Non-canonical inputs are accepted: leading `'1'` runs are preserved
  verbatim, i.e. `decode(s)` is exact about the encoded byte count.

## 6. UTF-8 boundary

- `base58_encode_str(s)` copies the raw UTF-8 bytes of `s` and runs
  `base58_encode` (total; never fails).
- `base58_decode_str(s)` decodes first (invalid base58 propagates
  `Err("base58: invalid character")`), then validates the decoded bytes as
  RFC 3629 UTF-8 before constructing the `Str`. Rejected: stray continuation
  bytes (0x80-0xBF), invalid lead bytes (0xC0, 0xC1, 0xF5-0xFF), truncated
  sequences, overlong forms, UTF-16 surrogates (`ED A0 80`-`ED BF BF`) and
  code points above U+10FFFF. Failures return `Err("base58: invalid UTF-8")`.
- The validator is local (see the module header) because
  `xiom.utf8.utf8_validate` in the pinned v0.61.3 stdlib accepts stray bytes
  >= 0x80 as 1-byte "ASCII" sequences.

## 7. Error catalog

| Message | Trigger |
|---|---|
| `base58: invalid character` | `base58_decode` / `base58_decode_str`: any byte outside the 58-character alphabet. |
| `base58: invalid UTF-8` | `base58_decode_str`: decoded bytes are not well-formed RFC 3629 UTF-8. |

## 8. Test plan

`tests/test_conformance.xi` (module `base58_tests`) runs 18 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Expected byte vectors are built with the stdlib
`xiom.encoding.hex` decoder; all Str equality uses
`xiom.string.compare.str_compare`. Pinned vectors were cross-checked against
an independent big-integer implementation.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | empty input | `encode({})` = `""`; `decode("")` = `Ok({})` |
| t2 | single zero | `{0}` <-> `"1"` |
| t3 | two/three zeros | `{0,0}` <-> `"11"`; `{0,0,0}` -> `"111"` |
| t4 | single-byte vectors | `{1}` <-> `"2"`, `{0xFF}` <-> `"5Q"`, `{0x01,0x00}` -> `"5R"`, `{0x3A}` <-> `"21"` |
| t5 | known vector | UTF-8 `"Hello World"` <-> `"JxF12TrwUP45BMd"` |
| t6 | genesis sample | the 32 bytes of the Bitcoin genesis block hash `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f` -> `"111114VYJtj3yEDffZem7N3PkK563wkLZZ8RjKzcfY"`, plus round-trip |
| t7 | round-trip | lengths 0..8, deterministic bytes incl. >= 0x80 |
| t8 | leading zeros | `{0,1}` -> `"12"`, `{0,0,1}` -> `"112"`, `{0,0,0,1}` -> `"1112"`, `{0,0,0,0,1}` -> `"11112"` and inverse |
| t9 | invalid characters | `0`, `O`, `I`, `l`, `abc0`, space, `+`, `/` are Err |
| t10 | error message | Err text is exactly `base58: invalid character` |
| t11 | is_valid true | `""`, `"1"`, `"2"`, `"z"`, the known vector, the whole alphabet |
| t12 | is_valid false | `0`, `O`, `I`, `l`, `!`, embedded space, non-ASCII `é` |
| t13 | unicode round-trip | `"héllo 😀"` -> `"Syn5qUMrqzd8brf"` and back; `decode_str("")` = `Ok("")` |
| t14 | alphabet | the exact 58-character Bitcoin alphabet and its length |
| t15 | 58-value map | every one-byte value 0..57 encodes to its alphabet character and decodes back |
| t16 | multi-byte vectors | `{0x00,0xFF}` <-> `"15Q"`, `{0xFF,0xFF}` <-> `"LUv"`, `{0x01,0x02,0x03}` <-> `"Ldp"` |
| t17 | decode_str errors | invalid base58 -> `base58: invalid character`; byte sequences `0x80`, `0xC3`, `0xFF`, `0x80 0x81` -> `base58: invalid UTF-8` |
| t18 | 64-byte round-trip | deterministic 64-byte buffer pinned to `"9KSiV2hovo6nC4yQD2LjwhaxrdNeqfNamM5RWSsZ8BrM7mguAmXP5dzvXA95ZkmWZDeWLrxnwEjSzG3k4tj36iM"` |

## 9. Known limitations

- **Bitcoin alphabet only**: no alphabet parameter, no alternative alphabets.
- **No Base58Check**: no checksum and no version byte (section 3).
- **Strict input**: no whitespace trimming, no case folding, no alias
  normalization.
- **No canonical enforcement beyond leading zeros**: every alphabet string
  decodes; leading `'1'` runs are preserved verbatim.
- **`O(n^2)` encode/decode**, in-memory only, no streaming API.
- **Local strict UTF-8 validator** (section 6).

## 10. Compiler / stdlib notes

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch.
- `Ok`/`Err` for the `Result`-returning functions are constructed only in the
  leaf helpers `_ok_bytes`/`_err_bytes`/`_ok_str`/`_err_str`.
- Bytes read from `Vec[UInt8]` or `byte_at` are always widened with
  `(x as Int) & 0xFF` before comparison/arithmetic.
- Int values read from `Vec[Int]` are bound with explicit `let v: Int = ...`.
- No `==` on `Str` values anywhere (tests route every comparison through
  `str_compare`, BUG 17).
- A reference to a `Result` field (`&dec.value`) passed directly into a
  `&Vec[UInt8]` parameter makes the callee see an empty vector; the field is
  bound to a local first (`base58_decode_str`).
