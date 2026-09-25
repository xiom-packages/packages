# xiom.junit -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.junit`, version `0.1.0`).
Module: `src/junit.xi` (`module xiom.junit`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) JUnit XML report codec for a documented subset, with
three operations:

- `junit_parse` builds a flat report model (`JUnitDoc`) from a whole `Str`,
  validating nesting and the attribute syntax;
- accessors answer structural questions: suite count and fields, case count
  by outcome, owning suite, case name/classname/time, and the
  message/type/text of a case's outcome element;
- `junit_emit` serializes a parsed report back to a canonical, deterministic
  `Str` such that `parse -> emit -> parse` preserves the model and the
  emitted bytes are stable.

Count attributes are parsed as integers; the `time` attribute is opaque text.

## Non-goals

- xUnit schemas beyond the subset: no `<properties>`, `<system-out>`,
  `<system-err>`, no `<testsuites>`-level nesting variants, no `disabled`/
  `assertions`/`hostname`/`timestamp`/`package`/`id`/`file`/`line` semantics
  (unknown attributes are accepted and ignored).
- Timestamps and durations: `time` is kept exactly as written, never parsed
  as a number and never arithmetic.
- Full XML: no DTD/DOCTYPE, no CDATA, no namespaces, no XML declarations
  beyond skipping a `<?...?>` processing instruction, no entity declarations,
  no schema validation.
- Document-order reconstruction of unknown attributes or unknown elements.
- Streaming / incremental parsing, SAX-style callbacks; `junit_parse`
  consumes a whole `Str`.
- UTF-16 input, BOM handling, Unicode normalization; byte length/validity of
  the input is not validated.
- Escaping or decoding of outcome text content (documented as opaque below).

## Grammar subset

Informal EBNF over bytes; `WS` is space, tab, CR or LF:

```
document   = misc* root misc* EOF
misc       = WS | "<!--" ... "-->" | "<?" ... "?>"
root       = testsuites | testsuite
testsuites = "<testsuites" attr* WS? ( "/>" | ">" suite* "</testsuites>" )
suite      = "<testsuite" attr* WS? ( "/>" | ">" case* "</testsuite>" )
case       = "<testcase" attr* WS? ( "/>" | ">" outcome? "</testcase>" )
outcome    = ("<failure" | "<error" | "<skipped") attr* WS? ( "/>"
           | ">" rawtext "</failure"> | "</error>" | "</skipped>" )
attr       = name WS? "=" WS? ( '"' [^"]* '"' | "'" [^']* "'" )
rawtext    = any bytes up to the first literal "</failure>"/"</error>"/"</skipped>"
name       = non-empty byte run excluding WS, '<', '>', '/' and '='
```

Rules:

- the root element must be exactly one `<testsuites>` wrapper or one bare
  `<testsuite>`; comments and processing instructions are accepted wherever
  whitespace is accepted, including before and after the root;
- `WS` between attributes, between elements and around `/` and `>` is
  ignored; whitespace-only character data is ignored everywhere;
- non-whitespace character data where elements are expected (document level,
  inside `<testsuites>`, `<testsuite>` or `<testcase>`) is an error;
- attribute values must be quoted (double or single quotes); entity decoding
  applies to attribute values only, with `&amp; &lt; &gt; &quot; &apos;`,
  `&#NN;` (decimal) and `&#xHH;`/`&#XHH;` (hex); a reference that is unknown,
  malformed, unterminated, `&#0;` or above U+10FFFF is
  `Err("junit: bad entity")`;
- count attributes (`tests`, `failures`, `errors`, `skipped`) accept `""` or
  a decimal integer of at most 18 digits; anything else is
  `Err("junit: invalid integer attribute")`; a missing attribute is 0;
- `time` (wrapper, suite, case) is stored verbatim; a missing attribute is
  `""`;
- `name` is required and non-empty on `<testsuite>` and `<testcase>`
  (`Err("junit: missing name")` otherwise); `classname` is optional;
- a `<testcase>` may hold at most one outcome element; a second one is
  `Err("junit: misplaced tag '<name>'")`;
- a non-self-closing outcome element consumes raw text up to the first
  literal `</name>` (see "Outcome text" below); a missing close is
  `Err("junit: premature EOF")`;
- `</name>` must match the innermost open element exactly (byte comparison).

## Outcome text

Outcome text is passed through: the bytes between the outcome start tag and
the first literal `</failure>`/`</error>`/`</skipped>` are stored as-is, with
no entity decoding and no markup interpretation. On emit the text is written
back verbatim, so already-escaped text (`&lt;`, `&amp;`, CDATA sections,
... ) survives byte-for-byte and `parse -> emit -> parse` is stable. Text
that contains the literal closing sequence is cut at the first occurrence;
this is documented pass-through behavior, not an error.

Attributes follow the opposite rule: they are decoded on parse and escaped on
emit (`& < > " '` as named entities), so entity-bearing attribute values also
round-trip.

## Model

`JUnitDoc` is flat; every field is a scalar or a `Vec` of scalars/`Str` (no
`Vec[StructType]`).

