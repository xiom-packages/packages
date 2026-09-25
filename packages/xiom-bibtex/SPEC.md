# xiom.bibtex -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.bibtex` (`src/bibtex.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free BibTeX **codec** for in-memory `Str` documents:

- `bib_parse` -- `.bib` text -> `Result[BibDoc, Str]`,
- flat entry/field/macro accessors (`bib_entry_*`, `bib_field_*`,
  `bib_get_field`, `bib_macro_*`, `bib_get_macro`),
- `@preamble` / `@comment` pass-through accessors,
- `bib_emit` -- canonical BibTeX text,
- documented round-trip: `bib_parse(bib_emit(d))` preserves every entry,
  field, macro, preamble and comment.

The document model is flat: entry types/keys and per-entry field slices are
parallel vectors, and all field names/values and all macro names/values live
in two shared pools. `Vec[StructType]` is not usable in this compiler, so
there is no tree of entry structs.

## 2. Non-goals

- LaTeX macro, accent or escape processing (`\foo`, `\"o`, `~`, `--` are
  opaque bytes).
- Citation styles, `.bst` files, sorting, label generation, `.bib` database
  merging or cross-references (`@xdata`, `crossref` semantics).
- `#` value concatenation; parenthesis-delimited entries (`@type(...)`).
- Field-name mapping to a fixed schema; any field may appear on any entry.
- Writer options (indentation, brace vs. quote style, field ordering).
- File I/O, streaming parsing or registry integration.
- Rich error positions (line/column); errors carry a message and, where
  useful, the offending name or token snippet.
- Any FFI.

## 3. Supported grammar

```
document    = *( ws / entry )
entry       = "@" ws* etype ws* "{" body
etype       = ALPHA *( ALPHA / DIGIT / "-" / "_" / ":" / "." )
body        = string-def / comment / preamble / normal
string-def  = ws* name ws* "=" ws* value ws* "}"
comment     = *( braced-group / byte ) "}"        ; braces balanced
preamble    = ws* value ws* "}"
normal      = ws* key ( ws* "}" / ws* "," field-list )
key         = 1*( byte except ws , "," , "{" , "}" , "(" , ")" , "=" , '"' , "#" )
field-list  = ws* [ field *( ws* "," ws* field ) [ ws* "," ] ] ws* "}"
field       = name ws* "=" ws* value
name        = ALPHA *( ALPHA / DIGIT / "-" / "_" / ":" / "." )
value       = braced-group / quoted / number / macro
braced-group= "{" *( braced-group / byte ) "}"     ; nested braces preserved
quoted      = '"' *( "\" byte / "{" / "}" / byte ) '"'
number      = 1*DIGIT
macro       = name
ws          = SP / TAB / LF / CR
```

The three command names `string`, `comment` and `preamble` are recognized
case-insensitively after `@`; every other `etype` is a normal entry.

### Decisions (each is covered by the conformance suite)

1. **Text outside entries.** Only whitespace (SP TAB LF CR), including CRLF
   line endings, may appear between entries. Any other byte (including `%`
   comments and `{}` blocks) is
   `Err("bibtex: text outside entries: <snippet>")`. An empty or
   whitespace-only document is valid and empty.
2. **Entry type.** `@`, optional whitespace, then a name run starting with
   an ASCII letter. `@article`, `@ARTICLE` and `@Article` all normalize to
   the stored type `"article"`. A missing name after `@` (end of input or
   non-letter) is an error; `@preamble`/`@comment`/`@string` are commands,
   not stored entries.
3. **Entry delimiters.** Only braces are supported. `@type(...)` is
   `Err("bibtex: expected '{' after entry type")`. Entries never nest.
4. **Citation keys.** A key is one or more bytes up to the first whitespace
   or one of `, { } ( ) = " #`. It is stored as written; matching
   (`bib_find_entry`) and duplicate detection are **case-insensitive**, as in
   BibTeX. `@article{k}` (no fields) and `@article{k,}` are valid; an empty
   key is `Err("bibtex: missing key in entry")`.
