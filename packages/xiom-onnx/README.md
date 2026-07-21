# xiom-onnx

> ONNX Runtime bindings for XIOM — cross-framework model inference with compile-time safety.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/XIOM-lang/XIOM.git )
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-onnx provides ONNX Runtime inference for XIOM. Load ONNX models
exported from PyTorch, TensorFlow, scikit-learn, or any ONNX-compatible
framework and run inference through a single unified API.

**Dual tier**: Pure XIOM types and tensor constructors work without any
dependency. FFI tier provides actual ONNX Runtime integration for model
execution.

## Installation

```bash
xiom install xiom-onnx
```

## Dependencies

### System Libraries

ONNX Runtime is required for FFI-backed inference. Without it, the pure XIOM
types and constructors still work; only session/run functions return dummy values.

| OS | Command |
|----|---------|
| **Windows** | Download from https://github.com/microsoft/onnxruntime/releases |
| **Ubuntu/Debian** | Download .tgz from ONNX Runtime releases |
| **macOS** | Download .tgz from ONNX Runtime releases |

### Build Integration

```bash
xiom myprogram.xi -L $ONNX_RUNTIME_DIR/lib -l onnxruntime
```

## Quick Start

```xiom
use xiom.onnx.types;
use xiom.onnx.session;
use xiom.onnx.io;

fn main() -> Int {
  var config = onnx_config_default();
  var model = onnx_load_model("resnet18.onnx", &config).unwrap();

  var shape = Vec[Int].new();
  shape.push(1);
  shape.push(3);
  shape.push(224);
  shape.push(224);
  var input = onnx_tensor_zeros("input", &shape);

  var inputs = Vec[OnnxTensor].new();
  inputs.push(input);
  var outputs = onnx_run(&model, &inputs).unwrap();

  var result = onnx_tensor_to_vec(&outputs[0]);
  return 0;
}
```

## API Reference

### Core Types (xiom.onnx.types)

| Type | Description |
|------|-------------|
| `OnnxModel` | { path, session, input_names, output_names } |
| `OnnxTensor` | { name, data: Vec[Float32], shape, dtype } |
| `OnnxConfig` | { num_threads, graph_optimization_level, enable_profiling } |

| Function | Description |
|----------|-------------|
| `onnx_config_default()` | Default config: 4 threads, basic optimization |

### DType Constants

| Constant | Value | Type |
|----------|-------|------|
| `ORT_DTYPE_FLOAT` | 1 | Float32 |
| `ORT_DTYPE_DOUBLE` | 11 | Float64 |
| `ORT_DTYPE_INT32` | 6 | Int32 |
| `ORT_DTYPE_INT64` | 7 | Int64 |
| `ORT_DTYPE_UINT8` | 2 | UInt8 |
| `ORT_DTYPE_BOOL` | 9 | Bool |

### Session (xiom.onnx.session)

| Function | Status |
|----------|--------|
| `onnx_load_model(path, config)` | Stub — Create inference session |
| `onnx_run(model, inputs)` | Stub — Run inference |
| `onnx_get_input_count(model)` | Stub — Get input count |
| `onnx_get_output_count(model)` | Stub — Get output count |
| `onnx_close(model)` | Stub — Release session |

### Tensor I/O (xiom.onnx.io)

| Function | Description |
|----------|-------------|
| `onnx_tensor_from_vec(data, shape)` | Wrap Vec[Float32] as OnnxTensor |
| `onnx_tensor_to_vec(t)` | Extract Vec[Float32] from OnnxTensor |
| `onnx_tensor_zeros(name, shape)` | Create zero-filled tensor |
| `onnx_preprocess_image(data, target_size)` | Stub — Preprocess for vision models |
| `onnx_tensor_get_name(t)` | Get tensor name |
| `onnx_tensor_set_name(t, name)` | Set tensor name |

## Safety Contracts

- `onnx_tensor_from_vec`: requires data.len() > 0, shape.len() > 0
- `onnx_tensor_zeros`: requires shape.len() > 0
- `onnx_preprocess_image`: requires data.len() > 0, target_size > 0

## Production Readiness

| Feature | Status | Notes |
|---------|--------|-------|
| OnnxModel/OnnxTensor types | Complete | Struct definitions |
| OnnxConfig type | Complete | With defaults |
| Dtype constants | Complete | All ORT enum values |
| Tensor constructors | Complete | from_vec, zeros |
| ONNX Runtime FFI stubs | Complete | extern "C" declarations |
| Session management | Stub | Needs native onnxruntime |
| Model inference | Stub | Needs native onnxruntime |
| Image preprocessing | Stub | Needs xiom-opencv |
| GPU execution | Not yet | CUDA/TensorRT/DirectML |
| Multi-I/O models | Not yet | Needs full FFI bridge |

### What's Left for v1.0

1. **ONNX Runtime FFI bridge** — Native C bridge for all ort_c_* symbols
2. **Execution providers** — CUDA, TensorRT, DirectML, CoreML
3. **Multi-input/output** — Support for models with multiple I/O tensors
4. **Dtype support** — Construction for INT32, INT64, DOUBLE, BOOL
5. **Image preprocessing** — Resize, normalize, mean/std pipeline
6. **Shape inference** — Query input/output metadata from model

## Build & Run

```bash
# With ONNX Runtime (recommended for production)
xiom myprogram.xi -L $ONNX_RUNTIME_DIR/lib -l onnxruntime

# Without ONNX Runtime (types & constructors only)
xiom --run myprogram.xi
```

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/XIOM-lang/XIOM.git )
- **ONNX Runtime**: [github.com/microsoft/onnxruntime](https://github.com/microsoft/onnxruntime)

## License

MIT OR Apache-2.0