| Field | Meaning |
|---|---|
| `has_wrapper` | `1` when the root was `<testsuites>`, `0` for a bare `<testsuite>`. |
| `total_tests` / `total_failures` / `total_errors` / `total_skipped` | Wrapper count attributes (0 when absent, including a wrapper-less document). |
| `total_time` | Wrapper time text (`""` when absent). |
| `suite_names[i]` | Suite name. |
| `suite_tests[i]` / `suite_failures[i]` / `suite_errors[i]` / `suite_skipped[i]` | Declared suite counts (0 when absent). |
| `suite_times[i]` | Suite time text (`""` when absent). |
| `case_suites[i]` | Owning suite index (document-order case index, suite index). |
| `case_names[i]` / `case_classnames[i]` / `case_times[i]` | Case identity fields (classname/time `""` when absent). |
| `case_outcomes[i]` | `JUNIT_PASSED`, `JUNIT_FAILURE`, `JUNIT_ERROR` or `JUNIT_SKIPPED`. |
| `case_messages[i]` / `case_types[i]` | Decoded `message`/`type` of the outcome element (`""` for a passed case or absent attribute). |
| `case_texts[i]` | Verbatim outcome text (`""` for a passed case or self-closing outcome). |

Suites and cases are appended in document order. All suite vectors advance
together (six pushes per suite) and all case vectors advance together (eight
pushes per case), so the vectors never drift during parsing; the accessors
nonetheless guard every index, and `junit_suite_count`/`junit_case_count`
return the minimum vector length for hand-built reports.

## API semantics

`junit_parse(text)`
: `Ok(doc)` for a report in the subset. `Err(msg)` for the first malformed
  construct, with `msg` from the catalog below.

`junit_emit(d)`
: Canonical serialization (rules below). For any doc returned by
  `junit_parse`, `junit_parse(junit_emit(d))` yields an equal model and
  re-emitting yields identical bytes.

`junit_has_wrapper(d)` / `junit_suite_count(d)` / `junit_case_count(d)`
: `Bool` / `Int` / `Int`; counts are 0 for empty reports.

`junit_case_count_by_outcome(d, o)`
: Number of cases whose outcome equals `o`; unknown codes count 0.

`junit_suite_name(d, s)` / `junit_suite_time(d, s)` / `junit_case_name(d, i)` /
`junit_case_classname(d, i)` / `junit_case_time(d, i)` /
`junit_case_message(d, i)` / `junit_case_type(d, i)` / `junit_case_text(d, i)`
: `Str` values; out-of-range indices and absent attributes both yield `""`.

`junit_suite_tests/failures/errors/skipped(d, s)`
: Declared counts; -1 when `s` is out of range (absent attributes are 0).

`junit_case_outcome(d, i)` / `junit_case_suite(d, i)`
: `Int`; -1 when `i` is out of range.

`junit_suite_case_count(d, s)`
: Case count owned by suite `s`; 0 for an out-of-range suite index.

`junit_total_tests/failures/errors/skipped(d)` / `junit_total_time(d)`
: Wrapper attributes (0/`""` when absent or wrapper-less).

`junit_outcome_name(o)`
: `"passed"`, `"failure"`, `"error"`, `"skipped"`; `""` for any other value.

## Canonical emission

- two-space indentation, one element per line, LF line endings;
- wrapper and suites open as `<testsuites ...>` / `<testsuite ...>`, cases as
  self-closing `<testcase .../>` when there is no outcome element;
- fixed attribute order: wrapper/suite `tests`, `failures`, `errors`,
  `skipped`, `time`; testcase `name`, `classname`, `time`; outcome `message`,
  `type`;
- count attributes are always written (0 when stored as 0); the optional
  `time` and `classname` attributes are written only when non-empty;
- an outcome with empty text collapses to a self-closing tag
  (`<failure message="m"/>`); non-empty outcome text is written verbatim;
- attribute values are escaped (`& < > " '` as `&amp; &lt; &gt; &quot;`
  `&apos;`); outcome text is not escaped (pass-through);
- output always ends with a LF after the root element's closing tag.

Example (source parsed and re-emitted):

```
<testsuite name="s" tests="1" failures="1" errors="0" skipped="0">
  <testcase name="c" classname="C" time="0.5">
    <failure message="m &amp; n" type="E">assert failed: a &gt; b</failure>
  </testcase>
</testsuite>
```

## Error string catalog

All errors are `Err("junit: ...")`; the first failure in document order wins.

