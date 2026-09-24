# xiom.ini -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.ini` (`src/ini.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free INI parser, editor and emitter for in-memory `Str`
documents:

- `ini_parse` -- document -> `Result[Ini, Str]`,
- `ini_get` / `ini_has` -- value lookup and presence,
- `ini_keys` / `ini_sections` -- per-section key order and section order,
- `ini_set` / `ini_remove` -- in-place editing,
- `ini_emit` -- `Ini` -> INI text.

The byte-level rules (comments, separators, trimming, CRLF) follow the
common line-oriented INI conventions as closely as the documented subset
allows; see sections 3-5.

## 2. Data model

```xi
pub type Ini = {
  sections: Vec[Str];  // section of each entry ("" = global/top-level)
  keys: Vec[Str];      // entry keys, index-aligned with sections
  values: Vec[Str];    // entry values, index-aligned with sections/keys
}
```

Invariants: `sections.len() == keys.len() == values.len()`; every
`(section, key)` pair is unique; entries keep first-seen order; a duplicate
assignment replaces `values[i]` in place, so the entry keeps its first
position and the last assignment wins. `ini_remove` shifts the tail left and
pops the trailing slots, so the arrays never contain gaps.

`Vec[StructType]` is not usable in this compiler, so the file is deliberately
flat (three homogeneous vectors) instead of a list of section/entry structs.

## 3. Line grammar

```
document   = *( line )                       ; LF or CRLF terminated
line       = ws* ( header / pair / comment / blank )
header     = "[" ws* name ws* "]"
pair       = key ws* ( "=" / ":" ) ws* value
comment    = ( ";" / "#" ) *( byte except LF )
name       = 1*( byte except "[" / "]" / LF )
key        = 1*( byte except "=" / ":" )      ; the text before the separator
value      = *( byte except LF )              ; the text after it
ws         = SP | TAB
```

Decisions (each is covered by the conformance suite):

1. **Lines.** LF terminates a line; one trailing CR is removed so CRLF input
   parses identically. A final line without a newline is still a line. A
   UTF-8 BOM is NOT stripped and becomes part of the first key.
2. **Whitespace.** The whole line is `str_trim`-ed first, so leading and
   trailing whitespace never matters. Keys, values and section names are
   `str_trim`-ed individually. Space and TAB are equivalent.
3. **Blank lines and comments.** Whitespace-only lines are skipped. A line
   whose first non-whitespace byte is `;` or `#` is a full-line comment and
   is skipped. Comments are parsed and dropped: emit never writes them.
4. **No inline comments.** `;` and `#` after the first byte are ordinary
   data: `a = 1 ; x` stores the value `1 ; x`.
5. **Section headers.** A line whose first non-whitespace byte is `[` must be
   a header: it has to end in `]` (otherwise
   `Err("ini: malformed section header: ...")`), the inner text is trimmed
   (empty -> `Err("ini: empty section name: ...")`), and the trimmed name
   may not contain `[` or `]`. The header switches the current section;
   entries before the first header live in the global section `""`.
6. **Pairs.** The line is split at its first `=` or `:`; the separator is not
   part of the key or the value. `key = value`, `key:value`, `key : value`
   and `key =` (empty value) are all valid. The key is `str_trim`-ed; an
   empty key is `Err("ini: empty key in line: ...")`. A non-blank,
   non-comment line with no separator is
   `Err("ini: expected '=' or ':' in line: ...")`.
7. **No quoting or escapes.** There are no quoted keys/values and no escape
   sequences; the key ends at the first separator, the value runs to the end
   of the line.
8. **Duplicates (merge rule).** A repeated `(section, key)` assignment
   replaces the value in place: the entry keeps the position and section
   order of its first occurrence, and the last assignment wins. This applies
   identically to `ini_parse` and `ini_set`.
9. **Order.** Entries are stored in first-seen order; `ini_keys` returns the
   keys of one section in entry order; `ini_sections` returns distinct
   sections in first-seen (entry) order and lists `""` only when the global
   area has entries. Both getters return fresh copies.
10. **Removal.** `ini_remove` returns false without touching the document
    when the pair is absent; otherwise it removes the entry and compacts the
    three vectors. A section that loses its last entry disappears from
    `ini_sections` and from emitted output.
11. **Emission.** The global group is written first with no header, one
    `key = value` line per entry, LF-separated; then each section of
    `ini_sections` (in order) as `[name]` followed by its entries. Exactly one
    blank line separates two groups; there is no trailing LF. An empty
    document emits `""`. Keys, values and section names are written
    verbatim.
12. **Encoding.** `Str` is treated as a UTF-8 byte buffer and all scanning is
    byte-wise; only ASCII bytes are special, so non-ASCII keys/values pass
    through byte-exact. No byte sequence is ever split or rewritten.
