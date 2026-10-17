# xiom.cudnn

NVIDIA **cuDNN** bindings for XIOM (classic graph-free essentials subset).
The runtime is **user-supplied** and loaded at run time -- **nothing from
NVIDIA is vendored** (no headers, libraries, import libs or DLLs).

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.6; **60/60 x2**, live RTX 3070 Ti: cuDNN **9.27.0.42**, driver 13.4,
> cc 8.6, known conv+ReLU/pool/softmax values). **Lane:** bindings
> (`keywords: ["binding"]`). Publish is gated until the coordinator's wave.

## Quick start

```xiom
use xiom.io;
use xiom.cudnn;

fn main() {
  let p = cudnn_probe_auto();           // XIOM_CUDNN_DIR / CUDNN_DIR / PATH
  if p.is_ok {
    io.println("cuDNN " + "see probe fields"); // p.value.version etc.
  } else if p.error.kind == CUDNN_LOAD_ABSENT || p.error.kind == CUDNN_NO_DEVICE {
    io.println("SKIP: " + p.error.message);
  }
}
```

The self-contained probe runs a 1x1x4x4 input through a 1x1x3x3 all-ones
filter (valid 3x3 convolution -> `54/63/90/99`), ReLU, 2x2 max pooling
(`99`) and a 4-way channel softmax (sum `1`), and round-trips the tensor
descriptor dims/strides.

## Runtime setup (user-supplied)

```powershell
pip download nvidia-cudnn-cu12==9.27.0.42 --no-deps -d E:\repos\nvidia-cudnn
# extract the .whl, then point the loader at the bin directory:
$env:XIOM_CUDNN_DIR = 'E:\repos\nvidia-cudnn\9.27.0.42\nvidia\cudnn\bin'
# cuDNN 9 dynamically needs cublasLt64_12.dll (nvidia-cublas-cu12):
$env:PATH = 'E:\repos\nvidia-cudnn\cublas-12.9.2.10\nvidia\cublas\bin;' + $env:PATH
```

`nvcuda.dll` (NVIDIA driver) and a CUDA device are required for the live
leg. Without them the suite reports a typed SKIP and exits 0. An explicit
directory is searched as `<dir>\`, `<dir>\bin\`, `<dir>\nvidia\cudnn\bin\`;
a full `.dll` path is accepted; the loader tries `cudnn64_9.dll` then
`cudnn64_8.dll`. See `SPEC.md` for the exact search order and pin.

## API

| Area | Functions |
|------|-----------|
| Probe/load | `cudnn_probe(dir)`, `cudnn_probe_auto()`, `cudnn_load(dir)`, `cudnn_version()`, `cudnn_loaded_module()`, `cudnn_device_name()`, `cudnn_compute_capability()`, `cudnn_shutdown()` |
| Core | `cudnn_handle_create/destroy`, `cudnn_error_text(status)` |
| Tensor | `cudnn_tensor_create/destroy`, `cudnn_tensor_set_4d`, `cudnn_tensor_get_4d -> Tensor4d` |
| Filter | `cudnn_filter_create/destroy`, `cudnn_filter_set_4d` |
| Convolution | `cudnn_convolution_create/destroy`, `cudnn_convolution_set_2d`, `cudnn_convolution_workspace_size`, `cudnn_convolution_forward` |
| Activation | `cudnn_activation_create/destroy`, `cudnn_activation_set`, `cudnn_activation_forward` |
| Pooling | `cudnn_pooling_create/destroy`, `cudnn_pooling_set_2d`, `cudnn_pooling_forward` |
| Softmax | `cudnn_softmax_forward` |
| Device memory | `cudnn_device_alloc/free/upload/download/sync` |

Typed errors: `Result[T, CudnnError]` with `kind` (`CUDNN_LOAD_ABSENT`,
`CUDNN_NO_DEVICE`, `CUDNN_LOAD_ABI`, `CUDNN_API_ERROR`,
`CUDNN_RUNTIME_ERROR`), the raw `status`, and the upstream message.

## Tests

```
scripts/port.ps1 -Package xiom.cudnn -TimeoutSec 300
```

Expected live: **60 `[PASS]`, exit 0** (or one SKIP line and exit 0 when the
runtime/device is absent).

## Docs

`SPEC.md` (declared subset + G2 pin), `PROVENANCE.md` (NVIDIA EULA check,
wheel/header hashes), `AUDIT.md`, `COVERAGE.md` (25/25 cuDNN + 11 CUDA
support bindings), `ROADMAP.md`.
