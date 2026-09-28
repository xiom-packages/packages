# xiom.monitoring -- specification

Prometheus / OpenMetrics text exposition format parser, implemented in pure
XIOM (no FFI). This document describes the grammar and the error catalog that
the implementation in `src/monitoring.xi` actually enforces.

- package: `xiom.monitoring` 0.1.0
- module: `xiom.monitoring`
- entry points: `mon_parse` (strict), `mon_parse_lenient` (error-collecting),
  `mon_parse_line` (single line), `mon_parse_value` / `mon_parse_float`
  (single value)

## 1. Scope

In scope:

- The Prometheus text exposition format (`text/plain; version=0.0.4`) and
  the OpenMetrics text format (`application/openmetrics-text`).
- Line-oriented parsing only: directives, samples, labels, values,
  timestamps, exemplars, histogram/summary grouping.
- Byte-exact spans (offsets and raw text) for every parsed element.
- Two value representations: exact integer mantissa + base-10 exponent
  (scaled to micro-units on demand) and a scalar Float64 helper.

Out of scope (non-goals):

- HTTP transport, scraping, push, service discovery.
- The protobuf exposition format.
- Rendering/serializing metrics.
- Timestamp timezone conversion (timestamps are plain int64 milliseconds).
- UTF-8 validation of label values and HELP text (bytes are preserved).
- Cumulative-bucket-count monotonicity, presence of a `+Inf` bucket,
  summary quantile ordering, and `__name__` label rejection are NOT checked
  (see section 7).

## 2. Lexical layer

- Lines end with `LF`; a single trailing `CR` is stripped (`CRLF` input is
  accepted). The last line needs no terminator.
- Horizontal whitespace is space (`0x20`) or tab (`0x09`).
- A line is *blank* when it is empty or only whitespace; blank lines are
  ignored. A trailing line break does not create an extra line.
- A non-blank line whose first byte is `#` is a directive/comment line; any
  other non-blank line is a sample line.
- Offsets in errors are byte offsets into the parsed input (absolute for
  document parses, line-relative for `mon_parse_line`).

## 3. Grammar

```
document   = { line }
line       = blank | comment | directive | sample
blank      = ws*
comment    = "#" { not-directive }          ; any unknown "# ..." line
directive  = "#" ws+ "HELP" ws+ name [ ws+ text ]
           | "#" ws+ "TYPE" ws+ name ws+ type
           | "#" ws+ "UNIT" ws+ name ws+ unit
           | "#" ws+ "EOF"
type       = "counter" | "gauge" | "histogram" | "summary"
           | "untyped" | "info" | "stateset" | "gaugehistogram"
name       = metric-name
unit       = 1*( any byte except space/tab )        ; non-empty, one word
text       = { any byte }                            ; escaped: \\ \n

metric-name = ( ALPHA | "_" | ":" ) { ALPHA | DIGIT | "_" | ":" }
label-name  = ( ALPHA | "_" ) { ALPHA | DIGIT | "_" }

sample     = metric-name [ "{" label { "," label } "}" ] ws+ value
             [ ws+ timestamp ] [ ws+ exemplar ] ws*
label      = ws* label-name ws* "=" ws* DQUOTE label-value DQUOTE
label-value= { any byte except DQUOTE and unescaped backslash
               and ( \\ | \" | \n ) }                ; escapes decoded

value      = "+Inf" | "-Inf" | "Inf" | "NaN"        ; case-sensitive
           | [ "+" | "-" ] number
number     = digits [ "." digits* ] [ ( "e" | "E" ) [ "+" | "-" ] digits ]
           | "." digits [ ( "e" | "E" ) [ "+" | "-" ] digits ]

timestamp  = [ "+" | "-" ] digits [ "." digits* ]   ; no exponent

exemplar   = "#" ws* "{" [ label { "," label } ] "}" ws+ value
             [ ws+ timestamp ]
```

Notes on the grammar as implemented:

- `ws+` before the value of a sample is required (`m{}5` is `missing value`).
- Trailing whitespace at the end of any line is allowed.
- Whitespace inside the braces is allowed (`{ le = "1" }` parses).
- `# HELP <name>` with no text is accepted and yields empty HELP text.
- `# HELP`, `# TYPE`, `# UNIT`, `# EOF` keywords are case-sensitive; any
  other `# ...` line is a comment.
- `# EOF` accepts no token after it.
- Values: at most 18 significant digits are accumulated; extra nonzero
  digits set the `over` flag (the stored mantissa/exponent pair truncates to
  the digits actually consumed). Exponent magnitude is capped at 1e6 and
  flags `over` when larger.
- `Inf` (bare) is accepted as an extension of the listed `+Inf`/`-Inf`;
  `nan`, `NAN`, `INF` are rejected.
- Label values and HELP text support exactly the escapes `\\`, `\"`, `\n`;
  any other backslash sequence is an error.
