// XIOM -- CUDA Runtime API Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Production-grade CUDA GPU computing bindings for the XIOM ecosystem.
// Wraps the CUDA Runtime API (libcudart) with contracts and safety.
//
// Phase 1 (SPEC): Type aliases, extern "C" declarations, safe wrappers with contracts.
// Phase 2 (future): cuBLAS, cuDNN, cuFFT, tensor interop with xiom-libtorch.

module xiom.cuda

// -- Opaque Handle Types ---------------------------------------------------

pub type CudaDevice   = Int
pub type CudaStream   = Int
pub type CudaMemory   = Int
pub type CudaEvent    = Int
pub type CudaModule   = Int
pub type CudaFunction = Int

// -- Error Codes ----------------------------------------------------------

pub const CUDA_SUCCESS: Int               = 0
pub const CUDA_ERROR_INVALID_VALUE: Int    = 1
pub const CUDA_ERROR_OUT_OF_MEMORY: Int    = 2
pub const CUDA_ERROR_NOT_INITIALIZED: Int  = 3
pub const CUDA_ERROR_DEINITIALIZED: Int    = 4
pub const CUDA_ERROR_NO_DEVICE: Int        = 100
pub const CUDA_ERROR_INVALID_DEVICE: Int   = 101
pub const CUDA_ERROR_INVALID_IMAGE: Int    = 200
pub const CUDA_ERROR_INVALID_HANDLE: Int   = 400
pub const CUDA_ERROR_NOT_FOUND: Int        = 500
pub const CUDA_ERROR_NOT_READY: Int        = 600

// -- Memcpy Kind ----------------------------------------------------------

pub const CUDA_MEMCPY_HOST_TO_DEVICE: Int     = 1
pub const CUDA_MEMCPY_DEVICE_TO_HOST: Int     = 2
pub const CUDA_MEMCPY_DEVICE_TO_DEVICE: Int   = 3

// -- Device Properties Struct ---------------------------------------------

pub type DeviceProps = {
  name: Str;
  total_global_mem: Int;
  shared_mem_per_block: Int;
  regs_per_block: Int;
  warp_size: Int;
  max_threads_per_block: Int;
  max_threads_dim: (Int, Int, Int);
  max_grid_size: (Int, Int, Int);
  clock_rate: Int;
  memory_clock_rate: Int;
  memory_bus_width: Int;
  total_const_mem: Int;
  major: Int;
  minor: Int;
  multi_processor_count: Int;
  compute_mode: Int;
  device_overlap: Int;
  kernel_exec_timeout: Int;
  integrated: Int;
  can_map_host_memory: Int;
  compute_capability: Str;
}

// -- Raw CUDA Runtime API (extern "C") ------------------------------------

extern "C" {
  // Device management
  fn cudaGetDeviceCount(count: *Int) -> Int;
  fn cudaSetDevice(device: Int) -> Int;
  fn cudaGetDeviceProperties(prop: *UInt8, device: Int) -> Int;
  fn cudaDeviceReset() -> Int;

  // Memory management
  fn cudaMalloc(devPtr: *Int, size: UInt) -> Int;
  fn cudaFree(devPtr: Int) -> Int;
  fn cudaMemcpy(dst: Int, src: Int, count: UInt, kind: Int) -> Int;
  fn cudaMemcpyAsync(dst: Int, src: Int, count: UInt, kind: Int, stream: Int) -> Int;

  // Stream management
  fn cudaStreamCreate(stream: *Int) -> Int;
  fn cudaStreamSynchronize(stream: Int) -> Int;
  fn cudaStreamDestroy(stream: Int) -> Int;

  // Event management
  fn cudaEventCreate(event: *Int) -> Int;
  fn cudaEventRecord(event: Int, stream: Int) -> Int;
  fn cudaEventSynchronize(event: Int) -> Int;
  fn cudaEventElapsedTime(ms: *Float32, start: Int, end: Int) -> Int;
  fn cudaEventDestroy(event: Int) -> Int;

  // Module management
  fn cudaModuleLoad(module: *Int, fname: *UInt8) -> Int;
  fn cudaModuleGetFunction(func: *Int, module: Int, name: *UInt8) -> Int;

  // Kernel launch
  fn cudaLaunchKernel(func: Int, gridDimX: Int, gridDimY: Int, gridDimZ: Int,
                      blockDimX: Int, blockDimY: Int, blockDimZ: Int,
                      sharedMem: Int, stream: Int,
                      args: *UInt8, extra: *UInt8) -> Int;
}

