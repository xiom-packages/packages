# AUDIT: xiom.optix

## Status (2026-10-17, v0.64.6)

New package at 0.1.0: reference-only dynamic-loader binding for the NVIDIA
OptiX 9.1 host API (ABI 118).  No pre-pilot module exists in git history for
this package.  **No NVIDIA artifact is vendored**; the runtime is the user's
driver component and the suite is SKIP-safe.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.6 (installed) |
| Upstream | NVIDIA OptiX 9.1 SDK/runtime -- proprietary, registration-gated, nothing vendored (`PROVENANCE.md`) |
| Reference headers | `NVIDIA/optix-dev` tag `v9.1.0`, commit `f1f6dd80` (hashes in `SPEC.md`) -- read-only oracle, not committed |
| Link model | none at build time; `LoadLibraryA/W` of the user's `nvoptix.dll` + `nvcuda.dll`; only `src/optix_bridge.c` is compiled (`--c-source`) |
| FFI confinement | all `unsafe`/`extern "C"` in `optix.xi`; the bridge is integer/handle-only |
| Surface | context + options + validate, module load, 3 program-group kinds, SBT build/readback, pipeline create, params buffer, launch; 13 typed error kinds |
| Suite | `tests/test_conformance.xi` |
| Live runs | **37/37 PASS x2** (RTX 3070 Ti, driver 616.92, `nvoptix.dll` 9.1.2) |
| SKIP-safe run | **15/15 PASS** with `XIOM_OPTIX_NO_AUTO=1` (live legs report `[PASS] SKIP -- ...`) |
| Publish | held; new package (allowlist/scope owned by the packages lane) |

## Run evidence

Host: Windows x64, NVIDIA GeForce RTX 3070 Ti, driver 616.92, CUDA driver API
13040, OptiX runtime 9.1.2, RT core 2.0.

Live `.\scripts\port.ps1 -Package xiom.optix -TimeoutSec 300` x2:

- pin/error/size checks: 7/7
- deterministic bogus loader path: `LOADER_ABSENT` (SKIP)
- live probe: ABI 118, RT core 20, max trace depth 31, device name
- context: create, validate (ABI/RT core/depth/cache/name), destroy
- options: validation-mode context with `cache_enabled=false`
- module: invalid PTX -> `OPTIX_ERR_MODULE`, native 7200, "COMPILE ERROR" log
- SBT: null-miss group, 64-byte record packed, device readback non-zero
- pipeline: raygen-less link -> `OPTIX_ERR_PIPELINE`, native 7001, "kind
  raygen" log
- params: 64-byte host -> device -> host pattern round trip
- all destroys green

SKIP run: same suite with `XIOM_OPTIX_NO_AUTO=1` -> 15/15 PASS, seven live
checks classified `SKIP -- runtime absent`; no FAIL.

The bridge was also exercised directly by a standalone C harness during
development (loader/table/context/options/module/PG/SBT/pipeline/params);
the harness lives outside the repository and is not part of the package.

## License / security audit

- **License**: full SDK download is gated by the NVIDIA Developer Program and
  the proprietary SDK agreement; the public headers are
  `LicenseRef-NvidiaProprietary`; `nvoptix.dll` is a display-driver
  component.  No artifact is copied, linked, downloaded by the package, or
  committed.  The package's own code is MIT OR Apache-2.0.
- **No secrets**, no network calls, no environment-dependent downloads.
- **Loader**: explicit paths are used as-is; auto-discovery is bounded
  (module search, Program Files, System32, DriverStore with a 1024-directory
  cap).  The driver-store scan only reads directory entries and file
  attributes.
- **Error handling**: every native call is checked; failures carry the
  native `OptixResult` + `optixGetErrorString` and, for compiler/link calls,
  the OptiX log.  No silent failure path.
- **FFI discipline**: handles cross as `Int` (B-25); owned `Vec[UInt8]` slots
  are the only buffers the bridge writes; no bare `null` (empty strings /
  handle 0 are the sentinels, B-23); no out-params (B-11); flat structs, no
  `Result[Option[T]]` (B-26).
- **Ownership**: single-threaded; children must be destroyed before the
  context.  Documented in `SPEC.md` section 3.

## Tooling finding (package-side)

The compiler's catalog header reader does not skip a UTF-8 BOM: a BOM before
`module xiom.optix` makes the module invisible to `use xiom.optix` (the
suite reports an unresolved import with no hint).  All package `.xi` files
are BOM-free; on Windows PowerShell 5.1 use
`[System.IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding($false)))`
instead of `Set-Content -Encoding UTF8`.

## Coverage ledger

| Upstream item | Bound | Tested |
|---------------|-------|--------|
| ABI 118 function-table query + exact size | yes | live probe |
| `optixDeviceContextCreate/Destroy/GetProperty` | yes | live lifecycle + properties |
| `OptixDeviceContextOptions` (validation/log/cache) | yes | live option run |
| cache enable/location/get | enable + get live; location wired | enable/get asserted; location not exercised (would write a cache dir) |
| `optixModuleCreate/Destroy` | yes | live invalid-PTX error + log; success needs user PTX |
| program groups raygen/miss/hitgroup | yes | miss live; raygen/hitgroup need user PTX |
| `optixSbtRecordPackHeader` + SBT layout | yes | live null-miss record + device readback |
| `optixPipelineCreate/Destroy` | yes | live raygen-less validation error; success needs user PTX |
| `optixLaunch` + params buffer | yes | params live round trip; launch guarded, needs raygen pipeline |
| typed errors + SKIP classification | yes | live and SKIP runs |

## Phase 2 audit items

- Acceleration-structure build/relocate/compact (the other half of a ray
  tracer) -- not in 0.1.0.
- Denoiser and callables/exception groups -- declared slots only.
- Multi-record SBT arrays and caller-owned CUDA contexts -- roadmap.
- Linux loader variant -- roadmap.
