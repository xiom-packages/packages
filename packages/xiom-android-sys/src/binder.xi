// XIOM -- xiom.android-sys: libbinder_ndk head (A12 binder surface).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime-load unit for the NDK binder C API
// (android/binder_ibinder.h of NDK r27b -> libbinder_ndk.so), backed by
// the self-contained bridge `src/binder_bridge.c` (compiled with
// `--c-source`).  Handles cross as Int (AIBinder* / AIBinder_Class* are
// opaque Int handles; pointers never cross -- B-series discipline).
//
//   core (API 29, ABI-gated, 12 symbols)
//     AIBinder_Class_define, AIBinder_new, AIBinder_incStrong,
//     AIBinder_decStrong, AIBinder_associateClass, AIBinder_isAlive,
//     AIBinder_isRemote, AIBinder_ping, AIBinder_getClass,
//     AIBinder_debugGetRefCount, AIBinder_getCallingUid,
//     AIBinder_getCallingPid
//   ext (API 31/33, resolved + reported, not gated, 3 symbols)
//     AIBinder_Class_getDescriptor, AIBinder_Class_setOnDump,
//     AIBinder_Class_disableInterfaceTokenHeader
//
// Classification (the suite maps it to markers):
//   BINDER_LOAD_ABSENT -> SKIP  (runtime missing; CI stays green)
//   BINDER_LOAD_ABI    -> FAIL  (present but core exports broken;
//                                never a silent SKIP)
//
// The interface descriptor is read through the class
// (AIBinder_Class_getDescriptor; the NDK has no
// AIBinder_getInterfaceDescriptor).  The descriptor symbol is API 31+
// (extension set): on older devices the module falls back to the cached
// definition descriptor and reports the ext gap.  Class objects have no
// public delete in the NDK; the bridge caches the defined class for the
// process lifetime (documented usage pattern).

module xiom.android_sys.binder

use xiom.android_sys;

extern "C" {
  fn xbn_load_named(soname: *UInt8) -> Int32;
  fn xbn_load() -> Int32;
  fn xbn_error() -> *UInt8;
  fn xbn_core_missing_count() -> Int32;
  fn xbn_core_missing() -> *UInt8;
  fn xbn_ext_count() -> Int32;
  fn xbn_ext_missing_count() -> Int32;
  fn xbn_ext_missing() -> *UInt8;
  fn xbn_class_define(descriptor: *UInt8) -> Int64;
  fn xbn_class_descriptor(clazz: Int64) -> *UInt8;
  fn xbn_create(clazz: Int64, arg: Int64) -> Int64;
  fn xbn_inc_strong(binder: Int64);
  fn xbn_dec_strong(binder: Int64);
  fn xbn_associate_class(binder: Int64, clazz: Int64) -> Int32;
  fn xbn_is_alive(binder: Int64) -> Int32;
  fn xbn_is_remote(binder: Int64) -> Int32;
  fn xbn_ping(binder: Int64) -> Int32;
  fn xbn_get_class(binder: Int64) -> Int64;
  fn xbn_debug_ref_count(binder: Int64) -> Int32;
  fn xbn_calling_uid() -> Int64;
  fn xbn_calling_pid() -> Int64;
  fn xbn_destroy_count() -> Int32;
  fn xbn_transact_count() -> Int32;
  fn xbn_status_name(status: Int32) -> *UInt8;
  fn xbn_unload();
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const BINDER_SONAME: Str = "libbinder_ndk.so";

pub const BINDER_LOAD_ABSENT: Int = 0; // runtime lib missing -> SKIP
pub const BINDER_LOAD_ABI: Int = 1;    // present but core exports broken -> FAIL
pub const BINDER_CALL: Int = 2;        // live call failed

/// Separates the bridge's "symbol unresolved" sentinel from real
/// binder_status_t values (-2 is a valid status, NAME_NOT_FOUND).
const BINDER_PING_UNRESOLVED: Int = -1024;

pub type BinderRuntime = {
  core_missing: Int;       // API-29 core unresolved count; 0 = full cover
  core_missing_names: Str;
  ext_total: Int;          // API-31/33 extension set size (3 at r27b)
  ext_missing: Int;        // unresolved extension count (informational)
  ext_missing_names: Str;
}

// =========================================================================
// binder_status_t (android/binder_status.h, r27b)
// =========================================================================

pub const BINDER_STATUS_OK: Int = 0;
pub const BINDER_STATUS_UNKNOWN_ERROR: Int = -2147483648;
pub const BINDER_STATUS_NO_MEMORY: Int = -12;           // -ENOMEM
pub const BINDER_STATUS_INVALID_OPERATION: Int = -38;   // -ENOSYS
pub const BINDER_STATUS_BAD_VALUE: Int = -22;           // -EINVAL
pub const BINDER_STATUS_BAD_TYPE: Int = -2147483647;
pub const BINDER_STATUS_NAME_NOT_FOUND: Int = -2;       // -ENOENT
pub const BINDER_STATUS_PERMISSION_DENIED: Int = -1;    // -EPERM
pub const BINDER_STATUS_NO_INIT: Int = -19;             // -ENODEV
pub const BINDER_STATUS_ALREADY_EXISTS: Int = -17;      // -EEXIST
pub const BINDER_STATUS_DEAD_OBJECT: Int = -32;         // -EPIPE
pub const BINDER_STATUS_FAILED_TRANSACTION: Int = -2147483646;
pub const BINDER_STATUS_BAD_INDEX: Int = -75;           // -EOVERFLOW
pub const BINDER_STATUS_NOT_ENOUGH_DATA: Int = -61;     // -ENODATA
pub const BINDER_STATUS_WOULD_BLOCK: Int = -11;         // -EWOULDBLOCK
pub const BINDER_STATUS_TIMED_OUT: Int = -110;          // -ETIMEDOUT
pub const BINDER_STATUS_UNKNOWN_TRANSACTION: Int = -74; // -EBADMSG
pub const BINDER_STATUS_FDS_NOT_ALLOWED: Int = -2147483641;
pub const BINDER_STATUS_UNEXPECTED_NULL: Int = -2147483640;

/// Human name of a binder_status_t value (e.g. "OK"; "UNRECOGNIZED(n)"
/// for values outside the r27b enum).  Complexity: O(1).
pub fn binder_status_name(status: Int) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xbn_status_name(status as Int32)); }
}

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named binder runtime.  Useful for tests: a bogus
/// name exercises the ABSENT/SKIP classification deterministically even
/// on hosts that ship the library.
/// Complexity: O(load + export set).
pub fn binder_probe_named(soname: Str) -> Result[BinderRuntime, AndroidSysError]
  requires: soname.len() > 0
{
  let rc = unsafe { xbn_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xbn_error()) };
    if rc == 1 {
      return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABSENT, errno_code: 0, message: msg });
    }
    return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABI, errno_code: 0, message: msg });
  }
  let core_missing = unsafe { xbn_core_missing_count() as Int };
  let core_names = unsafe { Str::from_c_str(xbn_core_missing()) };
  let ext_total = unsafe { xbn_ext_count() as Int };
  let ext_missing = unsafe { xbn_ext_missing_count() as Int };
  let ext_names = unsafe { Str::from_c_str(xbn_ext_missing()) };
  return Ok(BinderRuntime{
    core_missing: core_missing,
    core_missing_names: core_names,
    ext_total: ext_total,
    ext_missing: ext_missing,
    ext_missing_names: ext_names,
  });
}

