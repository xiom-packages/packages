# xiom.tap

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a TAP (Test Anything Protocol) parser and canonical emitter for
> the documented flat subset: version line, plan, `ok` / `not ok` results,
> `SKIP` / `TODO` directives, raw `#` diagnostics, `Bail out!`.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_lower`, `xiom.string.str_upper`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.tap` reads one in-memory `Str` stream into a flat `TapDoc` and writes it
back in a canonical form. It is a codec, not a test runner: it parses and
formats test output, it never executes a test. The accepted input is the TAP
subset specified in `SPEC.md`: the `TAP version <N>` line, the plan `1..<N>`,
flat results `ok <n> [description]` / `not ok <n> [description]` with
sequential numbers, the `# SKIP <reason>` and `# TODO <reason>` directives
(case-insensitive), full-line `# ...` diagnostics, blank lines, and
`Bail out! <reason>` (which stops the parse). YAML diagnostic blocks are
rejected, not parsed. Anything outside the subset is a deterministic
`Err("tap: ...")` carrying a 1-based line number. `SPEC.md` pins the grammar,
the policies and the full error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `tap_parse(text)` | `Result[TapDoc, Str]` | Parse a whole stream; `Err` carries a `tap: ...` message with the line number. |
| `tap_doc_new()` | `TapDoc` | An empty document (no version, plan `-1`, no results). |
| `tap_add_test(d, ok, description, directive, reason)` | nothing | Append a result; the number is the next free one. |
| `tap_set_version(d, n)` | nothing | Set the version (non-positive = no version line). |
| `tap_set_plan(d, n)` | nothing | Set the plan count (negative = no plan line). |
| `tap_set_bail(d, reason)` | nothing | Mark the document bailed out with a reason. |
| `tap_add_diagnostic(d, text)` | nothing | Append a diagnostic line (without the leading `#`). |
| `tap_version(d)` | `Int` | Recorded version; `0` when absent. |
| `tap_planned(d)` | `Int` | Plan count (`0` for `1..0`); `-1` when absent. |
| `tap_test_count(d)` | `Int` | Number of stored results. |
| `tap_number(d, i)` | `Int` | Declared number of result `i`; `-1` out of range. |
| `tap_is_ok(d, i)` | `Bool` | `true` for an `ok` result; `false` for `not ok` or out of range. |
| `tap_description(d, i)` | `Str` | Description of result `i`; `""` out of range. |
| `tap_directive(d, i)` | `Str` | `"skip"`, `"todo"` or `""`; `""` out of range. |
| `tap_reason(d, i)` | `Str` | Directive reason; `""` when absent. |
| `tap_passed(d)` | `Int` | Results that are `ok` with no directive. |
| `tap_failed(d)` | `Int` | Results that are `not ok` with no directive. |
| `tap_skipped(d)` | `Int` | Results carrying a `SKIP` directive. |
| `tap_todo(d)` | `Int` | Results carrying a `TODO` directive. |
| `tap_bailed(d)` | `Bool` | `true` when a `Bail out!` line was seen. |
| `tap_bail_reason(d)` | `Str` | Bail out reason; `""` when absent. |
| `tap_diagnostic_count(d)` | `Int` | Number of stored `#` diagnostics. |
| `tap_diagnostic(d, i)` | `Str` | Diagnostic text without the leading `#`; `""` out of range. |
| `tap_write_version(n)` | `Str` | `"TAP version <n>"`; `""` when `n <= 0`. |
| `tap_write_plan(n)` | `Str` | `"1..<n>"`; `""` when `n < 0`. |
| `tap_write_test(number, ok, description, directive, reason)` | `Str` | One canonical result line. |
| `tap_write_comment(text)` | `Str` | `"#"` or `"# <text>"`. |
| `tap_write_bail(reason)` | `Str` | `"Bail out!"` or `"Bail out! <reason>"`. |
| `tap_emit(d)` | `Str` | The whole document in canonical order, LF-terminated. |

`tap_passed + tap_failed + tap_skipped + tap_todo` equals
`tap_test_count`; a passing `TODO` is counted in `tap_todo`, not in
`tap_passed` (it is an unexpected success).

## Usage

```xi
use xiom.tap;
use xiom.io;

fn main() -> Int {
  let r = tap_parse("1..2\nok 1 adds\nnot ok 2 divides # TODO fix\n");
  match r {
    Ok(d) => {
      io.println(tap_planned(&d));   // 2
      io.println(tap_passed(&d));    // 1
      io.println(tap_todo(&d));      // 1
      io.println(tap_emit(&d));      // canonical replay, LF-terminated
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

Emitting a document built by hand:

```xi
var d = tap_doc_new();
tap_set_plan(&mut d, 1);
tap_add_test(&mut d, true, "checks things", "", "");
io.println(tap_emit(&d));          // "1..1\nok 1 checks things\n"
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.tap
```

Expected tail: 24 `[PASS]` lines, `xiom.tap: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- Flat TAP only: no subtests, no `pragma`, no YAML diagnostics (a `---` /
  `...` block is rejected with a dedicated error), no TAP 14 nested indentation.
- A plan is optional (`tap_planned` returns `-1`) and is never checked against
  the number of results; the codec does not judge whether a run succeeded.
- Test numbers must be sequential from 1 in stream order; out-of-order TAP is
  rejected rather than reordered.
- The plan may be first or last, but never between results (TAP 14 rule,
  enforced strictly).
- Diagnostics keep their text but not their stream position; `tap_emit`
  writes them all after the version line and before the plan.
- A description may contain `#` only when it is not preceded by whitespace; a
  ` # SKIP` / ` # TODO` tail is always a directive, so such text cannot be
  represented and does not round-trip.
- Comments on the plan line (`1..3 # SKIP`) are not supported.
- `Bail out!` is case-sensitive and always stops the parse; everything after
  it (including later errors) is ignored by design.
- In-memory only: no streaming, no file I/O, no FFI.

See `SPEC.md` for the exact grammar, policies, error catalog and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
