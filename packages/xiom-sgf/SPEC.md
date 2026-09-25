# xiom.sgf -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.sgf` (`src/sgf.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory codec for a documented subset of SGF (Smart Game Format,
FF[4]-style syntax):

- `sgf_parse` -- SGF text -> `Result[SgfCollection, Str]`: all game trees of a
  collection flattened into parallel node/property/value vectors;
- accessors -- games and roots, node links (`sgf_node_parent`,
  `sgf_node_depth`, `sgf_node_seq`, `sgf_node_start`,
  `sgf_node_child_count`, `sgf_node_child`), properties
  (`sgf_node_prop_count`, `sgf_node_prop_id`, `sgf_node_value_count`,
  `sgf_node_value`, `sgf_node_value_start`) and lookup (`sgf_prop_find`,
  `sgf_prop_value`, `sgf_root_prop_value`);
- `sgf_emit` -- canonical serialization of a parsed collection.

Validation is *structural* only: brackets, semicolons, parentheses,
identifiers, value framing and escapes. No board, no rule engine, no property
meaning is ever consulted, so `B[notacolor]` and `B[aa]` are equally
acceptable values.

## 2. Non-goals

- No Go, chess or any other game semantics; properties are opaque text.
- No coordinate interpretation beyond text: `aa` is stored as the two bytes
  `aa`, never as a board point.
- No FF[1] legacy differences and no version-specific property tables.
- No composed value types (point lists, number ranges, colors, doubles): a
  property value is always text.
- No SimpleText/Text distinction: one documented value rule set (section 4.7)
  applies to every value.
- No `CA` charset conversion: bytes are copied, non-ASCII only ever appears
  inside values.
- No comments (SGF has none) and no byte-exact round-tripping: `sgf_emit` is
  canonical (whitespace and layout are normalized; identifiers are uppercase).
- No streaming or multi-document parsing: one call parses one document.
- No line/column diagnostics: errors carry one byte offset.

## 3. Data model

```xi
pub type SgfCollection = {
  node_parent: Vec[Int];      // parent node index, -1 for a game-tree root
  node_depth: Vec[Int];       // ancestor count: 0 for a root
  node_seq: Vec[Int];         // 1 when the node continues its parent's
                              // sequence, 0 for a variation or tree root
  node_start: Vec[Int];       // byte offset of the node's ';'
  node_child_start: Vec[Int]; // offset into `children` of the first child
  node_child_count: Vec[Int]; // number of direct children
  children: Vec[Int];         // child node indices, grouped by parent
  node_prop_start: Vec[Int];  // offset into `prop_ids` of the first property
  node_prop_count: Vec[Int];  // number of properties on the node
  prop_ids: Vec[Str];         // identifiers, normalized to uppercase
  prop_val_start: Vec[Int];   // offset into `val_texts` of the first value
  prop_val_count: Vec[Int];   // number of values of the property
  val_texts: Vec[Str];        // decoded value text
  val_starts: Vec[Int];       // byte offset of the value's '['
  roots: Vec[Int];            // node indices of the top-level game trees
}
```

Invariants:

- every `node_*` vector has the same length; nodes are in depth-first document
  order and a parent always has a smaller index than its children;
- `node_parent[n] == -1` exactly for the node indices in `roots` (one entry per
  top-level game tree, in document order);
- the children of node `n` are, in document order,
  `children[node_child_start[n] .. +node_child_count[n]]`; child 0 is the
  sequence continuation when `node_seq[child 0] == 1`, otherwise all children
  are variations;
- the properties of node `n` are
  `prop_ids[node_prop_start[n] .. +node_prop_count[n]]`;
- the values of property `p` are
  `val_texts[prop_val_start[p] .. +prop_val_count[p]]` and every parsed
  property has at least one value;
- `node_depth[n]` is 0 for a root and `node_depth[parent] + 1` otherwise.

`node_seq` records the syntactic shape: in `(;A;B)` node B has
`node_seq == 1`, while in `(;A(;B))` node B has `node_seq == 0`; both are valid
SGF games with the same links, and `sgf_emit` reproduces whichever shape was
parsed. `Vec[StructType]` is not usable in this compiler, so the streams are
parallel homogeneous vectors rather than node/property structs.

## 4. Grammar and value rules

