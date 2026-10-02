# xiom.linter

Line-oriented lint engine for source text: a rule registry, a parallel-Vec
diagnostic bag, six built-in rules, a strict `key = value` configuration, and
two deterministic report formats.

> **Status:** `incubating` -- conformance-tested (26/26); published at `v0.1.1` on the XIOM registry.

Module: `xiom.linter` (`src/linter.xi`). Pure XIOM: no FFI, no file I/O, no
clock access, no global state. The input is a source `Str` and the output is a
`DiagnosticBag`; callers read files themselves.

## Scope

This is a **line-oriented engine, not a parser**: it classifies lines by bytes
(trailing whitespace, indentation, length, markers, line terminators) and
cannot enforce syntax or semantics. Lines and columns are 1-based **byte**
positions; non-ASCII text is counted in bytes.

## Usage

```xi
use xiom.linter;

let source = source_text_from_anywhere();   // caller-provided Str
let config = "line_length_max = 100\nrule.todo_marker.enabled = false\n";

let bag = lint_run(source, config);
io.println(linter_report_text(&bag));   // human report
io.println(linter_report_csv(&bag));    // machine report
```

Individual rules, the registry, the bag and the config are all public; see
`SPEC.md` for the exact formats, the config grammar and the error catalog.

## Built-in rules

| Rule id | Default severity | Fires on |
|---|---|---|
| `trailing_whitespace` | warning | line ends with space or tab |
| `tab_indent` | warning | tab inside the leading whitespace run |
| `line_length` | warning | line longer than `line_length_max` (default 80) |
| `todo_marker` | info | exact upper-case `TODO` or `FIXME` |
| `mixed_line_endings` | warning | LF, CRLF and CR mixed in one file |
| `missing_final_newline` | warning | non-empty source not ending in LF/CR |

## API (summary)

| Group | Functions |
|---|---|
| Convenience | `lint_run(source, config)` |
| Registry | `linter_registry_new`, `linter_registry_default`, `linter_register`, `linter_rule_count`, `linter_rule_index`, `linter_rule_id`, `linter_rule_severity`, `linter_rule_severity_at`, `linter_rule_enabled`, `linter_rule_enabled_at`, `linter_enable`, `linter_disable` |
| Diagnostic bag | `linter_bag_new`, `linter_bag_add`, `linter_bag_count`, `linter_bag_get`, `linter_bag_severity`, `linter_bag_rule`, `linter_bag_line`, `linter_bag_column`, `linter_bag_message`, `linter_bag_filter_severity`, `linter_bag_sort_by_line`, `linter_bag_merge`, `linter_severity_name` |
| Rules | `lint_trailing_whitespace`, `lint_tab_indent`, `lint_line_length`, `lint_todo_markers`, `lint_mixed_line_endings`, `lint_missing_final_newline` |
| Config | `linter_config_new`, `linter_config_parse`, `linter_config_count`, `linter_config_key`, `linter_config_value`, `linter_config_get`, `linter_config_set`, `linter_config_line_length`, `linter_registry_from_config` |
| Reports | `linter_report_text`, `linter_report_csv` |
| Misc | `linter_scan`, `linter_default_line_length`, `linter_version` |

## Report formats

- Text: one line per diagnostic, `<line>:<col>: <severity> <rule>: <message>`,
  LF-joined, no trailing newline; an empty bag renders as `""`.
  Example: `3:12: warning trailing_whitespace: trailing whitespace`.
- CSV-like: one line per diagnostic,
  `<severity-number>,<rule>,<line>,<column>,<message>`, LF-joined, no
  trailing newline; a field containing `,`, `"`, CR or LF is double-quoted
  with inner quotes doubled; an empty bag renders as `""`.

Both are deterministic; `SPEC.md` states them byte-exactly.

## Limitations

- Line-oriented, not a parser; byte columns; markers are ASCII-only.
- No automatic fixes and no inline suppression comments.
- `lint_run` runs only the six built-in rules. Custom rules can be registered
  and driven manually through the bag API, but `lint_run` ignores them.
- The config is strict: unknown keys and bad values are errors. `lint_run`
  fails closed on a config error (one `config` diagnostic; the source is not
  linted).
- `line_length_max` accepts 1..1000000.
- Not thread-safe (no global state; every call is self-contained).

## Tests

`tests/test_conformance.xi` -- 26 named checks, fixtures built in-test (no
files, no I/O). Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.linter
```
