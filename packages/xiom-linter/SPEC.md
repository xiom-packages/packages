# xiom.linter -- Specification

Status: `incubating` (implemented, harness-green on compiler 0.62.1, not
published).
Module: `xiom.linter` (`src/linter.xi`). Manifest: `package.xi` (name
`xiom.linter`, version `0.1.0`). Depends on `xiom.std` for the manifest; the
library imports `xiom.string` and `xiom.convert` and uses no other module.

## Scope

A self-contained, line-oriented lint engine over an in-memory `Str`:

- a rule registry (id + severity + enabled, in parallel Vec fields) with
  registration, lookup and enable/disable;
- a `Diagnostic` value and a `DiagnosticBag` (five parallel Vec fields) with
  add, access, filter-by-severity, stable sort-by-line and merge;
- six built-in line-oriented rules producing diagnostics;
- a strict `key = value` settings document parsed into parallel Vec fields,
  overriding the defaults (rule toggles by id; configurable line length);
- two deterministic report formats: human text and CSV-like;
- `lint_run(source, config)`, the one-call convenience.

Pure and deterministic: no FFI, no file I/O, no clock access, no global
state, no allocation beyond the Vecs involved.

## Non-goals

- Parsing or tokenizing: the engine never understands the language of the
  source; it classifies lines by bytes.
- Automatic fixes, inline suppression comments, severity escalation policies,
  baseline/allowlist files.
- A general rule-engine plugin ABI: custom rules are registry entries driven
  by the caller; `lint_run` runs only the six built-ins.
- Unicode-aware columns: everything is bytes (see "Known limitations").
- Reading files or writing reports: the caller owns all I/O.

## Diagnostic model

- Severity codes are Ints: `0` = info, `1` = warning, `2` = error. Any other
  value is rendered as `unknown` by `linter_severity_name` and by the text
  report; the CSV report always prints the raw number.
- A `Diagnostic` is the value
  `{ severity: Int; rule: Str; line: Int; column: Int; message: Str; }`.
- Lines are 1-based. Columns are 1-based byte offsets within the line.
  Config-error diagnostics use line 0, column 0 with rule id `config`.
- `DiagnosticBag` stores N diagnostics in five mirrored Vec fields:
  `severities`, `rules`, `lines`, `cols`, `messages`, index-aligned.
  `linter_bag_add` pushes all five; every mutator keeps the mirror invariant.
- Accessors are range-safe: `linter_bag_count` O(1); the scalar accessors
  return -1 (severity), 0 (line, column) or "" (rule, message) out of range;
  `linter_bag_get` returns a zero diagnostic (severity 0, empty rule and
  message, line 0, column 0).

## Data model

```xi
pub type RuleRegistry = { ids: Vec[Str]; severities: Vec[Int]; enabled: Vec[Int]; }
pub type Diagnostic = { severity: Int; rule: Str; line: Int; column: Int; message: Str; }
pub type DiagnosticBag = {
  severities: Vec[Int]; rules: Vec[Str]; lines: Vec[Int];
  cols: Vec[Int]; messages: Vec[Str];
}
pub type LintConfig = { keys: Vec[Str]; values: Vec[Str]; }
pub type LintSource = { lines: Vec[Str]; eols: Vec[Int]; }
```

`enabled[i]` is `1` when the rule is enabled and `0` otherwise. `LintSource`
is the internal line model exposed for advanced callers: `lines[i]` is line
`i+1` without its terminator, `eols[i]` is its terminator code
(0 = none, 1 = LF, 2 = CRLF, 3 = CR). A trailing terminator does not create
an extra empty line; a final unterminated line appears with code 0.

## Rule registry

- `linter_registry_new()` returns an empty registry.
- `linter_register(reg, id, severity, enabled)` rejects, in this order:
  empty id (`linter: rule id must not be empty`), severity outside 0..2
  (`linter: severity must be 0, 1 or 2`), duplicate id
  (`linter: duplicate rule id: <id>`). On success it appends and returns
  `Ok(index)`. Nothing is appended on error.
- `linter_rule_index` returns the index or -1; `linter_rule_severity` returns
  the severity or -1; `linter_rule_enabled` is true only for a registered,
  enabled rule; `linter_rule_id`, `linter_rule_severity_at` and
  `linter_rule_enabled_at` are index accessors with -1/""/false out of range.
