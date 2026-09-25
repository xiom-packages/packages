# xiom.tap -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.tap` (`src/tap.xi`). Pure XIOM, no FFI, no I/O.

## 1. Scope

A line-based parser and canonical emitter for a documented flat TAP subset,
all in memory:

- `tap_parse` reads one `Str` stream into a `TapDoc`;
- accessors expose the version, the plan, every result (number, verdict,
  description, directive kind and reason), summary counts and the raw
  diagnostics;
- builders (`tap_doc_new`, `tap_add_test`, `tap_set_*`, `tap_add_diagnostic`)
  construct or extend a document without parsing;
- `tap_emit` and the `tap_write_*` helpers serialize a document back to TAP.

The subset is: the version line `TAP version <N>`, the plan `1..<N>`, flat
results `ok <n> [description]` / `not ok <n> [description]`, the directives
`# SKIP <reason>` / `# TODO <reason>` (case-insensitive), full-line `# ...`
diagnostics, blank lines, and `Bail out! <reason>`. The grammar in section 4
is exact; section 9 is the complete error catalog. Anything outside the
subset is a deterministic `Err("tap: ...")` with a 1-based line number.

`Str` is treated as a UTF-8 byte buffer. Line scanning is byte-wise; every
stored slice is a slice of the input, so non-ASCII text (including multi-byte
UTF-8 in descriptions, reasons and diagnostics) round-trips byte-exact.

## 2. Non-goals

- **No test execution.** The module is a codec; it never runs a test.
- **No TAP 14 subtests** and no indentation-based nesting: a subtest body is
  not parsed as a nested document.
- **No YAML diagnostics.** `---` / `...` blocks are rejected, not captured
  and not interpreted (section 5, rule 8).
- **No plan/count reconciliation, no pass/fail verdict for the stream.** The
  codec reports what it read; deciding whether the run succeeded is the
  caller's job.
- **No streaming / incremental parsing**; the whole `Str` is in memory.
- **No error recovery.** The first offending line aborts the parse; results
  parsed before it are discarded (the function returns `Err`).
- **No pragmas, no filters, no test-point escaping, no `todo`/`skip`
  aggregation across files.**
- No file I/O, no FFI, no registry integration, no new dependencies.

## 3. Data model

`TapDoc` is flat because XIOM v0.61.3 cannot hold `Vec[StructType]`:

```xi
pub type TapDoc = {
  version: Int;         // 0 = no version line
  planned: Int;         // -1 = no plan line; 0 is the valid "1..0" plan
  bailed: Bool;         // true when a "Bail out!" line was seen
  bail_reason: Str;     // "" when absent or bare
  numbers: Vec[Int];
  oks: Vec[Int];        // 1 = ok, 0 = not ok
  descriptions: Vec[Str];
  directives: Vec[Str]; // "" | "skip" | "todo"
  reasons: Vec[Str];
  diagnostics: Vec[Str];
}
```

Result `i` (0-based, in stream order) is `numbers[i]`, `oks[i]`,
`descriptions[i]`, `directives[i]`, `reasons[i]`. The five test arrays are
kept index-aligned by `tap_parse` and `tap_add_test`; accessors and
`tap_emit` operate on `_test_count` = the shortest of the five lengths, so a
hand-built document can never read out of range.

Summary partition (each result falls in exactly one bucket):

| Bucket | Predicate |
|---|---|
| `tap_passed` | `ok` and no directive |
| `tap_failed` | `not ok` and no directive |
| `tap_skipped` | directive `skip` (regardless of the verdict) |
| `tap_todo` | directive `todo` (regardless of the verdict) |

A passing `TODO` is an unexpected success and is counted in `tap_todo`, not
in `tap_passed`.

## 4. Exact line grammar

