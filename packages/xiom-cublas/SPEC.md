# SPEC: xiom.cublas -- NVIDIA cuBLAS bindings (runtime loader, nothing vendored)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.cublas` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Target | NVIDIA cuBLAS (CUDA math library), loaded from the user's own runtime |
| Upstream | NVIDIA cuBLAS 12.9.2 (`nvidia-cublas-cu12` 12.9.2.10 wheel; proprietary) |
| Package license | MIT OR Apache-2.0 (no NVIDIA code in this package) |
| Platform | Windows x64 |
| Compiler pin | v0.64.6 |

## 2. G2 pin: sonames + entry points + constants + header set

**Sonames (tried in order):** `cublas64_13.dll`, `cublas64_12.dll`,
`cublas64_11.dll`, `cublas64_10.dll`. The pinned wheel ships
`cublas64_12.dll` (with its sibling dependency `cublasLt64_12.dll`). An
explicit `cublas_load_from(dir)` is strict (no bare-name fallback);
`cublas_load()` uses `XIOM_CUBLAS_DIR` first, then the OS module search.

**Bound entry points (16, all stable `_v2` ABI):**

| Group | Symbols |
|-------|---------|
| Lifecycle | `cublasCreate_v2`, `cublasDestroy_v2`, `cublasGetVersion_v2`, `cublasSetStream_v2` |
| Level 1 | `cublasSaxpy_v2`, `cublasDaxpy_v2`, `cublasSdot_v2`, `cublasDdot_v2`, `cublasSscal_v2`, `cublasDscal_v2`, `cublasSnrm2_v2`, `cublasDnrm2_v2` |
| Level 2 | `cublasSgemv_v2`, `cublasDgemv_v2` |
| Level 3 | `cublasSgemm_v2`, `cublasDgemm_v2` |

All 16 were verified in the pinned DLL's export table
(`llvm-objdump -p`). The bridge additionally uses the driver API
`cuInit`, `cuCtxCreate_v2`, `cuCtxDestroy_v2`, `cuMemAlloc_v2`,
`cuMemFree_v2`, `cuMemcpyHtoD_v2`, `cuMemcpyDtoH_v2` from `nvcuda.dll`
for the context and device-memory helpers.

**Constants (cublas_api.h @ 12.9.2.10):** `CUBLAS_OP_N=0`, `_T=1`, `_C=2`;
status `SUCCESS=0`, `NOT_INITIALIZED=1`, `ALLOC_FAILED=3`,
`INVALID_VALUE=7`, `ARCH_MISMATCH=8`, `MAPPING_ERROR=11`,
`EXECUTION_FAILED=13`, `INTERNAL_ERROR=14`, `NOT_SUPPORTED=15`,
`LICENSE_ERROR=16`.

**Header pin (declaration oracle, read from the wheel, never committed):**

| File | Bytes | SHA256 |
|------|-------|--------|
| `cublas_api.h` | 381,551 | `B64E0CE339DB7EA9E7A4D79C57CB05CF258694E2929ADBB831F63E406E43DBEA` |
| `cublas_v2.h` | 15,938 | `C00D426FBC7AA24C10702492C0DF2530FCF45786FC3E78832A1DCCB3FBA2C4EE` |
| `cublas.h` | 42,137 | `917979843ED4B042674A0DF27B86C06FE1E28B2643C8E24E6709C1E0D85C8B41` |
| `cublasLt.h` | 106,822 | `02BDF192D7E2209E6340B2F4D473299D7DC709D73A00CC5B24B91F7D1C5A597A` |
| `cublasXt.h` | 38,073 | `A51299616004AFCC0ED44D3394508D4878C66D6E5FD241BA027BC17E4DCC4FB5` |
| `nvblas.h` | 24,165 | `0BEBAE64184148E78C709FD283616EC831F0802CA915F1951412A9185A627A0C` |

**Artifact pin:** `nvidia_cublas_cu12-12.9.2.10-py3-none-win_amd64.whl`
(553,162,896 B, SHA256
`623F43027D40D44CEADF0043F002BD25CF353E8F13CE90B9A87057019F560661`);
`cublas64_12.dll` 102,518,272 B, SHA256
`52CE5BA0EC5327D39BE6021F0F9362D2ED4D64D7206F9B5AFC06398D827B8E82`.
Full evidence in `PROVENANCE.md`.

**Runtime sample (NOT the pin; nothing committed):** RTX 3070 Ti,
driver API 13040 (13.4), cuBLAS reports version **120902** (12.9.2).

### Re-pin procedure

1. Download the new `nvidia-cublas-cu12` wheel, verify its SHA256, extract
   to `E:\repos\nvidia-math\extract\<wheel>`; copy the DLLs to
   `E:\repos\nvidia-math\runtime` (external scratch).
2. Confirm the bound entry points still exist in the DLL export table and
   re-hash the header set (update tables above + `PROVENANCE.md`).
3. Run the suite x2 with `XIOM_CUBLAS_DIR` pointing at the new runtime,
   then record `STATUS.json` (`scripts/status.ps1 -Action update`).

## 3. Design and safe boundary (G5)

`cublas.xi` is the only module with `unsafe`/`extern "C"`. It calls the
integer-only C bridge (`src/cublas_bridge.c`), which:

- loads the module and resolves all 16 entry points (`GetProcAddress`);
  a loaded module with a missing symbol is `CUBLAS_LOAD_ABI` (FAIL);
- loads `nvcuda.dll` and creates one CUDA context (`cuCtxCreate_v2`);
  no driver/device is `CUBLAS_LOAD_NO_DEVICE` (SKIP);
- creates the cuBLAS handle on that context and forwards every call
  verbatim (column-major semantics);
- returns opaque handles/device addresses as `int64_t`; XIOM treats them
  as `Int` and never dereferences foreign memory;
- caches the scalar result of `sdot`/`ddot`/`snrm2` for a follow-up
  accessor (no out-param slots cross the ABI -- the B-11 discipline);
- provides `cuMemAlloc_v2`-based buffer helpers (alloc/free/upload/
  download for Float32/Float64 spans).

Bridge state is process-global and single-threaded; the CUDA context is
thread-affine. Destroy handles before unloading; the bridge destroys the
context and unloads the module on `cublas_unload`.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- **62 checks live**, 5 without a
runtime:

| Section | Checks | Content |
|---------|--------|---------|
| A (always) | 4 | deterministic SKIP classification, status-name map, stale-module typed error, pinned constants |
| B (live or SKIP) | 58 | load, create, version, setStream, 7 device allocations, sgemm + dgemm `[19,22,43,50]`, saxpy `[12,24,36]`, sdot/ddot 168, sscal `[3,6,9]`, snrm2 5, sgemv/dgemv `[6,15]`, buffer frees, destroy, unload |

Command (the runner hook adds the C source via `port.args.json`):

```
.\scripts\port.ps1 -Package xiom.cublas -TimeoutSec 300
```

Watchdog: 300 s (large runtime DLLs; ~5 s live on the development host).

## 5. Scope and limitations

- Windows x64 only (the loader uses `LoadLibraryExA` + `nvcuda.dll`).
- Single-threaded bridge/context use.
- Declared surface is the 16 entry points above; batched/strided,
  `gemmEx`, `gemmBatched`, `trsm`, `syrk`, and `cublasLt` are out of
  scope for 0.1.0 (`ROADMAP.md`).
- Device buffers are raw device addresses; the packaged helpers cover
  contiguous Float32/Float64 spans only.
