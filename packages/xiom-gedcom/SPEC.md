# xiom.gedcom -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.gedcom` (`src/gedcom.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free codec for the *line layer* of a GEDCOM 5.5.1
transmission held in memory as a `Str`:

- `gedcom_parse` -- document -> `Result[Gedcom, Str]`,
- `gedcom_line_count` / `gedcom_level` / `gedcom_xref` / `gedcom_tag` /
  `gedcom_value` / `gedcom_parent` -- per-line accessors,
- `gedcom_first_tag` / `gedcom_subtree_end` -- lookup and tree-range helpers,
- `gedcom_is_pointer` -- pointer-value predicate,
- `gedcom_join_text` -- CONT/CONC continuation join helper,
- `gedcom_emit` -- canonical emission.

The module decodes no records semantically (no HEAD/INDI/FAM validation, no
pointer-target resolution), performs no charset conversion (UTF-8 bytes pass
through), and does not cover GEDCOM 7 differences. It answers "what are the
lines and their tree shape?" and nothing more.

## 2. Data model

```xi
pub type Gedcom = {
  levels: Vec[Int];   // level of each line, 0..9999999
  xrefs: Vec[Str];    // xref id incl. "@"s; "" when the line has none
  tags: Vec[Str];     // tag, verbatim (case preserved)
  values: Vec[Str];   // value, verbatim; "" when absent
  parents: Vec[Int];  // parent line index; -1 for a level-0 line
}
```

Invariants: all five vectors have the same length and are index-aligned by
line number (0-based, document order); `xrefs[i]` is `""` exactly when line
`i` has no xref id; `parents[i]` is `-1` exactly for level-0 lines and
otherwise the index of the nearest preceding line at level `levels[i] - 1`
(computed during parsing, never stored redundantly elsewhere). Zero-length
input lines are not stored. `Vec[StructType]` is not usable in this compiler,
so the transmission is deliberately flat (five homogeneous vectors) instead
of a list of line structs.

## 3. Line grammar

```
document = *( line )                        ; LF- or CRLF-terminated
line     = level [ sep xref ] sep tag [ sep value ]
level    = 1*7DIGIT
xref     = "@" 1*64( ALPHA / DIGIT / "_" ) "@"
tag      = 1*31( ALPHA / DIGIT / "_" )
sep      = 1*( SP / TAB )
value    = *( byte except LF )              ; verbatim
```

Parsing decisions (each is covered by the conformance suite):

1. **Lines.** LF terminates a line; one trailing CR is removed so CRLF input
   parses identically. A final line without a terminator is still a line. A
   lone CR is **not** a terminator: it stays inside the line and becomes part
   of a value when it appears after the tag. A UTF-8 BOM is not stripped; its
   bytes are text before the level.
2. **Blank lines.** A zero-length line is ignored (the GEDCOM record
   separator); it is not stored and does not affect levels. A line containing
   only spaces/tabs is an error (see 3). Empty input parses as a `Gedcom`
   with zero lines.
3. **Text before level.** The first byte of a non-empty line must be an ASCII
   digit; anything else (including leading spaces/tabs, a BOM or a bare
   `HEAD`) is `Err("gedcom: text before level in line: <line>")`.
4. **Level.** 1 to 7 ASCII digits, parsed as a decimal non-negative integer
   (`0`..`9999999`); leading zeros are tolerated and canonicalize away on
   emit. A digit run followed by anything other than a space, a tab or the
   end of line (e.g. `0HEAD`, `1.5`, `0@I1@`) is
   `Err("gedcom: bad level digits in line: <line>")`.
5. **Separators.** Fields are separated by one or more spaces/tabs; between
   the level and the tag (and between the xref and the tag) the whole
   whitespace run is skipped. Exactly **one** separator byte after the tag
   belongs to the grammar; everything after it -- including any further
   leading whitespace -- is the verbatim value (see 7). A line that ends after
   the level, or after the xref, is `Err("gedcom: missing tag in line: <line>")`.
6. **Xref id.** A token whose first byte is `@` must be exactly `@id@` with an
   id of 1..64 bytes of `[A-Za-z0-9_]`; the id is stored with both `@`
   delimiters and is never empty. Any other `@`-initial token (`@I1`, `@@`,
   `@I-1@`, `@I1@INDI`, `@ @` after tokenizing) is
   `Err("gedcom: malformed xref in line: <line>")`. A valid xref token not
   followed by a tag is `missing tag`. Xref ids are byte-exact and
   case-sensitive.
