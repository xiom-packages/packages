# xiom.config -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.config` (`src/config.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A pure, in-memory configuration model:

- `config_parse` -- document text -> `Result[Config, Str]`,
- lookup and enumeration (`config_get`, `config_has`, `config_len`,
  `config_keys`, `config_values`, `config_entries`),
- overlay merge with later-source-wins precedence (`config_merge`,
  `config_resolve`, `config_set`),
- typed getters with defaults and Err variants for str/int/bool,
- schema validation that returns ALL errors (`config_validate`,
  `config_valid`, `config_schema_new`, `config_schema_add`),
- canonical rendering (`config_render`).

Out of scope by design: file I/O, environment variables, includes, hot
reload / watch, interpolation, quoting and escapes.

## 2. Data model

```xi
pub type Config = {
  keys: Vec[Str];    // normalized dotted keys, first-occurrence order
  values: Vec[Str];  // value text, index-aligned with keys
}

pub type Schema = {
  keys: Vec[Str];      // dotted key names
  types: Vec[Str];     // "str" | "int" | "bool"
  required: Vec[Int];  // 1 = required, 0 = optional
  allowed: Vec[Str];   // comma-separated allowed values; "" = unconstrained
}
```

Invariants: `keys.len() == values.len()`; every key is unique; a duplicate
assignment replaces `values[i]` in place, so the key keeps its first
position and the last assignment wins. `Vec[StructType]` is unusable in this
compiler, so entries are two parallel homogeneous vectors instead of a list
of entry structs. Schema rows are index-aligned across all four vectors;
`config_schema_add` is the safe way to build one.

## 3. Grammar

```
document    = *( line )
line        = ws* ( comment / section / pair ) [ ws* comment ]
comment     = ( "#" / ";" ) byte*
section     = "[" dotted-name "]"            ; ws* comment allowed after "]"
pair        = key ws* "=" ws* value?
key         = dotted-name                    ; internal whitespace rejected
dotted-name = segment *( "." segment )       ; every segment non-empty
segment     = byte except ws, "=", "[", "]", "#", ";"
value       = byte*                          ; trimmed; comment-cut rule below
ws          = SP | TAB
EOL         = LF / CRLF / lone CR
```

Plain strings only: there are no quotes and no escape sequences in the
format, and no byte of a line survives a comment cut except the value bytes.
Non-ASCII bytes are passed through verbatim (UTF-8 is not validated).

## 4. Parse decisions

Each numbered decision is covered by the conformance suite.

1. **Lines.** LF, CRLF and a lone CR each terminate a line; a final line
   without a terminator is still a line; a trailing terminator does not add
   an empty line. A UTF-8 BOM is NOT stripped: it becomes part of the first
   line (usually an error, or part of the first key).
2. **Blank lines.** Whitespace-only lines are skipped.
3. **Comments.** A line whose first non-whitespace byte is `#` or `;` is a
   full-line comment. Inside the value span (after trimming), a `#` or `;`
   preceded by space/tab starts a trailing comment: the cut is applied and
   the value re-trimmed. A `#` or `;` as the FIRST value byte is literal, so
   `color = #ff0000` stores `#ff0000` and `k = ; note` stores `; note`.
   `#`/`;` never cut inside a key (they make the key malformed instead).
4. **Sections.** `[name]` where `name` is a dotted-name; the name is trimmed
   inside the brackets and may be dotted (`[a.b]`). An empty name, an
   unclosed bracket, or a bad name is an error; so is any non-comment text
   after the closing `]`. `[x] # comment` is accepted.
5. **Keys.** Dotted names: one or more non-empty segments; the bytes allowed
   are those above 0x20 except `=`, `[`, `]`, `#`, `;` (so internal space or
   tab, `a b`, `a..b`, `.a`, `a.` and `a#b` are malformed). A line without
   `=` is `config: expected '=' in line: ...`; `= v` is
   `config: missing key in line: ...`.
6. **Normalization.** A plain key `K` inside an open section `S` is stored as
   `S.K` (textual prefix; `K` may itself be dotted, so `[db]` plus
   `server.host` yields `db.server.host`). Without a section the key is
   stored as written. Reopening a section continues it; sections accumulate
   keys and are not cleared.
