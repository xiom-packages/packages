# xiom.layers

> **Status:** `incubating` -- conformance-tested (22/22); published at `v0.1.0` on the XIOM registry.
> **Scope:** ordered layered configuration over dotted string keys: later-wins
> precedence, explicit replace/append/delete sentinels, provenance, shadowed
> value queries, flattening to a final map and layer-to-layer diff. Pure and
> deterministic: text/map in, map out -- no file I/O, no environment reads.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_starts_with`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test`, `xiom.io` and `xiom.core`.

## What it is

`xiom.layers` models configuration as an **ordered stack of layers** over
dotted string keys (`server.port`, `db.host`, ...). Each layer is a small
map of `Str` keys to `Str` values; the stack order defines precedence: layer
0 is the lowest, the last layer wins. Resolving the stack folds every layer
into one `FlatMap` of live keys, in first-introduction order, recording the
winning layer per key (provenance). `layers_shadowed_layers` /
`layers_shadowed_values` report which lower-precedence entries lost, and
`layers_tombstones` lists keys killed by a delete.

Because values are plain strings, two reserved spellings make the
non-default operations explicit:

| Raw value | Meaning |
|---|---|
| `<text>` | set the key to `<text>` (replace) |
| `!replace:<text>` | explicit form of the same set (handy in generated configs) |
| `!append:<text>` | fold `<text>` onto the accumulated value with `,` as separator; start fresh when the key is absent or was deleted |
| `!delete` (exactly) | tombstone the key; a later entry resurrects it |
| `!!<text>` | escape: one `!` is stripped, `<text>` is stored literally |

Matching is exact and case-sensitive: `!delete ` (trailing space), `!append`
(no colon) and `!APPEND:x` are ordinary text. Deletes are path-exact:
deleting `server` does not delete `server.port`.

There is no global state and no I/O: every function takes and returns values,
so the same stack works for defaults compiled into a program, config text
read elsewhere, and override layers.

## API

### Stack construction and inspection

| Function | Returns | Description |
|---|---|---|
| `layers_new()` | `LayerStack` | Empty stack (no layers, no entries). |
| `layers_add(s, name, keys, vals)` | `Result[LayerStack, Str]` | Append a layer on top; validates name, alignment, dotted keys and per-layer key uniqueness. |
| `layers_count(s)` | `Int` | Number of layers. |
| `layers_name(s, i)` | `Option[Str]` | Layer name; `None` out of range. |
| `layers_layer_len(s, i)` | `Int` | Entry count of layer `i` (0 out of range). |
| `layers_key_valid(k)` | `Bool` | The dotted-key validity rule. |

### Sentinel classification

| Function | Returns | Description |
|---|---|---|
| `layers_is_delete(v)` | `Bool` | Value is exactly `!delete`. |
| `layers_is_append(v)` | `Bool` | Value starts with `!append:`. |
| `layers_is_replace(v)` | `Bool` | Value starts with `!replace:`. |
| `layers_is_escaped(v)` | `Bool` | Value starts with `!!`. |

### Resolution, provenance and shadowed values

| Function | Returns | Description |
|---|---|---|
| `layers_flatten(s)` | `FlatMap` | Resolve all layers: live keys only, first-introduction order, winning layer recorded. |
| `layers_has(s, key)` | `Bool` | Key appears in any layer (even if deleted last). |
| `layers_winner(s, key)` | `Option[Int]` | Layer of the last entry for the key. |
| `layers_shadowed_layers(s, key)` | `Vec[Int]` | Layers of the losing entries, stack order. |
| `layers_shadowed_values(s, key)` | `Vec[Str]` | Raw texts of the losing entries (aligned with `layers_shadowed_layers`). |
| `layers_tombstones(s)` | `Vec[Str]` | Keys whose last entry is `!delete`, first-introduction order. |
| `layers_diff(s, base, other)` | `Result[LayerDiff, Str]` | Added/removed/changed keys between two layers by raw text. |

### FlatMap queries

| Function | Returns | Description |
|---|---|---|
| `flatmap_len(m)` | `Int` | Number of live entries. |
| `flatmap_has(m, key)` | `Bool` | Key present in the flattened map. |
| `flatmap_get(m, key)` | `Option[Str]` | Flattened value. |
| `flatmap_layer(m, key)` | `Option[Int]` | Winning layer index (provenance). |
| `flatmap_keys(m)` | `Vec[Str]` | Live keys (fresh copy). |
| `flatmap_values(m)` | `Vec[Str]` | Live values (fresh copy). |
| `flatmap_entries(m)` | `(Vec[Str], Vec[Str])` | All entries as parallel `(keys, values)` copies. |
| `flatmap_render(m)` | `Str` | Canonical `key = value` lines, LF separated, no trailing LF. |

Resolution is total: `layers_add` rejects every malformed input, so
`layers_flatten` never fails and never panics.

## Usage

```xi
use xiom.layers;
use xiom.io;

fn main() -> Int {
  var ks = Vec[Str].new();
  ks.push("log.level");
  var vs = Vec[Str].new();
  vs.push("info");
  let s0 = layers_new();
  match layers_add(&s0, "defaults", &ks, &vs) {
    Ok(base) => {
      var ok = Vec[Str].new();
      ok.push("log.level");
      var ov = Vec[Str].new();
      ov.push("!append:debug");
      match layers_add(&base, "env", &ok, &ov) {
        Ok(stack) => {
          let m = layers_flatten(&stack);
          io.println(flatmap_render(&m));          // log.level = info,debug
          match flatmap_get(&m, "log.level") {
            Some(v) => { io.println(v); },         // info,debug
            None => {},
          }
        },
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.layers
```

Expected tail: 22 `[PASS]` lines, `xiom.layers: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Install / publish

```
xiom pkg install xiom.layers@0.1.0     # consumer, from the XIOM registry
xiom pkg publish                       # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Limitations (honest scope)

- **No file I/O, no environment reads, no hot reload.** Feed the API values
  your program produced elsewhere; there is no parser for a config file
  format (`xiom.config`, `xiom.ini`, `xiom.toml`, `xiom.dotenv` cover that).
- Deletes are path-exact: `!delete` on `server` leaves `server.port` alone.
  There is no implicit subtree delete.
- Keys must be valid dotted names and unique within a layer; layer names must
  be non-empty and unique across the stack. Layers cannot be reordered or
  removed after they are added.
- A literal value that begins with `!` must use the `!!` escape to avoid
  being read as a sentinel (only exact `!delete`, `!append:`, `!replace:` and
  `!!` spellings are special).
- Values are opaque byte strings; the library never builds a `Str` through a
  NUL-terminated buffer, but printing via `xiom.io.println` stops at an
  embedded NUL, so keep NUL (which pure XIOM code cannot easily produce)
  out of values.
- `flatmap_render` is one-way: it has no quoting and no round-trip parser.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