- A label set must contain at least one label (`{}` is rejected); an
  exemplar label set may be empty.

## 4. Values and precision

A parsed finite value is stored as `mant * 10^exp` (signed Int mantissa,
Int exponent) plus a kind code:

| kind | meaning |
|------|---------|
| 0    | finite  |
| 1    | +Inf    |
| 2    | -Inf    |
| 3    | NaN     |

- `mon_*_value_micro` scales the finite value to integer micro-units
  (1e-6): `trunc(mant * 10^(exp + 6))`, truncating toward zero and
  saturating at `+/-9223372036854775807`. Values below one micro-unit
  truncate to 0 (e.g. `1e-7` -> 0); NaN and infinities return 0 and must be
  distinguished via the kind.
- `mon_*_value_float` returns a scalar `Float64` computed from `mant` and
  `exp` (IEEE specials for kinds 1/2/3). `Vec[Float64]` is not used anywhere
  in this package.
- `over` reports precision loss (more than 18 significant digits or an
  exponent above 1e6); parsing still succeeds.
- Timestamps are int64 milliseconds; a fractional part is truncated toward
  zero. Integers that overflow int64 are rejected.

## 5. Families, parts and grouping

Families are keyed by metric name (case-sensitive). A family is created by
the first `# HELP`/`# TYPE`/`# UNIT` naming it, or by a sample whose name is
not captured by an existing family.

Sample `part` codes:

| part | name pattern | meaning |
|------|--------------|---------|
| 0    | any          | plain sample |
| 1    | `<base>_bucket`   | histogram bucket |
| 2    | `<base>_sum`      | histogram/summary sum |
| 3    | `<base>_count`    | histogram/summary count |
| 4    | `<base>_created`  | created timestamp (plain sample, no semantics) |
| 5    | name with `quantile` label | summary quantile |

Resolution order for a sample name `n`:

1. exact family `n` if it exists (this covers counters such as `x_total`,
   summary base samples `x{quantile=...}`, and any undeclared name);
2. for parts 1-4, the family named by the stripped base (`h` for
   `h_bucket`, `s` for `s_sum`) if it exists;
3. otherwise a new undeclared family is created under `n` itself.

Consequences (documented behavior):

- Declarations must precede the samples they describe. A `# TYPE x
  histogram` line placed after its `x_bucket` samples does not retroactively
  re-group them (the later samples still group under `x`; the earlier ones
  stay under `x_bucket`).
- The exact name always wins: a family literally declared as `x_bucket`
  captures `x_bucket` samples even if `x` is declared histogram.
- A later `# HELP`/`# UNIT` for the same name replaces the earlier one; a
  second `# TYPE` for the same name is an error.
- `x_created` samples are attached with part 4 and are otherwise treated as
  plain samples.

## 6. Histogram and summary rules

For samples whose resolved family has TYPE `histogram`:

- a `_bucket` sample must carry an `le` label (`bucket without le`);
- a plain sample of the family (`x` itself) is rejected
  (`unexpected histogram sample`);
- `le` must parse as a finite value or exactly `+Inf`
  (`bad le` for `abc`, `NaN`, `-Inf`);
- the `le` boundaries of a family must be strictly increasing in sample
  order. Boundaries are compared in micro-units, so two le values that
  differ only below 1e-6 compare equal and are rejected as duplicates.
  `+Inf` must be last. Violations are `duplicate bucket le` (equal) or
  `bucket le out of order` (regression or a bucket after `+Inf`).
  The check applies to any `_bucket` sample that carries `le`, even when
  the family has no declared TYPE.

For samples whose resolved family has TYPE `summary`:

- a plain sample without a `quantile` label is rejected
  (`summary sample without quantile`);
- a quantile label value must parse as a finite value within `[0, 1]`
  (`bad quantile` otherwise), and is exposed in micro-units
  (0..1000000).

## 7. Explicitly not checked

- Cumulative bucket counts are not compared for monotonicity.
- The presence of an `+Inf` bucket is not required.
- Summary quantiles are not required to be sorted (the `le` ordering rule
  applies to histogram buckets only).
- Label names are not compared against any reserved set (`__name__` etc.).
- Unit text is any non-empty single word; no unit vocabulary is enforced.
- HELP text and label values are not validated as UTF-8.

## 8. EOF semantics

- `# EOF` is accepted anywhere; the first one sets `eof_seen`.
- After EOF, any non-blank line is an error: a second EOF is
  `duplicate EOF`, anything else is `line after EOF` or `sample after EOF`
  (sample lines). Blank lines after EOF are allowed.
- A malformed EOF (`# EOF x`) is a `bad EOF` error and does not set the
  marker.

## 9. Error catalog

Every error is the string

```
monitoring: <reason> at <byte offset>
```

