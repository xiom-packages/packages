# xiom-onnx — System Dependency Audit

> **Version:** 0.1.0 | **Compiler:** xiom v0.45.3 | **Status:** All modules compile clean.

## Compiler Compatibility

All `.xi` source files pass `xiom --check` with `{"status":"ok"}`.

### Fixes Applied (v0.45.3)

| File | Issue | Fix |
|------|-------|------|
| `src/io.xi` | `.clone()` on `Vec[Int]` / `Vec[Float32]` — method not registered | Replaced with manual `copy_vec_int` / `copy_vec_float32` helpers using `Vec.push` loop |
| `src/io.xi` | `ORT_DTYPE_FLOAT` undefined — bare constant access | Changed to `types.ORT_DTYPE_FLOAT` (module-qualified) |

## System Dependency: ONNX Runtime

The FFI tier (`xiom.onnx.session`) requires the **ONNX Runtime C API shared library** (v1.18.0+). All session functions are stubbed; they return dummy values until the native library is linked.

### Install Instructions

#### Windows
```
Download: https://github.com/microsoft/onnxruntime/releases
  → Select v1.18.0 → onnxruntime-win-x64-1.18.0.zip
Extract to: C:\onnxruntime

Build with:
  set ONNX_RUNTIME_DIR=C:\onnxruntime
  set PATH=%ONNX_RUNTIME_DIR%\lib;%PATH%
  xiom myprogram.xi -L %ONNX_RUNTIME_DIR%\lib -l onnxruntime
```

#### Ubuntu / Debian
```bash
wget https://github.com/microsoft/onnxruntime/releases/download/v1.18.0/onnxruntime-linux-x64-1.18.0.tgz
tar xzf onnxruntime-linux-x64-1.18.0.tgz -C /opt
export ONNX_RUNTIME_DIR=/opt/onnxruntime-linux-x64-1.18.0
export LD_LIBRARY_PATH=$ONNX_RUNTIME_DIR/lib:$LD_LIBRARY_PATH
xiom myprogram.xi -L $ONNX_RUNTIME_DIR/lib -l onnxruntime
```

#### macOS
```bash
wget https://github.com/microsoft/onnxruntime/releases/download/v1.18.0/onnxruntime-osx-universal2-1.18.0.tgz
tar xzf onnxruntime-osx-universal2-1.18.0.tgz -C /opt
export ONNX_RUNTIME_DIR=/opt/onnxruntime-osx-universal2-1.18.0
export DYLD_LIBRARY_PATH=$ONNX_RUNTIME_DIR/lib:$DYLD_LIBRARY_PATH
xiom myprogram.xi -L $ONNX_RUNTIME_DIR/lib -l onnxruntime
```

#### Fedora / RHEL
```bash
# Same as Ubuntu — download the Linux x64 distribution
wget https://github.com/microsoft/onnxruntime/releases/download/v1.18.0/onnxruntime-linux-x64-1.18.0.tgz
tar xzf onnxruntime-linux-x64-1.18.0.tgz -C /opt
export ONNX_RUNTIME_DIR=/opt/onnxruntime-linux-x64-1.18.0
export LD_LIBRARY_PATH=$ONNX_RUNTIME_DIR/lib:$LD_LIBRARY_PATH
```

### Library Dependencies
- `libonnxruntime.so` / `onnxruntime.dll` — Core inference engine
- (Optional) `libonnxruntime_providers_cuda.so` — CUDA execution provider
- (Optional) `libonnxruntime_providers_tensorrt.so` — TensorRT execution provider

### Without ONNX Runtime
- `xiom.onnx.types` and `xiom.onnx.io` work without any dependency (pure XIOM types and constructors)
- `xiom.onnx.session` functions return stubbed values

## GPU Execution Providers

CUDA / TensorRT / DirectML execution providers require additional setup:
- CUDA: NVIDIA CUDA Toolkit 11.8+ and cuDNN 8.x
- TensorRT: NVIDIA TensorRT 8.6+
- DirectML: Windows 10+ with DirectX 12 GPU
- CoreML: macOS 10.15+

## Production Readiness

| Module | Compiles | FFI Required |
|--------|----------|-------------|
| `xiom.onnx.types` | Yes | No |
| `xiom.onnx.io` | Yes | No |
| `xiom.onnx.session` | Yes | ONNX Runtime |