- `linter_enable` / `linter_disable` return `Ok(index)` or
  `Err("linter: unknown rule id: <id>")`.

### Default registry

`linter_registry_default()` registers, in order:

| Index | Rule id | Severity | Enabled |
|---|---|---|---|
| 0 | `trailing_whitespace` | warning (1) | yes |
| 1 | `tab_indent` | warning (1) | yes |
| 2 | `line_length` | warning (1) | yes |
| 3 | `todo_marker` | info (0) | yes |
| 4 | `mixed_line_endings` | warning (1) | yes |
| 5 | `missing_final_newline` | warning (1) | yes |

## Built-in rule definitions

All six rules operate on the `LintSource` line model. Each public per-rule
function (`lint_trailing_whitespace`, `lint_tab_indent`,
`lint_line_length`, `lint_todo_markers`, `lint_mixed_line_endings`,
`lint_missing_final_newline`) scans the source itself and returns a bag with
the default severity shown above.

### trailing_whitespace (warning)

One diagnostic per line whose last byte is space (0x20) or tab (0x09), at the
column of the first byte of the trailing run of spaces/tabs; message exactly
`trailing whitespace`. An all-whitespace line is flagged at column 1. A line
ending in any other byte (including CR/LF, which never belong to the line
content) is clean.

### tab_indent (warning)

One diagnostic per line whose leading run of spaces/tabs contains a tab, at
the column of the first tab; message exactly `tab indentation`. The leading
run is every byte before the first byte that is neither space nor tab; for an
all-whitespace line it is the whole line. A tab after the first non-whitespace
byte is never flagged.

### line_length (warning)

One diagnostic per line whose content length (excluding the terminator)
exceeds the limit, at column `limit + 1`; message exactly
`line length <n> exceeds <limit>` with decimal integers. `limit < 1` makes
the per-rule function return an empty bag; `lint_run` always passes a limit
>= 1 (see "Config").

### todo_marker (info)

Scans each line left to right for the exact, case-sensitive needles `TODO`
(4 bytes) and `FIXME` (5 bytes); at each byte position `TODO` is tested
before `FIXME`. One diagnostic per **non-overlapping** occurrence at the
occurrence's first byte, with message exactly `TODO marker` or
`FIXME marker`. `TODOTODO` therefore yields two diagnostics (columns 1 and
5); lower-case `todo`/`fixme` never match.

### mixed_line_endings (warning)

Among the actual terminators (LF, CRLF, CR), the first one defines the
baseline. One diagnostic at column 1 of the first later line whose terminator
code differs from the baseline; message exactly `mixed line endings`. At most
one diagnostic per source. Files with zero or one terminator kind produce
none, and a missing final terminator is not a terminator (that case belongs
to `missing_final_newline`).

### missing_final_newline (warning)

For a non-empty source whose final line was not terminated (last byte is
neither LF nor CR): one diagnostic at the last line, column
`last_line_length + 1`, message exactly `missing final newline`. An empty
source is clean. A source ending in LF or a lone CR counts as terminated.

### lint_run rule order

`lint_run` appends rules in this fixed order, so the bag order is
deterministic: `trailing_whitespace`, `tab_indent`, `line_length`,
`todo_marker`, `mixed_line_endings`, `missing_final_newline`. Use
`linter_bag_sort_by_line` (stable, line key only) for line-ordered output.

## Config grammar

```
document = line*
line     = ws* ( "" | comment | setting ) ws* ( LF | CRLF | CR | EOF )
comment  = ( "#" | ";" ) bytes*
setting  = key ws* "=" ws* value
key      = "line_length_max"
         | "rule." id ".enabled"          ; id non-empty
value(line_length_max)          = decimal digits, numeric value 1..1000000
value(rule.<id>.enabled)        = "true" | "false" | "1" | "0" | "yes" | "no"
ws       = space | tab
```

- Blank lines and lines whose first non-whitespace byte is `#` or `;` are
  skipped.
- Keys and values are trimmed of surrounding spaces/tabs; whitespace around
  `=` is insignificant. The first `=` on a line separates key and value.
- Boolean values are exact lower-case; `TRUE`, `Yes` etc. are errors.
- Duplicate keys are accepted: the key keeps its first position and the last
  value wins.
