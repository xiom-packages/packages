# xiom.environment -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.environment` (`src/environment.xi`). Pure XIOM, no FFI, no file
I/O, no process-environment access.

## 1. Scope

A small, deterministic environment-variable expansion engine for in-memory
`Str` text with a caller-supplied variable table:

- `env_expand` -- text + table + strictness -> `Result[Expansion, Str]`,
- `env_expand_pairs` -- text + `"NAME=VALUE"` entries -> `Result[Expansion, Str]`,
- `env_vars_from_pairs` -- entries -> `EnvVars`.

Because the table never comes from the process environment, expansion is a
pure function of `(src, table, strict)` and fully testable.

## 2. Data model

```xi
pub type EnvVars = {
  names: Vec[Str];    // lookup names, index-aligned with values
  values: Vec[Str];   // values
}

pub type Expansion = {
  text: Str;          // the expanded output
  names: Vec[Str];    // distinct names looked up, first-lookup order
}
```

Invariants and lookup rules:

- `names` and `values` are index-aligned; a lookup pair exists only up to the
  shorter vector's length, so a name beyond the end of `values` is unset.
- Lookups are byte-exact and case-sensitive.
- The first entry whose name matches **and** has a parallel value wins;
  duplicate names therefore resolve to the first occurrence.
- `Expansion.names` is distinct (each looked-up name once), ordered by first
  lookup, and includes names that were unset under lenient mode. Names inside
  skipped operator words, inside single-quoted spans, and names never reached
  because an error aborted the expansion, are not reported.

`Vec[StructType]` is not usable in this compiler, so tables and results are
structs of homogeneous vectors (no `Vec[EnvVars]`, no entry structs).

## 3. Grammar

```
text       = *( literal / escape / squote / dquote / reference )
escape     = "$$"                        ; emits one literal "$"
squote     = "'" *( byte except "'" ) "'"          ; literal, quotes removed
dquote     = DQUOTE *( dbyte / escape / reference ) DQUOTE
                                         ; quotes removed; a "'" is an ordinary
                                         ; byte inside a dquote span
reference  = "${" NAME [ operator ] "}"
operator   = ":-" word / "-" word / ":+" word / ":?" word
word       = byte sequence ending at the "}" that closes the reference,
             with nested "${ ... }" counted (see decision 7)
NAME       = ( ALPHA / "_" ) *( ALPHA / DIGIT / "_" )
literal    = byte                         ; any other byte, copied verbatim
ALPHA      = "A".."Z" / "a".."z"
dbyte      = byte except '"'
```

The word is everything between the operator and the closing `}`; there is no
backslash escaping anywhere.

## 4. Semantics (each decision is covered by the conformance suite)

1. **Recognition.** A `$` is special only when immediately followed by `$` or
   `{`. A lone `$`, `$NAME`, `$ {A}` and a `{` without a preceding `$` are
   literal bytes. Only `${NAME}`-style references expand; bare `$NAME` does
   not.
2. **`$$`.** Two consecutive dollars emit one literal `$` and are consumed as
   a unit; `$${A}` emits the literal text `${A}`. The escape also applies
   inside double-quoted spans.
3. **Plain `${NAME}`.** The name is looked up (decision 6). Found: the value
   is copied verbatim. Not found: strict mode is
   `Err("environment: undefined variable: NAME")`; lenient mode emits
   nothing. The name is recorded as referenced either way.
4. **Operators.**
   - `${NAME:-word}`: if `NAME` is unset **or** present with the empty value,
     the word is expanded and its output emitted; otherwise the value is
     emitted.
   - `${NAME-word}`: if `NAME` is unset, the word is expanded; otherwise the
     value is emitted (a set-but-empty value emits `""`, not the word).
   - `${NAME:+word}`: if `NAME` is set **and** non-empty, the word is expanded
     and its output emitted; otherwise nothing is emitted. The value itself is
     never emitted by this form.
   - `${NAME:?word}`: if `NAME` is set and non-empty, the value is emitted;
     otherwise the word is expanded and the result becomes the error message
     (decision 11).
5. **Strictness.** The `strict` flag affects only plain `${NAME}` references,
   including plain references inside selected operator words and inside
   `:?` messages. Operator forms never raise the undefined-variable error:
   `:-`, `-` and `:+` treat an unset name as a defined case, and `:?` has its
   own message (decision 11).
6. **Lookup.** Byte-exact, case-sensitive, first matching pair with a parallel
   value (decision 2). Names are ASCII: `[A-Za-z_][A-Za-z0-9_]*`.
