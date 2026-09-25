# xiom.wkt

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Well-Known Text (WKT) geometry codec for a documented subset:
> POINT, LINESTRING, POLYGON, MULTIPOINT, MULTILINESTRING, MULTIPOLYGON and
> GEOMETRYCOLLECTION, with EMPTY forms, Z/M/ZM markers and nested collections.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.wkt` parses a WKT geometry into a flat element table (`WktDoc`) and
emits it back in canonical form. Every geometry element -- the root, each
container child, each point of a MULTIPOINT, each ring of a POLYGON -- is one
entry in parallel flat vectors with child, ring and coordinate spans, because
XIOM v0.61.3 cannot hold a `Vec[StructType]`. Coordinates are **validated
decimal text tokens kept as strings**: `30`, `1.50`, `+1e3` and `-0` round
trip byte-identical and no Float64 conversion or rounding ever happens.

The parser is strict about syntax (parentheses, commas, number shape,
ordinate counts) and deliberately silent about geometry semantics: ring
closure, minimum vertex counts and self-intersection are **not** checked.
See `SPEC.md` for the exact grammar, error catalog and test matrix.

## API

| Function | Returns | Description |
|---|---|---|
| `wkt_parse(text)` | `Result[WktDoc, Str]` | Parse one geometry; errors are `"wkt: ... at <offset>"`. |
| `wkt_write(doc)` | `Str` | Canonical emit: uppercase types, single spaces, `", "` separators, verbatim coordinate tokens. |
| `wkt_normalize(text)` | `Result[Str, Str]` | Parse then emit, or the parse error. |
| `wkt_geometry_count(doc)` | `Int` | Element count (root plus all descendants). |
| `wkt_type(doc, i)` | `Str` | Canonical type name; `""` out of range. |
| `wkt_marker(doc, i)` | `Int` | Declared marker `0/1/2/3` (none/Z/M/ZM); `-1` out of range. |
| `wkt_coord_arity(doc, i)` | `Int` | Effective ordinates per tuple, `2..4` (inherited included); `-1` out of range. |
| `wkt_is_empty(doc, i)` | `Bool` | EMPTY flag (`true` out of range). |
| `wkt_parent(doc, i)` | `Int` | Parent element, `-1` for the root. |
| `wkt_child_count(doc, i)` | `Int` | Number of direct children. |
| `wkt_child(doc, i, k)` | `Int` | k-th direct child element; `-1` out of range. |
| `wkt_point_start(doc, i)` / `wkt_point_end(doc, i)` | `Int` | `[start, end)` coordinate span of the subtree. |
| `wkt_point_count(doc, i)` | `Int` | Coordinates in the subtree. |
| `wkt_ring_count(doc, i)` | `Int` | Rings in the subtree. |
| `wkt_ring_parent(doc, r)` | `Int` | Owning POLYGON of global ring `r`. |
| `wkt_ring_point_start(doc, r)` / `wkt_ring_point_end(doc, r)` | `Int` | `[start, end)` coordinate span of ring `r`. |
| `wkt_ring_point_count(doc, r)` | `Int` | Vertices of ring `r`. |
| `wkt_coord_count(doc)` | `Int` | Total coordinates in the document. |
| `wkt_x(doc, p)` / `wkt_y(doc, p)` | `Str` | First/second ordinate text of coordinate `p`. |
| `wkt_z(doc, p)` / `wkt_m(doc, p)` | `Str` | z/m ordinate text, `""` when absent. |

All accessors are total: out-of-range indices return the documented defaults
instead of failing.

## Usage

```xi
use xiom.wkt;
use xiom.io;
use xiom.string.compare;

fn main() -> Int {
  let r = wkt_parse("  polygon ( ( 0 0 , 1 0 , 1 1 , 0 0 ) )  ");
  match r {
    Ok(doc) => {
      io.println(wkt_type(&doc, 0));              // POLYGON
      io.println(wkt_ring_count(&doc, 0));        // 1
      io.println(wkt_ring_point_count(&doc, 0));  // 4
      io.println(wkt_x(&doc, 2));                 // 1
      io.println(wkt_write(&doc));                // POLYGON ((0 0, 1 0, 1 1, 0 0))
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

`wkt_normalize` is the one-call canonical form:

```xi
let canonical = wkt_normalize("point z (1  2 3)");   // Ok("POINT Z (1 2 3)")
```

Walking a MULTIPOINT's children:

```xi
let r = wkt_parse("MULTIPOINT Z ((1 2 3), (4 5 6))");
match r {
  Ok(doc) => {
    var k = 0;
    while k < wkt_child_count(&doc, 0) {
      let child = wkt_child(&doc, 0, k);
      io.println(wkt_type(&doc, child) + " " + wkt_z(&doc, wkt_point_start(&doc, child)));
      k = k + 1;
    }
  },
  Err(e) => { io.println(e); },
}
```

## Error model

Parsing returns `Err(Str)`; every message has the exact shape
`"wkt: <detail> at <byte-offset>"`, where the offset is the first offending
byte. The catalog is:

`unknown geometry type`, `unknown ordinate marker`, `expected "("`,
`expected ")"`, `unbalanced parentheses`, `invalid number`,
`expected N ordinates`, `missing ","`, `empty coordinate list`,
`trailing tokens`, `conflicting ordinate markers`.

Examples: `POINT (1 2` -> `wkt: unbalanced parentheses at 6`;
`POINT (1 2 3)` -> `wkt: expected 2 ordinates at 7`;
`POINT ()` -> `wkt: empty coordinate list at 7`.
`wkt_normalize` forwards the error unchanged, so callers can match on the
canonical message without re-parsing. `SPEC.md` section 5 lists one concrete
example per detail.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.wkt
```

Expected tail: 27 `[PASS]` lines, `xiom.wkt: all tests passed`, then
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## Limitations

- No SRID/EWKT prefix, no WKB, no GeoJSON, no coordinate transforms.
- No geometry math: rings are not checked for closure, minimum vertex count,
  simplicity or self-intersection; no area/length/spatial predicates.
- Coordinates stay text; `1.0` and `1` are different tokens. Use
  `xiom.string.str_to_float` for numeric work.
- `MULTIPOINT` items must be parenthesized (`MULTIPOINT ((1 2), (3 4))`); the
  older unparenthesized spelling is rejected.
- Z/M/ZM markers must be space-separated; `POINTZ` is rejected.
- One geometry per document; no trailing tokens; `()` is never accepted
  (`EMPTY` is the only empty spelling).
- Whole-input, in-memory parsing; nesting depth is bounded by the stack.
- Non-goals and the full grammar are spelled out in `SPEC.md`.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
