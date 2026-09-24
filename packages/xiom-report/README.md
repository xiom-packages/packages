# xiom.report

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** plain-text report building: aligned tables, key/value blocks,
> bullet lists, greedy word wrap, and horizontal rules.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_split`,
> `xiom.string.lines`, `xiom.string.str_slice` and `xiom.string.str_repeat`).
> Tests additionally use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.report` turns containers of strings into the fixed-width plain text you
see in console reports, test summaries and CI logs. It is pure string math:
no floating point, no locale data, no FFI, and every layout rule is pinned in
`SPEC.md` so the output is stable across platforms and compiler versions.

## API

| Function | Returns | Description |
|---|---|---|
| `report_table(headers, rows, pad)` | `Str` | Fixed-width table: header line, `-` separator (only when `headers` is non-empty), then one line per row. Column width is `max(header length, longest cell) + pad` (`pad` clamped to `>= 0`); all lines share one byte length and short rows are padded with empty cells. Cells beyond `headers.len()` get data-only widths. |
| `report_kv(keys, values, separator)` | `Str` | Aligned `"key<separator>value"` lines: keys are left-justified to the longest rendered key, then the separator and value follow verbatim. Stops at the shorter of `keys`/`values`. |
| `report_bullets(items, marker)` | `Str` | `"marker item"` lines joined with LF; an embedded LF starts a continuation line indented by `marker.len()` spaces. |
| `report_wrap(text, width, indent)` | `Str` | Greedy word wrap on ASCII spaces; space runs collapse, words longer than `width` are hard-broken into exactly-`width` chunks, every line is prefixed with `indent`. `width < 1` returns `text` unchanged. |
| `report_rule(width, ch)` | `Str` | The first byte of `ch` repeated `width` times; empty `ch` means `-`; `width <= 0` yields `""`. |

All `Str` widths are **byte lengths** (see Limitations).

## Usage

```xi
use xiom.report;
use xiom.io;

fn main() -> Int {
  var headers = Vec[Str].new();
  headers.push("name");
  headers.push("age");
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new(); r1.push("Ada"); r1.push("36");
  var r2 = Vec[Str].new(); r2.push("Bob"); r2.push("7");
  rows.push(r1);
  rows.push(r2);
  io.println(report_table(&headers, &rows, 1));
  return 0;
}
```

`report_table` with `pad = 1` prints:

```
name age 
---------
Ada  36  
Bob  7   
```

Every line is exactly nine bytes long, so the trailing spaces on the header
and data lines are part of the fixed-width layout (they keep the columns
aligned with the separator).

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.report
```

Expected tail: 24 `[PASS]` lines, `xiom.report: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **ASCII widths.** Column widths, wrap widths, indent sizes and rule lengths
  are byte counts: a multi-byte UTF-8 character counts as several columns, and
  `report_wrap`/`report_rule` can split a multi-byte sequence. The module is
  intended for ASCII report text.
- **No ANSI colors or styling.** Output is plain text only; callers that want
  color must wrap the result themselves (colored bytes would also break the
  width arithmetic).
- **Left alignment only.** Tables have no right/center alignment, borders,
  row separators or truncation; cells are emitted verbatim (no trimming or
  escaping), and an embedded LF inside a table cell breaks the line/width
  invariant.
- **LF-only line structure.** `report_bullets` and `report_wrap` split on LF;
  a CR before LF is ordinary data (normalize CRLF input first).
- **Wrap normalizes spacing.** Space runs collapse to one space and leading/
  trailing spaces are dropped inside a logical line; `width < 1` returns the
  text unchanged and ignores `indent`.
- **Concatenation cost.** Every function builds its result by `Str`
  concatenation; reports are sized for terminals and CI summaries, not
  multi-megabyte documents.

See `SPEC.md` for the full layout rules and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
