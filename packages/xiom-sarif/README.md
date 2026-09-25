# xiom.sarif

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a SARIF 2.1.0 report codec for a documented JSON subset: parse,
> query and canonical re-emit.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.sarif` parses a practical subset of [SARIF 2.1.0][sarif] static-analysis
reports into a flat, allocation-friendly model and answers structural
questions about it: run counts and driver names, result counts by run and by
level, and per-result `ruleId` / `level` / `message.text` plus the URIs,
start lines and start columns of its locations. `sarif_emit` writes the model
back out in a deterministic, compact canonical form, so `parse -> emit ->
parse` is a byte-stable round-trip.

The codec never touches a C library: scanning is byte-wise over the input
`Str`, decoded strings are assembled with `xiom.string.builder` over
`Vec[UInt8]`, and every public function is a free function.

Parsed reports are *flat*: runs, results and locations live in parallel
vectors (`run_driver_names`, `result_rule_ids`, `result_levels`, ...,
`location_uris`, `location_lines`, ...) plus sentinel-terminated range vectors
(`run_result_offsets`, `result_location_offsets`) instead of nested records.
This is the ecosystem pattern for XIOM v0.61.3, where `Vec[StructType]` is
unsupported.

[sarif]: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html

## Supported subset

- a top-level object with `version` (must be exactly `"2.1.0"`), optional
  `$schema` (kept verbatim and re-emitted) and `runs`;
- per run, a required `tool.driver.name` (non-empty) and optional `results`;
- per result, optional `ruleId`, optional `level` (`error` | `warning` |
  `note` | `none`; an absent level means `warning`, the SARIF default), a
  required `message.text`, and optional `locations`;
- per location, `physicalLocation.artifactLocation.uri` (a string, possibly
  empty) and optional positive-integer `physicalLocation.region.startLine` /
  `startColumn`;
- printable-ASCII strings with the basic escapes (`\" \\ \/ \b \f \n \r \t`)
  and `\uXXXX` for printable-ASCII code points;
- non-negative integers without leading zeros; keys in any order; whitespace
  between tokens.

Everything else -- fixes, codeFlows, taxonomies, invocations, fingerprints,
rule metadata, URI base ids, schema validation, file IO -- is a documented
error or out of scope, never a silent misinterpretation. Unknown keys,
duplicate keys and missing required keys are errors; `true`/`false`/`null`
and floats are recognized and rejected. See `SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `sarif_parse(text)` | `Result[SarifDoc, Str]` | Parse a whole report; `Err("sarif: ...")` on malformed input. |
| `sarif_emit(d)` | `Str` | Canonical compact serialization of a parsed report. |
| `sarif_version()` | `Str` | The accepted version, `"2.1.0"`. |
| `sarif_schema(d)` | `Str` | `$schema` value (`""` when absent). |
| `sarif_run_count(d)` | `Int` | Number of runs. |
| `sarif_run_driver_name(d, r)` | `Str` | `tool.driver.name` of run `r` (`""` out of range). |
| `sarif_run_result_count(d, r)` | `Int` | Results owned by run `r` (0 out of range). |
| `sarif_run_level_count(d, r, level)` | `Int` | Results of run `r` with a `SARIF_LEVEL_*` code (0 out of range). |
| `sarif_result_count(d)` | `Int` | Total number of results. |
| `sarif_result_run(d, i)` | `Int` | Owning run of result `i` (-1 out of range). |
| `sarif_result_rule_id(d, i)` | `Str` | `ruleId` of result `i` (`""` when absent/out of range). |
| `sarif_result_level(d, i)` | `Int` | `SARIF_LEVEL_*` code of result `i` (-1 out of range). |
| `sarif_result_message(d, i)` | `Str` | `message.text` of result `i`. |
| `sarif_result_location_count(d, i)` | `Int` | Locations owned by result `i`. |
| `sarif_result_uri/line/column(d, i)` | `Str`/`Int`/`Int` | First location of result `i` (`""`/0 when it has none). |
| `sarif_location_count(d)` | `Int` | Total number of locations. |
| `sarif_location_result(d, i)` | `Int` | Owning result of location `i` (-1 out of range). |
| `sarif_location_uri(d, i)` | `Str` | `uri` of location `i`. |
| `sarif_location_line/column(d, i)` | `Int`/`Int` | `startLine`/`startColumn` of location `i` (0 when absent). |
| `sarif_level_count(d, level)` | `Int` | Results with a `SARIF_LEVEL_*` code across all runs. |
| `sarif_level_name(level)` | `Str` | `"error"`, `"warning"`, `"note"`, `"none"` or `""`. |

Level codes: `SARIF_LEVEL_ERROR = 0`, `SARIF_LEVEL_WARNING = 1`,
`SARIF_LEVEL_NOTE = 2`, `SARIF_LEVEL_NONE = 3`.

Errors: a single catalog of `Err("sarif: ...")` strings (see SPEC.md); the
most common are `sarif: unsupported version '...'`,
`sarif: unknown key '<name>'`, `sarif: missing key '<name>'` and
`sarif: duplicate key '<name>'`. Byte-level errors carry an exact position
(`sarif: ... at byte N`).

## Usage

```xi
use xiom.sarif;
use xiom.io;

