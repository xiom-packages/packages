# xiom.vdf -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.vdf` (`src/vdf.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free Valve KeyValues (VDF) text codec for in-memory `Str`
documents:

- `vdf_parse` -- VDF text -> `Result[Vdf, Str]`,
- `vdf_root_keys` / `vdf_child_keys` -- key order per block,
- `vdf_has` -- path presence,
- `vdf_get_str` / `vdf_get_int` / `vdf_get_bool` -- typed lookup,
- `vdf_emit` -- `Vdf` -> canonical VDF text.

The accepted language is the common quoted text dialect: nested quoted pairs
and blocks, `//` line comments, quoted strings with `\n` `\t` `\"` `\\`
escapes, and unquoted tokens accepted only as values. See section 4 for the
exact grammar.

## 2. Non-goals

- No binary VDF (the byte-oriented `kv`/`.vdf` format): this module is text
  only.
- No conditionals, platform tags or macros: `[$WIN32]`, `[!$OSX]`, `#base`
  and `#include` are not interpreted.
- No app-specific schemas or key names: any key/value is accepted.
- No file I/O, streaming, async or registry integration.
- No serialization of anything but the documented canonical form: comments
  are not preserved, block layout/comments are not round-tripped (only the
  tree is).

## 3. Data model

```xi
pub type Vdf = {
  keys: Vec[Str];         // node key; node 0 is the virtual root ("")
  values: Vec[Str];       // scalar text for value nodes, "" for blocks
  kinds: Vec[Int];        // 0 = value, 1 = block; node 0 is a block
  child_firsts: Vec[Int]; // first direct child, -1 when there are none
  child_counts: Vec[Int]; // number of direct children (0 for values)
}
```

Invariants:

1. The five vectors are index-aligned; node 0 is the virtual root block with
   the empty key. It is never emitted but makes every other node a child of
   exactly one block.
2. A block node `i` owns the direct-child range
   `[child_firsts[i], child_firsts[i] + child_counts[i])` over the same flat
   arrays. Sibling ranges preserve document order.
3. Value nodes have `child_firsts = -1` and `child_counts = 0`.
4. Storage order is breadth-first: the parser first builds a temporary
   first/last/next-child structure and then flattens it with a FIFO queue, so
   each block's direct children end up contiguous. Both passes are linear.

`Vec[StructType]` is not usable in this compiler, so the document is
deliberately flat (five homogeneous parallel vectors) instead of a node tree.
Node indices are an implementation detail: no public function exposes a raw
index, so callers cannot depend on the storage order.

## 4. Grammar

```
document   = *( ws / comment / pair / block ) ;
pair       = key ws* value ;
block      = key ws* "{" document "}" ;
key        = quoted ;
value      = quoted / token ;
quoted     = '"' *( escaped / byte-except( '"' "\\" LF CR ) ) '"' ;
escaped    = "\\" ( "n" / "t" / '"' / "\\" ) ;
token      = 1*( byte-except( SP TAB LF CR "{" "}" ) ) ;
comment    = "//" *( byte-except( LF ) ) ;
ws         = SP | TAB | LF | CR ;
```

Byte-level decisions (each is covered by the conformance suite):

1. **Layout.** Documents are a token stream; line structure is irrelevant
   except for `//` comments, which end at LF (or EOF). CR is whitespace
   outside quoted strings, so CRLF input parses identically. A UTF-8 BOM is
   NOT stripped and becomes part of the first token.
2. **Keys.** A key must be quoted. The decoded key must not be empty
   (`Err("vdf: empty key")`). An unquoted token where a key is expected is
   `Err("vdf: stray token: <token>")` -- this is how unquoted conditionals
   such as `[$WIN32]` are rejected.
3. **Values.** A value is either a quoted string (decoded) or an unquoted
   token stored byte-exact. Unquoted tokens run until whitespace, `{` or `}`
   and may contain `//` (only a token-initial `//` starts a comment). A key
   followed directly by EOF or `}` is `Err("vdf: key without value: <key>")`.
4. **Blocks.** `key {` opens a block; `}` closes the innermost open block.
   EOF with open blocks is `Err("vdf: unterminated block")`; a `}` with no
   open block is `Err("vdf: unexpected '}'")`. A `}` immediately after a key
   is still a missing value: `Err("vdf: key without value: <key>")`.
5. **Quoted strings.** `\n`, `\t`, `\"` and `\\` decode to LF, TAB, `"` and
   `\`; any other escape is `Err("vdf: bad escape: <seq>")`; EOF, LF or CR
   before the closing quote is `Err("vdf: unterminated quoted string")`. All
   other bytes (including non-ASCII) pass through unchanged.
6. **Comments.** `//` at a token boundary skips to LF or EOF; comments may
   appear between any tokens and are never stored, so they are not emitted.
