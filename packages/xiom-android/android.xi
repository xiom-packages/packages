// XIOM -- xiom.android: Android platform-core bindings (NDK r27b).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime probe + functional head for the A1 window-core slice
// of the Android SDK100 program (docs/ANDROID-SDK100.md), backed by the
// small vendored bridge `src/android_bridge.c` (compiled with
// `--c-source`; see port.args.json).  The bridge resolves the platform
// libraries at RUNTIME (dlopen on Android/Linux, LoadLibraryA on
// Windows -- where everything classifies ABSENT) and verifies the
// declared export set of native_window.h + hardware_buffer.h:
//
//   ANativeWindow_*   (15 non-inline exports; window ops need a live
//                      Surface -> A11 seam; bound + ABI-checked here)
//   AHardwareBuffer_* (12 exports; allocate/describe/lock/write/read/
//                      release exercised functionally by the suite)
//
// Classification (the suite maps it to markers):
//   ANDROID_LOAD_ABSENT -> SKIP  (runtime missing; CI stays green)
//   ANDROID_LOAD_ABI    -> FAIL  (present but exports broken; never
//                                 a silent SKIP)
//
// Pointers never cross the boundary (B-25 discipline): the bridge keeps
// the locked buffer address on the C side; pixels are read/written by
// value.  Handles cross as Int.
//
// Naming note: this package is the proposed `xiom.android` home of the
// platform-core slices (A1/A2/A5); the name is rename-safe pending the
// compiler reply to REL-20261015-1109-bindings.

module xiom.android

