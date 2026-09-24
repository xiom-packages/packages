# xiom.envsubst -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.envsubst` (`src/envsubst.xi`). Pure XIOM, no FFI, no file I/O,
no environment access.

## 1. Scope

A small, dependency-free `${VAR}` expander for in-memory `Str` text with a
caller-supplied variable table:

- `envsubst_expand` -- text + parallel name/value vectors -> `Result[Str, Str]`,
- `envsubst_expand_pairs` -- text + `"NAME=VALUE"` entries -> `Result[Str, Str]`,
- `envsubst_has_vars` -- cheap reference pre-check,
- `envsubst_names` -- referenced-name enumeration.

Because the table never comes from the process environment, expansion is
deterministic and fully testable; the module does not read, write or depend on
any ambient state.

## 2. Expansion grammar

```
text        = *( literal / escape / reference )
escape      = "$$"                      ; emits one literal "$"
reference   = "${" NAME "}"             ; emits the value, "" or Err
NAME        = ( ALPHA / "_" ) *( ALPHA / DIGIT / "_" )
literal     = byte                      ; any byte not starting an escape or
                                        ; a reference; includes a lone "$",
                                        ; a "{" not preceded by "$", and all
                                        ; text between references
ALPHA       = "A".."Z" / "a".."z"
```

The reference content is everything between `${` and the **first** following
`}`; there is no nesting and no escaping inside the braces.

## 3. Semantics (each decision is covered by the conformance suite)

1. **Reference.** At a `${`, scan forward to the first `}`. If there is none,
   the whole expansion is `Err("envsubst: unterminated variable reference")` --
   in both missing-value modes. Otherwise the content must match `NAME`
   exactly; if it does not, the expansion is
   `Err("envsubst: invalid variable name")` -- in both modes.
2. **Lookup.** `NAME` is matched byte-exactly and case-sensitively against the
   `names` vector. The first entry whose name matches **and** has a parallel
   value wins; a name that appears only after the end of `values` counts as
   undefined. Duplicate names therefore resolve to the first.
3. **Missing value.** With `missing_empty = false`, an undefined `NAME` is
   `Err("envsubst: undefined variable: NAME")`. With `missing_empty = true`,
   it expands to `""`. A name that is present with the empty value always
   expands to `""` (it is not undefined), in both modes.
4. **`$$`.** Two consecutive dollars emit one literal `$` and are consumed as
   a unit. Consequently `$${A}` emits the literal text `${A}` -- it is not an
   escape followed by a reference.
5. **Lone `$`.** A `$` not followed by `$` or `{` is copied literally, as is
   the byte after it.
6. **Lone `{`.** A `{` not immediately preceded by a `$` is copied literally;
   a stray `}` is literal text.
7. **Text after a reference.** Expansion resumes after the closing `}`; any
   remaining bytes (including an extra `}`) are literal.
8. **Nested-looking input.** `${A${B}}` is not nesting: the content up to the
   first `}` is `A${B`, which fails `NAME` validation, so it is
   `Err("envsubst: invalid variable name")`. By contrast `x${A}y}` expands
   the reference and keeps `y}` as text.
9. **Single pass.** Substituted values are copied into the output verbatim
   and are never re-scanned, so a value containing `${X}` is emitted as
   `${X}`.
10. **Pairs.** Each entry is split at the first `=`; the key part is
    everything before it and the value part everything after (a value may
    contain `=`). An entry with no `=` or with an empty key part is skipped
    (malformed pairs are ignored, never an error). Keys are stored verbatim
    (only exact lookups can reach them) and the first pair for a repeated
    name wins, matching decision 2.
11. **`envsubst_has_vars`.** A raw scan for a `$` immediately followed by
    `{`. It is deliberately not a validator: it reports true for `"${"`
    without a closing `}`, for an invalid name such as `"${1}"`, and for
    `"$${"` (which expansion treats as the literal `"${"`). It returns false
    for a lone `$`, `$X` and plain text.
12. **`envsubst_names`.** Distinct names of valid references in first-seen
    order; `$$` is skipped as a literal; invalid brace content (`${}`,
    `${1x}`, `${A-B}`, ...) is skipped; an unterminated `${` stops the scan,
    so names seen before it are still reported. The scan does not expand and
    does not consult any table.
13. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise and never rewrites multi-byte sequences, so non-ASCII text and
    values pass through byte-exact.

## 4. API signatures

```xi
pub fn envsubst_has_vars(text: Str) -> Bool
pub fn envsubst_expand(text: Str, names: &Vec[Str], values: &Vec[Str], missing_empty: Bool) -> Result[Str, Str]
pub fn envsubst_expand_pairs(text: Str, pairs: &Vec[Str], missing_empty: Bool) -> Result[Str, Str]
pub fn envsubst_names(text: Str) -> Vec[Str]
```