```
stream      = *( blank / comment / version / plan / test / bail )
blank       = ws*
comment     = ws* "#" rest
version     = ws* "TAP version" ws+ digits ws*
plan        = ws* "1.." digits ws*
test        = ws* verdict ws+ digits [ ws+ description ] [ directive ] ws*
verdict     = "ok" / "not ok"
directive   = ws+ "#" ws* WORD [ ws+ reason ]
bail        = ws* "Bail out!" [ ws+ reason ] ws*
ws          = SPACE / TAB
digits      = 1*( "0".."9" )            value <= 1000000000
WORD        = bytes up to the next ws, matched to SKIP/TODO case-insensitively
rest        = any byte except LF and CR
reason      = rest of line, trimmed
description = text between the number and a directive "#" (or end of line),
              leading/trailing ws trimmed, interior bytes verbatim
```

Line splitting: the stream is split on LF; one CR immediately before the LF
(or before end of input) is dropped, so LF and CRLF both work. A standalone
CR is content, not a terminator. Every line's leading and trailing SPACE/TAB
bytes are then ignored (`ws*` above); blank lines produce nothing.

An unrecognized non-blank line is `Err` (section 9).

## 5. Parsing rules and decisions

Each rule is covered by the conformance suite; section 11 maps them to checks.

1. **Dispatch.** A non-blank trimmed line is classified in this order:
   `Bail out!`, `TAP version` (with a word boundary), `#` comment, `ok` /
   `not ok` result, YAML marker, plan candidate (contains `..`), otherwise
   unrecognized.
2. **Version.** `TAP version <N>` requires literal `TAP version` (case
   sensitive) followed by ws or end of line, then a digits run with value
   `>= 1`. It must be the **first non-blank line**: any earlier non-blank
   line (including a comment) or a second version line is `misplaced`. The
   value is stored, never gated against a supported version list. `N = 0`,
   non-digits, trailing junk and an empty value are `bad version line`.
3. **Plan.** Exactly `1..<N>`: the text before `..` must be the single byte
   `1` (so `01..3` and `2..3` are `bad plan`), the text after it a digits run
   (`N >= 0`, `1..0` valid); anything else after the digits is `bad plan`. At
   most one plan line; a second is `duplicate plan`.
4. **Plan position.** The plan may appear before the first result (plan
   first) or after the last one (plan last). A plan that appears after at
   least one result and is followed by another result is `plan after tests`
   at the plan's line. Plan-first streams and plan-last streams are both
   accepted and both count as valid TAP 13/14 orderings.
5. **Plan count is not reconciled.** The number of results need not equal
   `tap_planned`; the codec does not enforce or repair it.
6. **Test line.** `ok` / `not ok` must be followed by ws or end of line. The
   number is a digits run immediately after optional ws; it must be followed
   by ws or end of line. No number (`ok`, `ok x`, `ok 1x`) is `bad test line`.
7. **Sequential numbers.** The k-th result line in stream order must carry
   number k. Leading zeros are accepted (`ok 01` is number 1). A number that
   does not match is `non-sequential test number`; an unparseable or larger
   than 1000000000 digits run is `bad test line`.
8. **Negative numbers.** A `-` where the number is expected is
   `negative test number` (never a wrapped value).
9. **Description.** Everything between the number (and its separator) and the
   directive `#` (or the end of line), with leading and trailing SPACE/TAB
   removed and interior bytes verbatim. A result with no text has description
   `""`.
10. **Directive.** A `#` starts a directive when it is the first byte of the
    description region or is preceded by SPACE/TAB; the first such `#` wins.
    A `#` inside a description (`issue#42`) stays in the description. The
    WORD after `#` (optional ws) must be `SKIP` or `TODO` in any case and be
    followed by ws or end of line; otherwise `bad directive`. The reason is
    the remaining text with surrounding ws removed (`""` when absent).
    Directive text cannot be represented in a description; see section 12.
11. **Diagnostics.** A line whose first non-ws byte is `#` is a comment; the
    stored text is everything after the `#` with following ws removed and
    trailing ws already stripped (`#` alone stores `""`). Diagnostics keep
    their text, not their stream position (section 8).
