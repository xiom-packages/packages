# xiom-torch — System Dependency Audit

> **Version:** 0.1.0 | **Compiler:** xiom v0.45.3 | **Status:** All modules compile clean.

## Compiler Compatibility

All `.xi` source files pass `xiom --check` with `{"status":"ok"}`.

### Fixes Applied (v0.45.3)

| File | Issue | Fix |
|------|-------|-----|
| `src/types.xi` | `.clone()` on `Vec[Int]` / `Vec[Float32]` — method not registered | Replaced with manual `copy_vec_int` / `copy_vec_float32` helpers using `Vec.push` loop |
| `src/ffi.xi` | `Unit` type unknown; `Ok(Unit{})` parse error | Changed `Result[Unit, Str]` → `Result[Bool, Str]`, returns `Ok(true)` |

## System Dependency: LibTorch

The FFI tier (`xiom.torch.ffi`) requires the **LibTorch C++ distribution** from PyTorch. All FFI functions are stubbed; they return dummy values until the native library is linked.

### Install Instructions

#### Windows
```
Download: https://pytorch.org/get-started/locally/
  → Select "C++/Java" → "LibTorch" → CPU or CUDA
Extract to: C:\libtorch

Build with:
  set LIBTORCH=C:\libtorch
  set PATH=%LIBTORCH%\lib;%PATH%
  xiom myprogram.xi -L %LIBTORCH%\lib -l torch -l c10 -I %LIBTORCH%\include
```

#### Ubuntu / Debian
```bash
wget https://download.pytorch.org/libtorch/cpu/libtorch-shared-with-deps-2.4.0%2Bcpu.zip
unzip libtorch-shared-with-deps-2.4.0+cpu.zip -d /opt/libtorch
export LIBTORCH=/opt/libtorch
export LD_LIBRARY_PATH=$LIBTORCH/lib:$LD_LIBRARY_PATH
xiom myprogram.xi -L $LIBTORCH/lib -l torch -l c10 -I $LIBTORCH/include
```

#### macOS
```bash
wget https://download.pytorch.org/libtorch/cpu/libtorch-macos-2.4.0.zip
unzip libtorch-macos-2.4.0.zip -d /opt/libtorch
export LIBTORCH=/opt/libtorch
export DYLD_LIBRARY_PATH=$LIBTORCH/lib:$DYLD_LIBRARY_PATH
xiom myprogram.xi -L $LIBTORCH/lib -l torch -l c10 -I $LIBTORCH/include
```

#### Fedora / RHEL
```bash
# Same as Ubuntu — download the LibTorch CPU/CUDA distribution
wget https://download.pytorch.org/libtorch/cpu/libtorch-shared-with-deps-2.4.0%2Bcpu.zip
unzip libtorch-shared-with-deps-2.4.0+cpu.zip -d /opt/libtorch
export LIBTORCH=/opt/libtorch
export LD_LIBRARY_PATH=$LIBTORCH/lib:$LD_LIBRARY_PATH
```

### Library Dependencies
- `libtorch.so` / `torch.dll` — Core tensor library
- `libc10.so` / `c10.dll` — C10 utility library
- `libtorch_cpu.so` / `torch_cpu.dll` — CPU backend
- (Optional) `libtorch_cuda.so` / `torch_cuda.dll` — CUDA backend

### Without LibTorch
- `xiom.torch.types` and `xiom.torch.nn` work without any dependency (pure XIOM types and constructors)
- `xiom.torch.ffi` functions return stubbed values

## CUDA Support

CUDA tensor operations require:
- NVIDIA CUDA Toolkit 11.8+
- Compatible NVIDIA GPU driver
- LibTorch CUDA distribution (not CPU-only)

## Production Readiness

| Module | Compiles | FFI Required |
|--------|----------|-------------|
| `xiom.torch.types` | Yes | No |
| `xiom.torch.nn` | Yes | No |
| `xiom.torch.ffi` | Yes | LibTorch |
