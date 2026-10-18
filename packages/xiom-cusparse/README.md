# xiom.cusparse

NVIDIA **cuSPARSE** bindings for XIOM. The user's own CUDA sparse runtime
is loaded at run time (`cusparse64_13.dll` / `_12` / `_11` / `_10` soname
fallbacks); **nothing from NVIDIA is vendored or linked**. When the runtime
is absent the suite reports a typed **SKIP** (green), and a loaded module
with missing entry points reports a typed **FAIL**.

> **Status:** `incubating` -- 0.1.0; conformance suite **56/56 x2** live on
> the pin (xiom v0.64.6, RTX 3070 Ti, cuSPARSE 12.5.10 -> version 12510)
> and **5/5** on the deterministic SKIP path. Lane: bindings
> (`keywords: ["binding"]`). Not on the publish allowlist yet.

## What you get

- **Loader**: multi-soname search, `XIOM_CUSPARSE_DIR` override, strict
  explicit-directory loading, typed classification
  (`CUSPARSE_LOAD_ABSENT` / `_NO_DEVICE` -> SKIP, `_ABI` / `_RUNTIME` ->
  FAIL).
- **Handle lifecycle**: `cusparse_create` / `cusparse_destroy`,
  `cusparse_get_version`, `cusparse_set_stream`.
- **Legacy matrix descriptor**: `cusparse_create_mat_descr` /
  `_destroy_mat_descr`, `_set_mat_type`, `_set_mat_index_base`.
- **Generic descriptors**: CSR (`cusparse_create_csr`), dense vector
  (`cusparse_create_dnvec`), dense matrix (`cusparse_create_dnmat`) and
  their destroy functions.
- **SpMV**: `cusparse_spmv_buffer_size` + `cusparse_spmv` with the
  external-buffer form (f32 and f64 compute types).
- **SpMM**: `cusparse_spmm_buffer_size` + `cusparse_spmm` with dense
  row-major B/C (f64 compute type).
- **Device-memory helpers** (`cusparse_buffer_*`) over the CUDA driver API
  for Float32/Float64/Int32 spans (CSR index arrays included).
- **Typed errors** everywhere: `CusparseError{kind, code, message}` with
  the pinned cuSPARSE status names (`cusparse_status_name`).

The generic API's default pointer mode is HOST, so the typed wrappers take
`alpha`/`beta` by value and marshal them to the compute type
(`CUDA_R_32F` or `CUDA_R_64F`; other types return
`CUSPARSE_STATUS_NOT_SUPPORTED`).

## Quick start

```xiom
use xiom.io;
use xiom.cusparse;

fn main() {
  let lr = cusparse_load();                  // XIOM_CUSPARSE_DIR or OS search
  if lr.is_err {
    if lr.error.kind == CUSPARSE_LOAD_ABSENT || lr.error.kind == CUSPARSE_LOAD_NO_DEVICE {
      io.println("SKIP: " + lr.error.message);
      return;
    }
    io.println("FAIL: " + lr.error.message);
    return;
  }
  let lib = lr.value;
  let hr = cusparse_create(&lib);
  if hr.is_err { io.println(hr.error.message); return; }
  let h = hr.value;
  // build CSR device arrays (row offsets / col indices int32, values f64),
  // create the CSR + DnVec descriptors, query the buffer size, then:
  //   cusparse_spmv(&h, CUSPARSE_OPERATION_NON_TRANSPOSE, 1.0, &sp, &x,
  //                 0.0, &y, CUDA_R_64F, CUSPARSE_SPMV_ALG_DEFAULT, &buf)
  let _ = cusparse_destroy(&h);
  let _ = cusparse_unload(&lib);
}
```

## Verify

```
.\scripts\port.ps1 -Package xiom.cusparse -TimeoutSec 300
```

Live leg on this host (runtime fetched outside the repo):

```
$env:XIOM_CUSPARSE_DIR = "E:\repos\nvidia-math\runtime"
.\scripts\port.ps1 -Package xiom.cusparse -TimeoutSec 300   # 56/56, x2
Remove-Item Env:\XIOM_CUSPARSE_DIR
.\scripts\port.ps1 -Package xiom.cusparse -TimeoutSec 300   # 5/5 SKIP
```

See `SPEC.md` (ABI pin, entry points, test contract), `PROVENANCE.md`
(wheel/header pins + NVIDIA license record) and `AUDIT.md` (run evidence).

**Published:** `0.1.0` in `eco-v0.1.199` (sha256 `c1dc295f...`, 2026-10-18; registry live-verified).