5. **Fields.** `name = value`, comma-separated, optional trailing comma.
   A field name starts with a letter and continues with letters, digits,
   `-`, `_`, `:` or `.`; names are stored lowercased and matched
   case-insensitively (`bib_get_field`). Duplicate field names within one
   entry are an error. Whitespace and newlines are allowed around `=`,
   commas and the closing `}`.
6. **Braced values.** `{...}`; the outer braces are removed and nested
   braces are preserved verbatim, across lines if necessary. Content is not
   trimmed. An unclosed group is `Err("bibtex: unterminated value")`.
7. **Quoted values.** `"..."`; the outer quotes are removed. A backslash
   escapes the next byte, which is kept verbatim (`\"` does not end the
   string and both bytes stay in the value). Braces must balance inside the
   string; a `}` at level 0 or a closing quote at level > 0 is
   `Err("bibtex: unbalanced braces in value")`. A missing closing quote is
   `Err("bibtex: unterminated quote")`.
8. **Numbers.** One or more ASCII digits, stored verbatim (leading zeros
   kept, no sign, no float). A number immediately followed by a letter is
   not a number token; the trailing letter triggers
   `Err("bibtex: expected ',' or '}' after field value")`.
9. **Macros.** A bare name (not braced, quoted or numeric) is a macro
   reference, matched case-insensitively against the macros defined
   **earlier in document order**. It is expanded at parse time, so stored
   field/macro/preamble values are fully expanded. There are no built-in
   month macros; an unknown reference is
   `Err("bibtex: undefined macro: <name>")`.
10. **`@string`.** `@string{name = value}` where the value is braced,
    quoted, numeric or a reference to an earlier macro. Macro names are
    stored lowercased. Redefining a name (case-insensitively) is
    `Err("bibtex: duplicate macro: <name>")`.
11. **`@comment`.** The body is raw text with balanced braces; the outer
    braces are removed and the body is trimmed. It is stored in
    `comments` and re-emitted as `@comment{body}`. No other parsing happens
    inside. An unclosed body is `Err("bibtex: unterminated comment")`.
12. **`@preamble`.** Exactly one value token (braced, quoted, numeric or a
    macro reference) is stored expanded; missing values error, and a second
    token or `#` is `Err("bibtex: unsupported concatenation")` or
    `Err("bibtex: expected '}' after @preamble")`.
13. **Concatenation.** `#` in value position or after a value is
    `Err("bibtex: unsupported concatenation")`.
14. **Duplicates.** Duplicate citation keys (case-insensitive), field names
    within an entry and macro names are errors; detection is complete before
    the parse succeeds.
15. **Order.** Entries keep document order; their fields keep document
    order. `bib_emit` emits macros, then preamble blocks, then comments,
    then entries, so cross-pool interleaving is canonicalized, not
    preserved.
16. **Encoding.** `Str` is treated as a UTF-8 byte buffer; all scanning is
    byte-wise and multi-byte sequences pass through byte-exact. No
    normalization or validation is performed.

## 4. Data model

```xi
pub type BibDoc = {
  entry_types: Vec[Str];    // entry type per entry, lowercased
  entry_keys: Vec[Str];     // citation key per entry, as written
  field_starts: Vec[Int];   // entry e's first index in field_names/field_values
  field_counts: Vec[Int];   // entry e's field count
  field_names: Vec[Str];    // flat field-name pool, lowercased
  field_values: Vec[Str];   // flat field-value pool, expanded
  macro_names: Vec[Str];    // @string names, lowercased, definition order
  macro_values: Vec[Str];   // expanded @string values
  preambles: Vec[Str];      // expanded @preamble values, document order
  comments: Vec[Str];       // trimmed @comment bodies, document order
}
```

Invariants: the first four entry vectors have equal length;
`field_starts[e] + field_counts[e] <= field_names.len()` (and the same for
`field_values`); `macro_names.len() == macro_values.len()`.

`Vec[StructType]` is not usable in this compiler, so the model is
deliberately flat instead of a tree of entry/field structs.

