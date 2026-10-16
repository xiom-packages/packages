# xiom.onnx

> **Status:** `incubating` -- 0.1.0 (published in `eco-v0.1.193`, sha256
> `1c1c599b...`, 2026-10-16). Full ONNX Runtime C API
> binding delivered: 97/97 declared entry points bound and live-verified;
> suite x2 green (56/56) on the pinned toolchain.
> **Scope:** cross-framework model inference via the ONNX Runtime C API
> (M$/onnxruntime, MIT); system-library loader, typed SKIP when absent.
> **Deps:** stdlib only (xiom.ffi + xiom.ffi.dl). No build-time deps.

## What it is

`xiom.onnx` binds the **stable ONNX Runtime C API**: it loads
`onnxruntime.dll` / `libonnxruntime.so` / `libonnxruntime.dylib` at run
time (multi-soname loader), resolves the versioned `OrtApi`
function-pointer table through `OrtGetApiBase`, and exposes env, session +
options, tensors/values, type/shape metadata, run options, `Run`, full
`IoBinding`, model metadata and provider enumeration. Nothing is linked or
vendored -- a machine without a runtime gets the typed **SKIP** state
(`ONNX_LOAD_ABSENT`), never a fake success.

## Modules

| Module | Role |
|--------|------|
| `xiom.onnx.loader` | multi-soname loader + OrtApi table + declared surface (95 slots) + version negotiation + status decode |
| `xiom.onnx.env` | OrtEnv, telemetry, available providers |
| `xiom.onnx.value` | OrtValue tensors (allocator-owned + borrowed-buffer), type/shape info, memory info, allocators |
| `xiom.onnx.session` | session options, sessions (file path or bytes), metadata, run options, Run, IoBinding, high-level model API |
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

## Live leg (running the conformance suite)

```powershell
$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
# pin the official CPU runtime (MIT, GitHub release v1.31.0) for the live leg:
$env:XIOM_ONNX_RUNTIME = "E:\repos\onnxruntime-bin\onnxruntime-win-x64-1.31.0\lib\onnxruntime.dll"
.\scripts\port.ps1 -Package xiom.onnx -TimeoutSec 300
```

Without the override the loader falls back to bare sonames -- on a stock
Windows 11 box that is the inbox **ORT 1.17.1** (`C:\Windows\System32\
onnxruntime.dll`), which the suite also passes 56/56. Without any runtime
the suite reports `live: SKIP -- no onnxruntime candidate present` and
stays green.

## Coverage

100% of the declared C API surface (95 `OrtApi` members + 2 `OrtApiBase`),
organized as the export matrix in SPEC.md (section "Declared C API
surface"), each group with live evidence. Suite: **56 tests**, `port.ps1`
x2 = 56/56 (pinned ORT 1.31.0), plus a bare-runtime run 56/56 on ORT
1.17.1.

## Provenance

MIT upstream (microsoft/onnxruntime v1.31.0 @ `402979ac`; onnx/onnx v1.23.2
@ `e1ac8e74` for the model schema). Loader-only -- headers are an oracle,
no upstream code is vendored. Details + hashes: PROVENANCE.md.
