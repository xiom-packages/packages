# xiom.cron

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** parsing, validation, canonical emission and human-readable
> description of classic 5-field cron expressions (plus the standard
> `@daily`-style macros).
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library uses
> `xiom.string.byte_at`, `xiom.string.str_slice`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.cron` turns a cron expression into a flat, queryable value set and back
into canonical text:

- **parse** -- `cron_parse("0,30 9-17 * * MON-FRI")` validates the five
  fields and returns a `CronExpr`;
- **access** -- `cron_field_count` / `cron_field_at` and the five named
  pairs read the sorted, duplicate-free values of each field;
- **emit** -- `cron_emit(&c)` renders canonical text
  (`"0,30 9-17 * * 1-5"`);
- **describe** -- `cron_describe(&c)` renders a labelled summary
  (`"minute 0,30; hour 9-17; day-of-month *; month *; day-of-week MON-FRI"`);
- **macros** -- `@hourly @daily @midnight @weekly @monthly @yearly
  @annually` parse directly and `cron_expand_macro` expands them to their
  five-field text;
- **validate** -- `cron_valid(expr)` is the boolean fast path.

Parsing is set-based and intentionally syntax-lossy: every field reduces to
its sorted, duplicate-free value set, so `*/15` and `0,15,30,45` parse to the
same expression and emit identically. This is a codec for expressions, not a
scheduler: it never computes a next firing time.

## Quick start

```xi
use xiom.cron;
use xiom.io;