## 5. API signatures

```xi
pub fn bib_parse(text: Str) -> Result[BibDoc, Str]
pub fn bib_entry_count(d: &BibDoc) -> Int
pub fn bib_entry_type(d: &BibDoc, i: Int) -> Str
pub fn bib_entry_key(d: &BibDoc, i: Int) -> Str
pub fn bib_find_entry(d: &BibDoc, key: Str) -> Int
pub fn bib_field_count(d: &BibDoc, i: Int) -> Int
pub fn bib_field_name(d: &BibDoc, i: Int, j: Int) -> Str
pub fn bib_field_value(d: &BibDoc, i: Int, j: Int) -> Str
pub fn bib_get_field(d: &BibDoc, i: Int, name: Str) -> Option[Str]
pub fn bib_macro_count(d: &BibDoc) -> Int
pub fn bib_macro_name(d: &BibDoc, k: Int) -> Str
pub fn bib_macro_value(d: &BibDoc, k: Int) -> Str
pub fn bib_get_macro(d: &BibDoc, name: Str) -> Option[Str]
pub fn bib_preamble_count(d: &BibDoc) -> Int
pub fn bib_preamble(d: &BibDoc, i: Int) -> Str
pub fn bib_comment_count(d: &BibDoc) -> Int
pub fn bib_comment(d: &BibDoc, i: Int) -> Str
pub fn bib_emit(d: &BibDoc) -> Str
```

