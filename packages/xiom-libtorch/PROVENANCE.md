# xiom.libtorch -- Provenance

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0

## 1. Upstream

| Field | Value |
|---|---|
| Project | pytorch/pytorch (PyTorch, including its C++ distribution "libtorch") |
| License | **BSD-3-Clause** (verified in-tree before any code: `LICENSE`, "Redistribution and use in source and binary forms, with or without modification...", 3 clauses; PyTorch additionally carries per-file notices -- none of those files are vendored here) |
| Pin | tag `v2.9.0` = commit **`0fabc3ba44823f257e70ce397d989c8de5e362c1`** |
| Local copy | `E:\repos\pytorch` -- light clone (`--depth 1 --filter=blob:none --sparse`), sparse surface below; checked out at the pinned tag |
| Conversion basis | header oracle (declarations) + binary oracle (exports), no source code copied into this package |

### Sparse header surface (the oracle)

```text
c10/                              Device, ScalarType, macros
ATen/                             Tensor + op declarations
torch/csrc/api/                   torch::cuda, torch::optim, torch::serialize
torch/csrc/inductor/aoti_torch/   c/shim.h, c/macros.h, generated/c_shim_*.h,
                                  shim_common.cpp (semantics)
torch/csrc/inductor/aoti_runtime/ interface.h (AOTI model runtime side)
torch/csrc/jit/                   jit load declarations
torch/csrc/stable/                stableivalue_conversions.h (StableIValue encoding)
LICENSE, version.txt
```

## 2. Runtime binary (live-leg oracle)

| Field | Value |
|---|---|
| Artifact | `libtorch-win-shared-with-deps-2.9.0+cpu.zip` (official PyTorch release download) |
| URL | `https://download.pytorch.org/libtorch/cpu/libtorch-win-shared-with-deps-2.9.0%2Bcpu.zip` |
| SHA-256 | `C826069DA829550BD3F1205159F8A95EE906A447DD141D08F42C568D4EE9E05E` |
| Size | 195,825,313 bytes |
| Extracted | `E:\repos\libtorch-bin\libtorch` (documented artifact area, registered in `E:\repos\CLEANUP.md`); suites reach it via `XIOM_LIBTORCH_RUNTIME` + `PATH` |
| License | BSD-3-Clause (same release license; redistribution of this binary is the runtime user's concern -- it is NOT vendored into the package) |
| Export dumps | `E:\repos\libtorch-bin\torch_cpu_exports.txt` (60,248), `torch_exports.txt`, `c10_exports.txt`, `torch_cpu_c_exports.txt` (317 plain-C) via `llvm-readobj --coff-exports` |

Key binary facts used by the landing:

* `torch_cpu.dll` exports the AOTI shim: **317 plain-C symbols** (315
  `aoti_torch_*`/`aoti_torch_cpu_*` + 2 ancillary); the 38 declared entry
  points were each verified present by exact name in the dump.
* C++ anchors (byte-exact in the dump):
  * `?is_available@cuda@torch@@YA_NXZ`
  * `?device_count@cuda@torch@@YACXZ`
  * `?load@jit@torch@@YA?AUModule@12@AEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@V?$optional@UDevice@c10@@@5@_N@Z`
* `aoti_torch_abi_version()` live value: `0x0209000000000000`
  (MAJOR 2, MINOR 9, PATCH 0; `TORCH_ABI_VERSION` layout from
  `torch/version.h.in` = `MAJOR<<56 | MINOR<<48 | PATCH<<40 | ABI_TAG`).

## 3. Semantics oracle (pinned source reads)

Read (not copied) from the pinned sparse checkout to fix behavior:

* `aoti_torch/tensor_converter.h` + `shim_common.cpp` -- `to_ivalue`
  tensor case wraps inputs in `RAIIAtenTensorHandle` (dispatcher consumes
  input handles); `from_ivalue` TensorType allocates a fresh handle;
  `aoti_torch_tensor_copy_(src, dst)` == `dst.copy_(src)`;
  `aoti_torch_copy_(self, src, non_blocking)`.
* `torch/csrc/stable/stableivalue_conversions.h` -- `from(std::nullopt)`
  == `from(nullptr)` == 0 (the None sentinel used for the softmax dtype
  argument).
* `generated/c_shim_cpu.h` -- generated wrappers flatten `at::Scalar`
  arguments to `double` (e.g. `aoti_torch_cpu_add_Tensor(self, other,
  double alpha, ret)`), which is what makes the C ABI callable without
  C++ struct ABIs.

## 4. Attribution and packaging

* This package contains NO PyTorch code or binaries: it resolves symbols
  from a user-installed/official build at runtime and reconstructs Float32
  values with pure arithmetic (no copied tables beyond symbol NAME
  strings).
* Symbol names (mangled anchors + `aoti_torch_*` names) are factual
  identifiers required for interoperability.
* The XIOM-side implementation is original (MIT OR Apache-2.0, per
  package manifest).

## 5. Reproduce the oracle check

```powershell
git clone --depth 1 --filter=blob:none --sparse https://github.com/pytorch/pytorch E:\repos\pytorch
cd E:\repos\pytorch
git fetch --depth 1 origin tag v2.9.0
git sparse-checkout set --no-cone "ATen/" "c10/" "torch/csrc/api/" "torch/csrc/inductor/" "torch/csrc/jit/" "torch/csrc/stable/" "/LICENSE" "/version.txt"
git checkout v2.9.0   # 0fabc3ba44823f257e70ce397d989c8de5e362c1

curl.exe -L -o "E:\repos\libtorch-bin\libtorch-win-shared-with-deps-2.9.0+cpu.zip" `
  "https://download.pytorch.org/libtorch/cpu/libtorch-win-shared-with-deps-2.9.0%2Bcpu.zip"
# SHA-256 must equal C826069DA829550BD3F1205159F8A95EE906A447DD141D08F42C568D4EE9E05E
tar -xf "E:\repos\libtorch-bin\libtorch-win-shared-with-deps-2.9.0+cpu.zip" -C E:\repos\libtorch-bin
llvm-readobj --coff-exports E:\repos\libtorch-bin\libtorch\lib\torch_cpu.dll |
  Select-String "Name: aoti_torch_abi_version|Name: \?is_available@cuda"
```
