# SPEC: xiom.cusparse -- NVIDIA cuSPARSE bindings (runtime loader, nothing vendored)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.cusparse` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Target | NVIDIA cuSPARSE (CUDA sparse math library), loaded from the user's own runtime |
| Upstream | NVIDIA cuSPARSE 12.5.10 (`nvidia-cusparse-cu12` 12.5.10.65 wheel; proprietary) |
| Package license | MIT OR Apache-2.0 (no NVIDIA code in this package) |
| Platform | Windows x64 |
| Compiler pin | v0.64.6 |

## 2. G2 pin: sonames + entry points + constants + header set

**Sonames (tried in order):** `cusparse64_13.dll`, `cusparse64_12.dll`,
`cusparse64_11.dll`, `cusparse64_10.dll`. The pinned wheel ships
`cusparse64_12.dll` (its import table requires the sibling
`nvJitLink_120_0.dll`). An explicit `cusparse_load_from(dir)` is strict
(no bare-name fallback); `cusparse_load()` uses `XIOM_CUSPARSE_DIR` first,
then the OS module search.

**Bound entry points (18):**

| Group | Symbols |
|-------|---------|
| Lifecycle | `cusparseCreate`, `cusparseDestroy`, `cusparseGetVersion`, `cusparseSetStream` |
| Legacy descriptor | `cusparseCreateMatDescr`, `cusparseDestroyMatDescr`, `cusparseSetMatType`, `cusparseSetMatIndexBase` |
| Generic descriptors | `cusparseCreateCsr`, `cusparseCreateDnVec`, `cusparseCreateDnMat`, `cusparseDestroySpMat`, `cusparseDestroyDnVec`, `cusparseDestroyDnMat` |
| SpMV | `cusparseSpMV_bufferSize`, `cusparseSpMV` |
| SpMM | `cusparseSpMM_bufferSize`, `cusparseSpMM` |

All 18 were verified in the pinned DLL's export table
(`llvm-objdump -p`). The bridge additionally uses `cuInit`,
`cuCtxCreate_v2`, `cuCtxDestroy_v2`, `cuMemAlloc_v2`, `cuMemFree_v2`,
`cuMemcpyHtoD_v2`, `cuMemcpyDtoH_v2` from `nvcuda.dll`.

**Constants (cusparse.h @ 12.5.10.65):** status `SUCCESS=0` ..
`INSUFFICIENT_RESOURCES=11`; `CUSPARSE_MATRIX_TYPE_GENERAL=0`;
`CUSPARSE_INDEX_BASE_ZERO=0`, `_ONE=1`; `CUSPARSE_INDEX_32I=2`,
`_64I=3`; `CUSPARSE_OPERATION_NON_TRANSPOSE=0`, `_TRANSPOSE=1`,
`_CONJUGATE_TRANSPOSE=2`; `CUSPARSE_ORDER_COL=1`, `_ROW=2`;
`CUSPARSE_SPMV_ALG_DEFAULT=0`; `CUSPARSE_SPMM_ALG_DEFAULT=0`,
`CUSPARSE_SPMM_CSR_ALG1=4`; `CUDA_R_32F=0`, `CUDA_R_64F=1`.

**Header pin (declaration oracle, read from the wheel, never committed):**

| File | Bytes | SHA256 |
|------|-------|--------|
| `cusparse.h` | 302,927 | `5A5DDA54552ABC3CED2D7DB04C65E2B31C57D363C9AB973AE433AFE02631757B` |
| `cusparse_v2.h` | 2,641 | `A7A7078E7A404315E0B68D0834EDB87094B91129EA3E683DBB8009DBFC29697F` |

**Artifact pin:** `nvidia_cusparse_cu12-12.5.10.65-py3-none-win_amd64.whl`
(362,504,719 B, SHA256
`9E487468A22A1EAF1FBD1D2035936A905FEB79C4CE5C2F67626764EE4F90227C`);
`cusparse64_12.dll` 477,564,928 B, SHA256
`311D441E26746331746D6EFED76982E542C6398C622758939FCB33916E0222FB`;
dependency `nvJitLink_120_0.dll` 87,359,488 B, SHA256
`998494A8EFF0D8382B41BA443D668E3EAEA7B67852256CA2982C841CD5BED47A`.
Full evidence in `PROVENANCE.md`.

