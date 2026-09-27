# xiom.golden -- implementation specification

This document describes exactly what `src/golden.xi` implements: the
comparison contract, the normalization pipeline, the rendering formats, the
option grammar, the error strings and what is deliberately out of scope. It
matches the shipped code; where the code and this document disagree, the
code is the bug.

## 1. Scope

In scope:

- exact byte comparison of two in-memory buffers, with the offset of the
  first difference and a four-way difference kind;
- text comparison with line-ending normalization and two tolerance flags;
- a bounded, escape-rendered line-diff summary with a count of all
  differing lines;
- hex and escape rendering that is safe for arbitrary bytes, including
  `0x00`;
- parsing of update-mode and tolerance flags into a `GoldenOptions` value;
- path naming conventions for golden files and their `.actual`/`.new`
  siblings.

Out of scope: filesystem access, test discovery/run orchestration, binary
patch generation, insert/delete alignment (no Myers/LCS diff), Unicode
normalization, blank-line or case tolerance.

## 2. Data model

### 2.1 GoldenResult

| Field | Type | Meaning |
|---|---|---|
| `equal` | Int | 1 when no difference, else 0 |
| `kind` | Int | 0 equal, 1 content differs, 2 actual is a proper prefix of expected (actual shorter), 3 expected is a proper prefix of actual (actual longer) |
| `first_diff` | Int | Byte offset of the first differing byte in the compared buffers; when one buffer is a prefix of the other it is the length of the shorter buffer; -1 when equal |
| `diff_line` | Int | 1-based line holding `first_diff` for text compares; -1 for byte compares and when equal |
| `expected_len` | Int | Compared (normalized) length of expected |
| `actual_len` | Int | Compared (normalized) length of actual |
| `expected_lines` | Int | Line count of the normalized expected buffer for text compares; -1 for byte compares |
| `actual_lines` | Int | Line count of the normalized actual buffer for text compares; -1 for byte compares |

### 2.2 GoldenOptions

| Field | Type | Default | Meaning |
|---|---|---|---|
| `update` | Int | 0 | 1 when `-u`/`--update` was seen |
| `text` | Int | 1 | 1 for text comparison, 0 after `-b`/`--bytes` |
| `flags` | Int | 0 | Tolerance bits (bit 0 trailing space, bit 1 trailing newline) |
| `max_lines` | Int | 8 | Summary render bound |
| `quiet` | Int | 0 | 1 when `-q`/`--quiet` was seen |

## 3. Byte comparison

`golden_compare_bytes(expected, actual)`:

1. `n = min(expected.len(), actual.len())`.
2. Scan `i` in `0..n`; the first index where
   `(expected[i] as Int) != (actual[i] as Int)` is the first difference.
3. Classify:
   - difference found -> `kind = 1`, `first_diff = i`;
   - no difference and lengths equal -> `kind = 0`, `equal = 1`,
     `first_diff = -1`;
   - no difference, `actual.len() < expected.len()` -> `kind = 2`,
     `first_diff = n`;
   - otherwise -> `kind = 3`, `first_diff = n`.

Byte comparisons always set `diff_line`, `expected_lines`, `actual_lines`
to -1.

## 4. Text normalization

`golden_normalize_text(buf, flags)` applies, in order:

1. **Line endings (always):** every CR (0x0D) becomes LF (0x0A). For CRLF
   the LF is consumed, so CRLF becomes a single LF; a lone CR also becomes
   an LF. All other bytes are copied unchanged.
2. **Trailing spaces (flag bit 0):** maximal runs of spaces (0x20) and tabs
   (0x09) that are immediately followed by an LF, or that end the buffer,
   are removed. Runs followed by any other byte are copied byte for byte,
   so interior whitespace is preserved exactly.
3. **Trailing newlines (flag bit 1):** all LF bytes at the end of the
   buffer are removed; bytes before the first non-LF from the end are kept.

Flags are read with integer division: bit 0 is `(flags / 1) % 2`, bit 1 is
`(flags / 2) % 2`; flags are expected to be non-negative. The two public
bit values are 1 and 2 (`golden_flag_ignore_trailing_space()` /
`golden_flag_ignore_trailing_newline()`).

`golden_compare_text(expected, actual, flags)` normalizes both sides,
runs the byte comparison, and fills in `diff_line` (via
`_line_of_offset` on the normalized expected buffer) and the line counts.