Complexity: `envsubst_expand` is O(input length + references * table length);
`envsubst_expand_pairs` adds O(total pair bytes); `envsubst_has_vars` is
O(input length); `envsubst_names` is O(input length * distinct names).

## 5. Error catalog

| Message | Trigger |
|---|---|
| `envsubst: undefined variable: <NAME>` | valid reference whose name is absent (or has no parallel value) with `missing_empty = false` |
| `envsubst: unterminated variable reference` | `${` with no closing `}`, e.g. `"a ${B"`, `"${"`, `"x ${1"` |
| `envsubst: invalid variable name` | brace content not matching `NAME`, e.g. `"${}"`, `"${1A}"`, `"${A-B}"`, `"${A B}"`, `"${A$}"`, `"${A.}"`, `"${A${B}}"` |

The unterminated and invalid-name errors are raised in both missing-value
modes; `missing_empty` only changes the undefined-variable outcome.

## 6. Test plan

`tests/test_conformance.xi` (module `envsubst_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | single `${VAR}` | one substitution, exact Ok text |
| t2 | multiple references | `${A}+${B}=${C}` -> `1+2=3` |
| t3 | repeated references | every occurrence expands |
| t4 | strict missing | Err message is exactly `envsubst: undefined variable: WHO`; empty table too |
| t5 | lenient missing | undefined names collapse to `""` |
| t6 | `$$` literal | `$$5` -> `$5`; `$$` -> `$`; `$${A}` stays `${A}` |
| t7 | lone `{` | `a{b} c`, `}{`, `{$A}` are literal |
| t8 | unterminated `${` | `a ${B`, `${`, `x ${1` are Err in both modes |
| t9 | nested-looking | `${A${B}}` -> invalid name; `x${A}y}` -> `x1y}` |
| t10 | digits/underscore | `${_A1b}${X2}${_}` -> `uvw` |
| t11 | invalid names | `${}`, `${1A}`, `${A-B}`, `${A B}`, `${A$}`, `${A.}` -> invalid in both modes |
| t12 | pairs variant | lookup, `=` in value, first duplicate pair wins |
| t13 | malformed pairs | no-`=` and empty-key entries ignored; undefined after |
| t14 | single pass | value `${B}` is not re-expanded via names, values or pairs |
| t15 | empty inputs | empty text, plain text, empty tables, `names("")`, `has_vars("")` |
| t16 | `has_vars` | true for `${`/`$${`, false for `$`/`$X`/plain |
| t17 | `envsubst_names` | first-seen order, dedup, invalid skipped, unterminated stops |
| t18 | case-sensitivity | `${name}` matches, `${NAME}` is undefined |
| t19 | present empty value | not undefined; strict Ok `""` |
| t20 | duplicate/short table | first duplicate wins; name without a value is undefined |
| t21 | adjacency/lone `$` | `${A}${B}` -> `12`; `$X`, `$ {A}`, `a$` literal |
| t22 | pairs modes | `missing_empty` honoured with pairs and with an empty table |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 7. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same byte-wise
scanner idioms as `xiom.template`/`xiom.dotenv`:

- `Vec[StructType]` is unsupported, so variable tables are parallel
  homogeneous vectors (no entry structs).
- `Ok`/`Err` for `Result[Str, Str]` are constructed only in the leaf helpers
  `_ok_str`/`_err_str`; `envsubst_expand` and `envsubst_expand_pairs` only
  return them.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); values are read into typed
  locals before use.
- Bytes are read as `(string.byte_at(s, i) as Int) & 0xFF`, never compared as
  widened unsigned values.
- Output is collected in a `xiom.string.builder` buffer (one allocation per
  expanded `Str`).
- Tests dispatch directly (`t1()` ... `t22()`); `Vec[fn]` indexed calls are
  not used, there are no inline lambdas, no match pattern binds `mut`, and
  every `match` (none needed here) would be exhaustive.

## 8. Known limitations

- Only `${NAME}` and `$$` are recognized; bare `$VAR`, `%VAR%`, `$(cmd)` and
  backslash escapes are literal text.
- No default/alternate operators (`${VAR:-x}`, `${VAR-x}`, `${#VAR}`,
  `${VAR/x/y}`) and no nesting.
- Single pass only: values are never re-scanned.
- No environment, process or file integration; the table is caller-supplied.
- `NAME` is ASCII-only; no Unicode identifiers.
- Errors carry no byte offset or line/column position.
