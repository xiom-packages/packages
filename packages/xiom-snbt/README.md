# xiom.snbt

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM SNBT (stringified NBT) parsing and canonical emission:
> compounds, lists, typed arrays `[B;`/`[I;`/`[L;`, quoted and bare strings,
> booleans and the full SNBT number forms.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`,
> `xiom.convert`; tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare`).
> No FFI.

## What it is

`xiom.snbt` is a dependency-light codec for the text form of Minecraft's
Named Binary Tag data. `snbt_parse` validates one complete document into an
`SnbtTree`, a flat node store built from parallel vectors with contiguous
child ranges -- no `Vec[StructType]` tree. Navigation accessors
(`snbt_find_child`, `snbt_child_at`, `snbt_list_count`, ...) and typed
readers (`snbt_get_int`, `snbt_get_string`, ...) walk that store, and
`snbt_emit` writes a canonical document back. Parse -> emit -> parse is
stable: the second emission is always byte-identical to the first.

Binary NBT is the sibling package `xiom.nbt`; this package is text only.

## API

Kind constants: `SNBT_KIND_STRING` (1) ... `SNBT_KIND_LONG_ARRAY` (13),
`SNBT_MAX_DEPTH` (64).

| Function | Returns | Description |
|---|---|---|
| `snbt_parse(input)` | `Result[SnbtTree, Str]` | Parse one complete document (root may be any kind). |
| `snbt_emit(&tree)` | `Result[Str, Str]` | Canonical document text. |
| `snbt_node_count(&tree)` | `Int` | Number of nodes. |
| `snbt_root(&tree)` | `Int` | Root node index (`-1` when empty). |
| `snbt_kind(&tree, node)` | `Int` | Kind 1-13 (`-1` out of range). |
| `snbt_kind_name(kind)` | `Str` | Stable name, e.g. `"long_array"` ("" unknown). |
| `snbt_text(&tree, node)` | `Str` | Stored text: string content, numeric body or canonical decimal. |
| `snbt_key(&tree, node)` | `Str` | Key inside the parent compound ("" outside one). |
| `snbt_parent(&tree, node)` | `Int` | Parent index (`-1` for the root). |
| `snbt_child_count(&tree, node)` | `Int` | Number of children. |
| `snbt_child_at(&tree, node, index)` | `Int` | Child index at `index` (`-1` out of range). |
| `snbt_find_child(&tree, node, key)` | `Int` | First child with that key (`-1` absent). |
| `snbt_list_count(&tree, node)` | `Result[Int, Str]` | List element count. |
| `snbt_list_item(&tree, node, index)` | `Result[Int, Str]` | List element node index. |
| `snbt_array_count(&tree, node)` | `Result[Int, Str]` | Typed array element count. |
| `snbt_array_element_kind(&tree, node)` | `Result[Int, Str]` | Declared array element kind. |
| `snbt_get_integer(&tree, node)` | `Result[Int, Str]` | Any integer kind (byte/short/int/long). |
| `snbt_get_byte/short/int/long(&tree, node)` | `Result[Int, Str]` | Kind-exact integer readers. |
| `snbt_get_bool(&tree, node)` | `Result[Bool, Str]` | Boolean reader. |
| `snbt_get_string(&tree, node)` | `Result[Str, Str]` | String reader. |

## Error model

All failures are `Err(Str)` with deterministic text (full table in SPEC.md):
`snbt: empty input`, `snbt: unexpected character`, `snbt: unbalanced braces`,
`snbt: unbalanced brackets`, `snbt: missing colon`, `snbt: bad key`,
`snbt: bad escape`, `snbt: unterminated string`, `snbt: invalid number`,
`snbt: bad number suffix`, `snbt: integer out of range`,
`snbt: mixed typed array`, `snbt: depth exceeded`, `snbt: trailing tokens`,
`snbt: invalid tree`, `snbt: empty tree`,
`snbt: node index out of range`, `snbt: unexpected kind N`,
`snbt: list index out of range`.

## Install

```
xiom pkg install xiom.snbt@0.1.0     # once published to the registry
```

## Usage

```xi
use xiom.snbt;
use xiom.io;

let p = snbt_parse("{name:\"Bananrama\",level:4b,scores:[B;1b,2b,3b]}");
match p {
  Ok(t) => {
    let root = snbt_root(&t);
    let name = snbt_find_child(&t, root, "name");
    let nv = snbt_get_string(&t, name);
    match nv {
      Ok(v) => { io.println(v); },                       // "Bananrama"
      Err(e) => { io.println("read error: " + e); },
    }
    let scores = snbt_find_child(&t, root, "scores");
    let count = snbt_array_count(&t, scores);            // Ok(3)
    let e = snbt_emit(&t);                               // canonical text
  },
  Err(e) => { io.println("parse error: " + e); },
}
```

Canonical emission normalizes rather than copies:

- `{a:007, b:'x', c:1.5}` emits `{a:7,b:"x",c:1.5d}`;
- keys are bare when every byte is in `A-Za-z0-9._+-`, quoted otherwise;
- strings are always double-quoted (with `\"`, `\\`, `\n`, `\t` escapes);
- integer kinds render from their values with the canonical suffix
  (`b`/`s`/`L`); float/double bodies are preserved verbatim and get the
  canonical `f`/`d` suffix;
- trailing commas and all inter-token whitespace disappear.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.snbt
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No binary NBT.** This is the text form only; the big-endian binary codec
  is `xiom.nbt`.
- **No Mojang data-component syntax, no UUID/date semantics.** Values are
  structural only; there is no schema layer.
- **No Float64 in the API.** XIOM v0.61.3 has no `Float64` in `Vec` form
  and no bitcast helpers are needed here: decimal and exponent forms
  (`1.5`, `1e-3`, `1.5f`, `2.0d`) are validated text tokens. The numeric
  body is preserved byte-for-byte and the canonical suffix is appended on
  emit; interpreting the text as a float is the caller's job. There is no
  `Vec[Float64]` anywhere in this package.
- **Integer ranges are enforced.** `b`: -128..127, `s`: -32768..32767,
  bare ints: signed 32-bit, `L`: signed 64-bit. The exact Int64 minimum
  `-9223372036854775808L` is rejected as out of range (the magnitude
  accumulator caps at `Int` max); use `-9223372036854775807L` or smaller.
- **No comments.** SNBT has none; `#`, `//` and `/*` are not recognized.
- **No Unicode escapes.** The documented escape set is exactly
  `\\ \" \' \n \t`; a raw control byte below 32 inside a quoted string is
  rejected. Bytes above 127 pass through verbatim (UTF-8 is not validated).
- **Duplicate keys are preserved.** Compound order and duplicates are kept;
  `snbt_find_child` returns the first match.
- **Single trailing comma only.** `{a:1,}` and `[1,]` parse; `{a:1,,}` does
  not.
- **Nesting cap: 64 containers** (`SNBT_MAX_DEPTH`), root container counted
  as depth 1. Parsed trees are finalized, so all accessors work immediately.
- **In-memory only**, not thread-safe; trees are plain value types.
- **No builder API in 0.1.0.** Trees are produced by `snbt_parse`;
  `snbt_emit` validates store consistency and refuses drifted trees with
  `snbt: invalid tree`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
