# xiom.diagrams

> **Status:** `incubating` -- conformance-tested (34/34); published at `v0.1.0` on the XIOM registry.
> **Scope:** Graphviz DOT-subset codec: parse and serialize `graph`/`digraph`
> documents with node, edge and attribute statements, attribute lists, quoted
> strings, comments and a precise error catalog.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.diagrams` parses a documented Graphviz DOT subset from a `Str` and
serializes it back in a canonical, byte-deterministic form. No FFI, no file
I/O, no layout engine:

- `dot_parse` reads `graph` / `digraph` with node statements, edge statements
  (`->` in digraphs, `--` in graphs), `key=value` attribute statements and
  bracketed attribute lists; `#` and `//` line comments and optional
  semicolons are accepted.
- Malformed input yields `Err("<CODE>@<line>:<col>")` with an exact code,
  line and column -- the catalog is in `SPEC.md` section 6.
- `dot_serialize` emits one statement per line, two-space indent, canonical
  `, ` attribute separators, `;` after every statement, LF endings and no
  trailing newline. `parse -> serialize -> parse` is idempotent.
- The builder API (`dot_new`, `dot_add_node`, `dot_add_edge`, `dot_add_attr`,
  `dot_attr_pair`) constructs graphs programmatically; `dot_attr_get` looks
  attribute values back up (unescaped).
- `dot_escape` / `dot_unescape` handle the codec's quoted-string escaping.

The model is syntactic, not graph-theoretic: statements are kept in order in
four parallel vectors and `node [..]` / `edge [..]` / `graph [..]` default
statements parse and round-trip verbatim without special semantics. See
`SPEC.md` for the grammar, canonical form and normalizations.

## API

| Function | Returns | Description |
|---|---|---|
| `dot_parse(text)` | `Result[DotGraph, Str]` | Parse a DOT document; `Err("CODE@line:col")` on malformed input. |
| `dot_serialize(g)` | `Str` | Canonical, deterministic rendering (LF, no trailing newline). |
| `dot_new(directed, name)` | `DotGraph` | Empty graph; `directed` picks `digraph`/`->` vs `graph`/`--`. |
| `dot_add_node(g, id, attrs)` | `Void` | Append a node statement; `attrs` is a canonical body or `""`. |
| `dot_add_edge(g, from, to, attrs)` | `Void` | Append one edge statement. |
| `dot_add_attr(g, key, value)` | `Void` | Append a `key=value` attribute statement. |
| `dot_attr_pair(key, value)` | `Str` | One canonical `key=value` pair for an `attrs` argument. |
| `dot_attr_get(body, key)` | `Result[Str, Str]` | First matching value in a canonical body (unescaped), else `E_ATTR_NOT_FOUND`. |
| `dot_escape(s)` | `Str` | Escape `"` `\` LF TAB CR for a quoted string. |
| `dot_unescape(s)` | `Result[Str, Str]` | Inverse of `dot_escape`; `E_BAD_ESCAPE` on unknown escapes. |
| `dot_error_code(msg)` | `Str` | The code before the first `@` in an error message. |
| `dot_name(g)` | `Str` | Graph name as stored (`""` when anonymous). |
| `dot_is_directed(g)` | `Bool` | True for `digraph`. |
| `dot_is_consistent(g)` | `Bool` | True when the four parallel vectors have equal lengths. |
| `dot_stmt_count(g)` | `Int` | Number of statements. |
| `dot_node_count(g)` / `dot_edge_count(g)` / `dot_attr_count(g)` | `Int` | Statements per kind. |
| `dot_stmt_kind(g, i)` | `Int` | 0 node, 1 edge, 2 attr statement; `-1` out of range. |
| `dot_stmt_id(g, i)` | `Str` | Canonical node id / tail / attr key; `""` out of range. |
| `dot_stmt_target(g, i)` | `Str` | Canonical edge head / attr value; `""` out of range. |
| `dot_stmt_attrs(g, i)` | `Str` | Canonical attribute body without brackets; `""` out of range or none. |

Graph names, identifiers and values are stored in canonical DOT form: quoted
only when needed (`a`, `box`, `2` stay bare; `a b`, `#fff`, `""` are quoted
and escaped). Accessors return that canonical text.

## Install

From the XIOM registry (once published; the package is incubating):

```
xiom pkg install xiom.diagrams@0.1.0     # consumer
xiom pkg publish                          # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Usage

```xi
use xiom.diagrams;
use xiom.io;

fn main() -> Int {
  let src = "# build graph\ndigraph G {\n  a [label=\"Start Node\", shape=box];\n  a -> b [weight=2]; // edge\n}";
  let parsed = dot_parse(src);
  match parsed {
    Ok(g) => {
      io.println(dot_serialize(&g));
      let body = dot_stmt_attrs(&g, 0);
      let label = dot_attr_get(body, "label");
      match label {
        Ok(v) => { io.println("label = " + v); },
        Err(e) => { io.println("lookup failed: " + e); },
      }
    },
    Err(e) => { io.println("parse error: " + e); },
  }
  return 0;
}
```

Rendered output:

```
digraph G {
  a [label="Start Node", shape=box];
  a -> b [weight=2];
}
label = Start Node
```

Programmatic construction:

```xi
var g = dot_new(true, "G");
dot_add_node(&mut g, "a", dot_attr_pair("shape", "box"));
dot_add_edge(&mut g, "a", "b", dot_attr_pair("weight", "2"));
io.println(dot_serialize(&g));
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.diagrams
```

Expected tail: 34 `[PASS]` lines, `xiom.diagrams: all tests passed`, then
`port: PASS (passed=34 failed=0 program_exit=0 exit=0)`.

## Limitations

- Subset only: no subgraphs, ports, HTML-like strings, `strict`, `/* */`
  comments, or default-attribute (`node [..]`) semantics -- those statements
  parse and round-trip verbatim but are not interpreted.
- NUL bytes are outside the contract; every other byte round-trips.
- ASCII identifiers only when unquoted (`[A-Za-z0-9_]+`); quote anything else.
- `#` starts a line comment wherever it appears outside a quoted string.
- The codec is syntactic: statements keep order, chains expand to pairwise
  edges, `[]` and needless quotes are normalized away (see `SPEC.md`).
- No file I/O and no rendering: text in, text out.

See `SPEC.md` for the exact grammar, escaping table and error catalog.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
