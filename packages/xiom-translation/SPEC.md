# xiom.translation -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.translation` (`src/translation.xi`). Pure XIOM, no FFI, no file
I/O.

## 1. Scope

A small, dependency-free message-catalog layer for in-memory `Str` documents:

- `catalog_parse` -- document -> `Result[Catalog, Str]`,
- `catalog_get` / `catalog_locales` / `catalog_keys` -- inspection,
- `catalog_add` -- functional entry write (copy, replace/append),
- `catalog_missing` -- coverage gaps against a fallback locale,
- `catalog_translate` -- fallback resolution plus `{name}` interpolation.

Plural rules, ICU MessageFormat, locale negotiation, file loaders and value
formatting are non-goals (see README.md "Limitations").

## 2. Data model

```xi
pub type Catalog = {
  locales: Vec[Str];  // locale tag of each entry
  keys: Vec[Str];     // message key of each entry
  values: Vec[Str];   // translated text of each entry
}
```

Entry i is the triple (`locales[i]`, `keys[i]`, `values[i]`). The three
vectors are index-aligned and a `(locale, key)` pair appears at most once,
because every write replaces an existing pair in place; a pair therefore
keeps the position of its first insertion. `Vec[StructType]` is not usable in
this compiler, so the catalog is deliberately flat (three homogeneous
vectors) instead of a list of entry structs. A hand-built catalog that is
ragged (unequal vector lengths) is read only up to the shortest vector.

## 3. Line grammar

```
document      = *( line )                      ; LF or CRLF terminated
line          = ws* ( comment / pair )?        ; blank lines are ignored
comment       = ( ";" / "#" ) *( byte except LF )
pair          = key sep value?
sep           = "=" / ":"                      ; first occurrence wins
key           = *( byte except LF ) before sep, trimmed; non-empty
value         = *( byte except LF ) after sep, trimmed; may be empty
ws            = SP | TAB
```

Decisions (each is covered by the conformance suite):

1. **Lines.** LF terminates a line; one trailing CR is removed so CRLF input
   parses identically. A final line without a newline is still a line. A
   UTF-8 BOM is NOT stripped and becomes part of the first key.
2. **Blank lines and comments.** A line whose first non-whitespace byte is
   `;` or `#` is a full-line comment; blank/whitespace-only lines are
   skipped. `#` and `;` elsewhere are ordinary value bytes.
3. **Separator.** The first `=` or `:` on a line splits key and value; later
   occurrences belong to the value (`note = a:b:c` stores `a:b:c`).
4. **Keys.** The text before the separator, trimmed with `str_trim`; must be
   non-empty. Dots and dashes are ordinary bytes (no nesting); spaces inside
   a trimmed key are preserved (`my key = v` stores `my key`). Keys and
   locales are compared byte-exactly and case-sensitively.
5. **Values.** The text after the separator, trimmed; may be empty and may
   contain `=`, `:`, `;`, `#` and braces.
6. **Duplicates.** Not an error: the last assignment wins and keeps the
   first position.
7. **Parse errors.** A non-blank, non-comment line without a separator is
   `Err("translation: missing separator in line: <line>")`; an empty key
   (trimmed) is `Err("translation: empty key in line: <line>")`. `<line>` is
   the trimmed line text. The first bad line aborts the whole parse: no
   partial catalog is returned.
8. **Order.** `catalog_locales` returns the locales that have at least one
   entry in first-seen order; `catalog_keys` returns a locale's keys in entry
   order. Both return fresh copies.
9. **Immutability.** `catalog_add` copies the catalog and returns the copy;
   the input catalog is never mutated.

## 4. Fallback and interpolation rules

`catalog_translate(c, locale, fallback, key, names, values)` resolves the
text in this order:

1. the entry `(locale, key)`, when present;
2. otherwise the entry `(fallback, key)`, when present;
3. otherwise the `key` text itself (always resolves).

The resolved text is then interpolated in one left-to-right pass:

- `{name}` is replaced by the value at the first index where `names[i]`
  equals `name` (`str_compare`) and a parallel `values[i]` exists;
- a name with no match renders empty; `{}` matches the empty-string name;
- a `{` with no later `}` is literal, and scanning continues after it
  (`a{` -> `a{`);
- `{{` is not special: the first `}` closes the placeholder, so the name
  starts with `{`. Example: `{{x}}` with a known `x` -> `}` (the name `{x`
  is unknown, the second `}` is literal);
- a `}` outside a placeholder is literal (`a}}b` -> `a}}b`);
- substituted values are copied byte-exact and never re-scanned, so a value
  containing `{name}` stays literal (`v={a}` with `a -> {b}` yields `v={b}`);
- interpolation also applies to the last-resort key (`hi.{name}` with
  `name -> Ada` yields `hi.Ada`);
- scanning is byte-wise; non-ASCII bytes pass through byte-exact.

## 5. API signatures

