# AUDIT: xiom.meshopt

## Status (2026-10-11)

Vendored C++ implementation at 0.2.0. The pre-pilot declaration-only module
(85 externs plus an assert-only 72-check suite that never linked the library)
is preserved in git history; 0.2.0 vendors the real upstream sources and
links them, so the suite now exercises the library.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.3 |
| Upstream | meshoptimizer v1.2 (commit `f843aae0`, `v1.2-17-gf843aae0`), vendored unmodified (MIT) |
| Link model | `--c-source` (20 vendored TUs + `src/meshopt_bridge.cpp`) via `port.args.json`, `--timeout 900`; no system library |
| FFI confinement | all `extern "C"` in the root module `meshopt.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 38 checks (16 constants + 14 real-library probes + 3 owned-buffer wrappers + 5 codec-family checks) |
| Runs | **PASS 38/38 x2** on the pin (`scripts/port.ps1 -Package xiom.meshopt -TimeoutSec 900`) |

## Design notes

- **Integer/scalar-only ABI**: probes return scalars or write 4-byte ints
  into XIOM-owned slots read little-endian; C++ structs (vertex cache/fetch
  statistics, `meshopt_Bounds`, meshlets) stay inside the bridge and only
  their fields cross. This sidesteps the fp-return (B-12) and
  struct-by-value shapes that are unreliable through the raw extern surface
  on the pin.
- **No foreign-pointer reads (B-20)**: probe meshes are built inside the
  bridge. The one buffer direction (`xmo_build_indices` /
  `xmo_optimize_inplace` / `xmo_checksum`) has C copy into and back out of
  an XIOM-owned byte slot, read byte-indexed on the XIOM side (the
  B-16/B-17-safe path).
- **Owned-buffer wrappers (0.3.0)**: `meshopt_remap_mesh`,
  `meshopt_optimize_mesh` and `meshopt_simplify_mesh` take caller-owned
  `Vec[UInt8]` byte meshes (f32 positions stride 12, u32 indices); C reads
  the inputs and writes results into XIOM-owned outputs, and the suite
  reads results back byte-indexed. `meshopt_fill_grid` is the deterministic
  fixture filler (f32 grid positions, reversed triangle order so cache
  optimization must reorder). Wrapper remap merges byte-identical vertices
  and copies the remapped vertex buffer out; optimize verifies the triangle
  multiset before write-back; simplify reports count + relative error.
- **Codec family (0.4.0)**: index sequence codec (arbitrary topology,
  byte-exact order -- unlike the triangle-list codec), the quat/exp/color
  filter family at 16/16/8 bits (max error in micro units; decode layouts
  pinned from the implementation: quat -> 4 int16 in place, exp -> float
  bits in place, color -> 4 unsigned bytes), and the meshlet codec (typed
  4/3 decode; vertex refs byte-exact, triangles compared rotation-invariant
  because the meshlet triangle coder rotates corners to line up next-bits,
  meshletcodec.cpp line 120).
- **Deterministic probes**: an 8x8 grid (64 vertices / 98 triangles,
  triangle order reversed to be cache-hostile) and an 11x11 bumpy grid (121
  vertices / 200 triangles) for simplification. The index codec check is
  rotation-invariant by design -- upstream `meshopt_encodeIndexBuffer`
  rotates triangle corners to match the edge FIFO (README: use
  `meshopt_encodeIndexSequence` to preserve exact order); the vertex codec
  round trip is byte-exact.
- **Probe-specific expectations**: cache ACMR must drop and stay in
  [0.4, 2.0]; simplify reaches ~100 of 600 indices at <= 5% relative error;
  fp16 patterns are `1.0 -> 0x3C00`, `-2.0 -> 0xC000`; the enclosing-sphere
  probe uses a 2x2 planar square where upstream's heuristic is exact
  (center 1,1; r = sqrt(2) -> 1414 milli); `buildMeshlets` must conserve all
  98 triangles.
- **Legacy re-verify**: the pre-vendor 72-check suite passed 72/72 on
  v0.64.3 before the modernization (record commit `157094bc`).

## Known limitations

- Runtime coverage is a pilot slice of the vendored library: remap, cache and
  fetch analysis, simplify, index/sequence/vertex codecs, meshlet codec,
  stripify, meshlets, sphere bounds, oct/quat/exp/color filters, plus the
  owned-buffer optimize path and the 0.3.0 wrappers. The remaining families
  (partition, spatial sort, opacity maps, tangents) and the cluster pipeline
  are Phase 3 (`ROADMAP.md`).
- The raw 85-function extern surface remains declaration-first: fp returns
  and struct-by-value returns must go through the bridge until the compiler
  fixes land (B-12/B-20); callbacks (custom remap, setAllocator) need a C
  trampoline (B-13) and are not exposed.
- Windows x64 tested; the vendored C++ path is portable (no platform code in
  meshoptimizer).
