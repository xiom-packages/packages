# xiom.geology -- SPEC

LAS 2.0 (Log ASCII Standard) well-log text parsing, as actually implemented in
`src/geology.xi` at version 0.1.0. This document describes the grammar and
semantics the code accepts, the numeric model, the data model, the error
catalog, and the known divergences. Where the implementation is stricter or
more permissive than a typical LAS reader, that is stated explicitly.

## 1. Scope and non-goals

Implemented: read one LAS 2.0 document from a `Str`; parse sections `~V`, `~W`,
`~C`, `~P`, `~A`; preserve `~O` verbatim; return a `LasLog` value with
fixed-point scaled integers (scale 1000) and per-cell null flags; report all
failures as `Err` strings with a 1-based line number and a 0-based byte offset.

Not implemented: writing LAS; unit conversion; interpreting `~O`; validating
the VERS value; enforcing STOP against the number of rows; scientific notation
(`1.5E-3`); multi-line wrapped rows (LAS 1.2 "several values per line" wrap);
depth interpolation beyond `strt + row * step`.

## 2. Lines and sections

- A physical line ends at LF (`\n`). A CR immediately before the LF is
  stripped, so CRLF and LF files are equivalent. A lone CR is not a separator.
- The first non-blank byte of a line is significant. Blank lines are skipped
  (except inside `~O`, section 8).
- A line whose first non-blank byte is `#` is a comment and is skipped. This
  applies in every section **except `~O`** (section 8).
- A line whose first non-blank byte is `~` starts a section. The next
  non-blank byte selects the section, case-insensitively, by its first letter
  only; all remaining text on the header line is ignored:

  | Letter | Section | Meaning |
  |--------|---------|---------|
  | `V` | `~Version Information` | VERS and WRAP |
  | `W` | `~Well Information` | STRT/STOP/STEP/NULL and well rows |
  | `C` | `~Curve Information` | curve rows (required) |
  | `P` | `~Parameter Information` | parameter rows |
  | `A` | `~ASCII` | data rows |
  | `O` | `~Other` | preserved verbatim |

- Any other letter is an error. A duplicate `~V`, `~W`, `~C` or `~P` header
  is an error. `~A` may appear more than once; later blocks append rows to the
  same table and share the row-shape convention (section 6). `~O` may repeat.
- Lines before the first section header are ignored (a preamble is tolerated).
- Mnemonic comparisons are case-insensitive (section 3); curve names, well
  mnemonics and parameter mnemonics are stored exactly as written.

## 3. Definition rows (`~V`, `~W`, `~P`)

A definition row is `MNEM.UNIT VALUE : DESCRIPTION`. Parsing:

1. The description is the text after the first `:` that is not inside quotes
   (single or double), trimmed; when there is no colon the description is `""`.
2. The text before that colon is trimmed. The mnemonic is the longest leading
   run of `[A-Za-z0-9_]`; when the run is empty the row is invalid.
3. One optional `.` directly after the mnemonic is skipped, then the remainder
   is trimmed. If the remainder now begins with `.` followed by a non-digit,
   that dot is skipped too (tolerates `FLD . FIELD`). A leading `.` followed by
   a digit is kept, so `.5` remains a value.
4. The remainder is split on whitespace runs into tokens; quotes are stripped,
   and a quoted token may contain spaces and colons.
5. Value/unit selection:
   - one token: `value` = token, `unit` = `""`;
   - two or more tokens and the **last** token parses as a number and the
     **first** token is unit-shaped: `unit` = first, `value` = last;
   - two or more tokens and the last token parses as a number: `unit` = `""`,
     `value` = last;
   - otherwise `unit` = `""`, `value` = all tokens joined with single spaces
     (empty tokens skipped).
   The unit must therefore precede the value; a unit written after the value
   is not recognized.

A token is unit-shaped when it is 1-8 bytes, contains at least one ASCII
letter, contains only letters, digits, `.`, `-`, `/`, `%`, `_`, and does not
itself parse as a number (`M`, `GAPI`, `G/C3`, `US/F`, `OHMM`, `DEGC`).

Per section:

- `~V`: `VERS` stores the value verbatim; `WRAP` must be `YES` or `NO`
  (case-insensitive, value only) and sets the wrap flag. Other rows are
  ignored.
