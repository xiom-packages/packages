# SPEC: xiom.xess -- Intel XeSS bindings (dynamic loader, SKIP path)

Version 0.1.0 -- compiler pin v0.64.4 -- 2026-10-14.

## 1. Scope and decision

Dynamic-loader bindings for the **XeSS Super Resolution** runtime:

- `libxess.dll` -- the SR core: generic API (xess.h), D3D12 backend
  (xess_d3d12.h + xess_d3d12_debug.h), Vulkan backend (xess_vk.h +
  xess_vk_debug.h) and the public debug surface (xess_debug.h);
- `libxess_dx11.dll` -- the D3D11 companion (xess_d3d11.h), loaded
  opportunistically when present.

**System-library SKIP path only** (closed-SDK doctrine, `PROVENANCE.md`): no
Intel SDK binaries, headers, or sources are vendored or linked at build time.
The loader resolves the Windows sonames from the OS search path; when the core
is absent the suite reports a typed **SKIP** (never FAIL), so CI without the
runtime stays green.  A local runtime image on PATH is used for present-path
evidence only (sec. 5).

Out of scope for 0.1.0 (explicit non-goals): the companion technologies
**XeSS-FG** (`libxess_fg.dll`, `xefg_swapchain*.h`) and **XeLL**
(`libxell.dll`, `xell.h`); the undocumented non-header exports of the SDK
binaries (`INTC_D3D11_Xess*`, `INTC_D3D12_*`, `xessAIL*`, `xessTrinity*`,
`xessVKAILGetDecision`, `xessGetContextParameterP`/`xessSetContextParameterF`);
actual GPU context creation (requires a caller-owned D3D12/D3D11/Vulkan
device and is exercised by consumers, not CI).

## 2. G2 pin

| Field | Value |
|-------|-------|
| Upstream | github.com/intel/xess @ **v3.0.2** (`8fe81bdb`) |
| Header set | 7 public headers; SHA256 per file in `PROVENANCE.md` |
| Sonames | `libxess.dll` (core), `libxess_dx11.dll` (companion) |
| Runtime samples | `bin/` DLLs of the pin clone (hashes in `PROVENANCE.md`); nothing committed |
| Compiler | v0.64.4 |

Drift guard: re-hash the header set at the next touch (re-carve procedure in
`PROVENANCE.md`).

## 3. Loader model and typed errors

`xess_load()` -> `xess_load_named("libxess.dll", "libxess_dx11.dll")`:

1. open the core; failure => `Err(XessLoadError{kind: XESS_LOAD_ABSENT})` -> SKIP;
2. open the companion (empty name or failed open => `has_dx11 = false`, not an
   error);
3. resolve **all 41 declared entry points** (37 core + 4 D3D11 when the
   companion is loaded); any missing symbol => `Err(kind: XESS_LOAD_ABI)`, the
   handles are closed and leaked nothing -> FAIL.

The D3D11 wrappers return a typed flat outcome
(`ok=false, rc=XESS_RESULT_ERROR_CANT_LOAD_LIBRARY`) when the companion is not
loaded -- they never call through a null pointer.

## 4. Coverage: 41/41 declared public entries

