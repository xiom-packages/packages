# xiom.duration -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.duration` (`src/duration.xi`). Pure XIOM, no FFI.

## 1. Scope

Strict ISO 8601 duration parsing and canonical formatting, with flat
accessors and a restricted whole-seconds helper:

- parse a duration string into a flat `Duration` value (`duration_parse`),
- render a `Duration` back in canonical form (`duration_format`),
- inspect the sign, per-component presence, per-component values and the
  second-fraction text (`duration_sign`, `duration_has_*`, `duration_value`,
  `duration_fraction`),
- convert a time-only duration to whole seconds (`duration_total_seconds`).

All inputs are in-memory `Str` values; failures are `Err("duration: ...")`
strings (section 6). The module never allocates vectors and uses no floating
point.

## 2. Non-goals

- No calendar arithmetic: months, years and weeks never convert to seconds,
  days or each other.
- No conversion to/from timestamps, epoch seconds, `xiom.time.Duration` or
  clock values.
- No relaxed ISO 8601 forms: no lowercase designators, no comma decimal
  separator, no embedded whitespace, no repeated `P`/`T` sections, no
  fractional components other than seconds, no `-` on individual components.
- No arbitrary-precision integers and no `Float64` math: components fit a
  signed 64-bit `Int`, and the second fraction is kept as text.
- No multiple durations, durations ranges, or recurring intervals.
- No FFI, file I/O or registry integration.

## 3. Grammar

```
duration  := [ sign ] "P" [ date-part ] [ "T" time-part ]
sign      := "+" | "-"
date-part := [ n "Y" ] [ n "M" ] [ n "W" ] [ n "D" ]   ; in that order
time-part := [ n "H" ] [ n "M" ] [ n "S" ]             ; in that order
n         := 1*digit                       ; leading zeros allowed
seconds   := n [ "." 1*9digit ]            ; fraction kept as text
```

Equivalently: components appear in the fixed order `Y M W D` (date part) and
`H M S` (time part), each at most once, with at least one component overall
and at least one time component when `T` is present. `M` means months in the
date part and minutes in the time part. The `.` fraction is only recognized
on the seconds component. Every byte is matched case-sensitively.

Accepted: `P0D`, `PT0S`, `-P1Y`, `+PT0.5S`, `P1Y2M3W4DT5H6M7S`, `PT1.250S`.
Rejected: `P`, `PT`, `P1DT`, `P1D2Y`, `P1Y1Y`, `P1H`, `PT1D`, `PT1.5H`,
`p1d`, `1D`, `PT1.1234567890S`, `P1D2H` (hours before `T`).

## 4. Data model

```xiom
pub type Duration = {
  sign: Int;
  years: Int;
  months: Int;
  weeks: Int;
  days: Int;
  hours: Int;
  minutes: Int;
  seconds: Int;
  fraction: Str;
}
```

The representation is flat: nine scalar fields, no nested structures and no
vectors (the module contains no `Vec` at all). `sign` is 1 for an unsigned or
`+` duration and -1 for a `-` duration. The seven components are
non-negative. `fraction` is the validated fraction digit text exactly as
written (`"5"` for `PT0.5S`, `"05"` for `PT0.05S`) and `""` when the duration
has no fraction. The parser stores no presence flags, so a component that was
written as zero (`P0D`) is indistinguishable from an absent one (`PT0S`):
`duration_has_*` therefore reports non-zero values, not textual presence.

## 5. Parsing rules

1. **Sign.** One optional leading `+` or `-` byte; anything else leaves the
   sign at 1. `sign` is preserved for zero durations, so `-P0D` parses with
   `sign == -1`.
2. **Prefix.** `P` is required immediately after the optional sign. `""` is
   `empty input`; any other prefix byte (including lowercase `p`) is
   `missing P`.
3. **Digit policy.** Each component's integer is a run of one or more ASCII
   digits. Leading zeros are accepted (`P000000001D` is 1 day) and a digit
   run of any length is accepted when its value stays in range. The value
   must fit a signed 64-bit `Int`
   (`9223372036854775807`); larger values are `number too large`. `Int`
   division and floating point are not used anywhere in parsing.
4. **Component order.** Within a section the component indexes must be
   strictly increasing (`Y < M < W < D`, `H < M < S`). A lower index is
   `bad component order`; an equal index is `duplicate component`.
5. **Sections.** `Y`, `W` and `D` belong to the date part; `H` and `S` to the
   time part; `M` resolves to months in the date part and minutes in the time
   part. A designator of the other section is `bad component order`
   (`P1H`, `PT1D`, `PT1Y`).
6. **T.** At most one `T` is allowed and it must be followed by at least one
   time component: `PT`, `P1DT`, `P0DT` are `T without components`; a second
   `T` is `trailing tokens`. At least one component overall is required, so
   `P`, `+P`, `-P` are `empty duration`.
7. **Seconds fraction.** A fraction is recognized when the byte immediately
   after the seconds integer is `.`. It must be 1..9 ASCII digits followed by
   the `S` designator. Zero digits, more than 9 digits, a missing designator,
   or a designator other than `S` are `bad fraction` (`PT1.S`, `PT1.`,
   `PT1.1234567890S`, `PT1.5`, `PT1.5H`, `P1.5D`). The fraction digits are
   stored verbatim, including leading and trailing zeros; no numeric
   conversion or rounding is performed.
