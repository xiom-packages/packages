# xiom.meshopt

meshoptimizer v1.2 bindings for XIOM (mesh simplification, compression and
vertex processing). The upstream C++ sources are vendored into `vendor/`
(MIT) and compiled into the test binary with `--c-source` -- no system
library, no DLL, no SDK.

> **Status:** `incubating` -- vendored runtime path + owned-buffer wrappers
> green on the pin (xiom v0.64.3; 33/33 x2 native). Registry carry-over:
> `v0.1.0` (2026-09-30, pre-eco-train); 0.2.0 shipped in `eco-v0.1.155`;
> 0.3.0 published in `eco-v0.1.158` (sha256 `cbcd2ef7...`).
> **Lane:** bindings.

## Quick start

```xiom
use xiom.io;
use xiom.meshopt;

fn main() {
  let v = meshopt_version();          // 1020 for v1.2
  let s = meshopt_simplify_probe();   // real simplify of a 600-index grid
  let c = meshopt_cache_probe();      // ACMR before/after cache optimization
  if v == 1020 && s.out_count <= 102 && c.acmr_after_milli < c.acmr_before_milli {
    io.println("meshopt vendored path OK");
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Raw surface | 85 `meshoptimizer.h` declarations (100% of the C API), `Meshopt*` types + constants |
| Runtime probes (vendored) | `meshopt_version`, `meshopt_remap_probe`, `meshopt_cache_probe`, `meshopt_fetch_probe`, `meshopt_simplify_probe`, `meshopt_index_codec_probe`, `meshopt_vertex_codec_probe`, `meshopt_strip_probe`, `meshopt_quant_probe`, `meshopt_sphere_bounds_probe`, `meshopt_meshlet_probe`, `meshopt_oct_filter_probe` |
| Owned-buffer probes | `meshopt_probe_build_indices`, `meshopt_probe_optimize_inplace`, `meshopt_probe_checksum` |
| Owned-buffer wrappers (0.3.0) | `meshopt_remap_mesh` -> unique count, `meshopt_optimize_mesh` -> Bool, `meshopt_simplify_mesh` -> `MeshoptSimplifyResult`; `meshopt_fill_grid` fixture |

Full details: `SPEC.md`; vendored provenance + per-file SHA256 pins:
`SPEC.md` section 2.

## Tests

```
scripts/port.ps1 -Package xiom.meshopt -TimeoutSec 900
```

Expected: 33 `[PASS]`, exit 0. The suite runs real meshes through the
vendored library (remap, cache/fetch analysis, simplify, index/vertex
codecs, stripify, meshlets, sphere bounds, octahedral filters), the
XIOM-owned in-place optimization path read back byte-indexed, and the
0.3.0 owned-buffer wrappers (remap/optimize/simplify over caller-owned
byte meshes).