/// Probe the default runtime (libbinder_ndk.so).  On Windows the probe
/// classifies ABSENT (SKIP).
/// Complexity: O(load + export set).
pub fn binder_probe() -> Result[BinderRuntime, AndroidSysError]
  requires: true
{
  return binder_probe_named(BINDER_SONAME);
}

/// The last bridge error / missing-export summary (empty when clean).
/// Complexity: O(1).
pub fn binder_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xbn_error()); }
}

/// Release any runtime handles held by the bridge.  Safe when nothing is
/// loaded.  The defined class object (if any) is process-lifetime (the
/// NDK has no public class delete).
/// Complexity: O(1).
pub fn binder_unload()
  requires: true
{
  unsafe { xbn_unload(); }
}

// =========================================================================
// Functional head (class + instance lifecycle)
// =========================================================================

/// Define (or return the cached) local AIBinder class with `descriptor`
/// (AIBinder_Class_define).  The bridge installs onCreate/onDestroy/
/// onTransact callbacks; onTransact currently replies
/// BINDER_STATUS_UNKNOWN_TRANSACTION (no transact surface in this wave).
/// The class handle is an opaque Int.
/// Complexity: O(1) after the first define.
pub fn binder_class_define(descriptor: Str) -> Result[Int, AndroidSysError]
  requires: descriptor.len() > 0
{
  let h = unsafe { xbn_class_define(descriptor.c_str()) as Int };
  if h == 0 {
    return Err(AndroidSysError{ kind: BINDER_CALL, errno_code: 0, message: binder_error() });
  }
  return Ok(h);
}

/// The class interface descriptor (AIBinder_Class_getDescriptor; API 31+
/// extension symbol -- falls back to the cached definition descriptor and
/// reports the ext gap through `binder_error` when unresolvable).
/// Complexity: O(1).
pub fn binder_class_descriptor(clazz: Int) -> Str
  requires: true
{
  if clazz == 0 { return ""; }
  unsafe { return Str::from_c_str(xbn_class_descriptor(clazz as Int64)); }
}

/// Create a local binder instance of `clazz` (AIBinder_new).  `arg` is
/// handed to the class onCreate callback as an opaque Int.  The returned
/// strong reference must be released with `binder_dec_strong`.
/// Complexity: O(1).
pub fn binder_create(clazz: Int, arg: Int) -> Result[Int, AndroidSysError]
  requires: true
{
  if clazz == 0 {
    return Err(AndroidSysError{ kind: BINDER_CALL, errno_code: 0, message: "null class handle" });
  }
  let h = unsafe { xbn_create(clazz as Int64, arg as Int64) as Int };
  if h == 0 {
    return Err(AndroidSysError{ kind: BINDER_CALL, errno_code: 0, message: binder_error() });
  }
  return Ok(h);
}