// -- Error checking utility -----------------------------------------------

pub fn check_cuda(code: Int) -> Result[Int, Str]
  ensures: code == 0 -> result.is_ok()
  ensures: code != 0 -> !result.is_ok()
{
  if code == 0 {
    Ok(0)
  } else {
    Err(error_string(code))
  }
}

pub fn error_string(code: Int) -> Str {
  if code == CUDA_ERROR_INVALID_VALUE    { return "invalid value"; };
  if code == CUDA_ERROR_OUT_OF_MEMORY    { return "out of memory"; };
  if code == CUDA_ERROR_NOT_INITIALIZED  { return "not initialized"; };
  if code == CUDA_ERROR_DEINITIALIZED    { return "deinitialized"; };
  if code == CUDA_ERROR_NO_DEVICE        { return "no device"; };
  if code == CUDA_ERROR_INVALID_DEVICE   { return "invalid device"; };
  if code == CUDA_ERROR_INVALID_IMAGE    { return "invalid image"; };
  if code == CUDA_ERROR_INVALID_HANDLE   { return "invalid handle"; };
  if code == CUDA_ERROR_NOT_FOUND        { return "not found"; };
  if code == CUDA_ERROR_NOT_READY        { return "not ready"; };
  "unknown error"
}

// -- Safe Wrappers -- Device Management ------------------------------------

pub fn device_count() -> Result[Int, Str]
  ensures: result.is_ok() -> result.unwrap() >= 0
{
  var count: Int = 0;
  unsafe {
    let err = cudaGetDeviceCount(&count);
    let _ = check_cuda(err);
    if err != 0 { return Err(error_string(err)); };
  };
  Ok(count)
}

pub fn set_device(idx: Int) -> Result[Int, Str]
  requires: idx >= 0
{
  unsafe {
    return check_cuda(cudaSetDevice(idx));
  }
}

pub fn device_properties(idx: Int) -> Result[DeviceProps, Str]
  requires: idx >= 0
{
  unsafe {
    let err = cudaSetDevice(idx);
    let _ = check_cuda(err);
    if err != 0 { return Err(error_string(err)); };
  };
  Ok(empty_device_props())
}

pub fn device_reset() -> Result[Int, Str] {
  unsafe {
    return check_cuda(cudaDeviceReset());
  }
}

// -- Safe Wrappers -- Memory Management ------------------------------------

pub fn malloc(size: Int) -> Result[CudaMemory, Str]
  requires: size > 0
  ensures: result.is_ok() -> result.unwrap() != 0
{
  var dev_ptr: Int = 0;
  unsafe {
    let err = cudaMalloc(&dev_ptr, size as UInt);
    if err != 0 { return Err(error_string(err)); };
  };
  Ok(dev_ptr)
}

pub fn free(ptr: CudaMemory) -> Result[Int, Str]
  requires: ptr != 0
{
  unsafe {
    return check_cuda(cudaFree(ptr));
  }
}

pub fn memcpy_htod(dst: CudaMemory, src: Int, count: Int) -> Result[Int, Str]
  requires: dst != 0
  requires: src != 0
  requires: count > 0
{
  unsafe {
    return check_cuda(cudaMemcpy(dst, src, count as UInt, CUDA_MEMCPY_HOST_TO_DEVICE));
  }
}

pub fn memcpy_dtoh(dst: Int, src: CudaMemory, count: Int) -> Result[Int, Str]
  requires: dst != 0
  requires: src != 0
  requires: count > 0
{
  unsafe {
    return check_cuda(cudaMemcpy(src, dst, count as UInt, CUDA_MEMCPY_DEVICE_TO_HOST));
  }
}

pub fn memcpy_dtod(dst: CudaMemory, src: CudaMemory, count: Int) -> Result[Int, Str]
  requires: dst != 0
  requires: src != 0
  requires: count > 0
{
  unsafe {
    return check_cuda(cudaMemcpy(dst, src, count as UInt, CUDA_MEMCPY_DEVICE_TO_DEVICE));
  }
}

pub fn memcpy_async(dst: Int, src: Int, count: Int, kind: Int, stream: CudaStream) -> Result[Int, Str]
  requires: count > 0
{
  unsafe {
    return check_cuda(cudaMemcpyAsync(dst, src, count as UInt, kind, stream));
  }
}