7. **Tag.** All other lines: the next whitespace-delimited token is the tag.
   It must be 1..31 bytes of `[A-Za-z0-9_]` (GEDCOM 5.5.1 limit), stored
   verbatim with its case; a tag with a forbidden byte (`-`, `@`, non-ASCII)
   or more than 31 bytes is `Err("gedcom: bad tag in line: <line>")`.
8. **Value.** Everything after the single separator byte that follows the tag
   is the value, byte for byte, and may be empty. It may contain spaces, tabs,
   slashes and `@`; trailing whitespace is preserved. `0 NOTE ` (one trailing
   space) has value `""`; `0 NOTE  x` has value `" x"`. Pointers such as
   `@I1@` are values like any other and are never dereferenced or rewritten.
9. **Nesting.** The first parsed line must be level 0, and every later line's
   level must be at most the previous line's level + 1; violations are
   `Err("gedcom: level jump in line: <line>")`. Level 0 starts a new record;
   a level may drop back to any smaller value (sibling, ancestor or record
   boundary).
10. **Parents.** `parents[i]` is the last line before `i` whose level is
    `levels[i] - 1`; it is `-1` for level 0. Because levels rise by at most
    one and the first line is level 0, every level-`L` line (`L > 0`) is
    guaranteed to have a parent. The parent index is computed in the same
    single pass as parsing and is always `>= 0` for `L > 0`.
11. **Pointers.** `gedcom_is_pointer(v)` is true exactly when `v` is
    syntactically `@id@` with an id of 1..64 bytes of `[A-Za-z0-9_]` -- the
    same shape the parser accepts for an xref field. `"I1"`, `"@@@"`,
    `"@I 1@"`, `"@I-1@"` and `"John /Doe/"` are not pointers. The predicate
    classifies; it never converts or resolves.
12. **CONT/CONC joining.** `gedcom_join_text(g, i)` starts from `values[i]`
    and scans the direct children of `i` in order: a `CONT` child appends
    LF + its value, a `CONC` child appends its value verbatim. Scanning stops
    at the first direct child with any other tag; descendants of continuation
    children are skipped. An out-of-range `i` yields `""`.
13. **Emission.** Canonical form: `level [xref] tag [value]`, fields separated
    by exactly one space; a missing xref or empty value contributes no
    separator; every line is LF-terminated, including the last; an empty
    document emits `""`. Values are written verbatim, so canonical emission of
    a parsed document is byte-stable and `parse(emit(g))` restores `g`.
14. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise, only ASCII bytes are special, and no byte sequence is ever
    split or rewritten. Non-ASCII bytes pass through values and emission.

## 4. API signatures

```xi
pub fn gedcom_parse(text: Str) -> Result[Gedcom, Str]
pub fn gedcom_line_count(g: &Gedcom) -> Int
pub fn gedcom_level(g: &Gedcom, i: Int) -> Int
pub fn gedcom_xref(g: &Gedcom, i: Int) -> Option[Str]
pub fn gedcom_tag(g: &Gedcom, i: Int) -> Str
pub fn gedcom_value(g: &Gedcom, i: Int) -> Str
pub fn gedcom_parent(g: &Gedcom, i: Int) -> Int
pub fn gedcom_first_tag(g: &Gedcom, tag: Str) -> Option[Int]
pub fn gedcom_subtree_end(g: &Gedcom, i: Int) -> Int
pub fn gedcom_is_pointer(v: Str) -> Bool
pub fn gedcom_join_text(g: &Gedcom, i: Int) -> Str
pub fn gedcom_emit(g: &Gedcom) -> Str
```

Accessor sentinels: out-of-range `i` yields `-1` (`gedcom_level`,
`gedcom_parent`), `""` (`gedcom_tag`, `gedcom_value`), `None`
(`gedcom_xref`, `gedcom_first_tag`) and the line count
(`gedcom_subtree_end`); `gedcom_join_text` yields `""`. A line that exists can
never return these sentinels for `gedcom_level` because stored levels are
non-negative.

Complexity: `gedcom_parse` and `gedcom_emit` are O(input/output length);
`gedcom_level`/`gedcom_xref`/`gedcom_tag`/`gedcom_value`/`gedcom_parent`
are O(1); `gedcom_first_tag` is O(line count); `gedcom_subtree_end` and
`gedcom_join_text` are O(subtree size).

## 5. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"gedcom: "`:

| Message | Trigger |
|---|---|
| `gedcom: text before level in line: <line>` | `HEAD`, ` 0 HEAD`, `\t0 HEAD`, a whitespace-only line, a BOM-led line |
| `gedcom: bad level digits in line: <line>` | `0HEAD`, `1x`, `1.5 NAME x`, `0@I1@ INDI`, a level of 8+ digits |
| `gedcom: level jump in line: <line>` | first line not level 0 (`1 NAME x`); level rising by 2+ (`0 HEAD` then `2 SOUR x`) |
| `gedcom: malformed xref in line: <line>` | `0 @I1 INDI`, `0 @@ INDI`, `0 @I-1@ INDI`, `0 @I1@INDI`, `0 @ INDI` |
| `gedcom: bad tag in line: <line>` | `0 BAD-TAG`, `0 NA@ME x`, `0 TÄG x`, a tag of 32+ bytes |
| `gedcom: missing tag in line: <line>` | `0`, `0   `, `0 @I1@`, `0 @I1@   ` |

Emission, accessors and `gedcom_is_pointer`/`gedcom_join_text` are total for
any `Gedcom` value.

## 6. Test plan

`tests/test_conformance.xi` (module `gedcom_tests`) runs 23 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | sample accessors | 16 lines; levels, tags and values at known indices |
| t2 | xrefs and pointers | xref `Some`/`None`; `@F1@`/`@I1@` values verbatim; pointer predicate |
| t3 | parents | nearest level-1 ancestor; `-1` for records |
| t4 | subtree ranges | record/leaf ranges; out-of-range returns the line count |
| t5 | first_tag | first byte-equal tag; case-sensitive; missing -> `None` |
| t6 | join_text | CONT -> LF + value, CONC -> value; stop at other tag; out-of-range `""` |
| t7 | canonical emit | sample round-trips byte-exactly; empty document emits `""` |
| t8 | loose separators | runs of spaces/tabs collapse to one space; value `" padded"` kept |
| t9 | CRLF | CR stripped; CRLF input parses and emits canonically |
| t10 | blank lines | zero-length lines ignored; empty and all-blank input -> 0 lines |
| t11 | text before level | leading text/space/tab, whitespace-only lines; exact message |
| t12 | bad level digits | `0HEAD`, `1x`, 8 digits, glued xref; 7 leading zeros accepted |
| t13 | level jump | first line level 0; rise by one only; downward jumps valid |
| t14 | malformed xref | unclosed, empty, bad byte, glued tag, lone `@`; exact message |
| t15 | bad tag | `-`, `@`, non-ASCII, 32 bytes are Err; 31 bytes accepted |
| t16 | missing tag | level only, trailing spaces, xref only |
| t17 | empty values | absent and empty values both `""`; emit drops the separator |
| t18 | round trip | `parse -> emit -> parse` agrees on every field, byte-stable emit |
| t19 | emit stability | loosely spaced CRLF input canonicalizes and stays stable |
| t20 | tag alphabet | `1SOUR`, `_CUSTOM`, `Head` and `@X_Y9@` accepted verbatim |
| t21 | out-of-range | every accessor sentinel |
| t22 | nesting depth | deep chains keep parents; level 0 starts a new record |
| t23 | non-ASCII | `café`/`über` bytes pass through values and emission |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 7. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.eml`/`xiom.ini` (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so storage is five parallel homogeneous
  vectors (no `Vec[GedcomLine]`).
- `Ok`/`Err` for `Result[Gedcom, Str]` are constructed only in the leaf
  helpers `_ok_gedcom`/`_err_gedcom`.
- One line is decoded by `_scan_line`, which returns the small private struct
  `LineScan` (ok/err/level/xref/tag/value); struct-by-value returns are used
  (structs are fine by value; only `Vec[StructType]` is restricted).
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); values are read into typed
  locals before use.
- Tests dispatch directly (`t1()` ... `t23()`); `Vec[fn]` indexed calls are
  not used, no match pattern binds `mut`, no inline lambdas, and every
  `match` is exhaustive.
- `gedcom_parse` owns the per-line loop, the level-jump validation, the
  parent computation and the five parallel pushes; the read-only API borrows
  `&Gedcom`.

## 8. Known limitations

- No semantic validation: record grammar (HEAD/INDI/FAM), required tags,
  duplicate xref detection and pointer-target resolution are left to callers.
- No charset conversion: bytes are opaque; no BOM stripping, no ANSEL /
  UNICODE transformations; CR-only line endings are not recognized.
- No GEDCOM 7 coverage: section/extension rules and the GEDCOM 7 pointer and
  escaping differences are out of scope.
- Zero-length lines are dropped, not preserved; emission never writes them.
- Non-canonical spacing and leading zeros canonicalize on emit; a parsed
  document itself always emits byte-stably.
- Errors carry no line/column position (the offending line text is included).
- A hand-built `Gedcom` is not validated; a value containing LF would split
  into two lines on re-parse (parsed values can never contain LF).
