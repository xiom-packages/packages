# xiom.sarif -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.sarif`, version `0.1.0`).
Module: `src/sarif.xi` (`module xiom.sarif`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`, `xiom.convert`).

## Scope

A pure-XIOM (no FFI) SARIF 2.1.0 report codec for a documented JSON subset,
with three operations:

- `sarif_parse` builds a flat report model (`SarifDoc`) from a whole `Str`,
  validating the subset grammar and the documented value constraints;
- accessors answer structural questions: run count and driver names, result
  counts by run and by level, per-result `ruleId` / `level` / `message.text`
  and the first location's uri/line/column, and per-location uri/line/column
  with range ownership;
- `sarif_emit` serializes a parsed report back to a canonical, deterministic
  `Str` such that `parse -> emit -> parse` preserves the model and the
  emitted bytes are stable.

Keys may appear in any order on input. An absent result `level` is stored as
`SARIF_LEVEL_WARNING` (the SARIF 2.1.0 default).

## Non-goals

- SARIF properties outside the subset: no `fixes`, `codeFlows`, `graphs`,
  `taxonomies`, `invocations`, `fingerprints`, `partialFingerprints`,
  `tool.driver.rules`, `properties`, `uriBaseId`, `contextRegion`,
  `relatedLocations`, `message.markdown`, `region.endLine` and so on (all
  unknown keys are errors).
- JSON flexibility the subset does not use: no floats, no exponents, no
  negative numbers, no booleans, no nulls, no non-ASCII strings, no nesting
  beyond the documented schema levels.
- SARIF JSON schema validation, semantic validation of rule ids, URI
  normalization or resolution, `$schema` interpretation.
- Document-order reconstruction of unknown or out-of-subset keys; canonical
  output is not a byte-copy of the input.
- Streaming / incremental parsing; `sarif_parse` consumes a whole `Str`.
- File IO: no paths, no readers/writers, no BOM handling. NUL bytes and
  invalid UTF-8 are out of scope.

## Grammar subset

Informal EBNF over bytes; `WS` is space (0x20), tab (0x09), CR (0x0D) or LF
(0x0A):

```
document = WS* object WS* EOF
object   = "{" WS* (member (WS* "," WS* member)*)? WS* "}"
member   = string WS* ":" WS* value
array    = "[" WS* (value (WS* "," WS* value)*)? WS* "]"
value    = string | integer | object | array | "true" | "false" | "null"
string   = '"' (raw | escape)* '"'
raw      = 0x20..0x7E except '"' and '\'
escape   = '\' ( '"' | '\' | '/' | 'b' | 'f' | 'n' | 'r' | 't'
              | 'u' hex hex hex hex )
hex      = 0-9 | a-f | A-F
integer  = "0" | ( "1".."9" ) 0-9*
```

Rules:

- the top level is exactly one object, optionally surrounded by whitespace;
  non-whitespace after it is `sarif: trailing data at byte N`;
- `value` lists the recognized kinds, but the subset has no boolean, null or
  float fields: `true`/`false` are
  `sarif: boolean values are not supported at byte N`, `null` is
  `sarif: null values are not supported at byte N`, and an integer token
  immediately followed by `.`, `e` or `E` is
  `sarif: float values are not supported at byte N`. Literals are matched by
  prefix, so a token that merely starts with `true`, `false` or `null` is
  reported as that literal;
- integers have no sign (`-` is `sarif: negative integers are not supported
  at byte N`), no leading zeros (`0` followed by a digit is
  `sarif: leading zero in integer at byte N`) and must fit in a signed
  64-bit `Int` (`sarif: integer out of range at byte N`);
- strings accept raw printable ASCII (0x20..0x7E except `"` and `\`), the
  basic escapes `\" \\ \/ \b \f \n \r \t`, and `\uXXXX` code points in
  0x20..0x7E only. Raw control bytes, raw non-ASCII bytes, unknown escapes,
  bad hex digits and non-printable `\u` code points are deterministic errors
  (see the catalog);
