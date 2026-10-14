// XIOM -- xiom.oidn: Intel Open Image Denoise bindings (dynamic loader).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: loader-tier binding over the public C API of Intel Open Image
// Denoise v2.5.1 (github.com/RenderKit/oidn, Apache-2.0; pinned release,
// see PROVENANCE.md). `src/oidn_bridge.cpp` is a self-contained C++ bridge:
// it includes the VENDORED pinned header set
// (vendor/include/OpenImageDenoise/oidn.h + config.h) for exact ABI types,
// resolves `OpenImageDenoise.dll` at runtime (LoadLibraryA/GetProcAddress,
// no import library, no link-time dependency), and exposes the whole C
// surface through `xo_oidn_*` entry points. This module declares those
// entry points (the ONLY extern "C" block in the package -- G5) and wraps
// them in typed XIOM functions.
//
// DECLARED SURFACE: the 67 functions of the public C API in oidn.h --
// physical devices (5), device lifecycle/params/error (22), buffers (15),
// semaphores (6), filters (19). Every one has a typed wrapper here (0
// skips). GPU device variants (SYCL/CUDA/HIP/Metal) are outside the
// declared scope: the C++-only SYCL declarations in oidn.h
// (oidnIsSYCLDeviceSupported / oidnNewSYCLDevice /
// oidnExecuteSYCLFilterAsync) are not bound, the other GPU entry points
// are bound for surface completeness but only their typed-unsupported
// paths are in scope. The CPU device is the supported target.
//
// SAFETY MODEL (v0.64.4 bindings discipline):
//   - handles cross as `Int` (int64); all pointer casts happen in the
//     bridge (B-25: `Int as *UInt8` in XIOM is not value-preserving);
//   - out-params are one XIOM-owned byte slot per call, read byte-indexed
//     little-endian (B-11/B-16/B-17/B-24);
//   - image bytes move through owned `Vec[UInt8]` buffers (B-20); no
//     foreign pointer is ever dereferenced from XIOM;
//   - no bare `null` reaches C (B-23): every pointer argument is an owned
//     slot / Str handle or built inside the bridge;
//   - flat outcome types only -- never `Result[Option[T]]` (B-26);
//   - `Result` payloads are copied to locals before mutation (B-21).

module xiom.oidn

// =========================================================================
// FFI: the bridge surface (src/oidn_bridge.cpp)
// =========================================================================

