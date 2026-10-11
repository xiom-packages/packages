# xiom.assimp -- consumer mini-contract (engine asset pipeline)

**Status:** proposed 2026-10-11 by the bindings lane, in reply to
`REL-20261010-1900-2` (packages) / `REL-20261010-1834-engine-5` (engine).
**Applies to:** `xiom.assimp >= 0.8.0 < 1.0.0`, compiler pin v0.64.3
(behavioral contract; the guarantee is at the XIOM API level, not ABI).

## 0. Stability promise

The subset in sections 1-2 is frozen for the engine asset pipeline.
Additions are backward compatible (new functions, new struct fields, new
flags entry points); a breaking change to any item below requires a major
version bump and a relay notice one release ahead.

## 1. Import / release

| Entry point | Contract |
|-------------|----------|
| `assimp_import_file(path: Str) -> Result[Int, Str]` | Synchronous path import with `aiProcess_Triangulate \| aiProcess_FlipUVs`. Ok(handle) with handle > 0; Err(message) otherwise. |
| `assimp_release(handle: Int)` | Frees the scene/Importer in that registry slot. Unknown or already-released handles are a safe no-op. |

Exact 0.8.0 behavior (bridge `src/assimp_bridge.cpp`):

- The registry holds **4 live imports**; the handle is a 1-based slot index
  (1..4). The first free slot wins.
- **Handles are reusable slot numbers, not unique ids.** Never use a handle
  after `assimp_release`; a later import can receive the same number.
  (This also means do not call `release` again after the number may have
  been reused -- the no-op guarantee only covers the slot's own lifetime.)
- Error messages are deterministic:
  - `"assimp: import failed: empty path"`
  - `"assimp: import failed: <assimp GetErrorString()>"` -- missing or
    unreadable file, parse failure;
  - `"assimp: import failed: import registry full -- release a handle first"`
    -- four live imports already held.
- Import is synchronous and single-file. Paths are interpreted by assimp
  itself (cwd-relative or absolute); no memory-load entry exists in 0.8.0.

## 2. Mesh data access

| Entry point | Contract |
|-------------|----------|
| `assimp_mesh_count(handle) -> Int` | Meshes in the scene; 0 for an invalid/released handle. |
| `assimp_mesh_vertex_count(handle, mesh) -> Int` | Vertices; 0 for an invalid handle or mesh index. |
| `assimp_mesh_triangle_count(handle, mesh) -> Int` | Triangles (post-triangulate); 0 for invalid handle/mesh. |
| `assimp_mesh_has_uvs(handle, mesh) -> Bool` | True when the mesh carries UV channel 0. |
| `assimp_mesh_positions(handle, mesh) -> Vec[Float64]` | Object-space positions, **3 floats per vertex** (x, y, z). Empty on invalid handle/mesh. |
| `assimp_mesh_uvs(handle, mesh) -> Vec[Float64]` | **2 floats per vertex** when `has_uvs` is true; **empty** otherwise (or invalid handle/mesh). Length is `2 * vertex_count` only under `has_uvs`. |
| `assimp_mesh_indices(handle, mesh) -> Vec[UInt32]` | **3 indices per triangle**, post-triangulate, indexing the vertex arrays above. Empty on invalid handle/mesh. |

Semantics:

- Invalid handles and out-of-range mesh indices return empty/zero values, not
  errors and never a trap: consumer code can probe freely.
- All data is **copied into XIOM-owned `Vec`s** (C copies into an owned slot,
  read byte-indexed -- the B-20-safe path). No pointer into the assimp scene
  ever crosses the boundary, and the returned Vecs stay valid after
  `assimp_release` (they are independent copies).
- Cost: counts are O(1); each getter is an O(n) copy that allocates an owned
  Vec. For the engine pipeline: import, copy out, release -- do not hold
  handles while copying large scenes if a 5th import may arrive.

## 3. Threading

Single-threaded by contract: the bridge registry (`Importer` + scene statics)
and the XIOM-owned slots are unsynchronized. Import/getters/release must be
called from one thread. Parallel asset loading needs either a serialized
queue on the bindings side or per-thread processes; if the engine needs
concurrent loads, request it via relay (additive, backwards compatible).

## 4. Explicitly not in this contract (Phase 3 backlog)

- Memory-load entry (import from bytes; the `assimp_probe` in-memory group is
  probe-internal, not a consumer API).
- Materials/textures, node hierarchy and transforms, animations,
  cameras/lights.
- Custom post-process flag control (0.8.0 hardcodes Triangulate + FlipUVs).
- Export API.

These are additive when shipped; request via a relay item with the engine
use case so the subset is scoped to the consumer.

## 5. Consumer pattern

```xiom
use xiom.assimp;

let r = assimp_import_file("assets/quad_uv.obj");
if r.is_ok {
  let h = r.value;
  let meshes = assimp_mesh_count(h);
  var m = 0;
  while m < meshes {
    let vcount = assimp_mesh_vertex_count(h, m);
    let tris = assimp_mesh_triangle_count(h, m);
    let pos = assimp_mesh_positions(h, m);   // Vec[Float64], 3 per vertex
    let idx = assimp_mesh_indices(h, m);     // Vec[UInt32], 3 per triangle
    var uv: Vec[Float64] = Vec[Float64].new();
    if assimp_mesh_has_uvs(h, m) {
      uv = assimp_mesh_uvs(h, m);            // Vec[Float64], 2 per vertex
    }
    // ... hand pos/uv/idx to the mesh pipeline (e.g. xiom.meshopt) ...
    m = m + 1;
  }
  assimp_release(h);
} else {
  // r.error: one of the deterministic strings in section 1
}
```

## 6. Witness

`tests/test_conformance.xi` (16/16 x2 on v0.64.3) asserts the consumer path
end to end on `tests/fixtures/quad_uv.obj`: import -> handle, mesh/vertex/
triangle counts, `has_uvs`, positions contents, FlipUVs-corrected UV values,
non-degenerate post-triangulate indices, release invalidating the handle
(counts return 0), and the missing-file `Err` shape. Registry-full and
threading items are documented bridge behavior (sections 1-3).
