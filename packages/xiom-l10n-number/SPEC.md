# xiom.l10n.number -- specification

Version: 0.1.0 (incubating). Pure XIOM, no FFI, no floating point. All
functions are free functions; the module depends on `xiom.string` and
`xiom.convert` from `xiom.std` only.

## 1. Model

A decimal number is a **scaled integer**: `scaled` with `decimals` fraction
digits denotes the exact value `scaled / 10^decimals`. The representation is
canonical up to trailing zeros (`123450` with 2 digits and `12345` with 1
digit are the same number). A locale is the caller-supplied pair
`(group_sep, decimal_sep)`; there are no locale databases, no global state and
no rounding unless explicitly requested.

All text is byte-oriented. Digits are ASCII `0`-`9`; the ignored grouping
bytes are ASCII comma (44), underscore (95) and space (32). Separator
*strings* may be any non-digit text for output; in input, `decimal_sep` is
matched byte-wise and may itself be multi-byte.

## 2. `l10n_int_format(value: Int, group_sep: Str) -> Str`

1. `neg = value < 0`; the magnitude digit string is obtained from
   `xiom.convert.int_to_string` with a leading `-` stripped, so the 64-bit
   minimum is exact.
2. When `group_sep` is empty the digits are returned unchanged.
3. Otherwise `group_sep` is inserted before every digit whose distance from
   the least-significant digit is a positive multiple of 3 (i.e. groups of
   three counted from the right).
4. The sign is emitted once, in front: `-1,000`.

Examples: `(0, ",")` -> `"0"`; `(1000, ",")` -> `"1,000"`;
`(1234567, ".")` -> `"1.234.567"`; `(-999, ",")` -> `"-999"`;
`(Int::MIN, ",")` -> `"-9,223,372,036,854,775,808"`.

Complexity: O(digits). Never fails. `group_sep` may be multi-byte.

## 3. `l10n_decimal_format(scaled, decimals, group_sep, decimal_sep) -> Str`

1. `decimals` is clamped to `>= 0`.
2. `decimals == 0` delegates to `l10n_int_format(scaled, group_sep)`.
3. Otherwise the magnitude digit string is left-padded with `0` until it is
   at least `decimals + 1` characters long. The last `decimals` characters are
   the fraction, the rest the integer part.
4. The integer part is grouped (section 2 without the sign), `decimal_sep` is
   placed verbatim between the parts, the fraction is emitted as-is, and the
   sign is emitted once in front.
5. **No rounding and no carry ever happens**: the digits are exactly the
   digits of `scaled`. Round first with `l10n_decimal_round` when the value
   must be shortened. The construction is string-based, so it cannot overflow.

Examples: `(12345, 2, ",", ".")` -> `"123.45"`;
`(12345, 1, ",", ".")` -> `"1,234.5"`; `(5, 3, ",", ".")` -> `"0.005"`;
`(50, 3, ",", ".")` -> `"0.050"`; `(-5, 2, ",", ".")` -> `"-0.05"`;
`(12345, 0, ",", ".")` -> `"12,345"`; `(12345, -1, ",", ".")` ->`"12,345"`;
`(1234, 2, ",", "")` -> `"1234"` (the empty `decimal_sep` concatenates).

Complexity: O(digits + decimals). Never fails.

## 4. `l10n_decimal_round(scaled, from_decimals, to_decimals) -> Int`

`from_decimals` and `to_decimals` are clamped to `>= 0` first. If
`to_decimals >= from_decimals` the value already has the wanted precision and
is returned unchanged. Otherwise let `drop = from_decimals - to_decimals`;
the result is `round(scaled / 10^drop)` with **round half away from zero**:

- `drop <= 18`: `div = 10^drop` fits in a signed 64-bit integer;
  `q = scaled / div` and `r = scaled % div` use truncating division, so `q`
  is the floor magnitude and `r` carries the sign of `scaled`. The result is
  `q + 1` when `scaled >= 0 && 2r >= div`, `q - 1` when
  `scaled < 0 && -2r >= div`, else `q`. Exact ties round away from zero.
- `drop == 19`: all magnitude digits are dropped (`|scaled| < 10^19` always).
  The result is `+1`/`-1` exactly when the magnitude has 19 digits and starts
  with `5`..`9` (i.e. `|scaled| >= 5 * 10^18`), else `0`.
- `drop > 19`: the result is `0` (`|scaled| <= 2^63 - 1 < 10^19 <= 10^drop`,
  so the magnitude is below one half).

Rounding never wraps at the 64-bit boundary: the only increment performed is
strictly inside the value's own range.

