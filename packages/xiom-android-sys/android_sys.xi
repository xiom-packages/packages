// XIOM -- xiom.android-sys: Android system-starter bindings (NDK r27b).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime probe + functional head for the A12 system slice
// (android/log.h -> liblog.so, android/sync.h -> libsync.so) of the
// Android SDK100 program (docs/ANDROID-SDK100.md), backed by the small
// vendored bridge `src/android_sys_bridge.c` (compiled with
// `--c-source`; see port.args.json).  The bridge resolves the platform
// libraries at RUNTIME (dlopen on Android/Linux, LoadLibraryA on
// Windows -- where everything classifies ABSENT) and verifies the
// declared export sets:
//
//   core (API 26, ABI-gated, 11 symbols)
//     liblog  (8): __android_log_write/print/vprint/assert,
//                  __android_log_buf_write/print,
//                  __android_log_is_loggable(/_len)
//     libsync (3): sync_merge, sync_file_info, sync_file_info_free
//   ext (API 30+, resolved + reported, not gated, 10 symbols)
//     __android_log_write_log_message, set_logger, logd_logger,
//     stderr_logger, set_aborter, call_aborter, default_aborter,
//     set_minimum_priority, get_minimum_priority, set_default_tag
//
// Oracle note: android/sync.h (r27b) declares exactly the three libsync
// exports above; `sync_wait` and `sync_file_info_is_signaled` are NOT
// declared by the NDK headers (libsync private surface -> excluded with
// evidence in SPEC.md/PROVENANCE.md; their device presence is probed
// informationally by the repro driver).  `sync_get_fence_info` is a
// static inline helper, not an export (the raw `sync_fence_info` field
// offset is pinned in the bridge for the info accessors below).
//
// Classification (the suite maps it to markers):
//   ANDROID_SYS_LOAD_ABSENT -> SKIP  (runtime missing; CI stays green)
//   ANDROID_SYS_LOAD_ABI    -> FAIL  (present but core exports broken;
//                                     never a silent SKIP)
//
// Pointers never cross the boundary (B-25 discipline): sync_file_info
// handles stay opaque Int values; the bridge reads the struct fields on
// the C side.  Handles cross as Int.

module xiom.android_sys