7. **Depth.** At most 64 blocks may be open simultaneously; opening a 65th is
   `Err("vdf: depth exceeded (max 64)")`.
8. **Encoding.** `Str` is treated as a UTF-8 byte buffer; only ASCII bytes
   are special. Non-ASCII keys/values pass through byte-exact and are never
   split or rewritten.

## 5. Case and duplicate rules

1. Keys are stored byte-exact: `vdf_root_keys` / `vdf_child_keys` return the
   original spellings, and `vdf_emit` writes them unchanged (escaped).
2. All occurrences are preserved, including exact duplicates and case
   variants (`"k"`, `"K"`, `"k"` are three nodes).
3. Lookup is ASCII case-insensitive: each path segment is compared with
   `str_compare_ignore_case` (ASCII `A-Z` folded to `a-z`; every other byte
   compares byte-exact).
4. When several children of one block match a segment, the **last**
   occurrence in document order wins for `vdf_get_*` and for further path
   descent. This applies equally to duplicate value keys and duplicate block
   keys.

## 6. Path resolution

A path is a `.`-separated list of key segments matched against direct
children only:

- `""` resolves to the virtual root block (`vdf_has(d, "")` is always true,
  `vdf_child_keys(d, "")` equals `vdf_root_keys(d)`).
- `a.b.c` descends from the root: segment `a` among root children, `b` among
  the children of the last matching `a`, `c` among those of the last
  matching `b`.
- An empty segment (`a..b`, `.a`, `a.`) makes the path unresolvable; there is
  no escaping syntax, so a key containing `.` cannot be addressed as a single
  segment (flat namespace).

Unresolvable paths are never errors: `vdf_has` is false, `vdf_get_*` yield
`None`, `vdf_child_keys` yields an empty vector.

## 7. API contract

```xi
pub fn vdf_parse(text: Str) -> Result[Vdf, Str]
pub fn vdf_root_keys(d: &Vdf) -> Vec[Str]
pub fn vdf_child_keys(d: &Vdf, path: Str) -> Vec[Str]
pub fn vdf_has(d: &Vdf, path: Str) -> Bool
pub fn vdf_get_str(d: &Vdf, path: Str) -> Option[Str]
pub fn vdf_get_int(d: &Vdf, path: Str) -> Option[Int]
pub fn vdf_get_bool(d: &Vdf, path: Str) -> Option[Bool]
pub fn vdf_emit(d: &Vdf) -> Str
```

Typed lookup rules:

- `vdf_get_str`: any value node returns its decoded/raw text (possibly `""`);
  a block or an absent path returns `None`.
- `vdf_get_int`: the value must be an optional leading `-` followed by one or
  more ASCII digits; leading zeros are accepted (`"007"` -> `7`) and overflow
  is not detected; everything else returns `None`.
- `vdf_get_bool`: `"1"` / `"true"` (ASCII case-insensitive) -> `true`,
  `"0"` / `"false"` -> `false`; everything else returns `None`.
- All accessors ignore whitespace: values are used exactly as stored (the
  parser does not trim), so `" 7 "` is not an integer.

`vdf_root_keys` and `vdf_child_keys` return fresh copies: mutating the result
never changes the document.

Complexity: `vdf_parse` is O(total input length) time and memory plus O(node
count) for flattening; a lookup is O(total children of the blocks on the
path); `vdf_emit` is O(total output length) with an O(depth) stack.

## 8. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"vdf: "`:

| Message | Trigger |
|---|---|
| `vdf: unterminated quoted string` | EOF, LF or CR before the closing `"` (`"a`, `"a\nb"`) |
| `vdf: unterminated block` | EOF with at least one `{` open (`"a" { "b" "1"`) |
| `vdf: unexpected '}'` | `}` at top level (`}`, `"a" "1" }`, `"a" { } }`) |
| `vdf: stray token: <token>` | unquoted token where a key is expected (`foo "bar"`, `"a" "b" 42`, `[$WIN32]`) |
| `vdf: bad escape: <seq>` | `\` followed by anything but `n` `t` `"` `\` (`"x\qz"`) |
| `vdf: key without value: <key>` | key followed by EOF or `}` (`"a"`, `"a" }`, `"a" "b"` then `"c"`) |
| `vdf: empty key` | quoted key that decodes to `""` (`"" "x"`) |
| `vdf: depth exceeded (max 64)` | a 65th simultaneously open `{` |

Error reporting stops at the first failure; messages carry no line/column
position. Lookups, `vdf_emit` and all key/typed accessors are total.

## 9. Emission

`vdf_emit` writes the canonical form:

