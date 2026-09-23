# xiom.toml -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.toml` (`src/toml.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free TOML v1.0 **subset** parser for in-memory `Str`
documents. It parses a document into a flat `TomlDoc` and exposes
dotted-path lookups:

- `toml_parse` -- document -> `Result[TomlDoc, Str]`,
- `toml_has` / `toml_kind` -- presence and kind,
- `toml_get_str` / `toml_get_int` / `toml_get_bool` -- typed scalar access,
- `toml_get_str_array` / `toml_get_int_array` -- array access,
- `toml_keys` / `toml_key_count` -- entry enumeration.

Lookup keys are canonical dotted paths joined with `.` (`server.port`,
`a.b.x`). Table headers contribute their header path as a prefix; dotted keys
are already canonical. Lookups never traverse a value tree because values are
stored flat.

## 2. Non-goals

- Full TOML v1.0 conformance (multi-line strings, dates/times, floats,
  inline tables, arrays of tables, integer bases, digit separators).
- Serialization / pretty-printing back to TOML text.
- File I/O, streaming parsing, or registry integration.
- A nested value object model (`TomlValue` trees); the document is flat.
- Rich error positions (line/column); errors carry a message and, where
  useful, the offending line text.
- Any FFI.

## 3. Supported grammar

```
document       = *( blank / comment / keyval / table )
blank          = ws* EOL
comment        = ws* "#" *( any byte except LF )
keyval         = key ws* "=" ws* value ws* [ comment ]
table          = "[" ws* key ws* "]" ws* [ comment ]
key            = segment *( ws* "." ws* segment )
segment        = barekey / basic-string / literal-string
barekey        = 1*( ALPHA / DIGIT / "_" / "-" )
value          = basic-string / literal-string / integer / boolean / array
integer        = [ "-" ] 1*DIGIT
boolean        = "true" / "false"
array          = "[" ws* [ item *( ws* "," ws* item ) [ ws* "," ] ] ws* "]"
item           = basic-string / literal-string / integer
basic-string   = '"' *( escaped / UTF8-except-'"'-and-'\' ) '"'
escaped        = "\n" / "\t" / "\r" / "\"" / "\\"
literal-string = "'" *( UTF8-except-"'") "'"
ws             = SP | TAB
EOL            = LF | CRLF
```

Decisions (each is covered by the conformance suite):

1. **Lines.** Records are processed line by line. LF and CRLF terminate a
   line; a trailing CR is removed. A line without a final newline is still a
   line. Blank and whitespace-only lines are skipped.
2. **Comments.** `#` starts a comment outside strings and runs to end of
   line; it may follow a value, a table header, or an array item. A `#`
   inside a basic or literal string is literal data.
3. **Keys.** Bare keys use `A-Z a-z 0-9 _ -`. Quoted keys may be basic
   (`"my key"`) or literal (`'lit key'`); basic keys support the same escapes
   as basic string values. Whitespace around dotted segments is trimmed.
   A quoted segment is stored without its quotes.
4. **Tables.** `[a]` and `[a.b]` set the current prefix; every following
   `key = value` line is stored as `<prefix>.<key>`. A repeated table header
   is `Err("toml: duplicate table: <name>")`. `[[name]]` is explicitly
   rejected as unsupported. A table header does not nest; the prefix is
   replaced, not appended.
5. **Strings.** Basic strings decode `\n` (LF), `\t` (TAB), `\r` (CR), `\"`
   and `\\`; any other escape is malformed. Literal strings are taken
   byte-for-byte with no escapes and may not contain `'`. Neither may span
   lines.
6. **Integers.** Optional `-` followed by one or more ASCII digits. No
   leading-zero validation, no bases other than decimal, no `_` separators,
   no overflow detection. Accepted values are stored canonically (via
   `xiom.convert.int_to_string`), so `-0` reads back as `0`.
7. **Booleans.** Only the bare words `true` and `false`.
8. **Arrays.** Comma-separated strings or integers, optional trailing comma,
   arbitrary intra-line whitespace. All items must be the same kind: all
   strings -> kind 3, all integers -> kind 4. Mixed arrays, boolean items and
   nested arrays are malformed. An empty array is kind 3 with zero items.
   Arrays do not span lines.
9. **Duplicates.** The same canonical dotted path twice is
   `Err("toml: duplicate key: <path>")`; the same table header twice is
   `Err("toml: duplicate table: <name>")`. Implicit table re-opening
   (`a.b = 1` then `[a]`, or `[a]` then `a = 1`) is not modelled.
10. **Order.** Entries keep document order; `toml_keys` returns a fresh copy,
    so mutating the result does not change the document.
11. **Missing/mismatched lookups.** An absent key yields `false`, `None` or an
    empty `Vec`; a present key of another kind also yields `None`/empty.
12. **Encoding.** `Str` is treated as a UTF-8 byte buffer and all scanning is
    byte-wise, but the parser never splits or rewrites multi-byte sequences,
    so non-ASCII string content passes through byte-exact.

## 4. Data model

```xi
pub type TomlDoc = {
  keys: Vec[Str];           // dotted paths, document order
  values: Vec[Str];         // scalar text (str decoded, int canonical, bool word)
  kinds: Vec[Int];          // 0=str 1=int 2=bool 3=str-array 4=int-array
  array_items: Vec[Str];    // shared flat pool of array items
  array_starts: Vec[Int];   // entry i slice start into array_items (0 for scalars)
  array_lengths: Vec[Int];  // entry i slice length (0 for scalars)
}
```

