# xiom.torch

> **Status:** `incubating` -- conformance suite green (22 checks live on
> the pinned libtorch 2.9.0 CPU build, 19 checks pure/SKIP on v0.64.6);
> published in `eco-v0.1.194` (sha256 `bde0ce5c...`, 2026-10-17).
> **Scope:** Torch-style tensor types and neural-network building blocks
> with a REAL linear forward (pure XIOM, no runtime required), plus a
> libtorch runtime tier that moves tensors between XIOM and libtorch
> through the AOTInductor C ABI (typed SKIP when no build is present).
> **Deps:** stdlib only.

## What it is

```text
module xiom.torch.types    -- Tensor/DType/Device/TensorOptions + tensor_new/
                              zeros/ones/shape/reshape (pure XIOM)
module xiom.torch.nn       -- Linear/Conv2D/BatchNorm2D/Sequential builders
                              + a real linear_forward (x @ W^T + b)
module xiom.torch.runtime  -- multi-soname libtorch loader (AOTI C ABI
                              subset, 13 entry points + 1 C++ anchor) and
                              the tensor bridge: torch_upload, torch_download,
                              torch_release, torch_cuda_available
```

The pure tier is oracle-free math (hand-computed test vectors); the
runtime tier follows the same loader discipline as `xiom.libtorch` and
shares its upstream pins (PROVENANCE.md). Module-name note: the historical
`xiom.torch.ffi` name was retired at this landing -- a module whose last
segment is `ffi` cannot import the stdlib `xiom.ffi` module on the pinned
toolchain (B-07).

## Quick start

```xiom
use xiom.torch.types;
use xiom.torch.nn;
use xiom.torch.runtime;
use xiom.io;

pub fn main() -> Int {
  // Pure tier: a 2x2 linear layer with custom weights, no runtime.
  var layer = linear_new(2, 2);
  layer.weight.data[0] = 1.0; layer.weight.data[1] = 0.0;
  layer.weight.data[2] = 0.0; layer.weight.data[3] = 1.0;
  layer.bias.data[0] = 10.0; layer.bias.data[1] = 20.0;

  var opts = TensorOptions{ dtype: DType.Float32, device: Device.CPU, requires_grad: false };
  var shape: Vec[Int] = Vec[Int].new();
  shape.push(1); shape.push(2);
  var x = tensor_new(&shape, &opts);
  x.data[0] = 1.0; x.data[1] = 2.0;
  let y = linear_forward(&layer, &x);        // [11, 22]

  // Runtime tier (optional): upload to libtorch and read back.
  let orr = torch_runtime_open();
  if orr.is_ok {
    let rt = orr.value;
    let h = torch_upload(&rt, &y).value;
    let back = torch_download(&rt, h, "y").value;   // exact round trip
    io.println("downloaded: " + runtime.int_to_str(back.data.len()));
    let rel = torch_release(&rt, h);
    let cr = torch_runtime_close(&rt);
  }
  return 0;
}
```

**Live leg:** `XIOM_LIBTORCH_RUNTIME` (explicit build path) or a bare
soname from the candidate list (`torch_cpu.dll`, `libtorch_cpu.dll`,
`libtorch.dll`, `torch.dll` + `.so`/`.dylib` variants); put the build's
`lib` directory on `PATH`. Without a build every runtime call classifies
`TORCH_LOAD_ABSENT` (typed SKIP) and the suite stays green.

## Conformance

```powershell
$env:XIOM_LIBTORCH_RUNTIME = "E:\repos\libtorch-bin\libtorch\lib\torch_cpu.dll"
$env:PATH = "E:\repos\libtorch-bin\libtorch\lib;$env:PATH"
.\scripts\port.ps1 -Package xiom.torch -TimeoutSec 300   # 22/22 live
$env:XIOM_LIBTORCH_RUNTIME = ""
.\scripts\port.ps1 -Package xiom.torch -TimeoutSec 300   # 19/19 pure+SKIP
```

Upstream: pytorch/pytorch `v2.9.0` (`0fabc3ba...`), BSD-3-Clause; shared
binary/oracle pins with `xiom.libtorch` (see PROVENANCE.md). See SPEC.md
for the declared surface and coverage tables, AUDIT.md for verification
and findings.
