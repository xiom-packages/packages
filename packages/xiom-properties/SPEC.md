# xiom.properties -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.properties` (`src/properties.xi`). Pure XIOM, no FFI, no file
I/O.

## 1. Scope

A small, dependency-free Java `.properties` parser and emitter for in-memory
`Str` documents:

- `props_parse` -- document -> `Result[Props, Str]`,
- `props_get` / `props_count` -- lookup and size,
- `props_keys` -- key enumeration,
- `props_set` -- a new `Props` with one pair replaced or appended,
- `props_emit` -- `Props` -> properties text.

The byte-level rules (logical lines, continuations, separators, escapes)
follow `java.util.Properties.load` as closely as a line-oriented, in-memory
implementation allows.

## 2. Data model

```xi
pub type Props = {
  keys: Vec[Str];    // distinct keys, first-occurrence order
  values: Vec[Str];  // decoded values, index-aligned with keys
}
```

Invariants: `keys.len() == values.len()`; every key in `keys` is unique; a
duplicate assignment replaces `values[i]` in place, so the key keeps its
first position and the last assignment wins.

`Vec[StructType]` is not usable in this compiler, so the file is deliberately
flat (two homogeneous vectors) instead of a list of entry structs.

## 3. Logical-line grammar

```
document       = *( physical-line )
physical-line  = bytes* ( LF / CRLF / CR )      ; a final line without a
                                                ; terminator is still a line
line           = blank / comment / pair
comment        = ws* ( "#" / "!" ) bytes*       ; ends at the physical line
                                                ; end (a trailing backslash
                                                ; does not continue it)
blank          = ws*
pair           = ws* key [ ws* ( "=" / ":" )? ws* value ]
key            = ( escaped / byte-except-"="-":"-ws )*
value          = ( escaped / byte )*
escaped        = "\t" / "\n" / "\r" / "\f" / "\\"
               / "\u" HEX HEX HEX HEX / "\" byte
ws             = SP | TAB | FF
HEX            = "0".."9" / "a".."f" / "A".."F"
```

Decisions (each is covered by the conformance suite):

1. **Physical lines.** LF, CRLF and a lone CR each terminate a line; a single
   CR before LF is removed. A final line without a terminator is still a
   line. A trailing terminator adds no extra (blank) line.
2. **Logical lines.** While the current physical line ends with an odd number
   of backslashes, the joining backslash is removed and the next physical
   line is appended after its leading whitespace is stripped. Two trailing
   backslashes are an escaped backslash and end the logical line; a trailing
   backslash on the last line is removed.
3. **Blank lines** (only whitespace) are skipped everywhere.
4. **Comments.** A line whose first non-whitespace byte is `#` or `!` is
   ignored. Comments are detected per physical line, so a comment ending in a
   backslash does not continue; a continuation line that begins with `#` or
   `!` is data.
5. **Key.** Leading whitespace is skipped. The key runs to the first
   unescaped `=` or `:` or to the first whitespace byte. An escape pair is
   opaque to this scan, so `\=`, `\:`, `\ ` and `\uXXXX` cannot terminate the
   key.
6. **Separator.** After the key, a whitespace run and/or one optional `=` or
   `:` are consumed, followed by a whitespace run. Lines without a separator
   (`KEY`) store `""`; a line with an empty key (`=v`) is accepted.
7. **Value.** The rest of the logical line, escapes decoded, is the value.
   Trailing whitespace is kept (Java behavior); whitespace between the
   separator and the value is skipped.
8. **Case and exactness.** Keys are byte-exact and case-sensitive.
9. **Duplicates.** Not an error: last assignment wins, first position kept.
10. **Order.** `props_keys` returns a fresh copy in first-occurrence order;
    mutating the result does not change the `Props`.
11. **Immutability.** `props_set` copies and returns a new `Props`; the input
    is never modified.
