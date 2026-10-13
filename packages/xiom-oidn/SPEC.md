# SPEC: xiom.oidn -- Intel Open Image Denoise bindings (loader tier, CPU scope)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.oidn` |
| Version | 0.1.0 |
| Kind | binding (`categories: ["graphics"]`) |
| Upstream project | Intel Open Image Denoise -- https://github.com/RenderKit/oidn |
| Upstream version pinned | tag `v2.5.1`, commit `6602ee2ca38a1a2a02135beed8f6e68eed630180` (2026-08-14) |
| Upstream license | Apache-2.0 (`vendor/LICENSE.txt`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 |
| Compiler pin | v0.64.4 |
| Modules | `xiom.oidn` (root module: loader + full C API surface; the only `extern "C"` in the package -- G5) |
| Runtime soname | `OpenImageDenoise.dll` (release layout: `OpenImageDenoise_core.dll` + `OpenImageDenoise_device_cpu.dll` + `tbb12.dll` companions) |
| Declared scope | **CPU device only**. GPU device variants (SYCL/CUDA/HIP/Metal) are outside the declared scope; see section 4.2. |

## 2. Vendored pin + runtime delivery (G2)

The **public header set of the pin is vendored byte-exact** and is the
declaration oracle and the ABI types used by the bridge at compile time:

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/include/OpenImageDenoise/oidn.h` | 24,768 | `F59758986A79ED60739A9A7A13A39A99CC6C4B35A04D9135769480124FA1F0AF` |
| `vendor/include/OpenImageDenoise/config.h` | 2,289 | `ADBAE7E2649F02278624922DD0EA0399868FEE82D5E22B7BFCF6C63EF83254FA` |
| `vendor/LICENSE.txt` | 11,358 | `CFC7749B96F63BD31C3C42B5C471BF756814053E847C10F3EB003417BC523D30` |

- `oidn.h` is the clone's tree blob at the pin (canonical LF bytes via
  `git cat-file blob`; hash-verified with `git hash-object`); the official
  Windows archive ships the same content with CRLF line endings.
- `config.h` is the upstream-CMake-generated configuration header shipped
  by the official v2.5.1 Windows archive (bytes as shipped, CRLF;
  `oidn.h` includes it, so it is part of the vendored header set).
- `.gitattributes` pins `vendor/** -text` (byte identity).

### 2.1 Why the C++ CPU library is loaded, not compiled in-pipeline

The OIDN CPU device is implemented by ISPC kernels (`devices/cpu/**/*.ispc`)
compiled by the ISPC compiler into per-ISA objects at build time, plus
oneTBB tasking. The v0.64.4 `--c-source` pipeline drives plain
`clang`/`clang++` only: it cannot run ISPC, and the repo does not commit
binary build artifacts (`.gitignore` excludes `*.obj/*.o/*.lib`; no package
vendors binaries). Compiling the CPU device from the vendored sources is
therefore **blocked on ISPC support in the pipeline** (see `ROADMAP.md`);
the same constraint is why other compiler-driven C++ libraries in the lane
use the loader tier.

The runtime is therefore the **official upstream v2.5.1 Windows binary
distribution**, used as a documented local sample and **never committed**:

| Local sample artifact (E:\repos\oidn-release) | Bytes | SHA256 |
|-----------------------------------------------|-------|--------|
| `oidn-2.5.1.x64.windows.zip` (official archive) | 56,619,412 | `F11F91BC072A5E3A564515724CB72AB8FCFBC445C84A84C197FF9B16CC01396F` |
| `cpu/OpenImageDenoise.dll` | 190,384 | `64CEB78B1E10342A5323EAD6F346D7F2B2E1C69FE17C399BEBBCEF3DF26BED16` |
| `cpu/OpenImageDenoise_core.dll` | 50,634,160 | `18557E4424297ED892F2A0285DD565EC9065234A84BAC1B84D16FD995371A422` |
| `cpu/OpenImageDenoise_device_cpu.dll` | 663,984 | `E22617F115AE4056C3417983545AEBED1D75AC7C1BACA086C39D18A84BF47D78` |
| `cpu/tbb12.dll` | 352,144 | `454EA95817CD33B837540BBFE21F6BF415F6FBF2AD712C2353896D17492E763D` |

Download: `https://github.com/RenderKit/oidn/releases/download/v2.5.1/oidn-2.5.1.x64.windows.zip`
(extracted `bin/` minus the GPU/SYCL device DLLs, giving a CPU-only device
profile: `oidnGetNumPhysicalDevices()` reports 1 and the GPU support flags
report false). Prepend a directory holding these four DLLs to `PATH` for
the present-path run; see section 5 for the exact evidence commands.

Re-pin: advance `E:\repos\oidn` to the new tag, re-extract `oidn.h` +
`LICENSE.txt` (`git cat-file blob`), refresh `config.h` from the matching
official release archive, recompute both tables, re-run
`scripts/port.ps1 -Package xiom.oidn -TimeoutSec 240` x2 (present + absent
profile), update the version rows.

## 3. Design and safe boundary (G5)

`src/oidn_bridge.cpp` (self-contained C++; compiled by the suite via
`port.args.json` `--c-source`) is the loader and the whole FFI:

- Includes the vendored `oidn.h`/`config.h` for ABI-exact types; every
  resolved entry point is typed with `decltype(&oidnX)`, so signature drift
  against the pinned header is a compile error.
- Resolves `OpenImageDenoise.dll` with `LoadLibraryA`/`GetProcAddress`
  (67 required exports, table in `kOidnRequired`); no import library and no
  link-time dependency on the runtime.
- Handles cross the FFI as `Int`; **all pointer casts happen in C** (B-25).
- Out-params are XIOM-owned byte slots (`unsigned char*`), written
  little-endian by C and read byte-indexed in XIOM; one owned slot per
  out-param (B-11/B-16/B-17/B-24).
- Image data moves only through owned `Vec[UInt8]` buffers
  (`xo_oidn_buffer_read/write`); foreign pointers are never dereferenced
  from XIOM (B-20). `oidnGetBufferData` is exposed as an integer address
  value for evidence only.
- No bare `null` crosses from XIOM: every pointer argument is an owned
  slot, a `Str` handle, or built inside the bridge (B-23).
- Flat outcome structs only -- never `Result[Option[T]]` (B-26); `Result`
  payloads are copied to locals before any mutation (B-21).
- `oidnSetDeviceErrorFunction` / `oidnSetFilterProgressMonitorFunction`
  take a **bridge-owned C callback** (hit counters + last message exposed),
  so no XIOM `fn` value crosses to C (B-13/B-18/B-22 family).

Error model: every operation drains the pending OIDN error queue, calls,
then returns the OIDN error code; on failure the message is retrievable
through `xo_oidn_error()` and becomes the `OidnError.message` of the typed
result. Handle-returning entry points report the real code as a negative
return (`-code`) so typed errors keep the upstream classification.

## 4. Declared surface and coverage (100%)

### 4.1 The public C API of oidn.h v2.5.1 -- 67 functions, all bound

All 67 functions are resolved at load (evidence: `resolved=67/67`,
`oidn_export_count() == 67`) and every one has a typed module wrapper:

| oidn.h C API | Module wrapper |
|--------------|----------------|
| `oidnGetNumPhysicalDevices` | `oidn_get_num_physical_devices` |
| `oidnGetPhysicalDeviceBool/Int/String/Data` | `oidn_get_physical_device_bool/int/string/data` |
| `oidnIsCPUDeviceSupported` | `oidn_is_cpu_device_supported` |
| `oidnIsCUDADeviceSupported` | `oidn_is_cuda_device_supported` |
| `oidnIsHIPDeviceSupported` | `oidn_is_hip_device_supported` |
| `oidnIsMetalDeviceSupported` | `oidn_is_metal_device_supported` |
| `oidnNewDevice` | `oidn_new_device` |
| `oidnNewDeviceByID` | `oidn_new_device_by_id` |
| `oidnNewDeviceByUUID` | `oidn_new_device_by_uuid` |
| `oidnNewDeviceByLUID` | `oidn_new_device_by_luid` |
| `oidnNewDeviceByPCIAddress` | `oidn_new_device_by_pci_address` |
| `oidnNewCUDADevice` | `oidn_new_cuda_device` (single pair) |
| `oidnNewHIPDevice` | `oidn_new_hip_device` (single pair) |
| `oidnNewMetalDevice` | `oidn_new_metal_device` (single queue) |
| `oidnRetainDevice` / `oidnReleaseDevice` | `oidn_retain_device` / `oidn_release_device` |
| `oidnSetDeviceBool` / `oidnSetDeviceInt` | `oidn_set_device_bool` / `oidn_set_device_int` |
| `oidnGetDeviceBool` / `oidnGetDeviceInt` | `oidn_get_device_bool` / `oidn_get_device_int` |
| `oidnSetDeviceErrorFunction` | `oidn_set_device_error_function` (+ `oidn_device_error_function_hits/last`) |
| `oidnGetDeviceError` | `oidn_device_get_error` (+ `oidn_device_clear_errors`) |
| `oidnCommitDevice` / `oidnSyncDevice` | `oidn_commit_device` / `oidn_sync_device` |
| `oidnNewBuffer` / `oidnNewBufferWithStorage` | `oidn_new_buffer` / `oidn_new_buffer_with_storage` |
| `oidnNewSharedBuffer` | `oidn_new_shared_buffer` (over owned memory) |
| `oidnNewSharedBufferFromFD/Win32Handle/Metal` | `oidn_new_shared_buffer_from_fd/win32_handle/metal` |
| `oidnGetBufferSize` / `oidnGetBufferStorage` | `oidn_get_buffer_size` / `oidn_get_buffer_storage` |
| `oidnGetBufferData` | `oidn_get_buffer_data_addr` (integer address, evidence only) |
| `oidnReadBuffer` / `oidnReadBufferAsync` | `oidn_read_buffer` / `oidn_read_buffer_async` |
| `oidnWriteBuffer` / `oidnWriteBufferAsync` | `oidn_write_buffer` / `oidn_write_buffer_async` |
| `oidnRetainBuffer` / `oidnReleaseBuffer` | `oidn_retain_buffer` / `oidn_release_buffer` |
| `oidnNewSharedSemaphoreFromFD` | `oidn_new_shared_semaphore_from_fd` |
| `oidnNewSharedSemaphoreFromWin32Handle` | `oidn_new_shared_semaphore_from_win32_handle` |
| `oidnSignalSemaphoresAsync` | `oidn_signal_semaphores_async` |
| `oidnWaitSemaphoresAsync` | `oidn_wait_semaphores_async` |
| `oidnRetainSemaphore` / `oidnReleaseSemaphore` | `oidn_retain_semaphore` / `oidn_release_semaphore` |
| `oidnNewFilter` | `oidn_new_filter` |
| `oidnRetainFilter` / `oidnReleaseFilter` | `oidn_retain_filter` / `oidn_release_filter` |
| `oidnSetFilterImage` | `oidn_set_filter_image` |
| `oidnSetSharedFilterImage` | `oidn_set_shared_filter_image` (over owned memory) |
| `oidnUnsetFilterImage` | `oidn_unset_filter_image` |
| `oidnSetSharedFilterData` | `oidn_set_shared_filter_data` |
| `oidnUpdateFilterData` / `oidnUnsetFilterData` | `oidn_update_filter_data` / `oidn_unset_filter_data` |
| `oidnSetFilterBool/Int/Float` | `oidn_set_filter_bool/int/float` |
| `oidnGetFilterBool/Int/Float` | `oidn_get_filter_bool/int` / `oidn_get_filter_float_bytes` |
| `oidnSetFilterProgressMonitorFunction` | `oidn_set_filter_progress_monitor` (+ `oidn_filter_progress_hits/reset`) |
| `oidnCommitFilter` | `oidn_commit_filter` |
| `oidnExecuteFilter` / `oidnExecuteFilterAsync` | `oidn_execute_filter` / `oidn_execute_filter_async` |

Skips: **0**.

### 4.2 Documented exclusions (out of the DECLARED scope)

- `oidnIsSYCLDeviceSupported`, `oidnNewSYCLDevice`,
  `oidnExecuteSYCLFilterAsync` -- declared in `oidn.h` only under
  `#if defined(__cplusplus)` and typed on `sycl::device/queue/event`:
  C++-only, GPU scope, not part of the C surface.
- GPU device support (CUDA/HIP/Metal/SYCL): the C entry points of the
  enumerated surface are bound (support flags, device creation) and their
  typed-unsupported paths are in scope on a CPU-only runtime; no GPU
  present-path is claimed or tested.
- Deprecated inline aliases (`oidnSetDevice1b/1i`,
  `oidnGetDevice1b/1i`, `oidnSetDeviceUInt`, `oidnGetDeviceUInt`,
  `oidnSetFilter1b/1i/1f`, `oidnGetFilter1b/1i/1f`,
  `oidnRemoveFilterImage/Data`) -- inline C++ helpers in `oidn.h`, not
  exported functions of the library.
- The C++ convenience API (`oidn.hpp`) and the upstream CLI tools
  (`oidnDenoise`, `oidnBenchmark`, `oidnTest`) are out of scope.

## 5. Runtime classification (G3) and suite

The suite (`tests/test_conformance.xi`) is deterministic and SKIP-safe:

| Classification | Condition | Outcome |
|----------------|-----------|---------|
| ABSENT (`OIDN_LOAD_ABSENT`) | `OpenImageDenoise.dll` not resolvable | `[PASS]` classification checks; present-path sections reported `[SKIP]`; exit 0, 4/4 |
| ABI (`OIDN_LOAD_ABI`) | library resolves but required exports are missing | `[FAIL]`, exit 1 |
| PRESENT | 67/67 exports resolve | full functional profile, 33/33 |

Sections (present profile, 33 checks):

1. constants vs `oidn.h`; export table 67; bogus-soname ABSENT; 67/67 resolve.
2. device enumeration (CPU physical device + name), lifecycle (create/commit/
   sync/retain/release/version assert `20501` = 2.5.1), typed errors (unknown
   param, double commit), bridge error callback.
3. buffers: create/size/storage/data-address, byte-exact round trip, partial
   range read, async round trip + sync, shared buffer over XIOM-owned memory,
   Win32 external-memory import typed error.
4. filters: RT + RTLightmap construction, unknown type typed error, bool/int
   param round trip, invalid quality typed error, unknown float getter error.
5. CPU denoise: deterministic in-test fixture (8x8 float RGB color with an
   LCG-driven band pattern + albedo + normal guides; exact IEEE-754 bit
   patterns), commit-without-images typed error, execute on CPU, progress
   monitor fired, output finite 192/192 and changed vs input, byte-level diff.
6. repeat determinism (bit-identical async rerun), shared-image path (OIDN
   reads/writes XIOM-owned image memory directly), teardown + unload.

Evidence (recorded runs, 2026-10-13, v0.64.4, local sample on PATH):

```
scripts/port.ps1 -Package xiom.oidn -TimeoutSec 240   -> PASS passed=33 failed=0   (x2)
scripts/port.ps1 -Package xiom.oidn -TimeoutSec 240   -> PASS passed=4  failed=0   (absent profile)
  stats: finite=192 changed=192 min_milli=418 max_milli=656 mean_milli=565
  denoise byte-level diff vs input: 547 bytes; progress hits: 27
```

## 6. Platform and runtime dependencies

| Field | Value |
|-------|-------|
| Platforms | `windows-x64` |
| Runtime deps | `OpenImageDenoise.dll` (loader-resolved at call time; not committed). Companion DLLs `OpenImageDenoise_core.dll` + `OpenImageDenoise_device_cpu.dll` + `tbb12.dll` must be co-located/on `PATH`. |
| Kernel surface | `kernel32` (LoadLibraryA/GetProcAddress/FreeLibrary) only |
| Staging | allowlist NOT yet appended for `xiom.oidn` (native lane owns `.github/publish-allowlist.txt`) |

## 7. Known limits

- Denoising is validated on the CPU device only, with tiny in-test images
  (8x8) -- no performance claims.
- Semaphores: only the no-op (count 0) and the typed-unsupported creation
  paths are exercised (the CPU device exposes no external semaphore types).
- `oidnSetSharedFilterData`/`UpdateFilterData`/`UnsetFilterData` are bound
  and leak-free (unknown names are warnings upstream); no present-path data
  blob (e.g. custom weights) is claimed in 0.1.0.
- The progress monitor and error function are bridge-owned counters and
  messages (no XIOM callback values cross to C on this pin).
