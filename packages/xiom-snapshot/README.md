# xiom.snapshot

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** snapshot comparison over two in-memory texts: canonical
> normalization, line splitting, equality, first-difference position and a
> human-readable first-difference summary.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.snapshot` is the comparison core of a golden-file / snapshot test
workflow: given an expected text (the golden file) and an actual text (the
rendered output), it normalizes both to a canonical LF form, decides whether
they match, points at the first differing line, and produces a small pinned
summary for failure output. Every entry point is infallible -- functions
return `Str` / `Bool` / `Int` / `Vec[Str]`, never a `Result`, and empty input
yields empty output.

The normalization pipeline is: split on LF with each line's trailing CR
removed, optionally strip per-line trailing spaces and tabs, then drop
trailing empty lines. All comparisons of `Str` values read from `Vec`
elements go through `xiom.string.compare.str_compare` (the compiler lowers
`==` on such values to a pointer comparison, BUG 17).

## API

| Function | Returns | Description |
|---|---|---|
| `snapshot_lines(text)` | `Vec[Str]` | Split on LF; one CR immediately before the LF or at the end of the text is removed; a single trailing newline adds no line; `""` is zero lines, `"\n"` is one empty line. |
| `snapshot_normalized(text, trim_trailing_ws)` | `Str` | CRLF -> LF; optional per-line trailing space/tab trim; trailing empty lines dropped; lines rejoined with LF and no trailing newline. |
| `snapshot_equal(a, b, trim_trailing_ws)` | `Bool` | True when both texts normalize to the same line sequence. |
| `snapshot_first_diff_line(a, b, trim_trailing_ws)` | `Int` | 1-based line number of the first difference; `-1` when equal; a missing line on either side counts as a difference. |
| `snapshot_diff_summary(a, b, trim_trailing_ws)` | `Str` | `"equal"` or `"N line(s) differ; first at line L\n  expected: <line>\n  actual:   <line>"`; a side that ran out of lines is shown as `<missing>`. |
| `snapshot_is_clean(a, b)` | `Bool` | Convenience wrapper: `snapshot_equal(a, b, true)`. |

## Usage

A golden-file check treats the golden text as `a` (expected) and the rendered
text as `b` (actual):

```xi
use xiom.snapshot;
use xiom.io;

fn main() -> Int {
  let golden = "alpha\nbeta\ngamma\n";
  let rendered = "alpha\r\nbeta\ngamma  \n";
  if snapshot_is_clean(golden, rendered) {
    io.println("snapshot ok");
    return 0;
  }
  io.println(snapshot_diff_summary(golden, rendered, true));
  return 1;
}
// snapshot ok -- CRLF, a trailing newline and trailing spaces are tolerated.
```

With differing content the summary prints, for example:

```
2 line(s) differ; first at line 2
  expected: beta
  actual:   delta
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.snapshot
```

Expected: the namespaced module passes the section-4 namespace rule, 20
`[PASS]` lines, `xiom.snapshot: all tests passed`, and a final
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- Line-level only: there is no whitespace-fuzzy matching beyond the optional
  trailing space/tab trim. Interior whitespace runs, case, interior CR bytes
  and Unicode forms are all significant.
- Positional first difference, not an alignment: inserting one line makes
  every following position differ, and `N` counts those positional
  mismatches up to the longer length.
- A line that is literally `<missing>` cannot be distinguished from a missing
  line in the summary (no escaping).
- Trailing blank lines are always dropped, so `""` and `"\n\n"` compare
  equal.
- Byte-wise over UTF-8: no Unicode normalization, case folding or width
  handling.
- No file I/O, no on-disk snapshot store and no update/accept workflow in
  this version (those remain future work); texts are compared in memory.
- String building is repeated concatenation, so very large texts cost more
  than linear to normalize or summarize.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