7. **Brace matching.** From the bytes after `${`, scan forward; every `$`
   immediately followed by `{` opens one nesting level and every `}` closes
   the innermost one. The reference content ends at the first `}` with
   nesting level zero; a `$$` pair does **not** shield a following `{` (so
   `$${` opens a level via its second `$`). Quotes do not shield braces: an
   operator word cannot contain an unbalanced `}`.
8. **Operand evaluation and short-circuit.** A selected word is expanded
   recursively with the same table and strictness, at `depth + 1`. An
   unselected word is only brace-matched (decision 7) and never validated or
   expanded, so a bad escape-free quote, an invalid reference or an undefined
   name inside it is not reported and its names are not collected.
   Example: with `A` set, `${A:-${NOPE}}` under strict mode is `Ok` and
   reports only `A`; with `A` empty it is
   `Err("environment: undefined variable: NOPE")`.
9. **Nesting depth.** Top-level text is expanded at depth 0; each selected
   word adds one level. At most eight nested word levels are allowed; entering
   an expansion at depth greater than eight is
   `Err("environment: nesting too deep")`. The exact boundary is pinned by
   the suite: eight `${A:-...}` levels are accepted, nine are rejected.
10. **Quotes.** `'...'` copies its bytes verbatim (no expansion, no escapes)
    and drops the quotes; adjacent spans concatenate, so `'it''s'` is `its`.
    `"..."` expands its content (references and `$$`) and drops the quotes; a
    `'` inside it is an ordinary byte, and the span ends at the first `"`
    (there is no `\"` escape). Quote spans are processed within the range
    being expanded, so a reference cannot span a quote boundary and a quote
    cannot span a reference. A missing closing quote is
    `Err("environment: unterminated single quote")` or
    `Err("environment: unterminated double quote")` when that range is
    actually expanded.
11. **`:?` message.** The word is expanded with the same table, strictness and
    `depth + 1`. If that expansion fails, its error propagates unchanged.
    Otherwise, an empty result yields
    `Err("environment: NAME: unset or empty")` and a non-empty result yields
    `Err("environment: NAME: <expanded message>")`.
12. **Single pass.** Substituted values are copied into the output verbatim
    and never re-scanned, so a value containing `${X}` is emitted as `${X}`.
    Expansion resumes after the reference's closing `}`; a stray `}` in the
    surrounding text is literal.
13. **Pairs.** Each entry is split at its first `=`; the key part is
    everything before it (stored verbatim; only exact lookups reach it) and
    the value part everything after (a value may contain `=`). An entry with
    no `=` or with an empty key part is skipped (malformed entries are
    ignored, never an error). Entries keep their order, so a repeated name
    resolves to the first pair, matching decision 6.
14. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise and never rewrites multi-byte sequences, so non-ASCII text,
    names in values and output pass through byte-exact.
15. **Error precedence inside one reference.** Unterminated reference (no
    matching `}`) is reported before name or operator problems; an empty or
    badly-started name is `invalid variable name` before any operator check
    (so `${:x}` is an invalid name, not an operator); a name followed by
    anything other than `}`, `:-`, `-`, `:+` or `:?` is an
    `unsupported operator` error.
16. **Termination.** Every scan loop advances its index or returns, and every
    branch of the expander consumes at least one byte; with the depth cap,
    expansion always terminates in O(source + references * table length)
    byte work (nested words additionally scan their own ranges).

## 5. API signatures

```xi
pub fn env_expand(src: Str, vars: &EnvVars, strict: Bool) -> Result[Expansion, Str]
pub fn env_vars_from_pairs(pairs: &Vec[Str]) -> EnvVars
pub fn env_expand_pairs(src: Str, pairs: &Vec[Str], strict: Bool) -> Result[Expansion, Str]
```

`env_expand` looks up each distinct name by scanning the table, so the cost is
O(output + references * table length); `env_vars_from_pairs` and
`env_expand_pairs` add O(total entry bytes).

## 6. Error catalog

All failures are `Err(msg)` where `msg` starts with `"environment: "`:

| Message | Trigger |
|---|---|
| `environment: unterminated reference` | `${` with no matching `}`, e.g. `${A`, `${`, `a ${B`, `"${A"` |
| `environment: invalid variable name` | brace content that does not start with `[A-Za-z_]`, e.g. `${}`, `${1A}`, `${.x}`, `${:x}` |
| `environment: unsupported operator: <token>` | valid name followed by anything other than `}`, `:-`, `-`, `:+`, `:?`. Token: `:` when the content ends right after `:` (`${A:}`); `:` plus the next byte when that byte is not `-`, `+` or `?` (`${A:b}` -> `:b`); otherwise the single offending byte (`${A+x}` -> `+`, `${A?}` -> `?`, `${A.b}` -> `.`) |
| `environment: unterminated single quote` | `'` with no closing `'` in the expanded range, e.g. `'abc`, `a'b` |
| `environment: unterminated double quote` | `"` with no closing `"` in the expanded range, e.g. `"abc` |
| `environment: nesting too deep` | a selected word would expand at depth > 8 |
| `environment: undefined variable: <NAME>` | plain `${NAME}` with an unset name and `strict = true` |
| `environment: <NAME>: <message>` | failing `${NAME:?word}` whose expanded word is non-empty |
| `environment: <NAME>: unset or empty` | failing `${NAME:?}` (or a word expanding to `""`) |

