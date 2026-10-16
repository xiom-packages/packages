// XIOM -- xiom.android.lifecycle: A2 lifecycle-glue head (W2c).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// SCOPE: android/looper.h + android/native_activity.h of NDK r27b
// (docs/ANDROID-SDK100.md slice A2; wave brief docs/prep/android-wave.md).
//
//   ALooper       -- FUNCTIONAL: prepare/forThread/wake/addFd (callback
//                    or ident variant)/removeFd/pollOnce/pollAll, plus
//                    the probe pipe helpers the looper itself needs.
//                    Handlers use DIRECT HANDOFF (env-free top-level
//                    fns; B-22 fixed in m277 -- see glfw 0.6.0).
//   ANativeActivity_* -- export-set ABI-checked in the bridge (5 exports);
//                    live wrappers need a real NativeActivity instance
//                    (A11 JNI seam / G1), so only the flag constants are
//                    surfaced here.  ANativeActivity_onCreate + the 16
//                    callback fields are the CONSUMER's surface -- the
//                    native_app_glue C unit implements them (source ships
//                    in the NDK; not vendored here, compile into the app).
//
// The declared export set (117 total for the package) is verified at
// runtime by the bridge; on Windows the runtime is absent -> the suite
// reports the SKIP classification and every functional call errors
// explicitly (never a silent zero).
//
// Minimum API level note: the full A2 declared set needs API 34+
// (AConfiguration get/setGrammaticalGender is API 34; getScreenRound is
// API 30); against older images the bridge reports the honest ABI delta.

module xiom.android.lifecycle

use xiom.android;

extern "C" {
  fn xa_looper_prepare(allow_non_callbacks: Int32) -> Int64;
  fn xa_looper_for_thread() -> Int64;
  fn xa_looper_acquire(looper: Int64);
  fn xa_looper_release(looper: Int64);
  fn xa_looper_wake(looper: Int64) -> Int32;
  fn xa_looper_add_fd(looper: Int64, fd: Int32, ident: Int32, events: Int32,
                      cb: fn(Int32, Int32, Int) -> Int32, data: Int64) -> Int32;
  fn xa_looper_add_fd_ident(looper: Int64, fd: Int32, ident: Int32, events: Int32) -> Int32;
  fn xa_looper_remove_fd(looper: Int64, fd: Int32) -> Int32;
  fn xa_looper_poll_once(looper: Int64, timeout_ms: Int32) -> Int32;
  fn xa_looper_poll_all(looper: Int64, timeout_ms: Int32) -> Int32;
  fn xa_looper_last_fd() -> Int32;
  fn xa_looper_last_events() -> Int32;
  fn xa_looper_last_data() -> Int64;
  fn xa_pipe_open() -> Int64;
  fn xa_pipe_write_byte(byte: Int32) -> Int32;
  fn xa_pipe_read_byte(fd: Int32) -> Int32;
  fn xa_pipe_close(read_fd: Int64) -> Int32;
}

// =========================================================================
// ALooper constants (android/looper.h)
// =========================================================================

// ALooper_prepare option: accept ALooper_addFd calls with a NULL callback.
pub const ALOOPER_PREPARE_ALLOW_NON_CALLBACKS: Int = 1;

// ALooper_pollOnce / ALooper_pollAll results.
pub const ALOOPER_POLL_WAKE: Int = -1;
pub const ALOOPER_POLL_CALLBACK: Int = -2;
pub const ALOOPER_POLL_TIMEOUT: Int = -3;
pub const ALOOPER_POLL_ERROR: Int = -4;

// File-descriptor event flags (ALOOPER_EVENT_*).
pub const ALOOPER_EVENT_INPUT: Int = 1;
pub const ALOOPER_EVENT_OUTPUT: Int = 2;
pub const ALOOPER_EVENT_ERROR: Int = 4;
pub const ALOOPER_EVENT_HANGUP: Int = 8;
pub const ALOOPER_EVENT_INVALID: Int = 16;

