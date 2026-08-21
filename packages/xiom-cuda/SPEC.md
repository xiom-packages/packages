# xiom-cuda -- SPEC

**Phase**: 2 | **Priority**: HIGH
**Status**: Implemented (Phase 1 -- Core Foundation) | **Depends on**: xiom.ffi, xiom-libtorch (for tensor interop)

## What it wraps
CUDA Toolkit -- NVIDIA GPU computing (cuBLAS, cuDNN, cuFFT, cuRAND).

## Dependencies
| What | How | Size |
|------|-----|------|
| CUDA Toolkit 12.x | System-installed. `nvidia-smi` to check. Set `CUDA_PATH`. | ~3GB |

## Bundling strategy: System-installed only. Never bundle.

## Implementation Status (Phase 1)

### Module: `xiom.cuda` (`cuda.xi`)
- **6 opaque handle types**: `CudaDevice`, `CudaStream`, `CudaMemory`, `CudaEvent`, `CudaModule`, `CudaFunction`
- **10 error code constants**: `CUDA_SUCCESS` through `CUDA_ERROR_NOT_READY`
- **3 memcpy kind constants**: `CUDA_MEMCPY_HOST_TO_DEVICE`, `*_TO_HOST`, `*_TO_DEVICE`
- **19 extern "C" declarations**: Full CUDA Runtime API covering device, memory, stream, event, module, and kernel launch
- **21 safe wrappers** with `requires`/`ensures` contracts:
  - Device: `device_count`, `set_device`, `device_properties`, `device_reset`
  - Memory: `malloc`, `free`, `memcpy_htod`, `memcpy_dtoh`, `memcpy_dtod`, `memcpy_async`
  - Stream: `stream_create`, `stream_synchronize`, `stream_destroy`
  - Event: `event_create`, `event_record`, `event_synchronize`, `event_elapsed_time`, `event_destroy`
  - Module: `module_load`, `module_get_function`
  - Kernel: `launch_kernel`
- **Utility functions**: `check_cuda` (error-to-Result), `error_string` (code-to-message)
- **Type**: `DeviceProps` struct with 20 fields

### Tests: `tests/test_conformance.xi`
- **23 conformance tests** covering types, constants, error handling, Result propagation, struct initialization, and all safe wrapper subsystems

## API (minimal -- Phase 1 implemented)
```xiom
// Device
pub fn device_count() -> Result[Int, Str]
pub fn device_properties(idx: Int) -> Result[DeviceProps, Str]
pub fn set_device(idx: Int) -> Result[Int, Str]
pub fn device_reset() -> Result[Int, Str]

// Memory
pub fn malloc(size: Int) -> Result[CudaMemory, Str]
pub fn memcpy_htod(dst: CudaMemory, src: Int, count: Int) -> Result[Int, Str]
pub fn memcpy_dtoh(dst: Int, src: CudaMemory, count: Int) -> Result[Int, Str]
pub fn free(ptr: CudaMemory) -> Result[Int, Str]

// Stream
pub fn stream_create() -> Result[CudaStream, Str]
pub fn stream_synchronize(stream: CudaStream) -> Result[Int, Str]
pub fn stream_destroy(stream: CudaStream) -> Result[Int, Str]

// Event
pub fn event_create() -> Result[CudaEvent, Str]
pub fn event_record(event: CudaEvent, stream: CudaStream) -> Result[Int, Str]
pub fn event_synchronize(event: CudaEvent) -> Result[Int, Str]
pub fn event_elapsed_time(start: CudaEvent, end: CudaEvent) -> Result[Float32, Str]
pub fn event_destroy(event: CudaEvent) -> Result[Int, Str]

// Module
pub fn module_load(fname: Str) -> Result[CudaModule, Str]
pub fn module_get_function(module: CudaModule, name: Str) -> Result[CudaFunction, Str]

// Kernel
pub fn launch_kernel(func: CudaFunction, grid: (Int, Int, Int), block: (Int, Int, Int),
                     shared_mem: Int, stream: CudaStream) -> Result[Int, Str]
```

## Phase 2 (planned): cuBLAS + cuDNN
```xiom
// cuBLAS
pub fn cublas_create() -> Result[CublasHandle, Str]
pub fn cublas_sgemm(handle, transA, transB, m, n, k, alpha, A, B, beta, C)

// cuDNN
pub fn cudnn_create() -> Result[CudnnHandle, Str]
pub fn cudnn_conv2d(handle, input, filter) -> Result[Tensor, Str]
```

## Effort: Week (Phase 1 complete; Phase 2-5 remaining)
