# SPEC: xiom.optix -- NVIDIA OptiX ray-tracing engine bindings

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.optix` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Target | NVIDIA OptiX 9.1 host API (`OPTIX_ABI_VERSION` 118) via the display-driver runtime `nvoptix.dll` |
| Upstream | NVIDIA OptiX SDK / runtime -- proprietary, **nothing vendored** |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (loader + CUDA driver context); Linux is a ROADMAP item |
| Compiler pin | v0.64.6 |
| Modules | `xiom.optix` |

## 2. Pin: ABI, headers, runtime sample

### 2.1 ABI

- `OPTIX_ABI_VERSION` **118** (OptiX 9.1).
- `nvoptix.dll` exports exactly two names: `optixQueryFunctionTable` and the
  legacy `rtGetSymbolTable` (observed with `dumpbin /exports`).  The package
  resolves `optixQueryFunctionTable`, requests ABI 118 with a 60-pointer
  (480-byte) function table, and requires exact size agreement.  Older ABI
  versions return `OPTIX_ERROR_FUNCTION_TABLE_SIZE_MISMATCH` (7802) for this
  table size and are classified as a typed ABI failure (update the driver).

Function-table slots used by the bridge (full 60-slot order pinned from
`optix_function_table.h` @ v9.1.0):

| Slot | Entry | Use |
|------|-------|-----|
| 0 / 1 | `optixGetErrorName` / `optixGetErrorString` | typed error text |
| 2 / 3 / 4 | `optixDeviceContextCreate` / `Destroy` / `GetProperty` | context + validate |
| 6 / 7 / 9 | `optixDeviceContextSetCacheEnabled` / `SetCacheLocation` / `GetCacheEnabled` | context options |
| 12 / 18 | `optixModuleCreate` / `Destroy` | PTX module load |
| 24 / 25 | `optixProgramGroupCreate` / `Destroy` | raygen/miss/hitgroup |
| 27 / 28 | `optixPipelineCreate` / `Destroy` | pipeline link |
| 48 / 49 | `optixSbtRecordPackHeader` / `optixLaunch` | SBT + launch |

Mirrored x64 struct sizes (verified against the pinned headers): module
compile options 48 B, pipeline compile options 56 B, program-group desc 56 B,
program-group options 8 B, pipeline link options 20 B, SBT 64 B.
SBT record header 32 B, alignment 16 B.

### 2.2 Declaration oracle (reference-only, not committed)

NVIDIA's official public header subset:

| Field | Value |
|-------|-------|
| Repository | `https://github.com/NVIDIA/optix-dev` |
| Tag | `v9.1.0` |
| Commit | `f1f6dd803f3159992d248178f6e09421c6eb8b6d` |
| License | `LicenseRef-NvidiaProprietary` (header SPDX line) |
| Local study clone | `E:\repos\optix\include` (not in the package) |

| Header | SHA256 |
|--------|--------|
| `optix.h` | `65B70A4A33D3EE4D0CE8B2A90DEBDB2CAA4EAA0A38129092EE5EACDF6A1984A7` |
| `optix_device.h` | `9C921BA108D7890DF79F218A3675ACE3D1A5A2785E29E4D052DDE01A7E949CFA` |
| `optix_function_table.h` | `A885A24230F7D1F89A2E753BC66B0ADAE7F84CEECEA50CAB67DC370C147E27DE` |
| `optix_host.h` | `DEB94FB5EEBE8509B507EBD9633398127E4BBBCD32D41383401DA22440F2CB38` |
| `optix_stubs.h` | `8353F4A14951956F771A6208669BA6D17B2D34877459628785E7339B97EDA0CA` |
| `optix_types.h` | `42928FA0FC471F09EFF90C8FF96D541CAB9062602F98CE50C2C2AA40A62440F6` |

### 2.3 Local runtime sample (NOT the pin; not committed)

| Field | Value |
|-------|-------|
| Module | `nvoptix.dll`, version **9.1.2** (`9.1.2 64-bit CL: 38780218 release`) |
| Selected by the loader | newest `nv_dispi.inf_amd64_b20cc8aeaed64fc2\nvoptix.dll`, 83,233,000 B, SHA256 `AED7BFC4AFB3616BEE65BDBED54F051E4E18BD7FDBD928DE7A09E2E0085851E0` |
| Other DriverStore copies | `a3944b54...` 83,233,000 B `C1475123...`; `c8bc8425...` 49,398,504 B `66DA2A82...` (same version, older/other driver packages) |
| Display driver | 616.92 (CUDA driver API 13040) |
| GPU | `NVIDIA GeForce RTX 3070 Ti`, compute capability 8.6 |
| OptiX probe values | ABI 118, RT core 2.0 (`rtcore_version=20`), max trace depth 31, cache enabled |
| DriverStore discovery | `GetWindowsDirectoryW` + `FindFirstFileW` over `System32\DriverStore\FileRepository\nv_dispi.inf_amd64_*`, newest `LastWriteTime`, then `LoadLibraryW` |

### 2.4 Re-pin procedure

1. Fetch the new `NVIDIA/optix-dev` tag; update the commit, header hashes and
   `OPTIX_ABI_VERSION` in this file and `optix_bridge.c`.
2. Re-check the 60-slot table order and every mirrored struct size against
   the new `optix_function_table.h` / `optix_types.h` (the bridge uses named
   slots, so an inserted field is a real ABI change).
