# xiom.dotenv -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.dotenv` (`src/dotenv.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free dotenv (`.env`) parser and emitter for in-memory
`Str` documents:

- `dotenv_parse` -- document -> `Result[EnvFile, Str]`,
- `dotenv_get` / `dotenv_has` -- value lookup and presence,
- `dotenv_keys` / `dotenv_len` -- key enumeration,
- `dotenv_emit` -- `EnvFile` -> dotenv text.

The byte-level rules (comment detection, quoting, escapes, trimming) follow
the widely used dotenv conventions as closely as a line-oriented, in-memory
implementation allows.

## 2. Data model

```xi
pub type EnvFile = {
  keys: Vec[Str];    // distinct keys, first-occurrence order
  values: Vec[Str];  // decoded values, index-aligned with keys
}
```

Invariants: `keys.len() == values.len()`; every key in `keys` is unique; a
duplicate assignment replaces `values[i]` in place, so the key keeps its
first position and the last assignment wins.

`Vec[StructType]` is not usable in this compiler, so the file is deliberately
flat (two homogeneous vectors) instead of a list of entry structs.

## 3. Line grammar

```
document      = *( line )                      ; LF or CRLF terminated
line          = ws* [ "export" ws+ ] pair / comment / blank
comment       = ws* "#" *( byte except LF )
pair          = key ws* "=" ws* value? [ trailing ]
trailing      = ws* "#" *( byte except LF )
key           = ( ALPHA / "_" ) *( ALPHA / DIGIT / "_" )
value         = dquote-string / squote-string / unquoted
dquote-string = '"' *( escaped / byte-except-'"'-and-'\' ) '"'
escaped       = "\n" / "\t" / "\r" / "\"" / "\\"
squote-string = "'" *( byte-except-"'" ) "'"
unquoted      = *( byte except LF )            ; see cut/trim rule below
ws            = SP | TAB
ALPHA         = "A".."Z" / "a".."z"
```

Decisions (each is covered by the conformance suite):

1. **Lines.** LF terminates a line; one trailing CR is removed so CRLF input
   parses identically. A final line without a newline is still a line.
   A UTF-8 BOM is NOT stripped and makes the first line malformed.
2. **Blank lines and comments.** A line whose first non-whitespace byte is
   `#` is a full-line comment. Blank/whitespace-only lines are skipped.
3. **`export` prefix.** The exact word `export` followed by at least one
   whitespace byte is stripped. `exportedFOO=y` is the key `exportedFOO`;
   `export=1` is the key `export`; `export` alone has no key and is
   `Err("dotenv: missing key in line: ...")`.
4. **Keys.** `[A-Za-z_][A-Za-z0-9_]*`. No spaces inside a key: `A B=1` is
   `Err("dotenv: expected '=' in line: ...")`. Keys are stored without the
   `export` prefix and compared byte-exactly (case-sensitive).
5. **Whitespace.** Space and tab are equivalent around `=`, inside the
   `export` prefix and before a trailing comment.
6. **Empty values.** `KEY=` and `KEY=   ` store `""`.
7. **Double-quoted values.** The only valid escapes are `\n` (LF), `\t`
   (TAB), `\r` (CR), `\"` and `\\`. Any other escape is
   `Err("dotenv: invalid escape in line: ...")`. A missing closing quote is
   `Err("dotenv: unterminated double quote in line: ...")`. `#` and
   whitespace inside the quotes are literal.
8. **Single-quoted values.** Taken byte-for-byte; backslashes are literal and
   the only forbidden byte is `'`. A missing closing quote is
   `Err("dotenv: unterminated single quote in line: ...")`.
9. **Unquoted values.** The value range runs from the first non-whitespace
   byte after `=` to end of line, cut short at the first `#` whose preceding
   byte is whitespace (a trailing comment). The range is then `str_trim`-ed.
   So `A=hello world` -> `hello world`, `A=two#three` keeps the `#`, and
   `A= # note` -> `""`.
10. **Text after a closing quote.** Only whitespace followed by an optional
    `#` comment may follow `"..."` or `'...'`; anything else is
    `Err("dotenv: unexpected text after quoted value in line: ...")`.
11. **Duplicates.** Not an error: last assignment wins, first position kept.
12. **Order.** `dotenv_keys` returns a fresh copy in first-occurrence order;
    mutating the result does not change the file.
