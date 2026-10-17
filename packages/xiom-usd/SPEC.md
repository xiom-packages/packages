# SPEC: xiom.usd -- OpenUSD v26.08 scene-import bindings

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.usd` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | OpenUSD -- https://github.com/PixarAnimationStudios/OpenUSD |
| Upstream pin | **v26.08**, commit `ee47c679abde5b467a7b6a41f3b2285564a4222e` (2026-07-17) |
| Upstream license | **TOST-1.0** (Apache-2.0 class; Section 6 trademark clause replaced) |
| Runtime | official `usd-core` **26.8** cp311 win_amd64 wheel, sha256 `D39CEF20EFDFC29473E92887487BB8C10C45E966C492B5356D32A52724C3578F` |
| Package license | MIT OR Apache-2.0 |
| Compiler pin | v0.64.6 |
| Stdlib | `>=0.60.0 <1.0.0` |
| Platforms | Windows x64 (PE/x64 trampolines); POSIX is a typed ABI gate |

## 2. Runtime contract

| Soname | Status |
|--------|--------|
| `usd_ms.dll` | **Bound**: the wheel's monolithic library; namespace `pxrInternal_v0_26_8__pxrReserved__` |
| `usd.dll` | **Probed, typed ABI gate**: a non-wheel soname is reported as `RUNTIME_ABI` (the trampolines bind the v26.08 wheel) |
| `libusd.so` | **Typed ABI gate** on this lane (no ELF trampolines yet) |

`usd_load(runtime_dir)`:
1. sets the DLL directory / `PXR_PLUGINPATH_NAME=<dir>/pluginfo` /
   `PXR_USD_WINDOWS_DLL_PATH`, prepends `<dir>` to `PATH`;
2. preloads `tbb.dll` and a CPython 3.11+ runtime discovered in `<dir>`,
   `<dir>/..`, `<dir>/../pythonNNN`, or `<dir>/../../pythonNNN`;
3. `LoadLibrary("usd_ms.dll")`, verifies all 57 USD function symbols,
   resolves the local trampoline slots, mirrors the Sdf pool tables, then
   `xiom.ffi.dl` opens the soname for the `UsdLibrary` handle;
4. on failure returns `UsdLoadError{kind,message}` where kind is
   `ABSENT`, `DEPS` or `ABI`; the suite reports SKIP for all three.

The runtime is **not** required at build time. No import library is linked;
the executable starts and the suite stays green when the wheel is absent.

## 3. Declared surface

The public XIOM surface is below. `Result[T, UsdError]` carries typed
errors for scalars/strings/status; the four Float64 array getters return
`Vec[Float64]` and expose the failure via `usd_error()` (compiler
`Result[Vec[Float64]]` ABI gate, see AUDIT). An empty Vec from an array
getter can also mean a valid empty array; check the mesh info / `usd_error`
when the distinction matters.

### Loader / identity

| Function | Semantics |
|----------|-----------|
| `usd_load(runtime_dir) -> Result[UsdLibrary, UsdLoadError]` | Load the wheel; typed SKIP kinds |
| `usd_close(lib)` | Release the dl handle (bridge keeps its own reference) |
| `usd_bridge_version() -> Int` | Bridge API 100 (0.1.0) |
| `usd_bridge_abi() -> Int` | OpenUSD 2608 (26.08) |
| `usd_bridge_surface_count() -> Int` | Declared C ABI functions = 58 |
| `usd_error() -> UsdError` | Last bridge error (code + message) |
| `usd_error_name(code) -> Str` | Error code name |

### Stage / traversal

| Function | Semantics |
|----------|-----------|
| `usd_stage_open(lib,path) -> Result[UsdStage, UsdError]` | `UsdStage::Open`; `OPEN` on failure |
| `usd_stage_release(stage)` | Close; invalidates the stage's prim/iter handles |
| `usd_stage_default_prim(stage) -> Result[Str, UsdError]` | defaultPrim name (`""` when none) |
| `usd_stage_iter(stage) -> Result[UsdIter, UsdError]` | Depth-first pre-order from the root prims |
| `usd_prim_iter(prim) -> Result[UsdIter, UsdError]` | Subtree walk rooted at the prim |
| `usd_iter_next(iter) -> UsdPrim` | Next owned prim handle; `handle == 0` at end |
| `usd_iter_release(iter)` | Release the cursor |
| `usd_prim_at_path(stage,path) -> Result[UsdPrim, UsdError]` | Absolute path lookup (constructs SdfPath) |
| `usd_prim_release(prim)` | Release a prim handle |
| `usd_prim_is_valid(prim) -> Bool` | Handle live + prim valid |

### Prim read

| Function | Semantics |
|----------|-----------|
| `usd_prim_name/type/path(prim) -> Result[Str, UsdError]` | Name token, type token (may be `""`), absolute path |
| `usd_prim_attr_count(prim) -> Result[Int, UsdError]` | Authored attribute count |
| `usd_prim_attr(prim,index) -> Result[UsdAttrInfo, UsdError]` | `{name,type_name}` aggregate |
| `usd_prim_attr_name/type(prim,index) -> Result[Str, UsdError]` | Full attribute name / Sdf type name |
| `usd_prim_attr_index(prim,name) -> Int` | Authored index or -1 |
| `usd_prim_attr_float(prim,index) -> Result[Float64, UsdError]` | float/double narrowed |
| `usd_prim_attr_double(prim,index) -> Result[Float64, UsdError]` | double/float widened |
| `usd_prim_attr_int(prim,index) -> Result[Int, UsdError]` | int/int64 |
| `usd_prim_attr_bool(prim,index) -> Result[Bool, UsdError]` | bool |
| `usd_prim_attr_string(prim,index) -> Result[Str, UsdError]` | token/string/asset |
| `usd_prim_attr_vec3(prim,index) -> Vec[Float64]` | float3/color3f/normal3f/point3f/vector3f |
| `usd_prim_attr_float_by_name(prim,name) -> Result[Float64, UsdError]` | Lookup + float |
| `usd_prim_attr_vec3_by_name(prim,name) -> Vec[Float64]` | Lookup + vec3 |

### Mesh

| Function | Semantics |
|----------|-----------|
| `usd_mesh_info(prim) -> Result[UsdMeshInfo, UsdError]` | Validates: Mesh type, counts sum == indices, indices in range; returns `{point_count,face_count,index_count}` |
| `usd_mesh_points(prim) -> Vec[Float64]` | xyz triples (F64) |
| `usd_mesh_face_counts(prim) -> Result[Vec[Int], UsdError]` | per-face vertex counts |
| `usd_mesh_indices(prim) -> Result[Vec[Int], UsdError]` | flattened indices |

Errors: `NOT_MESH`, `MESH_INVALID`, `BUFFER`, `RANGE`, `OVERFLOW`,
`NOT_PRIM`, `INVALID_HANDLE`.

### Material surface subset

| Function | Semantics |
|----------|-----------|
| `usd_material_binding(prim) -> Result[Str, UsdError]` | First `material:binding` target |
| `usd_material_surface_shader_path(prim) -> Result[Str, UsdError]` | `outputs:surface` connection prim path |
| `usd_material_surface_shader_prim(prim) -> Result[UsdPrim, UsdError]` | The connected shader prim handle |
| `usd_material_shader_id(shader) -> Result[Str, UsdError]` | `info:id` (e.g. `UsdPreviewSurface`) |
| `usd_material_input_count(shader) -> Result[Int, UsdError]` | authored `inputs:*` count |
| `usd_material_input(shader,index) -> Result[UsdMaterialInput, UsdError]` | `{name,type_name,connected,connection}` |
| `usd_material_input_name/type/connection(shader,index) -> Result[Str, UsdError]` | input metadata |
| `usd_material_input_connected(shader,index) -> Result[Bool, UsdError]` | connection state |
| `usd_material_input_float(shader,name) -> Result[Float64, UsdError]` | float/double input |
| `usd_material_input_vec3(shader,name) -> Vec[Float64]` | color/float3 input |
| `usd_material_input_string(shader,name) -> Result[Str, UsdError]` | token/string/asset input |
| `usd_material_diffuse_color/emissive_color(shader) -> Vec[Float64]` | UsdPreviewSurface conveniences |
| `usd_material_metallic/roughness/opacity/ior(shader) -> Result[Float64, UsdError]` | float conveniences |
| `usd_material_use_specular_workflow(shader) -> Result[Bool, UsdError]` | int input -> bool |

The subset reads constant authored inputs; a connected input returns its
connection path/state and a connected value getter returns an empty Vec
(`usd_error()` = `NO_VALUE`). Texture resolution is out of scope.

### Time samples

| Function | Semantics |
|----------|-----------|
| `usd_attr_time_count(prim,name) -> Result[Int, UsdError]` | 0 when not sampled |
| `usd_attr_time_at(prim,name,index) -> Result[Float64, UsdError]` | sample time |
| `usd_attr_time_samples(prim,name) -> Result[UsdTimeSamples, UsdError]` | `{count,min_time,max_time}` |
| `usd_attr_double_at(prim,name,time) -> Result[Float64, UsdError]` | double/float at time |
| `usd_attr_float_at(prim,name,time) -> Result[Float64, UsdError]` | float/double at time, narrowed |
| `usd_attr_vec3_at(prim,name,time) -> Vec[Float64]` | vec3 at time |
| `usd_attr_float_sample(prim,name,index) -> Result[Float64, UsdError]` | value at sample index |

## 4. Error model

| Code | Name | Code | Name |
|------|------|------|------|
| 0 | `OK` | 10 | `TYPE` |
| 1 | `RUNTIME_ABSENT` | 11 | `RANGE` |
| 2 | `RUNTIME_ABI` | 12 | `BUFFER` |
| 3 | `RUNTIME_DEPS` | 13 | `NO_SURFACE` |
| 4 | `OPEN` | 14 | `NO_VALUE` |
| 5 | `INVALID_HANDLE` | 15 | `INTERNAL` |
| 6 | `NOT_PRIM` | 16 | `NO_BINDING` |
| 7 | `NOT_MESH` | 17 | `NOT_MATERIAL` |
| 8 | `MESH_INVALID` | 18 | `INVALID_PATH` |
| 9 | `ATTR_MISSING` | 19 | `OVERFLOW` |

Status-returning C functions return `-code`; count-returning functions
return `-code`; handle-returning functions return 0 and set the last error.

## 5. Ownership / threading

- Handles are **IDs** into bridge-side maps; the caller releases stages,
  prims and iterators explicitly (`usd_*_release`).
- Closing a stage erases its prim/iter handles; later calls return
  `INVALID_HANDLE` (tested).
- Strings are copied into XIOM-owned `Str` values; no C memory escapes.
- The bridge serializes all USD calls under one mutex (safe, not parallel).
  An importer can shard by opening independent stages in separate processes;
  in-process concurrency is not a 0.1.0 promise.
- Float64 array getters return an owned `Vec[Float64]`; the runtime writes
  one 8-byte component at a time into a proven 3-argument slot shape.

## 6. C ABI surface

The bridge exposes **58** C ABI functions (the `usdbridge_*` table in
`docs/COVERAGE.md`). `usdbridge_resolve_all` is an internal trampoline
resolver, not part of the surface. `usdbridge_bridge_surface_count()`
returns 58; the suite asserts equality.

The C layer is Windows x64 specific:
- 57 generated x64 function trampolines (one per undefined USD symbol);
- local Sdf pool arrays + `UsdPrimDefaultPredicate` + a disabled
  `TfMallocTag::_isInitialized` (static-data shims);
- the local pool arrays are exported from the executable and mirrored from
  the DLL before calls (`sync_pools`).

## 7. Test plan

`tests/test_conformance.xi` (65 checks):
- constants / error table / soname list / declared-surface count;
- typed absent SKIP; wheel load + bound soname;
- stage open/defaultPrim/traversal/subtree iterator;
- prim read (name/type/path/attrs/typed values/floats/bool/vec3/strings);
- mesh counts/points/face counts/indices + typed `NOT_MESH`/`MESH_INVALID`;
- material binding/surface/inputs/constants/connections/typed errors;
- time count/bounds/sample times/double/float/sample-index/vec3;
- empty stage, stale handle, stage-close invalidation, missing file/prim.

## 8. Build

`packages/xiom-usd/port.args.json`:
```json
["--cxx-standard", "17",
 "--c-source", "${PACKAGE_DIR}/src/usd_bridge.cpp",
 "--c-source", "${PACKAGE_DIR}/src/usd_trampolines.cpp"]
```
No `-I`, no import library, no linker flags. The vendored header closure is
in `vendor/include`; generated `pxr/pxr.h` and `pxr/base/work/impl.h` are
committed. The maintainer tools are `tools/vendor_headers.ps1` and
`tools/gen_trampolines.ps1`.