extern "C" {
  fn xa_load_named(android_soname: *UInt8, nativewindow_soname: *UInt8) -> Int32;
  fn xa_load() -> Int32;
  fn xa_error() -> *UInt8;
  fn xa_abi_missing_count() -> Int32;
  fn xa_abi_missing() -> *UInt8;
  fn xa_hwb_is_supported(width: Int32, height: Int32, format: Int32, usage: Int64) -> Int32;
  fn xa_hwb_alloc(width: Int32, height: Int32, format: Int32, usage: Int64) -> Int64;
  fn xa_hwb_width(handle: Int64) -> Int32;
  fn xa_hwb_height(handle: Int64) -> Int32;
  fn xa_hwb_format(handle: Int64) -> Int32;
  fn xa_hwb_stride(handle: Int64) -> Int32;
  fn xa_hwb_layers(handle: Int64) -> Int32;
  fn xa_hwb_write_pixel(handle: Int64, x: Int32, y: Int32, rgba: Int32) -> Int32;
  fn xa_hwb_read_pixel(handle: Int64, x: Int32, y: Int32) -> Int64;
  fn xa_hwb_acquire(handle: Int64);
  fn xa_hwb_release(handle: Int64);
  fn xa_shm_create(name: *UInt8, size: Int64) -> Int64;
  fn xa_shm_get_size(fd: Int64) -> Int64;
  fn xa_shm_set_prot(fd: Int64, prot: Int32) -> Int32;
  fn xa_shm_write_probe(fd: Int64, value: Int32) -> Int32;
  fn xa_shm_read_probe(fd: Int64) -> Int64;
  fn xa_fd_close(fd: Int64) -> Int32;
  fn xa_unload();
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const ANDROID_SONAME: Str = "libandroid.so";
pub const NATIVEWINDOW_SONAME: Str = "libnativewindow.so";

// Probe outcome kinds.
pub const ANDROID_LOAD_ABSENT: Int = 0; // runtime libs missing -> SKIP
pub const ANDROID_LOAD_ABI: Int = 1;    // present but exports broken -> FAIL

pub type AndroidProbeError = {
  kind: Int;
  message: Str;
}

pub type AndroidRuntime = {
  missing_exports: Int;
  missing: Str;
}

// =========================================================================
// Window formats (ANativeWindow_LegacyFormat, native_window.h)
// =========================================================================

pub const WINDOW_FORMAT_RGBA_8888: Int = 1; // = AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM
pub const WINDOW_FORMAT_RGBX_8888: Int = 2; // = AHARDWAREBUFFER_FORMAT_R8G8B8X8_UNORM
pub const WINDOW_FORMAT_RGB_565: Int = 4;   // = AHARDWAREBUFFER_FORMAT_R5G6B5_UNORM

// ANativeWindow_Transform (native_window.h)
pub const ANATIVEWINDOW_TRANSFORM_IDENTITY: Int = 0x00;
pub const ANATIVEWINDOW_TRANSFORM_MIRROR_HORIZONTAL: Int = 0x01;
pub const ANATIVEWINDOW_TRANSFORM_MIRROR_VERTICAL: Int = 0x02;
pub const ANATIVEWINDOW_TRANSFORM_ROTATE_90: Int = 0x04;
pub const ANATIVEWINDOW_TRANSFORM_ROTATE_180: Int = 0x03;
pub const ANATIVEWINDOW_TRANSFORM_ROTATE_270: Int = 0x07;

// Frame-rate compatibility / change strategies (native_window.h)
pub const ANATIVEWINDOW_FRAME_RATE_COMPATIBILITY_DEFAULT: Int = 0;
pub const ANATIVEWINDOW_FRAME_RATE_COMPATIBILITY_FIXED_SOURCE: Int = 1;
pub const ANATIVEWINDOW_CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS: Int = 0;
pub const ANATIVEWINDOW_CHANGE_FRAME_RATE_ALWAYS: Int = 1;

// =========================================================================
// AHardwareBuffer formats (hardware_buffer.h)
// =========================================================================

pub const AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM: Int = 1;
pub const AHARDWAREBUFFER_FORMAT_R8G8B8X8_UNORM: Int = 2;
pub const AHARDWAREBUFFER_FORMAT_R8G8B8_UNORM: Int = 3;
pub const AHARDWAREBUFFER_FORMAT_R5G6B5_UNORM: Int = 4;
pub const AHARDWAREBUFFER_FORMAT_R16G16B16A16_FLOAT: Int = 0x16;
pub const AHARDWAREBUFFER_FORMAT_R10G10B10A2_UNORM: Int = 0x2b;
pub const AHARDWAREBUFFER_FORMAT_BLOB: Int = 0x21;
pub const AHARDWAREBUFFER_FORMAT_D16_UNORM: Int = 0x30;
pub const AHARDWAREBUFFER_FORMAT_D24_UNORM: Int = 0x31;
pub const AHARDWAREBUFFER_FORMAT_D24_UNORM_S8_UINT: Int = 0x32;
pub const AHARDWAREBUFFER_FORMAT_D32_FLOAT: Int = 0x33;
pub const AHARDWAREBUFFER_FORMAT_D32_FLOAT_S8_UINT: Int = 0x34;
pub const AHARDWAREBUFFER_FORMAT_S8_UINT: Int = 0x35;
pub const AHARDWAREBUFFER_FORMAT_Y8Cb8Cr8_420: Int = 0x23;
pub const AHARDWAREBUFFER_FORMAT_YCbCr_P010: Int = 0x36;
pub const AHARDWAREBUFFER_FORMAT_R8_UNORM: Int = 0x38;
pub const AHARDWAREBUFFER_FORMAT_R16_UINT: Int = 0x39;
pub const AHARDWAREBUFFER_FORMAT_R16G16_UINT: Int = 0x3a;
pub const AHARDWAREBUFFER_FORMAT_R10G10B10A10_UNORM: Int = 0x3b;

// =========================================================================
// AHardwareBuffer usage flags (hardware_buffer.h)
// =========================================================================

pub const AHARDWAREBUFFER_USAGE_CPU_READ_NEVER: Int = 0;
pub const AHARDWAREBUFFER_USAGE_CPU_READ_RARELY: Int = 2;
pub const AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN: Int = 3;
pub const AHARDWAREBUFFER_USAGE_CPU_READ_MASK: Int = 0xF;
pub const AHARDWAREBUFFER_USAGE_CPU_WRITE_NEVER: Int = 0;
pub const AHARDWAREBUFFER_USAGE_CPU_WRITE_RARELY: Int = 0x20;
pub const AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN: Int = 0x30;
pub const AHARDWAREBUFFER_USAGE_CPU_WRITE_MASK: Int = 0xF0;
pub const AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE: Int = 0x100;
pub const AHARDWAREBUFFER_USAGE_GPU_FRAMEBUFFER: Int = 0x200;
pub const AHARDWAREBUFFER_USAGE_GPU_COLOR_OUTPUT: Int = 0x200;
pub const AHARDWAREBUFFER_USAGE_COMPOSER_OVERLAY: Int = 0x800;
pub const AHARDWAREBUFFER_USAGE_PROTECTED_CONTENT: Int = 0x4000;
pub const AHARDWAREBUFFER_USAGE_VIDEO_ENCODE: Int = 0x10000;
pub const AHARDWAREBUFFER_USAGE_SENSOR_DIRECT_DATA: Int = 0x800000;
pub const AHARDWAREBUFFER_USAGE_GPU_DATA_BUFFER: Int = 0x1000000;
pub const AHARDWAREBUFFER_USAGE_GPU_CUBE_MAP: Int = 0x2000000;
pub const AHARDWAREBUFFER_USAGE_GPU_MIPMAP_COMPLETE: Int = 0x4000000;
pub const AHARDWAREBUFFER_USAGE_VENDOR_0: Int = 0x10000000;
pub const AHARDWAREBUFFER_USAGE_FRONT_BUFFER: Int = 0x100000000;

// =========================================================================
// A5 assets-storage head (W2b): asset modes + shared-memory protection
// =========================================================================

// AAssetManager open modes (asset_manager.h)
pub const AASSET_MODE_UNKNOWN: Int = 0;
pub const AASSET_MODE_RANDOM: Int = 1;
pub const AASSET_MODE_STREAMING: Int = 2;
pub const AASSET_MODE_BUFFER: Int = 3;

// ASharedMemory_setProt flags (POSIX PROT_*)
pub const PROT_NONE: Int = 0;
pub const PROT_READ: Int = 1;
pub const PROT_WRITE: Int = 2;
pub const PROT_EXEC: Int = 4;

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named platform library pair.  Useful for tests: a
/// bogus pair exercises the ABSENT/SKIP classification deterministically
/// even on hosts that ship the libraries.
/// Complexity: O(load + export set).
pub fn android_probe_named(android_soname: Str, nativewindow_soname: Str) -> Result[AndroidRuntime, AndroidProbeError]
  requires: android_soname.len() > 0
  requires: nativewindow_soname.len() > 0
{
  let rc = unsafe { xa_load_named(android_soname.c_str(), nativewindow_soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xa_error()) };
    if rc == 1 {
      return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABSENT; message: msg });
    }
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: msg });
  }
  let missing_count = unsafe { xa_abi_missing_count() as Int };
  let missing = unsafe { Str::from_c_str(xa_abi_missing()) };
  return Ok(AndroidRuntime{ missing_exports: missing_count, missing: missing });
}

