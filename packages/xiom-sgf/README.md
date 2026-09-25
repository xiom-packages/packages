# xiom.sgf

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a Smart Game Format (SGF) codec for a documented subset: game
> tree collections, nodes, properties with multi-values and escapes, nested
> variations, accessors and canonical emit.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.builder.sb_to_str`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.sgf` parses an in-memory SGF document into a flat, fully indexed tree
model and serializes that model back to canonical SGF text. It is a *codec*,
not a game engine: validation is structural (parentheses, semicolons,
identifiers, value framing and escapes) and no board, rule engine or property
meaning is ever consulted. `B[notacolor]` and `B[aa]` are equally acceptable
values; coordinates are never interpreted beyond text.

Covered syntax:

- collections `(;...)(;...)` with any number of game trees per document;
- sequences `;A[x];B[y]` and nested variations `(;B[y])(;C[z](;D[w]))`
  preserved through parent links and contiguous child ranges;
- properties `XX[value]`, with identifiers normalized to uppercase (`ff`,
  `FF` and `Ff` are the same property) and case-insensitive lookup;
- multi-values `AB[aa][bb][cc]`, kept in order;
- value escapes: `\]` -> `]`, `\\` -> `\`, `\X` -> `X` (backslash dropped),
  soft line breaks removed, unescaped LF/CRLF/CR become one space, tabs and
  non-ASCII bytes preserved;
- canonical emit: no layout whitespace, one game tree per line, values
  re-escaped.

Whitespace inside a property run is deliberately strict: values must be
adjacent to their identifier (`AB[aa][bb]`, not `AB [aa] [bb]`). See `SPEC.md`
for the exact grammar, the value rules, the error catalog and the test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `sgf_parse(text)` | `Result[SgfCollection, Str]` | Parse one SGF document; errors are fixed `"sgf: ..."` messages with a byte offset. |
| `sgf_emit(c)` | `Str` | Canonical text: one game tree per line, no whitespace inside a tree; `""` for an empty collection. |
| `sgf_game_count(c)` | `Int` | Number of top-level game trees. |
| `sgf_root(c, g)` | `Int` | Root node index of game `g`; `-1` out of range. |
| `sgf_node_count(c)` | `Int` | Total nodes across all trees. |
| `sgf_node_parent(c, n)` | `Int` | Parent node index; `-1` for a root or out of range. |
| `sgf_node_depth(c, n)` | `Int` | Ancestor count (0 for a root); `-1` out of range. |
| `sgf_node_seq(c, n)` | `Int` | 1 when the node continues its parent's sequence (written after `;`), 0 for a variation/root; `-1` out of range. |
| `sgf_node_start(c, n)` | `Int` | Byte offset of the node's `;`; `-1` out of range. |
| `sgf_node_child_count(c, n)` | `Int` | Direct children (sequence continuation and variations); `-1` out of range. |
| `sgf_node_child(c, n, k)` | `Int` | k-th direct child in document order; `-1` out of range. |
| `sgf_node_prop_count(c, n)` | `Int` | Properties on the node (duplicates counted); `-1` out of range. |
| `sgf_node_prop_id(c, n, p)` | `Str` | Property identifier, uppercase; `""` out of range. |
| `sgf_node_value_count(c, n, p)` | `Int` | Number of values of the property; `-1` out of range. |
| `sgf_node_value(c, n, p, v)` | `Str` | Decoded value; `""` out of range (an empty value is also `""`, so check the count). |
| `sgf_node_value_start(c, n, p, v)` | `Int` | Byte offset of the value's `[`; `-1` out of range. |
| `sgf_prop_find(c, n, id)` | `Int` | Index of the first property on the node whose identifier matches `id` ignoring case; `-1` when absent. |
| `sgf_prop_value(c, n, id)` | `Str` | First value of the first matching property; `""` when absent. |
| `sgf_root_prop_value(c, g, id)` | `Str` | `sgf_prop_value` on game `g`'s root -- the usual way to read `FF`, `GM`, `SZ`, `CA`. |

## Quick start

```xi
use xiom.sgf;
use xiom.convert;
use xiom.io;

fn main() -> Int {
  let text = "(;FF[4]GM[1]SZ[19]C[a\\]b\nnext];B[aa](;W[bb])(;W[cc]))";
  let r = sgf_parse(text);
  match r {
    Ok(c) => {
      io.println(int_to_string(sgf_game_count(&c)));           // 1
      io.println(int_to_string(sgf_node_count(&c)));           // 4
      io.println(sgf_root_prop_value(&c, 0, "FF"));            // 4
      io.println(sgf_node_prop_id(&c, 1, 0));                  // B
      io.println(sgf_node_value(&c, 1, 0, 0));                 // aa
      io.println(int_to_string(sgf_node_child_count(&c, 1)));  // 2
      io.println(sgf_node_value(&c, 0, 3, 0));                 // a]b next
      io.println(sgf_emit(&c));                                // canonical text
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

(`io.println` takes a `Str`, hence `int_to_string` for the count accessors.
The canonical emit of the example is
`(;FF[4]GM[1]SZ[19]C[a\]b next];B[aa](;W[bb])(;W[cc]))` plus a newline.)

Walk a game with `sgf_game_count`, `sgf_root` and `sgf_node_child`, or read a
single property by name with `sgf_prop_value` / `sgf_root_prop_value`. Check
`sgf_node_seq` to tell a sequence continuation from a variation root;
`sgf_node_value_start` and `sgf_node_start` map model items back to byte
offsets in the parsed input.

## Error model

Every failure is an `Err(Str)` with a fixed message and the offending byte
offset, e.g.:

- `sgf: unterminated value at 3`
- `sgf: missing ; after ( at 7`
- `sgf: empty property id at 2`
- `sgf: bad property id char at 4`
- `sgf: unmatched ( at 0`
- `sgf: stray ) at 7`
- `sgf: trailing garbage at 7`

The scanner stops at the first error; the partial collection is discarded. The
full catalog is in `SPEC.md` section 6.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.sgf
```

Expected tail: 24 `[PASS]` lines, `xiom.sgf: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- Property values must be adjacent to their identifier: `AB [aa]` is an error
  (`bad property id char`) and `AB[aa] [bb]` reports `empty property id`.
  FF[4] is more lenient; this codec is deliberately strict and documents it.
- One value rule set: no SimpleText whitespace collapsing, no FF[1] legacy
  syntax, no composed value grammar (point lists, ranges, colors are text).
- No game semantics and no coordinate interpretation: properties are opaque.
- `sgf_emit` is canonical, not byte-faithful: layout, line breaks and
  identifier case are normalized; decoded value bytes are preserved.
- Identifier bytes must be ASCII letters; non-ASCII text is supported only
  inside values.
- Errors report a byte position only, with no line/column mapping.
- `sgf_emit` assumes a collection produced by `sgf_parse`; hand-built
  `SgfCollection` values that break the documented invariants are not
  validated.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