7. **Duplicates.** Not an error: the last assignment wins and the first
   position is kept (across sections too).
8. **Values.** The value is the text after the first `=` in the line, trimmed
   of space/tab and comment-cut as in decision 3. It may be empty, may
   contain `=` and may contain internal space/tab; non-ASCII bytes pass
   through.
9. **Errors.** Parsing stops at the first malformed line; the error message
   embeds the trimmed offending line (no line/column numbers).
10. **NUL.** Input containing a 0x00 byte is rejected with
    `config: NUL byte in input`. In the current toolchain a `Str` cannot
    carry an embedded NUL (strings are NUL-terminated), so this guard is
    defensive for foreign inputs only.

## 5. Merge semantics

- `config_merge(base, overlay)`: copies `base` entries in order, then walks
  `overlay` entries in order; an overlay key already present replaces the
  value in place (base position kept), an overlay-only key is appended. The
  result key order is: base keys in base order, then overlay-only keys in
  overlay order. Neither input is modified.
- `config_resolve(defaults, file, overrides)` is
  `config_merge(config_merge(defaults, file), overrides)`, i.e. the
  precedence chain **defaults <- file <- overrides** (later source wins).
- `config_set(c, key, value)` is a merge of `c` with the single pair
  `(key, value)`, in a new `Config`. The key is used verbatim (no section
  prefixing, no validation) and should be a normalized dotted key.

## 6. Typed getters

Getters never modify the config and never trim stored text (values are
already trimmed by parse).

- `config_get_str` / `config_try_str`: any stored value (including `""`) is
  returned as-is. `config_try_str` fails only when the key is absent:
  `config: missing key: <key>`.
- `config_get_int` / `config_try_int`: grammar `[+-]? [0-9]+` (no
  whitespace, no underscores). Accepted range:
  `-9223372036854775807 ..= 9223372036854775807`. The two's-complement
  minimum `-9223372036854775808` is rejected as out of range because its
  magnitude is not representable as a positive `Int` (same decision as
  `xiom.l10n.number`). Syntax failures and range failures have distinct
  messages; `config_get_int` falls back to its default for both and for an
  absent key.
- `config_get_bool` / `config_try_bool`: the exact byte strings `true`,
  `false`, `yes`, `no`, `1`, `0`, compared ASCII case-insensitively
  (`TRUE`, `TrUe`, `No`, ... are accepted). Anything else -- notably `on`
  and `off` -- is `config: invalid boolean for key <key>: <value>`;
  `config_get_bool` falls back to its default.

## 7. Validation rules

`config_validate(c, s)` walks the schema rows in order and collects ALL
errors (never just the first); `config_valid` is
`config_validate(...).len() == 0`.

Per row, in this order:

1. **Alignment guard.** If `types`, `required` or `allowed` is shorter than
   `keys`, append
   `config: schema vectors are not aligned at index <i>` and stop.
2. **Unknown type.** A type name other than exactly `str`, `int` or `bool`
   appends `config: unknown schema type for key <key>: <type>`. (This is
   reported even when the key is absent: it is a schema bug.)
3. **Missing required.** `required[i] != 0` and the key is absent appends
   `config: missing required key: <key>`. Absent optional keys are fine and
   skip all further checks for that row.
4. **Type check (present values).** `str` always passes; `int` and `bool`
   are parsed with the same parsers as the typed getters and their message
   is appended on failure.
5. **Allowed list.** When `allowed[i]` is non-empty, the raw stored value
   must equal one of its comma-separated tokens (each token trimmed;
   comparison byte-exact). On failure:
   `config: value not allowed for key <key>: <value>`. The list is only
   consulted when the value is present and its type parsed (or the type is
   `str`).

Extra config keys that are not listed in the schema are ignored: validation
is schema-closed, not config-closed. A row contributes at most one error.

## 8. API signatures

