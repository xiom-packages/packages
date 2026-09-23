# xiom.scheduler -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.scheduler` (`src/scheduler.xi`). Pure XIOM, no FFI.

## 1. Scope

Parse the classic 5-field cron expression, re-emit it canonically, and answer
UTC match / next-run questions with pure in-module civil-date math:

- `cron_parse` -- expression -> `Result[CronSchedule, Str]`,
- `cron_describe` -- schedule -> canonical expression text,
- `cron_matches` -- schedule + Unix seconds -> `Bool`,
- `cron_next` -- schedule + Unix seconds -> next matching minute,
- `cron_parse_next` -- the two composed.

No FFI, no stdlib time module, no file I/O. All timestamps are Unix seconds
interpreted as UTC.

## 2. Non-goals

- Seconds field, year field, `@hourly`/`@daily`-style macros, `CRON_TZ`/`TZ`
  prefixes, `?`, `L`, `W`, `#` extensions.
- Timezone conversion or DST handling of any kind.
- Vixie `a/n` ("from a, step n") syntax.
- Scheduling, timers, task execution, persistence.
- Rich error positions; errors carry a message only.
- Any FFI.

## 3. Grammar

Fields are separated by runs of ASCII space or tab. Exactly five fields are
required, in this order:

```
expression = ws* field ws+ field ws+ field ws+ field ws+ field ws*
field      = element *( "," element )
element    = "*" | "*/" uint | uint | uint "-" uint | uint "-" uint "/" uint
uint       = 1*DIGIT
ws         = SP | TAB
```

Allowed ranges and the semantics of each element:

| Field | Range | `*` | `a` | `a-b` | `*/n` | `a-b/n` |
|---|---|---|---|---|---|---|
| minute | 0-59 | all | {a} | a..b inclusive | a..hi step n | a..b step n |
| hour | 0-23 | all | {a} | a..b inclusive | lo..hi step n | a..b step n |
| day-of-month | 1-31 | all | {a} | a..b inclusive | lo..hi step n | a..b step n |
| month | 1-12 | all | {a} | a..b inclusive | lo..hi step n | a..b step n |
| weekday | 0-6 | all | {a} | a..b inclusive | lo..hi step n | a..b step n |

Decisions (each covered by the conformance suite):

1. **Canonical form.** Every field is stored as an ascending, duplicate-free
   `Vec[Int]` of allowed values regardless of how it was written
   (`30,5,15,5` -> `[5,15,30]`).
2. **Ranges and steps.** `a-b` requires `a <= b`; `a-b/n` emits
   `a, a+n, ... <= b`; `*/n` emits `lo, lo+n, ... <= hi`. `n >= 1`.
   Values outside the field's range are errors, including both range
   endpoints.
3. **Lists.** Elements are comma-separated and may mix forms
   (`5,10-12,*/20`). An empty element (leading, trailing or doubled comma)
   is an error. Duplicates merge silently.
4. **Unrestricted fields.** After canonicalization, a field is
   "unrestricted" iff it contains every allowed value (so `*/1` is
   unrestricted). This is what the day-of-month/day-of-week rule keys on.
5. **Whitespace.** SP and TAB separate fields; any surrounding whitespace is
   ignored. No other whitespace is produced or accepted inside a field.
6. **Weekday numbering.** 0 = Sunday ... 6 = Saturday; 1970-01-01 was a
   Thursday (4). The value `7` is rejected.

## 4. Data model

```xi
pub type CronSchedule = {
  minutes: Vec[Int];    // 0-59, ascending, duplicate-free
  hours: Vec[Int];      // 0-23
  days: Vec[Int];       // 1-31
  months: Vec[Int];     // 1-12
  weekdays: Vec[Int];   // 0-6 (0 = Sunday)
}
```

Invariants produced by `cron_parse`: every vector is non-empty, strictly
ascending, within its range, and equal to the full allowed range iff the
original field was unrestricted. `cron_matches`, `cron_next` and
`cron_describe` rely on the sorted invariant for efficiency (ascending
hours/minutes admit first-hit scanning).

## 5. Matching semantics

### 5.1 Minute and hour

`cron_matches(s, t)` floors `t` to a whole minute: `mi = floor(t / 60)`,
`days = floor(mi / 1440)`, `hour = (mi mod 1440) / 60`, `minute = mi mod 60`
(all divisions are floor divisions, so negative `t` works). Seconds inside
the minute are ignored. The minute must be in `s.minutes` and the hour in
`s.hours`, otherwise the instant does not match.

### 5.2 Month and civil date

Month and day-of-month are computed from the day number `days` (days since
1970-01-01) with Howard Hinnant's `civil_from_days` algorithm, adapted to
floor division:

