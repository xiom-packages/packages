# xiom.ean -- Specification

Version: 0.1.0 (`incubating`; implemented, harness-green with compiler
v0.61.3, not published).
Manifest: `package.xi` (`xiom.ean`, version `0.1.0`).
Module: `src/ean.xi` (`module xiom.ean`).
Depends on `xiom.std` (`xiom.string`, `xiom.convert`); no other dependencies.

## Scope

A pure-XIOM (no FFI) EAN/UPC codec for the three canonical GS1 retail code
lengths:

- `ean_parse` / `ean_is_valid`: parse the ASCII digit form of EAN-13 (13
  digits), UPC-A (12 digits) or EAN-8 (8 digits), selected by length, and
  verify the trailing check digit;
- `ean13_parse` / `upca_parse` / `ean8_parse` plus the matching
  `*_is_valid` shorthands: declared-length entry points, so a wrong length is
  a named error;
- `ean13_compute_check_digit` / `upca_compute_check_digit` /
  `ean8_compute_check_digit`: derive the check digit from a body;
- `ean_kind` / `ean_digits` / `ean_body` / `ean_check_digit` /
  `ean_country_prefix`: structure accessors on a parsed code;
- `ean_compact` / `ean_format`: canonical digit emit and grouped display;
- `upca_to_ean13` / `ean13_to_upca` / `ean13_is_upca_equivalent`: the UPC-A
  <-> EAN-13 zero-prefix equivalence.

## Non-goals

- Barcode rendering, fonts, SVG/PNG output, or any symbology encoding
  (EAN-13 / UPC-A / EAN-8 left/right parity patterns are not modeled).
- GS1 registry, company prefix, product, batch or serial validation; no
  prefix-to-country table and no check-digit-external structure rules.
- EAN-2 / EAN-5 add-on codes.
- ITF, Code128, Code39, DataBar and any other symbology.
- ISBN conversion, ISSN conversion, or any GTIN-14 aggregation.
- Lenient input normalization: spaces, hyphens, lowercase digits
  (impossible in ASCII) and other separators are rejected, not normalized.
- Arbitrary-precision arithmetic: every sum fits comfortably in `Int`.

## Data model

```xiom
pub type Ean = {
  kind: Int;    // 8, 12 or 13: the declared type, equal to the digit length
  digits: Str;  // complete code text including the check digit, as parsed
}
```

```xiom
pub const EAN_KIND_EAN8: Int = 8;
pub const EAN_KIND_UPCA: Int = 12;
pub const EAN_KIND_EAN13: Int = 13;
```

`kind` is the full digit length, so a valid `Ean` always satisfies
`digits.len() == kind`. The body length is `kind - 1` and the check digit is
the last byte of `digits`.

## Input grammar (strict)

```
ean     := ean13 / upca / ean8          ; ean_parse: by length
ean13   := DIGIT x 12 DIGIT             ; ean13_parse
upca    := DIGIT x 11 DIGIT             ; upca_parse
ean8    := DIGIT x 7  DIGIT             ; ean8_parse
DIGIT   := "0".."9"
```

No whitespace or separator is allowed anywhere. The byte length equals the
character length because only ASCII digits are admitted.

Validation order is fixed so every malformed input has exactly one
deterministic error:

1. empty input;
2. supported length (generic `ean_parse`) or declared length (typed parsers);
3. every byte is `0-9`;
4. the last digit equals the computed check digit.

For the generic entry point the length must be one of 8, 12, 13; any other
length is reported without inspecting the bytes.

## Check-digit algorithm

For a body `d[0]..d[n-1]` (all ASCII digits):

```
sum = 0
weight = 3
for i = n-1 down to 0:
  sum = sum + int(d[i]) * weight
  weight = 3 - weight            ; alternates 3, 1, 3, 1, ...
check = (10 - (sum mod 10)) mod 10
```

That is the GS1 rule: the rightmost body digit carries weight 3, weights
alternate 3/1 toward the left, and the check digit is the value that makes
the weighted sum of the complete code a multiple of 10. The `mod 10` outside
the parentheses is what yields check digit 0 when `sum mod 10 == 0` (for
example the all-zero code and `4006381333900`).

Worked examples (all covered by the tests):

| Code | Body | Check |
|---|---|---|
| `4006381333931` (EAN-13) | `400638133393` | 1 |
| `5901234123457` (EAN-13) | `590123412345` | 7 |
| `9780201379624` (EAN-13) | `978020137962` | 4 |
| `0036000291452` (EAN-13, zero-prefixed UPC) | `003600029145` | 2 |
| `036000291452` (UPC-A) | `03600029145` | 2 |
| `96385074` (EAN-8) | `9638507` | 4 |
| `9999999999994` (EAN-13, all nines body) | `999999999999` | 4 |
| `0000000000000` (EAN-13, all zeros) | `000000000000` | 0 |

The sum is at most `12 * 9 * 3 = 324`, so `Int` cannot overflow.