- object keys are strings; duplicates in the same object are
  `sarif: duplicate key '<key>'`.

## Schema

```
document = object { $schema? version runs }
$schema  = string                          -- optional; kept verbatim
version  = string                          -- required; must equal "2.1.0"
runs     = array of run                    -- required
run      = object { tool results? }
tool     = object { driver }
driver   = object { name }                 -- name: non-empty string
results  = array of result
result   = object { ruleId? level? message locations? }
ruleId   = string                          -- optional, may be empty
level    = "error" | "warning" | "note" | "none"   -- absent means warning
message  = object { text }                 -- text: string, may be empty
locations= array of location
location = object { physicalLocation }
physicalLocation = object { artifactLocation region? }
artifactLocation = object { uri }          -- uri: string, may be empty
region   = object { startLine? startColumn? }      -- positive integers
```

Rules:

- required keys are enforced at the close of their containing object, so a
  missing `version`/`runs`/`tool`/`driver`/`name`/`message`/`text`/
  `physicalLocation`/`artifactLocation`/`uri` reports
  `sarif: missing key '<key>'`; an empty top-level object reports
  `sarif: missing key 'version'` first and `missing key 'runs'` second;
- `tool.driver.name` must additionally be non-empty
  (`sarif: empty tool.driver.name`); all other required strings may be empty;
- keys outside the schema at their level are `sarif: unknown key '<key>'`;
- key order is free: `results` may precede `tool`, `region` may precede
  `artifactLocation`, `startColumn` may precede `startLine`, and so on;
- `startLine` and `startColumn` are independent; each must be a positive
  integer when present (`sarif: startLine must be a positive integer` /
  `sarif: startColumn must be a positive integer`); a region with neither is
  accepted but normalized away by the emitter;
- the version value is validated as soon as it is read, so the first failure
  in document order wins (see below).

## Model

`SarifDoc` is flat; every field is a scalar or a `Vec` of scalars/`Str` (no
`Vec[StructType]`).

| Field | Meaning |
|---|---|
| `schema` | `$schema` value (`""` when absent). |
| `run_driver_names[r]` | `tool.driver.name` of run `r`. |
| `run_result_offsets[r]` | Index of run `r`'s first result; the last entry is a sentinel equal to the total result count (len = runs + 1). |
| `result_runs[i]` | Owning run index of result `i`. |
| `result_rule_ids[i]` | `ruleId` (`""` when absent). |
| `result_levels[i]` | `SARIF_LEVEL_*` code (`SARIF_LEVEL_WARNING` when absent). |
| `result_messages[i]` | `message.text` (may be empty). |
| `result_location_offsets[i]` | Index of result `i`'s first location; the last entry is a sentinel equal to the total location count (len = results + 1). |
| `location_results[k]` | Owning result index of location `k`. |
| `location_uris[k]` | `physicalLocation.artifactLocation.uri` (may be empty). |
| `location_lines[k]` | `physicalLocation.region.startLine` (0 when absent). |
| `location_columns[k]` | `physicalLocation.region.startColumn` (0 when absent). |

Runs, results and locations are appended in document order. The row vectors
of a run (two pushes), a result (five pushes) and a location (four pushes)
always advance together, so the vectors cannot drift during a successful
parse. Accessors nonetheless guard every index and compute counts as the
minimum of the relevant vector lengths (including the range sentinels), so a
hand-built report with drifted vectors stays safe to traverse.

## API semantics

`sarif_parse(text)`
: `Ok(doc)` for a report in the subset. `Err(msg)` for the first malformed
  construct in document order, with `msg` from the catalog below.
  O(n) over the report bytes.

`sarif_emit(d)`
: Canonical compact serialization (rules below). For any doc returned by
  `sarif_parse`, `sarif_parse(sarif_emit(d))` yields an equal model and
  re-emitting yields identical bytes.

