# xiom.meshopt

meshoptimizer v1.2 bindings for XIOM (mesh simplification, compression and
vertex processing). The upstream C++ sources are vendored into `vendor/`
(MIT) and compiled into the test binary with `--c-source` -- no system
library, no DLL, no SDK.

> **Status:** `incubating` -- vendored runtime path, owned-buffer wrappers,
> codec families and the cooked-mesh container green on the pin (xiom
> v0.64.4; 43/43 x2 native). Registry carry-over: `v0.1.0` (2026-09-30,
> pre-eco-train); 0.3.0 shipped in `eco-v0.1.158`; 0.4.0 published in
> `eco-v0.1.159` (sha256 `0e98c707...`); **0.5.0 in `eco-v0.1.176` (sha256
> `521dab9e...`)**. **Lane:** bindings.

## Quick start

```xiom
use xiom.io;
use xiom.meshopt;
use xiom.meshopt_cooked;

fn main() {
  let v = meshopt_version();          // 1020 for v1.2
  let s = meshopt_simplify_probe();   // real simplify of a 600-index grid
  let c = meshopt_cache_probe();      // ACMR before/after cache optimization
  if v == 1020 && s.out_count <= 102 && c.acmr_after_milli < c.acmr_before_milli {
    io.println("meshopt vendored path OK");
  }
}
```

## Cooked mesh container (0.5.0)

```xiom
use xiom.meshopt_cooked;

// vertices: u32-indexed mesh bytes (stride vertex_size), indices: u32 list
let container = meshopt_cooked_encode(&vertices, vertex_count, vertex_size, &indices, index_count)?;
// ... store/transmit container bytes ...
let mesh = meshopt_cooked_decode(&container)?;   // counts + decoded bytes, one call
```

The container is the package's own documented "XMC1" framing of the
EncodePipeline vertex/index codec streams (SPEC.md section 4). Decode is
byte-indexed on XIOM-owned memory only; corrupt/truncated input returns
typed `MeshoptError` codes 10..15 (header/magic/version/size/decode/range).

## API

| Area | Functions |
|------|-----------|
| Raw surface | 85 `meshoptimizer.h` declarations (100% of the C API), `Meshopt*` types + constants |
| Runtime probes (vendored) | `meshopt_version`, `meshopt_remap_probe`, `meshopt_cache_probe`, `meshopt_fetch_probe`, `meshopt_simplify_probe`, `meshopt_index_codec_probe`, `meshopt_vertex_codec_probe`, `meshopt_strip_probe`, `meshopt_quant_probe`, `meshopt_sphere_bounds_probe`, `meshopt_meshlet_probe`, `meshopt_oct_filter_probe` |
| Owned-buffer probes | `meshopt_probe_build_indices`, `meshopt_probe_optimize_inplace`, `meshopt_probe_checksum` |
| Owned-buffer wrappers (0.3.0) | `meshopt_remap_mesh` -> unique count, `meshopt_optimize_mesh` -> Bool, `meshopt_simplify_mesh` -> `MeshoptSimplifyResult`; `meshopt_fill_grid` fixture |
| Codec family (0.4.0) | `meshopt_index_sequence_probe` -> `MeshoptCodecProbe` (byte-exact order), `meshopt_filter_quat_probe` / `meshopt_filter_exp_probe` / `meshopt_filter_color_probe` -> max error (micro), `meshopt_meshlet_codec_probe` -> `MeshoptMeshletCodec` |
| Cooked container (0.5.0) | `meshopt_cooked_encode` -> `Vec[UInt8]` container, `meshopt_cooked_decode` -> `MeshoptCookedMesh` (counts + owned vertex/index bytes), constants `MESHOPT_COOKED_*` |
| Pipelines (module `xiom.meshopt_safe`) | `RemapPipeline`, `OptimizePipeline`, `SimplifyPipeline`, `EncodePipeline` (encode/decode vertex + index), `StripPipeline` |

Full details: `SPEC.md`; vendored provenance + per-file SHA256 pins:
`SPEC.md` section 2 and `PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.meshopt -TimeoutSec 900
```

Expected: 43 `[PASS]`, exit 0. The suite runs real meshes through the
vendored library (remap, cache/fetch analysis, simplify, index/sequence/
vertex codecs, stripify, meshlets + meshlet codec, sphere bounds, oct/quat/
exp/color filters), the XIOM-owned in-place optimization path read back
byte-indexed, the owned-buffer wrappers (remap/optimize/simplify over
caller-owned byte meshes), and the cooked container (encode -> decode
byte-exact vertices + rotation-invariant triangle set, typed corrupt-input
errors).