Export-table ground truth (PE parse of the pin's `bin/` DLLs) vs the bound
surface:

| Module | Total exports | Header-declared | Undocumented | Bound here |
|--------|--------------:|----------------:|-------------:|-----------:|
| `libxess.dll` | 72 | 37 | 35 (`INTC_*` 26, `xessAIL*` 2, `xessTrinity*` 4, `xessVKAILGetDecision`, ctx-params 2) | **37/37** |
| `libxess_dx11.dll` | 51 | 23 (4 D3D11 + 19 generic duplicates) | 28 (`INTC_*` 26, ctx-params 2) | **4/4** (D3D11 set; generic surface bound from core) |
| **Declared public total** | | **41** | | **41/41** |

Bound entry point -> wrapper (module in parentheses):

| # | Entry (header) | Wrapper |
|---|----------------|---------|
| 1 | xessGetVersion (xess.h) | `xess_get_version` |
| 2 | xessGetIntelXeFXVersion | `xess_get_intel_xefx_version` |
| 3 | xessGetProperties | `xess_get_properties` |
| 4 | xessGetInputResolution | `xess_get_input_resolution` |
| 5 | xessGetOptimalInputResolution | `xess_get_optimal_input_resolution` |
| 6 | xessGetJitterScale | `xess_get_jitter_scale` |
| 7 | xessGetVelocityScale | `xess_get_velocity_scale` |
| 8 | xessDestroyContext | `xess_destroy_context` |
| 9 | xessSetJitterScale | `xess_set_jitter_scale` |
| 10 | xessSetVelocityScale | `xess_set_velocity_scale` |
| 11 | xessSetExposureMultiplier | `xess_set_exposure_multiplier` |
| 12 | xessGetExposureMultiplier | `xess_get_exposure_multiplier` |
| 13 | xessSetMaxResponsiveMaskValue | `xess_set_max_responsive_mask_value` |
| 14 | xessGetMaxResponsiveMaskValue | `xess_get_max_responsive_mask_value` |
| 15 | xessSetLoggingCallback | `xess_set_logging_callback` |
| 16 | xessIsOptimalDriver | `xess_is_optimal_driver` |
| 17 | xessForceLegacyScaleFactors | `xess_force_legacy_scale_factors` |
| 18 | xessGetPipelineBuildStatus | `xess_get_pipeline_build_status` |
| 19 | xessD3D12CreateContext (xess_d3d12.h) | `xess_d3d12_create_context` |
| 20 | xessD3D12BuildPipelines | `xess_d3d12_build_pipelines` |
| 21 | xessD3D12Init | `xess_d3d12_init` |
| 22 | xessD3D12GetInitParams | `xess_d3d12_get_init_params` |
| 23 | xessD3D12Execute | `xess_d3d12_execute` |
| 24 | xessD3D12GetResourcesToDump (xess_d3d12_debug.h) | `xess_d3d12_get_resources_to_dump` |
| 25 | xessD3D12GetProfilingData (xess_d3d12_debug.h) | `xess_d3d12_get_profiling_data` |
| 26 | xessVKGetRequiredInstanceExtensions (xess_vk.h) | `xess_vk_get_required_instance_extensions` |
| 27 | xessVKGetRequiredDeviceExtensions | `xess_vk_get_required_device_extensions` |
| 28 | xessVKGetRequiredDeviceFeatures | `xess_vk_get_required_device_features` |
| 29 | xessVKCreateContext | `xess_vk_create_context` |
| 30 | xessVKBuildPipelines | `xess_vk_build_pipelines` |
| 31 | xessVKInit | `xess_vk_init` |
| 32 | xessVKGetInitParams | `xess_vk_get_init_params` |
| 33 | xessVKExecute | `xess_vk_execute` |
| 34 | xessVKGetResourcesToDump (xess_vk_debug.h) | `xess_vk_get_resources_to_dump` |
| 35 | xessSelectNetworkModel (xess_debug.h) | `xess_select_network_model` |
| 36 | xessStartDump (xess_debug.h) | `xess_start_dump` |
| 37 | xessGetProfilingData (xess_debug.h) | `xess_get_profiling_data` |
| 38 | xessD3D11CreateContext (xess_d3d11.h) | `xess_d3d11_create_context` |
| 39 | xessD3D11Init | `xess_d3d11_init` |
| 40 | xessD3D11GetInitParams | `xess_d3d11_get_init_params` |
| 41 | xessD3D11Execute | `xess_d3d11_execute` |

`xess_entry_names_core()` / `xess_entry_names_dx11()` publish the name lists
used by the suite's dl_sym sweep; the suite also re-derives the counts.

## 5. Pinned struct layouts (pack(8)) and ABI boundary

Structs are serialized/parsed by hand (byte-indexed, `xess_wr_*`/`xess_rd_*`):

| Struct | Size | Key offsets |
|--------|-----:|-------------|
| `xess_version_t` | 8 | u16 @0/2/4/6 |
| `xess_2d_t` / `xess_coord_t` | 8 | u32 @0/4 |
| `xess_properties_t` | 24 | u32 @0, u64 @8, u64 @16 |
| `xess_d3d12_init_params_t` | 64 | u32 @0/4/8/12/16/20, ptr @24, u64 @32, ptr @40, u64 @48, ptr @56 |
| `xess_d3d12_execute_params_t` | 136 | 6 ptrs @0..40, f32 @48/52/56, u32 @60/64/68, 6 coord pairs @72..112, ptr @120, u32 @128 |
| `xess_vk_image_view_info` | 48 | ptr @0/8, 5 x u32 range @16..32, u32 format @36, u32 w/h @40/44 |
| `xess_vk_init_params_t` | 64 | as d3d12, `pipeline_cache` @56 |
| `xess_vk_execute_params_t` | 360 | 6 x info @0..240, f32 @288/292/296, u32 @300/304/308, 6 coord pairs @312..352 |
| `xess_d3d11_init_params_t` | 16 | u32 @0/4/8/12 |
| `xess_d3d11_execute_params_t` | 120 | 6 ptrs @0..40, f32 @48/52/56, u32 @60/64/68, 6 coord pairs @72..112 |
| `xess_dump_parameters_t` | 24 | ptr @0, u32 @8/12/16 |

Boundary rules (G5, v0.64.4 findings): handles/foreign pointers cross as
`Int`; out-params are one owned `Vec[UInt8]` slot each, read byte-indexed;
nullable args are `Int 0`; C `bool` crosses as `UInt8`; enum args as `Int32`;
no fp returns through cast-calls -- f32 values are decoded from slots with a
pure-arithmetic codec (`xess_f32_from_bits`) and encoded with an exact RNE
integer encoder (`xess_f32_bits_from_f64`), both unit-tested; the callback
setter takes a C-ABI `Int` (0 = none) because fn values cannot cross to C on
this pin (B-13/B-18/B-22); all outcomes are flat structs.

## 6. Runs (v0.64.4)

| Environment | Command | Result |
|-------------|---------|--------|
| Default PATH (no runtime) | `scripts/port.ps1 -Package xiom.xess` | **PASS 24/24 x2** -- typed SKIP classification + all host-independent checks |
| Pin clone `bin` prepended to PATH | same | **PASS 29/29 x2** -- 37/37 core + 4/4 D3D11 entries resolved, xessGetVersion, VK extension query, companion-absent typed error, handles closed |

Present-path evidence from the pin binaries: `xessGetVersion` -> rc 0,
version `2.0.2` (the SR component's own version; the SDK release tag is 3.0.2);
`xessVKGetRequiredInstanceExtensions` -> rc 0, count 0, minVkApiVersion
1.3.0 (0x403000).  Local samples and hashes: `PROVENANCE.md`.