12. **YAML blocks are rejected.** A trimmed line equal to exactly `---` or
    `...` is `yaml diagnostics unsupported`. Other YAML body lines (for
    example `message: hi`) fall through to the unrecognized-line errors.
13. **Bail out.** A line starting with the literal `Bail out!` (case
    sensitive) sets `bailed`; the reason is the rest of the line, trimmed.
    Parsing stops immediately: every later line, valid or not, is ignored.
    A bail-out line may appear at any point, including before the plan; then
    `planned` stays `-1`.
14. **Text before plan.** An unrecognized line seen before any plan line is
    `text before plan`; after a plan line it is `unrecognized line`. This is
    the only difference between the two messages.
15. **No BOM handling.** A leading UTF-8 BOM is content, not whitespace, and
    makes the first line unrecognized.
16. **Determinism.** The same input always yields the same document or the
    same first error; the input is never mutated.

## 6. Directive rules

- `SKIP` and `TODO` are matched case-insensitively (`skip`, `Skip`, `sKiP`).
- The canonical stored form is lowercase `"skip"` / `"todo"`; no directive is
  `""`.
- The word must end at ws or end of line: `# TODO(y)` and `# nope` are
  `bad directive`; `#` alone is `bad directive`.
- A reason is optional and stored as `""` when absent; a reason may itself
  contain `#` (`# SKIP see #4` stores `see #4`).
- A directive may ride on either verdict: `not ok 2 # SKIP` stores
  `skip` and counts in `tap_skipped` (the summary bucket is decided by the
  directive, not the verdict).
- `TODO` and `SKIP` are line directives only; the plan line does not accept
  a directive (it is `bad plan`).

## 7. Bail out

`Bail out!` (exact case, `!` included) is recognized at the start of a
trimmed line, optionally followed by a reason. Once seen:

- `tap_bailed(d)` is `true` and `tap_bail_reason(d)` holds the trimmed reason
  (`""` for a bare line);
- parsing returns `Ok` immediately, as bailed-out streams are valid and
  incomplete by definition;
- every subsequent line is ignored, so a later `---`, bad plan or bad test
  cannot fail the parse.

`tap_emit` writes the bail line last, after the results that preceded it.

## 8. Canonical emitter

`tap_emit(d)` writes exactly this order, each emitted line terminated by LF:

1. `TAP version <N>` when `tap_version > 0` (`tap_write_version`);
2. every diagnostic in stored order via `tap_write_comment`, i.e. `#` or
   `# <text>`;
3. `1..<N>` when `tap_planned >= 0` (`tap_write_plan`);
4. every result in stored order via `tap_write_test`, using the stored
   numbers (never renumbered);
5. `Bail out! <reason>` when `tap_bailed` (`tap_write_bail`).

An empty document emits `""` (no bytes). `tap_write_test` trims the
description and reason, omits empty parts, and renders the directive as
`# SKIP` / `# TODO` in upper case (a non-empty directive that matches
neither keyword is emitted verbatim after `#`, and such a line may not
re-parse). The number is emitted verbatim and is not validated; negative or
non-sequential numbers are the caller's problem, not the writer's.

Two documented canonicalizations mean `tap_emit` is not byte-identical to an
arbitrary accepted input:

- a plan parsed from the end of the stream is emitted first;
- diagnostics are emitted as one block after the version line, because their
  stream positions are not stored.

Both preserve the parsed structure (section 10), and `tap_emit` is
idempotent: `tap_emit(parse(tap_emit(d))) == tap_emit(d)`.

## 9. Error catalog

All messages are `"tap: "` + a lower-case description; `<L>` is the 1-based
physical line number of the offending line, `<n>` / `<m>` are decimal.