/// Probe the default runtime (libandroid.so + libnativewindow.so).  On
/// Android this is the platform itself; on Windows the probe classifies
/// ABSENT (SKIP).
/// Complexity: O(load + export set).
pub fn android_probe() -> Result[AndroidRuntime, AndroidProbeError]
  requires: true
{
  return android_probe_named(ANDROID_SONAME, NATIVEWINDOW_SONAME);
}

/// The last bridge error / missing-export summary (empty when clean).
/// Complexity: O(1).
pub fn android_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xa_error()); }
}

/// Release any runtime handles held by the bridge.  Safe when nothing is
/// loaded.
/// Complexity: O(1).
pub fn android_unload()
  requires: true
{
  unsafe { xa_unload(); }
}

// =========================================================================
// AHardwareBuffer functional head
// =========================================================================

pub type HwbBuffer = {
  handle: Int;
}

/// True when a buffer of this shape/usage is allocatable on this device.
/// Complexity: O(1).
pub fn hwb_is_supported(width: Int, height: Int, format: Int, usage: Int) -> Bool
  requires: width > 0
  requires: height > 0
{
  let rc = unsafe { xa_hwb_is_supported(width as Int32, height as Int32, format as Int32, usage as Int64) as Int };
  return rc == 1;
}

/// Allocate an AHardwareBuffer (single layer).  Usage must include the
/// CPU access bits the caller intends (see the usage constants).
/// Complexity: O(allocation).
pub fn hwb_alloc(width: Int, height: Int, format: Int, usage: Int) -> Result[HwbBuffer, AndroidProbeError]
  requires: width > 0
  requires: height > 0
{
  let h = unsafe { xa_hwb_alloc(width as Int32, height as Int32, format as Int32, usage as Int64) as Int };
  if h == 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: android_error() });
  }
  return Ok(HwbBuffer{ handle: h });
}

/// Described width in pixels (0 when the buffer is released).
/// Complexity: O(1).
pub fn hwb_width(buf: &HwbBuffer) -> Int
  requires: true
{
  unsafe { return xa_hwb_width(buf.handle as Int64) as Int; }
}

/// Described height in pixels.
/// Complexity: O(1).
pub fn hwb_height(buf: &HwbBuffer) -> Int
  requires: true
{
  unsafe { return xa_hwb_height(buf.handle as Int64) as Int; }
}

