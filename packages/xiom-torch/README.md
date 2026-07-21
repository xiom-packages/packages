# xiom-torch

> LibTorch bindings for XIOM — PyTorch C++ inference with compile-time safety.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-torch brings PyTorch model inference to XIOM via LibTorch FFI bindings.
Define neural network architectures in pure XIOM types (Linear, Conv2d,
BatchNorm2d, activations, Sequential) and execute forward passes backed
by the PyTorch C++ runtime.

**Dual tier**: Pure XIOM types and constructors work without any dependency.
FFI tier provides actual LibTorch integration for model inference.

## Installation

```bash
xiom install xiom-torch
```

## Dependencies

### System Libraries

LibTorch is required for FFI-backed inference. Without LibTorch, the pure XIOM
types and constructors still work; only FFI functions return dummy values.

| OS | Command |
|----|---------|
| **Windows** | Download from https://pytorch.org, extract to `C:\libtorch` |
| **Ubuntu/Debian** | Download LibTorch .zip from https://pytorch.org |
| **macOS** | Download LibTorch .zip from https://pytorch.org |

### Build Integration

```bash
xiom myprogram.xi -L $LIBTORCH/lib -l torch -l c10 -I $LIBTORCH/include
```

## Quick Start

```xiom
use xiom.torch.types;
use xiom.torch.nn;

fn main() -> Int {
  var shape = Vec[Int].new();
  shape.push(1);
  shape.push(3);
  shape.push(224);
  shape.push(224);
  var img = tensor_zeros(&shape);

  var conv = conv2d_new(3, 64, 7, 2, 3);
  var relu: ReLU = {};

  var seq = sequential_new();
  sequential_add(&mut seq, LayerType.Conv2dLayer(conv));
  sequential_add(&mut seq, LayerType.ReLULayer);

  return 0;
}
```

## API Reference

### Core Types (xiom.torch.types)

| Type | Description |
|------|-------------|
| `Tensor` | Multi-dimensional array with data, shape, strides, device, dtype |
| `DType` | Enum: Float32, Float64, Int32, Int64, UInt8, Bool |
| `Device` | Enum: CPU, CUDA(device_id) |
| `TensorOptions` | { dtype, device, requires_grad } |
| `ModuleDef` | { name, params, buffers } — represents a saved model |

| Function | Description |
|----------|-------------|
| `tensor_new(shape, options)` | Create zero-initialized tensor |
| `tensor_zeros(shape)` | Shortcut for Float32/CPU zero tensor |
| `tensor_ones(shape)` | Tensor filled with 1.0 |
| `tensor_shape(t)` | Get shape clone |
| `tensor_reshape(t, shape)` | Reshape tensor (same element count) |

### FFI (xiom.torch.ffi)

| Function | Status |
|----------|--------|
| `torch_load_model(path)` | Stub — Load PyTorch model file |
| `torch_forward(module, input)` | Stub — Run inference |
| `torch_save_model(module, path)` | Stub — Save model to disk |
| `torch_is_cuda_available()` | Stub — Always returns false |

### Neural Networks (xiom.torch.nn)

| Type | Description |
|------|-------------|
| `Linear` | Fully-connected layer: { weight, bias, in_features, out_features } |
| `Conv2d` | 2D convolution: { weight, bias, in_ch, out_ch, kernel, stride, padding } |
| `BatchNorm2d` | Batch normalization: { gamma, beta, running_mean, running_var, eps } |
| `ReLU` | ReLU activation: {} |
| `Sigmoid` | Sigmoid activation: {} |
| `Tanh` | Tanh activation: {} |
| `Softmax` | Softmax activation: { dim } |
| `Sequential` | Layer container: { layers: Vec[LayerType] } |
| `LayerType` | Union of all layer types |

| Function | Description |
|----------|-------------|
| `linear_new(in, out)` | Create Linear layer |
| `linear_forward(layer, input)` | Stub — y = x @ W^T + b |
| `conv2d_new(in, out, k, s, p)` | Create Conv2d layer |
| `batchnorm2d_new(features, eps)` | Create BatchNorm2d |
| `sequential_new()` | Create empty Sequential |
| `sequential_add(seq, layer)` | Append layer to model |

## Safety Contracts

Every constructor is guarded:
- `linear_new`: requires in_features > 0, out_features > 0
- `conv2d_new`: requires in_ch > 0, out_ch > 0, kernel > 0, stride > 0, padding >= 0
- `batchnorm2d_new`: requires num_features > 0, eps > 0.0
- `tensor_new`, `tensor_zeros`, `tensor_ones`: requires shape.len() > 0
- `tensor_reshape`: ensures element count is preserved

## Production Readiness

| Feature | Status | Notes |
|---------|--------|-------|
| Tensor types | Complete | Struct/enum definitions |
| Device/DType enums | Complete | All variants defined |
| Tensor constructors | Complete | zeros, ones, new, reshape |
| NN layer types | Complete | Linear, Conv2d, BatchNorm2d |
| Activation types | Complete | ReLU, Sigmoid, Tanh, Softmax |
| Sequential container | Complete | Vec-based with LayerType enum |
| LibTorch FFI stubs | Complete | extern "C" declarations |
| Model inference | Stub | Needs native LibTorch |
| GPU/CUDA support | Not yet | Needs CUDA toolkit |
| Autograd | Not yet | Needs compiler support |

### What's Left for v1.0

1. **LibTorch FFI bridge** — Native C bridge for all extern "C" symbols
2. **Tensor math primitives** — matmul, convolutions, elementwise ops
3. **Real forward passes** — Using tensor math for actual computation
4. **Model serialization** — Load/save .pt and .pth files
5. **GPU support** — CUDA tensor allocation and device transfer

## Build & Run

```bash
# With LibTorch (recommended for production)
xiom myprogram.xi -L $LIBTORCH/lib -l torch -l c10 -I $LIBTORCH/include

# Without LibTorch (types & constructors only)
xiom --run myprogram.xi
```

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)
- **PyTorch**: [pytorch.org](https://pytorch.org)

## License

MIT OR Apache-2.0