| Condition | Exact message |
|---|---|
| Version digits empty/non-numeric/zero/overflow | `tap: bad version line at <L>` |
| Version line not first non-blank, or second version line | `tap: misplaced version line at <L>` |
| Plan not exactly `1..<N>` (wrong start, `..`, junk, negative, overflow) | `tap: bad plan at <L>` |
| Second plan line | `tap: duplicate plan at <L>` |
| Plan after results that is followed by another result | `tap: plan after tests at <L>` (`<L>` = plan line) |
| Test line without a usable number, or junk after it | `tap: bad test line at <L>` |
| Test number begins with `-` | `tap: negative test number at <L>` |
| Test number differs from its stream position | `tap: non-sequential test number at <L>: got <n>, expected <m>` |
| Directive word is not SKIP/TODO (including empty) | `tap: bad directive at <L>` |
| Trimmed line is exactly `---` or `...` | `tap: yaml diagnostics unsupported at <L>` |
| Unrecognized non-blank line before any plan line | `tap: text before plan at <L>` |
| Unrecognized non-blank line after a plan line | `tap: unrecognized line at <L>` |

Errors are reported for the first offending line; everything parsed before
it is discarded because `tap_parse` returns `Err`, not a partial document.

## 10. API contract

```xi
pub fn tap_parse(text: Str) -> Result[TapDoc, Str]
pub fn tap_doc_new() -> TapDoc
pub fn tap_add_test(d: &mut TapDoc, ok: Bool, description: Str, directive: Str, reason: Str)
pub fn tap_set_version(d: &mut TapDoc, n: Int)
pub fn tap_set_plan(d: &mut TapDoc, n: Int)
pub fn tap_set_bail(d: &mut TapDoc, reason: Str)
pub fn tap_add_diagnostic(d: &mut TapDoc, text: Str)
pub fn tap_version(d: &TapDoc) -> Int
pub fn tap_planned(d: &TapDoc) -> Int
pub fn tap_test_count(d: &TapDoc) -> Int
pub fn tap_number(d: &TapDoc, i: Int) -> Int
pub fn tap_is_ok(d: &TapDoc, i: Int) -> Bool
pub fn tap_description(d: &TapDoc, i: Int) -> Str
pub fn tap_directive(d: &TapDoc, i: Int) -> Str
pub fn tap_reason(d: &TapDoc, i: Int) -> Str
pub fn tap_passed(d: &TapDoc) -> Int
pub fn tap_failed(d: &TapDoc) -> Int
pub fn tap_skipped(d: &TapDoc) -> Int
pub fn tap_todo(d: &TapDoc) -> Int
pub fn tap_bailed(d: &TapDoc) -> Bool
pub fn tap_bail_reason(d: &TapDoc) -> Str
pub fn tap_diagnostic_count(d: &TapDoc) -> Int
pub fn tap_diagnostic(d: &TapDoc, i: Int) -> Str
pub fn tap_write_version(n: Int) -> Str
pub fn tap_write_plan(n: Int) -> Str
pub fn tap_write_test(number: Int, ok: Bool, description: Str, directive: Str, reason: Str) -> Str
pub fn tap_write_comment(text: Str) -> Str
pub fn tap_write_bail(reason: Str) -> Str
pub fn tap_emit(d: &TapDoc) -> Str
```

Out-of-range accessors: `tap_number` -> `-1`, `tap_is_ok` -> `false`,
`tap_description` / `tap_directive` / `tap_reason` / `tap_diagnostic` -> `""`.

`tap_add_test` appends to all five parallel arrays and assigns the next free
number (result count + 1). `tap_set_version` / `tap_set_plan` store the value
as given (the emitter and accessors interpret `<= 0` / `< 0` as "absent");
`tap_set_bail` sets the flag and reason; there is no way to clear it.

**Round trip.** For any document `d` produced by `tap_parse`, let
`e = tap_emit(d)`. Then `tap_parse(e)` succeeds and returns a document with
the same version, planned, verdicts, numbers, descriptions, directives,
reasons, diagnostics, bail flag and bail reason; and `tap_emit` of that
document equals `e`. The suite checks this with a structural comparison plus
string equality of the two emissions, never with `==` on element strings
(BUG 17).