## API contract

```xi
pub fn ean_parse(s: Str) -> Result[Ean, Str]
pub fn ean_is_valid(s: Str) -> Bool
pub fn ean13_parse(s: Str) -> Result[Ean, Str]
pub fn ean13_is_valid(s: Str) -> Bool
pub fn upca_parse(s: Str) -> Result[Ean, Str]
pub fn upca_is_valid(s: Str) -> Bool
pub fn ean8_parse(s: Str) -> Result[Ean, Str]
pub fn ean8_is_valid(s: Str) -> Bool
pub fn ean13_compute_check_digit(body: Str) -> Result[Int, Str]
pub fn upca_compute_check_digit(body: Str) -> Result[Int, Str]
pub fn ean8_compute_check_digit(body: Str) -> Result[Int, Str]
pub fn ean_kind(v: &Ean) -> Int
pub fn ean_digits(v: &Ean) -> Str
pub fn ean_body(v: &Ean) -> Str
pub fn ean_check_digit(v: &Ean) -> Int
pub fn ean_country_prefix(v: &Ean) -> Str
pub fn ean_compact(v: &Ean) -> Str
pub fn ean_format(v: &Ean) -> Str
pub fn upca_to_ean13(s: Str) -> Result[Str, Str]
pub fn ean13_to_upca(s: Str) -> Result[Str, Str]
pub fn ean13_is_upca_equivalent(s: Str) -> Bool
```

- `ean_parse` returns `Ok(Ean)` for a valid code of any supported length and
  `Err("ean: ...")` otherwise; `kind` is the detected type.
- Typed parsers behave like `ean_parse` restricted to one length; a
  length mismatch is `ean: bad length for <TYPE>: expected <k>, got <n>`.
- `*_is_valid` are exact boolean shorthands: `true` iff the corresponding
  parser returns `Ok`. Every error collapses to `false`.
- `*_compute_check_digit(body)` accepts exactly `kind - 1` digits and returns
  the check digit in `0..9`. Feeding `body + int_to_string(check)` back to the
  matching parser always succeeds and yields `body` and the same check digit.
- Accessors are total for any `Ean` produced by a parser (they assume the
  invariants above and are not defined for hand-built invalid values).
- `ean_country_prefix` returns exactly the first three digits of `digits`
  (three characters for every supported length). It is an informational
  field only: it is not looked up in a GS1 prefix table, GS1 prefixes are
  2-3 digits in the registry, they identify the issuing member organization
  rather than the country of manufacture, and EAN-8 carries no GS1 company
  prefix at all. Callers must not treat the result as authoritative.
- `ean_compact` returns `digits` (already canonical: digits only, no
  separators). `ean_format` groups for display: EAN-13 as 1-6-6, UPC-A as
  1-5-5-1, EAN-8 as 4-4, single spaces. Display text only; spaces must be
  stripped before parsing.

### UPC-A <-> EAN-13 equivalence

A UPC-A code is exactly an EAN-13 code with a leading zero: the UPC-A
numbering system digit becomes the EAN-13 `0` prefix. Adding the zero does
not change the check digit (the new leading zero carries weight 1 and shifts
every existing weight by one position, and the rightmost body digit keeps
weight 3).

- `upca_to_ean13(s)`: valid UPC-A -> `Ok("0" + s)` (13 digits); any
  `upca_parse` error is returned unchanged.
- `ean13_to_upca(s)`: valid EAN-13 starting with `0` -> `Ok` with the last 12
  digits; valid EAN-13 not starting with `0` -> `ean: not UPC-A equivalent:
  <s>`; invalid input -> the `ean13_parse` error.
- `ean13_is_upca_equivalent(s)`: `true` iff `s` is a valid EAN-13 whose first
  digit is `0`.

Both directions round-trip for the same code:
`ean13_to_upca(upca_to_ean13(s)) == s` for valid UPC-A `s`, and
`upca_to_ean13(ean13_to_upca(s)) == s` for zero-prefixed EAN-13 `s`.

## Error catalog

`ean_parse`, in validation order:

| Condition | Message |
|---|---|
| `s == ""` | `ean: empty input` |
| `len(s)` not 8, 12 or 13 | `ean: bad length: <n> (expected 8, 12 or 13)` |
| a byte not `0-9` | `ean: bad characters: <s>` |
| last digit != computed check | `ean: bad check digit: <s>` |

Typed parsers (`ean13_parse`, `upca_parse`, `ean8_parse`):

| Condition | Message |
|---|---|
| `s == ""` | `ean: empty input` |
| `len(s) != kind` | `ean: bad length for <TYPE>: expected <kind>, got <len(s)>` |
| a byte not `0-9` | `ean: bad characters: <s>` |
| last digit != computed check | `ean: bad check digit: <s>` |

`<TYPE>` is `EAN-13`, `UPC-A` or `EAN-8`; `<kind>` is 13, 12 or 8.

Check-digit helpers:

| Condition | Message |
|---|---|
| `body == ""` | `ean: empty input` |
| `len(body) != kind - 1` | `ean: bad body length for <TYPE>: expected <kind-1>, got <len(body)>` |
| a byte not `0-9` | `ean: bad characters: <body>` |

Equivalence helper `ean13_to_upca` adds:

| Condition | Message |
|---|---|
| valid EAN-13, first digit != `0` | `ean: not UPC-A equivalent: <s>` |

No other error strings exist; there are no panics and no exceptions. Every
failing input maps to exactly one class by the order above, and messages are
deterministic (no allocation-dependent text).

## Complexity

| Operation | Time | Space |
|---|---|---|
| `ean_parse` / typed parsers | O(1) (length <= 13) | O(1) |
| `*_is_valid` | O(1) | O(1) |
| `*_compute_check_digit` | O(1) | O(1) |
| `ean_compact` | O(1) | O(1) |
| `ean_format` | O(1) | O(1) output |
| accessors | O(1); `ean_body` O(kind) output | O(1) |
| equivalence helpers | O(1) | O(1) output |

The algorithms are written length-generically but every supported input is at
most 13 bytes.

## Test plan

`tests/test_conformance.xi` (`module ean_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Every valid fixture was independently re-checked
against a separate implementation of the GS1 check-digit rule before being
pinned. Dispatch is a direct `t1..t20` call chain, never a `Vec[fn]` table.

| # | Coverage |
|---|---|
| 1 | EAN-13 fixtures: `kind`, `ean_body`, `ean_check_digit`, `ean_digits` field by field (4 codes); |
| 2 | EAN-13 typed parse + `ean13_is_valid`, including a one-digit mutation; |
| 3 | EAN-8 fixtures: structure, typed parse + `ean8_is_valid`; |
| 4 | UPC-A fixtures: structure, typed parse + `upca_is_valid`; |
| 5 | `*_compute_check_digit` reproduces seven fixtures' check digits; |
| 6 | compute -> build -> parse -> compact round-trip for all three types; |
| 7 | all-zero boundaries at all three lengths (check digit 0); |
| 8 | all-nines boundaries: check digits 4 (EAN-13), 3 (UPC-A), 5 (EAN-8); |
| 9 | zero check digit: computed 0 accepted, parsed and round-tripped; |
| 10 | `ean_parse` auto-detects 8/12/13; `ean_is_valid` agrees; |
| 11 | empty input error for every parser entry point; |
| 12 | declared-type bad length messages with exact expected/got counts; |
| 13 | generic unsupported-length messages (7, 9, 14); |
| 14 | non-digit bytes -> `bad characters` for every typed parser and the generic one; |
| 15 | check-digit mismatch -> `bad check digit` for all three types; |
| 16 | compute-helper error catalog: empty, per-type body length, charset; |
| 17 | UPC-A <-> EAN-13 equivalence in both directions, plus "not UPC-A equivalent" and wrapped check-digit errors; |
| 18 | grouped display for all three grouping schemes; |
| 19 | `ean_compact` round-trip and the informational 3-digit prefix field; |
| 20 | accessor consistency: `body + check` reconstructs `digits`, repeated calls agree. |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.ean
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Check-digit consistency only: a valid check digit does not mean GS1
  assigned or recognizes the code. `0000000000000` and `9999999999994` are
  accepted by design; GS1 would never assign the all-zero GTIN.
- No GS1 prefix/company/product semantics and no prefix-to-country table;
  `ean_country_prefix` is informative only (see above).
- No checks on check-digit-external structure (for example restricted
  distribution ranges such as prefix `02`, `04`, `20`-`29`).
- Strict digit-only compact input; no normalization of spaced or hyphenated
  display text.
- No EAN-2 / EAN-5 add-ons, no GTIN-14, no ISBN/ISSN conversion, no barcode
  rendering.
- Check digits catch typos, not fraud: a single-digit mutation is detected,
  but a coordinated multi-digit change can pass.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, lambdas or `Vec[fn]` dispatch; one public
  struct (`Ean`), no `Vec[StructType]` and no vectors at all.
- `Ok`/`Err` are constructed only in leaf helpers (`_ean_ok`, `_ean_err`,
  `_int_ok`, `_int_err`, `_str_ok`, `_str_err`); parsers build the struct
  value first and then call the matching leaf.
- No `Str` equality is performed anywhere in the library module, so BUG 17
  (`==` on `Str`) is not reachable; the tests compare with
  `xiom.string.compare.str_compare`.
- Every `UInt8` widening masks (`(b as Int) & 255`); all byte constants are
  below 128.
- `&Ean` parameters are always called with a local bound from a `match`
  (`Ok(v) => ... &v`), never with a `&struct.field` expression.
- No `xiom.string.builder` use: all text is concatenation of validated ASCII
  slices, so the NUL-byte abort path is unreachable.
- The module declares no `extern "C"` blocks (no FFI) and imports only
  `xiom.string` and `xiom.convert`.