```
collection = *( ws | game-tree )
game-tree  = "(" ws* sequence *( ws* game-tree ) ws* ")"
sequence   = node+
node       = ";" *( ws* property ) ws*
property   = prop-ident value+
prop-ident = 1*( "A".."Z" | "a".."z" )        ; stored normalized to uppercase
value      = "[" *( escaped | byte except "]" ) "]"
escaped    = "\\" byte | "\\" line-break
line-break = LF | CRLF | CR
ws         = " " | TAB | LF | CR
```

Parsing decisions (each is covered by the conformance suite):

1. **Whitespace.** Space, tab, LF and CR are insignificant between game trees,
   between nodes, between `;` and the first property, between properties, after
   `(` and before `)`. Whitespace is *not* allowed between an identifier and
   its first value nor between consecutive values: values must be adjacent
   (`AB[aa][bb]`). FF[4] permits more whitespace flexibility; this subset is
   deliberately stricter and documented here.
2. **Collection.** Zero or more game trees; empty and whitespace-only input is
   a valid empty collection. At collection level `)` is a stray-parenthesis
   error and any other byte is trailing garbage.
3. **Game tree.** `(` must be followed (after whitespace) by `;`, else
   `missing ; after (`. A tree must close with `)` before end of input, else
   `unmatched (` reporting the innermost open parenthesis.
4. **Sequence.** One or more nodes; every `;` node after the first in a
   sequence attaches to the previous node of that sequence (`node_seq == 1`).
5. **Variations.** After a sequence, every `(` opens a child tree attached to
   the last node of the sequence (`node_seq == 0`). Once a variation tree has
   begun, another `;` in the same tree is trailing garbage; `)` closes the
   current tree and parsing resumes in the parent tree (or the collection).
6. **Properties.** An identifier is a run of one or more ASCII letters,
   immediately followed by one or more values. Identifiers are normalized to
   uppercase, so `ff`, `FF` and `Ff` are the same property; lookup
   (`sgf_prop_find`, `sgf_prop_value`, `sgf_root_prop_value`) is
   case-insensitive for the same reason. Duplicate identifiers on one node are
   preserved in order and the first one wins on lookup.
