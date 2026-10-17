# COVERAGE: xiom.usd declared surface

Standing owner policy: **100% of the declared surface is implemented and
mapped to a proof**. The declared surface is the public `xiom.usd` module
(64 functions) backed by a **58-function C ABI**. The suite has **65**
checks (`tests/test_conformance.xi`); all are green on the pinned wheel and
the loader/constants checks are green without it.

Count gates:
- `usd_bridge_surface_count()` = **58** (the C ABI table below).
- `docs/COVERAGE.md` rows = 64 public functions + 58 C ABI functions.
- `usdbridge_resolve_all` is the internal trampoline resolver (not counted;
  it is not a USD binding function).

## 1. Public XIOM surface

`✅` = implemented; the "Proof" column names the suite check or the public
call path that exercises it.

| Public function | C bridge function(s) | Proof |
|-----------------|----------------------|-------|
| `usd_load` | `usdbridge_runtime_prepare`, `usdbridge_runtime_soname` | `loader: absent runtime -> typed SKIP`; `loader: usd_ms.dll bound` |
| `usd_close` | (dl handle; bridge keeps its ref) | suite cleanup; load/bound checks |
| `usd_bridge_version` | `usdbridge_bridge_version` | `bridge: version 0.1.0` |
| `usd_bridge_abi` | `usdbridge_bridge_abi` | `bridge: OpenUSD 26.08 ABI` |
| `usd_bridge_surface_count` | `usdbridge_bridge_surface_count` | `constants: declared C-ABI surface = 58` |
| `usd_error` | `usdbridge_last_error_code`, `usdbridge_last_error_message` | `errors: usd_error() last-error query` |
| `usd_error_name` | `usdbridge_error_name` | `bridge: error-name table`; `errors: missing prim` |
| `usd_stage_open` | `usdbridge_stage_open` | `stage: open cube_material.usda`; `errors: missing file -> OPEN` |
| `usd_stage_release` | `usdbridge_stage_release` | cleanup; `ownership: stage close invalidates prim` |
| `usd_stage_default_prim` | `usdbridge_stage_default_prim` | `stage: defaultPrim Root`; empty stage |
| `usd_stage_iter` | `usdbridge_stage_iter` | `traversal: 7 prims` |
| `usd_prim_iter` | `usdbridge_prim_iter` | `prim: subtree iterator 3` |
| `usd_iter_next` | `usdbridge_iter_next` | traversal checks |
| `usd_iter_release` | `usdbridge_iter_release` | traversal checks |
| `usd_prim_at_path` | `usdbridge_prim_at_path` | material/error fixture lookups; `errors: missing prim` |
| `usd_prim_release` | `usdbridge_prim_release` | traversal/cleanup |
| `usd_prim_is_valid` | `usdbridge_prim_is_valid` | `prim: valid prim is_valid`; stale-handle check |
| `usd_prim_name` | `usdbridge_prim_name` | `prim: name Cube` |
| `usd_prim_type` | `usdbridge_prim_type` | `prim: type Mesh` |
| `usd_prim_path` | `usdbridge_prim_path` | `prim: path /Root/Cube` |
| `usd_prim_attr_count` | `usdbridge_prim_attr_count` | `prim: authored attribute count 8` |
| `usd_prim_attr` | `usdbridge_prim_attr_name`, `_type` | `prim: attr info aggregate` (subdivisionScheme inline in the indexed checks) |
| `usd_prim_attr_name` | `usdbridge_prim_attr_name` | named-index diagnostics in `subdivisionScheme` checks |
| `usd_prim_attr_type` | `usdbridge_prim_attr_type` | `prim: subdivisionScheme type token` |
| `usd_prim_attr_index` | `usdbridge_prim_attr_index` | `prim: subdivisionScheme indexed`, bool/testTime/diffuse/metallic lookups |
| `usd_prim_attr_float` | `usdbridge_prim_attr_float` | `prim: float attr read (metallic)`; token -> TYPE |
| `usd_prim_attr_double` | `usdbridge_prim_attr_double` | `prim: negative double decode (-1.5)` |
| `usd_prim_attr_int` | `usdbridge_prim_attr_int` | `material: useSpecularWorkflow int -> true` |
| `usd_prim_attr_bool` | `usdbridge_prim_attr_bool` | `prim: bool read (testBool)` |
| `usd_prim_attr_string` | `usdbridge_prim_attr_string` | `prim: subdivisionScheme = none` |
| `usd_prim_attr_vec3` | `usdbridge_prim_attr_vec3_packed` (x/y/z) | `prim: packed attr vec3 path` |
| `usd_prim_attr_float_by_name` | (`index` + `float`) | `prim: float_by_name (metallic)` |
| `usd_prim_attr_vec3_by_name` | (`index` + packed vec3) | `prim: vec3_by_name (diffuseColor)` |
| `usd_mesh_info` | `usdbridge_mesh_info` | `mesh: info 8 points / 6 faces / 24 indices` |
| `usd_mesh_points` | `usdbridge_mesh_point_packed` (x/y/z per point) | `mesh: points xyz + first vertex` |
| `usd_mesh_face_counts` | `usdbridge_mesh_face_counts` | `mesh: six quad face counts` |
| `usd_mesh_indices` | `usdbridge_mesh_indices` | `mesh: indices [0,1,2,3]`; `MESH_INVALID` error |
| `usd_material_binding` | `usdbridge_material_binding` | `material: binding -> /Root/Looks/Preview` |
| `usd_material_surface_shader_path` | `usdbridge_material_surface_shader` | `material: outputs:surface -> PreviewSurface`; orphan -> NO_SURFACE |
| `usd_material_surface_shader_prim` | `usdbridge_material_surface_shader_prim` | `material: shader prim resolved` |
| `usd_material_shader_id` | `usdbridge_material_shader_id` | `material: shader info:id = UsdPreviewSurface` |
| `usd_material_input_count` | `usdbridge_material_input_count` | `material: 8 inputs` |
| `usd_material_input` | `usdbridge_material_input_name/type/connected/connection` | `material: emissiveColor connection path` |
| `usd_material_input_name` | `usdbridge_material_input_name` | used by the aggregate loop (above) |
| `usd_material_input_type` | `usdbridge_material_input_type` | used by the aggregate loop (above) |
| `usd_material_input_connected` | `usdbridge_material_input_connected` | aggregate loop; emissive connection |
| `usd_material_input_connection` | `usdbridge_material_input_connection` | `material: emissiveColor connection path` |
| `usd_material_input_float` | `usdbridge_material_input_float` | metallic/roughness/opacity/ior; color -> TYPE |
| `usd_material_input_vec3` | `usdbridge_material_input_vec3_x/y/z` | diffuseColor; connected emissive -> empty |
| `usd_material_input_string` | `usdbridge_material_input_string` | `material: string input (testString)` |
| `usd_material_diffuse_color` | (`input_vec3`) | `material: diffuseColor` |
| `usd_material_emissive_color` | (`input_vec3`) | `material: connected emissive returns empty Vec` |
| `usd_material_metallic` | (`input_float`) | `material: metallic/roughness/opacity/ior` |
| `usd_material_roughness` | (`input_float`) | same |
| `usd_material_opacity` | (`input_float`) | same |
| `usd_material_ior` | (`input_float`) | same |
| `usd_material_use_specular_workflow` | (`index` + `prim_attr_int`) | `material: useSpecularWorkflow int -> true` |
| `usd_attr_time_count` | `usdbridge_attr_time_count` | `time: testTime count 3`; missing -> ATTR_MISSING |
| `usd_attr_time_at` | `usdbridge_attr_time_at` | `time: sample[1].time = 1`; index 9 -> RANGE |
| `usd_attr_time_samples` | `usdbridge_attr_time_bounds` | `time: bounds [0,2]` |
| `usd_attr_double_at` | `usdbridge_attr_double_at` | `time: value at 1.0 = 1.5` |
| `usd_attr_float_at` | `usdbridge_attr_float_at` | `time: float_at 1.0 = 1.5` |
| `usd_attr_vec3_at` | `usdbridge_attr_vec3_at_x/y/z` | `time: vec3 at 1.0 = (0,1,0)` |
| `usd_attr_float_sample` | `usdbridge_attr_float_sample` | `time: float sample[2] = 2.5` |