Examples: `(15, 1, 0)` -> `2`; `(-15, 1, 0)` -> `-2`; `(14, 1, 0)` -> `1`;
`(12355, 2, 0)` -> `124`; `(-12355, 2, 0)` -> `-124`; `(999, 1, 0)` -> `100`;
`(1234, 2, 5)` -> `1234`; `(1234, 2, -1)` -> `12`;
`(5000000000000000000, 19, 0)` -> `1`; `(4999999999999999999, 19, 0)` -> `0`;
`(Int::MIN, 1, 0)` -> `-922337203685477581`.

Complexity: O(min(from - to, 19)). Never fails.

## 5. `l10n_decimal_parse(text, decimal_sep, decimals) -> Result[Int, Str]`

`decimals` is clamped to `>= 0`. The input grammar is:

```
number  := sign? body
sign    := "+" | "-"                  (first byte only, at most once)
body    := element* digit element*    (at least one digit somewhere)
element := digit | group_sep | decimal_sep
group_sep := "," | "_" | " "
```

Rules and semantics:

1. Bytes are scanned left to right. An ASCII digit is accumulated into the
   integer magnitude before the decimal separator and into the fraction
   magnitude after it.
2. `decimal_sep`, when non-empty, is matched byte-wise at the current offset
   and may occur at most once. It takes precedence over the grouping bytes
   (so passing `","` as `decimal_sep` makes comma the fraction boundary).
   When `decimal_sep` is empty no boundary exists: the whole text is an
   integer, and `decimals > 0` right-pads it with zeros.
3. The grouping bytes `,` `_` and space are ignored everywhere, before and
   after the decimal separator, however they are placed (`1,2,3` -> `123`).
   Any other byte is an error.
4. Fewer fraction digits than `decimals` are right-padded with zeros
   (`("1.23", ".", 3)` -> `1230`); more fraction digits than `decimals` are an
   error. The value is
   `integer_digits * 10^decimals + fraction_digits * 10^(decimals - fraction_count)`.
5. The sign is applied once; `"-0"` parses to `0`.
6. The accepted magnitude range is `-(2^63 - 1)` .. `2^63 - 1`. Because the
   magnitude is accumulated positively, `-2^63` is rejected as too large.
7. Validation is left to right and the **first error wins**: a 20-digit
   integer reports "too large" before a later fraction would report "too many
   decimals".

Error catalog (all `Err`, message prefix `l10n: `):

| Condition | Message |
|---|---|
| `text` is empty | `l10n: empty input` |
| no digit anywhere (e.g. `"-"`, `" , "`) | `l10n: no digits` |
| a second `decimal_sep` | `l10n: multiple decimal separators` |
| a byte that is not a digit, a grouping byte or `decimal_sep` | `l10n: unexpected character: <byte>` |
| more fraction digits than `decimals` | `l10n: too many decimals` |
| magnitude would exceed the signed 64-bit range | `l10n: number too large` |

Examples: `("1,234.5", ".", 2)` -> `Ok(123450)`; `("1_234.50", ".", 2)` ->
`Ok(123450)`; `("+12.5", ".", 3)` -> `Ok(12500)`; `("-0.5", ".", 2)` ->
`Ok(-50)`; `("5.", ".", 2)` -> `Ok(500)`; `(".5", ".", 1)` -> `Ok(5)`;
`("1.234", ".", 2)` -> `Err("l10n: too many decimals")`;
`("1.2.3", ".", 2)` -> `Err("l10n: multiple decimal separators")`;
`("1.234,56", ",", 2)` -> `Err("l10n: unexpected character: .")`.

Complexity: O(len(text) + decimals). Never fails outside the catalog.

## 6. `l10n_permille_format(permille, decimals, group_sep, decimal_sep) -> Str`

`decimals` is clamped to `>= 0`; `permille` is an integer in parts per
thousand, so the rendered value is `permille / 10` as a percent number.

- `decimals >= 1`: the magnitude digit string is split before its last digit:
  that last digit (the tenths of the permille) becomes the first fraction
  digit and `decimals - 1` zeros are appended; the integer part is grouped.
  This is an exact string shift -- it never multiplies and cannot overflow,
  even for `Int::MIN`.
- `decimals == 0`: the tenths digit decides round-half-away-from-zero on the
  whole percent (`12345` -> `"1,235"`, `1234` -> `"123"`, `1235` -> `"124"`);
  the sign is dropped when the magnitude rounds to zero (`-4` -> `"0"`).

Examples: `(12345, 1, ",", ".")` -> `"1,234.5"`;
`(12345, 2, ",", ".")` -> `"1,234.50"`; `(5, 1, ",", ".")` -> `"0.5"`;
`(999, 1, ",", ".")` -> `"99.9"`; `(-12345, 1, ",", ".")` -> `"-1,234.5"`;
`(0, 3, ",", ".")` -> `"0.000"`;
`(Int::MIN, 1, ",", ".")` -> `"-922,337,203,685,477,580.8"`.

Complexity: O(digits + decimals). Never fails.

## 7. Test plan (tests/test_conformance.xi, 30 checks)