13. **Emission.** One `KEY=VALUE` line per entry, `LF` separated, no trailing
    LF. A value is double-quoted when it is empty or contains space, tab, LF,
    CR, `#`, `"`, `'` or a byte >= 0x80. Inside the quotes, `\` -> `\\`,
    `"` -> `\"`, LF -> `\n`, CR -> `\r`, TAB -> `\t` are re-applied; all
    other bytes (including UTF-8 sequences) pass through verbatim. Emission
    is total: any `EnvFile` produces output that `dotenv_parse` accepts.
14. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise and never rewrites multi-byte sequences, so non-ASCII values
    round-trip byte-exact.
15. **No expansion, no multiline values.** `$VAR`, `${VAR}` and `$(cmd)` are
    literal text; a value cannot span lines except via the `\n` escape.

## 4. API signatures

```xi
pub fn dotenv_parse(text: Str) -> Result[EnvFile, Str]
pub fn dotenv_get(e: &EnvFile, key: Str) -> Option[Str]
pub fn dotenv_has(e: &EnvFile, key: Str) -> Bool
pub fn dotenv_keys(e: &EnvFile) -> Vec[Str]
pub fn dotenv_len(e: &EnvFile) -> Int
pub fn dotenv_emit(e: &EnvFile) -> Str
```

Complexity: parsing is O(total input length * distinct keys) because
duplicate detection scans the key list per assignment; lookups are O(keys);
emitting is O(total output length).

## 5. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"dotenv: "`:

| Message | Trigger |
|---|---|
| `dotenv: missing key in line: <line>` | no key after `export`/indent; `=1`; `1BAD=x` |
| `dotenv: expected '=' in line: <line>` | key not followed by `=`; `A B=1`; `not a kv line` |
| `dotenv: invalid escape in line: <line>` | `\q`, `\z` or any escape outside `n t r \ "` |
| `dotenv: unterminated double quote in line: <line>` | `A="abc` or a trailing backslash before EOL |
| `dotenv: unterminated single quote in line: <line>` | `B='abc` |
| `dotenv: unexpected text after quoted value in line: <line>` | `A="x"junk` |

## 6. Test plan

`tests/test_conformance.xi` (module `dotenv_tests`) runs 18 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | simple pairs | two entries, lookup, presence |
| t2 | empty values | `EMPTY=` and `SPACES=   ` store `""` |
| t3 | unquoted trimming | spaces/tabs around key, `=`, value |
| t4 | full-line comments | `#`/indented `#`/blank lines skipped |
| t5 | trailing comments | `#` after whitespace; `two#three` keeps its `#` |
| t6 | `#` inside quotes | double/single quoted kept; unquoted `plain#kept` |
| t7 | double-quote escapes | `\n \t \r \" \\` decoded |
| t8 | single-quoted literal | backslashes and `"` verbatim |
| t9 | `export` prefix | stripped only before whitespace; `exportedFOO` |
| t10 | duplicates | last wins, first position, key order |
| t11 | missing keys | `has=false`, `get=None`, case-sensitivity |
| t12 | key order/copy | document order; `dotenv_keys` is a copy |
| t13 | bad escapes | `\q`/`\z` are Err("dotenv: ...") |
| t14 | unterminated quotes | `A="abc`, `B='abc` are Err |
| t15 | malformed lines | no `=`, `=1`, `1BAD`, `A B`, junk after quote |
| t16 | emit quoting | empty/space/`#`/`"`/`'`/tab/non-ASCII quoted, escapes reapplied |
| t17 | emit -> parse round-trip | six shapes survive emit + reparse |
| t18 | CRLF input | `\r\n` lines parse, CR stripped |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 7. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.csv`/`xiom.toml` (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the file is two parallel homogeneous
  vectors (no `Vec[EnvFile]`).
- `Ok`/`Err` for `Result[EnvFile, Str]` are constructed only in the leaf
  helpers `_ok_env`/`_err_env`.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); values are read into typed
  locals before use.
- Tests dispatch directly (`t1()` ... `t18()`); `Vec[fn]` indexed calls are
  not used, no match pattern binds `mut`, no inline lambdas, and every
  `match` is exhaustive.
- `dotenv_parse` owns the per-line loop and mutates `EnvFile` through
  `_set_pair(&mut EnvFile, ...)`; `&EnvFile` is used by the read-only API.

## 8. Known limitations

- No variable expansion (`$VAR`, `${VAR}`, `$(cmd)` are literal text).
- No multiline values (only `\n` inside double quotes).
- No `export` round-trip (stripped on parse, never written by emit).
- No quoted/dotted keys, no key escaping, no `KEY` without `=`.
- No file I/O, cascade/chained files or `process.env` integration.
- Errors carry no line/column position (the offending line text is included).