- Parse-time validation rejects malformed lines, empty keys, unknown key
  shapes, and invalid values with a `linter: config line <n>: ...` message
  (`<n>` is the 1-based line of the *config* document).
- Cross-reference validation (does `rule.<id>` name a built-in?) happens when
  the config is applied: `linter_registry_from_config` or `_config_error`
  inside `lint_run`, with a `linter: config: ...` message.

## lint_run semantics

`lint_run(source, config)`:

1. Parse `config` with `linter_config_parse`. On Err: return a bag with
   exactly one diagnostic (severity error, rule id `config`, line 0,
   column 0, message = the error text). The source is **not** linted
   (fail closed).
2. Validate the parsed config against the built-in rule ids and value ranges.
   On error: same single `config` diagnostic and fail closed.
3. Build the effective registry: `linter_registry_default()` with every
   `rule.<id>.enabled` override applied (severities stay at their defaults).
4. Effective line length: the parsed `line_length_max` value, or 80
   (`linter_default_line_length()`) when the key is absent.
5. Run every enabled rule in the fixed order above, taking each rule's
   severity from the effective registry, and return the combined bag.

`lint_run(source, "")` therefore lints with all six built-in rules, limit 80.

## Report formats

Both reporters consume a bag in its stored order and are byte-exact.

### Text report (`linter_report_text`)

- One line per diagnostic: `<line>:<col>: <severity> <rule>: <message>`,
  where `<severity>` is the `linter_severity_name` word
  (`info` / `warning` / `error` / `unknown`).
- Lines joined with a single LF; no trailing newline.
- An empty bag renders as the empty string `""`.
- Example: `3:12: warning trailing_whitespace: trailing whitespace`.

### CSV-like report (`linter_report_csv`)

- One line per diagnostic:
  `<severity-number>,<rule>,<line>,<column>,<message>`, the severity being
  the raw integer (0/1/2, unquoted).
- Lines joined with a single LF; no trailing newline; empty bag renders `""`.
- Field quoting (RFC-4180 style, applied to `rule` and `message` only): a
  field containing a comma, a double quote, LF or CR is wrapped in double
  quotes and each inner quote is doubled. Example field input
  `bad, value with "quotes"` becomes
  `"bad, value with ""quotes"""`.
- Example line: `1,trailing_whitespace,3,12,trailing whitespace`.

## API signatures

