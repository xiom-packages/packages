# xiom.radix -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.radix`, version `0.1.0`).
Module: `src/radix.xi` (`module xiom.radix`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`, `xiom.core`).
No FFI.

## 1. Scope

Six free functions over `Str`, `UInt8` and `Int`:

```xi
pub fn radix_alphabet() -> Str
pub fn radix_digit_value(c: UInt8) -> Int
pub fn radix_to_int(s: Str, base: Int) -> Result[Int, Str]
pub fn radix_from_int(n: Int, base: Int) -> Result[Str, Str]
pub fn radix_convert(s: Str, from_base: Int, to_base: Int) -> Result[Str, Str]
pub fn radix_is_valid(s: Str, base: Int) -> Bool
```

The codec is whole-string, in-memory and integer-only. Parsing and emission
are digit-wise over the canonical alphabet; base-to-base conversion goes
through `Int` without any `Float64` arithmetic. The radix range is 2..36 and
the value range is the signed 64-bit `Int` range
`[-9223372036854775808, 9223372036854775807]`.

## 2. Non-goals

- **No fractional or decimal values**: no `.`, no exponent, no rounding.
- **No arbitrary precision**: no BigInt, no digit buffers larger than the
  `Int` accumulator; out-of-range values are errors.
- **No prefixes**: `0x`, `0b`, `0o` and similar are rejected as invalid
  digits.
- **No custom alphabets**: the canonical lowercase alphabet is fixed;
  alternative alphabets are sibling-package territory.
- **No whitespace, grouping or normalization**: no trimming, no `_`
  separators, no locale digits.
- **No streaming/incremental API**: every function consumes or produces a
  complete `Str`.

## 3. Alphabet

The canonical alphabet has 36 characters in value order:

```
index  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35
char   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f  g  h  i  j  k  l  m  n  o  p  q  r  s  t  u  v  w  x  y  z
```

- `0`..`9` are values 0..9; `a`..`z` are values 10..35.
- `A`..`Z` map to the same values as `a`..`z` (case-insensitive input);
  emission is always lowercase.
- Every other byte, including `+`, `-`, `:`, `@`, whitespace and all bytes
  >= 0x80, has digit value `-1` and is rejected by the parser.
- `radix_digit_value` classifies a single byte with this table and returns
  `-1` outside it.

## 4. Parsing rules (`radix_to_int`)

1. **Base check first**: `base` must be 2..36; otherwise
   `Err("radix: base out of range")`, before any input byte is inspected.
2. **Empty input**: `""` is `Err("radix: empty input")`.
3. **Optional sign**: a leading `+` (byte 43) or `-` (byte 45) is consumed;
   the sign counts as position 0 for error reporting.
4. **Lone sign**: `"+"` or `"-"` alone is `Err("radix: lone sign")`.
5. **Digits**: every remaining byte must have a digit value `d` with
   `0 <= d < base`; the first violation at byte index `i` (0-based,
   including the sign byte) is `Err("radix: invalid digit at position N")`
   with `N = i` in decimal. Uppercase letters are valid digits.
6. **Leading zeros are accepted** (`"00042"` is 42) and have no other
   meaning; there is no length or prefix rule.
7. **Overflow**: the magnitude is accumulated negatively so it can reach
   2^63 exactly. Before each multiply-add the parser checks
   `acc < (INT_MIN + d) / base`; a violation is `Err("radix: overflow")`.
   After the loop a non-negative input whose accumulator equals `INT_MIN`
   is also overflow (positive magnitudes top out at `INT_MAX`).
8. The result is `Ok(-acc)` for non-negative input and `Ok(acc)` for
   negative input.

Examples:

| Input | Base | Result |
|---|---|---|
| `"0"` | any 2..36 | `Ok(0)` |
| `"1010"` | 2 | `Ok(10)` |
| `"777"` | 8 | `Ok(511)` |
| `"12345"` | 10 | `Ok(12345)` |
| `"ff"`, `"FF"` | 16 | `Ok(255)` |
| `"z"` | 36 | `Ok(35)` |
| `"-ff"` | 16 | `Ok(-255)` |
| `"+42"` | 10 | `Ok(42)` |
| `"00042"` | 10 | `Ok(42)` |
| `"-0"` | 10 | `Ok(0)` |
| `"12z"` | 10 | `Err("radix: invalid digit at position 2")` |
| `"2"` | 2 | `Err("radix: invalid digit at position 0")` |
| `"0x1f"` | 16 | `Err("radix: invalid digit at position 1")` |
| `"9223372036854775808"` | 10 | `Err("radix: overflow")` |

## 5. Emission rules (`radix_from_int`)

1. `base` must be 2..36; otherwise `Err("radix: base out of range")`.
2. `0` emits exactly `"0"` in every base.
3. Negative values emit a leading `-`; positive values emit no sign.
   `INT_MIN` is exact.
4. Digits are the canonical lowercase alphabet characters for the repeated
   division remainders, most significant first.
5. No leading zeros appear; the output is the shortest representation for
   the value in that base.

Examples:

| n | Base | Text |
|---|---|---|
| 0 | 10 | `"0"` |
| 42 | 10 | `"42"` |
| -42 | 10 | `"-42"` |
| 10 | 2 | `"1010"` |
| 511 | 8 | `"777"` |
| 255 | 16 | `"ff"` |
| -255 | 16 | `"-ff"` |
| `INT_MAX` | 16 | `"7fffffffffffffff"` |
| `INT_MIN` | 16 | `"-8000000000000000"` |

## 6. Conversion rules (`radix_convert`)

1. Both bases are validated before the input is scanned, in the order
   `from_base` then `to_base`; either failure is
   `Err("radix: base out of range")`.
2. `s` is parsed with the full `radix_to_int` rules; every error message is
   propagated verbatim (same position, same text).
3. The parsed value is emitted with the full `radix_from_int` rules, so the
   output is canonical even when the input was not (`"0000ff"` from base 16
   to base 16 yields `"ff"`).
4. The conversion goes through the signed 64-bit `Int` range. It is exact
   for all in-range values and reports `radix: overflow` for anything
   outside it; there is no arbitrary-precision path.

## 7. API contract

| Function | Input | Returns | Errors |
|---|---|---|---|
| `radix_alphabet()` | none | the 36-character alphabet | none |
| `radix_digit_value(c)` | any `UInt8` | `0..35` for digits, `-1` otherwise | none |
| `radix_to_int(s, base)` | any `Str`, `base` 2..36 | `Ok(Int)` signed value | the five errors below |
| `radix_from_int(n, base)` | any `Int`, `base` 2..36 | `Ok(Str)` canonical text | `radix: base out of range` |
| `radix_convert(s, from, to)` | any `Str`, bases 2..36 | `Ok(Str)` canonical text in `to` | propagated parse errors, plus base range |
| `radix_is_valid(s, base)` | any `Str`, `base` 2..36 | `true` iff `radix_to_int` is `Ok` | none |

Invariants:

- `radix_from_int(v, b)` then `radix_to_int(_, b)` is `v` for every `Int` `v`
  and every base `b` in 2..36 (round-trip).
- `radix_to_int(radix_from_int(v, b).value, b).value == v`; the formatted
  text contains only alphabet characters, an optional leading `-`, never a
  `+`, and never a leading zero unless the whole text is `"0"`.
- `radix_is_valid(s, b)` is exactly "`radix_to_int(s, b)` does not return
  `Err`"; it is the canonical acceptance predicate for this document.
- `radix_digit_value` is the only classification table: the parser and the
  alphabet agree with it for every index 0..35.

## 8. Error catalog

All messages start with the literal prefix `radix: `. The first applicable
rule in the order below wins.

| Message | Trigger |
|---|---|
| `radix: base out of range` | `base`, `from_base` or `to_base` outside 2..36. |
| `radix: empty input` | The input `Str` is empty. |
| `radix: lone sign` | The input is exactly `"+"` or `"-"`. |
| `radix: invalid digit at position N` | First byte (0-based, sign included) whose digit value is `-1` or `>= base`; `N` is decimal. |
| `radix: overflow` | The signed value does not fit the `Int` range. |

Examples by message:

- base out of range: `radix_to_int("1", 1)`, `radix_to_int("1", 37)`,
  `radix_from_int(1, 0)`, `radix_convert("1", 10, 99)`.
- empty input: `radix_to_int("", 10)`, `radix_convert("", 16, 2)`.
- lone sign: `radix_to_int("+", 10)`, `radix_to_int("-", 2)`.
- invalid digit at position: `radix_to_int("12z", 10)` -> position 2,
  `radix_to_int("2", 2)` -> position 0,
  `radix_to_int("-1@", 10)` -> position 2,
  `radix_to_int("1111111111!", 10)` -> position 10.
- overflow: `radix_to_int("9223372036854775808", 10)`,
  `radix_to_int("-9223372036854775809", 10)`,
  `radix_to_int("8000000000000000", 16)`.

## 9. Overflow rules

`Int` is two's-complement 64-bit (`core.INT_MAX` / `core.INT_MIN`). The
parser accumulates the magnitude **negatively** (`acc = acc * base - d`), so
the accumulator can represent 2^63, one more than the positive side. The
exact bound check is `acc < (INT_MIN + d) / base`; after the loop a
non-negative input with `acc == INT_MIN` is reported as overflow because its
magnitude exceeds `INT_MAX`.

| Boundary | Accepted | Rejected |
|---|---|---|
| positive | `"9223372036854775807"` (10), `"7fffffffffffffff"` (16) | `"9223372036854775808"` (10), `"8000000000000000"` (16), 2^64-1 in base 2 |
| negative | `"-9223372036854775808"` (10), `"-8000000000000000"` (16) | `"-9223372036854775809"` (10), `"-8000000000000001"` (16), below `INT_MIN` in base 2 |

There is no wrap, no saturation and no truncation: overflow is always an
`Err("radix: overflow")`.

## 10. Test plan

`tests/test_conformance.xi` (module `radix_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` equality uses
`xiom.string.compare.str_compare` (BUG 17 discipline). The big-value pins
(INT_MAX/INT_MIN in bases 2/8/10/16/36, the 2^63 boundary strings) were
cross-checked against an independent big-integer implementation.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | alphabet | exact 36-character lowercase set; `'0'`, `'9'`, `'a'`, `'z'` at indices 0/9/10/35 |
| t2 | digit values | `0-9`/`a-z`/`A-Z` -> 0..35; `!`, space, `-`, `+`, `:`, `@`, `{`, `é` (0xC3) and bytes 128/255 -> -1 |
| t3 | parse baselines | `0`(2), `1010`(2), `777`(8), `12345`(10), `ff`(16), `100`(16), `z`(36), `10`(36), INT_MAX in base 36 |
| t4 | uppercase input | `FF`=255, `DeadBeef`=3735928559, `Zz`=1295, `ABCDEF`=11259375, `Ac`=172 |
| t5 | signs | `+42`=42, `-42`, `+ff`, `-ff`, `-0`=0, `+0`, `-1010` base 2 |
| t6 | leading zeros | `00042`, `007`(8), `0000`, `-0007`, `00000000ff`, `000z` |
| t7 | emit baselines | 0/42/255/10/511/35/36 in their bases; `-42`(10), `-255`(16) |
| t8 | zero and +/-1 | `"0"` for zero and `"1"`/`"-1"` for +/-1 in every base 2..36 |
| t9 | INT_MAX | pins in bases 2/8/10/16/36; parses `7fffffffffffffff` and `1y2p0ij32e8e7`; round-trips 16/36 |
| t10 | INT_MIN | pins in bases 2/10/16/36; parses `-9223372036854775808`, `-8000000000000000`, `-1y2p0ij32e8e8`; round-trips 10/2 |
| t11 | positive overflow | 2^63 and above in base 10, `8000000000000000` (16), 2^63 and 2^64-1 in base 2, 24 nines |
| t12 | negative overflow | below INT_MIN in base 10, `-8000000000000001` (16), base 36 successor, 64 ones in base 2 |
| t13 | invalid digit positions | first bad byte 0-based (sign included); multi-digit position 10 |
| t14 | base out of range | 0/1/37/-2 for parse; 1/37 for emit; 0 and 99 for convert; precedes empty input |
| t15 | empty and lone sign | distinct messages for `""`, `"+"`, `"-"` |
| t16 | round-trips | 12 values (0, +/-1, 7, 8, 255, 256, +/-255, +/-1000000, INT_MAX, INT_MIN) x bases 2/8/10/16/36, with `is_valid` |
| t17 | convert | cross-base vectors, sign/leading-zero canonicalization, error propagation (invalid digit, overflow, empty, lone sign) |
| t18 | is_valid | true for valid text incl. uppercase/sign/leading zeros; false for empty, lone sign, bad digit, out-of-range digit, bad base, whitespace, `0x10` |
| t19 | canonical emit | `00ff` -> `ff`, `+ff` -> 255, `-000z` -> `-z`, `-0` -> `0`, `DEADBEEF` -> `deadbeef` |
| t20 | exhaustive digits | every value 0..b-1 round-trips as a single digit in every base 2..36 |

Scripted expectation from the repository root:

```
& .\scripts\port.ps1 -Package xiom.radix
# port: PASS (passed=20 failed=0 program_exit=0 exit=0)
```

## 11. Known limitations

- **Integer-only, 64-bit**: no fractions, no BigInt, no arbitrary precision.
- **Through-`Int` conversion**: `radix_convert` cannot convert values outside
  the `Int` range even between two huge bases.
- **Fixed case-insensitive alphabet**: no custom alphabets and no alias
  characters; letters are accepted in both cases but emitted lowercase only.
- **Strict input**: no whitespace, prefixes, separators or grouping; the
  parser never trims.
- **Whole-string, in-memory**: no streaming or incremental APIs.

## 12. Compiler / stdlib notes

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch.
- `Ok`/`Err` for the `Result`-returning functions are constructed only in
  the leaf helpers `_ok_int`/`_err_int`/`_ok_str`/`_err_str`.
- Bytes read via `xiom.string.byte_at` are widened with `(x as Int) & 0xFF`
  before comparison/arithmetic.
- `Int` values read from `Vec[Int]` are bound with explicit `let v: Int = ...`
  (`radix_digit_value` takes the byte and masks it once at the boundary).
- Output `Str` values are built with `xiom.string.builder.sb_to_str` from
  alphabet bytes only (printable ASCII, no `0x00`).
- No `==` on `Str` values anywhere (tests route every comparison through
  `str_compare`, BUG 17).
- Negative division (`x % base`, `x / base` with `x <= 0`) is the same
  INT_MIN-safe path used by `xiom.convert.int.int_to_base`.
