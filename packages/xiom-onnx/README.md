# xiom.onnx

> **Status:** `incubating` -- 0.2.0 (published in `eco-v0.1.198`, sha256
> `4c230691...`, 2026-10-18). Full ONNX Runtime C API
> binding delivered: 98/98 declared entry points bound and live-verified,
> plus the DirectML execution-provider leg; suite x2 green (60/60) on the
> DirectML wheel, 59/59 on the CPU-only SKIP path.
> **Scope:** cross-framework model inference via the ONNX Runtime C API
> (M$/onnxruntime, MIT); system-library loader, typed SKIP when absent.
> **Deps:** stdlib only (xiom.ffi + xiom.ffi.dl). No build-time deps.

## What it is

`xiom.onnx` binds the **stable ONNX Runtime C API**: it loads
`onnxruntime.dll` / `libonnxruntime.so` / `libonnxruntime.dylib` at run
time (multi-soname loader), resolves the versioned `OrtApi`
function-pointer table through `OrtGetApiBase`, and exposes env, session +
options, tensors/values, type/shape metadata, run options, `Run`, full
`IoBinding`, model metadata and provider enumeration. The 0.2.0 DirectML leg
appends the GPU EP by adapter index and runs the fixture with CPU fallback
disabled (real DML execution). Nothing is linked or vendored -- a machine
without a runtime gets the typed **SKIP** state (`ONNX_LOAD_ABSENT`); a
CPU-only runtime gets the typed provider SKIP (`ONNX_EP_ABSENT`), never a
fake success.

## Modules

| Module | Role |
|--------|------|
| `xiom.onnx.loader` | multi-soname loader + OrtApi table + declared surface (96 slots) + version negotiation + status decode |
| `xiom.onnx.env` | OrtEnv, telemetry, available providers |
| `xiom.onnx.value` | OrtValue tensors (allocator-owned + borrowed-buffer), type/shape info, memory info, allocators |
| `xiom.onnx.session` | session options, DirectML EP append (`onnx_options_append_directml`), sessions (file path or bytes), metadata, run options, Run, IoBinding, high-level model API |
| `xiom.onnx.types` | shared types + the full ORT constant set (dtypes 0..26, error codes, levels, mem types) |
| `xiom.onnx.tensor` | pure-XIOM tensor/config tier (kept from 0.1.0) |

## Quick start

```xiom
module app

use xiom.onnx.session;
use xiom.onnx.types;
use xiom.onnx.tensor;
use xiom.io;

pub fn main() -> Int {
  let cfg = onnx_config_default();
  match onnx_load_model("model.onnx", &cfg) {
    Ok(model) => {
      var name: Vec[Int] = Vec[Int].new();
      name.push(1);
      name.push(3);
      var img = tensor.onnx_tensor_zeros("images", &name);
      img.data[0] = 0.5;
      let r = onnx_run(&model, &(vec_of(img)));   // see tests for full shapes
      onnx_close(&model);
      return 0;
    }
    Err(msg) => { io.println("SKIP: " + msg); return 0; }
  }
}
```

(Working end-to-end usage, including the [2]->[2] `Add` model and the
low-level `Run` + `IoBinding` tiers, is in `tests/test_conformance.xi`.)

## DirectML execution provider (0.2.0)

```xiom
use xiom.onnx.loader;
use xiom.onnx.session;
use xiom.onnx.types;

let lr = onnx_load();
if lr.is_ok {
  let lib = lr.value;
  let or_ = onnx_session_options_new(&lib);
  if or_.is_ok {
    // device_id = DXGI adapter index; 0 = default adapter (primary GPU)
    let ar = onnx_options_append_directml(&lib, or_.value, types.ORT_DML_DEVICE_DEFAULT);
    if ar.is_ok {
      // create a session with these options -- it runs on DirectML
    } else if ar.error.kind == types.ONNX_EP_ABSENT {
      // CPU-only runtime: typed SKIP, not an error path
    }
    onnx_session_options_free(&lib, or_.value);
  }
}
```

`device_id` follows `IDXGIFactory::EnumAdapters` order (0-based): 0 is the
default adapter (typically the primary display GPU), negative ids are
invalid, and an id past the adapter count fails with ORT's own typed error.
On the recorded host DXGI adapter 0 is the RTX 3070 Ti. The append goes
through `OrtApi.GetExecutionProviderApi("DML")` and
`OrtDmlApi.SessionOptionsAppendExecutionProvider_DML` (the deprecated
standalone export is not used). A CPU-only build returns the typed
`ONNX_EP_ABSENT` SKIP state.

## Live leg (running the conformance suite)

DirectML live leg (x2 = 60/60; the wheel is MIT, fetched from PyPI):

```powershell
$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
$env:XIOM_ONNX_RUNTIME = "E:\repos\onnxruntime-dml\onnxruntime\capi\onnxruntime.dll"
$env:PATH = "E:\repos\onnxruntime-dml\onnxruntime\capi;" + $env:PATH  # DirectML.dll
.\scripts\port.ps1 -Package xiom.onnx -TimeoutSec 300
```

CPU-only SKIP leg (59/59; the two `directml:` lines report typed SKIP):

```powershell
$env:XIOM_ONNX_RUNTIME = "E:\repos\onnxruntime-bin\onnxruntime-win-x64-1.31.0\lib\onnxruntime.dll"
.\scripts\port.ps1 -Package xiom.onnx -TimeoutSec 300
```

Without the override the loader falls back to bare sonames -- on a stock
Windows 11 box that is the inbox **ORT 1.17.1** (`C:\Windows\System32\
onnxruntime.dll`), which is DML capable and passes 60/60. Without any
runtime the suite reports `live: SKIP -- no onnxruntime candidate present`
and stays green.

## Coverage

100% of the declared C API surface (96 `OrtApi` members + 2 `OrtApiBase`),
organized as the export matrix in SPEC.md (section "Declared C API
surface"), each group with live evidence. Suite: **60 tests**, `port.ps1`
x2 = 60/60 on the DirectML wheel (1.24.4, RTX 3070 Ti), 59/59 on the
CPU-only SKIP path (1.31.0), and 60/60 on inbox ORT 1.17.1.

## Provenance

MIT upstream (microsoft/onnxruntime v1.31.0 @ `402979ac` header oracle;
`onnxruntime-directml` 1.24.4 wheel @ SHA256 `F2ECB68B...`; onnx/onnx
v1.23.2 @ `e1ac8e74` for the model schema). Loader-only -- headers are an
oracle, no upstream code is vendored. Details + hashes: PROVENANCE.md.