Complexity: `tap_parse` and `tap_emit` are O(input length) with string
concatenation costs; accessors are O(1); summary counts are O(results).

## 11. Test matrix

`tests/test_conformance.xi` (module `tap_tests`) runs 24 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). All string comparisons go through `str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | version, plan, results, summary counts | rules 2, 3, 6, 7, section 3 |
| t2 | SKIP/TODO mixed case and buckets | section 6 |
| t3 | diagnostics captured raw | rule 11 |
| t4 | CRLF, blank lines, surrounding ws | line splitting, rule 16 |
| t5 | plan last accepted, canonical plan first | rules 4, 8 |
| t6 | `1..0` | rule 3 |
| t7 | no plan -> `planned = -1` | rule 5 (absence is legal) |
| t8 | Bail out! stops the parse | section 7 |
| t9 | bare Bail out! reason `""` | section 7 |
| t10 | malformed plans | rule 3, catalog |
| t11 | duplicate plan | rule 3 |
| t12 | plan between tests vs plan last | rule 4 |
| t13 | non-sequential and zero numbers | rule 7 |
| t14 | negative numbers | rule 8 |
| t15 | bad directives | rule 10, section 6 |
| t16 | text before plan / unrecognized line / bad test line | rules 6, 14 |
| t17 | version first-line rule | rule 2 |
| t18 | YAML block rejection | rule 12 |
| t19 | round trip incl. bail, `1..0`, reason with `#` | section 10 |
| t20 | all `tap_write_*` helpers, empty cases | section 8 |
| t21 | `#` boundaries, description trimming, number-only results | rules 9, 10 |
| t22 | accessor bounds and sentinels | section 10 |
| t23 | builder API -> canonical emit -> round trip | sections 3, 8 |
| t24 | empty and blank-only streams | rule 16, section 8 |

## 12. Known limitations

- No subtests, pragmas or YAML diagnostics (rejected, rule 12).
- No plan/count reconciliation and no whole-stream verdict.
- Numbers must be sequential; out-of-order streams are rejected, not sorted.
- A result whose description would end in ` # SKIP <reason>` or
  ` # TODO <reason>` cannot be represented: the parser reads it as a
  directive, so the description does not round-trip. Put such text in a
  comment line instead.
- Diagnostics lose their position; the emitter groups them after the version.
- A trailing comment on the plan line (`1..3 # SKIP`) is `bad plan`.
- `Bail out!` is case-sensitive and always terminal.
- The digit runs (plan and test numbers) are capped at 1000000000; larger
  values are rejected by the overflow guard rather than wrapping.
- No BOM stripping, no standalone-CR line endings, no Unicode-aware
  whitespace trimming (only SPACE and TAB).

## 13. Compiler / stdlib notes (v0.61.3)

The implementation follows the proven idioms of the sibling packages
(`xiom.csv`, `xiom.lexing`, `xiom.ini`): free functions only, flat parallel
`Vec`s instead of `Vec[StructType]`, byte-wise scanning with
`xiom.string.byte_at` / `str_slice`, and `Result` construction confined to the
leaf helpers `_ok_doc` / `_err_doc` because constructing `Ok`/`Err` in other
shapes miscompiles in this compiler.

Every `Str` read from a `Vec[Str]` element is bound to a typed local before
use and compared with `str_compare` (BUG 17: `==` on such values lowers to a
pointer comparison). `Int` element reads are likewise bound to typed locals.
Widened bytes are masked (`(b as Int) & 0xFF`). No `&struct.field` is passed
as a `&Vec` parameter, so the empty-vector payload defect does not apply.
Mismatched parallel arrays are clamped to their shortest length in
`_test_count`, so a hand-built document can never cause an out-of-range read.
No workarounds beyond these documented patterns were required.