`mon_parse` returns the first error; `mon_parse_lenient` collects all of them
in `err_msgs` / `err_lines` / `err_ats` and keeps parsing (invalid directives
and invalid samples are skipped, valid ones are kept). `mon_parse_line`
returns a single error with a line-relative offset.

| reason | meaning |
|--------|---------|
| `bad metric name` | sample/directive name missing or first byte invalid |
| `bad label name` | label name missing or first byte invalid |
| `bad label` | expected `=`, `,`, or `}` at the reported offset |
| `bad label quote` | expected `"` after `=` |
| `unterminated label value` | no closing `"` before end of line |
| `empty label set` | `{}` in a sample |
| `duplicate label` | repeated label name in one label set |
| `bad escape` | backslash escape other than `\\`, `\"`, `\n` |
| `missing value` | no value token after the name/label set |
| `bad value` | value token violates the value grammar |
| `bad timestamp` | timestamp token is not integer/decimal ms |
| `timestamp out of range` | timestamp does not fit int64 |
| `bad exemplar` | malformed `# { ... }` skeleton |
| `bad exemplar value` | exemplar value token violates the value grammar |
| `trailing garbage` | extra token after value/timestamp/exemplar |
| `missing metric name` | `# HELP`/`TYPE`/`UNIT` without a valid name |
| `bad type` | TYPE word not in the catalog or extra token after it |
| `duplicate TYPE for "<name>"` | a second TYPE for the same family |
| `invalid escape in HELP` | backslash escape other than `\\`, `\n` |
| `bad unit` | UNIT missing/empty or extra token after it |
| `bad EOF` | token after `# EOF` |
| `duplicate EOF` | second `# EOF` line |
| `line after EOF` | non-sample, non-blank line after EOF |
| `sample after EOF` | sample line after EOF |
| `bucket without le` | `_bucket` of a histogram without `le` |
| `bad le` | `le` is not finite/`+Inf` or does not parse |
| `duplicate bucket le` | two buckets with the same `le` (micro-units) |
| `bucket le out of order` | `le` regression or bucket after `+Inf` |
| `bad quantile` | quantile not finite or outside `[0, 1]` |
| `unexpected histogram sample` | plain sample of a histogram family |
| `summary sample without quantile` | plain sample of a summary family |

## 10. API index

Parsing:

- `mon_parse(text) -> Result[MonDoc, Str]` -- strict; first error aborts.
- `mon_parse_ok(text) -> Bool`
- `mon_parse_lenient(text) -> MonDoc` -- collects `err_msgs`/`err_lines`/
  `err_ats`, keeps valid families/samples.
- `mon_parse_line(line) -> Result[MonLine, Str]`
- `mon_parse_value(text) -> Result[MonValue, Str]`
- `mon_parse_float(text) -> Result[Float64, Str]`

Values / constants:

- `mon_value_raw`, `mon_value_kind`, `mon_value_is_finite`,
  `mon_value_is_special`, `mon_value_is_nan`, `mon_value_is_pos_inf`,
  `mon_value_is_neg_inf`, `mon_value_micro`, `mon_value_float`
- `mon_kind_finite/pos_inf/neg_inf/nan`
- `mon_part_plain/bucket/sum/count/created/quantile`
- `mon_line_blank/comment/help/type/unit/eof/sample`

Line accessors (`mon_line_get_*`): kind, name, name_at, part, type, type_at,
help_raw, help_text, help_at, unit, unit_at, value_raw, value_kind,
value_micro, value_float, value_at, value_len, has_timestamp, timestamp,
ts_at, label_count, label_name/value/value_raw/name_at/value_at,
label_index, label_lookup, exemplar_count, exemplar_label_count,
exemplar_label_name/value, exemplar_value_raw/kind/micro/float,
exemplar_has_timestamp, exemplar_timestamp, exemplar_at, exemplar_len, at,
len.

Document accessors (`mon_doc_*`): line_count, byte_count, eof_seen, eof_at,
error_count, error_msg, error_line, error_at, family_count, family_index,
family_name, family_type, family_has_type, family_help, family_help_text,
family_has_help, family_unit, family_has_unit, family_sample_count,
family_sample_at, sample_count, sample_name, sample_family, sample_part,
sample_value_raw/kind/micro/float, sample_has_timestamp, sample_timestamp,
sample_line, sample_at, sample_len, sample_exemplar_count, sample_has_le,
sample_le_raw/micro/inf, sample_has_quantile, sample_quantile_raw/micro,
sample_label_count, sample_label_name/value/value_raw/name_at/value_at,
sample_label_index, sample_label_lookup, exemplar_label_count,
exemplar_label_name/value, exemplar_value_raw/kind/micro/float,
exemplar_has_timestamp, exemplar_timestamp, exemplar_at, exemplar_len.

## 11. Complexity

All parsing and accessors are O(len(text)) or O(rows) per call; the family
and label lookups are linear scans over parallel vectors (no hashing).
