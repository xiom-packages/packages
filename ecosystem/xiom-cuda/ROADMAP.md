# xiom-cuda — ROADMAP

## Phase 1: Core Foundation (CURRENT)
**Status:** SPEC implemented — types, extern "C" block, safe wrappers with contracts, conformance tests.

| Deliverable | Status |
|---|---|
| `cuda.xi` — module `xiom.cuda` with 6 opaque types, 19 extern "C" declarations, 21 safe wrappers | Done |
| `tests/test_conformance.xi` — 23 conformance tests | Done |
| Opaque handle types: `CudaDevice`, `CudaStream`, `CudaMemory`, `CudaEvent`, `CudaModule`, `CudaFunction` | Done |
| Error codes: `CUDA_SUCCESS`, `CUDA_ERROR_*` (10 codes) | Done |
| Memcpy kind constants: `CUDA_MEMCPY_HOST_TO_DEVICE`, `*_TO_HOST`, `*_TO_DEVICE` | Done |
| Device management: `device_count`, `set_device`, `device_properties`, `device_reset` | Done |
| Memory management: `malloc`, `free`, `memcpy_htod`, `memcpy_dtoh`, `memcpy_dtod`, `memcpy_async` | Done |
| Stream management: `stream_create`, `stream_synchronize`, `stream_destroy` | Done |
| Event management: `event_create`, `event_record`, `event_synchronize`, `event_elapsed_time`, `event_destroy` | Done |
| Module management: `module_load`, `module_get_function` | Done |
| Kernel launch: `launch_kernel` | Done |
| Utility: `check_cuda`, `error_string` | Done |
| `DeviceProps` struct with 20 fields | Done |
| Contract enforcement: `requires:` clauses on all safe wrappers | Done |

## Phase 2: cuBLAS & cuDNN Bindings (planned)
- `cublas.xi` — module `xiom.cublas` with cuBLAS API wrappers
- `cudnn.xi` — module `xiom.cudnn` with cuDNN API wrappers
- `cublasCreate`, `cublasDestroy`, `cublasSgemm`, `cublasDgemm`
- `cudnnCreate`, `cudnnDestroy`, `cudnnConvolutionForward`
- Tensor descriptor types and creation helpers
- Operation descriptor management (convolution, pooling, activation)
- `tests/test_conformance_cublas.xi`, `tests/test_conformance_cudnn.xi`

## Phase 3: cuFFT & cuRAND (planned)
- `cufft.xi` — module `xiom.cufft` with FFT plan creation and execution
- `curand.xi` — module `xiom.curand` with random number generation
- Complex number support for FFT
- RNG state lifecycle: `curandCreateGenerator`, `curandGenerateUniform`, `curandDestroyGenerator`

## Phase 4: Tensor Interop (planned)
- Interop layer with `xiom-libtorch` for tensor GPU migration
- `to_cuda(t: Tensor) -> Tensor` and `to_cpu(t: Tensor) -> Tensor`
- Shared memory management across CUDA and PyTorch contexts
- `DeviceProps` full marshalling from `cudaGetDeviceProperties` C struct

## Phase 5: Advanced CUDA Features (future)
- CUDA Graphs (`cudaGraphCreate`, `cudaGraphLaunch`, `cudaGraphInstantiate`)
- Stream callbacks (`cudaStreamAddCallback`)
- Peer-to-peer memory access (`cudaDeviceEnablePeerAccess`)
- Unified memory (`cudaMallocManaged`)
- CUDA IPC (`cudaIpcGetMemHandle`, `cudaIpcOpenMemHandle`)
- Multi-GPU device management and topology queries
- NVML integration for GPU monitoring (temperature, power, utilization)
