# xiom.humanize -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.humanize` (`src/humanize.xi`). Pure XIOM, no FFI.

## 1. Scope

Five total functions that render integers as human-readable text:

- `humanize_bytes` -- byte counts with decimal (1000) or binary (1024) units,
- `humanize_duration_ms` -- millisecond durations in a compact ms/s/m/h/d form,
- `humanize_count` -- a count with an explicit singular and plural form,
- `humanize_ordinal` -- English ordinals (`1st`, `2nd`, `21st`, `111th`),
- `humanize_list` -- a conjunction-joined list of strings.

All functions are total (no error channel) and use integer arithmetic only:
no floating point, no locale data, no allocation beyond the returned `Str`.
The only dependency is `xiom.convert.int_to_string`.

## 2. Non-goals

- Floating-point or fractional inputs (no `Float64` overloads).
- Locale-aware output: no translations, decimal separators, or language rules.
- Configurable unit tables, custom suffixes, or bits/bytes variants.
- Calendar-aware durations (months, years) or ISO 8601 output.
- Escaping or quoting of list elements.

## 3. Rules

Notation: `dec` is the clamped fraction-digit count, `base` is the unit base,
and `|x|` is the magnitude of `x`.

### 3.1 `humanize_bytes(n: Int, decimals: Int, binary: Bool) -> Str`

1. **Decimals clamp.** `dec = decimals` clamped to `0..3`. Values outside are
   clamped, never rejected: `-5` -> `0`, `9` -> `3`.
2. **Unit base and suffixes.**
   - `binary == true`: `base = 1024`, suffixes `B, KiB, MiB, GiB, TiB, PiB`.
   - `binary == false`: `base = 1000`, suffixes `B, KB, MB, GB, TB, PB`.
3. **Unit selection.** The unit index `u` is the largest `k` in `0..5` with
   `|n| >= base^k`; otherwise `u = 0`. So `999` stays in `B`, `1000` becomes
   `KB`, `1023` stays in `B`, `1024` becomes `KiB`.
4. **Rounding.** The printed magnitude is
   `round_half_away_from_zero(|n| * 10^dec / base^u)`: a discarded tail of
   exactly half rounds away from zero in both directions
   (`1550` at 1 digit -> `1.6 KB`; `1450` at 1 digit -> `1.5 KB`;
   `2500` at 0 digits -> `3 KB`; `1536` binary at 0 digits -> `2 KiB`).
5. **Formatting.** With `dec == 0` the magnitude prints as a plain integer
   (base-unit values therefore keep integer form: `999 B`, `512 B`). With
   `dec > 0` exactly `dec` fraction digits are printed, zero-padded, separated
   by `.` (`1.50 MB`, `0.00 B`, `512.00 B`).
6. **Sign.** The sign is applied once, at the front: `-1536` at 1 digit ->
   `-1.5 KB`. The magnitude is rounded before the sign is applied, so the
   result is symmetric for `n` and `-n`.
7. **Layout.** The number and the suffix are separated by exactly one space:
   `1.5 MB`, `2 KiB`, `999 B`.
8. **64-bit edges.** The computation is arranged so no intermediate overflows;
   `9223372036854775807` -> `9223 PB` / `8192 PiB` and
   `-9223372036854775808` -> `-9223 PB` / `-8192 PiB` are exact at 0 digits.

### 3.2 `humanize_duration_ms(ms: Int) -> Str`

1. **Non-positive input.** `ms <= 0` -> `"0ms"`.
2. **Buckets.** The buckets are fixed and the leader is always printed:
   - `0..999` -> `"<ms>ms"` (`850` -> `"850ms"`),
   - `1000..59999` -> `"<s>s"` with `s = ms / 1000` floored (`45000` ->
     `"45s"`, `1500` -> `"1s"`, `59999` -> `"59s"`),
   - `60000..3599999` -> `"<m>m <s>s"` (`125000` -> `"2m 5s"`),
   - `3600000..86399999` -> `"<h>h <m>m"` (`3780000` -> `"1h 3m"`),
   - `>= 86400000` -> `"<d>d <h>h"` (`187200000` -> `"2d 4h"`).
3. **Component omission.** In the multi-component buckets the trailing
   component is omitted when zero, never the leading one:
   `60000` -> `"1m"`, `120000` -> `"2m"`, `3600000` -> `"1h"`, `7200000` ->
   `"2h"`, `86400000` -> `"1d"`, `2678400000` -> `"31d"`.
4. **Flooring.** Every bucket boundary floors smaller units first, so
   `59999` -> `"59s"` and `86399999` -> `"23h 59m"`; days are unbounded.

### 3.3 `humanize_count(n: Int, singular: Str, plural_form: Str) -> Str`

1. If `n == 1 || n == -1` (magnitude 1) the result is
   `int_to_string(n) + " " + singular`: `"1 item"`, `"-1 item"`.
2. Otherwise the result is `int_to_string(n) + " " + plural_form`, including
   zero: `"2 items"`, `"0 items"`, `"-2 items"`, `"100 items"`.

### 3.4 `humanize_ordinal(n: Int) -> Str`

1. The suffix is chosen from the magnitude's last two digits `m = |n| % 100`:
   `11`, `12`, `13` -> `th`; else last digit `1` -> `st`, `2` -> `nd`,
   `3` -> `rd`; else `th`.
