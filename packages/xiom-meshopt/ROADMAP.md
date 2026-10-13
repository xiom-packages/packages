# xiom.meshopt -- Roadmap

**Version**: v0.5.0 | **Compiler**: xiom v0.64.4 | **Last updated**: 2026-10-13

## Current state

| Criterion | Status |
|-----------|--------|
| Raw FFI surface, 85 functions (100% of the C API) | Done -- 0.1.0 (declaration-only, preserved in git history) |
| Vendored upstream tree (`vendor/src`, v1.2 @ f843aae0, per-file SHA256) | Done -- 0.2.0 |
| C++ bridge + runtime probes on deterministic meshes (12) | Done -- 0.2.0 |
| XIOM-owned buffer direction (build/optimize/checksum) | Done -- 0.2.0 |
| Pool-drive re-verify on v0.64.3 (legacy suite, 72/72) | Done -- record `157094bc` |
| Owned-buffer safe wrappers (remap/optimize/simplify for callers) | Done -- 0.3.0 |
| Remaining codec families (index sequence, meshlet codec, quat/exp/color filters) | Done -- 0.4.0 |
| Cooked-mesh container ("XMC1") + decoder integration surface | Done -- 0.5.0 |
| Pipeline wrapper floor for the sibling modules (B-04 layout) | Done -- 0.5.0 |
| Cluster pipeline (build -> optimize -> bounds) | Phase 3 |
| Opacity maps + tangents (experimental upstream) | Phase 3 / on demand |
| Re-pin to the next upstream tag | backlog |

## Phase 3 (next touches)

1. ~~Safe wrappers over the direct surface~~ Done 0.3.0: `Vec[UInt8]`-in/out
   APIs for remap (`meshopt_remap_mesh`), cache optimize
   (`meshopt_optimize_mesh`) and simplify (`meshopt_simplify_mesh`), built
   on the probe-trio template (C copies into the XIOM-owned slot;
   byte-indexed reads); `meshopt_fill_grid` is the fixture filler.
2. ~~Encoder/decoder coverage~~ Done 0.4.0: index sequence codec (byte-exact
   order), the quat/exp/color filter family (max error in micro units), and
   the meshlet codec (typed 4/3 decode; vertex refs exact, triangle corners
   may rotate).
3. ~~Cooked file wrapper~~ Done 0.5.0: `meshopt_cooked_encode` /
   `meshopt_cooked_decode` (module `xiom.meshopt_cooked`) frame the
   EncodePipeline vertex/index streams with the documented "XMC1" header
   (SPEC section 4), decode into XIOM-owned buffers and expose the decoded
   mesh in one call; corrupt containers surface as typed errors 10..15.
   The `xiom.meshopt_safe` pipeline module now actually compiles: flat
   sibling module names (a dotted child cannot import its parent on the
   pin, B-04) plus a thin pub wrapper floor exported by the root module
   (FFI still confined to `meshopt.xi`, G5). `EncodePipeline.decode_indices`
   completes the codec surface.
4. Cluster pipeline: `buildMeshlets` -> `optimizeMeshlet` ->
   `computeMeshletBounds` (struct-by-value stays inside the bridge).
5. Consumer note: the engine asset pipeline (P4+) consumes `xiom.assimp`
   meshes; meshopt is the on-demand optimization step and the "XMC1"
   container is the storage shape -- keep the API stable and publish before
   engine integration asks.
6. Re-pin procedure is ready in `SPEC.md` section 2 (object-store extraction
   + per-file hash verification).