```xi
pub fn catalog_parse(locale: Str, text: Str) -> Result[Catalog, Str]
pub fn catalog_get(c: &Catalog, locale: Str, key: Str) -> Option[Str]
pub fn catalog_locales(c: &Catalog) -> Vec[Str]
pub fn catalog_keys(c: &Catalog, locale: Str) -> Vec[Str]
pub fn catalog_add(c: &Catalog, locale: Str, key: Str, value: Str) -> Catalog
pub fn catalog_missing(c: &Catalog, locale: Str, fallback: Str) -> Vec[Str]
pub fn catalog_translate(c: &Catalog, locale: Str, fallback: Str, key: Str,
                         names: &Vec[Str], values: &Vec[Str]) -> Str
```

Complexity: parsing is `O(total input length * entry count)` because
duplicate detection scans the entry list per line; lookups are `O(entries)`;
`catalog_add` is `O(entries)` plus the copies; interpolation is `O(output)`
plus `O(placeholders * names)` for the lookups.

## 6. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"translation: "`:

| Message | Trigger |
|---|---|
| `translation: missing separator in line: <line>` | no `=` or `:`; a bare word such as `key` |
| `translation: empty key in line: <line>` | `=x`, `:x`, `  :  ` |

No other function produces an error: `catalog_get` returns `None`,
`catalog_translate` returns the key text, and the remaining functions are
total.

## 7. Test plan

`tests/test_conformance.xi` (module `translation_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Every string comparison goes through
`xiom.string.compare`'s `str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | basic pairs | `key = value`, whitespace trimmed, lookup |
| t2 | colon separator | `:` splits; the first separator wins (`a:b:c` value); empty value |
| t3 | comments | `;`/`#`/indented full-line comments and blank lines skipped |
| t4 | duplicates | last wins, first position, key order |
| t5 | CRLF | `\r\n` and a final lone `\r` parse, CR stripped |
| t6 | malformed lines | exact `missing separator` / `empty key` messages; `translation: ` prefix |
| t7 | multi-locale get | values per locale; unknown locale/key -> `None` |
| t8 | locales order | first-seen order, no duplicates on re-add |
| t9 | keys order/copy | entry order; returned vector is a copy |
| t10 | add append/replace | new pair appended; existing value replaced in place |
| t11 | add immutability | input catalog unchanged by `catalog_add` |
| t12 | missing detection | fallback-only keys in fallback order; empty and full cases |
| t13 | locale wins | `translate` prefers `locale` over `fallback` |
| t14 | fallback hit | value served from `fallback` when `locale` misses |
| t15 | key fallback | missing everywhere -> the key text; key interpolation |
| t16 | placeholders | multiple and repeated `{name}` substituted once each |
| t17 | unknown names | unknown placeholder names render empty |
| t18 | no re-scan | a substituted value containing `{b}` stays literal |
| t19 | empty names/values | empty vectors, `{}` -> empty-name entry, `""` value, unterminated `{` |
| t20 | empty catalog | `""` and comment-only documents valid; all operations inert |
| t21 | brace literalness | `{{` is not special; lone `}`/`{{`/`}}` behavior |
| t22 | str_compare | content-equal separately allocated locale/key still match |

## 8. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the proven v0.61.3
idioms from the sibling packages (`xiom.dotenv`, `xiom.template`,
`xiom.csv`):

- `Vec[StructType]` is unsupported, so the catalog is three parallel
  homogeneous vectors.
- `Ok`/`Err` for `Result[Catalog, Str]` are constructed only in the leaf
  helpers `_ok_catalog`/`_err_catalog` (constructing Results directly inside
  other functions miscompiles on this compiler).
- Str equality goes through `xiom.string.compare.str_compare` (BUG 17: `==`
  on Str values read from `Vec[Str]` elements lowers to a pointer
  comparison); Vec elements are read into typed locals first.
- Bytes are read as `(string.byte_at(s, i) as Int) & 0xFF`; output is
  accumulated in a `xiom.string.builder` buffer (one allocation per rendered
  `Str`).
- The suite avoids inline lambdas, `mut` patterns, `Vec[fn]` dispatch and
  non-exhaustive `match`es by using one explicit `fn` per check and explicit
  `main` dispatch.

## 9. Known limitations

- Flat keys and byte-exact locale tags only; no nesting, dotted paths or
  locale negotiation.
- No plural rules and no ICU MessageFormat syntax (`{n, plural, ...}`,
  selects, nesting, escaping).
- `{{` cannot escape a literal `{`; a literal `{` is written directly and
  only becomes special when a later `}` exists on the same text.
- No `.po`/`.mo`/JSON/TOML loading or emission; documents are in-memory
  `Str` values in the line grammar of section 3.
- Values cannot span lines; one trailing CR per line is stripped; a UTF-8
  BOM is not stripped.
- Linear lookups; no index. Errors carry no line/column numbers (the
  offending line text is included).
