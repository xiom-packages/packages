# xiom.torch -- Provenance

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0

## 1. Upstream (shared with xiom.libtorch)

| Field | Value |
|---|---|
| Project | pytorch/pytorch (PyTorch / libtorch) |
| License | **BSD-3-Clause** (verified in-tree before any code; see `xiom.libtorch/PROVENANCE.md` for the full check) |
| Pin | tag `v2.9.0` = commit **`0fabc3ba44823f257e70ce397d989c8de5e362c1`** |
| Local copy | `E:\repos\pytorch` (light sparse clone; surface list in the libtorch PROVENANCE) |
| Runtime binary | official CPU build `libtorch-win-shared-with-deps-2.9.0+cpu.zip`, SHA-256 `C826069DA829550BD3F1205159F8A95EE906A447DD141D08F42C568D4EE9E05E`, extracted to `E:\repos\libtorch-bin\libtorch` (registered in `E:\repos\CLEANUP.md`) |

## 2. What this package borrows from upstream

* **Symbol names only**: 13 `aoti_torch_*` C entry point names and one
  mangled anchor (`?is_available@cuda@torch@@YA_NXZ`), verified by exact
  name against the pinned binary's export table before transcription.
* **Behavioral semantics** read from the pinned sources (no code copied):
  `aoti_torch_tensor_copy_(src, dst)` == `dst.copy_(src)`;
  borrowed-blob tensors use a no-op deleter; the AOTI protocol is
  `AOTITorchError` 0 == success; `TORCH_ABI_VERSION` layout
  (`torch/version.h.in`) decoded for the version probe.
* **Float32 reconstruction** is pure XIOM arithmetic (the
  `xxx_f32_from_bits` lane pattern), no copied tables.

The package contains no PyTorch code or binaries; the runtime is the
user's installed/official build, located at load time.

## 3. Verification commands

The reproduce block in `xiom.libtorch/PROVENANCE.md` covers the shared
oracle (clone + tag + sparse surface + binary download + export dump).
Package-specific checks:

```powershell
# runtime tier symbols present in the pinned build:
Select-String -Path E:\repos\libtorch-bin\torch_cpu_exports.txt `
  -Pattern "aoti_torch_abi_version","aoti_torch_empty_strided","\?is_available@cuda@torch"

# conformance:
$env:XIOM_LIBTORCH_RUNTIME = "E:\repos\libtorch-bin\libtorch\lib\torch_cpu.dll"
$env:PATH = "E:\repos\libtorch-bin\libtorch\lib;$env:PATH"
.\scripts\port.ps1 -Package xiom.torch -TimeoutSec 300
```