extern "C" {
  // loader
  fn xo_oidn_soname() -> *UInt8;
  fn xo_oidn_loaded() -> Int32;
  fn xo_oidn_export_count() -> Int32;
  fn xo_oidn_resolved_count() -> Int32;
  fn xo_oidn_missing_count() -> Int32;
  fn xo_oidn_missing_name(idx: Int32, dst: *UInt8, cap: Int32) -> Int32;
  fn xo_oidn_error() -> *UInt8;
  fn xo_oidn_load() -> Int32;
  fn xo_oidn_load_named(soname: *UInt8) -> Int32;
  fn xo_oidn_unload();

  // physical devices + support flags
  fn xo_oidn_num_physical_devices(out4: *UInt8) -> Int32;
  fn xo_oidn_physical_device_get_bool(id: Int32, name: *UInt8, out1: *UInt8) -> Int32;
  fn xo_oidn_physical_device_get_int(id: Int32, name: *UInt8, out4: *UInt8) -> Int32;
  fn xo_oidn_physical_device_get_string(id: Int32, name: *UInt8, dst: *UInt8, cap: Int32, out4len: *UInt8) -> Int32;
  fn xo_oidn_physical_device_get_data(id: Int32, name: *UInt8, dst: *UInt8, cap: Int32, out4len: *UInt8) -> Int32;
  fn xo_oidn_is_cpu_device_supported(out1: *UInt8) -> Int32;
  fn xo_oidn_is_cuda_device_supported(device_id: Int32, out1: *UInt8) -> Int32;
  fn xo_oidn_is_hip_device_supported(device_id: Int32, out1: *UInt8) -> Int32;
  fn xo_oidn_is_metal_device_supported(device: Int, out1: *UInt8) -> Int32;

  // device lifecycle
  fn xo_oidn_device_new(device_type: Int32) -> Int;
  fn xo_oidn_device_new_default() -> Int;
  fn xo_oidn_device_new_cpu() -> Int;
  fn xo_oidn_device_new_by_id(physical_device_id: Int32) -> Int;
  fn xo_oidn_device_new_by_uuid(uuid16: *UInt8) -> Int;
  fn xo_oidn_device_new_by_luid(luid8: *UInt8) -> Int;
  fn xo_oidn_device_new_by_pci_address(pci_domain: Int32, pci_bus: Int32, pci_device: Int32, pci_function: Int32) -> Int;
  fn xo_oidn_device_new_cuda(device_id: Int32) -> Int;
  fn xo_oidn_device_new_hip(device_id: Int32) -> Int;
  fn xo_oidn_device_new_metal(command_queue: Int) -> Int;
  fn xo_oidn_device_retain(device: Int) -> Int32;
  fn xo_oidn_device_release(device: Int) -> Int32;
  fn xo_oidn_device_clear_errors(device: Int) -> Int32;
  fn xo_oidn_device_get_error(device: Int, msg: *UInt8, cap: Int32, out4code: *UInt8) -> Int32;
  fn xo_oidn_device_commit(device: Int) -> Int32;
  fn xo_oidn_device_sync(device: Int) -> Int32;
  fn xo_oidn_device_get_bool(device: Int, name: *UInt8, out1: *UInt8) -> Int32;
  fn xo_oidn_device_get_int(device: Int, name: *UInt8, out4: *UInt8) -> Int32;
  fn xo_oidn_device_set_bool(device: Int, name: *UInt8, value: Int32) -> Int32;
  fn xo_oidn_device_set_int(device: Int, name: *UInt8, value: Int32) -> Int32;
  fn xo_oidn_device_set_error_function(device: Int, enable: Int32) -> Int32;
  fn xo_oidn_device_error_function_hits(out4: *UInt8) -> Int32;
  fn xo_oidn_device_error_function_last(dst: *UInt8, cap: Int32, out4len: *UInt8) -> Int32;

  // buffers
  fn xo_oidn_buffer_new(device: Int, byte_size: Int) -> Int;
  fn xo_oidn_buffer_new_with_storage(device: Int, byte_size: Int, storage: Int32) -> Int;
  fn xo_oidn_buffer_new_shared(device: Int, ptr: *UInt8, byte_size: Int) -> Int;
  fn xo_oidn_buffer_new_shared_fd(device: Int, flags: Int32, fd: Int32, byte_size: Int) -> Int;
  fn xo_oidn_buffer_new_shared_win32(device: Int, flags: Int32, handle: Int, name: Int, byte_size: Int) -> Int;
  fn xo_oidn_buffer_new_shared_metal(device: Int, metal_buffer: Int) -> Int;
  fn xo_oidn_buffer_retain(buffer: Int) -> Int32;
  fn xo_oidn_buffer_release(buffer: Int) -> Int32;
  fn xo_oidn_buffer_size(device: Int, buffer: Int, out8: *UInt8) -> Int32;
  fn xo_oidn_buffer_storage(device: Int, buffer: Int, out4: *UInt8) -> Int32;
  fn xo_oidn_buffer_data_addr(device: Int, buffer: Int, out8: *UInt8) -> Int32;
  fn xo_oidn_buffer_read(device: Int, buffer: Int, offset: Int, size: Int, dst: *UInt8) -> Int32;
  fn xo_oidn_buffer_read_async(device: Int, buffer: Int, offset: Int, size: Int, dst: *UInt8) -> Int32;
  fn xo_oidn_buffer_write(device: Int, buffer: Int, offset: Int, size: Int, src: *UInt8) -> Int32;
  fn xo_oidn_buffer_write_async(device: Int, buffer: Int, offset: Int, size: Int, src: *UInt8) -> Int32;

  // semaphores
  fn xo_oidn_semaphore_new_shared_fd(device: Int, flags: Int32, fd: Int32) -> Int;
  fn xo_oidn_semaphore_new_shared_win32(device: Int, flags: Int32, handle: Int, name: Int) -> Int;
  fn xo_oidn_semaphore_signal(device: Int, handles8: *UInt8, values8: *UInt8, count: Int32) -> Int32;
  fn xo_oidn_semaphore_wait(device: Int, handles8: *UInt8, values8: *UInt8, timeouts4: *UInt8, count: Int32) -> Int32;
  fn xo_oidn_semaphore_retain(semaphore: Int) -> Int32;
  fn xo_oidn_semaphore_release(semaphore: Int) -> Int32;

  // filters
  fn xo_oidn_filter_new(device: Int, filter_type: *UInt8) -> Int;
  fn xo_oidn_filter_retain(filter: Int) -> Int32;
  fn xo_oidn_filter_release(filter: Int) -> Int32;
  fn xo_oidn_filter_set_image(device: Int, filter: Int, name: *UInt8, buffer: Int, format: Int32, width: Int, height: Int, byte_offset: Int, pixel_byte_stride: Int, row_byte_stride: Int) -> Int32;
  fn xo_oidn_filter_set_shared_image(device: Int, filter: Int, name: *UInt8, ptr: *UInt8, format: Int32, width: Int, height: Int, byte_offset: Int, pixel_byte_stride: Int, row_byte_stride: Int) -> Int32;
  fn xo_oidn_filter_unset_image(device: Int, filter: Int, name: *UInt8) -> Int32;
  fn xo_oidn_filter_set_data(device: Int, filter: Int, name: *UInt8, ptr: *UInt8, byte_size: Int) -> Int32;
  fn xo_oidn_filter_update_data(device: Int, filter: Int, name: *UInt8) -> Int32;
  fn xo_oidn_filter_unset_data(device: Int, filter: Int, name: *UInt8) -> Int32;
  fn xo_oidn_filter_set_bool(device: Int, filter: Int, name: *UInt8, value: Int32) -> Int32;
  fn xo_oidn_filter_get_bool(device: Int, filter: Int, name: *UInt8, out1: *UInt8) -> Int32;
  fn xo_oidn_filter_set_int(device: Int, filter: Int, name: *UInt8, value: Int32) -> Int32;
  fn xo_oidn_filter_get_int(device: Int, filter: Int, name: *UInt8, out4: *UInt8) -> Int32;
  fn xo_oidn_filter_set_float(device: Int, filter: Int, name: *UInt8, value: Float32) -> Int32;
  fn xo_oidn_filter_get_float(device: Int, filter: Int, name: *UInt8, out4: *UInt8) -> Int32;
  fn xo_oidn_filter_set_progress_monitor(device: Int, filter: Int, enable: Int32) -> Int32;
  fn xo_oidn_filter_progress_hits(out4: *UInt8) -> Int32;
  fn xo_oidn_filter_progress_reset() -> Int32;
  fn xo_oidn_filter_commit(device: Int, filter: Int) -> Int32;
  fn xo_oidn_filter_execute(device: Int, filter: Int) -> Int32;
  fn xo_oidn_filter_execute_async(device: Int, filter: Int) -> Int32;

  // test-support analysis over owned buffers
  fn xo_oidn_f32_analyze(input: *UInt8, output: *UInt8, float_count: Int32, eps_milli: Int32, out_slots: *UInt8) -> Int32;
  fn xo_oidn_byte_diff(a: *UInt8, b: *UInt8, byte_count: Int32, out4: *UInt8) -> Int32;
  fn xo_oidn_byte_equal(a: *UInt8, b: *UInt8, byte_count: Int32, out1: *UInt8) -> Int32;
}

// =========================================================================
// Constants (transcribed from the pinned oidn.h)
// =========================================================================

/// Size of a physical-device UUID in bytes (OIDN_UUID_SIZE).
pub const OIDN_UUID_SIZE: Int = 16;

/// Size of a physical-device LUID in bytes (OIDN_LUID_SIZE).
pub const OIDN_LUID_SIZE: Int = 8;

/// Device types (OIDNDeviceType).
pub const OIDN_DEVICE_TYPE_DEFAULT: Int = 0;
pub const OIDN_DEVICE_TYPE_CPU: Int = 1;
pub const OIDN_DEVICE_TYPE_SYCL: Int = 2;
pub const OIDN_DEVICE_TYPE_CUDA: Int = 3;
pub const OIDN_DEVICE_TYPE_HIP: Int = 4;
pub const OIDN_DEVICE_TYPE_METAL: Int = 5;

/// Error codes (OIDNError).
pub const OIDN_ERROR_NONE: Int = 0;
pub const OIDN_ERROR_UNKNOWN: Int = 1;
pub const OIDN_ERROR_INVALID_ARGUMENT: Int = 2;
pub const OIDN_ERROR_INVALID_OPERATION: Int = 3;
pub const OIDN_ERROR_OUT_OF_MEMORY: Int = 4;
pub const OIDN_ERROR_UNSUPPORTED_HARDWARE: Int = 5;
pub const OIDN_ERROR_CANCELLED: Int = 6;

/// Buffer formats (OIDNFormat).
pub const OIDN_FORMAT_UNDEFINED: Int = 0;
pub const OIDN_FORMAT_FLOAT: Int = 1;
pub const OIDN_FORMAT_FLOAT2: Int = 2;
pub const OIDN_FORMAT_FLOAT3: Int = 3;
pub const OIDN_FORMAT_FLOAT4: Int = 4;
pub const OIDN_FORMAT_HALF: Int = 257;
pub const OIDN_FORMAT_HALF2: Int = 258;
pub const OIDN_FORMAT_HALF3: Int = 259;
pub const OIDN_FORMAT_HALF4: Int = 260;