```
z    = days + 719468
era  = floor(z / 146097)
doe  = z - era * 146097                      // [0, 146096]
yoe  = (doe - doe/1460 + doe/36524 - doe/146096) / 365
y    = yoe + era * 400
doy  = doe - (365*yoe + yoe/4 - yoe/100)     // [0, 365]
mp   = (5*doy + 2) / 153                     // [0, 11]
d    = doy - (153*mp + 2)/5 + 1              // [1, 31]
m    = mp + 3, or mp - 9 when mp >= 10       // [1, 12]
y    = y + 1 when m <= 2
```

The weekday is `(days + 4) mod 7` with 0 = Sunday (1970-01-01 = day 0 was a
Thursday, so `(0 + 4) mod 7 = 4`). The month must be in `s.months`; if not,
the day rule is never reached.

### 5.3 Day-of-month / day-of-week OR rule

Let `dom_restricted` mean `s.days` does not contain all of 1-31, and
`wd_restricted` mean `s.weekdays` does not contain all of 0-6. Then:

| dom_restricted | wd_restricted | Day matches when |
|---|---|---|
| false | false | always |
| true | false | day-of-month is in `s.days` |
| false | true | weekday is in `s.weekdays` |
| true | true | day-of-month is in `s.days` **or** weekday is in `s.weekdays` |

This is the standard cron rule: with both restricted, a day matches if
either field is satisfied (so `0 0 1 * 4` fires on every 1st and every
Thursday). The `* * * * *` case never consults the rule (no restrictions).

### 5.4 Next run

`cron_next(s, from_secs)` returns the earliest whole-minute timestamp `t`
with `t > from_secs` and `cron_matches(s, t)` true -- strictly greater, so
an already-matching instant is skipped and the following occurrence is
returned. Implementation: start at day `floor(floor(from_secs/60)/1440)` and
scan whole days up to `start_day + 1461` (four years including a leap day);
inside each day whose month and day rule match, try `s.hours` and
`s.minutes` in ascending order and return the first `t > from_secs`. If no
day matches within the window, the result is
`Err("cron: no match within 4 years")`. The 1461-day window guarantees one
leap day (`0 0 29 2 *` from just after 2028-02-29 finds 2032-02-29 exactly
on the last scanned day).

## 6. Epoch anchors and a correction to the task text

The suite pins these UTC anchors (verified against Unix time):

| Wall clock (UTC) | Unix seconds | Weekday |
|---|---|---|
| 2026-01-01T00:00:00Z | 1767225600 | Thursday |
| 2026-01-01T00:15:00Z | 1767226500 | Thursday |
| 2026-01-01T09:30:00Z | 1767259800 | Thursday |
| 2026-01-02T00:00:00Z | 1767312000 | Friday |
| 2026-01-08T00:00:00Z | 1767830400 | Thursday |
| 2026-01-15T00:00:00Z | 1768435200 | Thursday |
| 2026-02-01T00:00:00Z | 1769904000 | Sunday |
| 2028-02-29T00:00:00Z | 1835395200 | Tuesday |
| 2032-02-29T00:00:00Z | 1961625600 | Sunday |

The original port task stated `2026-01-01T09:30:00Z = 1767259200` and
`... 00:15 = 1767225900`. Both are 600 seconds small for the wall-clock time
named: `1767259200` is `2026-01-01T09:20:00Z` and `1767225900` is
`2026-01-01T00:05:00Z`. The suite keeps every self-consistent anchor
(`1767225600`, `1769904000`, `1767225800`, `0 0 * * *` matching
`1767225600`, `0 0 1 * *` next = `1769904000`) and uses the corrected
timestamps for the two inconsistent ones, asserting the wall-clock semantics
(e.g. `30 9 * * *` next from `1767225600` is `1767259800` = 09:30Z, and
`*/15 * * * *` matches `1767226500` = 00:15Z).

## 7. API signatures

```xi
pub fn cron_parse(expr: Str) -> Result[CronSchedule, Str]
pub fn cron_describe(s: &CronSchedule) -> Str
pub fn cron_matches(s: &CronSchedule, epoch_secs: Int) -> Bool
pub fn cron_next(s: &CronSchedule, from_secs: Int) -> Result[Int, Str]
pub fn cron_parse_next(expr: Str, from_secs: Int) -> Result[Int, Str]
```

Complexity: parse O(len(expr) + 207) (canonicalization scans each field's
range); describe O(64); matches O(31 + field sizes); next
O(1461 * |hours| * |minutes|) worst case.

## 8. Error catalog

Every parse failure is `Err(msg)` with `msg` starting with `"cron: "`:

| Message | Trigger |
|---|---|
| `cron: expected 5 fields, got <n>` | wrong field count (including empty input) |
| `cron: empty <name> field` | empty list element: leading/trailing/doubled comma |
| `cron: invalid value in <name> field: <seg>` | non-digit, empty number, `1..2`, `*5`, `*-` |
| `cron: invalid range in <name> field: <seg>` | `5-1` (reversed), `5-`, `-5` |
| `cron: invalid step in <name> field: <seg>` | `*/0`, `*/x`, `1-10/`, `1/2` (`a/n` unsupported) |
| `cron: out-of-range value in <name> field: <seg>` | value or range endpoint outside the allowed range |
| `cron: no match within 4 years` | `cron_next` scan exhausted (e.g. `0 0 30 2 *`) |