| # | Name | Expectation |
|---|---|---|
| t1 | grouping 1000 and below | `1000` -> `1,000`; `999`, `100`, `12` ungrouped |
| t2 | grouping millions | `1000000`, `1234567`, `100000`, `12345` grouped from the right |
| t3 | grouping negatives | `-1000` -> `-1,000`; one sign before the groups |
| t4 | grouping zero | `0` -> `"0"` for `","`, `""`, `" "` |
| t5 | custom separators | `"."`, `"_"`, `" "`, `""` and multi-char `"::"` |
| t6 | big integers | `2^63-1` and `Int::MIN` grouped exactly |
| t7 | decimal 1 digit | `(12345,1,",",".")` -> `1,234.5`; negatives; `(5,1)` -> `0.5` |
| t8 | decimal 2/3 digits | `123.45`, `12.345`, `0.123` |
| t9 | decimal 0 digits | equals `l10n_int_format` for positive, negative, zero |
| t10 | zero padding | `0.005`, `0.050`, `0.00`, `1,234.5678` |
| t11 | decimal negatives | `-0.05`, `-123,45` (swapped pair), `-0.050` |
| t12 | negative decimals | clamps to 0; empty `decimal_sep` concatenates |
| t13 | round half away + | `15->2`, `14->1`, `5->1`, `4->0`, `0->0` |
| t14 | round half away - | `-15->-2`, `-14->-1`, `-5->-1`, `-4->0`, `-1->0` |
| t15 | rounding carries | `999->100`, `995->100`, `994->99`, `123456/3/1->1235`, `-995->-100` |
| t16 | rounding no-op | `to >= from` unchanged (`(1234,2,2)`, `(1234,2,7)`, `(-1234,3,3)`, ...) |
| t17 | negative counts clamp | `(1234,2,-1)->12`; `(1234,-5,*)` unchanged |
| t18 | extreme drops | drop 19 -> signed 1/0 at `|scaled| >= 5*10^18`; drop 20 -> 0 |
| t19 | 64-bit boundaries | rounding and formatting exact at `2^63-1` and `Int::MIN` |
| t20 | parse padding | `1.234`/3 -> 1234; `1.23`/3 -> 1230; `1`/3 -> 1000; `0`/5 -> 0; multi-byte `..` separator -> 15 |
| t21 | parse signs/edges | `+12.5`, `-0.5`, `.5`, `5.`, `-0` |
| t22 | parse grouping ignored | space/underscore/comma ignored on both sides |
| t23 | format->parse round-trips | int, decimal and permille outputs parse back |
| t24 | too many decimals | exact `Err("l10n: too many decimals")` in three cases |
| t25 | malformed input | empty, no digits, two separators, bad bytes (incl. `.` with `,` sep) |
| t26 | range limits | `2^63-1` accepted; `2^63`, `-2^63`, 20 nines -> `l10n: number too large` |
| t27 | permille basic | `12345/1`, `12345/2`, `999/1`, `5/1`, `5/3`, swapped pair |
| t28 | permille zero decimals | half away (`12345->1,235`, `1235->124`, `-1235->-124`, `85->9`, `9995->1,000`); `-4->0` |
| t29 | permille extremes | negatives, zeros, `2^63-1`, `Int::MIN` |
| t30 | rounding exact ties | `15000/4/0->2`, `14999->1`, `-15000->-2`, `99999999/8/4->10000` |

Every test folds its sub-checks into one `assert(cond, name)` and `main`
returns the number of failing checks (0 = green). `port.ps1` must end
`port: PASS (passed=30 failed=0 program_exit=0 exit=0)`.

## 8. Compiler / stdlib notes (XIOM v0.61.3)

- Free functions only; no `self` methods, no lambdas, no `Vec[StructType]`;
  the module allocates no vectors at all.
- `Ok`/`Err` are constructed only in the leaf helpers `_parse_ok` and
  `_parse_err`; constructing results inline in a function that returns a
  struct miscompiles on this compiler.
- Byte classification compares `xiom.string.byte_at` against ASCII constants
  below 128 only.
- Matches over `Result` are exhaustive (`Ok`/`Err`); no `mut` patterns.
- `use` statements end with `;`, `module` does not.

## 9. Known limitations

- Scaled-integer values only; no `Float64`, no rationals, no arbitrary
  precision. Parsing covers `-(2^63 - 1)` .. `2^63 - 1`; `-2^63` is rejected.
- ASCII digits only; no non-ASCII digit sets, no bidi marks.
- The ignored grouping set is fixed to `,`, `_` and space; other separators
  (e.g. `.` under a comma-decimal locale) are errors when parsing.
- Grouping is always 2-2-3-free: exactly three digits per group, repeating.
- No currency, percent-sign, scientific, compact or significant-digit
  notation; no locale data of any kind.
- `l10n_decimal_format` never rounds; callers must use `l10n_decimal_round`.
