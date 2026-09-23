# xiom.scheduler

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** 5-field cron expression parsing, canonical re-emission, UTC
> matching and next-run computation with pure civil-date math.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.scheduler` parses the classic 5-field cron expression

```
minute hour day-of-month month weekday
```

into a `CronSchedule` (five ascending, duplicate-free `Vec[Int]` fields),
re-emits it canonically with `cron_describe`, answers "does this instant
match?" with `cron_matches`, and computes the next run with `cron_next` /
`cron_parse_next`. All arithmetic is UTC and all date math is implemented in
the module (day number -> year/month/day and weekday), with no FFI and no
stdlib time module. See `SPEC.md` for the grammar, the matching semantics
(including the standard day-of-month/day-of-week OR rule), the error catalog
and the test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `cron_parse(expr)` | `Result[CronSchedule, Str]` | Parse 5 fields; `Err("cron: ...")` on malformed lists, ranges, steps, values or field count. |
| `cron_describe(s)` | `Str` | Canonical text: `*` for unrestricted fields, else ascending comma lists. |
| `cron_matches(s, epoch_secs)` | `Bool` | True when the UTC minute containing `epoch_secs` satisfies the schedule. |
| `cron_next(s, from_secs)` | `Result[Int, Str]` | Earliest matching whole minute strictly after `from_secs`; scans up to 4 years, else `Err("cron: no match within 4 years")`. |
| `cron_parse_next(expr, from_secs)` | `Result[Int, Str]` | `cron_parse` + `cron_next` convenience. |

Field syntax: `*`, lists (`a,b`), ranges (`a-b`), steps (`*/n`, `a-b/n`) and
single values; list elements may mix those forms. Allowed values: minutes
0-59, hours 0-23, days 1-31, months 1-12, weekdays 0-6 (0 = Sunday;
no 7 synonym).

## Usage

```xi
use xiom.scheduler;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // 2026-01-01T00:00:00Z (Thursday)
  let now: Int = 1767225600;
  match cron_parse_next("30 9 * * *", now) {
    Ok(t) => { io.println(convert.int_to_string(t)); },   // 1767259800 (09:30Z)
    Err(e) => { io.println(e); },
  }
  let every15 = cron_parse("*/15 * * * *");
  match every15 {
    Ok(s) => {
      io.println(cron_describe(&s));                       // 0,15,30,45 * * * *
      match cron_next(&s, now) {
        Ok(t) => { io.println(convert.int_to_string(t)); }, // 1767226500 (00:15Z)
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.scheduler
```

Expected tail: 28 `[PASS]` lines, `xiom.scheduler: all tests passed`, then
`port: PASS (passed=28 failed=0 program_exit=0 exit=0)`.

The conformance suite pins the harness epoch anchors exactly:
`2026-01-01T00:00:00Z = 1767225600` (Thursday), `2026-02-01T00:00:00Z =
1769904000`, `0 0 * * *` matches `1767225600`, `0 0 1 * *` next from
`1767225600` is `1769904000`, `*/15 * * * *` does not match `1767225800`,
`0 0 * * 4` matches Thursday `1767225600`, and the day-OR-weekday rule.
Two derived anchors differ from the values in the original task text because
those were internally inconsistent with Unix time: `1767259200` is
`2026-01-01T09:20:00Z` (not 09:30) and `1767225900` is
`2026-01-01T00:05:00Z` (not 00:15). The suite therefore uses the correct
roots `1767259800` for 09:30Z and `1767226500` for 00:15Z; the required
negative anchor `1767225800` is kept verbatim. See `SPEC.md` section 6.

## Limitations

- **UTC only.** No timezone offsets, no DST; timestamps are Unix seconds.
- **5-field expressions only.** No seconds field, no year field, no
  `@hourly`/`@daily`-style macros, no `CRON_TZ`/`TZ` prefixes, no `?` or
  `L`/`W`/`#` extensions.
- **4-year scan bound.** `cron_next` scans at most 1461 days (four years,
  covering a leap day) and then returns
  `Err("cron: no match within 4 years")`; schedules that can never match
  (for example `0 0 30 2 *`) always take that path.
- **No `a/n` step form.** Only `*/n` and `a-b/n` define a step; a bare
  `a/n` is rejected (standard Vixie cron accepts it, this package does not).
- **No weekday 7.** Sunday is 0 only; `7` is out of range.
- **Minute granularity.** `cron_matches` ignores seconds: any instant inside
  a matching UTC minute matches. `cron_next` returns whole-minute timestamps
  strictly after `from_secs` (an already-matching instant is skipped).
- **Parse only, no persistence.** No file I/O, no scheduler loop/threads and
  no task execution; the module computes times only.
- Input size is not bounded beyond the scan window; parsing is O(len).
- Negative epoch seconds are handled by floor division down to the civil-date
  algorithm's valid range (year 0 and later).

See `SPEC.md` for the full semantics, error strings and test plan. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
