# xiom.ast -- Specification

Module: `xiom.ast` (package `xiom.ast@0.1.0`). Pure XIOM, deterministic, no
FFI, no IO. All state is passed explicitly; all queries are total (out-of-range
indices return sentinel values instead of trapping).

## 1. Node model

A tree (or forest) is one `Ast` value with **seven parallel `Vec` fields** of
identical length `n = ast_node_count(t)`:

| Field | Type | Meaning |
|---|---|---|
| `kinds` | `Vec[Int]` | `AST_KIND_*` value of node `i` |
| `starts` | `Vec[Int]` | span start (inclusive byte offset) |
| `ends` | `Vec[Int]` | span end (exclusive byte offset) |
| `parents` | `Vec[Int]` | parent index, `-1` for a root |
| `first_child` | `Vec[Int]` | first child index, `-1` for a leaf |
| `next_sibling` | `Vec[Int]` | next sibling, `-1` at the end of a chain |
| `labels` | `Vec[Str]` | optional label (`""` default) |

Node `i` exists iff `0 <= i < n`. A node with `parents[i] == -1` is a forest
root. The children of a node form a singly linked chain: `first_child[i]`,
then `next_sibling[...]`, `-1` terminating. **Child order is insertion order**:
`ast_child(i, k)` returns the k-th attached child, and reparenting appends at
the end of the new parent's chain.

There is no `Vec[StructType]`; the parallel arrays are the model. Only
`ast_add_node` grows the arrays and it pushes to all seven at once, so the
lengths cannot drift.

### Node kinds

| Constant | Value | Shape |
|---|---|---|
| `AST_KIND_NONE` | 0 | never produced by the builder |
| `AST_KIND_PROGRAM` | 1 | root of a compilation unit |
| `AST_KIND_LET` | 2 | `let name = expr` (excludes the `;`) |
| `AST_KIND_IF` | 3 | `if cond { ... } else { ... }` |
| `AST_KIND_BLOCK` | 4 | `{ ... }` braces included |
| `AST_KIND_RETURN` | 5 | `return expr` (excludes the `;`) |
| `AST_KIND_BINARY` | 6 | operator, exactly two children (left, right) |
| `AST_KIND_IDENT` | 7 | identifier reference (label = name) |
| `AST_KIND_LITERAL` | 8 | literal (label = text) |

`ast_kind_name(k)` maps these to `"none"`, `"program"`, `"let"`, `"if"`,
`"block"`, `"return"`, `"binary"`, `"ident"`, `"literal"`; any other value maps
to `"none"`.

## 2. Builder and invariants

- `ast_add_node(t, kind, start, end) -> Int` appends a detached root and
  returns its index. The span is stored verbatim: negative and inverted spans
  are legal input, reported later by `ast_diagnostics`, never rejected.
- `ast_add_child(t, parent, child) -> Bool` attaches `child` as the last child
  of `parent` iff both indices are valid, `parent != child`, `child` currently
  has no parent (`parents[child] == -1`), and `child` is not an ancestor of
  `parent`. Otherwise it returns `false` and changes nothing.
- `ast_reparent(t, child, new_parent) -> Bool` moves `child` (unlink from the
  old parent's chain, append to the new parent's chain) when
  `new_parent != -1`, or detaches `child` to a root when `new_parent == -1`.
  It refuses out-of-range indices, `child == new_parent`, and any move that
  would make a node its own descendant (successor cycle). A no-op move
  (`parents[child] == new_parent`) returns `true`.
- `ast_set_span` / `ast_set_label` overwrite a field iff the index is valid.
- Invariants maintained: all seven arrays stay the same length; every
  `parents`/`first_child`/`next_sibling` entry is `-1` or a valid index; a
  child's parent equals the node that holds it; the forest is acyclic.
  `ast_is_well_formed` checks exactly this, including that pre-order visits
  every node exactly once.

## 3. Traversal order

`ast_preorder(t)` and `ast_postorder(t)` return a `Vec[Int]` of node indices.
Both walk only structural links, never the `kinds` array.

- **Roots** are visited in increasing index order.
- **Children** of a node are visited left-to-right (insertion order).
- **Pre-order** emits a node before its subtree.
- **Post-order** emits a node after its subtree.

Both traversals are iterative with an explicit stack and a per-node visit
budget, so a corrupt/foreign tree terminates instead of looping; a tree built
by this module yields a permutation of `0..n`.

## 4. Queries

- `ast_roots(t)`: indices with `parents[i] == -1`, increasing.
- `ast_child(t, i, k)`: k-th child, `-1` when `i` out of range, `k < 0`, or
  too few children.
