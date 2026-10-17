# PROVENANCE: xiom.optix

Owner policy: reference-only dynamic loading for closed/driver SDKs
(`docs/UPSTREAM-FIRST.md`; FFmpeg / DLSS / NRD precedent).  **Nothing from
NVIDIA is vendored, linked at build time, downloaded by the package, or
committed.**  The package ships independent declarations of interface facts
and loads the user's own runtime.

## 1. License check (before any acquisition attempt)

| Item | Finding |
|------|---------|
| Full SDK | NVIDIA OptiX SDK, offered on <https://developer.nvidia.com/designworks/optix/download> under the **SOFTWARE DEVELOPER KITS, SAMPLES AND TOOLS LICENSE AGREEMENT** ("By clicking the Accept & Download button ... you are confirming that you have read and agree to be bound by ...").  Proprietary; not an OSI license. |
| Public headers | `https://github.com/NVIDIA/optix-dev` -- SPDX `LicenseRef-NvidiaProprietary` in every header ("NVIDIA ... retains all intellectual property and proprietary rights ... Any use, reproduction, disclosure or distribution ... without an express license agreement ... is strictly prohibited"). |
| Runtime | `nvoptix.dll` is a component of the user's NVIDIA display driver (proprietary).  It is not redistributable by this package. |
| Package license | MIT OR Apache-2.0, covering only XIOM-authored code and the independent interface declarations. |

Consequences enforced here:

1. No SDK header, sample, shader, import library, `.lib`, `.dll` or doc text
   is copied into this repository.
2. The bridge declares only the ABI facts needed for interop (export name,
   function-table slot order, struct field order/sizes, numeric constants,
   error codes).  This is the same category used by the DLSS/NRD/DXC
   precedents.
3. The loader reads the runtime from the user's installation at run time
   (DriverStore / System32 / Program Files / `XIOM_OPTIX_DLL`).  It never
   downloads, copies or commits it.
4. The suite uses deterministic self-built probes (bogus loader path,
   invalid PTX, null-miss group, raygen-less pipeline, params pattern); no
   NVIDIA test vector is imported.

## 2. Acquisition attempt (2026-10-17, headless)

The mission asked for an official SDK fetch into `E:\repos\optix`.  The
official route is **registration-gated**:

| Step | Evidence |
|------|----------|
| Download page | <https://developer.nvidia.com/designworks/optix/download> states "To download, you must be a member of the NVIDIA Developer Program"; the Windows button targets `https://developer.nvidia.com/downloads/designworks/optix/secure/9.1.0/nvidia-optix-sdk-9.1.0-win64.exe` (OptiX SDK 9.1). |
| Direct link HEAD | HTTP **307** -> `https://developer.nvidia.com/login` (no session), `2026-10-17T14:54:44Z` |
| CDN host | `https://developer.download.nvidia.com/designworks/optix/secure/9.1.0/nvidia-optix-sdk-9.1.0-win64.exe` -> **403** (`403.html`), same time |
| Result | The full SDK installer was **not obtained**.  No fake build, no substitute binary; the live launch leg is gated on user-supplied PTX. |

The official **public header subset** was obtained from NVIDIA's own
`NVIDIA/optix-dev` repository (not the gated SDK installer):

| Field | Value |
|-------|-------|
| Tag | `v9.1.0` |
| Commit | `f1f6dd803f3159992d248178f6e09421c6eb8b6d` |
| Files fetched | `optix.h`, `optix_device.h`, `optix_function_table.h`, `optix_host.h`, `optix_stubs.h`, `optix_types.h` into `E:\repos\optix\include` (outside the repo) |
| Hashes | recorded in `SPEC.md` section 2.2 |

The headers were read only as the declaration oracle.  They are **not**
committed and the build does not include them (`port.args.json` compiles
only `src/optix_bridge.c`).

## 3. Runtime sample (not committed)

| Artifact | Value |
|----------|-------|
| `nvoptix.dll` version 9.1.2, selected from DriverStore | `C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_b20cc8aeaed64fc2\nvoptix.dll` -- 83,233,000 B, SHA256 `AED7BFC4AFB3616BEE65BDBED54F051E4E18BD7FDBD928DE7A09E2E0085851E0` |
| Other copies on the host | `a3944b54...` 83,233,000 B `C1475123...`; `c8bc8425...` 49,398,504 B `66DA2A82...` |
| Display driver | 616.92 (CUDA driver API 13040) |
| GPU | NVIDIA GeForce RTX 3070 Ti, compute capability 8.6, RT core 2.0 |
| Discovery rule | newest `nv_dispi.inf_amd64_*\nvoptix.dll` by directory `LastWriteTime`; explicit paths win; `XIOM_OPTIX_NO_AUTO=1` disables auto-discovery |
| Live probe | ABI 118, rtcore 20, max trace depth 31, cache enabled, context create/validate/destroy |

The DLL stays in the driver store; the package never copies it.  `E:\repos\optix`
contains only the reference headers and throw-away probe sources used to
validate the ABI (outside the repository).

## 4. Acquisition contract (user drops the SDK)

To use the full SDK surface (samples, PTX authoring, documentation):

1. Join the NVIDIA Developer Program and accept the SDK license at
   <https://developer.nvidia.com/designworks/optix/download>.
2. Download `nvidia-optix-sdk-9.1.0-win64.exe` (or the current release) and
   install/extract it under `E:\repos\optix` (or any user-chosen path).
   Keep it outside this repository; do not commit headers, samples or
   binaries.
3. The SDK's `include/` then contains the same headers pinned in
   `SPEC.md`; `nvoptix.dll` still comes from the display driver, not the SDK.
4. Author/compile PTX with the SDK samples or your own nvcc project and pass
   it to `optix_module_load`; the launch-params variable name/size must match
   the PTX (`optixLaunchParams` in the samples is a common choice).
5. Point the loader at a specific runtime with `XIOM_OPTIX_DLL` or
   `optix_probe_named(path)` if it is not in the standard locations.

If the SDK is unavailable, the package remains useful: the loader, typed
surface, context/options, module error handling, miss group, SBT packing,
pipeline validation and params buffer are exercised live against the driver
runtime; the raygen launch is the only gated leg.

## 5. Derived vs independent

**Independent (XIOM-authored, MIT OR Apache-2.0):**

- `optix.xi` -- typed loader surface, handle wrappers, error mapping, SBT
  size math, contracts.
- `src/optix_bridge.c` -- original C bridge: Win32 loader, CUDA driver
  context, ABI-mirror structs, function-table indices, resource handles,
  typed error text.  No NVIDIA code.
- `tests/test_conformance.xi` -- original deterministic probes.
- `README.md`, `SPEC.md`, `AUDIT.md`, `ROADMAP.md`, `docs/COVERAGE.md`.

**Upstream (studied, never committed):** the OptiX SDK (not obtained) and
the `NVIDIA/optix-dev` public headers (reference oracle, hashed in
`SPEC.md`).

## 6. Re-pin / re-carve

1. Refresh `E:\repos\optix\include` from the new `NVIDIA/optix-dev` tag;
   update the commit + hashes in `SPEC.md`.
2. Diff the 60-slot function table and the mirrored struct sizes; update the
   bridge (named slots make insertions visible).
3. Re-run the suite x2 and the `XIOM_OPTIX_NO_AUTO=1` SKIP run; record in
   `STATUS.json`.
4. If the driver's `nvoptix.dll` changes, record its version/path/hash in
   section 3.
