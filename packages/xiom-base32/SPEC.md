# xiom.base32 -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.base32`, version `0.1.0`).
Module: `src/base32.xi` (`module xiom.base32`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`). No FFI.

## 1. Scope

Four free functions over flat `Vec[UInt8]` and `Str` values:

```xi
pub fn base32_alphabet() -> Str
pub fn base32_encode(data: &Vec[UInt8]) -> Str
pub fn base32_decode(s: Str) -> Result[Vec[UInt8], Str]
pub fn base32_is_valid(s: Str) -> Bool
```

All scanning is byte-wise via `xiom.string.byte_at`. Every raw byte is widened
with `(x as Int) & 0xFF` before comparisons or arithmetic. No bitwise shifts
are used anywhere: 40-bit groups are assembled and split with multiplication,
division and modulo. Every function is O(n) and allocates its result in
memory.

## 2. Non-goals

- **No base32hex** (RFC 4648 section 7) and no other alphabet variant
  (z-base-32, Crockford). The alphabet is fixed to `A-Z2-7`.
- **No streaming/incremental API**: whole-value encode/decode only.
- **No base64 or hex**: sibling packages own those codecs.
- **No `Str`/UTF-8 convenience helpers**: the API is bytes-only; callers own
  the UTF-8 boundary.
- **No whitespace tolerance, no aliases, no auto-normalization**: input is
  strict and canonical.

## 3. Alphabet

RFC 4648 section 6 "base32" uses 32 characters in value order:

```
A B C D E F G H I J K L M N O P Q R S T U V W X Y Z 2 3 4 5 6 7
0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
```

- `A`..`Z` are values 0..25; `2`..`7` are values 26..31.
- `=` (0x3D) is the pad character, never a digit.
- Decoding is case-insensitive: `a`..`z` map to the same values as `A`..`Z`.
- Bytes outside `A-Z`, `a-z`, `2-7` and `=` are invalid characters.
  In particular `0`, `1`, `8`, `9` and all whitespace are invalid.

## 4. Encoding rules

Input is consumed in 5-byte groups; each group's 40 bits are written as 8
base-32 digits, most significant first.

- **Full group** (5 bytes): 8 characters.
- **Final partial group** of `n` bytes (1..4): `n` bytes are the most
  significant `8n` bits of the group; the remaining bits are zero; `2/4/5/7`
  characters are emitted for `n = 1/2/3/4` and then `6/4/3/1` pad characters
  `=` fill the group to 8.
- **Empty input**: `""`.
- The encoded length is always `8 * ceil(n / 5)`, a multiple of 8.
- The encoder is total: it never validates its input and has no error case.

Bit layout of one partial group (each letter is one of the 8 output digits,
`0` marks a zero fill bit):

```
n=1: b0 11111 22222 00000 00000 00000 00000 00000 00000   -> 2 chars + 6 '='
n=2: b0,b1 11111 22222 33333 44444 00000 00000 00000 00000 -> 4 chars + 4 '='
n=3: 3 bytes 11111 22222 33333 44444 55555 00000 00000 00000 -> 5 chars + 3 '='
n=4: 4 bytes ... 66666 77777 00000 -> 7 chars + 1 '='
n=5: 5 bytes ... 88888 -> 8 chars, no padding
```

Pinned vectors (cross-checked against an independent Base32 implementation):

| Bytes (hex) | Base32 |
|---|---|
| `` (empty) | `` |
| `66` | `MY======` |
| `666f` | `MZXQ====` |
| `666f6f` | `MZXW6===` |
| `666f6f62` | `MZXW6YQ=` |
| `666f6f6261` | `MZXW6YTB` |
| `666f6f626172` (`foobar`) | `MZXW6YTBOI======` |
| `07` / `072c` / `072c51` | `A4======` / `A4WA====` / `A4WFC===` |
| `072c5176` / `072c51769b` | `A4WFC5Q=` / `A4WFC5U3` |
| `ff` / `ffff` / `ffffff` / `ffffffff` / `ffffffffff` | `74======` / `777Q====` / `77776===` / `777777Y=` / `77777777` |
| 16 x `ff` | `77777777777777777777777774======` |
| 10 x `00` | `AAAAAAAAAAAAAAAA` |
| `000000000102030400000000` | `AAAAAAABAIBQIAAAAAAA====` |
| `68c3a96c6c6f20f09f9880` (`héllo 😀`) | `NDB2S3DMN4QPBH4YQA======` |

## 5. Decoding rules

1. **Empty input** yields `Ok(empty)`.
2. **Character validation** runs left to right; the first byte outside
   `A-Z`/`a-z`/`2-7`/`=` yields `Err("base32: invalid character")`.
3. **Padding position**: let `d` be the index of the first `=` and `p` the
   number of bytes from `d` to the end. Every byte after the first `=` must be
   `=`: an alphabet character there yields
   `Err("base32: invalid padding position")`; any other byte yields
   `Err("base32: invalid character")`.
4. **Padding count** (when `p > 0`): with `rem = d % 8`, the only valid
   combinations are `(rem, p) = (2, 6)`, `(4, 4)`, `(5, 3)`, `(7, 1)` and the
   total length must be a multiple of 8. Anything else (including `=` after
   whole groups, `rem = 0`, `rem = 1/3/6`, or extra `=`) yields
   `Err("base32: bad padding count")`.
5. **Unpadded input** (when `p = 0`): the whole input is data. `d % 8` must be
   0; otherwise the input is an unpadded partial group and yields
   `Err("base32: truncated group")`. **Padding is therefore required for
   partial final groups; unpadded partial groups are rejected.** Whole
   `8`-character groups need no padding, matching the canonical encoding.
6. **Payload**: the `d` data characters are folded into a running
   most-significant-first accumulator; every full 8 bits emit one byte.
   Lowercase characters are folded to their uppercase value before folding.
7. **Trailing bits**: after all data characters, the accumulator holds the
   unused low bits of the final group (2/4/1/3 bits for `d % 8 = 2/4/5/7`;
   zero for whole groups). A non-zero accumulator yields
   `Err("base32: non-canonical trailing bits")` -- non-canonical encodings of
   the same bytes are rejected rather than normalized.
8. Decoded bytes are never UTF-8 validated; the caller owns that boundary.

## 6. API contract

| Function | Input | Returns | Errors |
|---|---|---|---|
| `base32_alphabet()` | none | `"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"` | none |
| `base32_encode(data)` | any `Vec[UInt8]`, including empty | canonical padded Base32 `Str`; length `8 * ceil(n/5)` | none |
| `base32_decode(s)` | any `Str`; bytes are read as encoded characters | `Ok(Vec[UInt8])` for canonical Base32, `Ok(empty)` for `""` | the five `base32: ...` errors below |
| `base32_is_valid(s)` | any `Str` | `true` iff `base32_decode(s)` is `Ok` (including `""`) | none |

Invariants:

- `base32_decode(base32_encode(data))` is `Ok(data)` for every `Vec[UInt8]`,
  including empty and high-byte data.
- `base32_encode` output is canonical: length a multiple of 8, correct pad
  count, zero trailing bits -- so `base32_is_valid(base32_encode(data))` is
  always `true`.
- `base32_is_valid(s)` is exactly "`base32_decode(s)` does not return `Err`";
  it is the canonical acceptance predicate for the rest of this document.

## 7. Error catalog

All decode errors start with the literal prefix `base32: `; they are produced
only by `base32_decode` (and therefore surface as `false` from
`base32_is_valid`). The first applicable rule in the order below wins.

| Message | Trigger |
|---|---|
| `base32: invalid character` | Any byte outside `A-Z`/`a-z`/`2-7`/`=` encountered while scanning data characters, or a byte after the first `=` that is neither `=` nor an alphabet character. |
| `base32: invalid padding position` | An alphabet character (`A-Z`/`a-z`/`2-7`) after the first `=`. |
| `base32: bad padding count` | `p > 0` and `(d % 8, p)` is not one of `(2,6)`, `(4,4)`, `(5,3)`, `(7,1)`, or the total length is not a multiple of 8. |
| `base32: truncated group` | `p = 0` and `d % 8 != 0` (unpadded partial final group). |
| `base32: non-canonical trailing bits` | The final group's unused low bits are not all zero (e.g. `MZ======`, `MZXR====`, `MZXW7===`, `MZXW6YR=`). |

Examples by message:

- invalid character: `0`, `1`, `8`, `9`, `MB!`, `"MZXW6 YTB"`, `MZXW6YTB-`,
  `MZXW6YTé`, `"MY===!="`.
- invalid padding position: `"MY=====A"`, `"MZXW6YTB=B"`, `"M=Y====="`,
  `"=M======"`, `"MY=====z"`.
- bad padding count: `"MY="`, `"MY====="`, `"MY======="`, `"M======="`,
  `"========"`, `"MZXW6YTB="`, `"MZXW6YTBOI====="`.
- truncated group: `"M"`, `"MZXW6"`, `"MZXW6YQ"`, `"MZXW6YTBOI"`.
- non-canonical trailing bits: `"MZ======"`, `"MZXR===="`, `"MZXW7==="`,
  `"MZXW6YR="`, `"mz======"`.

## 8. Test plan

`tests/test_conformance.xi` (module `base32_tests`) runs 18 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Expected byte vectors are built with the stdlib
`xiom.encoding.hex` decoder; all `Str` equality uses
`xiom.string.compare.str_compare` (BUG 17 discipline). Pinned vectors were
cross-checked against an independent Base32 implementation
(`base64.b32encode`).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | encode RFC 4648 vectors | `""`, `f`, `fo`, `foo`, `foob`, `fooba`, `foobar` -> the RFC section 10 encodings |
| t2 | decode RFC 4648 vectors | inverse of t1, including `Ok(empty)` |
| t3 | encode boundaries | deterministic 1..5 byte sequences pinned to `A4======` ... `A4WFC5U3`, plus a 6-byte `YA======` tail |
| t4 | decode boundaries | inverse pins; for lengths 0..10 encoded length is `8*ceil(n/5)`, a multiple of 8, and round-trips |
| t5 | empty input | `encode({}) == ""`, `decode("") == Ok(empty)`, `is_valid("")` |
| t6 | case-insensitive | lowercase and mixed-case RFC vectors decode identically; `is_valid` accepts `mzxw6===` |
| t7 | invalid characters | `0`, `1`, `8`, `9`, `MB!`, embedded space, `-`, `_`, `é` -> `base32: invalid character` |
| t8 | padding position | alphabet chars after the first `=` -> `base32: invalid padding position`; non-alphabet after `=` -> `base32: invalid character` |
| t9 | padding count | wrong `=` counts -> `base32: bad padding count`; exact counts (`MY======`, `MZXW6===`) -> `Ok` |
| t10 | truncated group | unpadded `M`, `MZXW6`, `MZXW6YQ`, `MZXW6YTBOI` -> `base32: truncated group`; `MZXW6YTB` and `MZXW6YTBOI======` -> `Ok` |
| t11 | trailing bits | `MZ======`, `MZXR====`, `MZXW7===`, `MZXW6YR=`, lowercase `mz======` -> `base32: non-canonical trailing bits`; canonical tails -> `Ok` |
| t12 | round-trip 0..8 | deterministic bytes including >= 0x80 |
| t13 | round-trip 0..40 + 16x `ff` | 16 x `ff` -> `77777777777777777777777774======` and back; every length 0..40 round-trips, encoded length a multiple of 8, `is_valid` |
| t14 | 64-byte pinned | deterministic 64-byte buffer -> the 104-character pinned encoding and back |
| t15 | high bytes | `ff`..`ffffffffff` and 16 x `ff` pins; round-trips for `ff`, `ffff`, `ffffff`, `ffffffff`, `ffffffffff`, `00ff00ff00ff00ff00` |
| t16 | exhaustive one-byte | every value 0..255 encodes to exactly 2 characters + 6 `=` and round-trips |
| t17 | unicode / zero runs | `68c3a96c6c6f20f09f9880` -> `NDB2S3DMN4QPBH4YQA======`; `000000000102030400000000` -> `AAAAAAABAIBQIAAAAAAA====`; round-trips |
| t18 | alphabet + is_valid | alphabet exact and length 32; 5 zero bytes -> `AAAAAAAA` and back; `is_valid` true for `""`/`MZXW6===`, false for `MZXW6`, `MZ======`, `0`, `MY=====` |

Scripted expectation from the repository root:

```
& .\scripts\port.ps1 -Package xiom.base32
# port: PASS (passed=18 failed=0 program_exit=0 exit=0)
```

## 9. Known limitations

- **Standard alphabet only** (section 2).
- **Padding required for partial groups**; a deliberate strictness choice.
  Many decoders accept unpadded tails; this one rejects them with
  `base32: truncated group`.
- **Non-canonical encodings rejected**, not normalized (trailing bits and
  pad counts must be exact).
- **No whitespace tolerance**: even a trailing newline is an invalid
  character.
- **Bytes only**: no `encode_str`/`decode_str`; no UTF-8 validation.
- **In-memory, O(n)**, no streaming.

## 10. Compiler / stdlib notes

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch.
- `Ok`/`Err` for the `Result`-returning functions are constructed only in the
  leaf helpers `_ok_bytes`/`_err_bytes`.
- Bytes read from `Vec[UInt8]` or `byte_at` are always widened with
  `(x as Int) & 0xFF` before comparison/arithmetic.
- No bitwise shifts: full 40-bit groups are split with multiplication,
  division and modulo (`b0 / 8`, `(b0 % 8) * 4 + b1 / 64`, ...), avoiding
  v0.61.3 shifts on values with the high bit set.
- The decoder folds digits with `acc = acc * 32 + v` and extracts bytes with
  division by a small power of two (`_pow2`), keeping the accumulator below
  2^12.
- No `==` on `Str` values anywhere (tests route every comparison through
  `str_compare`, BUG 17).