12. **Emission.** One `key=value` line per entry, `LF` separated, no trailing
    LF, in insertion order. In a key every space becomes `\ ` and `=` `:`
    `#` `!` get a backslash; in a value, `=` `:` `#` `!` get a backslash only
    as the first byte and spaces only while they lead. `\` -> `\\`, LF ->
    `\n`, TAB -> `\t`, CR -> `\r`. All other bytes (including UTF-8
    sequences) pass through verbatim, so encode/parse round-trips
    byte-exact.
13. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise and never rewrites multi-byte sequences, so non-ASCII text
    round-trips byte-exact. No locale or character-set conversion is applied.
14. **No expansion, no defaults.** `${VAR}` and friends are literal text;
    there is no cascade or defaults merge.

## 4. Escape table

| Escape | Decodes to | Notes |
|---|---|---|
| `\\` | `\` (0x5C) | |
| `\n` | LF (0x0A) | |
| `\t` | TAB (0x09) | |
| `\r` | CR (0x0D) | |
| `\f` | FF (0x0C) | |
| `\uXXXX` | UTF-8 bytes of the BMP code point | 4 hex digits, case-insensitive; encoded as 1-3 UTF-8 bytes |
| `\X` | the byte `X` | Java behavior; covers `\= \: \# \! \ ` |
| `\` at EOF of a logical line | removed | logical lines never end in a lone backslash |

A `\u` escape with fewer than four following bytes inside the line, or with a
non-hex digit, is `Err("properties: malformed \\uxxxx escape in line: ...")`.

## 5. API signatures

```xi
pub fn props_parse(text: Str) -> Result[Props, Str]
pub fn props_get(p: &Props, key: Str) -> Option[Str]
pub fn props_count(p: &Props) -> Int
pub fn props_keys(p: &Props) -> Vec[Str]
pub fn props_set(p: &Props, key: Str, value: Str) -> Props
pub fn props_emit(p: &Props) -> Str
```

Complexity: parsing is O(total input length * distinct keys) because
duplicate detection scans the key list per pair; lookups are O(keys);
emitting is O(total output length).

## 6. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"properties: "`:

| Message | Trigger |
|---|---|
| `properties: malformed \uxxxx escape in line: <line>` | `\u12`, `\u00e`, `\uZZZZ`, `\u12` in a key |
| `properties: trailing backslash in line: <line>` | defensive only: logical-line joining always removes a trailing continuation backslash |

## 7. Test plan

`tests/test_conformance.xi` (module `properties_tests`) runs 21 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | simple pairs | two entries, lookup |
| t2 | `=`/`:` separators | both separators, optional surrounding whitespace |
| t3 | whitespace separator | space/tab end the key; spaces kept in the value |
| t4 | comments | `#` and `!`, indented, blank lines; `!B=2` is a comment |
| t5 | leading whitespace | spaces/tab before the key skipped |
| t6 | continuation | one continuation joins; continuation leading whitespace stripped |
| t7 | two continuations | `a\`+`b\`+`c` joins; even trailing backslashes end the line |
| t8 | short escapes | `\n \t \r \f \\` decoded (FF checked by byte) |
| t9 | `\uXXXX` | `\u00e9` -> 2 bytes, `\u4e2D` -> 3 bytes, `\u0041` -> `A` |
| t10 | malformed `\u` | truncated and non-hex escapes are Err("properties: ...") |
| t11 | escaped separators | `\=`, `\:`, `\ ` stay in the key |
| t12 | value separators | `x=y:z`, `:x`, `:`, `a=b=c` kept whole |
| t13 | duplicates | last wins, first position, key order |
| t14 | missing keys | `get=None`; keys case-sensitive |
| t15 | `props_set` replace | in-place replace, order kept, original `Props` unchanged |
| t16 | `props_set` append | new key appended, original `Props` unchanged |
| t17 | emit escaping | pinned output for controls, key specials, spaces, UTF-8 |
| t18 | emit -> parse | ten shapes survive emit + reparse |
| t19 | empty input | `""` and comment-only documents give zero entries; emit "" |
| t20 | CRLF / CR | `\r\n` lines parse; a lone `\r` terminates too |
| t21 | unknown escapes | `\q` -> `q`; `\=` `\:` `\#` `\!` `\ ` -> the byte |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 8. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.csv`/`xiom.dotenv` (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the file is two parallel homogeneous
  vectors (no `Vec[Props]`).
- `Ok`/`Err` for `Result[Props, Str]` and `Result[Str, Str]` are constructed
  only in the leaf helpers `_ok_props`/`_err_props`/`_ok_str`/`_err_str`.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); values are read into typed
  locals before use.
- Tests dispatch directly (`t1()` ... `t21()`); `Vec[fn]` indexed calls are
  not used, no match pattern binds `mut`, no inline lambdas, and every
  `match` is exhaustive.
- `props_parse` owns the line loop and mutates `Props` through
  `_set_pair(&mut Props, ...)`; `&Props` is used by the read-only API.

## 9. Known limitations

- No locale/character-set handling: no ISO-8859-1 or UTF-16 input modes; the
  input `Str` bytes are taken as-is (UTF-8 in practice).
- `\u` is BMP-only: surrogate pairs are encoded as two separate 3-byte
  sequences, not combined into one 4-byte code point.
- `props_emit` never writes `\f` or `\uXXXX`; non-ASCII text stays raw UTF-8
  and FF stays a raw byte.
- No file I/O, no defaults/cascade merge, no `${}` expansion, no
  `java.util.Properties` API.
- Comments and blank lines are parsed but never emitted, so a
  parse -> emit -> parse round trip loses them (keys and values survive).
- Errors carry the offending line text but no line/column position.