extern "C" {
  fn xs_load_named(log_soname: *UInt8, sync_soname: *UInt8) -> Int32;
  fn xs_load() -> Int32;
  fn xs_error() -> *UInt8;
  fn xs_abi_missing_count() -> Int32;
  fn xs_abi_missing() -> *UInt8;
  fn xs_ext_count() -> Int32;
  fn xs_ext_missing_count() -> Int32;
  fn xs_ext_missing() -> *UInt8;
  fn xs_errno() -> Int32;
  fn xs_log_write(prio: Int32, tag: *UInt8, text: *UInt8) -> Int32;
  fn xs_log_print(prio: Int32, tag: *UInt8, text: *UInt8) -> Int32;
  fn xs_log_is_loggable(prio: Int32, tag: *UInt8, default_prio: Int32) -> Int32;
  fn xs_log_is_loggable_len(prio: Int32, tag: *UInt8, len: Int64, default_prio: Int32) -> Int32;
  fn xs_log_buf_write(buf_id: Int32, prio: Int32, tag: *UInt8, text: *UInt8) -> Int32;
  fn xs_log_minimum_priority() -> Int32;
  fn xs_sync_file_info(fd: Int32) -> Int64;
  fn xs_sync_file_info_status(handle: Int64) -> Int32;
  fn xs_sync_file_info_num_fences(handle: Int64) -> Int32;
  fn xs_sync_file_info_name(handle: Int64) -> *UInt8;
  fn xs_sync_file_info_free(handle: Int64);
  fn xs_sync_merge(name: *UInt8, fd1: Int32, fd2: Int32) -> Int32;
  fn xs_unload();
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const LOG_SONAME: Str = "liblog.so";
pub const SYNC_SONAME: Str = "libsync.so";

// Probe/classification kinds.
pub const ANDROID_SYS_LOAD_ABSENT: Int = 0; // runtime libs missing -> SKIP
pub const ANDROID_SYS_LOAD_ABI: Int = 1;    // present but core exports broken -> FAIL
pub const ANDROID_SYS_CALL: Int = 2;        // live call failed (errno family)

pub type AndroidSysError = {
  kind: Int;       // ANDROID_SYS_LOAD_ABSENT | _LOAD_ABI | _CALL
  errno_code: Int; // captured errno for _CALL sync failures; 0 otherwise
  message: Str;
}

pub type AndroidSysRuntime = {
  missing_exports: Int; // core (API 26) unresolved count; 0 = full cover
  missing: Str;         // comma-joined missing core names
  ext_total: Int;       // API-30 liblog extension set size (10 at r27b)
  ext_missing: Int;     // unresolved extension count (informational)
  ext_missing_names: Str;
}

// =========================================================================
// android_LogPriority (android/log.h)
// =========================================================================

pub const ANDROID_LOG_UNKNOWN: Int = 0;
pub const ANDROID_LOG_DEFAULT: Int = 1; // only for SetMinPriority()
pub const ANDROID_LOG_VERBOSE: Int = 2;
pub const ANDROID_LOG_DEBUG: Int = 3;
pub const ANDROID_LOG_INFO: Int = 4;
pub const ANDROID_LOG_WARN: Int = 5;
pub const ANDROID_LOG_ERROR: Int = 6;
pub const ANDROID_LOG_FATAL: Int = 7;
pub const ANDROID_LOG_SILENT: Int = 8; // must be last

// =========================================================================
// log_id (android/log.h)
// =========================================================================

pub const LOG_ID_MIN: Int = 0;
pub const LOG_ID_MAIN: Int = 0; // the only log buffer available to apps
pub const LOG_ID_RADIO: Int = 1;
pub const LOG_ID_EVENTS: Int = 2;
pub const LOG_ID_SYSTEM: Int = 3;
pub const LOG_ID_CRASH: Int = 4;
pub const LOG_ID_STATS: Int = 5;
pub const LOG_ID_SECURITY: Int = 6;
pub const LOG_ID_KERNEL: Int = 7;
pub const LOG_ID_MAX: Int = 8;
pub const LOG_ID_DEFAULT: Int = 0x7FFFFFFF;

// =========================================================================
// Sync ioctls + struct ABI (linux/sync_file.h, included by android/sync.h)
//
// The SYNC_IOC_* values are computed from the header macros with the
// asm-generic <linux/ioctl.h> encoding: dir<<30 | size<<16 | type<<8 | nr,
// SYNC_IOC_MAGIC = '>' (0x3E).  Cross-checked at build time against the
// r27b headers by the repro driver (_Static_assert + runtime print).
// =========================================================================

pub const SYNC_IOC_MAGIC: Int = 0x3E;    // '>'
pub const SYNC_IOC_MERGE: Int = 0xC0303E03;      // _IOWR('>', 3, sync_merge_data)
pub const SYNC_IOC_FILE_INFO: Int = 0xC0383E04;  // _IOWR('>', 4, sync_file_info)
pub const SYNC_IOC_SET_DEADLINE: Int = 0x40103E05; // _IOW('>', 5, sync_set_deadline)

// Pinned struct sizes (x86_64/aarch64 LP64; the ioctl size fields above).
pub const SYNC_MERGE_DATA_SIZE: Int = 48; // char name[32] + i32 fd2/fence + u32 flags/pad
pub const SYNC_FILE_INFO_SIZE: Int = 56;  // char name[32] + i32 status + u32 flags/num_fences/pad + u64 ptr
pub const SYNC_FENCE_INFO_SIZE: Int = 80; // char obj_name[32] + driver_name[32] + i32 status + u32 flags + u64 timestamp_ns
pub const SYNC_SET_DEADLINE_SIZE: Int = 16; // u64 deadline_ns + u64 pad

// errno values for the typed sync error path (asm-generic errno; EBADF on
// fd -1, EINVAL when the fd is not a sync file).
pub const SYS_EBADF: Int = 9;
pub const SYS_EINVAL: Int = 22;

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named platform library pair.  Useful for tests: a
/// bogus pair exercises the ABSENT/SKIP classification deterministically
/// even on hosts that ship the libraries.
/// Complexity: O(load + export set).
pub fn android_sys_probe_named(log_soname: Str, sync_soname: Str) -> Result[AndroidSysRuntime, AndroidSysError]
  requires: log_soname.len() > 0
  requires: sync_soname.len() > 0
{
  let rc = unsafe { xs_load_named(log_soname.c_str(), sync_soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xs_error()) };
    if rc == 1 {
      return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABSENT, errno_code: 0, message: msg });
    }
    return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABI, errno_code: 0, message: msg });
  }
  let missing_count = unsafe { xs_abi_missing_count() as Int };
  let missing = unsafe { Str::from_c_str(xs_abi_missing()) };
  let ext_total = unsafe { xs_ext_count() as Int };
  let ext_missing = unsafe { xs_ext_missing_count() as Int };
  let ext_names = unsafe { Str::from_c_str(xs_ext_missing()) };
  return Ok(AndroidSysRuntime{
    missing_exports: missing_count,
    missing: missing,
    ext_total: ext_total,
    ext_missing: ext_missing,
    ext_missing_names: ext_names,
  });
}