Invariants: `keys`, `values`, `kinds`, `array_starts` and `array_lengths`
always have the same length; `array_starts[i] + array_lengths[i] <=
array_items.len()`; scalar entries have `array_starts[i] == array_lengths[i]
== 0`; for arrays `values[i] == ""`.

`Vec[StructType]` is not usable in this compiler, so the model is deliberately
flat (six homogeneous vectors) instead of a tree of structs.

## 5. API signatures

```xi
pub fn toml_parse(text: Str) -> Result[TomlDoc, Str]
pub fn toml_has(d: &TomlDoc, key: Str) -> Bool
pub fn toml_kind(d: &TomlDoc, key: Str) -> Option[Int]
pub fn toml_get_str(d: &TomlDoc, key: Str) -> Option[Str]
pub fn toml_get_int(d: &TomlDoc, key: Str) -> Option[Int]
pub fn toml_get_bool(d: &TomlDoc, key: Str) -> Option[Bool]
pub fn toml_get_str_array(d: &TomlDoc, key: Str) -> Vec[Str]
pub fn toml_get_int_array(d: &TomlDoc, key: Str) -> Vec[Int]
pub fn toml_keys(d: &TomlDoc) -> Vec[Str]
pub fn toml_key_count(d: &TomlDoc) -> Int
```

Complexity: parsing is O(total input length); lookups are O(keys) because the
document is a flat list; array getters are O(items).

## 6. Error strings

All parse failures are `Err(msg)` where `msg` starts with `"toml: "`:

| Message | Trigger |
|---|---|
| `toml: array of tables is not supported` | `[[name]]` header |
| `toml: malformed table header: <line>` | `[` line not ending in `]` |
| `toml: duplicate table: <name>` | the same header twice |
| `toml: expected 'key = value': <line>` | non-header line with no top-level `=` |
| `toml: unterminated quoted key: <s>` | `"` key without a closing quote |
| `toml: malformed quoted key: <s>` | bad escape or stray `"` in a quoted key |
| `toml: unterminated literal key: <s>` | `'` key without a closing quote |
| `toml: malformed key: <s>` | junk or a missing `.` between segments |
| `toml: empty key segment: <s>` | `a..b` or `"" = 1` |
| `toml: empty key` | `= 1` |
| `toml: duplicate key: <path>` | the same dotted path twice |
| `toml: missing value for key: <path>` | `x =` with nothing after `=` |
| `toml: malformed value for key: <path>` | unquoted junk, bad escape, `1 2`, unterminated string |
| `toml: malformed array for key: <path>` | mixed/nested/bool array, missing comma, trailing junk |

## 7. Test plan

`tests/test_conformance.xi` (module `toml_tests`) runs 21 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | string value | kind 0, lookup, `get_int` None |
| t2 | integer values | kind 1, values, `get_str` None |
| t3 | booleans | kind 2, true/false, `get_int` None |
| t4 | comments/blank lines | full-line, trailing, `#` inside strings, key count |
| t5 | dotted keys | paths, values, document order |
| t6 | `[server]` prefix | `server.*`, bare key absent |
| t7 | nested `[a.b]` / `[a.c]` | nested paths |
| t8 | quoted keys | basic + literal keys stored unquoted, order |
| t9 | basic escapes | `\n \t \" \\` decoded, one entry |
| t10 | literal strings | bytes verbatim (backslashes, quotes) |
| t11 | negative/zero ints | `-42`, `0`, `-7` |
| t12 | string arrays | quoted + literal items, escaped item |
| t13 | int arrays | values, empty array kind 3, trailing comma |
| t14 | arrays in tables | `svc.ports`, mixed/nested/bool arrays rejected |
| t15 | duplicate keys | plain, dotted, table-scoped |
| t16 | duplicate tables | header twice; duplicate key inside a table |
| t17 | malformed lines | no `=`, empty key, unclosed header, `1 2`, junk after `]`, `[[...]]`, unterminated string |
| t18 | `toml_keys` | order, copy semantics, empty/comment-only docs |
| t19 | missing lookups | `false`/`None`/empty for every accessor |
| t20 | kind enforcement | cross-kind getters return `None`/empty |
| t21 | whitespace tolerance | spaces around `=`, in `[ sec ]` |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 8. Compiler / stdlib notes

No unsafe code and no FFI. The implementation deliberately follows the
just-landed `xiom.csv` pure-parser idioms (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with `Str::from_utf8`,
`&Vec[...]` parameters) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the document is six parallel
  homogeneous vectors (no `Vec[TomlDoc]`, no `Vec[TomlEntry]`).
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17).
- Tests dispatch directly (`t1()` ... `t21()`); `Vec[fn]` indexed calls are
  not used, and match patterns bind no `mut`.
- `toml_parse` is a single function that owns the per-line loop: each line
  mutates the six parallel vectors plus the table list, and splitting that
  state into a helper would require a struct-typed out-parameter the compiler
  does not support reliably. `&mut TomlDoc` is used only by two same-module
  append helpers.
- Cross-module `&TomlDoc` parameters and `Result[TomlDoc, Str]` payloads
  compiled cleanly under v0.61.3; no `Ok`/`Err` is constructed inside a
  function whose declared return type is a struct.

## 9. Known limitations

- Flat namespace: `"a.b" = 1` and `a.b = 1` both canonicalize to `a.b`.
- No multi-line strings, dates/times, floats, inline tables, arrays of
  tables, nested arrays, boolean arrays, non-decimal integers, `_`
  separators, `\u`/`\U` escapes.
- No leading-zero or overflow validation for integers.
- Duplicate detection is per exact dotted path; implicit-table semantics are
  not enforced.
- No writer/serializer and no file I/O API.
- Errors carry no line/column position.
