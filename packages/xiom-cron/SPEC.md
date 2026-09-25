# xiom.cron -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.cron`, version `0.1.0`).
Module: `src/cron.xi` (`module xiom.cron`).
Depends on `xiom.std`; the library module imports `xiom.string`,
`xiom.string.compare` and `xiom.convert` from it (tests add `xiom.test`,
`xiom.io` and `xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) parser, validator, canonical emitter and describer for
classic 5-field cron expressions:

- `cron_parse` validates an expression (or one of the documented `@`-macros)
  and returns a `CronExpr`;
- `cron_valid` is the boolean fast path;
- `cron_field_count` / `cron_field_at` and the five named count/at pairs are
  the accessors over the flat per-field value sets;
- `cron_emit` renders canonical five-field text;
- `cron_describe` renders a labelled human-readable summary;
- `cron_expand_macro` expands a macro to its canonical five-field text;
- every rejection path returns a deterministic `Err(Str)` message.

## Non-goals

- **No next-fire computation and no date math.** The package never converts
  an expression into calendar instants, never advances a clock and never
  implements cron's day-of-month/day-of-week OR tie-break rule (that rule
  only matters for occurrence selection).
- No seconds field, no 6-field or 7-field Quartz/Spring variants, no year
  field, no `H`, `L`, `W`, `#` or `?` operators.
- No timezone, DST, locale or calendar logic.
- No scheduler, timer, retry or job state.
- No expression-level boolean logic (`@reboot`-style pseudo-macros beyond the
  documented table, `CRON_TZ=`, environment prefixes).
- No business-day, holiday or "last day of month" semantics.
- No batch or streaming API: one expression in, one value set out.
- The sets are per-field; the classic "day-of-month vs day-of-week" firing
  interaction is not represented.

## Data model

```xiom
pub type CronExpr = {
  minutes: Vec[Int];  // 0..59, sorted ascending, unique
  hours: Vec[Int];    // 0..23, sorted ascending, unique
  days: Vec[Int];     // 1..31, sorted ascending, unique
  months: Vec[Int];   // 1..12, sorted ascending, unique
  dows: Vec[Int];     // 0..6, sorted ascending, unique, Sunday = 0
}
```

Five flat parallel vectors, not `Vec[StructType]` (unsupported in XIOM
v0.61.3). `cron_parse` guarantees the sorted/unique/in-range invariant;
accessors and renderers rely on it. Hand-built `CronExpr` values must satisfy
the same invariant; no validation function is provided for them.

Field indices are exported as `CRON_FIELD_MINUTE` = 0, `CRON_FIELD_HOUR` = 1,
`CRON_FIELD_DAY` = 2, `CRON_FIELD_MONTH` = 3 and `CRON_FIELD_DOW` = 4.

## Grammar

```
expression := macro | field SP+ field SP+ field SP+ field SP+ field
macro      := "@hourly" | "@daily" | "@midnight" | "@weekly"
            | "@monthly" | "@yearly" | "@annually"
field      := item ("," item)*
item       := "*" | value | value "-" value
            | "*" "/" step | value "-" value "/" step
value      := digits | month-name | dow-name
step       := digits
digits     := digit+                      ; leading zeros accepted
month-name := "JAN" | "FEB" | ... | "DEC" ; case-insensitive
dow-name   := "SUN" | "MON" | ... | "SAT" ; case-insensitive
SP         := " " | "\t" | "\r" | "\n"
```

Field order and ranges:

| # | Field | Index constant | Range | Names |
|---|---|---|---|---|
| 1 | minute | `CRON_FIELD_MINUTE` | 0..59 | -- |
| 2 | hour | `CRON_FIELD_HOUR` | 0..23 | -- |
| 3 | day-of-month | `CRON_FIELD_DAY` | 1..31 | -- |
| 4 | month | `CRON_FIELD_MONTH` | 1..12 | `JAN`..`DEC` |
| 5 | day-of-week | `CRON_FIELD_DOW` | 0..7 (0 and 7 = Sunday) | `SUN`..`SAT` |

Tokenization rules:

- Leading and trailing whitespace is ignored; one or more whitespace bytes
  (space, tab, CR, LF) separate fields.
- Names are exactly three letters; matching is case-insensitive
  (`jan`, `Jan`, `JAN` are equal). Longer or shorter spellings are unknown
  values.
- A step is allowed only after `*` or a range; `5/2` is a bad token.
- An item contains at most one `/`; a base contains at most one `-`.
- Empty list items (`,,`, a leading or a trailing comma) are errors.
- A `@`-macro must be the whole trimmed expression and exactly one token;
  any other input whose first byte is `@` reports
  `cron: bad macro: <text>`, where `<text>` is the source slice from the
  first token's first byte to the last token's last byte (outer whitespace
  trimmed, internal whitespace preserved verbatim).

### Macro table

| Macro | Equivalent | Canonical emit |
|---|---|---|
| `@hourly` | `0 * * * *` | `0 * * * *` |
| `@daily` | `0 0 * * *` | `0 0 * * *` |
| `@midnight` | `0 0 * * *` | `0 0 * * *` |
| `@weekly` | `0 0 * * 0` | `0 0 * * 0` |
| `@monthly` | `0 0 1 * *` | `0 0 1 * *` |
| `@yearly` | `0 0 1 1 *` | `0 0 1 1 *` |
| `@annually` | `0 0 1 1 *` | `0 0 1 1 *` |

Macro names are matched exactly (lowercase, leading `@`).

## Semantics

- **Set semantics.** A field denotes the set of values its items select:
  - `*` selects every value in the field range (for day-of-week, raw 0..7);
  - `a` selects `{a}`;
  - `a-b` selects every integer in `a..b` (inclusive);
  - `*/n` selects `lo, lo+n, lo+2n, ...` up to the field high bound;
  - `a-b/n` selects `a, a+n, ...` up to `b`.
  A list is the union of its items. The stored set is the union of all
  selected values, sorted ascending and deduplicated.
- **Steps.** `n` must be a positive decimal integer; a step larger than the
  range yields just the start value (`50-59/100` selects `{50}`,
  `*/100` selects `{0}`). Accumulation of oversized numeric tokens is capped
  so arbitrarily long digit runs stay in range and are reported out of range.
- **Day-of-week normalization.** Inputs accept 0..7; 7 is Sunday. Every
  produced value is normalized (7 -> 0) before being stored, then the set is
  deduplicated, so `0,7` is `{0}`, `5-7` is `{0,5,6}` and `0-7` is `{0..6}`.
  Range order is checked on the raw values, so `5-7` is a valid increasing
  range while `7-0` is `cron: range start > end`.
- **Range order.** `a > b` is an error; there is no wrap-around reversal.
  Checking order inside one item is: slash count, step syntax, step > 0,
  `*` detection, hyphen shape, start value, end value, `a > b`.
- **Leading zeros.** Digit runs are decimal and may carry leading zeros
  (`07`, `0007` select 7). The value parser caps accumulation at a small
  bound before the range check, so no overflow is possible.
- **Empty field.** A field cannot be empty: consecutive whitespace and
  leading/trailing whitespace are skipped, never producing an empty token;
  an empty token can therefore only come from a comma (list item).

## Canonical renderings

`cron_emit(c)` returns exactly five single-space-separated fields. A field
whose stored set equals its whole range renders as `*`; otherwise values are
rendered in ascending order, comma-separated, with every maximal run of two
or more consecutive values rendered as `a-b`:

| Stored set | Emitted |
|---|---|
| full range | `*` |
| `{0,30,59}` | `0,30,59` |
| `{1,2,4,5}` | `1-2,4-5` |
| `{0,5,6}` | `0,5-6` |
| `{0,15,30,45}` | `0,15,30,45` |

Rendering is **set-canonical, not syntax-preserving**: steps and input order
are expanded, so `*/15 * * * *` emits `0,15,30,45 * * * *`, and `@yearly`
emits `0 0 1 1 *`. Round-trip identity holds at the set level:
`cron_parse(cron_emit(parse(x)))` has exactly the same five value vectors as
`parse(x)`.

`cron_describe(c)` renders five labelled segments joined by `"; "`, in field
order: `minute`, `hour`, `day-of-month`, `month`, `day-of-week`. Each segment
uses the same `*` / list / run notation as `cron_emit`, except that month and
day-of-week values use canonical three-letter uppercase names:

```
minute 0,30; hour 9-17; day-of-month *; month JAN,JUL; day-of-week MON-FRI
```

For a full wildcard expression: `minute *; hour *; day-of-month *; month *;
day-of-week *`. For `@yearly`: `minute 0; hour 0; day-of-month 1; month JAN;
day-of-week *`.

## API contract

```xi
pub const CRON_FIELD_MINUTE: Int = 0;
pub const CRON_FIELD_HOUR: Int = 1;
pub const CRON_FIELD_DAY: Int = 2;
pub const CRON_FIELD_MONTH: Int = 3;
pub const CRON_FIELD_DOW: Int = 4;

pub type CronExpr = { minutes: Vec[Int]; hours: Vec[Int]; days: Vec[Int];
                      months: Vec[Int]; dows: Vec[Int]; }

pub fn cron_parse(expr: Str) -> Result[CronExpr, Str]
pub fn cron_valid(expr: Str) -> Bool
pub fn cron_expand_macro(macro_name: Str) -> Result[Str, Str]
pub fn cron_emit(c: &CronExpr) -> Str
pub fn cron_describe(c: &CronExpr) -> Str
pub fn cron_field_name(field: Int) -> Str
pub fn cron_field_count(c: &CronExpr, field: Int) -> Int
pub fn cron_field_at(c: &CronExpr, field: Int, i: Int) -> Int
pub fn cron_minute_count(c: &CronExpr) -> Int
pub fn cron_minute_at(c: &CronExpr, i: Int) -> Int
pub fn cron_hour_count(c: &CronExpr) -> Int
pub fn cron_hour_at(c: &CronExpr, i: Int) -> Int
pub fn cron_day_count(c: &CronExpr) -> Int
pub fn cron_day_at(c: &CronExpr, i: Int) -> Int
pub fn cron_month_count(c: &CronExpr) -> Int
pub fn cron_month_at(c: &CronExpr, i: Int) -> Int
pub fn cron_dow_count(c: &CronExpr) -> Int
pub fn cron_dow_at(c: &CronExpr, i: Int) -> Int
```

`cron_parse` accepts a documented macro or exactly five fields; any other
field count is `cron: expected 5 fields, got <n>` (after the macro branch).
`cron_valid` returns `false` for every input `cron_parse` rejects and never
returns an error itself.

`cron_field_count` returns 0 for an unknown field index; `cron_field_at`
returns -1 for an unknown field index, for `i < 0`, and for `i >= count`.
`cron_field_name` returns `""` for an unknown field index. The named
accessors are thin wrappers over the generic pair.

`cron_expand_macro` returns the canonical emit of the macro's expression
(see the macro table) or `Err("cron: bad macro: <name>")`; it accepts the
same names `cron_parse` does and nothing else (including `""`, `"hourly"`,
`"@DAILY"` and `"@daily extra"`).

## Error catalog

All messages are deterministic and start with `"cron: "`. `<field>` is one
of `minute`, `hour`, `day-of-month`, `month`, `day-of-week`. `<token>` is
the offending source slice and `<n>` the actual field count.

| Condition | Message |
|---|---|
| `""` or whitespace only | `cron: empty expression` |
| non-macro field count != 5 | `cron: expected 5 fields, got <n>` |
| input starts with `@` but is not exactly one known macro | `cron: bad macro: <trimmed text>` |
| `cron_expand_macro`: not a known macro name | `cron: bad macro: <name>` |
| empty list item (`,,`, `,a`, `a,`) | `cron: empty list item in <field>` |
| unknown token or name | `cron: unknown value: <token> in <field>` |
| numeric value outside the field range | `cron: value out of range: <token> in <field>` |
| step is zero (`*/0`, `1-5/0`) | `cron: step must be > 0 in <field>` |
| missing step (`*/`, `1-5/`) | `cron: bad step in <field>` |
| non-digit step (`*/x`, `*/2x`) | `cron: bad step: <step> in <field>` |
| malformed item (`1-2-3`, `-5`, `5-`, `5/2`, `*/2/3`) | `cron: bad token: <item> in <field>` |
| range start greater than end (`5-1`, `JUL-JAN`) | `cron: range start > end: <range> in <field>` |

Examples of the exact texts:

```
cron_parse("")                -> Err("cron: empty expression")
cron_parse("   ")             -> Err("cron: empty expression")
cron_parse("* * *")           -> Err("cron: expected 5 fields, got 3")
cron_parse("@daily x")        -> Err("cron: bad macro: @daily x")
cron_parse("1,,2 * * * *")    -> Err("cron: empty list item in minute")
cron_parse("x * * * *")       -> Err("cron: unknown value: x in minute")
cron_parse("60 * * * *")      -> Err("cron: value out of range: 60 in minute")
cron_parse("*/0 * * * *")     -> Err("cron: step must be > 0 in minute")
cron_parse("*/ * * * *")      -> Err("cron: bad step in minute")
cron_parse("*/x * * * *")     -> Err("cron: bad step: x in minute")
cron_parse("5/2 * * * *")     -> Err("cron: bad token: 5/2 in minute")
cron_parse("5-1 * * * *")     -> Err("cron: range start > end: 5-1 in minute")
```

Precedence inside a field: fields are parsed left to right and the first
failing item wins. Inside an item the checks run in the order listed under
"Range order" above. Inside a range, the start value is reported before the
end value (`70-80` reports `70`).

## Complexity

| Operation | Complexity |
|---|---|
| `cron_parse` | O(len(expr)) plus O(field span) per `*`/step item |
| `cron_valid` | same as `cron_parse` |
| `cron_expand_macro` | O(field span) |
| accessors | O(1) |
| `cron_emit` / `cron_describe` | O(total stored values) |

Memory: one 60-slot presence vector per field during parse and at most 60
stored values per field; parsing is allocation-bounded by the field ranges,
not by input size.

## Test matrix

`tests/test_conformance.xi` (`module cron_tests`, 25 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test and returns the failure
count). No `Vec[fn]` dispatch: every test is called directly.

| # | Name | Covers |
|---|---|---|
| 1 | wildcard | all five full ranges, first/last values |
| 2 | single values | one-entry fields and exact values |
| 3 | lists | multiple items, unsorted input, duplicates |
| 4 | ranges | inclusive spans, explicit full ranges, `a-a` |
| 5 | steps | `*/n` from each field's low bound |
| 6 | range steps | `a-b/n`, oversized steps, dow wrap |
| 7 | names | `JAN-DEC`, `SUN-SAT`, mixed case |
| 8 | day-of-week | 0/7 normalization, `0,7`, `5-7`, `6-7` |
| 9 | macros | field sets of all seven macros |
| 10 | macro expansion | canonical text and bad-macro errors |
| 11 | macro parity | macro vs. literal field-for-field equality |
| 12 | emit | runs as `a-b`, full fields as `*`, normalization |
| 13 | round-trip | `parse(emit(parse(x)))` field parity on 8 inputs |
| 14 | describe | labelled summaries incl. names |
| 15 | empty | `""` and whitespace-only inputs |
| 16 | field count | 1, 3, 4 and 6 field inputs |
| 17 | out of range | every field's bounds, oversized digits |
| 18 | unknown value | bad names in each field, name in wrong field |
| 19 | step errors | zero, missing, non-digit, trailing digit |
| 20 | bad token | `1-2-3`, `5/2`, `-5`, `5-`, `*/2/3`, names with a dangling hyphen |
| 21 | range order | reversed ranges, equal ends accepted |
| 22 | empty list item | `,,`, leading and trailing commas |
| 23 | accessors | bounds, names, generic + named accessors, constants |
| 24 | `cron_valid` | true/false matrix |
| 25 | whitespace | multiple spaces, tabs, CRLF, leading zeros |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.cron
```

Last verified: compiler 0.61.3,
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Set-based, syntax-lossy parse: steps, item order and macro spelling do not
  survive a parse/emit round trip; only the selected sets do.
- No next-fire computation, no date math, no timezone/DST, no scheduler.
- No seconds/6-field variants, no year field, no `H`/`L`/`W`/`#`/`?`.
- Reversed ranges are errors (no wrap-around), and the day-of-week `7-0`
  spelling is therefore also an error.
- Names are exact three-letter abbreviations; no full month/weekday names.
- Macros are exact and lowercase and must be the entire expression.
- Day-of-month and day-of-week sets are independent; the classic
  firing-time OR interaction between them is outside the scope of a parser.
- Leading zeros are accepted (`07` = `7`).
- `cron_emit`/`cron_describe` assume the documented sorted/unique/in-range
  invariant; hand-built `CronExpr` values are not re-validated.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_cron_expr_ok`,
  `_cron_expr_err`, `_cron_str_ok` and `_cron_str_err` (constructing Results
  inline in larger functions miscompiles).
- Every byte read from a `Str` goes through `(string.byte_at(...) as Int) &
  0xFF` before comparison or arithmetic, so no raw `UInt8` is ever compared
  against a constant.
- Every `Vec[Int]` element read is bound to a typed local
  (`let x: Int = v[i];`) before use (untyped reads can mis-lower).
- `&mut Vec[Int]` parameters are passed with an explicit `&mut` at every call
  site; a value passed without it would be copied and the writes lost.
- Month/day name matching is byte arithmetic (uppercased byte triplets
  compared against hex codes); no `Vec[Str]` is used anywhere, so no
  `Vec[Str]` element comparison is needed.
- No `Vec[StructType]`, no `Vec[Float64]`, no lambdas, no methods, no indexed
  `Vec[fn]` dispatch.
- `Str` equality in the library and tests goes through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a `Vec[Str]` element
  lowers to a pointer comparison).
