# xiom.usd -- ROADMAP

## Phase 1 (done) -- 0.1.0 declared scene-import surface

- [x] License check + provenance: OpenUSD v26.08 (`ee47c679`), TOST-1.0,
      oneTBB 2021.13 headers, usd-core 26.8 wheel hash.
- [x] Light clone (`--depth 1 --filter=blob:none --sparse`,
      `pxr/usd` + `pxr/base`); no full C++ tree, no import library.
- [x] Vendored header closure (316 files) with relative include rewriting;
      generated `pxr/pxr.h` + `pxr/base/work/impl.h`.
- [x] 57-symbol x64 trampoline bridge + typed runtime loader
      (`usd_ms.dll` bound; `usd.dll`/`libusd.so` ABI gates; SKIP-safe).
- [x] Static-data ABI shim (Sdf pool mirror, default predicate,
      TfMallocTag init) and call-boundary pool sync.
- [x] Stage open/close, defaultPrim, whole-stage + subtree traversal.
- [x] Prim name/type/path + authored attributes (float/double/int/bool/
      string/token/vec3) + by-name helpers.
- [x] Mesh points / face-vertex counts / indices with mesh validation and
      typed `NOT_MESH` / `MESH_INVALID`.
- [x] Material binding -> `outputs:surface` -> shader `info:id` -> authored
      `inputs:*` (name/type/connected/connection, float/vec3/string) +
      UsdPreviewSurface conveniences + typed `NO_BINDING`/`NO_SURFACE`.
- [x] Time-sample count/bounds/sample times/double/float/vec3/sample index.
- [x] 58-function C ABI, 65-check conformance suite, 65/65 x2 on the wheel;
      absent-runtime SKIP proven.
- [x] Coverage table (`docs/COVERAGE.md`) and lane docs.

## Phase 2 (planned) -- mesh/material depth

- [ ] Mesh normals, UVs, tangents/binormals and generic primvars
      (`primvars:*` with interpolation metadata).
- [ ] Subdivision/left-handed orientation flags; mesh topology helpers
      (edge counts, face-offset accessors).
- [ ] Xform read (local-to-world matrices, `xformOpOrder`, transform
      time samples) and camera essentials.
- [ ] Material inputs: texture reader/asset paths, `UsdUVTexture` subset,
      `normal`/`occlusion`/`clearcoat` inputs, shader network traversal.
- [ ] Material binding strength/preview variants (`material:binding:*`).
- [ ] Time interpolation policy selection (held/linear) and time-range
      metadata.
- [ ] Binary `.usdc` and packaged `.usdz` fixtures through the same loader
      (the wheel already carries the file-format plugins; add proof).

## Phase 3 (planned) -- scene composition

- [ ] References/payloads/variant selection and instance proxies.
- [ ] Stage metadata (upAxis, metersPerUnit, start/end time codes) and
      layer stack summary.
- [ ] Prim flags/predicates + schema type queries; `UsdShade` typed wrappers
      where the generic read is insufficient.
- [ ] Collection/API-schema subset for engine import (e.g. `MaterialBindingAPI`).
- [ ] Mesh sharing/caching for large scenes (per-stage cache, release).

## Phase 4 (toolchain / platform)

- [ ] Linux/macOS trampoline generation (ELF/Mach-O) and `libusd.so` binding;
      keep the typed ABI gate until proven.
- [ ] Revisit a full C++ bridge with a linker delay-load/import path if the
      XIOM toolchain gains a linker-flag passthrough; keep the SKIP gate.
- [ ] Remove the component/plain-Vec FFI workarounds when the compiler's
      `Result[Vec[Float64]]` and multi-Int32-out ABI are fixed.
- [ ] Re-pin to the next OpenUSD release when the drift guard flags it;
      regenerate trampolines, pool symbols and header closure.
