# xiom.cublas

NVIDIA **cuBLAS** bindings for XIOM. The user's own CUDA math runtime is
loaded at run time (`cublas64_13.dll` / `_12` / `_11` / `_10` soname
fallbacks); **nothing from NVIDIA is vendored or linked**. When the
runtime is absent the suite reports a typed **SKIP** (green), and when a
module loads with missing entry points it reports a typed **FAIL**.

> **Status:** `incubating` -- 0.1.0; conformance suite **62/62 x2** live on
> the pin (xiom v0.64.6, RTX 3070 Ti, cuBLAS 12.9.2 -> version 120902) and
> **5/5** on the deterministic SKIP path. Lane: bindings
> (`keywords: ["binding"]`). Not on the publish allowlist yet.

## What you get

- **Loader**: multi-soname search, `XIOM_CUBLAS_DIR` override, strict
  explicit-directory loading, typed classification
  (`CUBLAS_LOAD_ABSENT` / `_NO_DEVICE` -> SKIP, `_ABI` / `_RUNTIME` ->
  FAIL).
- **Handle lifecycle**: `cublas_create` / `cublas_destroy`,
  `cublas_get_version`, `cublas_set_stream`.
- **BLAS level 1**: `s/daxpy`, `s/ddot`, `s/dscal`, `s/dnrm2`.
- **BLAS level 2**: `s/dgemv`.
- **BLAS level 3**: `s/dgemm`.
- **Device-memory helpers** (`cublas_buffer_*`) over the CUDA driver API
  (`cuMemAlloc_v2` / `cuMemcpyHtoD_v2` / `cuMemcpyDtoH_v2` /
  `cuMemFree_v2`) so the cuBLAS surface is usable without a separate
  memory package. These are scaffolding, not cuBLAS.
- **Typed errors** everywhere: `CublasError{kind, code, message}` with the
  pinned cuBLAS status names (`cublas_status_name`).

cuBLAS is **column-major**: the wrappers pass `CUBLAS_OP_N/T/C` and
`lda`/`ldb`/`ldc` through unchanged. For row-major data use the usual
transpose identity (`C^T = B^T A^T`); the suite demonstrates it.

## Quick start

```xiom
use xiom.io;
use xiom.cublas;

fn main() {
  let lr = cublas_load();                    // XIOM_CUBLAS_DIR or OS search
  if lr.is_err {
    if lr.error.kind == CUBLAS_LOAD_ABSENT || lr.error.kind == CUBLAS_LOAD_NO_DEVICE {
      io.println("SKIP: " + lr.error.message);   // no NVIDIA runtime on this host
      return;
    }
    io.println("FAIL: " + lr.error.message);
    return;
  }
  let lib = lr.value;
  let hr = cublas_create(&lib);
  if hr.is_err { io.println(hr.error.message); return; }
  let h = hr.value;
  // allocate + upload device buffers, then e.g.
  //   cublas_dgemm(&h, CUBLAS_OP_N, CUBLAS_OP_N, m, n, k, alpha, &a, lda,
  //                &b, ldb, beta, &c, ldc)
  let _ = cublas_destroy(&h);
  let _ = cublas_unload(&lib);
}
```

## Verify

```
.\scripts\port.ps1 -Package xiom.cublas -TimeoutSec 300
```

Live leg on this host (runtime fetched outside the repo):

```
$env:XIOM_CUBLAS_DIR = "E:\repos\nvidia-math\runtime"
.\scripts\port.ps1 -Package xiom.cublas -TimeoutSec 300   # 62/62, x2
Remove-Item Env:\XIOM_CUBLAS_DIR
.\scripts\port.ps1 -Package xiom.cublas -TimeoutSec 300   # 5/5 SKIP
```

See `SPEC.md` (ABI pin, entry points, test contract), `PROVENANCE.md`
(wheel/header pins + NVIDIA license record) and `AUDIT.md` (run evidence).
