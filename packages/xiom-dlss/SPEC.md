# SPEC: xiom.dlss -- NVIDIA DLSS / NGX bindings (CLOSED-SDK pattern)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.dlss` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | NVIDIA DLSS SDK -- https://github.com/NVIDIA/DLSS |
| Upstream version pinned | **v310.9.1** (commit `374959484e79a640feaba44c93ac8cfb0a03f5b5`, 2026-09-08; latest release) |
| Upstream license | **NVIDIA RTX SDKs License** -- CLOSED, reference-only, nothing vendored (`PROVENANCE.md` section 2) |
| Package license | MIT OR Apache-2.0 (this package's own code + declarations only) |
| Platform | Windows x64 (`nvngx*.dll` loader surface; SKIP when absent) |
| Compiler pin | v0.64.4 |
| Modules | `xiom.dlss`, `xiom.dlss.surface` (declared in `package.xi`) |

## 2. Declaration oracle (reference-only clone)

Pinned clone: `E:\repos\DLSS` @ `37495948` (shallow, tag `v310.9.1`;
registered in `E:\repos\CLEANUP.md` with the CLOSED license note; nothing
from it is committed).

Read as the declaration oracle:

- `include/nvsdk_ngx.h`, `nvsdk_ngx_defs.h`, `nvsdk_ngx_params.h`,
  `nvsdk_ngx_defs_dlssd.h`, `nvsdk_ngx_defs_dlssg.h`, `nvsdk_ngx_vk.h`,
  `nvsdk_ngx_defs_vk.h`, `nvsdk_ngx_helpers*.h` -- the declared API.
- `lib/Windows_x86_64/*/nvngx_dlss.dll` / `nvngx_dlssg.dll` /
  `nvngx_dlssd.dll` -- observed export oracles (`llvm-objdump -p`), used to
  verify that the declared table resolves against real runtime modules:

| Module | Named exports | Declared-table hits | Breakdown |
|--------|---------------|---------------------|-----------|
| `nvngx_dlss.dll` (SR) | 59 | **41/85** | D3D11 9, D3D12 9, CUDA 10, VULKAN 13 |
| `nvngx_dlssg.dll` (FG) | 50 | **36/85** | D3D11 9, D3D12 9, CUDA 7, VULKAN 11 |
| `nvngx_dlssd.dll` (RR) | 54 | **41/85** | D3D11 9, D3D12 9, CUDA 10, VULKAN 13 |

The feature modules carry the per-API *snippet* subset (init/create/evaluate/
release/scratch/requirements); the full declared table additionally needs
the **core proxy** (`nvngx.dll` / `_nvngx.dll`, installed by the NVIDIA
driver) for the parameter C API, `Get*/AllocateParameters`,
`DestroyParameters`, `EvaluateFeature_C`, `UpdateFeature` and the
project-id inits.  The in-suite present path proves the 41/85 direct
resolution with the real `nvngx_dlss.dll` (`XIOM_DLSS_DIR`,
`AUDIT.md` run evidence).

### Regeneration

`tools/gen_surface.py` (committed) reads the pinned headers and emits
`src/surface.xi`:

- every declared-table name is verified against the pinned headers (the
  four `..._Init_ProjectID` runtime spellings are runtime facts from the
  SDK's own loader strings -- informational, not header declarations);
- the 435 parameter keys and 74 effective-key codes are transcribed
  mechanically (deduped; conflicting duplicates abort).

```
python tools/gen_surface.py          # rewrite src/surface.xi
python tools/gen_surface.py --check  # verify in sync
```

Re-pin procedure: refresh the clone at the new tag, update `CLEANUP.md`,
re-run the generator, re-verify the observed export counts (`llvm-objdump
-p`), re-run the suite x2, record.

## 3. Declared surface (100% exposed)

| Surface | Count | Where |
|---------|-------|-------|
| Entry-point table (resolvable export names) | **85** | `surface.dlss_table_entries()` |
| -- core D3D11 / D3D12 / CUDA / VULKAN | 15 / 15 / 17 / 20 | `DLSS_GROUP_CORE_*` |
| -- parameter C API / globals | 16 / 2 | `DLSS_GROUP_PARAMETER` / `_GLOBAL` |
| Parameter keys (`NVSDK_NGX_Parameter_*` + `_DLSSG_Parameter_*`) | **435** | `surface.dlss_param_key_table()` + `pub const` |
| Effective-key byte codes (`NVSDK_NGX_EParameter_*`) | **74** | `surface.NVSDK_NGX_EParameter_*` + `dlss_eparameter_key()` |
| Result codes + SUCCEED/FAILED | 19 + 2 fns | `NVSDK_NGX_RESULT_*`, `dlss_succeeded/failed` |
| Feature ids / flags / perf-quality / SR+RR presets / FG enums | ~70 consts | `dlss.xi` |

100% of the declared table is exposed: every entry is resolvable by name
(`dlss_entry_addr` / `dlss_entry_resolved[_as]`), every key/code constant
is declared, and `dlss_resolved_count` / `_in_group` report coverage.
Nothing in the table is a stub.

"DLSS-SR / DLSS-FG / DLSS-RR entry points": in the NGX runtime model all
three features execute through the **same** per-API entries
(`CreateFeature` / `EvaluateFeature` / `ReleaseFeature` /
`GetFeatureRequirements` / `GetScratchBufferSize`) parameterized by
`NVSDK_NGX_Feature_SuperSampling` (1), `_FrameGeneration` (11),
`_RayReconstruction` (13), with per-feature parameter keys (all declared).
The feature modules `nvngx_dlss/dllssd/dllssg.dll` provide the snippet
subset of those same names (section 2 table).

## 4. Reflex

The pinned public headers do **not** describe the NVIDIA Reflex SDK (no
PCL stats/marker declarations anywhere under `include/`; scan evidence in
`PROVENANCE.md` section 4), so this package declares no Reflex surface:
`DLSS_REFLEX_COVERED = false`, reported by the suite as a typed scope SKIP.

## 5. Typed flows and SKIP semantics

- Loader: `dlss_load()` (common locations: loader search path / cwd /
  `%SystemRoot%\System32`) and `dlss_load_from(...)` (explicit paths for
  hosts/games).  Classification: `DLSS_LOAD_ABSENT` (typed SKIP) or
  `DLSS_LOAD_ABI` (module loaded but D3D12 anchors missing).  Modules are
  never downloaded, never copied, never committed.
- Typed parameter C API: all 16 `NVSDK_NGX_Parameter_*` wrappers; out-params
  land in XIOM-owned slots (`int 0 for absent pointers`, byte-indexed reads,
  float reads through `xiom.ffi` -- B-11/B-12/B-20/B-23/B-24 discipline).
- DLSS-SR sequence: `dlss_sr_create_d3d12` (Width/Height/OutWidth/OutHeight
  + PerfQualityValue + create flags, then CreateFeature),
  `dlss_sr_evaluate_d3d12` (Color/Output/Depth/MotionVectors, jitter,
  sharpness, MV scale with the upstream 0 -> 1.0 defaulting, Reset),
  `dlss_sr_destroy_d3d12` (ReleaseFeature + DestroyParameters),
  `dlss_sr_optimal_settings` (the NGX_DLSS_GET_OPTIMAL_SETTINGS sequence
  incl. the dynamic min/max reads and the callback absence ->
  `FAIL_OUT_OF_DATE` path), `dlss_sr_available` /
  `dlss_fg_available` / `dlss_rr_available` (capability parameters).
- Feature support query: `dlss_d3d12_get_feature_requirements` (entry
  exposed; the discovery/requirement structs follow the pinned layouts and
  are caller-built pointers -- struct builders are a ROADMAP item).
- Every typed wrapper returns `DLSS_RC_UNRESOLVED` (-1) or a flat-outcome
  ok/rc marker when the entry is unresolved, so consumers can branch on the
  SKIP state without special cases.

## 6. Compiler discipline notes

- fp RETURNS through cast calls are never used (B-12): `GetF`/`GetD` read
  XIOM-owned slots through `xiom.ffi`.
- fn-pointer locals are `f_`-prefixed (B-10); `Get*` results are flat
  structs, never `Result[Option[T]]` (B-26); no bare `null` (B-23); no
  `x as *UInt8` handle casts (B-25); one owned slot per out-param.
- **B-27 workaround**: bitwise ops and integer division on Int values
  >= 2^31 miscompile on v0.64.4 (found building this package;
  `docs/repro/bindings-pilot/bigint-bitops/`).  `dlss_failed` therefore uses
  the equivalent boundary form `(rc - 0xBAD00000) in [0, 18]` over the
  pinned 19-code failure space, pinned by the suite; re-probe at v0.64.5+
  and restore a bitwise form if fixed.

## 7. Test matrix

| Configuration | Command | Result |
|---------------|---------|--------|
| Default (no runtime) | `scripts/port.ps1 -Package xiom.dlss` | 21/21 PASS x2 (`STATUS.json`); runtime branches report typed SKIP |
| Present path (local dev) | `$env:XIOM_DLSS_DIR=<dir with nvngx_dlss.dll>; scripts/port.ps1 -Package xiom.dlss` | 22/22 PASS; resolves 41/85 against the pinned real module |

No SKIP path hides a gap: the declared surface checks run unconditionally;
only execution of the NVIDIA runtime is skipped, and an optional present
path exercises the loader + resolution when a runtime is available.