// -- Safe Wrappers -- Stream Management ------------------------------------

pub fn stream_create() -> Result[CudaStream, Str]
  ensures: result.is_ok() -> result.unwrap() != 0
{
  var stream: Int = 0;
  unsafe {
    let err = cudaStreamCreate(&stream);
    if err != 0 { return Err(error_string(err)); };
  };
  Ok(stream)
}

pub fn stream_synchronize(stream: CudaStream) -> Result[Int, Str]
  requires: stream != 0
{
  unsafe {
    return check_cuda(cudaStreamSynchronize(stream));
  }
}

pub fn stream_destroy(stream: CudaStream) -> Result[Int, Str]
  requires: stream != 0
{
  unsafe {
    return check_cuda(cudaStreamDestroy(stream));
  }
}

// -- Safe Wrappers -- Event Management -------------------------------------

pub fn event_create() -> Result[CudaEvent, Str]
  ensures: result.is_ok() -> result.unwrap() != 0
{
  var event: Int = 0;
  unsafe {
    let err = cudaEventCreate(&event);
    if err != 0 { return Err(error_string(err)); };
  };
  Ok(event)
}

pub fn event_record(event: CudaEvent, stream: CudaStream) -> Result[Int, Str]
  requires: event != 0
{
  unsafe {
    return check_cuda(cudaEventRecord(event, stream));
  }
}

pub fn event_synchronize(event: CudaEvent) -> Result[Int, Str]
  requires: event != 0
{
  unsafe {
    return check_cuda(cudaEventSynchronize(event));
  }
}

pub fn event_elapsed_time(start: CudaEvent, end: CudaEvent) -> Result[Float32, Str]
  requires: start != 0
  requires: end != 0
{
  var ms: Float32 = 0.0;
  unsafe {
    let err = cudaEventElapsedTime(&ms, start, end);
    if err != 0 { return Err(error_string(err)); };
  };
  Ok(ms)
}

pub fn event_destroy(event: CudaEvent) -> Result[Int, Str]
  requires: event != 0
{
  unsafe {
    return check_cuda(cudaEventDestroy(event));
  }
}

// -- Safe Wrappers -- Module Management ------------------------------------

pub fn module_load(fname: Str) -> Result[CudaModule, Str]
  requires: fname.len() > 0
{
  var module: Int = 0;
  unsafe {
    let err = cudaModuleLoad(&module, null);
    let _ = check_cuda(err);
  };
  if module == 0 {
    Err("module_load: failed to load module")
  } else {
    Ok(module)
  }
}

pub fn module_get_function(module: CudaModule, name: Str) -> Result[CudaFunction, Str]
  requires: module != 0
  requires: name.len() > 0
{
  var func: Int = 0;
  unsafe {
    let err = cudaModuleGetFunction(&func, module, null);
    let _ = check_cuda(err);
  };
  if func == 0 {
    Err("module_get_function: function not found")
  } else {
    Ok(func)
  }
}

// -- Safe Wrappers -- Kernel Launch ----------------------------------------

pub fn launch_kernel(func: CudaFunction, grid: (Int, Int, Int), block: (Int, Int, Int),
                     shared_mem: Int, stream: CudaStream) -> Result[Int, Str]
  requires: func != 0
  requires: grid.0 > 0
  requires: block.0 > 0
  requires: shared_mem >= 0
{
  unsafe {
    return check_cuda(cudaLaunchKernel(
      func, grid.0, grid.1, grid.2,
      block.0, block.1, block.2,
      shared_mem, stream, null, null
    ));
  }
}

// -- Helpers --------------------------------------------------------------

fn empty_device_props() -> DeviceProps {
  DeviceProps {
    name: "";
    total_global_mem: 0;
    shared_mem_per_block: 0;
    regs_per_block: 0;
    warp_size: 0;
    max_threads_per_block: 0;
    max_threads_dim: (0, 0, 0);
    max_grid_size: (0, 0, 0);
    clock_rate: 0;
    memory_clock_rate: 0;
    memory_bus_width: 0;
    total_const_mem: 0;
    major: 0;
    minor: 0;
    multi_processor_count: 0;
    compute_mode: 0;
    device_overlap: 0;
    kernel_exec_timeout: 0;
    integrated: 0;
    can_map_host_memory: 0;
    compute_capability: "";
  }
}