/// Storage modes (OIDNStorage).
pub const OIDN_STORAGE_UNDEFINED: Int = 0;
pub const OIDN_STORAGE_HOST: Int = 1;
pub const OIDN_STORAGE_DEVICE: Int = 2;
pub const OIDN_STORAGE_MANAGED: Int = 3;

/// External memory type flags (OIDNExternalMemoryTypeFlag).
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_NONE: Int = 0;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_OPAQUE_FD: Int = 1;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_DMA_BUF: Int = 2;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_OPAQUE_WIN32: Int = 4;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_OPAQUE_WIN32_KMT: Int = 8;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_D3D11_TEXTURE: Int = 16;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_D3D11_TEXTURE_KMT: Int = 32;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_D3D11_RESOURCE: Int = 64;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_D3D11_RESOURCE_KMT: Int = 128;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_D3D12_HEAP: Int = 256;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_D3D12_RESOURCE: Int = 512;
pub const OIDN_EXTERNAL_MEMORY_TYPE_FLAG_DEDICATED: Int = 1073741824;

/// External semaphore type flags (OIDNExternalSemaphoreTypeFlag).
pub const OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_NONE: Int = 0;
pub const OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_OPAQUE_FD: Int = 1;
pub const OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_OPAQUE_WIN32: Int = 2;
pub const OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_OPAQUE_WIN32_KMT: Int = 4;
pub const OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_D3D11_FENCE: Int = 8;
pub const OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_D3D12_FENCE: Int = 16;
pub const OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_KEYED_MUTEX: Int = 32;
pub const OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_KEYED_MUTEX_KMT: Int = 64;
pub const OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_TIMELINE_SEMAPHORE_FD: Int = 128;
pub const OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_TIMELINE_SEMAPHORE_WIN32: Int = 256;

/// Filter quality/performance modes (OIDNQuality).
pub const OIDN_QUALITY_DEFAULT: Int = 0;
pub const OIDN_QUALITY_FAST: Int = 4;
pub const OIDN_QUALITY_BALANCED: Int = 5;
pub const OIDN_QUALITY_HIGH: Int = 6;

/// Loader classification codes (the bridge's xo_oidn_load* return values).
pub const OIDN_LOAD_OK: Int = 0;
pub const OIDN_LOAD_ABSENT: Int = 1;
pub const OIDN_LOAD_ABI: Int = 2;

/// Default runtime soname.
pub const OIDN_SONAME: Str = "OpenImageDenoise.dll";

// =========================================================================
// Types (flat outcome structs -- no nested enum payloads, B-26)
// =========================================================================

/// Loader outcome: soname, resolved and required export counts.
pub type OidnInfo = {
  soname: Str;
  resolved: Int;
  required: Int;
}

/// Loader failure: kind is OIDN_LOAD_ABSENT / OIDN_LOAD_ABI.
pub type OidnLoadError = {
  kind: Int;
  message: Str;
}

/// Typed OIDN error: the library error code plus its message.
pub type OidnError = {
  code: Int;
  message: Str;
}

/// Float32 buffer summary (analysis helper over owned buffers):
/// finite/changed value counts plus min/max/mean in milli units.
pub type OidnF32Stats = {
  finite: Int;
  changed: Int;
  min_milli: Int;
  max_milli: Int;
  mean_milli: Int;
}

// =========================================================================
// Internal helpers
// =========================================================================

/// n zero bytes in an XIOM-owned slot.
/// Complexity: O(n).
fn xo_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Byte-indexed u8 read from an owned slot.
/// Complexity: O(1).
fn xo_rd_u8(buf: &Vec[UInt8], off: Int) -> Int
  requires: buf.len() >= off + 1
{
  return buf[off] as Int;
}

/// Byte-indexed little-endian i32 read from an owned slot.
/// Complexity: O(1).
fn xo_rd_i32(buf: &Vec[UInt8], off: Int) -> Int
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Byte-indexed little-endian u64 read from an owned slot.
/// Complexity: O(1).
fn xo_rd_u64(buf: &Vec[UInt8], off: Int) -> Int
  requires: buf.len() >= off + 8
{
  var v: Int = 0;
  var i: Int = 0;
  while i < 8 {
    v = v | ((buf[off + i] as Int) << (8 * i));
    i = i + 1;
  }
  return v;
}

