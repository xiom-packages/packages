# xiom.snapshot -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.snapshot` (`src/snapshot.xi`). Manifest: `package.xi` (name
`xiom.snapshot`, version `0.1.0`). Depends on `xiom.std` (`xiom.string`,
`xiom.string.compare`, `xiom.convert.int`).

## Scope

Snapshot comparison between two in-memory texts:

- raw line splitting with CR handling (`snapshot_lines`);
- a canonical normalized form (`snapshot_normalized`);
- equality of normalized texts (`snapshot_equal`);
- the 1-based first-difference line (`snapshot_first_diff_line`);
- a pinned first-difference summary (`snapshot_diff_summary`);
- a default-normalization clean check (`snapshot_is_clean`).

## Non-goals

- No FFI, no file-system access: texts are passed as `Str` by value.
- No snapshot store, no update/accept workflow, no environment or path
  integration (the comparison core only).
- No alignment/diff algorithm: `snapshot_first_diff_line` is positional, not
  an LCS edit script (use `xiom.diff` for that).
- No whitespace-fuzzy matching beyond the optional per-line trailing
  space/tab trim; no case folding, no Unicode normalization.
- No generics in XIOM v0.61.x: the API is `Str` / `Vec[Str]` only.
- Not thread-safe and not `async`.

## Normalization rules

`_raw_lines(text)` (public as `snapshot_lines`) splits on LF (byte 10):

1. Every LF terminates a line; the segment between two LF bytes is one line.
2. One CR immediately before a line's LF terminator is removed, and one CR at
   the very end of the text (last line, no LF) is removed. Interior CR bytes
   are kept.
3. A single trailing newline adds no line (it only terminates the last line).
   The empty text is zero lines.

| Text | Lines |
|---|---|
| `""` | `[]` |
| `"\n"` | `[""]` |
| `"a"` | `["a"]` |
| `"a\n"` | `["a"]` |
| `"a\n\n"` | `["a",""]` |
| `"a\nb"` | `["a","b"]` |
| `"a\n\nb"` | `["a","","b"]` |
| `"a\r\nb\r\n"` | `["a","b"]` |
| `"a\r"` | `["a"]` |
| `"a\rb"` | `["a\rb"]` |

`_normalized_lines(text, trim_trailing_ws)` applies the pipeline:

1. `snapshot_lines(text)` (CRLF and final lone CR become line-ending-free
   LF lines).
2. When `trim_trailing_ws` is true, remove each line's trailing run of
   spaces (32) and tabs (9).
3. Drop trailing lines that are empty (`""`) after step 2.

`snapshot_normalized` joins the resulting lines with a single LF and appends
no trailing newline.

| Input | `trim_trailing_ws` | `snapshot_normalized` |
|---|---|---|
| `""` | either | `""` |
| `"\n\n"` | either | `""` |
| `"a\r\nb\r\n"` | false | `"a\nb"` |
| `"a  \nb\t\n"` | true | `"a\nb"` |
| `"a  \nb\t\n"` | false | `"a  \nb\t"` |
| `"a\n  \nb\n \n"` | true | `"a\n\nb"` |
| `"a\n\nb\n\n"` | true | `"a\n\nb"` |

Consequences: `""`, `"\n"` and `"\n\n"` all normalize to `""`; trailing
whitespace-only lines are dropped only under `trim_trailing_ws = true`
(without the trim, `"a\n   "` keeps its final all-space line); interior blank
lines are always kept.

## Summary grammar

`snapshot_diff_summary(a, b, trim_trailing_ws)` compares the normalized line
vectors `A` and `B` positionally. Let `n = A.len()`, `m = B.len()`,
`limit = max(n, m)`. A position `i` in `[0, limit)` differs when `i >= n`,
or `i >= m`, or `str_compare(A[i], B[i]) != 0`. Let `N` be the number of
differing positions and `L` the 1-based first differing position (which
equals `snapshot_first_diff_line`).

```
summary := "equal"
         | <N> " line(s) differ; first at line " <L> "\n"
           "  expected: " <line> "\n"
           "  actual:   " <line>

<line>  := A[L-1]        when L-1 < n
         | B[L-1]        when L-1 < m
         | "<missing>"   otherwise
```

- `N >= 1` whenever the result is not the bare word `equal` (including the
  length-mismatch case, where missing positions count as differing).
- `expected` is taken from `a`, `actual` from `b`; the label padding aligns
  (`"expected: "` and `"actual:   "`).
- No trailing newline is emitted after `actual`.

Examples:

| `a` | `b` | Result |
|---|---|---|
| `"a\nb"` | `"a\nb"` | `equal` |
| `"a\r\nb\r\n"` | `"a\nb"` | `equal` |
| `"alpha\nbeta\ngamma"` | `"alpha\ndelta\ngamma"` | `1 line(s) differ; first at line 2\n  expected: beta\n  actual:   delta` |
| `"a\nb\nc"` | `"a\nx\ny"` | `2 line(s) differ; first at line 2\n  expected: b\n  actual:   x` |
| `"a\nb\nc"` | `"a"` | `2 line(s) differ; first at line 2\n  expected: b\n  actual:   <missing>` |
| `"a"` | `"a\nb\nc"` | `2 line(s) differ; first at line 2\n  expected: <missing>\n  actual:   b` |
| `""` | `"x"` | `1 line(s) differ; first at line 1\n  expected: <missing>\n  actual:   x` |