// =========================================================================
// ANativeActivity constants (android/native_activity.h)
//
// The 5 exported ANativeActivity_* functions (finish/setWindowFormat/
// setWindowFlags/showSoftInput/hideSoftInput) are export-set ABI-checked
// by the bridge; live wrappers join at the A11 JNI seam.  Flags below.
// =========================================================================

// ANativeActivity_showSoftInput flags.
pub const ANATIVEACTIVITY_SHOW_SOFT_INPUT_IMPLICIT: Int = 0x0001;
pub const ANATIVEACTIVITY_SHOW_SOFT_INPUT_FORCED: Int = 0x0002;

// ANativeActivity_hideSoftInput flags.
pub const ANATIVEACTIVITY_HIDE_SOFT_INPUT_IMPLICIT_ONLY: Int = 0x0001;
pub const ANATIVEACTIVITY_HIDE_SOFT_INPUT_NOT_ALWAYS: Int = 0x0002;

// =========================================================================
// ALooper functional head
// =========================================================================

pub type Looper = {
  handle: Int;
}

pub type LooperPipe = {
  read_fd: Int;
}

/// The looper associated with the calling thread, or handle 0 when the
/// thread has none (a normal state, not an error).
/// Complexity: O(1).
pub fn looper_for_thread() -> Looper
  requires: true
{
  let h = unsafe { xa_looper_for_thread() } as Int;
  return Looper{ handle: h };
}

/// True when the handle refers to a live looper (non-zero).
/// Complexity: O(1).
pub fn looper_valid(lp: &Looper) -> Bool
  requires: true
{
  return lp.handle != 0;
}

/// Prepare (or return) the calling thread's looper.  With
/// `allow_non_callbacks` the looper also accepts `looper_add_fd_ident`
/// (NULL callback; the poll return carries the ident).
/// Complexity: O(1).
pub fn looper_prepare(allow_non_callbacks: Bool) -> Result[Looper, AndroidProbeError]
  requires: true
{
  let flags: Int32 = if allow_non_callbacks { 1 } else { 0 };
  let h = unsafe { xa_looper_prepare(flags) } as Int;
  if h == 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI, message: android_error() });
  }
  return Ok(Looper{ handle: h });
}

/// Add one reference (safe hand-off across threads).
/// Complexity: O(1).
pub fn looper_acquire(lp: &Looper)
  requires: true
{
  unsafe { xa_looper_acquire(lp.handle as Int64); }
}

/// Drop one reference previously added with looper_acquire.
/// Complexity: O(1).
pub fn looper_release(lp: &Looper)
  requires: true
{
  unsafe { xa_looper_release(lp.handle as Int64); }
}

/// Wake the poll from any thread (returns immediately).
/// Complexity: O(1).
pub fn looper_wake(lp: &Looper) -> Bool
  requires: true
{
  let rc = unsafe { xa_looper_wake(lp.handle as Int64) } as Int;
  return rc == 1;
}

/// Add a file descriptor with a DIRECT-HANDOFF handler (`handler` must be
/// an env-free top-level fn).  `ident` is ignored for callback fd's (the
/// poll return is ALOOPER_POLL_CALLBACK); pass ALOOPER_EVENT_INPUT for
/// "data available".  Returns true when the fd was added.
/// Complexity: O(1).
pub fn looper_add_fd(lp: &Looper, fd: Int, ident: Int, events: Int,
                     handler: fn(Int32, Int32, Int) -> Int32) -> Bool
  requires: true
{
  let rc = unsafe {
    xa_looper_add_fd(lp.handle as Int64, fd as Int32, ident as Int32,
                     events as Int32, handler, 0 as Int64) as Int
  };
  return rc == 1;
}

/// Add a file descriptor with NO callback (requires
/// looper_prepare(true)).  `looper_poll_once` then returns `ident` when
/// the fd has data and the caller owns the fd handling.
/// Complexity: O(1).
pub fn looper_add_fd_ident(lp: &Looper, fd: Int, ident: Int, events: Int) -> Bool
  requires: ident >= 0
{
  let rc = unsafe {
    xa_looper_add_fd_ident(lp.handle as Int64, fd as Int32, ident as Int32,
                           events as Int32) as Int
  };
  return rc == 1;
}