13. **No expansion, no nesting.** `%(name)s`, `${name}` and `$name` are
    literal text; `[a.b]` is a flat section literally named `a.b` (no nested
    sections, no defaults/inheritance).

## 4. API signatures

```xi
pub fn ini_parse(text: Str) -> Result[Ini, Str]
pub fn ini_get(i: &Ini, section: Str, key: Str) -> Option[Str]
pub fn ini_has(i: &Ini, section: Str, key: Str) -> Bool
pub fn ini_keys(i: &Ini, section: Str) -> Vec[Str]
pub fn ini_sections(i: &Ini) -> Vec[Str]
pub fn ini_set(i: &mut Ini, section: Str, key: Str, value: Str)
pub fn ini_remove(i: &mut Ini, section: Str, key: Str) -> Bool
pub fn ini_emit(i: &Ini) -> Str
```

Complexity: parsing is O(total input length * entry count) because duplicate
detection scans the entry list per assignment; lookups and `ini_set`/
`ini_remove` are O(entry count); `ini_keys` is O(entry count); `ini_sections`
is O(entry count * section count); emitting is O(total output length *
section count + entry count).

## 5. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"ini: "`:

| Message | Trigger |
|---|---|
| `ini: malformed section header: <line>` | `[unclosed`, `[a]b]`, `[a][b]`, `[` (no closing `]` or brackets inside the name) |
| `ini: empty section name: <line>` | `[]`, `[  ]` |
| `ini: expected '=' or ':' in line: <line>` | `justakey`, `key value`, `key.value` (no separator) |
| `ini: empty key in line: <line>` | `= 1`, `:value`, `   =  ` |

`ini_set`, `ini_remove` and `ini_emit` are total for any `Ini`; `Ini` values
built with `ini_set` are not validated (see section 7, limitation 5).

## 6. Test plan

`tests/test_conformance.xi` (module `ini_tests`) runs 20 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | global + section parse | global entry, `[server]` entries, no cross-section leak |
| t2 | `:` separator | `a: 1`, `user : ada`, `pass:secret` |
| t3 | full-line comments | `;`/`#`, indented, blank lines; inline `;`/`#` are data |
| t4 | whitespace trimming | spaces/tabs around key, separator, value, `[ sec ]` name |
| t5 | empty key | `= value`, `:value`, `[a]` then `=1` are Err |
| t6 | duplicates | last wins, first position, per-section duplicates |
| t7 | CRLF input | `\r\n` lines parse, CR stripped, sections found |
| t8 | get/has | byte-exact, case-sensitive, absent pairs yield `None` |
| t9 | `ini_keys` order | entry order per section, empty for unknown section |
| t10 | `ini_sections` order | first-seen order with global first here |
| t11 | global section | `""` listed only when it has entries |
| t12 | `ini_set` replace | in-place replace keeps position, no duplicate key |
| t13 | `ini_set` append | new key/section appended, section order kept |
| t14 | `ini_remove` present | compacts global + section arrays, drops emptied section |
| t15 | `ini_remove` absent | false, document untouched |
| t16 | emit -> parse round trip | sections, keys and values survive |
| t17 | emit layout | exact global-first text with blank-line separators |
| t18 | empty documents | `""` and comment-only input: zero entries, emit `""` |
| t19 | invalid headers | unclosed, `[a]b]`, `[]`, `[`, `[  ]`, `[a][b]` |
| t20 | missing separator | `justakey`, `key value`, `value` lines are Err |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 7. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.csv`/`xiom.toml`/`xiom.dotenv` (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the file is three parallel homogeneous
  vectors (no `Vec[IniEntry]`).
- `Ok`/`Err` for `Result[Ini, Str]` are constructed only in the leaf helpers
  `_ok_ini`/`_err_ini`.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); values are read into typed
  locals before use.
- `ini_remove` compacts by shifting elements left and `Vec.pop`-ing the
  trailing slots (no `Vec.remove` element method is resolved for library
  code).
- Tests dispatch directly (`t1()` ... `t20()`); `Vec[fn]` indexed calls are
  not used, no match pattern binds `mut`, no inline lambdas, and every
  `match` is exhaustive.
- `ini_parse` is a single function that owns the per-line loop and mutates
  the three parallel vectors plus the current section through
  `_set_pair(&mut Ini, ...)`; `&Ini` is used by the read-only API.

## 8. Known limitations

- No nested sections (`[a.b]` is flat), no defaults/inheritance, no include.
- No interpolation (`%(name)s`, `${name}`, `$name` are literal).
- Comments are not preserved on emit; emit writes no comments.
- No inline comments (`;`/`#` are full-line only).
- No quoting/escaping; `ini_set` arguments are stored verbatim, so a key with
  `=`/`:` or a section name with `]` may not re-parse as written.
- A value carrying leading/trailing whitespace or an embedded LF does not
  survive an emit/parse round trip.
- No file I/O, no streaming, no registry integration.
- Errors carry no line/column position (the offending line text is included).