### 4.1 Line semantics

- A line is a maximal byte segment ending at an LF, plus a final segment
  when the buffer does not end with LF.
- `golden_count_lines`: empty buffer -> 0; `"a\n"` -> 1; `"a\nb"` -> 2;
  `"a\n\n"` -> 2.
- Line numbers are 1-based.
- `_line_of_offset` clamps the offset to the buffer length and counts LFs
  before it plus one, so an offset equal to the buffer length reports the
  line that would continue there.

## 5. Line-diff summary

`golden_diff_summary(expected, actual, flags, max_entries)` normalizes both
buffers and walks them line by line:

- Each side yields a line when it still has bytes or when a line is
  pending: side cursor `< len` means the side has a line, whose content is
  `[cursor, next LF or end)` and whose `terminated` flag is true when the
  line ends at an LF before the buffer end.
- Two lines are **same** when both sides have a line, the content ranges
  are byte-identical and the `terminated` flags match. A line present on
  one side only is a difference. A missing final newline is therefore
  reported on the line that lacks it.
- Every differing line increments `differing`. The first `max_entries`
  (negative clamped to 0) are rendered; all are counted.

Output, exactly:

- no differing line: `golden: equal\n`;
- otherwise a header `golden: <n> line(s) differ\n`, then per rendered
  line `  line <L>: expected=<render> actual=<render>\n` (LF-terminated),
  then, when `differing > max_entries`,
  `  ... (<k> more differing line(s))\n` where `k = differing -
  max_entries`.

`<render>` is either `<none>` or a double-quoted escape rendering of the
line content followed by the two characters `\` `n` when the line was
terminated. Because a literal backslash is escaped to `\\`, the trailing
marker is unambiguous.

## 6. Hex and escape rendering

`golden_hex(buf)`: two lowercase hex digits per byte, in order; empty
buffer -> `""`. `golden_hex_bounded(buf, max)` renders at most `max` bytes
(negative = all) and appends `...(<k> more bytes)` where `k` is the number
of omitted bytes.

`golden_escape_range(buf, start, end, max)` clamps `start`/`end` to the
buffer (`start < 0` -> 0, `end < start` -> `start`, `end > len` -> `len`),
then renders at most `max` input bytes (negative = all), appending
`...(<k> more bytes)` when truncated. Byte mapping:

| Byte | Rendered as |
|---|---|
| `\` (0x5C) | `\\` |
| `"` (0x22) | `\"` |
| LF (0x0A) | `\n` |
| CR (0x0D) | `\r` |
| TAB (0x09) | `\t` |
| 0x20..0x7E (others) | the byte itself |
| everything else, including 0x00 | `\x` + two lowercase hex digits |

Every mapping is built by pushing bytes and hex text, never by copying raw
input bytes into a `Str`, so a NUL byte renders as the four characters
`\x00` and cannot truncate the result (the v0.61.3 compiler aborts
`sb_to_str` on an embedded NUL). `golden_escape(buf)` is
`golden_escape_range(buf, 0, len, -1)`; `golden_escape_bounded(buf, max)`
is the same with a bound.

## 7. Option parsing

`golden_parse_options(args)` starts from the defaults (section 2.2) and
processes tokens in order:

| Token(s) | Effect |
|---|---|
| `-u`, `--update` | `update = 1` |
| `-t`, `--text` | `text = 1` |
| `-b`, `--bytes` | `text = 0` |
| `--ignore-trailing-space` | `flags += 1` |
| `--ignore-trailing-newline` | `flags += 2` |
| `-q`, `--quiet` | `quiet = 1` |
| `--max-lines=N` | `max_lines = N`, requires digits only and `1 <= N <= 1000000` |
| anything else | `Err("golden: unknown flag: " + token)` |

Repeated tokens are idempotent except `--max-lines`, where the last value
wins. The token list may be empty (defaults). `--max-lines=` prefix is 12
bytes, so only the exact spelling with `=` is recognized.

### 7.1 Error catalog

| Message | Condition |
|---|---|
| `golden: unknown flag: <token>` | token matched no known flag |
| `golden: max-lines needs a number` | `--max-lines=` with nothing after `=` |
| `golden: max-lines must be a number` | value contains a non-digit |
| `golden: max-lines out of range` | value is 0 or exceeds 1000000 |

