# xiom.bech32 -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.bech32`, version `0.1.0`).
Module: `src/bech32.xi` (`module xiom.bech32`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`). No FFI.

## 1. Scope

Eleven public items: the alphabet function, the encoder, the two decoders,
the validity predicate, three accessors over the decoded value, the general
`convertbits` helper and its two concrete directions.

```xi
pub const BECH32_VARIANT_BECH32: Int = 0
pub const BECH32_VARIANT_BECH32M: Int = 1

pub type Bech32 = { hrp: Str; variant: Int; data: Vec[Int]; }

pub fn bech32_charset() -> Str
pub fn bech32_encode(hrp: Str, data: &Vec[Int], variant: Int) -> Result[Str, Str]
pub fn bech32_decode(s: Str) -> Result[Bech32, Str]
pub fn bech32_decode_variant(s: Str, variant: Int) -> Result[Bech32, Str]
pub fn bech32_is_valid(s: Str) -> Bool
pub fn bech32_hrp(v: &Bech32) -> Str
pub fn bech32_variant(v: &Bech32) -> Int
pub fn bech32_data(v: &Bech32) -> Vec[Int]
pub fn bech32_convertbits(data: &Vec[Int], frombits: Int, tobits: Int, pad: Bool) -> Result[Vec[Int], Str]
pub fn bech32_bytes_to_symbols(data: &Vec[UInt8]) -> Vec[Int]
pub fn bech32_symbols_to_bytes(data: &Vec[Int]) -> Result[Vec[UInt8], Str]
```

All scanning is byte-wise via `xiom.string.byte_at`; every raw byte is
widened with `(x as Int) & 0xFF` before comparison or arithmetic. No bitwise
shifts are used anywhere: the polymod loop works with division and modulo by
2^25 / 2^30 and the checksum symbols are extracted by division by
2^(5*(5-i)). Every function is O(n) and allocates its result in memory.

## 2. Non-goals

- **No segwit address semantics**: no witness versions, no program-length
  policy, no network HRP table, no BIP-141 checks. The BIP address vectors
  in the tests are used strictly as codec-level strings.
- **No error correction or location**: BIP-173 explicitly discourages
  correcting; this codec only detects.
- **No base58/base64/hex**: sibling packages own those codecs.
- **No streaming/incremental API**: whole-value encode/decode only.
- **No `Str`/UTF-8 convenience helpers**: bytes and 5-bit symbols only.
- **No case normalization beyond the BIP rule**: the decoder folds an
  all-uppercase string to lowercase; the encoder emits lowercase and
  refuses an uppercase HRP rather than silently changing it.

## 3. Format, HRP and alphabet

A Bech32 string is at most **90 characters** and has the shape
`hrp + separator + data`, where the separator is the **last** `1` in the
string (a `1` may also appear inside the HRP).

- **HRP**: 1..83 US-ASCII characters, each with a value in `[33,126]`.
- **Data part**: at least 6 characters from the 32-character alphabet
  below; the final 6 are the checksum and carry no information.

BIP-173 data alphabet, index = 5-bit value:

```
value  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
char   q  p  z  r  y  9  x  8  g  f  2  t  v  d  w  0
value 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
char   s  3  j  n  5  4  k  h  c  e  6  m  u  a  7  l
```

`1`, `b`, `i` and `o` are not in the alphabet.

**Case rule (BIP-173):** the lowercase form determines value and checksum.
Decoders must reject mixed-case strings; an all-uppercase string is valid
and equivalent to its lowercase form. Encoders must output all lowercase.
Accordingly:

- `bech32_encode` accepts only a lowercase HRP and returns
  `Err("bech32: mixed case")` for any uppercase HRP letter (it would make
  the emitted string mixed case).
- `_bech32_parse` folds an all-uppercase string to lowercase and reports
  `Err("bech32: mixed case")` when both cases occur.

## 4. Checksum

Both variants use the BIP-173 BCH polymod over
`hrp-expand(hrp) + data symbols + 6 zero symbols`, where

```
hrp-expand(hrp) = [b / 32 for b in hrp] + [0] + [b % 32 for b in hrp]
```

and the 30-bit checksum constant is xored into the final polymod value:

| Variant | Constant | Accepted by |
|---|---|---|
| Bech32 (BIP-173) | `1` | `bech32_decode`, `bech32_decode_variant(..., 0)` |
| Bech32m (BIP-350) | `0x2bc830a3` (734539939) | `bech32_decode`, `bech32_decode_variant(..., 1)` |

Verification requires `polymod(hrp-expand(hrp) + data) == constant`. The
polymod generator constants are `0x3b6a57b2, 0x26508e6d, 0x1ea119fa,
0x3d4233dd, 0x2a1462b3`. In this implementation `chk` never leaves
`0..2^30-1`, so the reference's `chk >> 25` and `(chk & 0x1ffffff) << 5`
become `chk / 33554432` and `(chk % 33554432) * 32`.

## 5. Encoding rules

`bech32_encode(hrp, data, variant)`:

1. `variant` must be 0 or 1, else `bech32: bad variant`.
2. HRP length must be 1..83, else `bech32: invalid hrp length`.
3. Every HRP byte must be in `[33,126]` (`bech32: invalid hrp character`)
   and lowercase (`bech32: mixed case`).
4. Every data symbol must be in 0..31 (`bech32: invalid data value`).
5. `hrp.len() + data.len() + 7` must be at most 90
   (`bech32: bad length`).
6. Output is `hrp + "1" + symbols(data) + symbols(checksum)`, all lowercase.

The encoder is strict and total on valid input; it never normalizes case.
Pinned: `bech32_encode("a", [], 0) == "a12uel5l"`,
`bech32_encode("abcdef", [0..31], 0) ==
"abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"`,
`bech32_encode("abcdef", [31..0], 1) ==
"abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx"`.

## 6. Decoding rules

`_bech32_parse(s, want)` is shared by both decoders; `want` is a variant
(0/1) or `-1` for auto-detection. Validation order:

1. **Length**: `s.len()` must be in 8..90, else `bech32: bad length`.
2. **Case**: both an uppercase and a lowercase letter present yields
   `bech32: mixed case`.
3. **Separator**: `pos` is the index of the last `1`; `pos < 1` (no `1`, or
   an empty HRP) yields `bech32: missing separator`.
4. **Data-part length**: `s.len() - pos - 1` must be at least 6, else
   `bech32: bad length` (checksum too short).
5. **HRP**: every byte before `pos` must be in `[33,126]`
   (`bech32: invalid hrp character`); uppercase letters are folded, so the
   stored HRP is always lowercase.
6. **Data alphabet**: every byte after `pos` is case-folded and looked up in
   the alphabet; an unknown byte yields `bech32: invalid data character`.
7. **Checksum**: `pm = polymod(hrp-expand(hrp) + all data symbols)`. If
   `pm == 1` the variant is Bech32, if `pm == 0x2bc830a3` it is Bech32m,
   otherwise `bech32: bad checksum`. When `want != -1` and the detected
   variant differs, the result is `bech32: wrong variant`.
8. **Payload**: the 6 checksum symbols are removed; the remaining 5-bit
   values (possibly none) become `Bech32.data`.

The decoded `hrp` is the folded lowercase HRP, `variant` is the constant
that verified, and `data` never includes checksum symbols.

## 7. Ambiguity between the two constants

BIP-350's test-vector notes state that no string can be simultaneously
valid Bech32 and Bech32m ("a valid Bech32 and Bech32m string will always
differ by at least 3 characters if they are the same length"). The reason is
structural: for a fixed string the polymod is one number, and verification
compares it with `1` or `0x2bc830a3`; since `1 != 0x2bc830a3`, at most one
comparison can hold. There is therefore no "verifies against both
constants" case to detect, and this module guarantees:

- `bech32_decode(s)` is `Ok` with exactly one variant, never an ambiguous
  result.
- `bech32_decode_variant(s, v)` distinguishes the two failure modes:
  `bech32: wrong variant` means the string is valid under the **other**
  constant; `bech32: bad checksum` means it is valid under neither.
- Consequently an application that must enforce a variant (e.g. BIP-350's
  "v0 uses Bech32, v1+ uses Bech32m") can call `bech32_decode_variant` and
  trust the error taxonomy rather than decoding twice.

## 8. convertbits

`bech32_convertbits(data, frombits, tobits, pad)` implements BIP-173's
bit regrouping, most significant bit first:

```
acc = (acc * 2^frombits + value) mod 2^(frombits + tobits - 1)
bits = bits + frombits
while bits >= tobits:
    bits = bits - tobits
    emit (acc / 2^bits) mod 2^tobits
if pad:
    if bits > 0: emit (acc * 2^(tobits - bits)) mod 2^tobits
else:
    if bits >= frombits: error invalid padding
    if (acc * 2^(tobits - bits)) mod 2^tobits != 0: error invalid padding
```

Preconditions and errors:

- `frombits` and `tobits` must each be 1..8, else `bech32: invalid bits`.
- Every input value must be in `0..2^frombits - 1`, else
  `bech32: convertbits overflow`.
- With `pad = false` a leftover group of at least `frombits` bits, or a
  non-zero leftover, is `bech32: invalid padding`.

Concrete directions:

| Helper | Direction | pad | Notes |
|---|---|---|---|
| `bech32_bytes_to_symbols` | 8->5 | true | Total: bytes are always in range and padding is always allowed, so no error is possible. `foobar` (6 bytes) becomes 10 symbols `[12,25,23,22,30,24,19,1,14,8]` (2 zero pad bits). |
| `bech32_symbols_to_bytes` | 5->8 | false | Strict. 32 symbols `[0..31]` become the 20 bytes `00443214c74254b635cf84653a56d7c675be77df`; a single symbol is `bech32: invalid padding`; `[0,0]` is one zero byte; `[31,31]` and `[0,0,0]` are `bech32: invalid padding`. |

## 9. API contract

| Function | Input | Returns | Errors |
|---|---|---|---|
| `bech32_charset()` | none | the 32-character alphabet | none |
| `bech32_encode(hrp, data, variant)` | lowercase HRP 1..83, symbols 0..31, variant 0/1 | `Ok(canonical lowercase string)` | bad variant, invalid hrp length, invalid hrp character, mixed case, invalid data value, bad length |
| `bech32_decode(s)` | any `Str` | `Ok(Bech32)` with the detected variant | bad length, mixed case, missing separator, invalid hrp character, invalid data character, bad checksum |
| `bech32_decode_variant(s, variant)` | as above, variant 0/1 | `Ok(Bech32)` under that constant | as above plus bad variant and wrong variant |
| `bech32_is_valid(s)` | any `Str` | `true` iff `bech32_decode(s)` is `Ok` | none |
| `bech32_hrp(v)` | decoded value | lowercase HRP | none |
| `bech32_variant(v)` | decoded value | 0 or 1 | none |
| `bech32_data(v)` | decoded value | `Vec[Int]` of 0..31, no checksum | none |
| `bech32_convertbits(...)` | symbols, 1..8 / 1..8, Bool | `Ok(Vec[Int])` | invalid bits, convertbits overflow, invalid padding |
| `bech32_bytes_to_symbols(data)` | any bytes | symbols, zero-padded tail | none (total) |
| `bech32_symbols_to_bytes(data)` | symbols 0..31 | `Ok(Vec[UInt8])` | convertbits overflow, invalid padding |

Invariants:

- `bech32_decode(bech32_encode(hrp, data, v))` is `Ok` with the same HRP,
  variant and data for every valid encoding input.
- `bech32_symbols_to_bytes(bech32_bytes_to_symbols(bytes)) == Ok(bytes)`.
- `bech32_is_valid(s)` is exactly "`bech32_decode(s)` does not return
  `Err`"; it is the canonical acceptance predicate for this document.
- `bech32_decode_variant(s, v)` is `Ok` iff `bech32_decode(s)` is `Ok` with
  variant `v`.

## 10. Error catalog

All errors start with the literal prefix `bech32: `. The first applicable
rule in the documented order wins.

| Message | Trigger |
|---|---|
| `bech32: bad length` | Decode: length < 8 or > 90, or data part < 6. Encode: total would exceed 90. |
| `bech32: invalid hrp length` | Encode: HRP empty or > 83. |
| `bech32: invalid hrp character` | HRP byte outside `[33,126]` (encode or decode). |
| `bech32: mixed case` | Decode: uppercase and lowercase letters both present. Encode: uppercase HRP letter. |
| `bech32: missing separator` | Decode: no `1`, or `1` at index 0. |
| `bech32: invalid data character` | Data byte outside the alphabet. |
| `bech32: invalid data value` | Encode: symbol outside 0..31. |
| `bech32: bad variant` | variant not in {0, 1}. |
| `bech32: bad checksum` | Polymod matches neither constant, or neither the requested one nor the other. |
| `bech32: wrong variant` | `bech32_decode_variant` only: polymod matches the other constant. |
| `bech32: invalid bits` | `convertbits`: frombits/tobits outside 1..8. |
| `bech32: convertbits overflow` | `convertbits`: value < 0 or >= 2^frombits. |
| `bech32: invalid padding` | `convertbits` pad=false: leftover >= frombits or non-zero. |

Examples by message:

- bad length: `""`, `"A1"`, `"li1dgmt3"`, `"in1muywd"`, the `an84...`
  vectors (91 characters), and any encode whose HRP + data exceeds 90.
- invalid hrp character: `" 1nwldj5"` (0x20 HRP), `0x7F1axkwrx`,
  `0x801eym55h`, `0x801vctc34`.
- mixed case: `"A12uel5l"`, `"a12UEL5L"`, `...q47Zagq`, `...q0sL5k7`.
- missing separator: `"pzry9x0s0muk"`, `"1pzry9x0s0muk"`, `"1qzzfhee"`,
  `"1p2gdwpf"`, `"10a06t8"` (7 characters) is bad length before this rule.
- invalid data character: `"x1b4n0q5v"`, `"y1b0jsk6g"`, `"lt1igcx5c0"`,
  `"mm1crxm3i"`, `"au1s5cgom"`, `"de1lg7wt\xff"`.
- bad checksum: `"A1G7SGD8"`, `"M1VUXWEZ"` (checksum computed over the
  uppercase form of the HRP).
- wrong variant: `bc1qw508...kemeawh` under `BECH32_VARIANT_BECH32` (it is
  a valid Bech32m string), `bc1p0xlx...vqh2y7hd` under
  `BECH32_VARIANT_BECH32M` (valid Bech32).

## 11. Test plan

`tests/test_conformance.xi` (module `bech32_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` equality uses
`xiom.string.compare.str_compare` (BUG 17 discipline). Expected bytes are
built with the stdlib `xiom.encoding.hex` decoder. Every pinned vector was
cross-checked against an independent reference polymod implementation before
being written into the suite.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | charset | exact 32-character alphabet, unique, variant constants 0/1 |
| t2 | BIP-173 valid | all 7 vectors decode as Bech32 with pinned HRP/payload; `[0..31]` and 82 zeros pinned |
| t3 | BIP-350 valid | all 7 vectors decode as Bech32m; `[31..0]` and 82 x 31 pinned |
| t4 | canonical re-encode | decoding then re-encoding all 14 vectors reproduces the lowercase form |
| t5 | pinned encodes | empty payloads, both `abcdef` payloads, both 82-symbol vectors, the `split` payload |
| t6 | BIP-173 invalid | 12 invalid vectors map to the documented messages |
| t7 | BIP-350 invalid | 14 invalid vectors map to the documented messages |
| t8 | case | uppercase-only accepted and folded; mixed case rejected (incl. two BIP segwit mixed vectors) |
| t9 | variants | auto-detect vs `bech32_decode_variant`; `wrong variant` vs `bad checksum`; bad variant argument |
| t10 | is_valid | mirrors the decoder over both valid sets, the invalid sets and short inputs |
| t11 | 8->5 | `foobar`, `ff`, zero bytes and empty input pinned |
| t12 | 5->8 | `[0..31]` -> pinned 20 bytes; a 16-symbol payload -> pinned 10 bytes; empty |
| t13 | convertbits round-trip | lengths 0..24, symbol count `ceil(8n/5)`, inverse returns the bytes |
| t14 | convertbits errors | invalid bits (0, 9), overflow (32, -1, 256), invalid padding through both entry points |
| t15 | encoder errors | every encoder error message incl. total-length and variant failures |
| t16 | limits | 83-character HRP + 6 checksum = 90 accepted; 84-character HRP, 91-character total and 2-character inputs rejected |
| t17 | raw bytes | 0x20/0x7F/0x80 HRP bytes rejected; 0xFF suffix is an invalid data character and survives the builder |
| t18 | end-to-end | BIP P2WPKH / P2WSH / taproot strings produced from raw bytes and parsed back |
| t19 | accessors | `bech32_hrp` / `bech32_variant` / `bech32_data` on both `abcdef` vectors |
| t20 | round-trip | 0..12 bytes, both variants, full encode/decode/convert chain, length <= 90 |

Scripted expectation from the repository root:

```
& .\scripts\port.ps1 -Package xiom.bech32
# port: PASS (passed=20 failed=0 program_exit=0 exit=0)
```

## 12. Known limitations

- **No segwit semantics** (section 2).
- **No error correction or location**; detection only, per BIP-173.
- **Strict encoder case**: an uppercase HRP is refused, not lowercased.
- **Strict decoder**: no whitespace tolerance, no aliases, no
  normalization beyond the BIP case fold.
- **No UTF-8 convenience helpers**; `Vec[UInt8]` and `Vec[Int]` only.
- **In-memory, O(n)**; no streaming.

## 13. Compiler / stdlib notes

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch, no `[T, U]` generics.
- Every `Ok`/`Err` is constructed in a tiny leaf helper, including the
  struct payload (`_ok_bech32`/`_err_bech32`).
- Bytes read via `xiom.string.byte_at` or from `Vec[UInt8]` are always
  widened with `(x as Int) & 0xFF` before comparison or arithmetic.
- No bitwise shifts: the polymod uses `/` and `%` against 2^25 and 2^30,
  and checksum extraction divides by `_pow2(5 * (5 - k))`.
- `_bech32_polymod` keeps `chk < 2^30`, so all `^` (xor) operands stay
  below the sign bit.
- Callers bind the `Ok` payload of a `Result` to a local before taking a
  reference to it (`&r.value` reads an empty Vec in v0.61.3); the tests do
  this and README examples show it.
- No `==` on `Str` values anywhere; tests route every comparison through
  `str_compare` (BUG 17).
- No NUL byte is ever passed to `builder.sb_to_str`; raw-byte test vectors
  use 0x20, 0x7F, 0x80 and 0xFF, never 0x00.
