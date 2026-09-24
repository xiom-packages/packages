# xiom.yaml -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.yaml` (`src/yaml.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free YAML **subset** parser for in-memory `Str` documents.
It parses a document into a flat `YamlDoc` and exposes dotted-path lookups:

- `yaml_parse` -- document -> `Result[YamlDoc, Str]`,
- `yaml_has` / `yaml_kind` -- presence and kind,
- `yaml_get_str` / `yaml_get_int` / `yaml_get_bool` -- typed scalar access,
- `yaml_get_str_list` -- list access,
- `yaml_keys` / `yaml_key_count` -- entry enumeration.

Lookup keys are canonical dotted paths joined with `.` (`server.port`,
`a.b.c.d.e`). A nested mapping contributes its key path as a prefix; mapping
containers are implicit and have no entry of their own (like TOML table
headers). Lookups never traverse a value tree because values are stored flat.

## 2. Non-goals

- Full YAML conformance (anchors/aliases, tags, directives, multi-document
  streams, merge keys, block scalars `|`/`>`, flow mappings `{...}`, nested
  flow collections, complex keys, quoted keys).
- Serialization / pretty-printing back to YAML text.
- File I/O, streaming parsing, or event-based parsing.
- A nested value object model (`YamlValue` trees); the document is flat.
- Rich error positions (line/column); errors carry a message and, where
  useful, the offending trimmed line or the dotted path.
- Any FFI.

## 3. Supported grammar

```
document     = *( blank / comment / entry )
blank        = ws* EOL
comment      = ws* "#" *( any byte except LF )
entry        = key ":" ws* [ scalar / inline-list ] [ ws* comment ]   -- mapping line
             | "-" ws+ item                                          -- block list item
key          = plain text up to the first ":" (trimmed; non-empty)
scalar       = plain / single-quoted / double-quoted / integer / boolean / null
plain        = 1*( any byte except the unsupported-map forms )
single-quoted= "'" *( UTF8 except "'" ) "'"
double-quoted= '"' *( escaped / UTF8 except '"' and '\' ) '"'
escaped      = "\n" / "\t" / "\"" / "\\"
integer      = [ "-" ] 1*DIGIT
boolean      = "true" / "false"
null         = "null" / "~"
inline-list  = "[" ws* [ item *( ws* "," ws* item ) [ ws* "," ] ] ws* "]"
item         = scalar (same forms; no nested collections)
ws           = SP | TAB
EOL          = LF | CRLF
```

Decisions (each is covered by the conformance suite):

1. **Lines.** The document is processed line by line. LF and CRLF terminate a
   line; a trailing CR is removed. A line without a final newline is still a
   line. Blank and whitespace-only lines are skipped.
2. **Comments.** `#` starts a comment when it is at the line start or
   preceded by a space/tab and outside a quoted region; it runs to end of
   line. A quoted region opens at a quote that is at the line start or right
   after a space, tab, `:`, `,`, `[` or `-`; a stray quote inside a plain
   scalar does not open one, so `frag: c#d` keeps `c#d` and
   `frag: a"b # c` comments out ` # c`.
3. **Keys.** Plain text before the first `:`, trimmed, non-empty. Quoted
   keys (`"a":`) are rejected as unsupported. The full dotted path is
   `<parent prefix>.<key>`, or `<key>` at the root. Whitespace around `:` and
   the value is trimmed.
4. **Values.** `key: value` stores a scalar or inline list. `key:` with an
   empty value is a *pending* key: if the next content line is indented
   deeper it opens a child block; otherwise the key is `null`. A pending key
   at end of input is `null`.
5. **Indentation.** See section 4. Spaces only; a tab in the leading
   whitespace of a content line is an error. The indentation step is fixed by
   the first nested level and must be used by every nested level.
6. **Block lists.** A child block whose first line starts with `- ` is a
   block list: one string item per line at the same indent. `- ` with no
   item text, an item that looks like a nested collection (`[`/`{`, a nested
   `- ` indicator) or like a mapping (`": "` or a trailing `:`) is a
   malformed list item. A non-item line at a list level is also malformed.
   List items are stored as decoded text (quoted items decode; plain items
   are verbatim), never as numbers or booleans.
