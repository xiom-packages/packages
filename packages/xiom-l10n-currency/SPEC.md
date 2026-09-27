# xiom.l10n-currency -- Specification

Version: 0.1.0 (`incubating`; implemented, harness-green with compiler
v0.61.3, not published).
Manifest: `package.xi` (`xiom.l10n-currency`, version `0.1.0`).
Module: `src/l10n_currency.xi` (`module xiom.l10n.currency`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.compare`, `xiom.convert`);
no other dependencies, no FFI.

## Name mapping

The manifest name is the dotted package name `xiom.l10n-currency`. The
importable module name must be a dotted identifier chain: compiler v0.61.3
rejects `-` inside a `module` declaration (`error[P001] ... expected
declaration, found '-'`), so the module is `xiom.l10n.currency` and the
manifest `modules` field lists it. Consumers write `use xiom.l10n.currency;`.

## Scope

A pure-XIOM ISO 4217 currency codec and exact-money helper:

- embedded, documented currency table with alpha/numeric/exponent/name/symbol;
- lookups by alpha (case-insensitive), numeric (zero-padded), name, symbol;
- `l10n_currency_is_valid` and the `alpha` <-> `numeric` cross-check;
- `Money` in minor units (`Int`) with parse and format, no floats anywhere;
- integer half-up rounding for extra-precision amounts, per-currency and
  generic.

## Non-goals

- Locale databases, CLDR data, symbol placement rules, grouping conventions
  or currency-specific number patterns: separators and style are parameters.
- Exchange rates, conversion, fee or payment routing semantics.
- Cash rounding rules (0.05 CHF rounds, Swedish rounding, etc.).
- Historical/withdrawn ISO codes, precious-metal codes and the `N.A.` codes
  (see the cut-off), cryptocurrency codes, and unofficial symbols.
- Arbitrary-precision arithmetic: amounts are 64-bit signed minor units.

## Data model

```xiom
pub type Currency = {
  alpha: Str;      // exactly 3 ASCII letters, uppercase in the table
  numeric: Str;    // exactly 3 ASCII digits, zero padded ("008")
  exponent: Int;   // minor-unit exponent: 0, 2, 3 or 4
  name: Str;       // English ISO name, unique in the table
  symbol: Str;     // common prefix symbol or "" (no suffix symbols)
}

pub type Money = {
  alpha: Str;      // currency alpha the amount belongs to
  minor: Int;      // value * 10^exponent, signed
  exponent: Int;   // exponent captured at parse time (informational)
}
```

`Money.minor` is exact: USD 12.34 is `minor = 1234`, JPY 1234 is
`minor = 1234` (exponent 0), CLF 1.2345 is `minor = 12345` (exponent 4).
The value range is the 64-bit signed `Int` range; every parse path guards
magnitudes before multiplying so overflow cannot wrap.

`Currency` rows are compiled into three explicit `if` chains (`_bank_a`,
`_bank_b`, `_bank_c`) of one-line row builders behind the `_row(i)`
dispatcher; module-level table initializers are mis-materialized by v0.61.3,
so there is no runtime table object. Each bank returns the `_missing`
sentinel (empty alpha, exponent -1) past its end; public functions never
expose the sentinel.

## Table cut-off

Source: ISO 4217 "List One" (SIX Financial Information), published
2026-09-17. Included: the 165 active entries that carry a numeric minor-unit
exponent. Excluded: the 13 active entries whose `CcyMnrUnts` is `N.A.` --
XAU, XAG, XPT, XPD (precious metals), XDR (SDR), XBA, XBB, XBC, XBD (bond
market units), XSU (Sucre), XUA (ADB unit), XTS (testing), XXX (no
currency). They have no minor-unit semantics, so parse/format cannot be
defined; every one is an `unknown currency` / `unknown numeric code` here.
Also excluded: historical codes and non-ISO symbols.

Class counts (asserted by the integrity test):

| exponent | rows | examples |
|---|---|---|
| 0 | 17 | JPY, KRW, CLP, ISK, VND, XOF, XAF, XPF, BIF, PYG, UGX, UYI, VUV, RWF, GNF, DJF, KMF |
| 2 | 139 | USD, EUR, GBP, CNY, ... |
| 3 | 7 | BHD, IQD, JOD, KWD, LYD, OMR, TND |
| 4 | 2 | CLF, UYW |
| total | 165 | |

Names are unique; the official list has two entries named "Bolívar
Soberano", so the VED row is "Bolívar Soberano (VED)" while VES keeps the
official name. Symbols are unique; when the conventional symbol is a suffix
(`kr`, `zł`, `Ft`) the row stores `""` and formats with the code. CAD uses
"CA$" so that the table symbol set stays duplicate-free (NIO keeps "C$").

## Lookup semantics

| Function | Input rule | Success | Failure |
|---|---|---|---|
| `by_alpha` | exactly 3 ASCII letters, case-insensitive | row | `bad currency code: <code>` (shape) / `unknown currency: <code>` |
| `by_numeric` | exactly 3 ASCII digits, zero-padded | first row with that numeric | `bad numeric code: <code>` / `unknown numeric code: <code>` |
| `by_name` | non-empty, ASCII case-insensitive | row with that name | `unknown currency name: <name>` |
| `by_symbol` | non-empty | first row with that symbol | `bad symbol: <symbol>` / `unknown currency symbol: <symbol>` |
| `at(index)` | `0 <= index < count` | row | `index out of range: <index>` |
| `is_valid(code)` | any | `Bool` | never (errors collapse to `false`) |
| `cross_check(alpha, numeric)` | any | `Bool` | never (errors collapse to `false`) |

`cross_check` returns `true` only when both inputs have the right shape and
the resolved alpha row carries exactly that numeric text. `by_symbol` is a
first-match scan; the table keeps non-empty symbols unique, so the first
match is the only match.

## Parse grammar

`l10n_currency_parse_amount(text, cur, decimal_sep, group_sep)`:

```
amount   := sign? prefix? space* body
sign     := "+" | "-"
prefix   := cur.symbol                       ; verbatim bytes, when non-empty
          | cur.alpha                        ; ASCII case-insensitive
space    := 0x20 (one or more, only after the prefix)
body     := int_part (decimal_sep frac_part)?
int_part := (digit | group_sep)*
frac_part:= digit*
```

Rules:

- `decimal_sep` and `group_sep` are exact caller-supplied strings (matched
  whole, so multi-byte separators work); an empty `group_sep` disables
  grouping, an empty `decimal_sep` disables fraction recognition.
- The sign must come first; `-` and `+` set the sign, `-0` parses to `0`.
- The prefix is optional and is only tried at the position right after the
  sign, before any digit; `group_sep` and spaces inside the body are not
  allowed before it.
- At most one `decimal_sep`; a second occurrence is an error.
- The integer part may be empty when a fraction is present (".5"); a trailing
  `decimal_sep` is allowed and means zero fraction digits.
- At most `cur.exponent` fraction digits; the first excess digit is an error
  at its own byte offset.
- Missing digits anywhere (`"$"`, `"-"`, `""`) are errors.
- Magnitude: the integer scan refuses a digit that would push the running
  magnitude past `Int` max; after scanning, scaling the integer part by
  `10^exponent` and adding the scaled fraction are both guarded, so an
  overflowing input can never wrap.
- `Money.exponent` is `cur.exponent`; `Money.alpha` is `cur.alpha`.

Validation is strictly left to right, so every malformed input has exactly
one deterministic error. `l10n_currency_parse_amount_code` resolves the
alpha first (`l10n_currency_by_alpha`) and propagates its error, so a
malformed or unknown code is reported before any text scanning.

## Format rules

`l10n_currency_format_amount(m, group_sep, decimal_sep, use_symbol, paren_negative)`:

1. Resolve `m.alpha` with `l10n_currency_by_alpha`; failure is
   `Err("l10n-currency: ...")`.
2. Split the magnitude `|m.minor|` into digit text; right-pad with leading
   zeros to at least `exponent + 1` digits so the integer part is never
   empty. The fraction is the last `exponent` digits.
3. Group the integer digits in threes from the right, separated by
   `group_sep` (empty disables grouping; multi-byte separators allowed).
4. Prefix: `alpha + " "` always, replaced by `symbol` alone when
   `use_symbol` is true and the row has a non-empty symbol (a row without a
   symbol therefore falls back to the code form).
5. Sign: `m.minor < 0` renders `"-" + prefix + body` normally, and
   `"(" + prefix + body + ")"` when `paren_negative` is true. `minor == 0`
   is never negative.

Examples: `(123456, USD)` -> `"USD 1,234.56"` / `"$1,234.56"`;
`(-123456, USD, parens)` -> `"($1,234.56)"`; `(1234, JPY)` ->
`"¥1,234"`; `(1234, BHD)` -> `"BHD 1.234"`; `(1, CLF)` -> `"CLF 0.0001"`;
`(5, USD)` -> `"$0.05"`; `(0, USD)` -> `"$0.00"`.

`Money.exponent` is informational: formatting uses the table exponent of the
resolved row, so a hand-built `Money` with a stale exponent still formats at
the currency's own scale.

## Rounding rules

`l10n_currency_round_half_up(scaled, from_decimals, to_decimals)`:

- Both counts clamp to `>= 0`; `to_decimals >= from_decimals` is a no-op
  (scale-up is not performed).
- Otherwise `drop = from - to` and the result is
  `round(scaled / 10^drop)` with **halves away from zero**:
  `25 -> 3`, `-25 -> -3`, `15 -> 2`, `-15 -> -2`, `14 -> 1`, `-14 -> -1`.
  The sign is handled explicitly (`q = scaled / div`, `r = scaled % div`
  with truncation toward zero; for negatives the tie test uses `-r`), so the
  truncating `%` never silently rounds a negative tie toward zero.
- Carries propagate through `q + 1` / `q - 1`; `995 -> 100`, `-995 -> -100`.
- `drop == 19` is special-cased (the divisor does not fit an `Int`): a
  signed `1` when the magnitude has at least 19 digits and its lead digit is
  `>= 5`, else `0`. `drop > 19` yields `0` because no 64-bit magnitude can
  reach half of that divisor.
- The 64-bit minimum cannot be produced by negation (magnitudes are
  accumulated as non-negative `Int`s and negated only when non-zero).

`l10n_currency_round_to_currency(scaled, from_decimals, cur)`:

- Resolves `cur.exponent` and rounds as above when `from_decimals >=
  exponent`; returns `Ok(minor)`.
- `from_decimals < exponent` is
  `Err("l10n-currency: scale up not supported: from <a> to <b>")`: scaling
  up is a multiplication that the caller must do deliberately because it can
  overflow.
- A hand-built `cur` with the sentinel exponent (`< 0`) is
  `Err("l10n-currency: bad currency: <alpha>")`.

## Error catalog

Lookups (all messages are `"l10n-currency: " + ...`, deterministic):

| Condition | Message |
|---|---|
| alpha not 3 ASCII letters | `bad currency code: <code>` |
| alpha well formed, absent from table | `unknown currency: <code>` |
| numeric not 3 ASCII digits | `bad numeric code: <code>` |
| numeric well formed, absent | `unknown numeric code: <code>` |
| empty name or no name match | `unknown currency name: <name>` |
| empty symbol | `bad symbol: <symbol>` |
| symbol not found | `unknown currency symbol: <symbol>` |
| index < 0 or >= count | `index out of range: <index>` |

Parse (`l10n_currency_parse_amount` / `_code`), left to right:

| Condition | Message |
|---|---|
| `text == ""` | `empty input` (no offset: there is no byte) |
| no digit anywhere (e.g. `"$"`, `"-"`) | `no digits at byte <end>` |
| byte that is neither digit, separator nor space | `unexpected character at byte <i>` |
| second `decimal_sep` | `multiple decimal separators at byte <i>` |
| fraction digit beyond `exponent` | `too many decimals at byte <i>` |
| digit scan would overflow `Int` | `number too large at byte <i>` |
| scale-up or add would overflow | `number too large at byte <end>` |
| `cur` sentinel / bad code via `_code` | `bad currency: <alpha>` / lookup error |

Format: the lookup error of `m.alpha`, or
`l10n-currency: unknown currency: <alpha>` for the unreachable tail.

## API signatures

```xi
pub fn l10n_currency_count() -> Int
pub fn l10n_currency_at(index: Int) -> Result[Currency, Str]
pub fn l10n_currency_by_alpha(code: Str) -> Result[Currency, Str]
pub fn l10n_currency_by_numeric(code: Str) -> Result[Currency, Str]
pub fn l10n_currency_by_name(name: Str) -> Result[Currency, Str]
pub fn l10n_currency_by_symbol(symbol: Str) -> Result[Currency, Str]
pub fn l10n_currency_is_valid(code: Str) -> Bool
pub fn l10n_currency_cross_check(alpha: Str, numeric: Str) -> Bool
pub fn l10n_currency_money_alpha(m: &Money) -> Str
pub fn l10n_currency_money_minor(m: &Money) -> Int
pub fn l10n_currency_money_exponent(m: &Money) -> Int
pub fn l10n_currency_parse_amount(text: Str, cur: &Currency, decimal_sep: Str, group_sep: Str) -> Result[Money, Str]
pub fn l10n_currency_parse_amount_code(text: Str, alpha: Str, decimal_sep: Str, group_sep: Str) -> Result[Money, Str]
pub fn l10n_currency_format_amount(m: &Money, group_sep: Str, decimal_sep: Str, use_symbol: Bool, paren_negative: Bool) -> Result[Str, Str]
pub fn l10n_currency_round_half_up(scaled: Int, from_decimals: Int, to_decimals: Int) -> Int
pub fn l10n_currency_round_to_currency(scaled: Int, from_decimals: Int, cur: &Currency) -> Result[Int, Str]
```

## Complexity

| Operation | Time | Space |
|---|---|---|
| `at` / `by_*` / `is_valid` / `cross_check` | O(165) bounded scan | O(1) |
| `parse_amount` | O(len(text)) | O(1) |
| `format_amount` | O(digits) | O(digits) output |
| `round_half_up` / `round_to_currency` | O(min(drop, 19)) | O(1) |

The table is compiled into comparison chains (no runtime data structure, no
`Vec[Str]` in the library at all).

## Test plan

`tests/test_conformance.xi` (`module l10n_currency_tests`, 24 named tests;
the hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count):

1. exponent 0 rows (all 17);
2. exponents 2 (spot), 3 (all 7) and 4 (both);
3. alpha lookup: case variants, validity, malformed/unknown, cut-off code XAU;
4. numeric lookup: `840/978/008/392/048/990/532`, bad width, non-digit, `999`
   and `959` (XXX/XAU) absent;
5. name lookup: majors, lowercase, unknown and empty;
6. symbol lookup: `$`, `€`, `£`, `¥`, `₹`, `₩`, unknown and empty;
7. cross-check matches, mismatches, malformed; 8. `count`/`at`/out-of-range;
9. table integrity: 165 rows, unique alpha/numeric/symbol, 3-char widths,
   ascending order, exponent class counts 17/139/7/2;
10. parse exponent 2 (`1,234.56` / `1.234,56` / prefixes / `.5` / `5.`);
11. signs (`-$5.00`, `-EUR 5,00`, `+0.50`, `-0.00`);
12. parse exponent 0 with the exact fraction-rejection offset;
13. parse exponent 3 with the 4th-digit offset;
14. parse exponent 4 with the 5th-digit offset;
15. offsets: unexpected char, space without group, second separator, no
    digits, 20-digit overflow at byte 18;
16. late overflow at end of input, bad/unknown code propagation;
17. format exponent 2: code/symbol, minus/parens, zero padding, de-DE pair;
18. format exponents 0/3/4, symbol fallback with a symbol-less row, negative
    parens for a 3-decimal currency;
19. format errors: unknown and malformed alpha;
20. half-up: both signs, ties, below-half, zero;
21. half-up: carries, no-op scales, clamped counts, 19-digit drops;
22. `round_to_currency` drops and the scale-up refusal;
23. parse -> format round-trips for exponents 0/2/3/4 in both locale pairs;
24. `Money` accessors: `-0.00` is 0, alpha/exponent captured, `+` ignored.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.l10n-currency
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Compiler / stdlib notes for v0.61.3

- Free functions only, no methods, lambdas or `Vec[fn]` dispatch; the test
  dispatch is the direct call chain `t1..t24`.
- `Ok`/`Err` are constructed only in leaf helpers (`_cur_ok`, `_cur_err`,
  `_money_ok`, `_money_err`, `_str_ok`, `_str_err`, `_int_ok`, `_int_err`);
  callers build the struct in a local first and pass it to the leaf.
- Two functions may not share a name even with different arities: the row
  builder is `_mk_row` while the dispatcher is `_row` (a single name for
  both was the one real trap hit during porting: the later definition
  shadowed the earlier and every row call reported `argument 1 type
  mismatch: expected Int, found Str`).
- All `Str` equality uses `xiom.string.compare.str_compare`; `==` is never
  applied to `Str`.
- Every `UInt8` widening masks (`(b as Int) & 255`); all byte constants are
  below 128. Symbols are UTF-8 literals in the table and are only ever
  compared or concatenated whole, never indexed.
- No `xiom.string.builder` use: text is built from validated slices and
  literals, so no NUL-byte abort path exists.
- Hand-rolled because `xiom.std` lacks them: ASCII case-insensitive compare
  (`_eq_ci`), three-digit grouping (`_group_digits`), magnitude digits
  (`_abs_digits`), half-away-from-zero rescaling, and substring matching with
  offsets (`_matches_at` / `_matches_ci_at`).
