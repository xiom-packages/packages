# xiom.obj

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Wavefront OBJ geometry parsing: vertices and polygon faces with
> scaled integer coordinates.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.convert.int_to_string`). Tests additionally
> use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.obj` reads the geometry subset of Wavefront OBJ held in a `Str`: `v`
records become vertices and `f` records become polygons. Coordinates never
become floats -- a small decimal parser computes `trunc(value * scale)`
directly into `Int`, so callers choose the fixed-point resolution (for example
`scale = 1000` for milli-units) and the compiler never needs `Float64`
vectors. Faces are stored as 0-based resolved vertex indices, packed flat
behind `face_starts`/`face_ends` ranges, and every rule is pinned in
`SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `obj_parse(text, scale)` | `Result[ObjMesh, Str]` | Parse a whole OBJ document. `scale` must be in `1..=1000000`; coordinates are `trunc(value * scale)` toward zero. Faces keep their original vertex count. |
| `obj_vertex_count(m)` | `Int` | Number of `v` records parsed. |
| `obj_face_count(m)` | `Int` | Number of `f` records parsed. |
| `obj_vertex_x(m, i)` | `Int` | Scaled x of vertex `i`; `0` when `i` is out of range. |
| `obj_vertex_y(m, i)` | `Int` | Scaled y of vertex `i`; `0` when `i` is out of range. |
| `obj_vertex_z(m, i)` | `Int` | Scaled z of vertex `i`; `0` when `i` is out of range. |
| `obj_face_len(m, f)` | `Int` | Number of vertices in face `f`; `0` when `f` is out of range. |
| `obj_face_index(m, f, j)` | `Int` | 0-based vertex index of slot `j` in face `f`; `-1` when `f` or `j` is out of range. |

`ObjMesh` holds `xs`, `ys`, `zs` (one entry per vertex) plus `face_starts`,
`face_ends` and `face_indices`: face `f` owns
`face_indices[face_starts[f]..face_ends[f]]`.

## Supported records

| Statement | Handling |
|---|---|
| `v x y z [w ...]` | Vertex. `x`, `y`, `z` are scaled decimals; the optional `w` and any further tokens (vertex colors) are ignored. |
| `f i j k ...` | Polygon. At least 3 references; the polygon keeps its vertex count (no triangulation). |
| `vt`, `vn`, `vp` | Ignored verbatim. |
| `g`, `o`, `s` | Ignored verbatim. |
| `usemtl`, `mtllib` | Ignored verbatim. |
| `# ...` | Comment: `#` starts a comment that runs to the end of the line. |
| blank line | Ignored. |
| anything else | `Err("obj: unknown record at line N")`; records are rejected, not silently skipped. |

## Usage

```xi
use xiom.obj;
use xiom.io;

fn main() -> Int {
  let r = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n", 1000);
  match r {
    Ok(m) => {
      io.println(int_to_string(obj_vertex_count(&m)));  // 3
      io.println(int_to_string(obj_face_len(&m, 0)));   // 3
      io.println(int_to_string(obj_vertex_x(&m, 1)));   // 1000
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.obj
```

Expected tail: 23 `[PASS]` lines, `xiom.obj: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No vt/vn/normals/groups/materials.** Texture coordinates, normals, free
  parameters, groups, smoothing, object names, material libraries and material
  uses are ignored, not exposed. The face reference forms `n/t`, `n//n` and
  `n/t/n` are accepted, but only the vertex number is retained.
- **No triangulation.** Polygons are kept exactly as written (a quad stays one
  face of length 4); consumers that need triangles must triangulate themselves
  (fan, ear clipping, ...).
- **No curves or surfaces.** Free-form records (`curv`, `surf`, `l`, `p`, ...)
  are not supported and are rejected as unknown records.
- **Integer-only coordinates.** There is no `Float64` path: coordinates are
  truncated toward zero into `Int` at parse time, `scale` is limited to
  `1..=1000000`, at most 12 integer and 9 fraction digits are accepted, and a
  vertex violating those limits is `Err("obj: malformed vertex at line N")`
  rather than rounded. Precision beyond the accepted digits is not carried.
- **Strict records.** Any record keyword other than the tables above (including
  `V` versus `v`) is an error; `#` always starts a comment, so a `#` byte in a
  data token truncates the rest of the line.
- **Byte-oriented.** Tokens are split on space and TAB only; a non-ASCII byte
  inside a record keyword is an unknown-record error. A UTF-8 BOM at the start
  of the file is not stripped.
- **Line endings.** Lines end at LF; a CR immediately before the LF is dropped
  (CRLF), but a bare CR is ordinary token data.
- **First error wins.** Parsing stops at the first bad line and no partial mesh
  is returned; blank and comment lines still count for the reported line
  number.
- **Whole-document parse.** The mesh is built in memory in one pass over the
  input; there is no streaming or callback API.

See `SPEC.md` for the full grammar, index resolution rules, error catalog and
test plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