7. **Inline lists.** `[a, b]` holds comma-separated scalar items with
   optional surrounding whitespace, an optional trailing comma and an empty
   form `[]`. Items follow the block-item rules. An unclosed list, an empty
   item, junk after `]`, a nested collection or a mapping item are malformed.
8. **Strings.** Double-quoted strings decode `\n` (LF), `\t` (TAB), `\"` and
   `\\`; any other escape is `Err("yaml: invalid escape: ...")`. Single-quoted
   strings are taken byte-for-byte with no escapes and may not contain a
   quote (`''` doubling is not supported). A quoted scalar must close at the
   end of the value/item; trailing text is
   `Err("yaml: unexpected text after quoted value: ...")`, a missing close is
   `Err("yaml: unterminated quote: ...")`. Neither spans lines.
9. **Scalars.** `true`/`false` -> kind 2; `null`/`~` -> kind 3 (stored as
   `""`); optional `-` followed by digits -> kind 1, stored canonically via
   `xiom.convert.int_to_string` (`007` -> `7`, `-0` -> `0`); anything else
   non-quoted is kind 0, stored verbatim, unless it carries unsupported
   mapping/sequence syntax (`": "`, trailing `:`, a leading `{`, a leading
   `- `), which is `Err("yaml: malformed value for key: <path>")`.
10. **Duplicates.** The same canonical dotted path twice -- whether leaf or
    container -- is `Err("yaml: duplicate key: <path>")`. Re-opening a
    mapping (`a:` / `  b: 1` then `a:` again) is an error as well.
11. **Order.** Entries keep document order; `yaml_keys` returns a fresh copy,
    so mutating the result does not change the document.
12. **Missing/mismatched lookups.** An absent key yields `false`, `None` or an
    empty `Vec`; a present key of another kind also yields `None`/empty.
    Mapping containers have no entry, so `yaml_has(d, "server")` is false for
    a document that only defines `server.host`.
13. **Encoding.** `Str` is treated as a UTF-8 byte buffer and all scanning is
    byte-wise, but the parser never splits or rewrites multi-byte sequences,
    so non-ASCII content passes through byte-exact.

## 4. Indentation model

- The root level starts at column 0. A content line with leading spaces
  before any root key (` k: 1`) is an indentation jump error.
- The leading whitespace of a content line may contain only spaces. If a tab
  is reached before the first non-whitespace byte, the line is
  `Err("yaml: tab indentation is not allowed: <line>")`. Tabs after the
  content starts, inside strings, and in blank/comment-only lines are fine.
- **Step.** The first nested level fixes `step = child indent - parent
  indent` (for example 2). Every later child level must sit exactly `step`
  below its parent. A child deeper or shallower than `parent + step` is
  `Err("yaml: indentation jump: <line>")`.
- **Jump.** A line indented deeper than the current level without a pending
  `key:` above it is an indentation jump. A dedent must land on a level that
  is currently open (or the root); any other column is an indentation jump.
- **Blocks.** A pending key followed by a deeper line opens a child level:
  a block list when that line starts with `- `, otherwise a mapping. The
  level ends at the next line indented less than it, and all its lines must
  keep the level's kind (mixing items and keys is `malformed list item`).
- Lists are flat: an item cannot open a deeper level.

Example (step 2, three levels, a block list and an inline list):

```
server:            # pending -> child mapping
  host: localhost  # server.host, str
  port: 9000       # server.port, int
  tags: [a, b]     # server.tags, str-list
ports:             # pending -> child list
  - 80             # ports[0]
  - 443            # ports[1]
```

Entries: `server.host`, `server.port`, `server.tags`, `ports`; there are no
entries for `server` or `ports` beyond the list entry itself.

## 5. Data model

