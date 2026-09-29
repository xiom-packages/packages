# xiom.ast

> **Status:** `incubating` -- conformance-tested (24/24); not yet published on the XIOM registry.
> **Scope:** a deterministic abstract-syntax-tree toolkit: a parallel-array
> node model, a cycle-safe builder, pre/post-order traversal, parent/child/
> sibling queries, byte spans, a span/diagnostic table and a canonical
> pretty-printer, demonstrated on a fixed 14-node fixture grammar.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.ast` is the generic, language-agnostic half of an AST pipeline: the
data model and the algorithms that work on any tree shape. It deliberately
stops before parsing and before name resolution; a lexer/parser (e.g.
`xiom.lexer-fw`) produces token streams and span coordinates, and you attach
those spans to `xiom.ast` nodes.

XIOM cannot hold a `Vec[StructType]`, so nodes are stored in seven **parallel
`Vec` fields** of the same length that index each other instead of pointers:

| Field | Meaning |
|---|---|
| `kinds` | `AST_KIND_*` value per node |
| `starts`, `ends` | `[start, end)` byte span into some source text |
| `parents` | parent index, `-1` for a forest root |
| `first_child` | first child index (insertion order), `-1` for a leaf |
| `next_sibling` | next sibling in a parent's child chain, `-1` at the end |
| `labels` | optional text (identifier name, operator, literal), `""` default |

Only `ast_add_node` grows the arrays -- it pushes to all seven at once, so
their lengths cannot drift. Children form a `first_child`/`next_sibling`
chain, which makes reparenting O(children) and never invalidates other nodes'
stored indices.

## API

Builder and field accessors:

| Function | Returns | Description |
|---|---|---|
| `ast_new()` | `Ast` | Empty tree. |
| `ast_add_node(t, kind, start, end)` | `Int` | Append a detached node; returns its index. |
| `ast_set_span(t, i, start, end)` | `Bool` | Overwrite node `i`'s span; `false` out of range. |
| `ast_set_label(t, i, label)` | `Bool` | Overwrite node `i`'s label; `false` out of range. |
| `ast_node_count(t)` | `Int` | Number of nodes. |
| `ast_kind(t, i)` | `Int` | Kind, or `AST_KIND_NONE`. |
| `ast_span_start(t, i)` / `ast_span_end(t, i)` | `Int` | Span end, or `-1`. |
| `ast_label(t, i)` | `Str` | Label, or `""`. |
| `ast_parent(t, i)` / `ast_first_child(t, i)` / `ast_next_sibling(t, i)` | `Int` | Structural link, or `-1`. |
| `ast_child(t, i, k)` | `Int` | k-th child in insertion order, or `-1`. |
| `ast_child_count(t, i)` / `ast_is_leaf(t, i)` | `Int` / `Bool` | Child queries. |
| `ast_depth(t, i)` | `Int` | Root depth 0; `-1` out of range. |
| `ast_is_ancestor(t, a, b)` | `Bool` | Strict ancestry. |
| `ast_roots(t)` | `Vec[Int]` | Forest roots in index order. |

Structure mutation and traversal:

| Function | Returns | Description |
|---|---|---|
| `ast_add_child(t, parent, child)` | `Bool` | Attach a **fresh** node as last child; refuses cycles. |
| `ast_reparent(t, child, new_parent)` | `Bool` | Move a node (or detach with `-1`); refuses cycles. |
| `ast_preorder(t)` / `ast_postorder(t)` | `Vec[Int]` | Pre/post-order index order, children left-to-right. |

Spans, printing, diagnostics:

| Function | Returns | Description |
|---|---|---|
| `ast_kind_name(kind)` | `Str` | `"program"` ... `"literal"`, or `"none"`. |
| `ast_count_kind(t, kind)` / `ast_leaf_count(t)` | `Int` | Counting. |
| `ast_span_text(source, t, i)` | `Str` | Raw source slice of node `i`'s span. |
| `ast_span_row(t, i)` / `ast_span_table(t)` | `Str` / `Vec[Str]` | `"<i>: <kind> [<s>,<e>) parent=<p> depth=<d>"` rows. |
| `ast_pretty(t)` | `Str` | Canonical pre-order tree, 2-space indent, trailing newline. |
| `ast_diagnostics(t)` | `Vec[Str]` | Negative/inverted span messages in index order. |
| `ast_is_well_formed(t)` | `Bool` | Link consistency + exact-once pre-order coverage. |
| `ast_fixture_source()` / `ast_fixture_ast()` | `Str` / `Ast` | The fixed 52-byte source and its 14-node tree. |

```xi
use xiom.ast;
use xiom.io;

fn main() -> Int {
  let src = ast_fixture_source();
  let t = ast_fixture_ast();
  io.println(ast_node_count(&t));          // 14
  io.println(ast_pretty(&t));              // program / let / ident x / ...
  io.println(ast_span_text(src, &t, 8));   // "{ return x; }"
  return 0;
}
```

## Install

```
xiom pkg install xiom.ast@0.1.0
```

Until the first publish lands, consume it from this monorepo with
`xiom --run` and the `XIOM_STDLIB` environment set by `scripts/xiom.ps1`.

## Tests

```
.\scripts\port.ps1 -Package xiom.ast
```

Expected tail: 24 `[PASS]` lines, `xiom.ast: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Not a parser.** Nodes are built by hand (or by a future parser package);
  this module never lexes or parses text.
- **No type or scope information.** Kinds are structural only.
- **ASCII-int spans, byte offsets.** Spans are byte offsets like
  `xiom.lexer-fw`'s token positions, not character offsets.
- **Span metadata is not validated.** `ast_set_span` stores whatever it is
  given; use `ast_diagnostics` to detect negative/inverted spans.
- **No deletion or index reuse.** Nodes are append-only; the only structural
  edits are `ast_add_child` and `ast_reparent`.
- **Single-threaded, in-memory.** No persistence or sharing.

See `SPEC.md` for the full semantics. License: MIT OR Apache-2.0 (see the
repository root `LICENSE`).