- `ast_child_count(t, i)`: chain length; `0` when `i` is out of range.
- `ast_is_leaf(t, i)`: `true` iff `i` is valid and `first_child[i] == -1`.
- `ast_depth(t, i)`: number of parent hops, root = 0; `-1` when `i` is out of
  range or the parent chain is corrupt.
- `ast_is_ancestor(t, a, b)`: `true` iff `a` is a **strict** ancestor of `b`
  (`a != b`, and following `parents` from `b` reaches `a`). Out-of-range
  indices and corrupt chains yield `false`.
- `ast_count_kind(t, kind)` / `ast_leaf_count(t)`.

## 5. Spans, tables, diagnostics

- A node's span is `[starts[i], ends[i])` into an external source `Str`.
- `ast_span_text(source, t, i)` returns `string.str_slice(source, s, e)`:
  out-of-range `i` yields `""`; inverted spans clamp to `""` exactly like
  `str_slice`.
- `ast_span_row(t, i)` returns
  `<i>: <kind> [<s>,<e>) parent=<p> depth=<d>`, or `""` out of range.
- `ast_span_table(t)` returns one row per node in **index order** (storage
  order, not traversal order).
- `ast_diagnostics(t)` returns, in index order, one message per offending
  node:
  - `ast: node <i> has negative span [<s>,<e>)` when `s < 0` or `e < 0`;
  - `ast: node <i> has inverted span [<s>,<e>)` when `s > e` (checked only
    when the span is not negative).
  A clean tree yields an empty vector.

## 6. Canonical pretty-printer

`ast_pretty(t)` renders the whole forest in **pre-order**, one node per line,
with exactly two spaces of indentation per depth level, and a trailing `\n`
after every line (an empty tree renders `""`). A line is:

```
<indent><kind>[ <label>] [<start>,<end>)
```

The label is omitted when it is empty (compared byte-wise with `str_compare`,
never `==`; see the language notes). Example (the fixture):

```
program [0,52)
  let [0,13)
    ident x [4,5)
    binary + [8,13)
      literal 1 [8,9)
      literal 2 [12,13)
  if [15,52)
    ident x [18,19)
    block [20,33)
      return [22,30)
        ident x [29,30)
    block [39,52)
      return [41,49)
        literal 0 [48,49)
```

## 7. Fixture grammar

`ast_fixture_source()` is the fixed 52-byte text

```
let x = 1 + 2;
if x { return x; } else { return 0; }
```

`ast_fixture_ast()` builds its 14-node tree. Nodes are created in a
deliberately non-preorder sequence so traversal tests are non-trivial:

| Index | Kind | Label | Span | Parent |
|---|---|---|---|---|
| 0 | literal | `1` | `[8,9)` | 2 |
| 1 | literal | `2` | `[12,13)` | 2 |
| 2 | binary | `+` | `[8,13)` | 4 |
| 3 | ident | `x` | `[4,5)` | 4 |
| 4 | let | | `[0,13)` | 13 |
| 5 | ident | `x` | `[18,19)` | 12 |
| 6 | return | | `[22,30)` | 8 |
| 7 | ident | `x` | `[29,30)` | 6 |
| 8 | block | | `[20,33)` | 12 |
| 9 | return | | `[41,49)` | 11 |
| 10 | literal | `0` | `[48,49)` | 9 |
| 11 | block | | `[39,52)` | 12 |
| 12 | if | | `[15,52)` | 13 |
| 13 | program | | `[0,52)` | -1 |

Pre-order: exactly `13,4,3,2,0,1,12,5,8,6,7,11,9,10`.
Post-order: `3,0,1,2,4,5,7,6,8,10,9,11,12,13`.
Statement spans exclude the trailing `;`; block spans include both braces.

## 8. Language notes (XIOM v0.62.1)

- Every `Str` read out of a `Vec[Str]` goes through a typed local and is
  compared with `str_compare` (BUG 17: `==` on `Vec[Str]` elements lowers to a
  pointer comparison and `.len()` there is unreliable).
- `Vec[Int]` element reads go through typed locals.
- Mutators touch the tree only through `&mut`-taking private helpers before
  their own `&mut` field accesses, avoiding the advisory E001 pattern.
- No `Vec[StructType]`, no `Vec[Float64]`, no indexed `Vec[fn]` dispatch, no
  `self` methods.

## 9. Determinism

Every function depends only on its arguments. Two identical builds produce
byte-identical pre-order, post-order, pretty text and span tables (covered by
the conformance suite).
