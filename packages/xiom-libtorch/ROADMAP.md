# xiom.libtorch -- ROADMAP

## Phase 1: Core Foundation (CURRENT)
**Status:** SPEC implemented -- types, extern "C" block, safe wrappers with contracts, conformance tests.

| Deliverable | Status |
|---|---|
| `libtorch.xi` -- module `xiom.libtorch` with 3 opaque types, 18 extern "C" declarations, 18 safe wrappers | Done |
| `tests/test_conformance.xi` -- 16 conformance tests | Done |
| Opaque handle types: `TorchModel`, `TorchTensor`, `TorchOptimizer` | Done |
| Tensor creation: `tensor_new`, `tensor_from_data`, `tensor_free`, `tensor_to_vec` | Done |
| Tensor ops: `tensor_add`, `tensor_mul`, `tensor_matmul`, `tensor_relu`, `tensor_softmax` | Done |
| Module: `jit_load`, `module_forward`, `module_free` | Done |
| GPU: `cuda_is_available`, `tensor_to_cuda`, `tensor_to_cpu` | Done |
| Optimizer: `optimizer_sgd`, `optimizer_step`, `optimizer_zero_grad`, `optimizer_free` | Done |
| Contract enforcement: `requires:` and `ensures:` clauses on all safe wrappers | Done |

## Phase 2: JIT Model Execution & GPU (planned)
- C bridge implementation (`libtorch_bridge.cpp`) linking against LibTorch
- `jit_load` -- load `model.pt` from disk, verify `requires: io.file_exists(path)`
- `module_forward` -- run forward pass with tensor input
- `tensor_to_cuda` / `tensor_to_cpu` -- device transfer with CUDA check
- `cuda_is_available` -- real `torch::cuda::is_available()` query
- `tensor_to_vec` -- full tensor data extraction to `Vec[Float32]`
- `tests/test_integration.xi` -- integration tests requiring LibTorch DLL

## Phase 3: Autograd & Training (planned)
- Autograd support: `tensor_backward`, `tensor_grad`, `tensor_no_grad`
- Loss functions: `loss_mse`, `loss_cross_entropy`
- Additional optimizers: `optimizer_adam`, `optimizer_rmsprop`
- Training loop utilities: `module_train`, `module_eval`
- Parameter extraction: `module_parameters`, `module_named_parameters`
- `tests/test_training.xi`

## Phase 4: DataLoader & Datasets (planned)
- `DataLoader` type with batching, shuffling, multi-worker support
- `Dataset` trait for custom datasets
- Built-in transforms: `Normalize`, `ToTensor`, `Resize`, `RandomCrop`
- Integration with `xiom.numpy` for data preprocessing
- `tests/test_dataloader.xi`