**Runtime sample (NOT the pin; nothing committed):** RTX 3070 Ti,
driver API 13040 (13.4), cuSPARSE reports version **12510** (12.5.10).

### Re-pin procedure

1. Download the new `nvidia-cusparse-cu12` wheel (plus
   `nvidia-nvjitlink-cu12` if the import table needs it), verify SHA256,
   extract to `E:\repos\nvidia-math\extract\<wheel>`; copy the DLLs to
   `E:\repos\nvidia-math\runtime` (external scratch).
2. Confirm the bound entry points still exist in the DLL export table and
   re-hash the header set (update tables above + `PROVENANCE.md`).
3. Run the suite x2 with `XIOM_CUSPARSE_DIR` pointing at the new runtime,
   then record `STATUS.json` (`scripts/status.ps1 -Action update`).

## 3. Design and safe boundary (G5)

`cusparse.xi` is the only module with `unsafe`/`extern "C"`. It calls the
integer-only C bridge (`src/cusparse_bridge.c`), which:

- loads the module and resolves all 18 entry points (`GetProcAddress`);
  a loaded module with a missing symbol is `CUSPARSE_LOAD_ABI` (FAIL);
- loads `nvcuda.dll` and creates one CUDA context (`cuCtxCreate_v2`);
  no driver/device is `CUSPARSE_LOAD_NO_DEVICE` (SKIP);
- creates handles and descriptors, forwards the generic SpMV/SpMM calls
  with HOST scalar pointers selected by `computeType`, and returns opaque
  handles as `int64_t` (XIOM never dereferences foreign memory);
- exposes `cuMemAlloc_v2`-based helpers for Float32/Float64/Int32 spans;
- stores no descriptor state of its own: destroy order remains the
  caller's responsibility.

Bridge state is process-global and single-threaded; the CUDA context is
thread-affine. Destroy descriptors and handles before unloading; the
bridge destroys the context and unloads the module on `cusparse_unload`.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- **54 checks live**, 5 without a
runtime:

| Section | Checks | Content |
|---------|--------|---------|
| A (always) | 4 | deterministic SKIP classification, status-name map, stale-module typed error, pinned constants |
| B (live or SKIP) | 50 | load, create, version, setStream, legacy mat descriptor create/set/destroy, 7 device allocations, CSR uploads (i32/f64), CSR/DnVec descriptors, SpMV buffer query + result `[5,6,13]` (f64), f32 SpMV path, DnMat descriptors, SpMM buffer query + result `[[3,1],[0,3],[5,4]]` (f64), descriptor/buffer/handle teardown, unload |

CSR input: `A = [[2,0,1],[0,3,0],[1,0,4]]` (`row_offsets=[0,2,3,5]`,
`col_indices=[0,2,1,0,2]`, `values=[2,1,3,1,4]`), `x=[1,2,3]`;
`B = [[1,0],[0,1],[1,1]]` row-major.

Command (the runner hook adds the C source via `port.args.json`):

```
.\scripts\port.ps1 -Package xiom.cusparse -TimeoutSec 300
```

Watchdog: 300 s (large runtime DLLs; ~5 s live on the development host).

## 5. Scope and limitations

- Windows x64 only (the loader uses `LoadLibraryExA` + `nvcuda.dll`).
- Single-threaded bridge/context use; HOST scalar pointer mode only.
- Declared surface: the 18 entry points above with CSR + dense descriptors
  and SpMV/SpMM; COO/BSR/CSC formats, SpGEMM, triangular solves, and
  preprocess APIs are out of scope for 0.1.0 (`ROADMAP.md`).
- Compute/value types are limited to `CUDA_R_32F` and `CUDA_R_64F`; other
  `cudaDataType` values return `CUSPARSE_STATUS_NOT_SUPPORTED`.
- The legacy `cusparseMatDescr_t` is exposed for interoperability and is
  not consumed by the generic SpMV/SpMM path (the generic API takes the
  CSR/dense descriptors).