/// The bridge's last error message as a Str (bridge-owned memory).
/// Complexity: O(len).
fn xo_bridge_message() -> Str
  requires: true
{
  unsafe {
    let p = xo_oidn_error();
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// Typed error from a non-zero bridge status (code + bridge message).
/// Complexity: O(len).
fn xo_err(code: Int) -> OidnError
  requires: code != 0
{
  return OidnError{ code: code; message: xo_bridge_message() };
}

/// Local Int-to-Str (lane pattern: avoids cross-module const/convert
/// resolution traps in confined modules; see BINDINGS-COMPILER-FINDINGS).
/// Complexity: O(digits).
pub fn oidn_int_to_str(n: Int) -> Str
  requires: true
{
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}

// =========================================================================
// Loader
// =========================================================================

/// The bridge's compiled-in soname.
/// Complexity: O(1).
pub fn oidn_soname() -> Str
  requires: true
{
  return OIDN_SONAME;
}

/// Whether a runtime is currently loaded.
/// Complexity: O(1).
pub fn oidn_loaded() -> Bool
  requires: true
{
  return unsafe { xo_oidn_loaded() != 0 };
}

/// Size of the required export table (67).
/// Complexity: O(1).
pub fn oidn_export_count() -> Int
  requires: true
{
  return unsafe { xo_oidn_export_count() as Int };
}

/// Number of exports resolved by the current load.
/// Complexity: O(1).
pub fn oidn_resolved_count() -> Int
  requires: true
{
  return unsafe { xo_oidn_resolved_count() as Int };
}

/// Number of required exports missing from the loaded library.
/// Complexity: O(1).
pub fn oidn_missing_count() -> Int
  requires: true
{
  return unsafe { xo_oidn_missing_count() as Int };
}

/// Name of the first missing export copied into an owned slot; returns the
/// copied length, or -1 when nothing is missing. The slot is NUL-terminated.
/// Complexity: O(len).
pub fn oidn_missing_name(buf: &mut Vec[UInt8]) -> Int
  requires: buf.len() > 0
{
  return unsafe { xo_oidn_missing_name(0, buf.as_mut_ptr(), buf.len() as Int32) as Int };
}

/// The bridge's last error message.
/// Complexity: O(len).
pub fn oidn_last_error() -> Str
  requires: true
{
  return xo_bridge_message();
}

/// Load the default runtime (`OpenImageDenoise.dll`).
/// Complexity: O(load + export resolution).
pub fn oidn_load() -> Result[OidnInfo, OidnLoadError]
  requires: true
{
  let rc = unsafe { xo_oidn_load() as Int };
  if rc != OIDN_LOAD_OK {
    var kind = OIDN_LOAD_ABI;
    if rc == OIDN_LOAD_ABSENT { kind = OIDN_LOAD_ABSENT; }
    return Err(OidnLoadError{ kind: kind; message: xo_bridge_message() });
  }
  return Ok(OidnInfo{
    soname: OIDN_SONAME;
    resolved: oidn_resolved_count();
    required: oidn_export_count();
  });
}

/// Load an explicitly named runtime (path or soname). A bogus name yields
/// the deterministic ABSENT classification on any host.
/// Complexity: O(load + export resolution).
pub fn oidn_load_named(soname: Str) -> Result[OidnInfo, OidnLoadError]
  requires: soname.len() > 0
{
  let rc = unsafe { xo_oidn_load_named(soname.c_str()) as Int };
  if rc != OIDN_LOAD_OK {
    var kind = OIDN_LOAD_ABI;
    if rc == OIDN_LOAD_ABSENT { kind = OIDN_LOAD_ABSENT; }
    return Err(OidnLoadError{ kind: kind; message: xo_bridge_message() });
  }
  return Ok(OidnInfo{
    soname: soname;
    resolved: oidn_resolved_count();
    required: oidn_export_count();
  });
}

/// Release the runtime (previously created handles become invalid).
/// Complexity: O(1).
pub fn oidn_unload()
  requires: true
{
  unsafe { xo_oidn_unload(); }
}

// =========================================================================
// Physical devices (5 functions)
// =========================================================================

/// Number of physical devices (oidnGetNumPhysicalDevices).
/// Complexity: O(1).
pub fn oidn_get_num_physical_devices() -> Result[Int, OidnError]
  requires: true
{
  var slot = xo_slot(4);
  let rc = unsafe { xo_oidn_num_physical_devices(slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_i32(&slot, 0));
}

/// Boolean physical-device parameter (oidnGetPhysicalDeviceBool).
/// Complexity: O(len(name)).
pub fn oidn_get_physical_device_bool(id: Int, name: Str) -> Result[Bool, OidnError]
  requires: name.len() > 0
{
  var slot = xo_slot(1);
  let rc = unsafe { xo_oidn_physical_device_get_bool(id as Int32, name.c_str(), slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_u8(&slot, 0) != 0);
}

/// Integer physical-device parameter (oidnGetPhysicalDeviceInt).
/// Complexity: O(len(name)).
pub fn oidn_get_physical_device_int(id: Int, name: Str) -> Result[Int, OidnError]
  requires: name.len() > 0
{
  var slot = xo_slot(4);
  let rc = unsafe { xo_oidn_physical_device_get_int(id as Int32, name.c_str(), slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_i32(&slot, 0));
}

/// String physical-device parameter copied into an owned slot
/// (oidnGetPhysicalDeviceString); returns the copied length.
/// Complexity: O(len).
pub fn oidn_get_physical_device_string(id: Int, name: Str, buf: &mut Vec[UInt8]) -> Result[Int, OidnError]
  requires: name.len() > 0
  requires: buf.len() > 0
{
  var len_slot = xo_slot(4);
  let rc = unsafe { xo_oidn_physical_device_get_string(id as Int32, name.c_str(), buf.as_mut_ptr(), buf.len() as Int32, len_slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_i32(&len_slot, 0));
}

/// Opaque data physical-device parameter copied into an owned slot
/// (oidnGetPhysicalDeviceData); returns the copied byte count.
/// Complexity: O(len).
pub fn oidn_get_physical_device_data(id: Int, name: Str, buf: &mut Vec[UInt8]) -> Result[Int, OidnError]
  requires: name.len() > 0
  requires: buf.len() > 0
{
  var len_slot = xo_slot(4);
  let rc = unsafe { xo_oidn_physical_device_get_data(id as Int32, name.c_str(), buf.as_mut_ptr(), buf.len() as Int32, len_slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_i32(&len_slot, 0));
}

/// Whether the CPU device is supported (oidnIsCPUDeviceSupported).
/// Complexity: O(1).
pub fn oidn_is_cpu_device_supported() -> Result[Bool, OidnError]
  requires: true
{
  var slot = xo_slot(1);
  let rc = unsafe { xo_oidn_is_cpu_device_supported(slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_u8(&slot, 0) != 0);
}

/// Whether the given CUDA device is supported (oidnIsCUDADeviceSupported).
/// Complexity: O(1).
pub fn oidn_is_cuda_device_supported(device_id: Int) -> Result[Bool, OidnError]
  requires: true
{
  var slot = xo_slot(1);
  let rc = unsafe { xo_oidn_is_cuda_device_supported(device_id as Int32, slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_u8(&slot, 0) != 0);
}

/// Whether the given HIP device is supported (oidnIsHIPDeviceSupported).
/// Complexity: O(1).
pub fn oidn_is_hip_device_supported(device_id: Int) -> Result[Bool, OidnError]
  requires: true
{
  var slot = xo_slot(1);
  let rc = unsafe { xo_oidn_is_hip_device_supported(device_id as Int32, slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_u8(&slot, 0) != 0);
}

/// Whether the given Metal device is supported (oidnIsMetalDeviceSupported);
/// the device crosses as an integer pointer value (never cast in XIOM, B-25).
/// Complexity: O(1).
pub fn oidn_is_metal_device_supported(device: Int) -> Result[Bool, OidnError]
  requires: true
{
  var slot = xo_slot(1);
  let rc = unsafe { xo_oidn_is_metal_device_supported(device, slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_u8(&slot, 0) != 0);
}

// =========================================================================
// Device lifecycle (22 functions)
// =========================================================================

/// Create a device of the given type (oidnNewDevice).
/// Complexity: O(device creation).
pub fn oidn_new_device(device_type: Int) -> Result[Int, OidnError]
  requires: true
{
  let h = unsafe { xo_oidn_device_new(device_type as Int32) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create the default device (oidnNewDevice with OIDN_DEVICE_TYPE_DEFAULT).
/// Complexity: O(device creation).
pub fn oidn_new_device_default() -> Result[Int, OidnError]
  requires: true
{
  let h = unsafe { xo_oidn_device_new_default() };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create the CPU device.
/// Complexity: O(device creation).
pub fn oidn_new_device_cpu() -> Result[Int, OidnError]
  requires: true
{
  let h = unsafe { xo_oidn_device_new_cpu() };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create a device from a physical device ID (oidnNewDeviceByID).
/// Complexity: O(device creation).
pub fn oidn_new_device_by_id(physical_device_id: Int) -> Result[Int, OidnError]
  requires: true
{
  let h = unsafe { xo_oidn_device_new_by_id(physical_device_id as Int32) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create a device from a 16-byte UUID (oidnNewDeviceByUUID).
/// Complexity: O(device creation).
pub fn oidn_new_device_by_uuid(uuid: &Vec[UInt8]) -> Result[Int, OidnError]
  requires: uuid.len() >= OIDN_UUID_SIZE
{
  let h = unsafe { xo_oidn_device_new_by_uuid(uuid.as_mut_ptr()) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create a device from an 8-byte LUID (oidnNewDeviceByLUID).
/// Complexity: O(device creation).
pub fn oidn_new_device_by_luid(luid: &Vec[UInt8]) -> Result[Int, OidnError]
  requires: luid.len() >= OIDN_LUID_SIZE
{
  let h = unsafe { xo_oidn_device_new_by_luid(luid.as_mut_ptr()) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create a device from a PCI address (oidnNewDeviceByPCIAddress).
/// Complexity: O(device creation).
pub fn oidn_new_device_by_pci_address(pci_domain: Int, pci_bus: Int, pci_device: Int, pci_function: Int) -> Result[Int, OidnError]
  requires: true
{
  let h = unsafe { xo_oidn_device_new_by_pci_address(pci_domain as Int32, pci_bus as Int32, pci_device as Int32, pci_function as Int32) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create a CUDA device from a device ID (oidnNewCUDADevice; one pair).
/// Complexity: O(device creation).
pub fn oidn_new_cuda_device(device_id: Int) -> Result[Int, OidnError]
  requires: true
{
  let h = unsafe { xo_oidn_device_new_cuda(device_id as Int32) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create a HIP device from a device ID (oidnNewHIPDevice; one pair).
/// Complexity: O(device creation).
pub fn oidn_new_hip_device(device_id: Int) -> Result[Int, OidnError]
  requires: true
{
  let h = unsafe { xo_oidn_device_new_hip(device_id as Int32) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create a Metal device from a command-queue pointer value
/// (oidnNewMetalDevice, one queue; pointer crosses as Int).
/// Complexity: O(device creation).
pub fn oidn_new_metal_device(command_queue: Int) -> Result[Int, OidnError]
  requires: true
{
  let h = unsafe { xo_oidn_device_new_metal(command_queue) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Retain the device reference (oidnRetainDevice).
/// Complexity: O(1).
pub fn oidn_retain_device(device: Int) -> Result[Unit, OidnError]
  requires: device != 0
{
  let rc = unsafe { xo_oidn_device_retain(device) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Release the device reference (oidnReleaseDevice).
/// Complexity: O(1).
pub fn oidn_release_device(device: Int) -> Result[Unit, OidnError]
  requires: device != 0
{
  let rc = unsafe { xo_oidn_device_release(device) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Discard any pending device errors without reporting them.
/// Complexity: O(1).
pub fn oidn_device_clear_errors(device: Int) -> Result[Unit, OidnError]
  requires: device != 0
{
  let rc = unsafe { xo_oidn_device_clear_errors(device) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// First pending error of the device (oidnGetDeviceError); code 0 = none.
/// The message is copied into the owned slot.
/// Complexity: O(len(message)).
pub fn oidn_device_get_error(device: Int, msg: &mut Vec[UInt8]) -> OidnError
  requires: msg.len() > 0
{
  var code_slot = xo_slot(4);
  let rc = unsafe { xo_oidn_device_get_error(device, msg.as_mut_ptr(), msg.len() as Int32, code_slot.as_mut_ptr()) as Int };
  if rc != 0 {
    return OidnError{ code: OIDN_ERROR_UNKNOWN; message: "oidn: not loaded" };
  }
  let code = xo_rd_i32(&code_slot, 0);
  if code == 0 {
    return OidnError{ code: 0; message: "" };
  }
  return OidnError{ code: code; message: xo_slot_str(msg) };
}

/// Owned NUL-terminated bytes as a Str.
/// Complexity: O(len).
fn xo_slot_str(buf: &mut Vec[UInt8]) -> Str
  requires: buf.len() > 0
{
  unsafe {
    return Str::from_c_str(buf.as_mut_ptr());
  }
}

/// Commit all pending device changes (oidnCommitDevice).
/// Complexity: O(commit).
pub fn oidn_commit_device(device: Int) -> Result[Unit, OidnError]
  requires: device != 0
{
  let rc = unsafe { xo_oidn_device_commit(device) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Wait for all pending device work (oidnSyncDevice).
/// Complexity: O(pending work).
pub fn oidn_sync_device(device: Int) -> Result[Unit, OidnError]
  requires: device != 0
{
  let rc = unsafe { xo_oidn_device_sync(device) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Boolean device parameter (oidnGetDeviceBool).
/// Complexity: O(len(name)).
pub fn oidn_get_device_bool(device: Int, name: Str) -> Result[Bool, OidnError]
  requires: device != 0
  requires: name.len() > 0
{
  var slot = xo_slot(1);
  let rc = unsafe { xo_oidn_device_get_bool(device, name.c_str(), slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_u8(&slot, 0) != 0);
}

/// Integer device parameter (oidnGetDeviceInt).
/// Complexity: O(len(name)).
pub fn oidn_get_device_int(device: Int, name: Str) -> Result[Int, OidnError]
  requires: device != 0
  requires: name.len() > 0
{
  var slot = xo_slot(4);
  let rc = unsafe { xo_oidn_device_get_int(device, name.c_str(), slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_i32(&slot, 0));
}

/// Set a boolean device parameter (oidnSetDeviceBool).
/// Complexity: O(len(name)).
pub fn oidn_set_device_bool(device: Int, name: Str, value: Bool) -> Result[Unit, OidnError]
  requires: device != 0
  requires: name.len() > 0
{
  var v: Int32 = 0 as Int32;
  if value { v = 1 as Int32; }
  let rc = unsafe { xo_oidn_device_set_bool(device, name.c_str(), v) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Set an integer device parameter (oidnSetDeviceInt).
/// Complexity: O(len(name)).
pub fn oidn_set_device_int(device: Int, name: Str, value: Int) -> Result[Unit, OidnError]
  requires: device != 0
  requires: name.len() > 0
{
  let rc = unsafe { xo_oidn_device_set_int(device, name.c_str(), value as Int32) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Install (enable=true) or remove the bridge-owned error callback through
/// oidnSetDeviceErrorFunction; hits are counted by the bridge.
/// Complexity: O(1).
pub fn oidn_set_device_error_function(device: Int, enable: Bool) -> Result[Unit, OidnError]
  requires: device != 0
{
  var v: Int32 = 0 as Int32;
  if enable { v = 1 as Int32; }
  let rc = unsafe { xo_oidn_device_set_error_function(device, v) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Number of error-callback invocations since load.
/// Complexity: O(1).
pub fn oidn_device_error_function_hits() -> Int
  requires: true
{
  var slot = xo_slot(4);
  unsafe { xo_oidn_device_error_function_hits(slot.as_mut_ptr()); }
  return xo_rd_i32(&slot, 0);
}

/// Last error-callback message copied into an owned slot; returns the
/// copied length.
/// Complexity: O(len).
pub fn oidn_device_error_function_last(buf: &mut Vec[UInt8]) -> Int
  requires: buf.len() > 0
{
  var len_slot = xo_slot(4);
  unsafe { xo_oidn_device_error_function_last(buf.as_mut_ptr(), buf.len() as Int32, len_slot.as_mut_ptr()); }
  return xo_rd_i32(&len_slot, 0);
}

// =========================================================================
// Buffers (15 functions)
// =========================================================================

/// Create a device buffer of `byte_size` bytes (oidnNewBuffer).
/// Complexity: O(allocation).
pub fn oidn_new_buffer(device: Int, byte_size: Int) -> Result[Int, OidnError]
  requires: device != 0
  requires: byte_size > 0
{
  let h = unsafe { xo_oidn_buffer_new(device, byte_size) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create a buffer with an explicit storage mode (oidnNewBufferWithStorage).
/// Complexity: O(allocation).
pub fn oidn_new_buffer_with_storage(device: Int, byte_size: Int, storage: Int) -> Result[Int, OidnError]
  requires: device != 0
  requires: byte_size > 0
{
  let h = unsafe { xo_oidn_buffer_new_with_storage(device, byte_size, storage as Int32) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Create a shared buffer over XIOM-owned memory (oidnNewSharedBuffer);
/// the owned Vec must outlive the buffer.
/// Complexity: O(1).
pub fn oidn_new_shared_buffer(device: Int, mem: &mut Vec[UInt8]) -> Result[Int, OidnError]
  requires: device != 0
  requires: mem.len() > 0
{
  let h = unsafe { xo_oidn_buffer_new_shared(device, mem.as_mut_ptr(), mem.len()) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Import an external POSIX-fd memory handle (oidnNewSharedBufferFromFD).
/// Complexity: O(import).
pub fn oidn_new_shared_buffer_from_fd(device: Int, flags: Int, fd: Int, byte_size: Int) -> Result[Int, OidnError]
  requires: device != 0
  requires: byte_size > 0
{
  let h = unsafe { xo_oidn_buffer_new_shared_fd(device, flags as Int32, fd as Int32, byte_size) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Import an external Win32-handle memory object
/// (oidnNewSharedBufferFromWin32Handle); handle/name cross as integers.
/// Complexity: O(import).
pub fn oidn_new_shared_buffer_from_win32_handle(device: Int, flags: Int, handle: Int, name: Int, byte_size: Int) -> Result[Int, OidnError]
  requires: device != 0
  requires: byte_size > 0
{
  let h = unsafe { xo_oidn_buffer_new_shared_win32(device, flags as Int32, handle, name, byte_size) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Import a Metal buffer as a shared buffer (oidnNewSharedBufferFromMetal);
/// the buffer crosses as an integer pointer value.
/// Complexity: O(import).
pub fn oidn_new_shared_buffer_from_metal(device: Int, metal_buffer: Int) -> Result[Int, OidnError]
  requires: device != 0
{
  let h = unsafe { xo_oidn_buffer_new_shared_metal(device, metal_buffer) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Retain the buffer reference (oidnRetainBuffer).
/// Complexity: O(1).
pub fn oidn_retain_buffer(buffer: Int) -> Result[Unit, OidnError]
  requires: buffer != 0
{
  let rc = unsafe { xo_oidn_buffer_retain(buffer) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Release the buffer reference (oidnReleaseBuffer).
/// Complexity: O(1).
pub fn oidn_release_buffer(buffer: Int) -> Result[Unit, OidnError]
  requires: buffer != 0
{
  let rc = unsafe { xo_oidn_buffer_release(buffer) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Buffer size in bytes (oidnGetBufferSize).
/// Complexity: O(1).
pub fn oidn_get_buffer_size(device: Int, buffer: Int) -> Result[Int, OidnError]
  requires: device != 0
  requires: buffer != 0
{
  var slot = xo_slot(8);
  let rc = unsafe { xo_oidn_buffer_size(device, buffer, slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_u64(&slot, 0));
}

/// Buffer storage mode (oidnGetBufferStorage).
/// Complexity: O(1).
pub fn oidn_get_buffer_storage(device: Int, buffer: Int) -> Result[Int, OidnError]
  requires: device != 0
  requires: buffer != 0
{
  var slot = xo_slot(4);
  let rc = unsafe { xo_oidn_buffer_storage(device, buffer, slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_i32(&slot, 0));
}

/// Raw data address of the buffer as an integer value
/// (oidnGetBufferData); evidence only -- XIOM never dereferences it.
/// Complexity: O(1).
pub fn oidn_get_buffer_data_addr(device: Int, buffer: Int) -> Result[Int, OidnError]
  requires: device != 0
  requires: buffer != 0
{
  var slot = xo_slot(8);
  let rc = unsafe { xo_oidn_buffer_data_addr(device, buffer, slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_u64(&slot, 0));
}

/// Copy a range of the buffer into an XIOM-owned slot (oidnReadBuffer).
/// Complexity: O(size).
pub fn oidn_read_buffer(device: Int, buffer: Int, offset: Int, size: Int, dst: &mut Vec[UInt8]) -> Result[Unit, OidnError]
  requires: device != 0
  requires: buffer != 0
  requires: offset >= 0
  requires: size > 0
  requires: dst.len() >= size
{
  let rc = unsafe { xo_oidn_buffer_read(device, buffer, offset, size, dst.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Asynchronous copy of a buffer range into an owned slot
/// (oidnReadBufferAsync); complete with oidn_sync_device.
/// Complexity: O(size).
pub fn oidn_read_buffer_async(device: Int, buffer: Int, offset: Int, size: Int, dst: &mut Vec[UInt8]) -> Result[Unit, OidnError]
  requires: device != 0
  requires: buffer != 0
  requires: offset >= 0
  requires: size > 0
  requires: dst.len() >= size
{
  let rc = unsafe { xo_oidn_buffer_read_async(device, buffer, offset, size, dst.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Copy XIOM-owned bytes into a buffer range (oidnWriteBuffer).
/// Complexity: O(size).
pub fn oidn_write_buffer(device: Int, buffer: Int, offset: Int, size: Int, src: &Vec[UInt8]) -> Result[Unit, OidnError]
  requires: device != 0
  requires: buffer != 0
  requires: offset >= 0
  requires: size > 0
  requires: src.len() >= size
{
  let rc = unsafe { xo_oidn_buffer_write(device, buffer, offset, size, src.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Asynchronous copy of owned bytes into a buffer range
/// (oidnWriteBufferAsync); complete with oidn_sync_device.
/// Complexity: O(size).
pub fn oidn_write_buffer_async(device: Int, buffer: Int, offset: Int, size: Int, src: &Vec[UInt8]) -> Result[Unit, OidnError]
  requires: device != 0
  requires: buffer != 0
  requires: offset >= 0
  requires: size > 0
  requires: src.len() >= size
{
  let rc = unsafe { xo_oidn_buffer_write_async(device, buffer, offset, size, src.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

// =========================================================================
// Semaphores (6 functions)
// =========================================================================

/// Import an external POSIX-fd semaphore (oidnNewSharedSemaphoreFromFD);
/// the CPU device rejects external semaphores with a typed error.
/// Complexity: O(import).
pub fn oidn_new_shared_semaphore_from_fd(device: Int, flags: Int, fd: Int) -> Result[Int, OidnError]
  requires: device != 0
{
  let h = unsafe { xo_oidn_semaphore_new_shared_fd(device, flags as Int32, fd as Int32) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Import an external Win32-handle semaphore
/// (oidnNewSharedSemaphoreFromWin32Handle); handle/name cross as integers.
/// Complexity: O(import).
pub fn oidn_new_shared_semaphore_from_win32_handle(device: Int, flags: Int, handle: Int, name: Int) -> Result[Int, OidnError]
  requires: device != 0
{
  let h = unsafe { xo_oidn_semaphore_new_shared_win32(device, flags as Int32, handle, name) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Signal semaphores asynchronously (oidnSignalSemaphoresAsync). Handles
/// (u64 each) and values (u64 each) travel in owned slots; a zero count is
/// a valid no-op.
/// Complexity: O(count).
pub fn oidn_signal_semaphores_async(device: Int, handles: &Vec[UInt8], values: &Vec[UInt8], count: Int) -> Result[Unit, OidnError]
  requires: device != 0
  requires: count >= 0
  requires: handles.len() >= count * 8
  requires: values.len() >= count * 8
{
  let rc = unsafe { xo_oidn_semaphore_signal(device, handles.as_mut_ptr(), values.as_mut_ptr(), count as Int32) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Wait on semaphores asynchronously (oidnWaitSemaphoresAsync). Handles,
/// values (u64) and timeouts (u32) travel in owned slots; a zero count is
/// a valid no-op.
/// Complexity: O(count).
pub fn oidn_wait_semaphores_async(device: Int, handles: &Vec[UInt8], values: &Vec[UInt8], timeouts: &Vec[UInt8], count: Int) -> Result[Unit, OidnError]
  requires: device != 0
  requires: count >= 0
  requires: handles.len() >= count * 8
  requires: values.len() >= count * 8
  requires: timeouts.len() >= count * 4
{
  let rc = unsafe { xo_oidn_semaphore_wait(device, handles.as_mut_ptr(), values.as_mut_ptr(), timeouts.as_mut_ptr(), count as Int32) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Retain the semaphore reference (oidnRetainSemaphore).
/// Complexity: O(1).
pub fn oidn_retain_semaphore(semaphore: Int) -> Result[Unit, OidnError]
  requires: semaphore != 0
{
  let rc = unsafe { xo_oidn_semaphore_retain(semaphore) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Release the semaphore reference (oidnReleaseSemaphore).
/// Complexity: O(1).
pub fn oidn_release_semaphore(semaphore: Int) -> Result[Unit, OidnError]
  requires: semaphore != 0
{
  let rc = unsafe { xo_oidn_semaphore_release(semaphore) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

// =========================================================================
// Filters (19 functions)
// =========================================================================

/// Create a filter of the given type, e.g. "RT" or "RTLightmap"
/// (oidnNewFilter).
/// Complexity: O(filter creation).
pub fn oidn_new_filter(device: Int, filter_type: Str) -> Result[Int, OidnError]
  requires: device != 0
  requires: filter_type.len() > 0
{
  let h = unsafe { xo_oidn_filter_new(device, filter_type.c_str()) };
  if h < 0 { return Err(xo_err(0 - h)); }
  if h == 0 { return Err(xo_err(OIDN_ERROR_UNKNOWN)); }
  return Ok(h);
}

/// Retain the filter reference (oidnRetainFilter).
/// Complexity: O(1).
pub fn oidn_retain_filter(filter: Int) -> Result[Unit, OidnError]
  requires: filter != 0
{
  let rc = unsafe { xo_oidn_filter_retain(filter) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Release the filter reference (oidnReleaseFilter).
/// Complexity: O(1).
pub fn oidn_release_filter(filter: Int) -> Result[Unit, OidnError]
  requires: filter != 0
{
  let rc = unsafe { xo_oidn_filter_release(filter) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Set a filter image parameter backed by an OIDN buffer
/// (oidnSetFilterImage). Strides of 0 are computed by OIDN.
/// Complexity: O(1).
pub fn oidn_set_filter_image(device: Int, filter: Int, name: Str, buffer: Int, format: Int, width: Int, height: Int, byte_offset: Int, pixel_byte_stride: Int, row_byte_stride: Int) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
  requires: buffer != 0
  requires: width > 0
  requires: height > 0
{
  let rc = unsafe { xo_oidn_filter_set_image(device, filter, name.c_str(), buffer, format as Int32, width, height, byte_offset, pixel_byte_stride, row_byte_stride) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Set a filter image parameter backed by XIOM-owned memory
/// (oidnSetSharedFilterImage); the owned Vec must outlive the filter use.
/// Complexity: O(1).
pub fn oidn_set_shared_filter_image(device: Int, filter: Int, name: Str, mem: &mut Vec[UInt8], format: Int, width: Int, height: Int, byte_offset: Int, pixel_byte_stride: Int, row_byte_stride: Int) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
  requires: mem.len() > 0
  requires: width > 0
  requires: height > 0
{
  let rc = unsafe { xo_oidn_filter_set_shared_image(device, filter, name.c_str(), mem.as_mut_ptr(), format as Int32, width, height, byte_offset, pixel_byte_stride, row_byte_stride) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Unset a filter image parameter (oidnUnsetFilterImage).
/// Complexity: O(1).
pub fn oidn_unset_filter_image(device: Int, filter: Int, name: Str) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
{
  let rc = unsafe { xo_oidn_filter_unset_image(device, filter, name.c_str()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Set an opaque data parameter over XIOM-owned memory
/// (oidnSetSharedFilterData).
/// Complexity: O(1).
pub fn oidn_set_shared_filter_data(device: Int, filter: Int, name: Str, mem: &mut Vec[UInt8]) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
  requires: mem.len() > 0
{
  let rc = unsafe { xo_oidn_filter_set_data(device, filter, name.c_str(), mem.as_mut_ptr(), mem.len()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Mark an opaque data parameter as changed (oidnUpdateFilterData).
/// Complexity: O(1).
pub fn oidn_update_filter_data(device: Int, filter: Int, name: Str) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
{
  let rc = unsafe { xo_oidn_filter_update_data(device, filter, name.c_str()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Unset an opaque data parameter (oidnUnsetFilterData).
/// Complexity: O(1).
pub fn oidn_unset_filter_data(device: Int, filter: Int, name: Str) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
{
  let rc = unsafe { xo_oidn_filter_unset_data(device, filter, name.c_str()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Set a boolean filter parameter (oidnSetFilterBool).
/// Complexity: O(len(name)).
pub fn oidn_set_filter_bool(device: Int, filter: Int, name: Str, value: Bool) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
{
  var v: Int32 = 0 as Int32;
  if value { v = 1 as Int32; }
  let rc = unsafe { xo_oidn_filter_set_bool(device, filter, name.c_str(), v) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Boolean filter parameter (oidnGetFilterBool).
/// Complexity: O(len(name)).
pub fn oidn_get_filter_bool(device: Int, filter: Int, name: Str) -> Result[Bool, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
{
  var slot = xo_slot(1);
  let rc = unsafe { xo_oidn_filter_get_bool(device, filter, name.c_str(), slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_u8(&slot, 0) != 0);
}

/// Set an integer filter parameter (oidnSetFilterInt).
/// Complexity: O(len(name)).
pub fn oidn_set_filter_int(device: Int, filter: Int, name: Str, value: Int) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
{
  let rc = unsafe { xo_oidn_filter_set_int(device, filter, name.c_str(), value as Int32) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Integer filter parameter (oidnGetFilterInt).
/// Complexity: O(len(name)).
pub fn oidn_get_filter_int(device: Int, filter: Int, name: Str) -> Result[Int, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
{
  var slot = xo_slot(4);
  let rc = unsafe { xo_oidn_filter_get_int(device, filter, name.c_str(), slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_i32(&slot, 0));
}

/// Set a float filter parameter (oidnSetFilterFloat).
/// Complexity: O(len(name)).
pub fn oidn_set_filter_float(device: Int, filter: Int, name: Str, value: Float32) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
{
  let rc = unsafe { xo_oidn_filter_set_float(device, filter, name.c_str(), value) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Float filter parameter as raw little-endian f32 bytes in an owned slot
/// (oidnGetFilterFloat); decode with the caller's float view.
/// Complexity: O(len(name)).
pub fn oidn_get_filter_float_bytes(device: Int, filter: Int, name: Str, out4: &mut Vec[UInt8]) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
  requires: name.len() > 0
  requires: out4.len() >= 4
{
  let rc = unsafe { xo_oidn_filter_get_float(device, filter, name.c_str(), out4.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Install (enable=true) or remove the bridge-owned progress monitor
/// through oidnSetFilterProgressMonitorFunction; hits are counted by the
/// bridge.
/// Complexity: O(1).
pub fn oidn_set_filter_progress_monitor(device: Int, filter: Int, enable: Bool) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
{
  var v: Int32 = 0 as Int32;
  if enable { v = 1 as Int32; }
  let rc = unsafe { xo_oidn_filter_set_progress_monitor(device, filter, v) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Number of progress-monitor invocations since load (or last reset).
/// Complexity: O(1).
pub fn oidn_filter_progress_hits() -> Int
  requires: true
{
  var slot = xo_slot(4);
  unsafe { xo_oidn_filter_progress_hits(slot.as_mut_ptr()); }
  return xo_rd_i32(&slot, 0);
}

/// Reset the progress-monitor hit counter.
/// Complexity: O(1).
pub fn oidn_filter_progress_reset()
  requires: true
{
  unsafe { xo_oidn_filter_progress_reset(); }
}

/// Commit all pending filter changes (oidnCommitFilter).
/// Complexity: O(commit).
pub fn oidn_commit_filter(device: Int, filter: Int) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
{
  let rc = unsafe { xo_oidn_filter_commit(device, filter) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Execute the filter synchronously (oidnExecuteFilter).
/// Complexity: O(filter work).
pub fn oidn_execute_filter(device: Int, filter: Int) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
{
  let rc = unsafe { xo_oidn_filter_execute(device, filter) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

/// Execute the filter asynchronously (oidnExecuteFilterAsync); complete
/// with oidn_sync_device.
/// Complexity: O(submit).
pub fn oidn_execute_filter_async(device: Int, filter: Int) -> Result[Unit, OidnError]
  requires: device != 0
  requires: filter != 0
{
  let rc = unsafe { xo_oidn_filter_execute_async(device, filter) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(());
}

// =========================================================================
// Analysis helpers over owned buffers (test support; C reads XIOM-owned
// bytes and writes XIOM-owned slots -- the B-20-safe direction)
// =========================================================================

/// Summarize a float32 output slot against its input slot: finite/changed
/// counts plus min/max/mean in milli units. `eps_milli <= 0` means 1e-6.
/// Complexity: O(float_count).
pub fn oidn_f32_analyze(input: &Vec[UInt8], output: &Vec[UInt8], float_count: Int, eps_milli: Int) -> Result[OidnF32Stats, OidnError]
  requires: output.len() >= float_count * 4
  requires: input.len() >= float_count * 4
{
  var slots = xo_slot(20);
  let rc = unsafe { xo_oidn_f32_analyze(input.as_mut_ptr(), output.as_mut_ptr(), float_count as Int32, eps_milli as Int32, slots.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(OidnF32Stats{
    finite: xo_rd_i32(&slots, 0);
    changed: xo_rd_i32(&slots, 4);
    min_milli: xo_rd_i32(&slots, 8);
    max_milli: xo_rd_i32(&slots, 12);
    mean_milli: xo_rd_i32(&slots, 16);
  });
}

/// Count differing bytes between two owned slots.
/// Complexity: O(byte_count).
pub fn oidn_byte_diff(a: &Vec[UInt8], b: &Vec[UInt8], byte_count: Int) -> Result[Int, OidnError]
  requires: a.len() >= byte_count
  requires: b.len() >= byte_count
{
  var slot = xo_slot(4);
  let rc = unsafe { xo_oidn_byte_diff(a.as_mut_ptr(), b.as_mut_ptr(), byte_count as Int32, slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_i32(&slot, 0));
}

/// Bit-exact equality of two owned slots.
/// Complexity: O(byte_count).
pub fn oidn_byte_equal(a: &Vec[UInt8], b: &Vec[UInt8], byte_count: Int) -> Result[Bool, OidnError]
  requires: a.len() >= byte_count
  requires: b.len() >= byte_count
{
  var slot = xo_slot(1);
  let rc = unsafe { xo_oidn_byte_equal(a.as_mut_ptr(), b.as_mut_ptr(), byte_count as Int32, slot.as_mut_ptr()) as Int };
  if rc != 0 { return Err(xo_err(rc)); }
  return Ok(xo_rd_u8(&slot, 0) != 0);
}