Types (all exercised by the suite): `UsdLibrary`, `UsdLoadError`,
`UsdError`, `UsdStage`, `UsdPrim`, `UsdIter`, `UsdAttrInfo`, `UsdMeshInfo`,
`UsdMaterialInput`, `UsdTimeSamples`.

## 2. C ABI surface (58)

All rows are implemented in `src/usd_bridge.cpp` and exported with C
linkage. "Public path" names the XIOM wrapper(s) that use them; the
internal trampoline resolver is listed separately.

| # | C function | Public path |
|---|------------|-------------|
| 1 | `usdbridge_runtime_prepare` | `usd_load` |
| 2 | `usdbridge_runtime_soname` | `usd_load` |
| 3 | `usdbridge_bridge_version` | `usd_bridge_version` |
| 4 | `usdbridge_bridge_abi` | `usd_bridge_abi` |
| 5 | `usdbridge_bridge_surface_count` | `usd_bridge_surface_count` / suite |
| 6 | `usdbridge_last_error_code` | `usd_error` |
| 7 | `usdbridge_last_error_message` | `usd_error` |
| 8 | `usdbridge_error_name` | `usd_error_name` |
| 9 | `usdbridge_stage_open` | `usd_stage_open` |
| 10 | `usdbridge_stage_release` | `usd_stage_release` |
| 11 | `usdbridge_stage_default_prim` | `usd_stage_default_prim` |
| 12 | `usdbridge_stage_iter` | `usd_stage_iter` |
| 13 | `usdbridge_prim_iter` | `usd_prim_iter` |
| 14 | `usdbridge_iter_next` | `usd_iter_next` |
| 15 | `usdbridge_iter_release` | `usd_iter_release` |
| 16 | `usdbridge_prim_at_path` | `usd_prim_at_path` |
| 17 | `usdbridge_prim_release` | `usd_prim_release` |
| 18 | `usdbridge_prim_is_valid` | `usd_prim_is_valid` |
| 19 | `usdbridge_prim_name` | `usd_prim_name` |
| 20 | `usdbridge_prim_type` | `usd_prim_type` |
| 21 | `usdbridge_prim_path` | `usd_prim_path` |
| 22 | `usdbridge_prim_attr_count` | `usd_prim_attr_count` |
| 23 | `usdbridge_prim_attr_name` | `usd_prim_attr_name` / aggregate |
| 24 | `usdbridge_prim_attr_type` | `usd_prim_attr_type` / aggregate |
| 25 | `usdbridge_prim_attr_index` | `usd_prim_attr_index` |
| 26 | `usdbridge_prim_attr_float` | `usd_prim_attr_float` |
| 27 | `usdbridge_prim_attr_double` | `usd_prim_attr_double` |
| 28 | `usdbridge_prim_attr_int` | `usd_prim_attr_int` |
| 29 | `usdbridge_prim_attr_bool` | `usd_prim_attr_bool` |
| 30 | `usdbridge_prim_attr_string` | `usd_prim_attr_string` |
| 31 | `usdbridge_mesh_info` | `usd_mesh_info` |
| 32 | `usdbridge_mesh_face_counts` | `usd_mesh_face_counts` |
| 33 | `usdbridge_mesh_indices` | `usd_mesh_indices` |
| 34 | `usdbridge_material_binding` | `usd_material_binding` |
| 35 | `usdbridge_material_surface_shader` | `usd_material_surface_shader_path` |
| 36 | `usdbridge_material_surface_shader_prim` | `usd_material_surface_shader_prim` |
| 37 | `usdbridge_material_shader_id` | `usd_material_shader_id` |
| 38 | `usdbridge_material_input_count` | `usd_material_input_count` |
| 39 | `usdbridge_material_input_name` | `usd_material_input` |
| 40 | `usdbridge_material_input_type` | `usd_material_input` |
| 41 | `usdbridge_material_input_connected` | `usd_material_input` / `usd_material_input_connected` |
| 42 | `usdbridge_material_input_connection` | `usd_material_input` / `usd_material_input_connection` |
| 43 | `usdbridge_material_input_float` | `usd_material_input_float` |
| 44 | `usdbridge_material_input_string` | `usd_material_input_string` |
| 45 | `usdbridge_attr_time_count` | `usd_attr_time_count` |
| 46 | `usdbridge_attr_time_at` | `usd_attr_time_at` |
| 47 | `usdbridge_attr_time_bounds` | `usd_attr_time_samples` |
| 48 | `usdbridge_attr_double_at` | `usd_attr_double_at` |
| 49 | `usdbridge_attr_float_at` | `usd_attr_float_at` |
| 50 | `usdbridge_attr_float_sample` | `usd_attr_float_sample` |
| 51 | `usdbridge_mesh_point_packed` | `usd_mesh_points` |
| 52 | `usdbridge_prim_attr_vec3_packed` | `usd_prim_attr_vec3` |
| 53 | `usdbridge_material_input_vec3_x` | `usd_material_input_vec3` |
| 54 | `usdbridge_material_input_vec3_y` | `usd_material_input_vec3` |
| 55 | `usdbridge_material_input_vec3_z` | `usd_material_input_vec3` |
| 56 | `usdbridge_attr_vec3_at_x` | `usd_attr_vec3_at` |
| 57 | `usdbridge_attr_vec3_at_y` | `usd_attr_vec3_at` |
| 58 | `usdbridge_attr_vec3_at_z` | `usd_attr_vec3_at` |

Internal (not counted): `usdbridge_resolve_all` (resolves the 57 USD
function trampolines after `LoadLibrary`).

## 3. Coverage notes

- The four Float64 array getters return **plain `Vec[Float64]`** (the
  compiler's `Result[Vec[Float64]]` return is unreliable); failures are read
  through `usd_error()`. The array C paths are 3-argument (out in R8) or
  4-argument with one `Float64` (out in R9), the proven FFI shapes.
- The suite's 65 checks include the negative/typed error paths
  (`OPEN`, `NOT_PRIM`, `INVALID_HANDLE`, `NOT_MESH`, `MESH_INVALID`,
  `ATTR_MISSING`, `TYPE`, `RANGE`, `NO_SURFACE`, `NO_BINDING` behavior via
  the orphan fixture) and the empty-stage path.
- The runtime-absent shape is the same binary: no `usd_ms.dll` import; the
  suite's constants/typed-SKIP checks remain green.
- Mesh/material/time values are compared with tolerances where the source
  is float (`0.8` -> `0.8000000119`).