`<name>` is one of `minute`, `hour`, `day-of-month`, `month`, `weekday`;
`<seg>` is the offending comma element (or the whole field for list-level
errors). `cron_parse_next` returns parse errors unchanged and otherwise the
`cron_next` result.

## 9. Test plan

`tests/test_conformance.xi` (module `scheduler_tests`) runs 28 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | `* * * * *` | full ranges 60/24/31/12/7, bounds |
| t2 | `30 9 1 6 4` | single values, struct field access |
| t3 | `5,10,12,30` | list parsing |
| t4 | `10-15` | inclusive range |
| t5 | `*/15` | star step |
| t6 | `1-10/3` | range step (`1,4,7,10`) |
| t7 | `30,5,15,5` | ascending, deduplicated canonical form |
| t8 | `""`, `* * * *`, `* * * * * *` | field-count errors, exact message |
| t9 | `60`, `24`, `0`, `32`, `13`, `7`, `8` | out-of-range rejection, boundary `59 23 31 12 6` accepted |
| t10 | `abc`, `1a`, `-5`, `5-`, `1..2`, `1/2` | malformed numbers and unsupported `a/n` |
| t11 | `5-1`, `1-70`, `*/0`, `*/`, `1-10/0`, `*/x`, `1-10/`, `10-5/2` | bad ranges/steps |
| t12 | `1,`, `,1`, `1,,2`, `'* * * * *` | bad lists |
| t13 | four invalid inputs | every error starts with `cron: ` |
| t14 | describe `0 0 * * *` etc. | `*` re-emission for unrestricted fields |
| t15 | describe steps/lists/ranges | canonical comma lists |
| t16 | describe -> parse -> describe | round-trip stability |
| t17 | `0 0 * * *` at `1767225600` | known anchor, negatives |
| t18 | sub-minute seconds | minute granularity documented in 5.1 |
| t19 | `*/15`, `30 9`, lists, ranges | match positives/negatives incl. `1767225800` |
| t20 | `0 0 * * 4/5/0` | weekday mapping (Thursday/Sunday) |
| t21 | month and day-of-month restrictions | month gate + dom |
| t22 | `0 0 1 * 4`, `0 0 15 * 4`, `0 0 2 * 4` | the OR rule on/off (section 5.3) |
| t23 | next with the OR rule | day branch beats weekday branch when earlier |
| t24 | `30 9`, `*`, `0 0 * * *` | strict next, skip already-matching minute |
| t25 | day 1 / day 15 / February / March 1 / Thursday | next across boundaries |
| t26 | `0 0 29 2 *` | leap-day scan (2028 and 2032) |
| t27 | `0 0 30 2 *`, `0 0 31 4 *` | `cron: no match within 4 years` exact |
| t28 | `cron_parse_next` | compose, parse-error passthrough |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison). Tests dispatch directly (`t1()` ... `t28()`); `Vec[fn]`
indexed calls are not used.

## 10. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the `xiom.csv` /
`xiom.toml` pure-parser idioms and documents these compiler-driven choices
(XIOM v0.61.3):

- `Vec[StructType]` is unsupported, so a schedule is five homogeneous
  `Vec[Int]` fields and no `Vec[CronSchedule]` is used.
- `Ok`/`Err` are constructed only inside the `_ok_*`/`_err_*` helper
  functions, never directly in a public body (the `xiom.patch` workaround for
  Result construction in struct-returning functions).
- `cron_parse` builds the struct through `_make_schedule`, which contains no
  `Ok`/`Err`.
- `_civil_ymd` returns `Option[(Int, Int, Int)]` (always `Some`) rather than a
  small struct, avoiding struct-in-Option lowering; the call sites destructure
  with `match` and a `None` arm (non-exhaustive match is a hard error).
- `Vec[Int]` element reads are bound with a typed `let` before use.
- Str equality between `Vec[Str]` elements goes through `str_compare`
  (BUG 17).

## 11. Known limitations

- UTC only; no zones, no DST.
- 5 fields only; no seconds/year, no macros, no `TZ=`, no `?`/`L`/`W`/`#`.
- No `a/n` step form (only `*/n` and `a-b/n`).
- No weekday `7` synonym for Sunday.
- Month lengths are not validated against day-of-month at parse time; e.g.
  `0 0 31 4 *` parses and then reports `cron: no match within 4 years` from
  `cron_next`.
- `cron_next` searches a fixed 1461-day window; schedules whose next match is
  further out are reported as no-match.
- Minute-granularity matching; `cron_matches` ignores the seconds component.
- `cron_describe` emits `*` based on the canonical vector length, so a
  hand-built `CronSchedule` that violates the sorted/full-range invariant is
  outside the contract.
- Errors carry no position information.