`sarif_version()` / `sarif_schema(d)`
: `"2.1.0"` / the `$schema` value (`""` when absent).

`sarif_run_count(d)` / `sarif_run_driver_name(d, r)` /
`sarif_run_result_count(d, r)` / `sarif_run_level_count(d, r, level)`
: Run count; driver name; results owned by run `r`; results of run `r` whose
  level equals `level`. Out-of-range `r` yields `""`/0/0; an unknown `level`
  code counts 0.

`sarif_result_count(d)` / `sarif_result_run(d, i)` /
`sarif_result_rule_id(d, i)` / `sarif_result_level(d, i)` /
`sarif_result_message(d, i)` / `sarif_result_location_count(d, i)`
: Total results; owning run; `ruleId`; `SARIF_LEVEL_*` code; `message.text`;
  owned location count. Out-of-range `i` yields -1 for `sarif_result_run` and
  `sarif_result_level`, 0 for counts, `""` for strings.

`sarif_result_uri(d, i)` / `sarif_result_line(d, i)` /
`sarif_result_column(d, i)`
: First location of result `i`; `""`/0 when the result has no locations or
  `i` is out of range.

`sarif_location_count(d)` / `sarif_location_result(d, i)` /
`sarif_location_uri(d, i)` / `sarif_location_line(d, i)` /
`sarif_location_column(d, i)`
: Total locations; owning result (-1 out of range); uri; startLine;
  startColumn (0 when the region or key is absent).

`sarif_level_count(d, level)` / `sarif_level_name(level)`
: Results with level `level` across all runs (0 for unknown codes);
  `"error"`, `"warning"`, `"note"`, `"none"` or `""`.

## Canonical emission

- compact JSON: no insignificant whitespace, single line, no trailing
  newline;
- fixed key order:
  - document: `$schema` (only when non-empty), `version`, `runs`;
  - run: `tool`, `results` (always written, even when empty);
  - tool: `driver`; driver: `name`;
  - result: `ruleId` (only when non-empty), `level` (always written, from
    the stored code), `message`, `locations` (always written, even when
    empty);
  - message: `text`;
  - location: `physicalLocation`; physicalLocation: `artifactLocation` then
    `region` (only when `startLine` or `startColumn` is > 0); region:
    `startLine` then `startColumn`, each only when > 0;
- `version` is emitted literally as `"2.1.0"`;
- strings are emitted with JSON escapes: `"` as `\"`, `\` as `\\`, and
  bytes 0x08/0x09/0x0A/0x0C/0x0D as `\b`/`\t`/`\n`/`\f`/`\r`; all other
  bytes are copied verbatim (a parsed model only ever contains printable
  ASCII plus those five control bytes). `\/` is decoded to `/` and is not
  re-escaped;
- an empty `ruleId`, an empty `region`, and an absent `region` all normalize
  away; empty `message.text` and empty `uri` are written as `""`;
- a hand-built document whose `level` code is outside 0..3 emits
  `"level":""` (the level name of an unknown code); documents from
  `sarif_parse` always carry a valid code.

Example (source parsed and re-emitted; line breaks added for readability):

```
{"$schema":"https://json.schemastore.org/sarif-2.1.0.json","version":"2.1.0","runs":[
  {"tool":{"driver":{"name":"linter"}},"results":[
    {"ruleId":"X001","level":"error","message":{"text":"unused variable"},
     "locations":[{"physicalLocation":{"artifactLocation":{"uri":"src/a.xi"},
     "region":{"startLine":3,"startColumn":7}}}]},
    {"level":"warning","message":{"text":"note text"},
     "locations":[{"physicalLocation":{"artifactLocation":{"uri":"src/b.xi"}}}]}]},
  {"tool":{"driver":{"name":"audit"}},"results":[]}]}
