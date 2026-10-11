# xiom.meshopt -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.3 | **Last updated**: 2026-10-11

## Current state

| Criterion | Status |
|-----------|--------|
| Raw FFI surface, 85 functions (100% of the C API) | Done -- 0.1.0 (declaration-only, preserved in git history) |
| Vendored upstream tree (`vendor/src`, v1.2 @ f843aae0, per-file SHA256) | Done -- 0.2.0 |
| C++ bridge + runtime probes on deterministic meshes (12) | Done -- 0.2.0 |
| XIOM-owned buffer direction (build/optimize/checksum) | Done -- 0.2.0 |
| Pool-drive re-verify on v0.64.3 (legacy suite, 72/72) | Done -- record `157094bc` |
| Owned-buffer safe wrappers (remap/optimize/simplify for callers) | Done -- 0.3.0 |
| Remaining codec families (index sequence, meshlet codec, quat/exp/color filters) | Phase 3 |
| Cluster pipeline (build -> optimize -> bounds) | Phase 3 |
| Opacity maps + tangents (experimental upstream) | Phase 3 / on demand |
| Re-pin to the next upstream tag | backlog |

## Phase 3 (next touches)

1. ~~Safe wrappers over the direct surface~~ Done 0.3.0: `Vec[UInt8]`-in/out
   APIs for remap (`meshopt_remap_mesh`), cache optimize
   (`meshopt_optimize_mesh`) and simplify (`meshopt_simplify_mesh`), built
   on the probe-trio template (C copies into the XIOM-owned slot;
   byte-indexed reads); `meshopt_fill_grid` is the fixture filler.
2. Encoder/decoder coverage: index sequence codec, meshlet codec, and the
   quat/exp/color vertex-filter family (oct is done), each as a round-trip
   probe with rotation/format-appropriate equality.
3. Cluster pipeline: `buildMeshlets` -> `optimizeMeshlet` ->
   `computeMeshletBounds` (struct-by-value stays inside the bridge).
4. Consumer note: the engine asset pipeline (P4+) consumes `xiom.assimp`
   meshes; meshopt is the on-demand optimization step -- keep the API stable
   and publish before engine integration asks.
5. Re-pin procedure is ready in `SPEC.md` section 2 (object-store extraction
   + per-file hash verification).