```xi
pub type RuleRegistry = { ids: Vec[Str]; severities: Vec[Int]; enabled: Vec[Int]; }
pub type Diagnostic = { severity: Int; rule: Str; line: Int; column: Int; message: Str; }
pub type DiagnosticBag = {
  severities: Vec[Int]; rules: Vec[Str]; lines: Vec[Int];
  cols: Vec[Int]; messages: Vec[Str];
}
pub type LintConfig = { keys: Vec[Str]; values: Vec[Str]; }
pub type LintSource = { lines: Vec[Str]; eols: Vec[Int]; }

pub fn linter_registry_new() -> RuleRegistry
pub fn linter_registry_default() -> RuleRegistry
pub fn linter_register(reg: &mut RuleRegistry, id: Str, severity: Int, enabled: Bool) -> Result[Int, Str]
pub fn linter_rule_count(reg: &RuleRegistry) -> Int
pub fn linter_rule_index(reg: &RuleRegistry, id: Str) -> Int
pub fn linter_rule_id(reg: &RuleRegistry, i: Int) -> Str
pub fn linter_rule_severity_at(reg: &RuleRegistry, i: Int) -> Int
pub fn linter_rule_enabled_at(reg: &RuleRegistry, i: Int) -> Bool
pub fn linter_rule_severity(reg: &RuleRegistry, id: Str) -> Int
pub fn linter_rule_enabled(reg: &RuleRegistry, id: Str) -> Bool
pub fn linter_enable(reg: &mut RuleRegistry, id: Str) -> Result[Int, Str]
pub fn linter_disable(reg: &mut RuleRegistry, id: Str) -> Result[Int, Str]

pub fn linter_bag_new() -> DiagnosticBag
pub fn linter_bag_add(bag: &mut DiagnosticBag, severity: Int, rule: Str, line: Int, column: Int, message: Str)
pub fn linter_bag_count(bag: &DiagnosticBag) -> Int
pub fn linter_bag_severity(bag: &DiagnosticBag, i: Int) -> Int
pub fn linter_bag_rule(bag: &DiagnosticBag, i: Int) -> Str
pub fn linter_bag_line(bag: &DiagnosticBag, i: Int) -> Int
pub fn linter_bag_column(bag: &DiagnosticBag, i: Int) -> Int
pub fn linter_bag_message(bag: &DiagnosticBag, i: Int) -> Str
pub fn linter_bag_get(bag: &DiagnosticBag, i: Int) -> Diagnostic
pub fn linter_bag_filter_severity(bag: &DiagnosticBag, severity: Int) -> DiagnosticBag
pub fn linter_bag_sort_by_line(bag: &mut DiagnosticBag)
pub fn linter_bag_merge(dst: &mut DiagnosticBag, src: &DiagnosticBag)
pub fn linter_severity_name(severity: Int) -> Str

pub fn lint_trailing_whitespace(source: Str) -> DiagnosticBag
pub fn lint_tab_indent(source: Str) -> DiagnosticBag
pub fn lint_line_length(source: Str, limit: Int) -> DiagnosticBag
pub fn lint_todo_markers(source: Str) -> DiagnosticBag
pub fn lint_mixed_line_endings(source: Str) -> DiagnosticBag
pub fn lint_missing_final_newline(source: Str) -> DiagnosticBag
pub fn linter_default_line_length() -> Int
pub fn linter_version() -> Str

pub fn linter_config_new() -> LintConfig
pub fn linter_config_parse(text: Str) -> Result[LintConfig, Str]
pub fn linter_config_count(cfg: &LintConfig) -> Int
pub fn linter_config_key(cfg: &LintConfig, i: Int) -> Str
pub fn linter_config_value(cfg: &LintConfig, i: Int) -> Str
pub fn linter_config_get(cfg: &LintConfig, key: Str) -> Option[Str]
pub fn linter_config_set(cfg: &mut LintConfig, key: Str, value: Str)
pub fn linter_config_line_length(cfg: &LintConfig) -> Result[Int, Str]
pub fn linter_registry_from_config(cfg: &LintConfig) -> Result[RuleRegistry, Str]
pub fn linter_scan(source: Str) -> LintSource

pub fn lint_run(source: Str, config: Str) -> DiagnosticBag
pub fn linter_report_text(bag: &DiagnosticBag) -> Str
pub fn linter_report_csv(bag: &DiagnosticBag) -> Str
```

## Error catalog

Every `Err` payload starts with `linter: `. Registry errors are exact per the
table; config-parse errors embed the 1-based config line number.

| Message | Raised by | Condition |
|---|---|---|
| `linter: rule id must not be empty` | `linter_register` | `id.len() == 0` |
| `linter: severity must be 0, 1 or 2` | `linter_register` | severity outside 0..2 |
| `linter: duplicate rule id: <id>` | `linter_register` | id already present |
| `linter: unknown rule id: <id>` | `linter_enable`, `linter_disable` | id absent |
| `linter: config line <n>: expected key = value` | `linter_config_parse` | no `=` on the line |
| `linter: config line <n>: empty key` | `linter_config_parse` | empty key before `=` |
| `linter: config line <n>: unknown key: <key>` | `linter_config_parse` | key matches no grammar form |
| `linter: config line <n>: line_length_max must be a positive integer: <value>` | `linter_config_parse` | value not digits 1..1000000 |
| `linter: config line <n>: enabled must be true, false, 1, 0, yes or no: <value>` | `linter_config_parse` | boolean not one of the six spellings |
| `linter: config: unknown rule id: <id>` | `linter_registry_from_config` | `rule.<id>.enabled` for a non-built-in id |
| `linter: config: unknown key: <key>` | `linter_registry_from_config` | hand-built key outside the grammar |
| `linter: config: line_length_max must be a positive integer: <value>` | `linter_registry_from_config`, `linter_config_line_length` | invalid value in a hand-built config |
| `linter: config: enabled must be true, false, 1, 0, yes or no: <value>` | `linter_registry_from_config` | invalid boolean in a hand-built config |

`lint_run` converts whichever config error occurs into one diagnostic with
rule id `config`, severity error, line 0, column 0 and the exact message
above; the source is not linted.

## Complexity