```

## Error string catalog

All errors are `Err("sarif: ...")`; the first failure in document order wins
(the version value is checked when read; missing-key checks run when the
containing object closes). `N` is always a byte offset into the input `Str`.

| Condition | Error text |
|---|---|
| EOF where a token, key or delimiter is expected | `sarif: unexpected end of input at byte N` (N = input length) |
| String not closed before EOF | `sarif: unterminated string at byte N` (N = opening quote) |
| Raw byte < 0x20 inside a string | `sarif: control character in string at byte N` |
| Raw byte > 0x7E inside a string | `sarif: non-ASCII byte in string at byte N` |
| Backslash followed by an unknown escape character | `sarif: unsupported escape at byte N` (N = the escape character) |
| `\u` escape with a non-hex digit | `sarif: invalid \u escape at byte N` (N = first bad digit) |
| `\u` escape outside 0x20..0x7E | `sarif: non-printable \u escape at byte N` (N = the `u`) |
| Not a quoted string where an object key is expected | `sarif: expected key at byte N` |
| Missing `:` after a key | `sarif: expected ':' at byte N` |
| Object entry not followed by `,` or `}` | `sarif: expected ',' or '}' at byte N` |
| Array entry not followed by `,` or `]` | `sarif: expected ',' or ']' at byte N` |
| Value where a string is required is not a string | `sarif: expected string at byte N` |
| Value where an integer is required is not an integer | `sarif: expected integer at byte N` |
| Value where an object is required is not an object | `sarif: expected object at byte N` |
| Value where an array is required is not an array | `sarif: expected array at byte N` |
| Value starting with `true` or `false` | `sarif: boolean values are not supported at byte N` |
| Value starting with `null` | `sarif: null values are not supported at byte N` |
| Integer token starting with `-` | `sarif: negative integers are not supported at byte N` |
| `0` immediately followed by a digit | `sarif: leading zero in integer at byte N` |
| Integer above INT64_MAX | `sarif: integer out of range at byte N` |
| Integer token followed by `.`, `e` or `E` | `sarif: float values are not supported at byte N` |
| Non-whitespace after the top-level object | `sarif: trailing data at byte N` |
| `version` is a string other than exactly `2.1.0` | `sarif: unsupported version '<v>'` |
| A required key is absent at its level (`version`, `runs`, `tool`, `driver`, `name`, `message`, `text`, `physicalLocation`, `artifactLocation`, `uri`) | `sarif: missing key '<key>'` |
| A key repeats inside one object | `sarif: duplicate key '<key>'` |
| A key outside the subset at its level | `sarif: unknown key '<key>'` |
| `tool.driver.name` is empty | `sarif: empty tool.driver.name` |
| `level` is not one of error/warning/note/none | `sarif: invalid level '<v>'` |
| `startLine` present but not positive | `sarif: startLine must be a positive integer` |
| `startColumn` present but not positive | `sarif: startColumn must be a positive integer` |

Missing-key precedence examples: `{}` reports `missing key 'version'` (then
`runs`); `{"version":"2.1.0","runs":[{}]}` reports `missing key 'tool'`; and
`{"version":"2.1.0","runs":[{"results":[]}]}` reports `missing key 'tool'`
too, while `{"version":"2.1.0","runs":[{"results":[{}]}]}` reports
`missing key 'message'` because the empty result closes (and fails) before
the run object does: the first failure in document order wins.

## Complexity

| Operation | Complexity |
|---|---|
| `sarif_parse` | O(n) over the report bytes |
| `sarif_emit` | O(runs + results + locations + output bytes) |
| `sarif_version` / `sarif_schema` / `sarif_*_count` / scalar accessors | O(1) |
| `sarif_run_level_count` | O(results of the run) |
| `sarif_level_count` | O(results) |

## Test plan

`tests/test_conformance.xi` (`module sarif_tests`, 21 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. full pretty-printed report: schema, two runs, two results with levels,
   messages, locations, range ownership and all counts;
2. empty `runs` and a result-less run; `sarif_version`;
3. result defaults: absent `level` means warning, empty `ruleId`/message
   strings, absent locations;
4. key order and whitespace do not change the model or the emission;
5. string escapes decode (`\" \\ \/ \b \f \n \r \t`, `\uXXXX`) and re-emit
   canonically;
