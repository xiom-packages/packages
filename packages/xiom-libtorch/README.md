# xiom.libtorch

> **Status:** `incubating` -- conformance suite green (33 checks live on the
> pinned libtorch 2.9.0 CPU build, 8 checks with the deterministic SKIP
> path); not yet published to the XIOM registry.
> **Scope:** LibTorch (the PyTorch C++ distribution) loader surface --
> tensor creation/metadata/ops, training primitives, and the CUDA/JIT
> anchor probes -- bound through the **AOTInductor C ABI** plus three
> pinned C++ mangled anchors.
> **Deps:** stdlib only. No link-time dependency on libtorch: the runtime
> is found at load time through multi-soname candidates and the package
> compiles and runs green on hosts without it (typed SKIP).

## What it is

libtorch's C++ API has no stable ABI, but PyTorch ships one stable C
surface for it: the **AOTInductor runtime shim** (`aoti_torch_*`, declared
in `torch/csrc/inductor/aoti_torch/c/shim.h`, "This header defines a
stable C API ... MUST MAINTAIN ABI compatibility"). Every export takes
ints/floats/pointers only, returns an error code, and evolves append-only
(`_v2` variants). That surface -- 38 declared entry points -- plus three
C++ mangled anchors (`torch::cuda::is_available`,
`torch::cuda::device_count`, `torch::jit::load`) is what this package
binds, resolved at runtime through `xiom.ffi.dl`.

```text
module xiom.libtorch          -- the declared tensor-level surface (40 fns)
        -> src/loader.xi      -- xiom.libtorch.loader: multi-soname loader,
                               ABI probe, surface resolution (38 + 3)
```

## Quick start

```xiom
use xiom.libtorch;
use xiom.libtorch.loader;
use xiom.io;

pub fn main() -> Int {
  let lr = torch_load();                       // candidates, typed SKIP
  if !lr.is_ok {
    io.println("libtorch absent: " + lr.error.message);
    return 0;                                  // LT_LOAD_ABSENT == SKIP
  }
  let lib = lr.value;

  var shape: Vec[Int] = Vec[Int].new();
  shape.push(2);
  shape.push(3);
  let t = torch_tensor_ones(&lib, &shape).value;       // [2,3] of 1.0
  let tv = torch_tensor_to_vec(&lib, t).value;         // 6 floats
  io.println("numel: " + loader.int_to_str(tv.len()));
  let ig = torch_tensor_free(&lib, t);
  let cr = torch_close(&lib);
  return 0;
}
```

Candidates, in order: `XIOM_LIBTORCH_RUNTIME` (explicit build path, used
by the live leg), `torch_cpu.dll`, `libtorch_cpu.dll`, `libtorch.dll`,
`torch.dll`, `libtorch_cpu.so`, `libtorch.so`, `libtorch_cpu.so.2`,
`libtorch.so.2`, `libtorch_cpu.dylib`, `libtorch.dylib`.

**Live leg:** put the build's `lib` directory on `PATH` (libtorch's own
dependencies -- `c10.dll`, `uv.dll`, `libiomp5md.dll` -- are resolved
through the standard loader search at `LoadLibraryA` time), then run the
suite. Without a build the suite reports SKIP and stays green.

## Surface at a glance

| Area | Functions |
|---|---|
| Loader | `torch_load`, `torch_load_named`, `torch_load_candidates`, `torch_probe`, `torch_close`, `torch_abi_version` |
| Creation/lifecycle | `torch_tensor_new/zeros/ones/from_data`, `torch_tensor_free`, `torch_tensor_to_vec`, `torch_tensor_data_ptr` |
| Metadata | `numel`, `dim`, `size`, `stride`, `shape`, `strides`, `is_contiguous`, `is_defined`, `dtype`, `device_type`, `device_index`, `storage_offset` |
| Scalars | `torch_tensor_item_float32`, `torch_tensor_scalar`, `torch_dtype_size`, `torch_dtype_float32`, `torch_device_type_cpu`, `torch_device_type_cuda` |
| Derived | `clone`, `copy_into`, `reshape`, `narrow` |
| Ops | `add`, `mul`, `scale`, `matmul` (2-D), `relu`, `softmax` (dispatcher), `fill`, `zero` |
| Training | `torch_sgd_step` (functional `p - lr*g`), `torch_grad_mode_enabled`, `torch_set_grad_mode` |
| Anchors | `torch_cuda_is_available`, `torch_cuda_device_count`, `torch_jit_anchor_present` |

Error taxonomy: `LT_LOAD_ABSENT` (no candidate -> SKIP),
`LT_LOAD_ABI` (candidate loaded, declared surface/version failed -> FAIL),
`LT_CALL_FAILED` (aoti call returned nonzero), `LT_UNAVAILABLE` (declared
capability not present on this build/host). See SPEC.md for contracts and
the full coverage table, AUDIT.md for the verification chain.

## Conformance

```powershell
$env:XIOM_LIBTORCH_RUNTIME = "E:\repos\libtorch-bin\libtorch\lib\torch_cpu.dll"
$env:PATH = "E:\repos\libtorch-bin\libtorch\lib;$env:PATH"
.\scripts\port.ps1 -Package xiom.libtorch -TimeoutSec 300   # 33/33 live
$env:XIOM_LIBTORCH_RUNTIME = ""
.\scripts\port.ps1 -Package xiom.libtorch -TimeoutSec 300   # 8/8 SKIP
```

Upstream: pytorch/pytorch `v2.9.0` (commit `0fabc3ba...`), BSD-3-Clause;
official CPU build `libtorch-win-shared-with-deps-2.9.0+cpu.zip` (SHA-256
`C826069D...`). See PROVENANCE.md.