Accessors are total: out-of-range indices yield `""`, `0`, `-1` or `None`
(see each function's doc comment). Parsing is O(total input length); index
accessors are O(1); `bib_find_entry`, `bib_get_field` and `bib_get_macro`
are linear in the number of entries/fields/macros.

## 6. Error strings

All parse failures are `Err(msg)` where `msg` starts with `"bibtex: "`.
`<snippet>` is at most 24 bytes of the offending non-whitespace run.

| Message | Trigger |
|---|---|
| `bibtex: text outside entries: <snippet>` | non-whitespace byte outside an entry |
| `bibtex: missing entry type` | `@` at end of input / followed only by whitespace |
| `bibtex: bad entry type: <snippet>` | non-letter where an entry type must start |
| `bibtex: expected '{' after entry type` | `@type` not followed by `{` (e.g. `@type(...)`) |
| `bibtex: unterminated entry` | end of input inside an entry's body |
| `bibtex: missing key in entry` | `@article{}`, `@article{, ...}` |
| `bibtex: expected ',' or '}' after entry key` | junk directly after the key |
| `bibtex: bad field name: <snippet>` | non-letter at field-name position |
| `bibtex: missing '=' after field name: <name>` | field name not followed by `=` |
| `bibtex: missing value for field: <name>` | `field = }`, `field =` at end of input |
| `bibtex: duplicate field: <name>` | same field name twice in one entry |
| `bibtex: expected ',' or '}' after field value` | junk after a value (e.g. `{a} b = {c}`, `12ab`) |
| `bibtex: duplicate key: <key>` | same citation key twice (case-insensitive) |
| `bibtex: malformed value: <snippet>` | value position starts with an unusable byte (`=`, `,`, `@`, ...) |
| `bibtex: unterminated value` | `{` value without its closing `}` |
| `bibtex: unterminated quote` | `"` value without its closing `"` |
| `bibtex: unbalanced braces in value` | `}` at brace level 0, or closing quote while a brace is open |
| `bibtex: unsupported concatenation` | `#` in or after a value |
| `bibtex: undefined macro: <name>` | macro reference not defined earlier |
| `bibtex: bad macro name: <snippet>` | `@string` name does not start with a letter |
| `bibtex: missing '=' after macro name: <name>` | `@string{name value}` |
| `bibtex: missing value for macro: <name>` | `@string{name = }` |
| `bibtex: duplicate macro: <name>` | same `@string` name twice (case-insensitive) |
| `bibtex: unterminated comment` | `@comment{...` without its closing `}` |
| `bibtex: missing value for @preamble` | `@preamble{}` |
| `bibtex: expected '}' after @string` | extra token before `@string`'s closing `}` |
| `bibtex: expected '}' after @preamble` | extra token before `@preamble`'s closing `}` |
| `bibtex: missing value` | defensive fallback in the value parser; unreachable through `bib_parse` |

## 7. Test plan

`tests/test_conformance.xi` (module `bibtex_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | simple entry | type/key/field count, braced value |
| t2 | case handling | type + field names lowercased, `bib_get_field` case-insensitive, key as written |
| t3 | field order | document order, trailing comma, multi-line entry |
| t4 | nested braces | `{A {B} C}` and `{{y}}` preserved |
| t5 | quoted values | quotes stripped, braces kept, `\"` preserved verbatim |
| t6 | numbers/empty | `2020`, `3`, `{}` and `""` values |
| t7 | multi-line + ws | newline inside a value, ws around `=`, CRLF separators |
| t8 | zero fields | `@misc{a}`, `@book{b,}` and trailing comma |
| t9 | macros | `@string` definition, macro refs (exact + uppercase), `bib_get_macro` |
| t10 | macro chaining | `@String`, macro reference inside `@string` |
| t11 | pass-through | `@comment` nested body, `@preamble` quoted value |
| t12 | outside text | empty/whitespace OK; text, `%` and `{}` rejected |
| t13 | entry heads | unterminated entry, missing/bad type, missing `{`, parenthesis entry |
| t14 | unterminated | `{` value, `"` value, `@comment{` |
| t15 | unbalanced | `}` inside quotes, closing quote with open brace |
| t16 | keys | `@article{}`, `{, ...}`, junk after key |
| t17 | field syntax | missing `=`, bad field/macro name, missing value |
| t18 | duplicates | keys (case-insensitive), fields (case-insensitive), macros |
| t19 | macro errors | undefined macro, `#`, junk after value, `12ab` |
| t20 | round-trip | full document parse -> emit -> parse, emitter prefixes |
| t21 | bounds | every accessor out of range, missing lookups return `None` |
| t22 | canonical emit | exact text for entry and zero-field entry |
| t23 | key lookup | case-insensitive `bib_find_entry`, absent -> -1 |
| t24 | empty input | empty document, empty emission |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 8. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the `xiom.toml` /
`xiom.lexing` pure-parser idioms (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with `Str::from_utf8`,
`&Vec[...]`/`&mut Vec[...]` parameters) and documents these compiler-driven
choices (XIOM v0.61.3):

- `Vec[StructType]` is unsupported, so the document is ten parallel
  homogeneous vectors (no `Vec[BibEntry]`, no `Vec[BibField]`).
- Str equality between `Vec[Str]` elements goes through
  `compare.str_compare` / `compare.str_eq_ignore_case` after binding a typed
  local (BUG 17).
- Int element reads are bound to typed locals (`let start: Int = ...`).
- Tests dispatch directly (`t1()` ... `t24()`); indexed `Vec[fn]` calls are
  not used.
- Free functions only; `Ok`/`Err` values are produced either in scalar
  helpers or directly in `bib_parse`, matching the proven `xiom.toml` shape.
- `@` is the only entry introducer; no `%` comment handling exists, so text
  outside entries must be whitespace (documented in section 3.1).

## 9. Known limitations

- No LaTeX semantics: escapes, accents and math are opaque bytes.
- Quoted values must keep braces balanced, so a raw `}` cannot appear in a
  quoted value even though classic BibTeX tolerates some cases.
- Brace content is not trimmed; whitespace inside `{ ... }` is data.
- No `#` concatenation, no parenthesis entries, no built-in month macros,
  no forward macro references and no macro redefinition.
- `@comment` requires balanced braces; brace-less `@comment` lines are not
  supported.
- No `%` comments or arbitrary junk outside entries.
- No sorting, citation styles, crossref resolution, `.bib` merging, writer
  options or file I/O.
- Emitter canonicalizes layout and pool order; it does not reproduce the
  original formatting.
- Errors carry no line/column position.