| Operation | Complexity |
|---|---|
| `linter_scan` | O(source length) |
| each `lint_*` rule | O(source length) (todo marker: O(source length * needle length)) |
| `lint_run` | O(config length + source length) |
| `linter_register` / `linter_rule_index` / enable / disable | O(rules * id length) |
| `linter_bag_add`, bag accessors | O(1) |
| `linter_bag_filter_severity`, `linter_bag_merge` | O(bag size) |
| `linter_bag_sort_by_line` | O(n) best case, O(n^2) worst case (insertion sort) |
| `linter_report_text`, `linter_report_csv` | O(total output length) |

## Test plan

`tests/test_conformance.xi` (`module linter_tests`, 26 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test (no files, no
I/O); all Str equality goes through `xiom.string.compare.str_compare`:

1. default registry has the six built-in rules (ids, severities, flags);
2. register accepts one rule and rejects duplicates (empty id, bad severity);
3. id lookup and out-of-range accessors;
4. enable and disable toggle rules by id (unknown-id errors);
5. bag add, count and accessors stay aligned (get + zero diagnostic);
6. filter keeps only the requested severity (order preserved);
7. merge appends every diagnostic in order;
8. sort_by_line is stable and keeps fields aligned;
9. trailing whitespace hit, miss and blank line (columns exact);
10. tab indentation flags leading tabs only;
11. line length hit, exact fit and non-positive limit;
12. TODO and FIXME markers are found exactly (case, columns, overlap);
13. mixed line endings detected at the first divergence (LF/CRLF/CR);
14. missing final newline edge cases (LF, CR, empty, unterminated);
15. scan keeps line content and terminator codes (LF/CRLF/CR/none);
16. config parse reads key = value settings (comments, blanks, get);
17. config defaults, last-wins and setter validation;
18. config parse errors are exact and line-numbered (9 cases);
19. registry_from_config applies overrides and rejects bad ids/keys/values;
20. lint_run honors rule toggles;
21. lint_run applies the configurable line length limit (default 80 too);
22. lint_run fails closed on config errors (single `config` diagnostic);
23. text report is byte-exact;
24. csv report is byte-exact and quotes fields;
25. lint_run end-to-end with sort and filter (5 diagnostics, 4 warnings);
26. version marker and severity names.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.linter
```

Last verified: compiler 0.62.1, `port: PASS (passed=26 failed=0
program_exit=0 exit=0)`, run twice for stability.

## Known limitations

- Line-oriented: no tokenizing/parsing, no syntax or semantic checks.
- Byte model: lines and columns count bytes; multi-byte UTF-8 characters
  count as several columns. The marker scan is case-sensitive ASCII only.
- `Vec[StructType]` is unsupported on the pinned compiler, so every list is
  a struct of parallel Vecs; the mirror invariant is the caller's
  responsibility when mutating the public fields directly.
- `lint_run` runs only the six built-ins; there is no config-key extension
  for third-party rules.
- `line_length_max` is capped at 1000000 (parser cap).
- `linter_bag_sort_by_line` is an insertion sort: fine for lint-sized bags,
  O(n^2) for very large ones.
- No suppression comments, no autofix, no severity overrides from config
  (severities are registry-level; the default registry's values are fixed
  unless a caller mutates the registry itself).
- Not thread-safe; no global state.

## Compiler notes (pinned v0.62.1)

- Free functions only (no methods, no lambdas, no `Vec[fn]` dispatch).
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_int`/`_err_int`,
  `_ok_registry`/`_err_registry`, `_ok_config`/`_err_config` (trap 6).
- Str equality goes through `xiom.string.str_compare` (trap 1); the module
  performs no `==` on Str values read from `Vec[Str]`.
- Every Vec element read is bound to a typed local (trap 2); byte reads that
  are widened for comparison use the `as Int` + `& 0xFF` path (trap 3), and
  all inline byte constants are < 128.
- Parallel Vecs are pushed/merged in mirrored fashion (trap 16).
- No `Vec[Float64]`, no FFI, no file I/O, no function named `log`;
  `int_to_base` is not used (integers are formatted with
  `xiom.convert.int_to_string`).
- Bracket canonicalization: a post-write grep for malformed angle-bracket
  `Vec`/`Result` forms is part of the porting loop (trap 14).
