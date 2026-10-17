# xiom.cufft

NVIDIA **cuFFT** bindings for XIOM. The user's own CUDA FFT runtime is
loaded at run time (`cufft64_12.dll` / `_11` / `_10` soname fallbacks);
**nothing from NVIDIA is vendored or linked**. When the runtime is absent
the suite reports a typed **SKIP** (green), and a loaded module with
missing entry points reports a typed **FAIL**.

> **Status:** `incubating` -- 0.1.0; conformance suite **45/45 x2** live on
> the pin (xiom v0.64.6, RTX 3070 Ti, cuFFT 11.4.1 -> version 11401) and
> **5/5** on the deterministic SKIP path. Lane: bindings
> (`keywords: ["binding"]`). Not on the publish allowlist yet.

## What you get

- **Loader**: multi-soname search, `XIOM_CUFFT_DIR` override, strict
  explicit-directory loading, typed classification
  (`CUFFT_LOAD_ABSENT` / `_NO_DEVICE` -> SKIP, `_ABI` / `_RUNTIME` ->
  FAIL).
- **Plans**: `cufft_plan1d`, `cufft_plan2d`, `cufft_destroy`,
  `cufft_set_stream`, `cufft_get_version`, `cufft_estimate1d`,
  `cufft_estimate2d`.
- **Execution**: `cufft_exec_r2c`, `cufft_exec_c2r`, `cufft_exec_z2z`,
  `cufft_exec_d2z`, `cufft_exec_z2d`.
- **Device-memory helpers** (`cufft_buffer_*`) over the CUDA driver API so
  plans are usable without a separate memory package.
- **Typed errors** everywhere: `CufftError{kind, code, message}` with the
  pinned cuFFT result names (`cufft_status_name`).

Transforms are **unnormalized** (scale by 1/N after an inverse pass).
Complex data is interleaved (`re, im`); the helpers move raw Float32/
Float64 spans, so a complex buffer is a `2*N`-element span.

## Quick start

```xiom
use xiom.io;
use xiom.cufft;

fn main() {
  let lr = cufft_load();                     // XIOM_CUFFT_DIR or OS search
  if lr.is_err {
    if lr.error.kind == CUFFT_LOAD_ABSENT || lr.error.kind == CUFFT_LOAD_NO_DEVICE {
      io.println("SKIP: " + lr.error.message);
      return;
    }
    io.println("FAIL: " + lr.error.message);
    return;
  }
  let lib = lr.value;
  let pr = cufft_plan1d(&lib, 8, CUFFT_R2C, 1);
  if pr.is_err { io.println(pr.error.message); return; }
  let plan = pr.value;
  // alloc real (8 f32) + complex (2*5 f32) device buffers, upload, then:
  //   cufft_exec_r2c(&plan, &dreal, &dcplx)
  let _ = cufft_destroy(&plan);
  let _ = cufft_unload(&lib);
}
```

## Verify

```
.\scripts\port.ps1 -Package xiom.cufft -TimeoutSec 300
```

Live leg on this host (runtime fetched outside the repo):

```
$env:XIOM_CUFFT_DIR = "E:\repos\nvidia-math\runtime"
.\scripts\port.ps1 -Package xiom.cufft -TimeoutSec 300   # 45/45, x2
Remove-Item Env:\XIOM_CUFFT_DIR
.\scripts\port.ps1 -Package xiom.cufft -TimeoutSec 300   # 5/5 SKIP
```

See `SPEC.md` (ABI pin, entry points, test contract), `PROVENANCE.md`
(wheel/header pins + NVIDIA license record) and `AUDIT.md` (run evidence).
