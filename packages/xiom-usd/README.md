# xiom.usd

OpenUSD (Pixar Universal Scene Description) scene-import bindings for XIOM.
Stage open/traversal, prim `name`/`type`/`path` + authored attributes, mesh
points / face-vertex counts / indices, the UsdPreviewSurface material subset
(binding -> `outputs:surface` shader -> inputs + connections), and the
time-sample essentials.

The package is **runtime-trampolined**: the bridge is compiled against the
vendored OpenUSD **v26.08** headers but has **no static `usd_ms.dll`
import**. Every USD call is a local x64 trampoline whose slot is filled from
the official `usd-core` 26.8 wheel after `LoadLibrary` succeeds. The suite
therefore builds and runs without the USD runtime and reports **SKIP**
(green) with a typed absent/deps/ABI result.

> **Status:** `incubating` -- **0.1.0** declared surface, 58-function C ABI,
> **65/65** conformance checks green x2 on the pinned wheel; absent-runtime
> SKIP path proven. **Lane:** bindings (`keywords: ["binding"]`).
> **Platforms:** Windows x64 (the trampolines are PE/x64).

## Quick start

```xiom
use xiom.io;
use xiom.usd;

fn main() {
  let l = usd_load("E:/repos/usd-core/wheel/pxr");   // dir with usd_ms.dll
  if !l.is_ok {
    io.println("USD unavailable (SKIP): " + l.error.message);
    return;
  }
  let lib = l.value;

  let s = usd_stage_open(&lib, "scene.usda");
  if s.is_ok {
    let stage = s.value;
    let dp = usd_stage_default_prim(&stage);
    let it = usd_stage_iter(&stage);
    if it.is_ok {
      var p = usd_iter_next(&it.value);
      while p.handle != 0 {
        let path = usd_prim_path(&p);
        if path.is_ok { io.println(path.value); }
        usd_prim_release(&p);
        p = usd_iter_next(&it.value);
      }
      usd_iter_release(&it.value);
    }
    usd_stage_release(&stage);
  }
  usd_close(&lib);
}
```

## Runtime setup

1. Fetch/unpack the official **`usd-core` 26.8** wheel (cp311 win_amd64;
   sha256 `D39CEF20EFDFC29473E92887487BB8C10C45E966C492B5356D32A52724C3578F`).
2. Point `usd_load(dir)` at the directory containing `usd_ms.dll` (the
   wheel's `pxr/` directory). The bridge:
   - sets the DLL directory, `PXR_PLUGINPATH_NAME=<dir>/pluginfo` and
     `PXR_USD_WINDOWS_DLL_PATH=<dir>`,
   - prepends the dir to `PATH`,
   - preloads `tbb.dll` and a CPython 3.11+ runtime it finds in the dir, its
     parent, or a sibling `python311/` directory,
   - `LoadLibrary`s **`usd_ms.dll`**, then resolves all 57 USD function
     trampolines.
3. If `usd_ms.dll` is absent the loader tries `usd.dll` for the ABI gate:
   this bridge binds the v26.08 namespace (`pxrInternal_v0_26_8__pxrReserved__`)
   and reports a typed **ABI** error instead of calling a mismatched runtime.
   `libusd.so` is reserved for a future POSIX trampoline lane (typed ABI gate
   today).

## API

| Area | Functions |
|------|-----------|
| Loader/identity | `usd_load`, `usd_close`, `usd_bridge_version`, `usd_bridge_abi`, `usd_bridge_surface_count`, `usd_error`, `usd_error_name` |
| Stage/traversal | `usd_stage_open`, `usd_stage_release`, `usd_stage_default_prim`, `usd_stage_iter`, `usd_prim_iter`, `usd_iter_next`, `usd_iter_release`, `usd_prim_at_path`, `usd_prim_release`, `usd_prim_is_valid` |
| Prim read | `usd_prim_name/type/path`, `usd_prim_attr_count`, `usd_prim_attr`, `usd_prim_attr_name/type/index`, `usd_prim_attr_float/double/int/bool/string`, `usd_prim_attr_vec3`, `usd_prim_attr_float_by_name`, `usd_prim_attr_vec3_by_name` |
| Mesh | `usd_mesh_info`, `usd_mesh_points`, `usd_mesh_face_counts`, `usd_mesh_indices` |
| Material | `usd_material_binding`, `usd_material_surface_shader_path`, `usd_material_surface_shader_prim`, `usd_material_shader_id`, `usd_material_input_count`, `usd_material_input`, `usd_material_input_name/type/connected/connection/float/vec3/string`, `usd_material_diffuse_color`, `usd_material_emissive_color`, `usd_material_metallic`, `usd_material_roughness`, `usd_material_opacity`, `usd_material_ior`, `usd_material_use_specular_workflow` |
| Time samples | `usd_attr_time_count`, `usd_attr_time_at`, `usd_attr_time_samples`, `usd_attr_double_at`, `usd_attr_float_at`, `usd_attr_vec3_at`, `usd_attr_float_sample` |
| Types | `UsdLibrary`, `UsdLoadError`, `UsdStage`, `UsdPrim`, `UsdIter`, `UsdError`, `UsdAttrInfo`, `UsdMeshInfo`, `UsdMaterialInput`, `UsdTimeSamples` |

Scalar/string/status calls return `Result[T, UsdError]`. The four Float64
array getters (`usd_mesh_points`, `usd_prim_attr_vec3`, `usd_material_input_vec3`,
`usd_attr_vec3_at`) return `Vec[Float64]` and use `usd_error()` for the typed
failure record: the pinned compiler's `Result[Vec[Float64]]` return layout is
not reliable (see `AUDIT.md`); the scalar Result surface is unaffected.

## Declared-surface policy

`docs/COVERAGE.md` maps every public function and every one of the **58**
C ABI functions to its implementation and the suite check that proves it.
The declared surface is **100% implemented**; the suite has **65** checks
(green on the runtime, typed SKIP without it).

## Tests

```powershell
.\scripts\port.ps1 -Package xiom.usd -TimeoutSec 300
```

The suite uses `tests/fixtures/cube_material.usda` (cube + material +
connections + time samples), `error_cases.usda` (typed mesh/material errors),
and `empty.usda`. The positive path needs the usd-core wheel at
`E:/repos/usd-core/wheel/pxr` (or edit `runtime_dir()` in the suite); without
it every runtime-dependent check is a labeled SKIP and the constants/typed
SKIP checks still pass.

## Build model

- `--cxx-standard 17 --c-source src/usd_bridge.cpp --c-source src/usd_trampolines.cpp`
  (`port.args.json`). The vendored header closure is committed under
  `vendor/include` with exact relative include paths (no `-I` in the link
  line; same technique as `xiom.assimp`).
- `src/usd_trampolines.cpp` is generated by `tools/gen_trampolines.ps1` from
  the bridge's undefined USD symbols; `usdbridge_resolve_all` fills the
  slots at runtime. There is **no import library** and no delay-load flag.
- The bridge defines the three data symbols its inline header code uses
  (Sdf pool region tables + `UsdPrimDefaultPredicate`), exports the local
  pool arrays, and mirrors the DLL's pool table before each USD call. This
  is the ABI shim that makes a prebuilt wheel usable from a separately
  compiled bridge (see `AUDIT.md`).

## License / provenance

The package is **MIT OR Apache-2.0**. Vendored OpenUSD headers are
**TOST-1.0** (Apache-2.0 with the Section 6 trademark clause replaced) and
the oneTBB headers are Apache-2.0; see `PROVENANCE.md` for the exact commit
pin, wheel hash and terms. The runtime DLLs are not redistributed.