8. **Component starts.** At a component position a digit starts a number; a
   designator byte with no number before it is `bad number` (`PD`, `P1YD`);
   any other byte is `trailing tokens` (`P1D!`, `P1D 2H`, `P1DX`). A number
   that is not followed by a valid designator is `bad number` (`P1`,
   `P1X`, `PT1H2`, `P1D2`).
9. **End of input.** After the scan, a `T` section with no time component is
   reported as `T without components` (checked before the overall component
   count), then a duration with no components is `empty duration`.
10. **Error precedence.** Scanning is single-pass, so the first violation
    reached is reported: for a string that is both out of order and a
    duplicate, the order violation appears first.

## 6. Error catalog

Every parse error starts with `duration: ` and embeds the whole input string.

| Condition | Message | Examples |
|---|---|---|
| empty input | `duration: empty input` | `""` |
| missing `P` | `duration: missing P: <s>` | `1D`, `p1d`, `-`, `+`, `T1H` |
| no components | `duration: empty duration: <s>` | `P`, `+P`, `-P` |
| `T` with empty time part | `duration: T without components: <s>` | `PT`, `P1DT`, `P0DT` |
| order violation | `duration: bad component order: <s>` | `P1D2Y`, `P1M2Y`, `PT1S2H`, `P1H`, `PT1D` |
| repeated component | `duration: duplicate component: <s>` | `P1Y1Y`, `PT1M1M`, `PT1.5S1.5S` |
| number or designator malformed | `duration: bad number: <s>` | `P1X`, `P1`, `PD`, `P1YD`, `PT1H2` |
| seconds fraction malformed | `duration: bad fraction: <s>` | `PT1.S`, `PT1.`, `PT1.1234567890S`, `PT1.5H` |
| junk after a component | `duration: trailing tokens: <s>` | `P1D!`, `P1D 2H`, `P1DX`, `PT1HT2H` |
| component above `Int` | `duration: number too large: <s>` | `P9223372036854775808D` |
| `duration_value` unknown name | `duration: unknown component: <name>` | `duration_value(d, "centuries")` |
| `duration_total_seconds` date part | `duration: has date components: <canonical>` | total of `P1D` |
| `duration_total_seconds` fraction | `duration: has fractional seconds: <canonical>` | total of `PT0.5S` |
| `duration_total_seconds` overflow | `duration: total seconds overflow: <canonical>` | total of `PT2562047788015216H` |

## 7. Canonical formatting

`duration_format` emits, in order:

1. `-` when `sign < 0` (a `+` is never emitted), then `P`;
2. every non-zero date component in the order `Y M W D`, each as its decimal
   value (leading zeros are dropped) and designator;
3. `T` when at least one time part is emitted, then every non-zero hour and
   minute component in order, then the seconds part when `seconds != 0` or a
   fraction is present. The seconds part is `seconds` with `"." + fraction`
   when the fraction is non-empty. The fraction text is copied verbatim, so
   `PT0.50S` and `-PT0.0500S` are their own canonical forms;
4. when nothing was emitted, `0D` after the prefix, so the canonical form of
   every zero duration is `P0D` (or `-P0D` when the sign is negative).
   `+P1D`, `P01D` and `PT0S` are therefore not canonical.

| Input | Canonical form |
|---|---|
| `P1D` | `P1D` |
| `P1Y0M0W0DT0H0M0S` | `P1Y` |
| `+P1D` | `P1D` |
| `P01D` | `P1D` |
| `PT0S` | `P0D` |
| `P0DT0H` | `P0D` |
| `-P0D` | `-P0D` |
| `PT0.50S` | `PT0.50S` |
| `P1Y2M3W4DT5H6M7S` | `P1Y2M3W4DT5H6M7S` |

Round-trip contract: for every canonical `s`, `duration_format` of
`duration_parse(s)` is exactly `s`; for every parsed `d`,
`duration_parse(duration_format(d))` has the same fields as `d`; and
formatting is idempotent. Non-canonical inputs are normalized (see the table)
rather than rejected.

## 8. API signatures

```xi
pub fn duration_parse(s: Str) -> Result[Duration, Str]
pub fn duration_format(d: &Duration) -> Str
pub fn duration_sign(d: &Duration) -> Int
pub fn duration_has_years(d: &Duration) -> Bool
pub fn duration_has_months(d: &Duration) -> Bool
pub fn duration_has_weeks(d: &Duration) -> Bool
pub fn duration_has_days(d: &Duration) -> Bool
pub fn duration_has_hours(d: &Duration) -> Bool
pub fn duration_has_minutes(d: &Duration) -> Bool
pub fn duration_has_seconds(d: &Duration) -> Bool
pub fn duration_value(d: &Duration, component: Str) -> Result[Int, Str]
pub fn duration_fraction(d: &Duration) -> Str
pub fn duration_total_seconds(d: &Duration) -> Result[Int, Str]
```