- `~W`: `STRT`, `STOP`, `STEP`, `NULL` parse the value as a scaled number
  (section 5); a non-numeric value is an error. Each depth row that carries a
  non-empty unit updates `depth_unit` (last one wins). All other rows become
  well rows (mnemonic, unit, value, description) in push order.
- `~P`: every valid row becomes a parameter row in push order.

## 4. Curve rows (`~C`)

A curve row is `NAME.UNIT [TYPE/API...] : DESCRIPTION`. The head, mnemonic,
dot and description handling is identical to section 3. Token selection on
the remainder:

- no tokens: `unit` = `""`, `type` = `""`;
- one token: `unit` = token, `type` = `""`;
- two or more tokens: when the first token is unit-shaped, `unit` = first and
  `type` = the remaining tokens joined with single spaces; otherwise `unit` =
  `""` and `type` = all tokens joined.

This accepts both the common `GR.GAPI : GAMMA RAY` form and LAS 2.0 API-code
rows such as `GR.GAPI 00 000 00 00 : GAMMA RAY` (type = `00 000 00 00`).

The `~C` section must exist and contain at least one curve row. Curve rows are
stored in file order; that order defines the cell index. Curve names are not
uniquified or validated; `las_curve_index` returns the first case-insensitive
match.

## 5. Fixed-point numeric model

Every number is an `Int` in thousandths of its declared unit (scale = 1000,
`las_value_scale()`), including `STRT`, `STOP`, `STEP`, `NULL`, data cells and
depths. No `Float64` is used.

Token grammar: `[+-]? digits [ . digits ]` with at least one digit overall;
`.5` and `5.` are accepted, bare `+`/`-`/`.` are not. Conversion:

- integer part: accumulated with an overflow guard; magnitudes above
  9223372036854775 (whole units) are rejected as invalid;
- fraction part: the first three digits are kept, further digits are validated
  but ignored, missing digits are right-padded with zeros;
- result = `sign * (int_part * 1000 + frac3)`, so extra fraction digits are
  **truncated toward zero**, never rounded: `1.2345` -> `1234`,
  `-1.2345` -> `-1234`, `-0.0009` -> `0`, `-0.125` -> `-125`.
- The empty token is not a number: it carries the `blank` flag and is handled
  by context (null cell, or invalid depth).
- Anything else (letters, exponents, a second `.`, internal spaces) is invalid.

Depth arithmetic uses exact scaled integers: `depth(row) = strt + row * step`
(`las_depth`), no tolerance. `las_depth_is_expected(row, d)` is the exact
comparison `d == strt + row * step`. STOP is parsed and exposed but never
enforced.

## 6. Data rows (`~A`)

Rows are read until the next section header. Blank lines and comment lines are
skipped; a `#` byte in the middle of a row starts a trailing comment. Tokens
are whitespace-separated (space/tab); a token may be wrapped in single or
double quotes, which are stripped (a quoted token cannot contain spaces in the
data section). The absolute byte offset of every token is tracked for errors.

Two layouts:

- **WRAP YES**: each row carries exactly `curve_count` values, one per curve
  in `~C` order. There is no depth token; `las_depth_read` is `-1` and the
  depth is implied by `strt + row * step`.
- **WRAP NO**: the row starts with a depth token. Two shapes are accepted:
  - `curve_count + 1` tokens: the leading token is a dedicated depth column
    and the remaining tokens are the curve values;
  - `curve_count` tokens: the conventional LAS layout in which the first
    curve (typically `DEPT`) doubles as the depth column; that token is both
    `cells[row * curve_count + 0]` and `las_depth_read(row)`.

  The first non-empty data row fixes which of the two shapes the file uses;
  every later row must have exactly that many tokens. This makes a file with a
  mixed shape fail on the first deviating row rather than silently
  misaligning cells. (A file may be re-scanned with `~A` blocks; the
  convention persists across them.)

The depth token must parse as a scaled number; a blank depth token is an
error, but a token equal to `NULL` is accepted as a numeric depth.

Null model: `NULL` defaults to `-999.25` (`-999250`) when the `~W` section has
no `NULL` row. A cell is null when

- its token is blank (`""`), in which case the stored value is `0`; or
- its scaled value equals the scaled `NULL` declaration exactly.