fn main() -> Int {
  let src = "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"linter\"}},\"results\":[{\"ruleId\":\"X001\",\"level\":\"error\",\"message\":{\"text\":\"unused variable\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"src/a.xi\"},\"region\":{\"startLine\":3,\"startColumn\":7}}}]}]}]}";
  let res = sarif_parse(src);
  if !res.is_ok {
    io.println("parse error: " + res.error);
    return 1;
  }
  let d = res.value;
  io.println(sarif_run_driver_name(&d, 0));                 // linter
  io.println(sarif_result_rule_id(&d, 0));                  // X001
  io.println(sarif_level_name(sarif_result_level(&d, 0)));  // error
  io.println(sarif_result_message(&d, 0));                  // unused variable
  io.println(sarif_result_uri(&d, 0));                      // src/a.xi
  io.println(sarif_emit(&d));                               // canonical JSON
  return 0;
}
```

`sarif_emit` produces stable compact output for a given model (fixed key
order, no insignificant whitespace, level always written), so it is suitable
as a serialization baseline in tests.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.sarif
```

Expected: the section-4 namespace check passes, 21 `[PASS]` lines, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Documented subset only.** Real SARIF files carry `fixes`, `codeFlows`,
  `taxonomies`, `invocations`, `fingerprints`, `rules` and many other
  properties; every key outside the subset is
  `Err("sarif: unknown key '<name>'")`. Reduce real-world reports to the
  subset first.
- **No schema validation.** The codec enforces the subset grammar and the
  documented value constraints, not the SARIF JSON schema.
- **No file IO / streaming.** `sarif_parse` consumes a whole `Str`;
  `sarif_emit` returns one `Str`. NUL bytes and invalid UTF-8 are out of
  scope (raw bytes outside printable ASCII are rejected).
- **Strings are ASCII.** Printable ASCII plus the basic escapes and
  `\uXXXX` code points in `0x20..0x7E`; non-ASCII text (for example a
  non-ASCII path) is `Err("sarif: non-ASCII byte in string at byte N")`.
- **Numbers are integers.** `startLine`/`startColumn` must be positive
  integers; floats (`1.5`, `1e5`), negatives, leading zeros and values above
  `INT64_MAX` are deterministic errors. An absent key is 0 and is normalized
  away by the emitter.
- **`true`/`false`/`null` are rejected** wherever a value is expected; the
  subset has no boolean or null fields.
- **Empty strings are kept** for `message.text`, `uri` and `ruleId` on
  parse; an empty `ruleId` is normalized away on emit (it is
  indistinguishable from an absent key).
- **Canonical, not byte-preserving.** Key order, whitespace, `\/` escapes and
  an empty `region` are normalized; round-trips are model round-trips and
  emitted bytes are stable.

See `SPEC.md` for the grammar subset, the full error catalog, the exact
canonical output rules and the test plan. License: MIT OR Apache-2.0 (see the
repository root `LICENSE`).
