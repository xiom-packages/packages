# xiom.torch -- Roadmap

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0

## P1 -- Landed (0.1.0, this repo state)

Pure tier:
* `types`: tensor_new/zeros/ones/shape/reshape with exact semantics;
  reshape mismatch now a typed `Result` error (was a silent empty tensor
  in the stub).
* `nn`: all four layer builders; **real `linear_forward`**
  (`y = x @ W^T + b`, 1-D and batched, exact-math tested) replacing the
  zero-output stub.

Runtime tier:
* Multi-soname loader (13 declared AOTI entry points + the CUDA anchor),
  fail-closed resolution, `TORCH_ABI_VERSION` 2.9 floor, typed SKIP.
* Tensor bridge: `torch_upload` (copy-in via borrowed blob + `copy_`),
  `torch_download` (contiguity-guarded, exact Float32), `torch_release`,
  `torch_cuda_available`; live-proven round trip on the pinned official
  build (2.9.0 CPU, 22/22 suite).

## P2 -- Forward and training surface (next)

1. `conv2d_forward` (im2col + the runtime matmul path or a pure-XIOM
   loop nest), `batchnorm2d_forward` (inference mode), `sequential_forward`
   dispatch over `LayerType`.
2. `softmax`/`relu`/activations for the pure tier (exact small-shape
   math), matching the runtime tier's dispatcher ops.
3. Autograd scaffold: a tape over the pure tensor ops (Float32, reverse
   mode) with gradient checks on the linear layers.
4. `optim` module: SGD/Adam state objects operating on the tape or on the
   runtime tier's functional step (xiom.libtorch P3 alignment).
5. Extend the runtime tier with the dtype surface (float64/int64) and a
   `Concat`-style shape op as the declared set grows.

## P3 -- Checkpoints and datasets (exploratory)

1. Checkpoint save/load: pair with `xiom.libtorch` P2's TorchScript call
   path (`.pt` artifacts) or a native XIOM tensor-serialization format as
   the primary route.
2. Dataset loaders (CSV/NPY through the existing pure-XIOM parsers).
3. GPU lane: upload/download honoring a CUDA build's device (the anchor
   is already bound; device-guard calls land with xiom.libtorch P3).

## Non-goals

* Vendoring libtorch or any PyTorch artifact.
* A full autograd parity effort at 0.1.x; the pure tier stays small and
  exact.