```xi
pub fn config_new() -> Config
pub fn config_parse(text: Str) -> Result[Config, Str]
pub fn config_get(c: &Config, key: Str) -> Option[Str]
pub fn config_has(c: &Config, key: Str) -> Bool
pub fn config_len(c: &Config) -> Int
pub fn config_keys(c: &Config) -> Vec[Str]
pub fn config_values(c: &Config) -> Vec[Str]
pub fn config_entries(c: &Config) -> (Vec[Str], Vec[Str])
pub fn config_merge(base: &Config, overlay: &Config) -> Config
pub fn config_resolve(defaults: &Config, file: &Config, overrides: &Config) -> Config
pub fn config_set(c: &Config, key: Str, value: Str) -> Config
pub fn config_get_str(c: &Config, key: Str, default: Str) -> Str
pub fn config_try_str(c: &Config, key: Str) -> Result[Str, Str]
pub fn config_get_int(c: &Config, key: Str, default: Int) -> Int
pub fn config_try_int(c: &Config, key: Str) -> Result[Int, Str]
pub fn config_get_bool(c: &Config, key: Str, default: Bool) -> Bool
pub fn config_try_bool(c: &Config, key: Str) -> Result[Bool, Str]
pub fn config_schema_new() -> Schema
pub fn config_schema_add(s: &Schema, key: Str, typ: Str, required: Bool, allowed: Str) -> Schema
pub fn config_validate(c: &Config, s: &Schema) -> Vec[Str]
pub fn config_valid(c: &Config, s: &Schema) -> Bool
pub fn config_render(c: &Config) -> Str
```

Complexity: parsing is O(total input length * distinct keys) because
duplicate detection scans the key list per assignment; lookups are O(keys);
merge is O(keys of both inputs * result keys); rendering is O(total output
length) amortized for config-sized inputs (Str concatenation).

## 9. Error catalog

Parse errors (all stop at the first offending line; `<line>` is the trimmed
line text):

| Message | Trigger |
|---|---|
| `config: NUL byte in input` | defensive only; see parse decision 10 |
| `config: expected '=' in line: <line>` | non-comment, non-section line without `=` (`justkey`, `[x]` handled as section) |
| `config: missing key in line: <line>` | `= 1` (empty key before `=`) |
| `config: malformed key in line: <line>` | internal whitespace, empty dotted segment, leading/trailing `.`, or `# ; [ ] =` in the key |
| `config: empty section header in line: <line>` | `[]`, `[ ]` |
| `config: malformed section header in line: <line>` | unclosed `[`, bad section name |
| `config: unexpected text after section header in line: <line>` | non-comment text after `]` |

Getter errors:

| Message | Trigger |
|---|---|
| `config: missing key: <key>` | key absent (all `config_try_*`) |
| `config: invalid integer for key <key>: <value>` | not `[+-]?[0-9]+` |
| `config: integer out of range for key <key>: <value>` | magnitude beyond the signed 64-bit range (including the minimum) |
| `config: invalid boolean for key <key>: <value>` | not true/false/yes/no/1/0 (case-insensitive) |

Schema errors (collected, not first-only):

| Message | Trigger |
|---|---|
| `config: missing required key: <key>` | required flag set, key absent |
| `config: unknown schema type for key <key>: <type>` | type name not `str`/`int`/`bool` |
| `config: value not allowed for key <key>: <value>` | value present but not in the allowed list |
| `config: schema vectors are not aligned at index <i>` | parallel schema vectors shorter than `keys` |

## 10. Rendering rules

`config_render(c)` emits `key = value` for every entry:

- **Insertion order** (first-occurrence order), one line per entry, LF
  separated, no trailing LF. An empty config renders as `""`.
- Sections are NOT reconstructed; normalized dotted keys are written as-is,
  so `parse -> render -> parse` is stable for every parsed document.
- Values are written verbatim (the format has no quoting). A value that
  contains space/tab immediately followed by `#` or `;`, or leading/trailing
  space/tab, or a line break cannot be represented; parse never produces
  such values, and `config_set` callers must keep values to the grammar if
  they want round-trips.
- Output is accumulated with `Str` concatenation, never `sb_to_str`, so a
  stray NUL cannot truncate the result.