## API signatures

All functions are free functions in module `xiom.snapshot`:

```xi
pub fn snapshot_lines(text: Str) -> Vec[Str]
pub fn snapshot_normalized(text: Str, trim_trailing_ws: Bool) -> Str
pub fn snapshot_equal(a: Str, b: Str, trim_trailing_ws: Bool) -> Bool
pub fn snapshot_first_diff_line(a: Str, b: Str, trim_trailing_ws: Bool) -> Int
pub fn snapshot_diff_summary(a: Str, b: Str, trim_trailing_ws: Bool) -> Str
pub fn snapshot_is_clean(a: Str, b: Str) -> Bool
```

No function has an error path: every input is accepted and every return is
total. `snapshot_is_clean(a, b)` is exactly `snapshot_equal(a, b, true)`.

## Complexity

| Function | Time | Memory |
|---|---|---|
| `snapshot_lines` | O(n) | O(lines) |
| `snapshot_normalized` | O(n) + concat | O(lines) + result |
| `snapshot_equal` | O(n + m) | O(lines(a) + lines(b)) |
| `snapshot_first_diff_line` | O(n + m) | O(lines(a) + lines(b)) |
| `snapshot_diff_summary` | O(n + m) | O(lines(a) + lines(b)) + O(summary) |
| `snapshot_is_clean` | O(n + m) | O(lines(a) + lines(b)) |

Normalization materializes both line vectors; comparison is a single
positional pass. Result strings are built by repeated concatenation, so very
large payloads cost more than the linear scan.

## Test plan

`tests/test_conformance.xi` (`module snapshot_tests`, 20 named checks, a
`main` that prints `[PASS]`/`[FAIL]` per check, a summary line, and returns
the failure count):

1. LF text splits into one entry per line;
2. trailing newline adds no line; `""` is zero lines; `"\n"` is one empty
   line; `"a\n\n"` keeps the blank second line;
3. CRLF and a final lone CR are stripped from lines;
4. interior blank lines and interior CR bytes survive splitting;
5. normalization rewrites CRLF to LF without a trailing newline;
6. trailing space/tab trim is optional and per line;
7. trailing blank lines are dropped, interior ones are kept;
8. normalization does not alter interior blank lines;
9. equal after CRLF/newline/blank-tail normalization;
10. not equal on whitespace, content or length mismatch;
11. first difference at line 1 and after a CRLF-only first line;
12. first difference in the middle and at the last line;
13. equal texts report `-1`, including trailing-newline variants;
14. a missing line on either side counts as a difference;
15. summary is the bare word `equal` for matching texts;
16. single-line summary pins count, position and both sides;
17. summary counts every differing position and marks missing lines;
18. clean wrapper equals with default trailing-ws trim;
19. non-ASCII UTF-8 bytes pass through unchanged (including a byte-length
    check);
20. empty vs empty and empty vs non-empty in every entry point.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.snapshot
```

Last verified: compiler 0.61.3, `port: PASS (passed=20 failed=0
program_exit=0 exit=0)`.

## Known limitations

- Positional comparison only: there is no LCS alignment, so a single inserted
  line shifts every later position and inflates `N`.
- `N` counts positions, not edit operations; a replacement (`b` -> `x`)
  counts once, a pure insertion counts at every shifted position.
- A literal `<missing>` line is indistinguishable from a missing line.
- Trailing blank lines are dropped unconditionally; `""` and `"\n\n"` are
  equal under every flag combination.
- Without `trim_trailing_ws`, trailing spaces/tabs are significant, and a
  trailing whitespace-only line is a real (non-blank) line.
- Byte-wise over UTF-8: no Unicode normalization (NFC/NFD), no case folding,
  no East-Asian width handling.
- In-memory only: no file reads, snapshot store, or accept/update workflow.
- Result construction is O(payload^2) in the worst case (repeated
  concatenation); no builder is used.

## Compiler / stdlib notes for v0.61.3

- `str_compare` is imported from `xiom.string.compare`; every comparison of
  a `Str` read from a `Vec[Str]` element goes through it (BUG 17: `==` lowers
  to a pointer compare).
- Typed `Vec` element reads (`let line: Str = raw[i];`) are used wherever a
  value is bound before use, matching the xiom.diff workaround for the
  inference mis-typing of Vec element reads.
- Byte reads use `UInt8` constants (`const _SN_LF: UInt8 = 10u8;`) compared
  directly against `byte_at(...)`, so no `byte_at ... as Int` widening /
  sign-extension is involved.
- Boolean operators are assumed non-short-circuiting: guards that would form
  an out-of-range index are written as nested `if`s; `||` is used only on
  pure byte-constant comparisons.
- No `Vec[StructType]`, no `Vec[fn]` dispatch, no `self` methods, no lambdas,
  no `mut` match patterns; the module is free functions and `while` loops.