```xi
pub type YamlDoc = {
  keys: Vec[Str];          // dotted paths, document order
  values: Vec[Str];        // scalar text (str decoded, int canonical, bool word, "" for null)
  kinds: Vec[Int];         // 0=str 1=int 2=bool 3=null 4=str-list
  list_items: Vec[Str];    // shared flat pool of list items
  list_starts: Vec[Int];   // entry i slice start into list_items (0 for scalars)
  list_lengths: Vec[Int];  // entry i slice length (0 for scalars)
}
```

Invariants: `keys`, `values`, `kinds`, `list_starts` and `list_lengths`
always have the same length; `list_starts[i] + list_lengths[i] <=
list_items.len()`; scalar entries have `list_starts[i] == list_lengths[i] ==
0`; for lists `values[i] == ""`.

`Vec[StructType]` is not usable in this compiler, so the model is deliberately
flat (six homogeneous vectors) instead of a tree of structs.

## 6. API signatures

```xi
pub fn yaml_parse(text: Str) -> Result[YamlDoc, Str]
pub fn yaml_has(d: &YamlDoc, key: Str) -> Bool
pub fn yaml_kind(d: &YamlDoc, key: Str) -> Option[Int]
pub fn yaml_get_str(d: &YamlDoc, key: Str) -> Option[Str]
pub fn yaml_get_int(d: &YamlDoc, key: Str) -> Option[Int]
pub fn yaml_get_bool(d: &YamlDoc, key: Str) -> Option[Bool]
pub fn yaml_get_str_list(d: &YamlDoc, key: Str) -> Vec[Str]
pub fn yaml_keys(d: &YamlDoc) -> Vec[Str]
pub fn yaml_key_count(d: &YamlDoc) -> Int
```

Complexity: parsing is O(total input length * key count) because duplicate
detection scans the seen-path list per key line (O(total input length) with a
hash index); lookups are O(keys) because the document is a flat list; list
getters are O(items).

## 7. Error strings

All parse failures are `Err(msg)` where `msg` starts with `"yaml: "`:

| Message | Trigger |
|---|---|
| `yaml: tab indentation is not allowed: <line>` | a content line whose leading whitespace contains a tab |
| `yaml: indentation jump: <line>` | deeper line with no pending key, a child level not exactly `parent + step`, a dedent to a column that is not open, or an indented root line |
| `yaml: duplicate key: <path>` | the same canonical dotted path (leaf or container) twice |
| `yaml: malformed list item: <line>` | `-` outside a block list, an empty item, an item with mapping/nested-collection syntax, or a key line at a list level |
| `yaml: unterminated quote: <line>` | a `"` or `'` scalar without a closing quote (also inside a list) |
| `yaml: invalid escape: <line>` | a double-quoted `\x` other than `\n \t \" \\` |
| `yaml: unexpected text after quoted value: <line>` | text after a closing quote |
| `yaml: malformed inline list: <line>` | unclosed `[`, empty item, missing comma, junk after `]`, nested flow or mapping item |
| `yaml: expected 'key: value': <line>` | a non-list line with no `:` |
| `yaml: empty key: <line>` | a line starting with `:` |
| `yaml: quoted keys are not supported: <line>` | a key starting with `"` or `'` |
| `yaml: malformed value for key: <path>` | a plain value with mapping syntax, a leading `{`, or a `- ` sequence indicator |

## 8. Test plan