6. canonical emit bytes (fixed key order, level always written, region
   emission);
7. emit normalization: empty `ruleId`, empty region, results-less run,
   `$schema` first;
8. round-trip: `parse -> emit -> parse` preserves the model and the bytes;
9. version errors (`2.0.0`, ``, `2.1`) and missing top-level keys;
10. missing run/tool/driver/name keys and an empty driver name;
11. missing message/text keys;
12. missing location/physicalLocation/artifactLocation/uri keys;
13. unknown keys at every level (document, run, driver, result, message,
    location, physicalLocation, artifactLocation, region);
14. duplicate keys at every level;
15. structural errors with exact byte positions (key, colon, comma,
    unexpected EOF, trailing data);
16. value-kind errors (expected kinds, boolean, null, float, negative,
    leading zero, integer overflow);
17. string errors (unterminated, unsupported escape, invalid/non-printable
    `\u`, control byte, non-ASCII byte);
18. level and region validation (invalid level, boolean level, `startLine` 0,
    `startColumn` 0, boolean region);
19. location ranges: ownership, per-result and first-location accessors,
    round-trip with four locations across three results;
20. out-of-range accessor safety and level name mapping;
21. level summary counts (total and per run) and `$schema` pass-through with
    empty message/uri strings.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.sarif
```

Last verified: compiler 0.61.3,
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Only the documented subset parses; every other SARIF key is a hard error.
  There is no `fixes`/`codeFlows`/`taxonomies`/`invocations`/`rules` support.
- No SARIF JSON schema validation and no semantic validation beyond the
  documented constraints (for example, `ruleId` is not checked against any
  rule index).
- Strings are printable ASCII plus basic escapes; non-ASCII text is
  rejected. `\u` escapes accept only code points 0x20..0x7E.
- Numbers are integers: no floats, exponents or negatives anywhere; the
  subset uses integers only for `startLine`/`startColumn`.
- `true`, `false` and `null` are recognized but rejected at every value
  position.
- Canonical output is a normalized model, not a byte-copy: key order,
  whitespace, `\/`, empty `ruleId` and empty regions are canonicalized.
- Accessor counts for hand-built (not parsed) documents are minimums over
  the relevant vectors, including range sentinels; such documents should
  keep the push groups mirrored.
- `sarif_parse` builds the whole model in memory; no streaming callbacks.

## Compiler / stdlib notes for v0.61.3

- The report is a flat parallel-vector model because `Vec[StructType]` is
  unsupported in this compiler; nesting is parsed with schema-directed
  loops (no recursion, no generic JSON tree).
- `Ok`/`Err` for `Result[SarifDoc, Str]` are constructed only in the leaf
  helpers `_ok_doc`/`_err_doc` (constructing Results elsewhere miscompiles in
  this compiler).
- All Str equality uses `xiom.string.compare.str_compare` (BUG 17: `==` on
  Str values read from `Vec[Str]` elements lowers to a pointer comparison).
  The emitter scans bytes up to the NUL terminator instead of trusting
  `.len()` on such values.
- Widened byte reads are masked (`(b as Int) & 0xFF`) before numeric use.
- Every row push group is mirrored (runs: 2 pushes, results: 5 pushes,
  locations: 4 pushes) so the parallel vectors cannot drift on a successful
  parse; a failed parse returns no model at all.
- The package declares no `extern "C"` blocks (no FFI); output is built with
  `xiom.string.builder` over `Vec[UInt8]` and materialized with `sb_to_str`
  exactly once per emitted report.