fn main() -> Int {
  let parsed = cron_parse("0,30 9-17 * * MON-FRI");
  match parsed {
    Ok(c) => {
      io.println(cron_emit(&c));          // 0,30 9-17 * * 1-5
      io.println(cron_describe(&c));      // minute 0,30; hour 9-17; day-of-month *; month *; day-of-week MON-FRI
      io.println(cron_minute_count(&c));  // 2
      io.println(cron_minute_at(&c, 0));  // 0
      io.println(cron_minute_at(&c, 1));  // 30
      io.println(cron_dow_at(&c, 4));     // 5 (Friday)
    },
    Err(e) => { io.println(e); },
  }
  io.println(cron_valid("@daily"));       // true
  io.println(cron_valid("@sometimes"));   // false
  match cron_expand_macro("@weekly") {
    Ok(text) => { io.println(text); },    // 0 0 * * 0
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API

All names are free functions in module `xiom.cron`; there are no methods.

| Function | Returns | Description |
|---|---|---|
| `cron_parse(expr)` | `Result[CronExpr, Str]` | Parse the five fields or a macro; sets are sorted and deduplicated. |
| `cron_valid(expr)` | `Bool` | `true` exactly when `cron_parse` succeeds. |
| `cron_expand_macro(name)` | `Result[Str, Str]` | Canonical five-field text of one of the seven macros. |
| `cron_emit(c)` | `Str` | Canonical expression: `*` for full fields, `a-b` runs, ascending lists. |
| `cron_describe(c)` | `Str` | Labelled summary; months and weekdays use `JAN`..`DEC` / `SUN`..`SAT`. |
| `cron_field_name(field)` | `Str` | `"minute"`, `"hour"`, `"day-of-month"`, `"month"`, `"day-of-week"`, else `""`. |
| `cron_field_count(c, field)` | `Int` | Number of allowed values in a field; `0` for an unknown field index. |
| `cron_field_at(c, field, i)` | `Int` | Value `i` of a field in ascending order; `-1` out of range. |
| `cron_minute_count(c)` / `cron_minute_at(c, i)` | `Int` | Minutes `0..59`. |
| `cron_hour_count(c)` / `cron_hour_at(c, i)` | `Int` | Hours `0..23`. |
| `cron_day_count(c)` / `cron_day_at(c, i)` | `Int` | Days of month `1..31`. |
| `cron_month_count(c)` / `cron_month_at(c, i)` | `Int` | Months `1..12`. |
| `cron_dow_count(c)` / `cron_dow_at(c, i)` | `Int` | Days of week `0..6`, Sunday = `0`. |

Field indices for the generic accessors are exported as
`CRON_FIELD_MINUTE` (0), `CRON_FIELD_HOUR` (1), `CRON_FIELD_DAY` (2),
`CRON_FIELD_MONTH` (3) and `CRON_FIELD_DOW` (4).

```xiom
pub type CronExpr = {
  minutes: Vec[Int];  // 0..59, sorted, unique
  hours: Vec[Int];    // 0..23, sorted, unique
  days: Vec[Int];     // 1..31, sorted, unique
  months: Vec[Int];   // 1..12, sorted, unique
  dows: Vec[Int];     // 0..6, sorted, unique, Sunday = 0
}
```

The five fields are flat parallel vectors (no `Vec[StructType]`); they are
guaranteed sorted, duplicate-free and in range by `cron_parse`. Accessors
return `Int` values only, so callers never share library state.

## Expression grammar at a glance

```
expression := macro | minute SP hour SP dom SP month SP dow
macro      := "@hourly" | "@daily" | "@midnight" | "@weekly"
            | "@monthly" | "@yearly" | "@annually"
item       := "*" | "a" | "a-b" | "*/n" | "a-b/n"
field      := item ("," item)*
```

| Field | Range | Names |
|---|---|---|
| minute | `0..59` | -- |
| hour | `0..23` | -- |
| day-of-month | `1..31` | -- |
| month | `1..12` | `JAN`..`DEC` (case-insensitive) |
| day-of-week | `0..7` (0 and 7 = Sunday) | `SUN`..`SAT` (case-insensitive) |

Fields are separated by spaces, tabs, CRs or LFs; surrounding whitespace is
ignored. Values are decimal digit runs and leading zeros are accepted
(`07` = `7`). A step must be a positive decimal integer and is allowed only
after `*` or a range (`5/2` is rejected). A range with start greater than end
is rejected; there is no reversal. See `SPEC.md` for the exact grammar,
evaluation order and error catalog.

## Error model

Every failure is `Err("cron: ...")` with a deterministic message; there are
no panics, no silent defaults and no partial results. The catalog:

| Condition | Message |
|---|---|
| empty or whitespace-only input | `cron: empty expression` |
| not exactly 5 fields (non-macro) | `cron: expected 5 fields, got <n>` |
| `@`-input that is not exactly one known macro | `cron: bad macro: <text>` |
| empty list item (`,,`, leading or trailing comma) | `cron: empty list item in <field>` |
| unknown token or name | `cron: unknown value: <token> in <field>` |
| numeric value outside the field range | `cron: value out of range: <token> in <field>` |
| step is zero | `cron: step must be > 0 in <field>` |
| step is missing or not all digits | `cron: bad step in <field>` / `cron: bad step: <step> in <field>` |
| malformed item (`1-2-3`, `-5`, `5-`, `5/2`, `*/2/3`) | `cron: bad token: <token> in <field>` |
| range start greater than end | `cron: range start > end: <range> in <field>` |

`<field>` is one of `minute`, `hour`, `day-of-month`, `month`,
`day-of-week`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.cron
```

Expected tail: 25 `[PASS]` lines, `xiom.cron: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No next-fire computation and no date math.** The package describes
  which values each field selects; it never maps an expression to calendar
  instants and does not implement cron's day-of-month/day-of-week OR rule.
- **Classic 5 fields only.** No seconds field, no 6/7-field Quartz variants,
  no year field, no `H` hash, no `L`/`W`/`#`/`?` operators.
- **No timezone or DST logic**, no scheduler, timers or state of any kind.
- **Parsing is set-based and syntax-lossy**: steps and input order do not
  survive a parse/emit round trip (`*/15` emits as `0,15,30,45`). Sets do
  survive: `parse(emit(parse(x)))` is field-for-field identical to
  `parse(x)`.
- **Day-of-week 0 and 7 are both Sunday**; stored sets use `0..6`, so `7`
  emits as `0` and `0,7` parses to a single value.
- **Reversed ranges are errors**, not wrap-around ranges (`5-1` is
  rejected).
- **Names are exact three-letter abbreviations**: `SEPT`, `JANUARY` and
  mixed lengths are rejected; matching is case-insensitive otherwise.
- **Macros are exact and lowercase**: `@DAILY` is `bad macro`. A macro must
  be the whole (trimmed) expression.
- **Leading zeros are accepted** (`07` = `7`), unlike semver-style strict
  parsers.
- **In-memory, single expression**: no batch API and no streaming.

See `SPEC.md` for the full specification and test matrix. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