/// Probe the default runtime (liblog.so + libsync.so).  On Android this is
/// the platform itself; on Windows the probe classifies ABSENT (SKIP).
/// Complexity: O(load + export set).
pub fn android_sys_probe() -> Result[AndroidSysRuntime, AndroidSysError]
  requires: true
{
  return android_sys_probe_named(LOG_SONAME, SYNC_SONAME);
}

/// The last bridge error / missing-export summary (empty when clean).
/// Complexity: O(1).
pub fn android_sys_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xs_error()); }
}

/// Release any runtime handles held by the bridge.  Safe when nothing is
/// loaded.
/// Complexity: O(1).
pub fn android_sys_unload()
  requires: true
{
  unsafe { xs_unload(); }
}

// =========================================================================
// Functional liblog head
//
// __android_log_write / _print return 1 when the message was written to
// the log, -EPERM(-1) when the runtime refused it; -2 is the bridge's
// "symbol unresolved" sentinel (mapped to ANDROID_SYS_LOAD_ABI).
// =========================================================================

/// Write `text` with priority `prio` and tag `tag` to the main log
/// (__android_log_write).  Ok(1) = written.
/// Complexity: O(message).
pub fn log_write(prio: Int, tag: Str, text: Str) -> Result[Int, AndroidSysError]
  requires: tag.len() > 0
  requires: text.len() > 0
{
  let rc = unsafe { xs_log_write(prio as Int32, tag.c_str(), text.c_str()) as Int };
  if rc == 1 { return Ok(rc); }
  if rc == -2 {
    return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABI, errno_code: 0, message: android_sys_error() });
  }
  return Err(AndroidSysError{ kind: ANDROID_SYS_CALL, errno_code: 0, message: android_sys_error() });
}

/// Write `text` as a formatted argument to the log (__android_log_print
/// with a fixed "%s" format; the message itself is never a format string).
/// Ok(1) = written.
/// Complexity: O(message).
pub fn log_print(prio: Int, tag: Str, text: Str) -> Result[Int, AndroidSysError]
  requires: tag.len() > 0
  requires: text.len() > 0
{
  let rc = unsafe { xs_log_print(prio as Int32, tag.c_str(), text.c_str()) as Int };
  if rc == 1 { return Ok(rc); }
  if rc == -2 {
    return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABI, errno_code: 0, message: android_sys_error() });
  }
  return Err(AndroidSysError{ kind: ANDROID_SYS_CALL, errno_code: 0, message: android_sys_error() });
}

/// Whether a message with priority `prio` for `tag` would be printed,
/// per the per-tag properties + process minimum and `default_prio` when
/// neither is set (__android_log_is_loggable).
/// Complexity: O(1).
pub fn log_is_loggable(prio: Int, tag: Str, default_prio: Int) -> Bool
  requires: tag.len() > 0
{
  let rc = unsafe { xs_log_is_loggable(prio as Int32, tag.c_str(), default_prio as Int32) as Int };
  return rc == 1;
}

/// As `log_is_loggable`, but only the first `len` bytes of the tag are
/// considered (__android_log_is_loggable_len).
/// Complexity: O(1).
pub fn log_is_loggable_len(prio: Int, tag: Str, len: Int, default_prio: Int) -> Bool
  requires: tag.len() > 0
  requires: len > 0
{
  let rc = unsafe { xs_log_is_loggable_len(prio as Int32, tag.c_str(), len as Int64, default_prio as Int32) as Int };
  return rc == 1;
}

/// Write `text` to a specific log buffer (__android_log_buf_write);
/// applications normally use `log_write` (LOG_ID_MAIN).  Ok(1) = written.
/// Complexity: O(message).
pub fn log_buf_write(buf_id: Int, prio: Int, tag: Str, text: Str) -> Result[Int, AndroidSysError]
  requires: tag.len() > 0
  requires: text.len() > 0
{
  let rc = unsafe { xs_log_buf_write(buf_id as Int32, prio as Int32, tag.c_str(), text.c_str()) as Int };
  if rc == 1 { return Ok(rc); }
  if rc == -2 {
    return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABI, errno_code: 0, message: android_sys_error() });
  }
  return Err(AndroidSysError{ kind: ANDROID_SYS_CALL, errno_code: 0, message: android_sys_error() });
}