- `duration_has_seconds` is true when the seconds value is non-zero **or** a
  fraction is present (`PT0.5S` has seconds).
- `duration_value` accepts exactly the lowercase names `years`, `months`,
  `weeks`, `days`, `hours`, `minutes`, `seconds`; anything else (including
  `Years` and `""`) is `unknown component`. The fraction is not a component
  value; use `duration_fraction`.
- `duration_total_seconds` returns
  `Ok(sign * (hours*3600 + minutes*60 + seconds))` only when all four date
  components are zero and no fraction is present. It refuses date components
  (calendar arithmetic is out of scope), refuses fractions (they are text and
  would be silently dropped), and refuses totals above
  `9223372036854775807` (`total seconds overflow`). The date check runs
  before the fraction check and both run before the overflow checks.
- Complexities: `duration_parse` is O(len(s)); `duration_format` is
  O(non-zero components + len(fraction)); the accessors are O(1) except
  `duration_value`, which is O(len(component)); `duration_total_seconds` is
  O(digits + len(fraction)).

The emitter trusts a hand-built `Duration`: components are assumed
non-negative and `sign` is assumed to be -1 or 1, as produced by the parser.

## 9. Test plan

`tests/test_conformance.xi` (module `duration_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | date components | `Y M W D` values, defaults 0 |
| t2 | time components | `H M S` values, defaults 0, date+time mix |
| t3 | full form + signs | all seven values, `-`/`+`/unsigned sign |
| t4 | zero forms | `P0D`, `PT0S`, `P0Y0M0W0D`, `P0000D` accepted, all flags false |
| t5 | leading zeros + bounds | long zero-padded runs, `Int` max, `number too large` |
| t6 | fraction text | `0.5`, `1.250`, `0.05`, 9 digits, verbatim retention |
| t7 | duplicates | all seven components plus a repeated fractional second |
| t8 | date order | decreasing date designators rejected, valid orders accepted |
| t9 | time order + sections | decreasing time designators, `P1H`, `PT1D`, `P1T1H` |
| t10 | empty/T | `""`, `P`, `+P`, `-P`, `PT`, `P1DT`, `P1YT`, `P0DT` |
| t11 | missing `P` | digits/letters/space prefixes, bare `+`/`-` |
| t12 | bad number | junk or missing designator, number-less designator |
| t13 | bad fraction | 0/10 digits, non-`S` designator, missing designator |
| t14 | trailing tokens | punctuation, spaces, junk letters, second `T` |
| t15 | has-* accessors | all seven flags, `PT0.5S` has seconds, zero has none |
| t16 | value by name | all seven names, unknown/case-sensitive/empty names |
| t17 | fraction accessor | `""` or exact text, no truncation of trailing zeros |
| t18 | canonical round-trip | format(parse(s)) == s for canonical s |
| t19 | zero omission | zero components dropped, zero canonicalizes to `P0D` |
| t20 | sign + fraction format | `-P0D`, verbatim fractions, hand-built structs |
| t21 | total seconds | time-only durations, signs, zero date components |
| t22 | total seconds errors | date, fraction, exact `Int` max and overflow |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`.

## 10. Known limitations

- **`Int`-bounded components.** `years`..`seconds` are signed 64-bit values;
  larger components are rejected (`number too large`). The total-seconds
  helper additionally bounds `hours*3600 + minutes*60 + seconds` to the same
  range.
- **Text fraction.** The fraction is never converted to a number, so
  `duration_total_seconds` has no fractional answer and refuses instead. No
  rounding or normalization of the fraction text is performed.
- **No calendar math.** `P1M` and `P1Y` have no second count in this module.
- **ASCII only.** Designators and digits are ASCII; any other byte (including
  a multi-byte UTF-8 character) simply fails validation via the trailing /
  missing-`P` paths. NUL cannot occur in a valid duration and is not special
  cased.
- **No presence flags.** `has_*` reports non-zero values; `P0D` cannot be
  distinguished from `PT0S`.
- **Trusted emitter input.** Hand-built `Duration` values with negative
  components or a sign other than ±1 are emitted as-is.

## 11. Compiler / stdlib notes

No compiler workarounds were needed beyond the standard wave-29 precautions
on v0.61.3:

- `Result[Duration, Str]` carries a struct payload, so `Ok`/`Err` are
  constructed only in leaf helpers (`_duration_ok`, `_duration_err`,
  `_int_ok`, `_int_err`); `_duration_scan` never writes `Ok`/`Err` inline.
- Every `xiom.string.byte_at` read is widened with `as Int` and masked with
  `& 0xFF`; byte constants are `Int` constants.
- No `==` on `Str` values: `duration_value` uses
  `xiom.string.compare.str_compare`.
- Free functions only; the module declares no `Vec`, no `Vec[StructType]`,
  no `Vec[Float64]`, no `fn`-typed values and no generic `[T, U]` helpers.
- The one first-run failure was a test-authoring bug: two total-seconds
  inputs mistakenly placed the hours component before `T`
  (`P<max>HT...`), which the parser correctly rejects as
  `bad component order`. The fix was in the test strings; the module was
  green on the next run.