/// Remove a previously added fd: 1 removed, 0 not registered, -1 error.
/// Complexity: O(1).
pub fn looper_remove_fd(lp: &Looper, fd: Int) -> Int
  requires: true
{
  unsafe { return xa_looper_remove_fd(lp.handle as Int64, fd as Int32) as Int; }
}

/// Poll the CALLING thread's looper (the handle must be that thread's).
/// Returns a non-negative ident (data on a NULL-callback fd),
/// ALOOPER_POLL_CALLBACK (-2), ALOOPER_POLL_WAKE (-1),
/// ALOOPER_POLL_TIMEOUT (-3) or ALOOPER_POLL_ERROR (-4).  The out
/// params (fd/events/data) are read via looper_last_* (B-24 discipline).
/// Complexity: O(poll).
pub fn looper_poll_once(lp: &Looper, timeout_ms: Int) -> Int
  requires: true
{
  unsafe { return xa_looper_poll_once(lp.handle as Int64, timeout_ms as Int32) as Int; }
}

/// ALooper_pollAll (legacy; exported and ABI-checked).  Prefer
/// looper_poll_once -- pollAll may miss wakes (header deprecation).
/// Complexity: O(poll).
pub fn looper_poll_all(lp: &Looper, timeout_ms: Int) -> Int
  requires: true
{
  unsafe { return xa_looper_poll_all(lp.handle as Int64, timeout_ms as Int32) as Int; }
}

/// outFd of the last poll (0 when the call returned a poll code).
/// Complexity: O(1).
pub fn looper_last_fd() -> Int
  requires: true
{
  unsafe { return xa_looper_last_fd() as Int; }
}

/// outEvents of the last poll.
/// Complexity: O(1).
pub fn looper_last_events() -> Int
  requires: true
{
  unsafe { return xa_looper_last_events() as Int; }
}

/// outData of the last poll as an opaque token (0 when unset).
/// Complexity: O(1).
pub fn looper_last_data() -> Int
  requires: true
{
  unsafe { return xa_looper_last_data() as Int; }
}

// =========================================================================
// Probe pipe helpers (what a looper consumer attaches; POSIX pipe(2))
//
// One bridge-side pipe pair at a time (probe/suite scope).  The read end
// is O_NONBLOCK; the write end stays bridge-side.
// =========================================================================

/// Create the probe pipe; the returned fd is the read end (attach it with
/// looper_add_fd / looper_add_fd_ident).  Close with looper_pipe_close.
/// Complexity: O(1).
pub fn looper_pipe_open() -> Result[LooperPipe, AndroidProbeError]
  requires: true
{
  let fd = unsafe { xa_pipe_open() } as Int;
  if fd < 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI, message: android_error() });
  }
  return Ok(LooperPipe{ read_fd: fd });
}

/// Write one byte to the pipe's write end.
/// Complexity: O(1).
pub fn looper_pipe_write(pipe: &LooperPipe, byte: Int) -> Bool
  requires: byte >= 0
  requires: byte <= 255
{
  let rc = unsafe { xa_pipe_write_byte(byte as Int32) } as Int;
  return rc == 0;
}

/// Read one byte from the read end: byte >= 0, -1 empty (non-blocking),
/// -2 eof (write end closed), -3 error.
/// Complexity: O(1).
pub fn looper_pipe_read(pipe: &LooperPipe) -> Int
  requires: true
{
  unsafe { return xa_pipe_read_byte(pipe.read_fd as Int32) as Int; }
}

/// Close both ends of the probe pipe.
/// Complexity: O(1).
pub fn looper_pipe_close(pipe: LooperPipe) -> Bool
  requires: true
{
  let rc = unsafe { xa_pipe_close(pipe.read_fd as Int64) } as Int;
  return rc == 0;
}