/// Add a strong reference (AIBinder_incStrong).
/// Complexity: O(1).
pub fn binder_inc_strong(binder: Int)
  requires: true
{
  unsafe { xbn_inc_strong(binder as Int64); }
}

/// Drop a strong reference (AIBinder_decStrong); the instance is
/// destroyed (onDestroy invoked) when the count reaches zero.
/// Complexity: O(1).
pub fn binder_dec_strong(binder: Int)
  requires: true
{
  unsafe { xbn_dec_strong(binder as Int64); }
}

/// Associate (or re-check) the class of `binder`
/// (AIBinder_associateClass): Ok(true) when the binder has the class and
/// the association is in place.
/// Complexity: O(1).
pub fn binder_associate_class(binder: Int, clazz: Int) -> Result[Bool, AndroidSysError]
  requires: true
{
  let rc = unsafe { xbn_associate_class(binder as Int64, clazz as Int64) as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: BINDER_LOAD_ABI, errno_code: 0, message: binder_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: BINDER_CALL, errno_code: 0, message: binder_error() });
  }
  return Ok(rc == 1);
}

/// Whether the object is alive (AIBinder_isAlive).
/// Complexity: O(1).
pub fn binder_is_alive(binder: Int) -> Result[Bool, AndroidSysError]
  requires: true
{
  let rc = unsafe { xbn_is_alive(binder as Int64) as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: BINDER_LOAD_ABI, errno_code: 0, message: binder_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: BINDER_CALL, errno_code: 0, message: binder_error() });
  }
  return Ok(rc == 1);
}

/// Whether the object is a remote proxy (AIBinder_isRemote).
/// Complexity: O(1).
pub fn binder_is_remote(binder: Int) -> Result[Bool, AndroidSysError]
  requires: true
{
  let rc = unsafe { xbn_is_remote(binder as Int64) as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: BINDER_LOAD_ABI, errno_code: 0, message: binder_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: BINDER_CALL, errno_code: 0, message: binder_error() });
  }
  return Ok(rc == 1);
}

/// Ping the object (AIBinder_ping).  Ok(BINDER_STATUS_OK) for a live
/// local instance; other Ok(status) values are real binder_status_t
/// outcomes (e.g. BINDER_STATUS_DEAD_OBJECT).  Err(BINDER_LOAD_ABI) when
/// the symbol is unresolved.
/// Complexity: O(1).
pub fn binder_ping(binder: Int) -> Result[Int, AndroidSysError]
  requires: true
{
  let rc = unsafe { xbn_ping(binder as Int64) as Int };
  if rc == BINDER_PING_UNRESOLVED {
    return Err(AndroidSysError{ kind: BINDER_LOAD_ABI, errno_code: 0, message: binder_error() });
  }
  return Ok(rc);
}

/// The class of `binder` (AIBinder_getClass) as an opaque Int handle;
/// 0 when the binder has no class.  Err(BINDER_CALL) when the symbol is
/// unresolved or the handle is null.
/// Complexity: O(1).
pub fn binder_get_class(binder: Int) -> Result[Int, AndroidSysError]
  requires: true
{
  let h = unsafe { xbn_get_class(binder as Int64) as Int };
  if h == 0 {
    return Err(AndroidSysError{ kind: BINDER_CALL, errno_code: 0, message: binder_error() });
  }
  return Ok(h);
}

/// The strong reference count (AIBinder_debugGetRefCount; debug surface).
/// Complexity: O(1).
pub fn binder_debug_ref_count(binder: Int) -> Result[Int, AndroidSysError]
  requires: true
{
  let rc = unsafe { xbn_debug_ref_count(binder as Int64) as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: BINDER_LOAD_ABI, errno_code: 0, message: binder_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: BINDER_CALL, errno_code: 0, message: binder_error() });
  }
  return Ok(rc);
}

/// UID calling into the current thread (AIBinder_getCallingUid); the own
/// uid outside a transaction.  -1 when the symbol is unresolved.
/// Complexity: O(1).
pub fn binder_calling_uid() -> Int
  requires: true
{
  unsafe { return xbn_calling_uid() as Int; }
}

/// PID calling into the current thread (AIBinder_getCallingPid); the own
/// pid outside a transaction.  -1 when the symbol is unresolved.
/// Complexity: O(1).
pub fn binder_calling_pid() -> Int
  requires: true
{
  unsafe { return xbn_calling_pid() as Int; }
}

/// onDestroy callbacks observed by the bridge (destroy proof for the
/// smoke: increments when the last strong reference is dropped).
/// Complexity: O(1).
pub fn binder_destroy_count() -> Int
  requires: true
{
  unsafe { return xbn_destroy_count() as Int; }
}

/// onTransact callbacks observed by the bridge (0 in this wave: the
/// transact/parcel surface is a documented delta).
/// Complexity: O(1).
pub fn binder_transact_count() -> Int
  requires: true
{
  unsafe { return xbn_transact_count() as Int; }
}
