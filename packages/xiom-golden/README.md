# xiom.golden

> **Status:** `incubating` -- implemented and green on the local harness
> (35 conformance checks), NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no filesystem I/O) golden-file comparison
> helpers: exact byte diff, text diff with CRLF/LF normalization and
> trailing-space/newline tolerance, bounded line-diff summaries, NUL-safe
> hex/escape rendering, update-flag parsing and path conventions. Every
> function works on in-memory byte buffers.
> **Deps:** `xiom.std` only (the library imports `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare`; the tests add `xiom.test`
> and `xiom.io`).

## What it is

`xiom.golden` is the comparison half of golden-file testing: a test
produces bytes, the harness compares them against a checked-in expected
buffer and, when they differ, renders a bounded, readable summary. It is
deliberately not a test framework and it never touches the filesystem: the
caller reads and writes files and decides what to do with the result.

Three layers:

1. **Byte compare** (`golden_compare_bytes`) -- exact equality plus a
   `GoldenResult` carrying the first-difference offset and a kind:
   `content` (bytes differ), `actual-shorter` or `actual-longer` when one
   buffer is a proper prefix of the other.
2. **Text compare** (`golden_compare_text`) -- normalizes both buffers
   (CRLF and lone CR become LF), then applies tolerance flags, then runs
   the byte compare. Results also report the first differing line and the
   line counts.
3. **Reporting** (`golden_diff_summary`) -- a bounded, escape-rendered
   line diff. It counts every differing line, renders at most `max_lines`
   of them with `expected=`/`actual=` sides (`<none>` for a missing line,
   a `\n` marker when a line lacks its terminator), and appends a
   truncation marker.

Rendering never builds a `Str` from raw input bytes: `golden_hex` emits
lowercase hex and `golden_escape` maps control bytes to `\n`/`\r`/`\t` and
everything else -- including `0x00` -- to `\xNN`. A NUL in the input
therefore renders as the four characters `\x00` instead of truncating the
output (the pinned compiler aborts `sb_to_str` on an embedded NUL).

## Tolerances and flags

Text comparison always treats CRLF, lone CR and LF as the same line break.
Two optional tolerance bits are added to the comparison:

| Bit | Function | Effect |
|---|---|---|
| 0 | `golden_flag_ignore_trailing_space()` | strips spaces/tabs before every LF and at EOF |
| 1 | `golden_flag_ignore_trailing_newline()` | removes all trailing LF bytes at EOF |

Bits combine with `+`, e.g. `golden_flag_ignore_trailing_space() +
golden_flag_ignore_trailing_newline()`.

## API

| Function | Returns | Description |
|---|---|---|
| `golden_compare_bytes(expected, actual)` | `GoldenResult` | Exact byte diff. |
| `golden_compare_text(expected, actual, flags)` | `GoldenResult` | Normalized text diff. |
| `golden_normalize_text(buf, flags)` | `Vec[UInt8]` | The normalized form used by text compares. |
| `golden_count_lines(buf)` | `Int` | Line count of a text buffer. |
| `golden_equal/kind/first_diff/diff_line/expected_len/actual_len/expected_lines/actual_lines(r)` | mixed | `GoldenResult` accessors. |
| `golden_kind_name(kind)` | `Str` | `equal` / `content` / `actual-shorter` / `actual-longer` / `unknown`. |
| `golden_hex(buf)` / `golden_hex_bounded(buf, max)` | `Str` | Lowercase hex rendering. |
| `golden_escape(buf)` / `golden_escape_bounded(buf, max)` / `golden_escape_range(buf, start, end, max)` | `Str` | NUL-safe escape rendering. |
| `golden_diff_summary(expected, actual, flags, max_lines)` | `Str` | Bounded line-diff summary. |
| `golden_flag_ignore_trailing_space/newline()` | `Int` | Tolerance bit values (1, 2). |
| `golden_options_default()` | `GoldenOptions` | update 0, text 1, flags 0, max-lines 8, quiet 0. |
| `golden_parse_options(args)` | `Result[GoldenOptions, Str]` | Update-mode and tolerance flag parsing. |
| `golden_option_update/text/flags/max_lines/quiet(o)` | mixed | `GoldenOptions` accessors. |
| `golden_join(dir, name)` | `Str` | `/` join tolerant of empty parts and trailing separators. |
| `golden_slug(name)` | `Str` | Filesystem-safe test name (`[A-Za-z0-9._-]`). |
| `golden_default_path(name)` | `Str` | `tests/golden/<slug>.golden`. |
| `golden_actual_path/new_path(path)` | `Str` | `<path>.actual` / `<path>.new`. |
| `golden_is_golden_path(path)` | `Bool` | Ends with `.golden`. |

## Usage

```xi
use xiom.io;
use xiom.golden;

fn main() -> Int {
  let expected = /* bytes read from tests/golden/case1.golden */ Vec[UInt8].new();
  let actual = /* bytes produced by the test under check */ Vec[UInt8].new();

  let args = /* argv tokens, e.g. from xiom.os.args */ Vec[Str].new();
  let opts_r = golden_parse_options(&args);
  if !opts_r.is_ok {
    io.println(opts_r.error);
    return 2;
  }
  let opts = opts_r.value;

  let flags = golden_option_flags(&opts);
  let r = golden_compare_text(&expected, &actual, flags);
  if golden_equal(&r) {
    io.println("golden: match");
    return 0;
  }

  io.println(golden_diff_summary(&expected, &actual, flags, golden_option_max_lines(&opts)));
  if golden_option_update(&opts) {
    io.println("golden: update mode -- write " + golden_actual_path("tests/golden/case1.golden"));
  }
  return 1;
}
```

Example summary for two 4-line buffers with `max_lines = 2`:

```
golden: 4 line(s) differ
  line 1: expected="l1" actual="x1"
  line 2: expected="l2" actual="x2"
  ... (2 more differing line(s))
```

## Tests

```
xiom --run tests/test_conformance.xi      # or: .\scripts\port.ps1 -Package xiom.golden
```

Expected: 35 `[PASS]` lines, then `xiom.golden: all tests passed`, exit 0.
All fixtures are synthetic byte buffers built in the test file.

## Limits (honest scope)

- No filesystem I/O, no test discovery, no runner: the caller supplies
  buffers and acts on the result.
- The diff is line-based and positional; it does not compute insert/delete
  alignment (no Myers diff, no LCS).
- `max_lines` bounds rendering, but the summary still scans both buffers
  once to count all differing lines.
- Tolerance flags are intentionally limited to trailing spaces and trailing
  newlines; blank-line and case-insensitive modes are not provided.
- Lone CR is normalized to LF (documented behavior, not inferred).
- Line content is compared as bytes; no Unicode normalization is
  performed.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