Null cells keep their raw scaled magnitude (blank cells store `0`); consumers
must check `las_cell_is_null` or use `las_cell`. The comparison is exact
scaled-integer equality: a value that differs from `NULL` in the fourth
decimal is not null.

## 7. Data model (`LasLog`)

All row lists are parallel vectors: index `i` of each list describes the same
curve/well/parameter/data row. Cells are row-major, so cell `(row, curve)` is
at `row * curve_count + curve`, and `nulls` mirrors `cells` one-to-one.

| Field | Type | Meaning |
|-------|------|---------|
| `version` | `Str` | VERS value (`""` when absent) |
| `wrap` | `Bool` | WRAP YES (false when absent or NO) |
| `strt`, `stop`, `step` | `Int` | scaled; `0` when absent -- check the `have_*` flags |
| `depth_unit` | `Str` | unit of the last STRT/STOP/STEP row that declared one |
| `null_value` | `Int` | scaled NULL declaration (default -999250) |
| `have_strt`, `have_stop`, `have_step` | `Bool` | presence flags |
| `curve`, `curve_unit`, `curve_type`, `curve_desc` | `Vec[Str]` | `~C` rows |
| `well`, `well_unit`, `well_value`, `well_desc` | `Vec[Str]` | non-special `~W` rows |
| `param`, `param_unit`, `param_value`, `param_desc` | `Vec[Str]` | `~P` rows |
| `row_count` | `Int` | number of data rows |
| `cells` | `Vec[Int]` | row-major scaled values |
| `nulls` | `Vec[Int]` | `0`/`1`, mirrors `cells` |
| `depths` | `Vec[Int]` | canonical scaled depth per row; `-1` when STRT/STEP missing |
| `depths_read` | `Vec[Int]` | first data token per row; `-1` for WRAP YES |
| `row_line` | `Vec[Int]` | 1-based physical line each row started on |
| `other` | `Vec[Str]` | `~O` lines verbatim (header line excluded) |

## 8. Opaque `~O`

Every physical line between a `~O` header and the next section header is
pushed verbatim, with only the CR of a CRLF stripped: blank lines, `#` lines
and indentation are preserved. The `~O` header line itself is not stored.
`las_other_count` / `las_other_line` expose the list.

## 9. Errors

All failures return `Err("geology: <reason> at line <L> offset <B>")` where
`L` is 1-based and `B` is a 0-based byte offset: the line start for
line-level errors, the token start (including an opening quote, when present)
for token-level errors. `geology_error_line` and `geology_error_offset` parse
`L` and `B` back out; both return `-1` when the markers are absent.

| Reason template | Trigger |
|-----------------|---------|
| `unknown section: <head>` | `~` followed by an unimplemented letter (`<head>` is up to 16 bytes of the header) |
| `empty section header` | `~` with nothing after it |
| `duplicate ~V section` / `~W` / `~C` / `~P` | second occurrence of that header |
| `invalid definition` | `~V`/`~W`/`~P` row with an empty mnemonic |
| `invalid WRAP value: <value>` | WRAP value is not YES/NO |
| `invalid STRT value: <value>` / `STOP` / `STEP` / `NULL` | special `~W` row whose value is not a scaled number |
| `invalid curve definition` | `~C` row with an empty mnemonic |
| `missing ~C curve section` | document ends without `~C`; also a data row that appears before any curve is known |
| `empty ~C curve section` | `~C` header present but zero curve rows (reported at the header) |
| `ragged row: expected N values, got M` | token count differs from the fixed file convention (WRAP YES or an established WRAP NO shape) |
| `ragged row: expected N or M values, got K` | first WRAP NO data row does not match either accepted shape |
| `invalid depth token: <token>` | WRAP NO row whose first token is blank or not a scaled number |
| `invalid numeric token: <token>` | cell token that is neither blank nor a scaled number |

Empty input fails with `missing ~C curve section at line 1 offset 0`.

## 10. Accessors

All accessors are total and never trap.