7. **Values.** A value is the byte run from `[` to the matching unescaped `]`:
   - `\]` -> `]` and `\\` -> `\`;
   - a backslash before any other byte is dropped and the byte kept
     (`\:` -> `:`);
   - a backslash before LF, CRLF or lone CR removes the line break entirely
     (soft line break);
   - an unescaped LF, CRLF or lone CR becomes exactly one space;
   - every other byte is kept verbatim, including TAB, spaces and non-ASCII
     UTF-8 bytes; raw `[` is an ordinary value byte;
   - a `[` whose closing `]` is missing before end of input (including a
     backslash as the last input byte) is `unterminated value` at the `[`.
8. **Encoding.** `Str` is a UTF-8 byte buffer and all scanning is byte-wise;
   non-ASCII bytes are only meaningful inside values. A non-ASCII byte at a
   structural position is reported as bad property id char or trailing
   garbage, depending on context.

## 5. Canonical emit

`sgf_emit(c)` produces:

```
output  = *( game-tree NL )                  ; one tree per line; "" if no trees
tree    = "(" node-props ( sequence-continuation | variations ) ")"
```

- No whitespace is emitted inside a tree.
- A node is emitted as `;` followed by each property as `IDENT` + `[value]`
  per value. Identifiers are written as stored (uppercase after parsing).
- Values are re-escaped: `\` -> `\\`, `]` -> `\]`; every other byte is emitted
  verbatim.
- For each node with children: if `node_seq` of the first child is 1, that
  child is written in-line as the sequence continuation and every later child
  (never produced by `sgf_parse`) is written as a parenthesized tree;
  otherwise every child is written as a parenthesized variation tree.
- An empty collection emits `""`.

Because tokens and decoded values round-trip and the tree shape is recorded in
`node_seq`, `sgf_parse(sgf_emit(c))` is structurally equal to `c` for every
`c` that `sgf_parse` accepts: same roots, same parent/child links, same
`node_seq`, same identifiers and same decoded values. Byte offsets differ.
`sgf_emit` is idempotent: `sgf_emit(sgf_parse(sgf_emit(c)))` is byte-equal to
`sgf_emit(c)`.

## 6. Error catalog

Every parse failure is `Err(msg)` with a fixed message carrying a byte
position in the parsed input:

| Message | Trigger | Position |
|---|---|---|
| `sgf: unterminated value at <pos>` | `[` without a closing `]` before end of input (a trailing `\` counts) | the `[` |
| `sgf: missing ; after ( at <pos>` | after `(` and optional whitespace the next byte is not `;` | the offending byte, or input length at EOF |
| `sgf: stray ) at <pos>` | `)` where no game tree is open | the `)` |
| `sgf: empty property id at <pos>` | `[` where a property identifier is expected | the `[` |
| `sgf: bad property id char at <pos>` | a byte that cannot start a property, or an identifier not immediately followed by `[` | the offending byte, or input length at EOF |
| `sgf: unmatched ( at <pos>` | end of input while a game tree is still open | the innermost unmatched `(` |
| `sgf: trailing garbage at <pos>` | any byte that cannot continue the current production: junk at collection level, junk where `)` is expected, `;` after variation trees have begun | the offending byte |

The scanner stops at the first error; nodes, properties and values read before
it are discarded. Messages are built as `"sgf: "` + text + `" at "` + decimal
position via `xiom.convert.int_to_string`.

## 7. API signatures

```xi
pub fn sgf_parse(text: Str) -> Result[SgfCollection, Str]
pub fn sgf_emit(c: &SgfCollection) -> Str

pub fn sgf_game_count(c: &SgfCollection) -> Int
pub fn sgf_root(c: &SgfCollection, g: Int) -> Int            // -1 out of range
pub fn sgf_node_count(c: &SgfCollection) -> Int
pub fn sgf_node_parent(c: &SgfCollection, n: Int) -> Int     // -1 out of range
pub fn sgf_node_depth(c: &SgfCollection, n: Int) -> Int      // -1 out of range
pub fn sgf_node_seq(c: &SgfCollection, n: Int) -> Int        // -1 out of range
pub fn sgf_node_start(c: &SgfCollection, n: Int) -> Int      // -1 out of range
pub fn sgf_node_child_count(c: &SgfCollection, n: Int) -> Int // -1 out of range
pub fn sgf_node_child(c: &SgfCollection, n: Int, k: Int) -> Int // -1 out of range

pub fn sgf_node_prop_count(c: &SgfCollection, n: Int) -> Int // -1 out of range
pub fn sgf_node_prop_id(c: &SgfCollection, n: Int, p: Int) -> Str    // "" out of range
pub fn sgf_node_value_count(c: &SgfCollection, n: Int, p: Int) -> Int // -1 out of range
pub fn sgf_node_value(c: &SgfCollection, n: Int, p: Int, v: Int) -> Str // "" out of range
pub fn sgf_node_value_start(c: &SgfCollection, n: Int, p: Int, v: Int) -> Int // -1 out of range

pub fn sgf_prop_find(c: &SgfCollection, n: Int, id: Str) -> Int  // -1 when absent
pub fn sgf_prop_value(c: &SgfCollection, n: Int, id: Str) -> Str // "" when absent
pub fn sgf_root_prop_value(c: &SgfCollection, g: Int, id: Str) -> Str // "" when absent
```

Out-of-range accessors return `""`/`-1`. Because an empty value `X[]` also
decodes to `""`, use `sgf_node_value_count` (or `sgf_prop_find`) to tell an
empty value apart from a missing one. `sgf_node_parent` returns -1 both for
roots and for bad indices; use `sgf_root`/`sgf_node_depth` to distinguish.
Complexity: `sgf_parse` is O(input length); `sgf_emit` is O(output length);
structural accessors are O(1); `sgf_prop_find` is O(properties on the node).

## 8. Test plan

`tests/test_conformance.xi` (module `sgf_tests`) runs 24 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | full game | 3 nodes, parents/depths/starts, properties, case-insensitive lookup (sections 3-4) |
| t2 | multi-values | order, per-value `[` offsets, value counts (rule 6) |
| t3 | escapes | `\]`/`\\` decode, other `\X` drops the backslash, re-escape on emit (rule 7, section 5) |
| t4 | whitespace in values | LF/CRLF -> space, tab kept, soft line break removed (rule 7) |
| t5 | variations | parent/child ranges, depths, order, node_seq shape, emit shape (rule 5, section 5) |
| t6 | multiple trees | one collection, several roots, per-tree emit lines (rule 2, section 5) |
| t7 | identifier case | normalization to uppercase, case-insensitive lookup, uppercase emit (rule 6) |
| t8 | empty nodes | `(;)` valid, whitespace between `;`/properties/nodes, adjacent properties (rules 1, 4) |
| t9 | accessor totality | every accessor in and out of range (section 7) |
| t10 | empty collection | `""` and whitespace-only parse and emit empty (rule 2) |
| t11 | canonical emit | layout normalized, multi-tree lines, idempotence (section 5) |
| t12 | round-trip | parse -> emit -> parse preserves the model, including escapes and nesting (section 5) |
| t13 | value boundaries | raw `[`, empty values, `a\]`/`a\` tails, empty-first multi-value (rule 7) |
| t14 | unterminated value | EOF inside a value and a trailing backslash report the `[` (section 6) |
| t15 | missing `;` | `()`, `( )`, `((`, `(`, `([`, `(;A[x](`, `(;A[x]()` (section 6) |
| t16 | stray `)` | at start, after a closed tree, after whitespace (section 6) |
| t17 | empty property id | `[]` after `;`, after whitespace, after a value (rule 6) |
| t18 | bad property id char | digits, spaces, `)`, `.`, `@`, EOF after an identifier (rule 6) |
| t19 | unmatched `(` | outer and innermost open trees at EOF (section 6) |
| t20 | trailing garbage | after a tree, before a tree, `;` after variations, property after variations (rule 5) |
| t21 | duplicate properties | preserved in order, first match wins, case-insensitive query (rule 6) |
| t22 | value spaces | interior spaces preserved exactly, structural space dropped, offsets (rules 1, 7) |
| t23 | scale | 41-node sequence, 4-level nesting, chain walk, canonical emit (sections 3, 5) |
| t24 | offsets and emit | token offsets in a whitespace-heavy document, exact canonical output (rules 1, section 5) |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison). Tests call the check functions directly (`t1()` ...
`t24()`); `Vec[fn]` indexed dispatch is not used.

## 9. Compiler / stdlib notes

No unsafe code and no FFI. The implementation documents these
compiler-driven choices (XIOM v0.61.3):

- Free functions only, no methods on `SgfCollection`.
- No `Vec[StructType]`: the collection is a set of parallel `Vec` fields; the
  parser keeps sibling-link arrays and frame stacks as separate locals.
- The parser is iterative: an explicit stack of open game trees; the emitter
  walks the tree with its own action stack, so neither recursion depth nor
  input nesting can overflow the call stack.
- `Ok`/`Err` for `Result[SgfCollection, Str]` and `Result[Int, Str]` are
  constructed only in the leaf helpers `_ok_coll`/`_err_coll` and
  `_ok_pos`/`_err_pos`.
- `Str` equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); every element read binds a typed
  local, and every `Vec[Int]` read binds `let x: Int = v[i];`.
- Strings are materialized from a `Vec[UInt8]` buffer with
  `xiom.string.builder.sb_to_str`; `&mut Vec` arguments are passed with an
  explicit `&mut` at each call site; `&struct.field` is never passed as a
  `&Vec` argument.
- UInt8 bytes are widened with `(b as Int) & 0xFF` before comparisons and
  arithmetic.

## 10. Known limitations

- Whitespace inside a property run is rejected: `; AB [aa]` and `AB[aa] [bb]`
  fail (`bad property id char` / `empty property id`). FF[4] is more lenient;
  this subset requires values to be adjacent to their identifier. This is the
  one deliberate strictness of the codec.
- One value rule set: there is no SimpleText whitespace collapsing and no
  property-specific value grammar; `sgf_parse` never validates what a property
  means.
- No FF[1] support and no escape-form differences for it.
- `sgf_emit` is canonical, not byte-faithful: layout and case of identifiers
  are normalized; value bytes (after escape decoding) are preserved.
- Error messages carry one byte offset only; there is no line/column mapping
  and no partial result.
- The codec is not hardened against hand-built `SgfCollection` values that
  violate the section 3 invariants; `sgf_emit` assumes parse-produced data.
