# PROVENANCE: xiom.meshopt

Upstream-first doctrine: `docs/UPSTREAM-FIRST.md` (xiom-packages/packages).
This file records what was studied, what was vendored, and what is derived
for the xiom.meshopt binding.

## Upstream

| Item | Value |
|------|-------|
| Project | meshoptimizer -- https://github.com/zeux/meshoptimizer |
| License | MIT (`vendor/LICENSE.md`; per-file headers carry the MIT notice) |
| Clone | `E:\repos\meshoptimizer` (owner-provided shared clone space) |
| Pin | commit `f843aae0b3070306bd2aeef43ffcf09509fee526` (post-tag `v1.2`, `v1.2-17-gf843aae0`; `MESHOPTIMIZER_VERSION` 1020) |
| Vendored path | `vendor/src/**` verbatim (20 `.cpp` + `meshoptimizer.h`, canonical LF blobs) + `vendor/LICENSE.md`; per-file byte counts and SHA256 pins in `SPEC.md` section 2 |
| Verification | each vendored file passes `git hash-object <file> == git rev-parse HEAD:<path>` against the clone at the pin |
| Link model | compiled with the suite via `port.args.json` `--c-source` (20 vendored TUs + `src/meshopt_bridge.cpp`); no system library, no DLL |

## Studied surface

- `meshoptimizer.h` (v1.2, 85 public functions) -- the raw declaration
  surface in `meshopt.xi` mirrors the header 1:1 (100% coverage; the
  export matrix is the header itself).
- `src/indexcodec.cpp`, `src/vertexcodec.cpp` -- codec framing and the
  edge-FIFO corner rotation (the reason index round trips are checked
  rotation-invariant; `encodeIndexSequence` preserves exact order).
- `src/indexgenerator.cpp` -- `meshopt_generateVertexRemap` memsets the
  destination unconditionally and asserts `indices || index_count ==
  vertex_count` (the NULL-indices form is `index_count == vertex_count`).
- `src/meshletcodec.cpp` -- meshlet triangle coder rotates corners to line
  up next-bits; `src/vertexfilter.cpp`, `src/quantization.cpp` -- filter
  decode layouts and fp16 semantics pinned in `AUDIT.md`.
- `src/simplifier.cpp`, `src/stripifier.cpp`, `src/vcacheoptimizer.cpp`,
  `src/overdrawoptimizer.cpp`, `src/vfetchoptimizer.cpp`,
  `src/clusterizer.cpp` -- behavior exercised by the probe bridge.

## Derived vs independent

- `meshopt.xi` (raw externs, constants, probes), `src/meshopt_bridge.cpp`
  (probe/owned-buffer bridge), `src/meshopt_safe.xi` (pipeline wrappers),
  `src/meshopt_cooked.xi` (container) and `tests/test_conformance.xi` are
  original XIOM/C++ work for this package -- no upstream XIOM port exists
  and no upstream code was copied beyond the vendored tree.
- The "XMC1" cooked container (SPEC.md section 4) is a package-local,
  versioned framing of the EncodePipeline codec streams. It is **not** the
  upstream `.meshopt` meshlet file format and makes no upstream-format
  claim; only the stream bytes inside it are upstream codec output.
- Test vectors are self-contained deterministic probe meshes built in the
  bridge (8x8 grid: 64 vertices / 98 triangles / 294 indices; 11x11 bumpy
  grid: 121 vertices / 600 indices); no upstream golden files were imported.

## Re-carve procedure

Per `SPEC.md` section 2: advance `E:\repos\meshoptimizer` to the new commit,
re-extract `vendor/src/**` + `LICENSE.md` via `git cat-file blob
HEAD:<path>` (canonical LF bytes), hash-verify every file, recompute the
SPEC section 2 pin table, re-run `scripts/port.ps1 -Package xiom.meshopt
-TimeoutSec 900` x2, update the version rows (SPEC/README/AUDIT/ROADMAP),
record, wrap, publish.
