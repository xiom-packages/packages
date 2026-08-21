# xiom-torch ROADMAP

> LibTorch bindings for XIOM -- PyTorch C++ inference with compile-time safety.

## Current Status: v0.1.0 (Alpha)

### Completed

- [x] **Core tensor types** -- `Tensor`, `DType`, `Device`, `TensorOptions`, `ModuleDef` in `xiom.torch.types`
- [x] **Tensor constructors** -- `tensor_new`, `tensor_zeros`, `tensor_ones`, `tensor_shape`, `tensor_reshape` with requires/ensures contracts
- [x] **Row-major stride computation** -- automatic C-contiguous stride layout
- [x] **NN layer types** -- `Linear`, `Conv2d`, `BatchNorm2d`, `ReLU`, `Sigmoid`, `Tanh`, `Softmax` with fields
- [x] **Sequential container** -- `Sequential` with `LayerType` enum union of all layer types
- [x] **Layer constructors** -- `linear_new`, `conv2d_new`, `batchnorm2d_new` with requires contracts
- [x] **FFI stubs** -- `extern "C"` declarations for `torch_c_load_model`, `torch_c_forward`, `torch_c_save_model`, `torch_c_is_cuda_available`, `torch_c_free`
- [x] **FFI public API** -- `torch_load_model`, `torch_forward`, `torch_save_model`, `torch_is_cuda_available` with stub implementations
- [x] **Conformance test suite** -- 46 tests covering all public API (types/ffi/nn), contracts, and integration
- [x] **Package manifest** -- `package.xi` with module declarations

---

## Short-Term (v0.2.0) -- Tensor Math Primitives

**Goal**: Enable actual tensor computation without LibTorch.

| # | Task | Module | Priority |
|---|------|--------|----------|
| 1 | Element-wise add/subtract/multiply/divide | `xiom.torch.ops` | High |
| 2 | Matrix multiplication (matmul) | `xiom.torch.ops` | High |
| 3 | Convolution 2D (im2col + matmul) | `xiom.torch.ops` | High |
| 4 | Reduce ops (sum, mean, max) along axes | `xiom.torch.ops` | Medium |
| 5 | Activation functions (relu, sigmoid, tanh, softmax) | `xiom.torch.ops` | High |
| 6 | Replace stub forward passes with real computation | `xiom.torch.nn` | High |
| 7 | Broadcast semantics for binary ops | `xiom.torch.ops` | Medium |
| 8 | GPU tensor allocation via CUDA kernel | `xiom.torch.ops` | Low |

---

## Medium-Term (v0.3.0) -- LibTorch FFI Bridge

**Goal**: Link against native LibTorch for real model inference.

| # | Task | Module | Priority |
|---|------|--------|----------|
| 1 | Implement `xiom_torch_bridge.c` FFI bridge | `src/bridge/` | High |
| 2 | Wire `torch_c_load_model` to `torch::jit::load` | `src/bridge/` | High |
| 3 | Wire `torch_c_forward` to model `forward()` | `src/bridge/` | High |
| 4 | Wire `torch_c_save_model` to `torch::save` | `src/bridge/` | High |
| 5 | Wire `torch_c_is_cuda_available` to `torch::cuda::is_available()` | `src/bridge/` | High |
| 6 | Tensor conversion: XIOM Tensor <-> `torch::Tensor` | `src/bridge/` | High |
| 7 | Error propagation from C++ exceptions to XIOM `Result` | `src/bridge/` | Medium |
| 8 | CMakeLists.txt for bridge compilation | `src/bridge/` | High |
| 9 | XIOM memory management for FFI buffers | `src/bridge/` | Medium |

---

## Long-Term (v1.0.0) -- Production Readiness

**Goal**: Full PyTorch model lifecycle in XIOM.

| # | Task | Module | Priority |
|---|------|--------|----------|
| 1 | Model serialization -- load/save `.pt` and `.pth` files | `xiom.torch.ffi` | High |
| 2 | CUDA tensor allocation and device transfer | `xiom.torch.types` | High |
| 3 | Multi-GPU support (DataParallel) | `xiom.torch.nn` | Medium |
| 4 | Automatic differentiation (autograd engine) | `xiom.torch.autograd` | Low |
| 5 | Optimizers (SGD, Adam, AdamW) | `xiom.torch.optim` | Low |
| 6 | Loss functions (MSE, CrossEntropy, BCE) | `xiom.torch.nn` | Low |
| 7 | Data loading utilities (DataLoader, Dataset) | `xiom.torch.data` | Low |
| 8 | Support for Float64, Int32, Int64, UInt8 tensors | `xiom.torch.types` | Medium |
| 9 | TorchScript model support | `xiom.torch.ffi` | Medium |
| 10 | ONNX export from XIOM models | `xiom.torch.onnx` | Low |

---

## Dependency Map

```
xiom.torch.types          <- Foundation (complete)
        v
xiom.torch.nn             <- NN types + stub forward (complete)
        v
xiom.torch.ops            <- Tensor math (v0.2.0)
        v
xiom.torch.ffi            <- LibTorch bridge (v0.3.0)
        v
xiom.torch.autograd       <- Training (v1.0.0)
xiom.torch.optim          <- Training (v1.0.0)
xiom.torch.data           <- Data pipeline (v1.0.0)
```

## Test Coverage Goals

| Version | Module | Target |
|---------|--------|--------|
| v0.1.0 | `types`, `ffi`, `nn` | 46 tests (current) |
| v0.2.0 | `ops` | 30+ tests (math correctness) |
| v0.3.0 | `ffi` (bridge) | 20+ tests (integration) |
| v1.0.0 | All modules | 120+ tests (full coverage) |

## Safety Contract Goals

| Version | Contracts |
|---------|-----------|
| v0.1.0 | 11 requires/ensures across 6 functions (current) |
| v0.2.0 | Dimension compatibility, broadcast shape, non-empty tensors |
| v0.3.0 | File existence, model validity, GPU availability |
| v1.0.0 | Gradient shape matching, optimizer step bounds, loss non-negativity |