An error while expanding a `:?` word propagates instead of the `:?` message
(decision 11); all other errors above abort the whole expansion and no
`Expansion` is produced.

## 7. Test plan

`tests/test_conformance.xi` (module `environment_tests`) runs 23 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | single `${VAR}` | one substitution, surrounding literals |
| t2 | multiple/repeated refs | `${A}+${B}=${C}`, `${A}${A}${B}` |
| t3 | `${VAR:-word}` | unset and empty select the word; set keeps the value; empty word |
| t4 | `${VAR-word}` | only unset selects the word; set-but-empty stays `""` |
| t5 | `${VAR:+word}` | set and non-empty only; empty/unset yield `""`; empty word |
| t6 | `${VAR:?message}` | unset and empty fail; set passes; empty message wording |
| t7 | `:?` word expansion | `bad ${S}` and `${S}` become the error text |
| t8 | strict unknown | exact `undefined variable` message; empty table; plain text ok |
| t9 | lenient unknown | `[...]` collapses; `:-` still works |
| t10 | `$$` escape | `$$`, `$$5`, `$${A}`, `$$$$`, `a$$b` |
| t11 | lone `$` | `$`, `$A`, `a$`, `$ {A}` are literal |
| t12 | single quotes | `${A}` literal, `$$` literal, spaces, `'it''s'`, embedded `"` |
| t13 | double quotes | expansion, `$${A}` literal, `'` ordinary inside, `a'b'c` |
| t14 | mixed spans | `'${A}'${A}`, `pre"${A}"post`, `"x"'y'` |
| t15 | unterminated quotes | both exact messages; `a'b` |
| t16 | unterminated refs | `${A`, `${`, `a ${B` under both modes |
| t17 | invalid names | `${}`, `${1A}`, `${.x}`, `${:x}` |
| t18 | unsupported operators | `+`, `?`, `:b`, `:`, `.` tokens |
| t19 | nested words | selected words expand nested refs; skipped words are inert |
| t20 | depth cap | eight `:-` levels ok, nine are `nesting too deep` |
| t21 | names list | distinct, first-lookup, dedup; quoted and skipped-word names absent |
| t22 | pairs | `=` in value, malformed skipped, first duplicate wins, table reuse |
| t23 | empty/plain/non-ASCII | `""`, plain `$ {}` text, `café` byte-exact |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 8. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-scanner
idioms as `xiom.dotenv`/`xiom.envsubst` and documents these compiler-driven
choices:

- `Vec[StructType]` is unsupported, so tables and results are structs of
  parallel homogeneous vectors.
- `Ok`/`Err` for `Result[Expansion, Str]` are constructed only in the leaf
  helpers `_env_ok_exp`/`_env_err_exp`.
- `byte_at` returns `UInt8`, so bytes are compared directly against `u8`
  constants (no widen+mask idiom).
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); elements are read into typed
  locals before use.
- Helpers carry the `_env_` prefix because short C-runtime names such as
  `_close` collide with the platform linker.
- The expander is a single mutually-recursive pair
  `_env_expand_range`/`_env_expand_ref` with `&mut` buffers threaded through;
  every loop advances or returns.
- Tests dispatch directly (`t1()` ... `t23()`); `Vec[fn]` indexed calls are
  not used, no match pattern binds `mut`, and every `match` is exhaustive.

## 9. Known limitations

- Only `${NAME}` references, `$$`, `'...'` and `"..."` are recognized; bare
  `$VAR`, `%VAR%`, `$(cmd)`, backslash escapes and brace-free forms are
  literal text.
- Only `:-`, `-`, `:+` and `:?` exist; `${VAR+word}`, `${VAR?message}`,
  `${#VAR}`, substring/replacement forms and nested-name forms
  (`${A${B}}` is not nesting) are errors or literal output as documented.
- No process environment, no file I/O, no cascade/chained files.
- Single pass: values are never re-scanned.
- A `"` cannot appear inside a double-quoted span; quotes do not shield
  braces inside an operator word.
- Skipped operator words are not validated.
- `NAME` is ASCII-only; nesting is capped at eight levels; errors carry no
  byte offset or line/column position.