3. Run the suite x2 on the new driver; record `STATUS.json`; re-run the
   `XIOM_OPTIX_NO_AUTO=1` SKIP run.
4. Update `PROVENANCE.md` with the new runtime sample hashes.

## 3. Design and safe boundary (G5)

`optix.xi` is the only module with `unsafe`/`extern "C"`.  It calls the
integer/handle bridge `src/optix_bridge.c`, which:

- loads `nvoptix.dll` at run time (explicit path, env var, module search,
  Program Files, System32, DriverStore) -- nothing is linked or vendored;
- loads `nvcuda.dll` and creates its own CUDA context on device 0 (the OptiX
  device context is created from it);
- queries the pinned function table and caches the info values;
- owns context/module/group/SBT/pipeline/params handles (positive pointer
  values, magic-tagged); XIOM only ever sees `Int` handles (B-25);
- writes into XIOM-owned `Vec[UInt8]` slots for SBT/params readback (B-20 /
  B-24); all other data stays inside the bridge;
- returns `0` / `-(100 + kind)`; the native `OptixResult` and message are
  retrieved through getters, so no out-params cross the FFI boundary (B-11).

Ownership is explicit and single-threaded: children must be destroyed before
the context, and the context before the process exits.  `optix_context_destroy`
destroys the OptiX and CUDA contexts; all API objects must already be gone.

### 3.1 Classification

| Condition | Bridge kind | Suite |
|-----------|-------------|-------|
| `nvoptix.dll` absent / explicit bogus path | `OPTIX_ERR_LOADER_ABSENT` | SKIP (green) |
| no CUDA device / `cuInit` no-device | `OPTIX_ERR_NO_DEVICE` | SKIP (green) |
| runtime present, ABI/table mismatch | `OPTIX_ERR_ABI` | FAIL |
| bridge argument/range error | `OPTIX_ERR_ARG` | FAIL |
| context/module/group/pipeline/SBT/params/launch failure | matching kind + native code | FAIL |

The deterministic SKIP path is exercised on every host by
`optix_probe_named("xiom-absent-optix-probe-xyz.dll", false)`.
`XIOM_OPTIX_NO_AUTO=1` disables auto-discovery for the full SKIP-safe run on
a host that does have a driver.

## 4. Declared essentials and evidence

| Essential | API | Live evidence (RTX 3070 Ti, 2026-10-17) |
|-----------|-----|----------------------------------------|
| Context create/destroy/validate | `optix_context_create` / `_destroy` / `_validate` | created, properties queried, destroyed |
| Device context options | `OptixContextOptions` | validation/log level accepted; `cache_enabled=false` verified |
| Module load | `optix_module_load` | live runtime reached; invalid PTX -> kind `module`, native 7200 + compile log |
| Program groups (raygen/miss/hitgroup) | `optix_program_group_create` | null-miss group created/destroyed live; raygen/hitgroup need user PTX |
| SBT build | `optix_sbt_build` + record readback | 64-B record packed by the runtime, device->host header non-zero |
| Pipeline create | `optix_pipeline_create` | runtime link attempted; raygen-less pipeline -> kind `pipeline`, native 7001 + "kind raygen" log |
| Launch params buffer | `optix_params_create` / `_write` / `_read` / `_destroy` | 64-B host -> device -> host pattern round trip |
| Launch | `optix_launch` | declared and guarded; needs a valid raygen pipeline + PTX |
| Typed errors | `OptixError{kind,code,message}` | SKIP/FAIL mapping + native code/log asserted |
| SKIP-safe suite | `tests/test_conformance.xi` | live 37/37 x2; absent-runtime 15/15 |

The **full launch happy path is gated on user-supplied PTX**: the SDK is
registration-gated and no shader is vendored.  This is recorded, not faked.

## 5. Test contract

Suite: `tests/test_conformance.xi` (37 checks live; 15 when the runtime is
absent).  Command (the C bridge rides in `port.args.json`):

```
.\scripts\port.ps1 -Package xiom.optix -TimeoutSec 300
```

Watchdog: 300 s (the 83 MB runtime load + context bring-up is the slow part;
the suite finishes in a few seconds on the development host).

The suite covers: ABI pin, error-kind surface, SBT size math, deterministic
absent path, live probe, context lifecycle, context options, module error,
miss group + SBT + readback, pipeline validation error, params round trip.
Every live check reports `[PASS]` with `SKIP -- ...` when the runtime is
absent, so CI stays green.

## 6. Tooling note

Package `.xi` files must be **BOM-free**.  The compiler's catalog header
reader (`read_module_header`) does not skip a UTF-8 BOM, so a BOM before
`module xiom.optix` makes the package module invisible to `use xiom.optix`
and surfaces as an unresolved import.  All files here are written without a
BOM; keep it that way when editing with Windows PowerShell 5.1
(`Set-Content -Encoding UTF8` adds one).

## 7. Scope (0.1.0)

In: the declared essentials above, one program group of each kind per SBT /
pipeline, one record per kind, default-stream launch.

Out (Phase 2, `ROADMAP.md`): acceleration-structure build, denoiser, curves /
spheres / micromaps, callables and multi-record SBT arrays, multiple
pipelines, CUDA interop with a caller-owned context, PTX file/byte helpers,
SDK sample integration, Linux.