- one node per line, LF-terminated (including the last line);
- each nesting level prefixed with exactly one TAB;
- value node: `"key" "value"`;
- block node: `"key"` on its own line, then `{` at the node's indentation,
  the children, then `}` at the node's indentation;
- keys and values are quoted; `\` -> `\\`, `"` -> `\"`, LF -> `\n`,
  TAB -> `\t`; every other byte is written raw;
- node 0 (the virtual root) is not emitted, so an empty document emits `""`;
- duplicates are emitted in document order, so emit -> parse preserves the
  key sequence and the tree exactly (comments and original whitespace do
  not survive).

Round-trip guarantee: for any successfully parsed document `d`,
`vdf_parse(vdf_emit(d))` succeeds and yields the same node sequence, keys,
values and kinds (same root key order, same child orders, same duplicates,
same decoded scalar text) as `d`.

## 10. Test plan

`tests/test_conformance.xi` (module `vdf_tests`) runs 23 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | simple pair | quoted pair, `has`, typed accessors on a string node, root keys |
| t2 | root order | 3 root keys keep document order, all values readable |
| t3 | nested path | two-level path fetch, block presence, per-block child keys |
| t4 | whitespace/CRLF | spaces, tabs, blank lines and CRLF around all tokens |
| t5 | escapes | `\n` `\t` `\"` `\\` decode exactly |
| t6 | unquoted values | decimals, ints, `1`/`0`/`true`/`FALSE`, `http://...` tokens |
| t7 | stray token | unquoted key at root, after a pair, in a block, and `{` |
| t8 | comments | leading, trailing and middle `//` comments; blank lines |
| t9 | duplicates | `k`/`K`/`k`: all three root keys preserved, last wins lookup |
| t10 | case fold | `settings.playername`, `SETTINGS.PLAYERNAME`, stored case kept |
| t11 | typed lookup | `-42`, `0`, `007`, `12x`, `-`, `+5`, booleans, `yes` |
| t12 | empty docs | `""` and comment-only input: zero root keys, emit `""` |
| t13 | empty value/key | `"a" ""` legal; `"" "x"` and `""` are `empty key` |
| t14 | unterminated string | EOF, raw LF, and escaped-quote-then-EOF variants |
| t15 | unterminated block | EOF at depth 1 and depth 2, and `"a" {` |
| t16 | unexpected `}` | bare `}`, after a pair, after a closed block |
| t17 | key without value | EOF, `}`, next key without value, block body |
| t18 | bad escape | `\q` in a value and in a key, `\r` |
| t19 | depth limit | 64 nested blocks accepted and addressable, 65 rejected |
| t20 | canonical emit | exact multi-line text with tabs, then re-parse checks |
| t21 | duplicate blocks | both blocks emitted, lookup lands in the last one |
| t22 | path edges | `""`, missing, `a..b`, `.a.b`, `a.b.`, wrong kinds |
| t23 | emit escaping | exact `\"`/`\\` output, escape decode and re-parse |

All Str comparisons go through `xiom.string.compare`'s `str_compare`, never
`==` (BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 11. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.ini`/`xiom.toml` (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the document is five parallel
  homogeneous vectors (no `Vec[VdfNode]`).
- `Ok`/`Err` for `Result[Vdf, Str]` are constructed only in the leaf helpers
  `_ok_vdf`/`_err_vdf`.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare` (BUG 17); element values are read into typed locals
  before use, and case-insensitive matching uses `str_compare_ignore_case`.
- The parser is iterative (an explicit open-block stack), so no recursion
  depth is added; the 64-block limit is a documented input bound, not a
  compiler limit.
- The emitter walks the tree with an explicit stack of node indices, so it
  too is recursion-free.
- Tests dispatch directly (`t1()` ... `t23()`); `Vec[fn]` indexed calls are
  not used, no match pattern binds `mut`, no inline lambdas, and every
  `match` is exhaustive.

## 12. Known limitations

- Keys must be quoted; unquoted tokens are values only.
- No conditionals/macros, no `#base`/`#include`, no app schemas, no binary
  VDF.
- Flat path namespace: keys containing `.` are not addressable; empty path
  segments are unresolvable.
- ASCII-only case folding; non-ASCII bytes compare byte-exact.
- Raw LF/CR inside quoted strings is an error (write `\n`); CR therefore
  never occurs in parsed values, but a hand-built `Vdf` containing CR is
  emitted raw (not escaped), so it would not re-parse.
- Typed accessors cover decimal integers and `0`/`1`/`true`/`false` only; no
  floats, hex, whitespace trimming, or overload detection. `vdf_get_int`
  does not detect overflow.
- Duplicate keys/blocks are all preserved; lookup keeps the last occurrence.
- Comments are dropped, not preserved or emitted.
- Errors carry no line/column position.
- No file I/O, no streaming, no registry integration.