| Accessor | Returns | Out-of-range |
|----------|---------|--------------|
| `las_value_scale()` | 1000 | -- |
| `las_parse(text)` | `Result[LasLog, Str]` | -- |
| `las_version`, `las_depth_unit` | `Str` | n/a |
| `las_wrap`, `las_has_start`, `las_has_stop`, `las_has_step`, `las_depth_known` | `Bool` | n/a |
| `las_start_depth`, `las_stop_depth`, `las_step`, `las_null_value` | scaled `Int` | n/a |
| `las_curve_count`, `las_row_count`, `las_well_count`, `las_param_count`, `las_other_count` | `Int` | n/a |
| `las_curve_name`, `las_curve_unit`, `las_curve_type`, `las_curve_desc` | `Str` | `""` |
| `las_curve_index(name)` | first case-insensitive index | `-1` |
| `las_cell_value(row, curve)` | scaled `Int` | `0` |
| `las_cell_is_null(row, curve)` | `Bool` | `true` (there is no such cell) |
| `las_cell(row, curve)` | `LasCell` | `{ value: 0; is_null: true }` |
| `las_depth(row)` | `strt + row * step`, or `-1` when STRT/STEP are missing | `-1` |
| `las_depth_read(row)` | written first token, or `-1` for WRAP YES | `-1` |
| `las_depth_is_expected(row, d)` | exact equality with `strt + row * step` | `false` |
| `las_row_line(row)` | 1-based line | `-1` |
| `las_well_mnemonic/unit/value/desc(i)`, `las_param_mnemonic/unit/value/desc(i)` | `Str` | `""` |
| `las_well_lookup(mnem)`, `las_param_lookup(mnem)` | first case-insensitive value | `""` |
| `las_other_line(i)` | `Str` | `""` |
| `las_scaled_to_string(v)` | signed fixed-point text | -- |
| `geology_error_line(e)`, `geology_error_offset(e)` | `Int` | `-1` |

## 11. Divergences and limitations

- `STOP` is parsed but not enforced; rows beyond it are accepted.
- `las_depth_read` is not automatically reconciled with `las_depth`; use
  `las_depth_is_expected` when exact agreement matters.
- Section recognition uses the first letter only: `~Curve`, `~CURVE` and `~C`
  are equivalent, and the rest of the header line is ignored.
- VERS is not validated; a file declaring anything else is still parsed with
  the same rules (no LAS 1.2-specific behavior).
- Data tokens quoted with embedded spaces are not supported; the header-line
  tokenizer does support them.
- Scientific notation is not supported and is rejected as an invalid token.
- A comment is recognized only at the start of a line or after whitespace in
  the data section; `#` immediately after a value (`1.5#x`) ends the token at
  the `#`.
- Curve rows whose name is quoted or contains spaces are not supported; the
  mnemonic must start with a letter, digit or `_`.
- `~O` blank lines are preserved, so an empty line inside `~O` counts as a
  preserved line.
- Values are exact scaled integers; there is no rounding and no float path,
  so consumers of physical units must divide by 1000 themselves.

## 12. Test map

`tests/test_conformance.xi` (26 checks, all PASS):

| Test | Covers |
|------|--------|
| t1--t5 | full unwrapped document: VERS/WRAP, STRT/STOP/STEP/NULL, curves, cells, nulls, depths, lookups |
| t6 | WRAP YES: implied depths, `depth_read = -1` |
| t7 | CRLF, lowercase sections/mnemonics, tabs, comments, negative STEP, custom NULL |
| t8 | quoted values with dots/colons, API-code curve rows, quoted data token |
| t9 | declared NULL, blank quoted cell, non-null neighbor, dedicated depth column |
| t10 | truncation toward zero, leading `+` |
| t11 | exact error message for a bad numeric token (line + offset) |
| t12 | ragged rows against the established shape, both directions |
| t13 | wrapped row with too many values |
| t14 | blank quoted depth token |
| t15 | missing `~C` |
| t16 | empty `~C` (points at the header) |
| t17 | unknown section letter |
| t18 | duplicate `~C` |
| t19 | `~O` verbatim preservation (comments and spacing) |
| t20 | `~W`/`~P` rows, lookups, values containing spaces |
| t21 | inline comments, blank lines, multi-space rows |
| t22 | missing `~V` defaults |
| t23 | out-of-range accessors |
| t24 | missing STEP: unknown depth arithmetic, raw depth kept |
| t25 | `las_scaled_to_string` |
| t26 | error line/offset helpers, invalid WRAP |
