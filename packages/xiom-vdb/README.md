# xiom.vdb

> **Status:** `incubating` — conformance-tested **30/30** on the pinned
> compiler (XIOM v0.64.4); not yet recorded/published.
> **Scope:** minimal OpenVDB `.vdb` container reader: header, grid
> descriptor table, metadata, transforms, tree topology and dense 8x8x8
> leaf blocks. No writer, no codec, no I/O, no FFI.
> **Deps:** `xiom.std` only (the library module imports `xiom.string`,
> `xiom.string.compare`, `xiom.math` and `xiom.num.float`; the tests also
> use `xiom.test`, `xiom.io` and `xiom.convert`).
> **Published**: `0.1.0` in `eco-v0.1.178` (sha256 `a1eab885...`).

## What it is

`xiom.vdb` reads the sparse-volume container used by OpenVDB, Houdini and
Blender-side volume tools, entirely in pure XIOM over an in-memory file
image:

1. `vdb_open(data)` parses the header, file metadata and the grid
   descriptor table (name / tree type / instance parent / stream
   positions).
2. `vdb_grid_meta`, `vdb_grid_transform` and `vdb_grid_tree` parse one
   grid's sections on demand: metadata (class, creator, scalars),
   transform (map type + voxel size + translation), topology (leaf
   origins, counts, background) and the leaf-buffer index.
3. `vdb_read_leaf` decodes a dense 512-voxel block (active mask, raw
   payload, reconstructed values); `vdb_read_voxel` reads one voxel;
   `vdb_find_leaf` locates the leaf containing a coordinate.

Value chunks are decoded raw, as ZIP (a pure-XIOM RFC 1950/1951 inflate
with Adler-32 verification) or through OpenVDB's active-mask compression
(inactive voxels are reconstructed from the background, saved inactive
values and selection masks). Float, half-storage float, half, double,
vec3f, vec3f-as-half and vec3d grids are supported. Blosc-compressed
values and pre-222 / post-225 file versions are refused with typed errors;
the exact declared surface and its limits are in `SPEC.md`.

All validation is structural and purely in-memory; the API never touches
the filesystem. `xiom.io.read_file_bytes(path)` is the intended byte
source. Every failure is a typed `VdbError` (stable numeric code + stable
message); every read is bounds-checked before it happens.

## API

All functions are free functions in module `xiom.vdb`; see `SPEC.md` §8
for the full table and out-of-range conventions (`""`, `-1`, typed
errors).

```xiom
use xiom.io;
use xiom.string;
use xiom.vdb;

let fr = io.read_file_bytes("density.vdb");
if fr.is_ok {
  let bytes: Vec[UInt8] = fr.value;
  let or = vdb_open(&bytes);
  if or.is_ok {
    let f = or.value;
    let gi = vdb_find_grid(&f, "density");
    if gi >= 0 {
      let tr = vdb_grid_tree(&bytes, &f, gi);
      if tr.is_ok {
        let tree = tr.value;
        let k = vdb_find_leaf(&tree, 12, 3, 40);
        if k >= 0 {
          let lr = vdb_read_leaf(&bytes, &tree, k);
          /* lr.value.values: 512 reconstructed voxels */
        }
      }
    }
  }
}
```

## Verification

- 30/30 conformance checks: container/header, descriptor table, file and
  grid metadata, transforms (scale, scale-translate, translation,
  affine), topology walks, dense/sparse/vec/half leaf decode, voxel
  access, instances, empty grids, caps, truncation and corrupt-input paths.
- The zlib vectors are pinned from CPython's `zlib` (stored / fixed /
  dynamic Huffman + empty) and re-verified byte-for-byte; Adler-32 values
  are pinned from Python.
- Fixtures are hand-built from the documented layout; no upstream-produced
  `.vdb` is read yet (see `PROVENANCE.md` and `SPEC.md` §10 — this is a
  declared limitation, not a silent gap).

## Provenance

Independent implementation; no OpenVDB code vendored or copied. The pinned
oracle (v13.1.0, Apache-2.0) was used as a read-only semantic reference for
the file layout. Details: `PROVENANCE.md`.