`golden_parse_options` returns `Result[GoldenOptions, Str]`; `Ok` carries
the options value.

## 8. Path conventions

- `golden_join(dir, name)`: empty `dir` -> `name`; empty `name` -> `dir`;
  when `dir` ends with `/` (0x2F) or `\` (0x5C) the parts are concatenated
  directly; otherwise a single `/` is inserted.
- `golden_slug(name)`: keeps bytes in `[A-Za-z0-9._-]`; every other byte
  becomes a separator, separator runs collapse to one `_`, and
  leading/trailing separators are dropped. An empty result becomes
  `"golden"`.
- `golden_default_path(name)` = `golden_join("tests/golden",
  golden_slug(name) + ".golden")`.
- `golden_actual_path(path)` = `path + ".actual"`.
- `golden_new_path(path)` = `path + ".new"`.
- `golden_is_golden_path(path)`: true when `path` ends with `.golden`.

The module itself never creates, reads or writes any file; these helpers
only compute names for the caller.

## 9. Determinism and purity

All functions are pure: same inputs produce the same outputs, no global
state, no I/O, no allocation outside the returned values. Results do not
depend on locale, time or platform. Rendering functions bound their output
to the requested limits; the summary scan is linear in the input size.

## 10. Test plan

`tests/test_conformance.xi` runs 35 checks on synthetic buffers built in
the test file:

| # | Check |
|---|---|
| 1 | byte equal: `equal`, kind 0, first_diff -1 |
| 2 | byte content difference: kind 1, first_diff 3 |
| 3 | actual shorter: kind 2, first_diff 3, lengths 6/3 |
| 4 | actual longer: kind 3, first_diff 3 |
| 5 | empty equals empty; empty vs `x`: kind 3, first_diff 0 |
| 6 | CRLF equals LF after normalization (raw bytes differ) |
| 7 | lone CR equals LF |
| 8 | trailing spaces: differ by default, equal with flag bit 0 |
| 9 | missing final newline: kind 3, first_diff 1; equal with flag bit 1 |
| 10 | repeated trailing newlines ignored with flag bit 1 |
| 11 | first difference byte 4 -> line 3 |
| 12 | line counts: 0 / 1 / 2 / 2 for `""`, `"a\n"`, `"a\nb"`, `"a\n\n"` |
| 13 | hex `00 41 FF` -> `0041ff` |
| 14 | bounded hex -> `4142...(3 more bytes)` |
| 15 | escape of NUL/LF/TAB/backslash/quote: length 13, `\x00` present, no raw LF |
| 16 | bounded escape -> `AB...(2 more bytes)` |
| 17 | range escape 1..4 of `ABCDEF` -> `BCD` |
| 18 | equal summary -> `golden: equal\n` |
| 19 | summary counts 4, renders 2, omits line 3, truncation marker |
| 20 | missing line renders `expected=<none>` |
| 21 | missing final newline renders the `\n` marker on line 1 |
| 22 | option defaults: update off, text on, flags 0, max 8, quiet off |
| 23 | `-u` + both tolerance flags + `-q` + `--text` |
| 24 | `--bytes` disables text; `--max-lines=3` sets the bound |
| 25 | unknown flag error |
| 26 | non-numeric max-lines error |
| 27 | empty and zero max-lines errors |
| 28 | default path for `case 1`; empty slug fallback |
| 29 | join rules incl. trailing `/` and `\` |
| 30 | `.actual` / `.new` siblings; `.golden` predicate |
| 31 | slug collapse, edge trimming, fallback |
| 32 | normalization keeps interior whitespace, strips trailing runs |
| 33 | CRLF + newline flag normalizes to the bare line |
| 34 | kind names and flag bit values |
| 35 | combined space+newline tolerance in one text compare |

## 11. Known limitations

- The summary is positional: an inserted line shifts all later line
  comparisons; no alignment is attempted.
- Byte offsets in text mode refer to normalized buffers, not the caller's
  original bytes.
- Long line contents are rendered up to 120 bytes with a truncation marker;
  the marker is part of the rendering, not the comparison.
- CR-only files are accepted as text (lone CR is a line break); callers
  needing strict byte semantics should use the byte comparison with flag 0
  (no normalization).
- `--max-lines` is capped at 1000000 and rejects 0; use `0` render bound
  through the direct API (`golden_diff_summary(..., 0)`) if only the count
  is wanted.