/// The process minimum priority (__android_log_get_minimum_priority;
/// ANDROID_LOG_DEFAULT when none was set).  Returns -1 when the API-30
/// extension symbol is absent (older devices).
/// Complexity: O(1).
pub fn log_minimum_priority() -> Int
  requires: true
{
  unsafe { return xs_log_minimum_priority() as Int; }
}

// =========================================================================
// Functional libsync head (typed error path)
//
// sync_file_info/sync_merge failures are reported with the captured
// errno (see SYS_EBADF / SYS_EINVAL).  Pointer results stay C-side: the
// info struct is an opaque Int handle; accessors read fields in the
// bridge.  This wave does not synthesize fences -- the error path is the
// functional proof (fence creation needs a device driver producer).
// =========================================================================

pub type SyncFileInfo = {
  handle: Int;
}

/// Detailed information about the sync file `fd` (sync_file_info).  On
/// failure Err(kind=ANDROID_SYS_CALL) carries the errno (EBADF for an
/// invalid fd; EINVAL when the fd is not a sync file).  Free with
/// `sync_file_info_release`.
/// Complexity: O(1) + kernel query.
pub fn sync_file_info(fd: Int) -> Result[SyncFileInfo, AndroidSysError]
  requires: true
{
  let h = unsafe { xs_sync_file_info(fd as Int32) as Int };
  if h == 0 {
    let e = unsafe { xs_errno() as Int };
    if e == 0 {
      return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABI, errno_code: 0, message: android_sys_error() });
    }
    return Err(AndroidSysError{ kind: ANDROID_SYS_CALL, errno_code: e, message: android_sys_error() });
  }
  return Ok(SyncFileInfo{ handle: h });
}

/// The sync file's status (sync_file_info.status): 0 = unsignaled,
/// 1 = signaled, < 0 = error.  -1 when the handle is invalid.
/// Complexity: O(1).
pub fn sync_file_info_status(info: &SyncFileInfo) -> Int
  requires: true
{
  unsafe { return xs_sync_file_info_status(info.handle as Int64) as Int; }
}

/// Number of fences in the sync file (sync_file_info.num_fences).
/// -1 when the handle is invalid.
/// Complexity: O(1).
pub fn sync_file_info_num_fences(info: &SyncFileInfo) -> Int
  requires: true
{
  unsafe { return xs_sync_file_info_num_fences(info.handle as Int64) as Int; }
}

/// The sync file's name (sync_file_info.name, 32-byte NUL-terminated
/// field; in practice the name passed to sync_merge / set by the
/// producer).  Empty string when the handle is invalid.
/// Complexity: O(1).
pub fn sync_file_info_name(info: &SyncFileInfo) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xs_sync_file_info_name(info.handle as Int64)); }
}

/// Free a sync_file_info returned by `sync_file_info`
/// (sync_file_info_free).
/// Complexity: O(1).
pub fn sync_file_info_release(info: SyncFileInfo)
  requires: true
{
  unsafe { xs_sync_file_info_free(info.handle as Int64); }
}

/// Merge two sync files into a new sync file descriptor named `name`
/// (sync_merge).  Ok(fd) = the new descriptor (close with the platform's
/// fd close); Err(kind=ANDROID_SYS_CALL) carries the errno when the
/// inputs are not sync files (EBADF for invalid fds) -- the original
/// fences stay valid.
/// Complexity: O(kernel merge).
pub fn sync_merge(name: Str, fd1: Int, fd2: Int) -> Result[Int, AndroidSysError]
  requires: name.len() > 0
{
  let rc = unsafe { xs_sync_merge(name.c_str(), fd1 as Int32, fd2 as Int32) as Int };
  if rc >= 0 { return Ok(rc); }
  if rc == -2 {
    return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABI, errno_code: 0, message: android_sys_error() });
  }
  return Err(AndroidSysError{ kind: ANDROID_SYS_CALL, errno_code: unsafe { xs_errno() as Int }, message: android_sys_error() });
}

/// The last errno captured by a sync bridge call (0 when none).
/// Complexity: O(1).
pub fn sync_last_errno() -> Int
  requires: true
{
  unsafe { return xs_errno() as Int; }
}