`tests/test_conformance.xi` (module `yaml_tests`) runs 25 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | plain string scalar | kind 0, lookup, `get_int` None, count |
| t2 | integers | kinds, `8080` / `-42` / `0`, `007` -> `7`, `-0` -> `0`, cross-kind getters |
| t3 | booleans | kind 2, true/false, `get_int`/`get_str` None |
| t4 | null | `null`, `~`, dangling `key:` at EOF -> kind 3, all getters None |
| t5 | single-quoted | literal bytes, backslashes/quotes/`#` kept |
| t6 | double-quoted escapes | `\n \t \" \\` decoded, quoted digits stay str |
| t7 | comments | full-line, indented, trailing, `#` in quotes, `c#d` kept |
| t8 | blank lines / empty input | skipped lines, empty/whitespace/comment-only docs |
| t9 | nested mappings | `server.host`/`server.port`/`server.tls.enabled`, containers absent |
| t10 | deep nesting | 5 levels with step 2, order and count pinned |
| t11 | block lists | kind 4, items `80`/`443`, scalar getters None |
| t12 | block list items | decoded quotes, plain text and `42` kept as text |
| t13 | inline lists | `[a, b, c]`, `[1, -2, 3]`, `[]`, trailing comma, quoted items |
| t14 | CRLF | keys, nested value and list parse |
| t15 | order/copy | document order; mutating `yaml_keys` does not mutate the doc |
| t16 | missing keys | `false`/`None`/empty for every accessor |
| t17 | kind enforcement | cross-kind getters return `None`/empty; kinds 0-4 |
| t18 | indentation errors | shallow jump, deep jump, bad dedent, inconsistent step, indented root |
| t19 | tab indentation | tab indent Err; tabs in comments and content are not errors |
| t20 | duplicate keys | plain, nested, container re-open, container vs list/leaf |
| t21 | quote errors | unterminated (incl. in list), bad escape, trailing text |
| t22 | malformed list items | root `-`, unindented item, empty item, mixed level, nested/map items |
| t23 | malformed inline lists | unclosed, empty item, junk, `{}` item, mapping item |
| t24 | structural errors | no colon, empty key, quoted key, `b: c` value, `{x}`, `- x` |
| t25 | flat namespace | `a.b: 1` and `a:`/`  b: 2` both resolve to `a.b` |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 9. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the pure-parser idioms
already green in `xiom.csv`, `xiom.toml` and `xiom.dotenv` and documents these
compiler-driven choices:

- `Vec[StructType]` is unsupported, so the document is six parallel
  homogeneous vectors (no `Vec[YamlDoc]`, no `Vec[YamlEntry]`).
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); every Vec read is stored in a
  typed local first.
- Byte reads go through `_byte()`, which widens with `as Int` and `& 0xFF`
  before any comparison.
- `Ok`/`Err` for `Result[YamlDoc, Str]` are constructed only in the tiny leaf
  helpers `_ok_doc`/`_err_doc`.
- Tests dispatch directly (`t1()` ... `t25()`); `Vec[fn]` indexed calls are
  not used, and match patterns bind no `mut`.
- `yaml_parse` is a single function that owns the per-line loop; it keeps the
  indentation stack in parallel `Vec[Int]`/`Vec[Str]`/`Vec[Int]` buffers with
  a logical `depth` (no `pop()`) plus `pending`/`step` scalars. Splitting that
  state into a helper would require a struct-typed out-parameter the compiler
  does not support reliably. `&mut YamlDoc` is used only by same-module
  append helpers.
- Cross-module `&YamlDoc` parameters and `Result[YamlDoc, Str]` payloads
  compiled cleanly under v0.61.3; no `Ok`/`Err` is constructed inside a
  function whose declared return type is a struct.

## 10. Known limitations

- Flat namespace: `"a.b"` style dotted keys and nested mappings canonicalize
  to the same path.
- Mapping containers have no entry; re-opening a container is a duplicate-key
  error, and `yaml_has` is false for container paths.
- Spaces-only indentation with one global step; the root must start at
  column 0. No tabs, no alignment flexibility.
- List items (block and inline) are scalars; nested maps, nested lists and
  flow collections inside list items are malformed.
- No anchors/aliases, tags, directives, multi-document streams, merge keys,
  block scalars (`|`, `>`), flow mappings, quoted keys or complex keys.
- Single-quoted strings cannot contain a quote (`''` doubling unsupported);
  double-quoted escapes are limited to `\n \t \" \\` (no `\r`, `\uXXXX`).
- Plain scalars are stored verbatim; no implicit typing beyond
  `true`/`false`, `null`/`~` and decimal integers, and integers have no
  overflow validation.
- Errors carry no line/column position (messages carry the offending trimmed
  line or the dotted path).
- No writer/serializer and no file I/O API.