## 11. Test plan

`tests/test_conformance.xi` (module `config_tests`) runs 27 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t01 | simple pairs | two entries, lookup, case-sensitivity, absent key |
| t02 | sections + dotted keys | `server.host` from `[server]`; `[db]` + `server.host` composes |
| t03 | nested/reopened sections | `[a.b]`, empty section, reopening merges |
| t04 | comments | full-line `#`/`;`, indented, trailing cut, leading `#` literal, `a#b` kept |
| t05 | whitespace | trimming around key/`=`/value, empty value, internal tab kept |
| t06 | duplicates | last wins, first position, order `a,b` |
| t07 | line endings | CRLF, lone CR, final line without newline |
| t08 | parse errors (keys) | no `=`, empty key, `a b`, `a..b`, `a.`, `.a`, `a#b` |
| t09 | parse errors (sections) | unclosed, empty, `[a b]`, `[a..b]`, junk after `]`; comment after `]` ok |
| t10 | lookup/enumeration | `has`/`len`, `None` for absent, fresh-copy `keys`/`values` |
| t11 | entries tuple | parallel `(keys, values)` copies with order |
| t12 | merge precedence | defaults <- file <- overrides; inputs untouched |
| t13 | merge identity | empty base / empty overlay |
| t14 | config_set | replace keeps position, append, original untouched |
| t15 | str getters | value, empty value, default, missing-key Err |
| t16 | int getters | signs, `+5`, `007`, 64-bit bounds, defaults |
| t17 | int errors | empty, `12 3`, `+`, `1+`, `-`, missing key, defaults |
| t18 | int range | `INT_MAX+1`, the minimum, 20-digit magnitude |
| t19 | bool getters | true/false/1/0/yes/no, mixed case, case-insensitivity |
| t20 | bool errors | `maybe`, `on`, missing key, default fallback |
| t21 | schema pass | required present, optional missing, enum ok |
| t22 | schema multi-error | 5 errors in schema order (missing/int/bool/allowed/unknown type) |
| t23 | allowed lists | token trimming, failure message, unlisted config keys ignored |
| t24 | schema alignment | misaligned vectors reported, no crash |
| t25 | render | insertion order, dotted keys, empty config |
| t26 | render round-trip | parse -> render -> parse preserves keys and values |
| t27 | merge render | merged config renders canonically and round-trips |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 12. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.properties`/`xiom.dotenv` (byte-wise scanning with
`xiom.string.byte_at`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so entries and schemas are parallel
  homogeneous vectors.
- `Ok`/`Err` for every `Result[...]` are constructed only in the tiny leaf
  helpers `_cfg_ok`/`_cfg_err`, `_str_ok`/`_str_err`, `_int_ok`/`_int_err`
  and `_bool_ok`/`_bool_err`.
- Str equality goes through `xiom.string.compare.str_compare` (BUG 17);
  values are read into typed locals before use.
- Every string byte is read through the `_byte` helper, which widens to
  `Int` and masks with `0xFF` before any comparison (byte comparisons at
  >= 128 miscompile unless widened and masked).
- Rendering uses `Str` concatenation instead of `sb_to_str` so no NUL
  sentinel can truncate the output.
- Tests dispatch directly (`t01()` ... `t27()`); no indexed `Vec[fn]` calls,
  no inline lambdas, no `mut` bindings in match patterns, and every `match`
  is exhaustive.

## 13. Known limitations

- No file I/O, no environment reads, no includes, no hot reload or file
  watching (explicitly out of scope for this package).
- No interpolation; `$VAR` and `${VAR}` are literal text.
- No quoting, escapes or multiline values; see section 10 for the exact
  values that cannot round-trip.
- Comments and section headers are not preserved by rendering.
- No sorting or pretty-printing options; insertion order only.
- No case or Unicode normalization of keys; comparisons are byte-exact.
- Errors carry the offending line text but no line/column numbers.
- The signed 64-bit minimum is rejected as out of range by the int getter.
- A UTF-8 BOM is not stripped.
- Validation ignores config keys that are not listed in the schema.