| Condition | Error text |
|---|---|
| `</name>` not matching the innermost open element, or a closing tag with no open element | `junit: mismatched closing tag` |
| Start tag outside the subset (`<widget>`, `<>`, `<!DOCTYPE ...` handled separately) | `junit: unknown tag '<name>'` |
| Subset tag in a context that does not allow it (second root, `<testcase>` under `<testsuites>`, `<testsuite>` inside `<testsuite>`, outcome element outside a testcase, a second outcome element) | `junit: misplaced tag '<name>'` |
| `<testcase>` directly inside another `<testcase>` | `junit: nested testcase` |
| `<testsuite>`/`<testcase>` without a non-empty `name` attribute | `junit: missing name` |
| Attribute value not started by `"` or `'` | `junit: unquoted attribute` |
| Attribute name without `=`, or junk where an attribute name is expected | `junit: malformed attribute` |
| Junk after `/` in a self-closing tag, or after a closing tag name | `junit: malformed tag` |
| Unknown, malformed, unterminated, zero-valued or out-of-range entity reference in an attribute value | `junit: bad entity` |
| Non-decimal, negative or longer-than-18-digit count attribute | `junit: invalid integer attribute` |
| Non-whitespace character data at document, wrapper, suite or case level | `junit: text where elements expected` |
| EOF inside a tag, a quoted attribute value, an open element or unterminated outcome text; empty document | `junit: premature EOF` |
| `<!` markup that is not a comment (DOCTYPE, CDATA, ...) | `junit: unsupported markup` |

## Complexity

| Operation | Complexity |
|---|---|
| `junit_parse` | O(n) over the report bytes (entity decoding is linear) |
| `junit_emit` | O(suites + cases + output bytes) |
| `junit_suite_count` / `junit_case_count` / `junit_case_suite` / `junit_suite_*` / `junit_case_*` scalar accessors | O(1) |
| `junit_case_count_by_outcome` / `junit_suite_case_count` | O(cases) |

## Test plan

`tests/test_conformance.xi` (`module junit_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. full report: wrapper totals, two suites, three cases, outcomes, messages,
   types, texts, per-suite case counts;
2. bare `<testsuite>` root: wrapper totals default to 0/`""`, case defaults;
3. all four outcome forms, including self-closing `<failure/>` and
   `<skipped message type/>`;
4. both quote styles and named/decimal/hex entity decoding in attributes
   (including a double quote inside a single-quoted value; multi-byte
   numeric references decode to UTF-8 and re-emit byte-stable);
5. outcome text pass-through: `&amp;`/`&lt;` stay literal, multiline text is
   preserved;
6. pretty-printed input, comments and processing instructions are skipped;
7. mismatched and unexpected closing tags;
8. unknown and misplaced tags (wrapper child, suite child, nested suite,
   second root);
9. nested testcase;
10. missing and empty `name` attributes;
11. unquoted values and malformed attributes;
12. bad entities (`&amp`, `&bogus;`, `&#xZZ;`, `&#0;`, `&;`);
13. non-whitespace text where elements are expected (five positions);
14. premature EOF (empty input, open tag, open element, unterminated outcome
    text, unterminated close tag);
15. non-decimal count attributes (wrapper and suite);
16. DOCTYPE and CDATA are unsupported markup;
17. a second outcome element on one testcase;
18. canonical emit byte-for-byte (attribute order, indentation, escaping of
    attribute values, verbatim outcome text);
19. round-trip: `parse -> emit -> parse` preserves every accessor value and
    the emitted bytes are stable;
20. empty `<testsuites/>` canonical output;
21. prolog declaration, comment and PI handling;
22. out-of-range accessor safety and `junit_outcome_name` mapping.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.junit
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No DTD/DOCTYPE, CDATA, namespaces or schema validation; `<!` non-comment
  markup is a hard error.
- `<properties>`, `<system-out>` and `<system-err>` are outside the subset
  and rejected as unknown tags; real-world reports containing them must be
  reduced to the subset first.
- Unknown attributes are accepted and ignored; `junit_emit` does not
  reproduce them, so output is canonical rather than a byte-copy of the
  input.
- Outcome text is opaque: no entity decoding on parse, no escaping on emit.
  Text whose bytes contain the matching literal close tag is cut there.
- Count attributes are in-memory `Int`s of at most 18 digits; `time` is never
  parsed or formatted as a number.
- NUL bytes and invalid UTF-8 are out of scope; input is expected to be
  UTF-8 text without NUL bytes.
- One root element and one outcome element per case.
- `junit_parse` builds all suites and cases in memory (no SAX-style
  callbacks).

## Compiler / stdlib notes for v0.61.3

- The report is a flat parallel-vector model because `Vec[StructType]` is
  unsupported in this compiler; nesting is validated with an explicit
  context stack (`ctx_kind`/`ctx_idx`/`ctx_name`), so parsing is iterative.
- `Ok`/`Err` for `Result[JUnitDoc, Str]` are constructed only in the leaf
  helpers `_ok_doc`/`_err_doc` (constructing Results directly elsewhere
  miscompiles in this compiler).
- All Str equality uses `xiom.string.compare.str_compare` (BUG 17: `==` on
  Str values read from `Vec[Str]` elements lowers to a pointer comparison).
  `_count_value` and `_push_str_bytes` walk bytes until the NUL terminator
  instead of trusting `.len()` on such values.
- Widened byte constants are masked (`(b as Int) & 0xFF`) before numeric use.
- Attribute and outcome values are bound to typed locals before being pushed
  onto parallel vectors, and every push group is mirrored so the vectors
  cannot drift on a parse error.
- The package declares no `extern "C"` blocks (no FFI); output is built with
  `xiom.string.builder` over `Vec[UInt8]` and materialized with
  `sb_to_str` exactly once per emitted report.
