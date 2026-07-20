# xiom-cuda — SPEC

**Phase**: 2 | **Priority**: HIGH
**Status**: SPEC only | **Depends on**: xiom.ffi, xiom-libtorch (for tensor interop)

## What it wraps
CUDA Toolkit — NVIDIA GPU computing (cuBLAS, cuDNN, cuFFT, cuRAND).

## Dependencies
| What | How | Size |
|------|-----|------|
| CUDA Toolkit 12.x | System-installed. `nvidia-smi` to check. Set `CUDA_PATH`. | ~3GB |

## Bundling strategy: System-installed only. Never bundle.

## API (minimal)
```xiom
// Device
pub fn device_count() -> Int
pub fn device_properties(idx: Int) -> DeviceProps
pub fn set_device(idx: Int)

// Memory
pub fn malloc(size: Int) -> Result[DevicePtr, Str]
pub fn memcpy_htod(dst: DevicePtr, src: &Vec[Float32]) -> Result[Unit, Str]
pub fn memcpy_dtoh(dst: &mut Vec[Float32], src: DevicePtr) -> Result[Unit, Str]
pub fn free(ptr: DevicePtr)

// cuBLAS
pub fn cublas_create() -> Result[CublasHandle, Str]
pub fn cublas_sgemm(handle, transA, transB, m, n, k, alpha, A, B, beta, C)

// cuDNN
pub fn cudnn_create() -> Result[CudnnHandle, Str]
pub fn cudnn_conv2d(handle, input, filter) -> Result[Tensor, Str]
```

## Effort: Week
