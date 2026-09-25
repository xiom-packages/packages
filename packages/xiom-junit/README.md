# xiom.junit

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a JUnit XML report codec for a documented subset: parse, query
> and canonical re-emit.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.junit` parses a practical subset of JUnit XML reports into a flat,
allocation-friendly model and answers structural questions about it: suite
counts and fields, case counts by outcome, case name/classname/time, and the
message/type/text of a case's outcome element. `junit_emit` writes the model
back out in a deterministic canonical form, so `parse -> emit -> parse` is a
byte-stable round-trip.

The codec never touches a C library: scanning is byte-wise over the input
`Str`, attribute values are entity-decoded into a `Vec[UInt8]` builder, and
every public function is a free function.

Parsed reports are *flat*: suites and cases live in parallel vectors
(`suite_names`, `suite_tests`, ..., `case_names`, `case_classnames`, ...)
instead of nested records, and a case points at its owning suite through
`case_suites[i]`. This is the ecosystem pattern for XIOM v0.61.3, where
`Vec[StructType]` is unsupported.

## Supported subset

- an optional `<testsuites tests failures errors skipped time>` wrapper with
  `<testsuite name tests failures errors skipped time>` children, or a bare
  `<testsuite>` as the document root;
- `<testcase name classname time>` children, each holding at most one of
  `<failure>`, `<error>` or `<skipped>` (self-closing or with opaque text);
- `message`/`type` attributes on the outcome elements;
- single- or double-quoted attribute values with entity decoding
  (`&amp; &lt; &gt; &quot; &apos;`, `&#NN;`, `&#xHH;`);
- whitespace, comments and processing instructions (including the
  `<?xml ... ?>` declaration).

Everything else -- DTDs, CDATA, namespaces, `<properties>`, `<system-out>`,
`<system-err>`, timestamps, schemas -- is a documented error or ignored
attribute, never a silent misinterpretation. See `SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `junit_parse(text)` | `Result[JUnitDoc, Str]` | Parse a whole report; `Err("junit: ...")` on malformed input. |
| `junit_emit(d)` | `Str` | Canonical serialization of a parsed report. |
| `junit_has_wrapper(d)` | `Bool` | True when the root was `<testsuites>`, false for a bare `<testsuite>`. |
| `junit_suite_count(d)` | `Int` | Number of suites. |
| `junit_case_count(d)` | `Int` | Number of testcases. |
| `junit_case_count_by_outcome(d, o)` | `Int` | Cases with outcome `o` (`JUNIT_PASSED/FAILURE/ERROR/SKIPPED`). |
| `junit_suite_name(d, s)` | `Str` | Suite name; `""` out of range. |
| `junit_suite_tests/failures/errors/skipped(d, s)` | `Int` | Declared suite counts (0 when absent; -1 out of range). |
| `junit_suite_time(d, s)` | `Str` | Suite time attribute as written (`""` when absent). |
| `junit_suite_case_count(d, s)` | `Int` | Cases owned by suite `s`. |
| `junit_case_suite(d, i)` | `Int` | Owning suite index; -1 out of range. |
| `junit_case_name(d, i)` | `Str` | Case name. |
| `junit_case_classname(d, i)` | `Str` | Case classname (`""` when absent). |
| `junit_case_time(d, i)` | `Str` | Case time attribute as written. |
| `junit_case_outcome(d, i)` | `Int` | `JUNIT_*` code, or -1 out of range. |
| `junit_case_message(d, i)` | `Str` | Outcome message attribute (decoded). |
| `junit_case_type(d, i)` | `Str` | Outcome type attribute (decoded). |
| `junit_case_text(d, i)` | `Str` | Outcome text, verbatim. |
| `junit_total_tests/failures/errors/skipped(d)` | `Int` | Wrapper totals (0 when absent). |
| `junit_total_time(d)` | `Str` | Wrapper time attribute as written. |
| `junit_outcome_name(o)` | `Str` | `"passed"`, `"failure"`, `"error"`, `"skipped"`, or `""`. |

Outcome codes: `JUNIT_PASSED = 0`, `JUNIT_FAILURE = 1`, `JUNIT_ERROR = 2`,
`JUNIT_SKIPPED = 3`.

Errors: a single catalog of `Err("junit: ...")` strings (see SPEC.md); the
most common are `junit: mismatched closing tag`, `junit: unknown tag '<name>'`
and `junit: premature EOF`.

## Usage

```xi
use xiom.junit;
use xiom.io;

fn main() -> Int {
  let src = "<testsuite name=\"math\" tests=\"2\"><testcase name=\"adds\" classname=\"pkg.Math\"/><testcase name=\"divides\" classname=\"pkg.Math\"><failure message=\"division by zero\">expected 2, got error</failure></testcase></testsuite>";
  let res = junit_parse(src);
  if !res.is_ok {
    io.println("parse error: " + res.error);
    return 1;
  }
  let d = res.value;
  io.println(junit_suite_name(&d, 0));                             // math
  io.println(junit_outcome_name(junit_case_outcome(&d, 0)));       // passed
  io.println(junit_outcome_name(junit_case_outcome(&d, 1)));       // failure
  io.println(junit_case_message(&d, 1));                           // division by zero
  io.println(junit_case_text(&d, 1));                              // expected 2, got error
  io.println(junit_emit(&d));                                      // canonical XML
  return 0;
}
```

`junit_emit` produces stable output for a given model (fixed attribute order,
two-space indentation, one element per line), so it is suitable as a
serialization baseline in tests.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.junit
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No DTD / DOCTYPE and no CDATA.** Any `<!` construct other than a comment
  is rejected with `Err("junit: unsupported markup")`.
- **No `<properties>`, `<system-out>` or `<system-err>`.** They are outside
  the subset and are rejected as unknown tags; the codec covers suites, cases
  and their outcome elements only.
- **No namespaces**; `:` is an ordinary name byte and prefixes are not
  resolved.
- **Attribute entity subset.** Only `&amp; &lt; &gt; &quot; &apos;`, `&#NN;`
  and `&#xHH;` decode; anything else in an attribute value is
  `Err("junit: bad entity")`. `&#0;` and codepoints above U+10FFFF are
  rejected too.
- **Outcome text is opaque.** It is stored and re-emitted verbatim: no entity
  decoding on parse, no escaping on emit. Reports whose text is already
  escaped round-trip byte-for-byte; a model whose text contains a literal
  `</failure>` (etc.) sequence is not supported.
- **Unknown attributes are ignored** (for example `hostname`, `id`,
  `timestamp`, `assertions`, `line`, `file`). They are not stored and are not
  reproduced by `junit_emit`; round-trips are model round-trips.
- **Counts are integers.** `tests`/`failures`/`errors`/`skipped` accept at
  most 18 decimal digits; `time` is never parsed or formatted numerically
  (kept as written, including an absent attribute as `""`).
- **One outcome element per case.** A second `<failure>`, `<error>` or
  `<skipped>` is `Err("junit: misplaced tag '<name>'")`.
- **One root element.** A bare `<testsuite>` and a `<testsuites>` wrapper are
  both accepted, but a second top-level element and non-whitespace text
  outside the root are errors.
- In-memory only: `junit_parse` consumes a whole `Str`; no streaming, no
  schema validation, no UTF-8 validation of the input (bytes pass through,
  only markup bytes are interpreted), and NUL bytes are not supported.

See `SPEC.md` for the grammar subset, the full error catalog, the exact
canonical output rules and the test plan. License: MIT OR Apache-2.0 (see the
repository root `LICENSE`).