/// Described format (AHARDWAREBUFFER_FORMAT_*).
/// Complexity: O(1).
pub fn hwb_format(buf: &HwbBuffer) -> Int
  requires: true
{
  unsafe { return xa_hwb_format(buf.handle as Int64) as Int; }
}

/// Described row stride in pixels.
/// Complexity: O(1).
pub fn hwb_stride(buf: &HwbBuffer) -> Int
  requires: true
{
  unsafe { return xa_hwb_stride(buf.handle as Int64) as Int; }
}

/// Described layer count.
/// Complexity: O(1).
pub fn hwb_layers(buf: &HwbBuffer) -> Int
  requires: true
{
  unsafe { return xa_hwb_layers(buf.handle as Int64) as Int; }
}

/// Write one 32-bit pixel value (RGBA8 byte order) at (x, y).  The lock
/// window lives entirely inside the bridge; no pointer crosses the
/// boundary.
/// Complexity: O(lock + store + unlock).
pub fn hwb_write_pixel(buf: &HwbBuffer, x: Int, y: Int, rgba: Int) -> Bool
  requires: true
{
  let rc = unsafe { xa_hwb_write_pixel(buf.handle as Int64, x as Int32, y as Int32, rgba as Int32) as Int };
  return rc == 0;
}

/// Read one 32-bit pixel value (RGBA8 byte order) at (x, y).  Negative
/// values are errors (see android_error).
/// Complexity: O(lock + load + unlock).
pub fn hwb_read_pixel(buf: &HwbBuffer, x: Int, y: Int) -> Int
  requires: true
{
  unsafe { return xa_hwb_read_pixel(buf.handle as Int64, x as Int32, y as Int32) as Int; }
}

/// Add one reference to the buffer.
/// Complexity: O(1).
pub fn hwb_acquire(buf: HwbBuffer)
  requires: true
{
  unsafe { xa_hwb_acquire(buf.handle as Int64); }
}

/// Drop one reference to the buffer (the allocator's reference included).
/// Complexity: O(1).
pub fn hwb_release(buf: HwbBuffer)
  requires: true
{
  unsafe { xa_hwb_release(buf.handle as Int64); }
}

// =========================================================================
// ASharedMemory functional head (W2b; POSIX/Android memfd-backed)
//
// The AAsset_* / AAssetManager_* / AStorageManager_* surfaces are
// declared + ABI-checked in the bridge export set (27 -> 53 symbols);
// live wrappers need an app context (A11 JNI seam) and join then.
// =========================================================================

pub type ShmRegion = {
  fd: Int;
}

/// Create a shared memory region (ASharedMemory_create; memfd-backed on
/// Android).  Close with `shm_close`.
/// Complexity: O(1).
pub fn shm_create(name: Str, size: Int) -> Result[ShmRegion, AndroidProbeError]
  requires: size > 0
{
  let fd = unsafe { xa_shm_create(name.c_str(), size as Int64) as Int };
  if fd < 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: android_error() });
  }
  return Ok(ShmRegion{ fd: fd });
}

/// Size of the region in bytes (-1 on error).
/// Complexity: O(1).
pub fn shm_get_size(region: &ShmRegion) -> Int
  requires: true
{
  unsafe { return xa_shm_get_size(region.fd as Int64) as Int; }
}

/// Restrict/extend fd protections (ASharedMemory_setProt; POSIX PROT_*).
/// Complexity: O(1).
pub fn shm_set_prot(region: &ShmRegion, prot: Int) -> Bool
  requires: true
{
  let rc = unsafe { xa_shm_set_prot(region.fd as Int64, prot as Int32) as Int };
  return rc == 0;
}

/// Write a 32-bit probe value at offset 0 through a MAP_SHARED RW mapping
/// (the bridge keeps the mapping local).
/// Complexity: O(map + msync + unmap).
pub fn shm_write_probe(region: &ShmRegion, value: Int) -> Bool
  requires: true
{
  let rc = unsafe { xa_shm_write_probe(region.fd as Int64, value as Int32) as Int };
  return rc == 0;
}

/// Read the 32-bit probe value at offset 0 through a MAP_SHARED READ
/// mapping; negative values are errors (see android_error).
/// Complexity: O(map + load + unmap).
pub fn shm_read_probe(region: &ShmRegion) -> Int
  requires: true
{
  unsafe { return xa_shm_read_probe(region.fd as Int64) as Int; }
}

/// Close the region's file descriptor.
/// Complexity: O(1).
pub fn shm_close(region: ShmRegion) -> Bool
  requires: true
{
  let rc = unsafe { xa_fd_close(region.fd as Int64) as Int };
  return rc == 0;
}