2. The digits of `n` are printed unchanged (sign included):
   `1st`, `2nd`, `3rd`, `4th`, `11th`, `12th`, `13th`, `21st`, `101st`,
   `111th`, `121st`; `-21` -> `"-21st"`, `-111` -> `"-111th"`.
3. `0` -> `"0th"`, `100` -> `"100th"`.

### 3.5 `humanize_list(items: &Vec[Str], conjunction: Str) -> Str`

1. `n == 0` -> `""` (empty string).
2. `n == 1` -> the single element, verbatim.
3. `n == 2` -> `"<a> <conjunction> <b>"`, e.g. `"a and b"`, `"a or b"`.
4. `n >= 3` -> every element except the last followed by `", "`, then the last
   joined with the conjunction; the Oxford comma is omitted:
   `"a, b and c"`, `"a, b, c and d"`, `"a, b, c, d and e"`.
5. The conjunction is used verbatim (`"or"`, `"&"`, `"plus"`); an empty
   conjunction produces two spaces around the final join. Elements are not
   escaped or quoted.

## 4. API signatures

```xi
pub fn humanize_bytes(n: Int, decimals: Int, binary: Bool) -> Str
pub fn humanize_duration_ms(ms: Int) -> Str
pub fn humanize_count(n: Int, singular: Str, plural_form: Str) -> Str
pub fn humanize_ordinal(n: Int) -> Str
pub fn humanize_list(items: &Vec[Str], conjunction: Str) -> Str
```

Complexity: `humanize_bytes` is O(1); the others are O(digits) or O(total
bytes of the input); nothing allocates beyond the result and small
intermediates.

## 5. Test plan

`tests/test_conformance.xi` (module `humanize_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Every `Str` comparison is routed through
`xiom.string.compare.str_compare` (see section 7). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | bytes: zero and sub-unit | `0 B`, `0.00 B`, `999 B`, `512.00 B`; base-unit integers |
| t2 | bytes: unit ladder start | 1000/1024 -> `1 KB`/`1 KiB`, 1023 -> `1023 B` |
| t3 | bytes: 1536 both bases | 0 digits round up (`2 KB`), 1 digit `1.5 KB`/`1.5 KiB` |
| t4 | bytes: decimal ladder | KB, MB, GB, TB, PB |
| t5 | bytes: binary ladder | KiB, MiB, GiB, TiB, PiB |
| t6 | bytes: 1000000 differs | `1 MB` vs `977 KiB`, `976.6`/`976.56 KiB` |
| t7 | bytes: 0..3 digits | `2 MB`, `1.5 MB`, `1.50 MB`, `1.500 MB` |
| t8 | bytes: clamping | `-5`/`-1` -> 0 digits; `9`/`7` -> 3 digits |
| t9 | bytes: half-away rounding | 1550/1450/1449/2500/2400 at 0..1 digits |
| t10 | bytes: negative sign | `-1.5 KB`, `-500 B`, `-2 KiB` |
| t11 | bytes: 64-bit edges | Int max/min on both bases |
| t12 | duration: ms bucket | `0ms`, negatives, `1ms`, `850ms`, `999ms` |
| t13 | duration: second bucket | flooring and the 60000 minute edge (`1m`) |
| t14 | duration: minute bucket | `2m 5s`, trailing zero omitted (`2m`) |
| t15 | duration: hour bucket | `1h 3m`, `2h`, `23h 59m` |
| t16 | duration: day bucket | `1d`, `1d 1h`, `2d 4h`, `31d` |
| t17 | count | magnitude-1 singular, plural, zero, negatives |
| t18 | ordinal: 1..13 | `st/nd/rd/th` and the 11..13 exceptions |
| t19 | ordinal: large | 21, 101, 111..113, 120, 121 |
| t20 | ordinal: negative | sign kept, magnitude suffix |
| t21 | list: empty/one | `""` and the element |
| t22 | list: two/three | `and`/`or`, Oxford comma omitted |
| t23 | list: four/five | every element rendered |
| t24 | list: conjunction verbatim | `&`, `plus` |

## 6. Known limitations

- The byte rules are opinionated: fixed suffix tables, 0..3 fraction digits,
  no `bits`, no significant-digit heuristics, decimal point always `.`.
- The duration rules are opinionated: exactly two components, floor
  truncation, no weeks/months/years, no ISO 8601.
- No locale: ordinals and counts assume English-style forms and the caller
  supplies both noun forms and the conjunction.
- `humanize_list` does not escape or quote elements.
- No `Result` error channel anywhere: every input is valid.

## 7. Compiler / stdlib notes

- The implementation uses only `xiom.convert.int_to_string`; the tests use
  `xiom.test`, `xiom.io` and `xiom.string.compare`.
- The tests route every `Str` equality through `str_compare`, never `==`
  (BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
  pointer comparison).
- The byte formatter relies on the language's truncated-toward-zero integer
  division/remainder (the same semantics `xiom.l10n.number`'s rounding helper
  relies on); magnitudes of quotients and remainders stay below `base`, so no
  intermediate can overflow and the 64-bit minimum is handled exactly.
- No `Result`/`Ok`/`Err` values are constructed, so the v0.61.3 struct-return
  `Ok`/`Err` codegen bug does not apply. No compiler workarounds required.
