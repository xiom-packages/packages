# SPEC: xiom.cufft -- NVIDIA cuFFT bindings (runtime loader, nothing vendored)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.cufft` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Target | NVIDIA cuFFT (CUDA FFT library), loaded from the user's own runtime |
| Upstream | NVIDIA cuFFT 11.4.1 (`nvidia-cufft-cu12` 11.4.1.4 wheel; proprietary) |
| Package license | MIT OR Apache-2.0 (no NVIDIA code in this package) |
| Platform | Windows x64 |
| Compiler pin | v0.64.6 |

## 2. G2 pin: sonames + entry points + constants + header set

**Sonames (tried in order):** `cufft64_12.dll`, `cufft64_11.dll`,
`cufft64_10.dll`. The pinned wheel ships `cufft64_11.dll` (cuFFT 11.x is
the CUDA 12 line; `_12` covers a future CUDA 13 soname). An explicit
`cufft_load_from(dir)` is strict (no bare-name fallback); `cufft_load()`
uses `XIOM_CUFFT_DIR` first, then the OS module search.

**Bound entry points (12):**

| Group | Symbols |
|-------|---------|
| Plans | `cufftPlan1d`, `cufftPlan2d`, `cufftDestroy`, `cufftSetStream`, `cufftGetVersion`, `cufftEstimate1d`, `cufftEstimate2d` |
| Execute | `cufftExecR2C`, `cufftExecC2R`, `cufftExecZ2Z`, `cufftExecD2Z`, `cufftExecZ2D` |

All 12 were verified in the pinned DLL's export table
(`llvm-objdump -p`). `cufftGetVersion` is resolved optionally (Ok(0) if an
older runtime does not export it); every other entry point is required.
The bridge additionally uses `cuInit`, `cuCtxCreate_v2`, `cuCtxDestroy_v2`,
`cuMemAlloc_v2`, `cuMemFree_v2`, `cuMemcpyHtoD_v2`, `cuMemcpyDtoH_v2` from
`nvcuda.dll` for the context and device-memory helpers.

**Constants (cufft.h @ 11.4.1.4):** types `CUFFT_R2C=42`, `CUFFT_C2R=44`,
`CUFFT_C2C=41`, `CUFFT_D2Z=106`, `CUFFT_Z2D=108`, `CUFFT_Z2Z=105`;
directions `CUFFT_FORWARD=-1`, `CUFFT_INVERSE=1`; results `SUCCESS=0`
through `NOT_SUPPORTED=16` (names in `cufft.xi`).

**Header pin (declaration oracle, read from the wheel, never committed):**

| File | Bytes | SHA256 |
|------|-------|--------|
| `cufft.h` | 13,503 | `1FCA833C4E5C3A533C3C832A782FC8C8ED08AA73D310E52AB5EA25127DAC3F5C` |
| `cufftXt.h` | 13,223 | `420EB4CECA7E603C4A483B681D70859518E7E2A869FAF09C696312BDC31CDAA7` |
| `cufftw.h` | 20,516 | `64AFCC68790A4E46A5B2556EAD6502F66CA23AD45EA88EE5B36865B4CF4D335A` |
| `cudalibxt.h` | 4,202 | `A1680320630E760CB28223BE86F720178B1B9777F1D53638665AB1EEBB274591` |

**Artifact pin:** `nvidia_cufft_cu12-11.4.1.4-py3-none-win_amd64.whl`
(200,067,309 B, SHA256
`8E5BFAAC795E93F80611F807D42844E8E27E340E0CDE270DCB6C65386D795B80`);
`cufft64_11.dll` 287,136,768 B, SHA256
`5B90655CA9CDF5D91CBDF2C72B995EC937EED0AEF2D6954370C711B45C929B35`.
Full evidence in `PROVENANCE.md`.

**Runtime sample (NOT the pin; nothing committed):** RTX 3070 Ti,
driver API 13040 (13.4), cuFFT reports version **11401** (11.4.1).

### Re-pin procedure

1. Download the new `nvidia-cufft-cu12` wheel, verify its SHA256, extract
   to `E:\repos\nvidia-math\extract\<wheel>`; copy the DLLs to
   `E:\repos\nvidia-math\runtime` (external scratch).
2. Confirm the bound entry points still exist in the DLL export table and
   re-hash the header set (update tables above + `PROVENANCE.md`).
3. Run the suite x2 with `XIOM_CUFFT_DIR` pointing at the new runtime,
   then record `STATUS.json` (`scripts/status.ps1 -Action update`).

## 3. Design and safe boundary (G5)

`cufft.xi` is the only module with `unsafe`/`extern "C"`. It calls the
integer-only C bridge (`src/cufft_bridge.c`), which:

- loads the module and resolves the 12 entry points (`GetProcAddress`);
  a loaded module with a missing required symbol is `CUFFT_LOAD_ABI`
  (FAIL);
- loads `nvcuda.dll` and creates one CUDA context (`cuCtxCreate_v2`);
  no driver/device is `CUFFT_LOAD_NO_DEVICE` (SKIP);
- creates plans (`cufftPlan1d`/`cufftPlan2d`) and forwards execution
  verbatim; plan handles cross as `int64_t` values (`-1` = bridge failure,
  with the result cached for the typed error);
- exposes `cuMemAlloc_v2`-based buffer helpers (alloc/free/upload/
  download for Float32/Float64 spans; complex data is interleaved).

Bridge state is process-global and single-threaded; the CUDA context is
thread-affine. Destroy plans before unloading; the bridge destroys the
context and unloads the module on `cufft_unload`.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- **45 checks live**, 5 without a
runtime:

| Section | Checks | Content |
|---------|--------|---------|
| A (always) | 4 | deterministic SKIP classification, result-name map, stale-module typed error, pinned constants |
| B (live or SKIP) | 41 | load, version, estimate1d/2d, R2C plan + setStream, R2C all-ones -> DC=8, C2R round trip (8.0 unnormalized), 2D Z2Z 4x4 forward/inverse (16.0), D2Z/Z2D round trip (8.0), 5 plan destroys, 6 buffer frees, unload |

Command (the runner hook adds the C source via `port.args.json`):

```
.\scripts\port.ps1 -Package xiom.cufft -TimeoutSec 300
```

Watchdog: 300 s (large runtime DLLs; ~5 s live on the development host).

## 5. Scope and limitations

- Windows x64 only (the loader uses `LoadLibraryExA` + `nvcuda.dll`).
- Single-threaded bridge/context use.
- Declared surface: 1D/2D plans and the six transform types above. 3D,
  `cufftPlanMany` (batched/strided), `cufftXt` callbacks, and plan
  properties are out of scope for 0.1.0 (`ROADMAP.md`).
- Work-space estimates are returned as bytes; 0 is a valid estimate for
  small transforms.
