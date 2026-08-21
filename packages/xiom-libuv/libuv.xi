// XIOM -- libuv (Cross-platform Asynchronous I/O) Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Pure SPEC package -- all FFI calls return Err until the C bridge is linked.
// Phase 1: Event loop, TCP, timers, file I/O function signatures + full contracts.
//
// Dependencies: libuv (system-installed via winget/apt)
// Compile (when bridge ready): xiom --link uv libuv.xi

module xiom.libuv

// ===========================================================================
// Types
// ===========================================================================

pub type UvLoop = Int;
pub type UvTcp = Int;
pub type UvTimer = Int;

// ===========================================================================
// Constants
// ===========================================================================

pub const UV_RUN_DEFAULT: Int = 0;
pub const UV_RUN_ONCE: Int = 1;
pub const UV_RUN_NOWAIT: Int = 2;

// ===========================================================================
// libuv C FFI Declarations
// ===========================================================================

extern "C" {
  fn uv_loop_new() -> Int;
  fn uv_loop_close(loop: Int);
  fn uv_run(loop: Int, mode: Int) -> Int;
  fn uv_tcp_init(loop: Int, handle: Int) -> Int;
  fn uv_tcp_connect(req: Int, handle: Int, addr: Int, cb: Int) -> Int;
  fn uv_read_start(stream: Int, alloc_cb: Int, read_cb: Int) -> Int;
  fn uv_write(req: Int, stream: Int, buf: Int, count: Int, cb: Int) -> Int;
  fn uv_timer_init(loop: Int, handle: Int) -> Int;
  fn uv_timer_start(handle: Int, cb: Int, timeout: Int, repeat: Int) -> Int;
  fn uv_timer_stop(handle: Int) -> Int;
  fn uv_fs_open(loop: Int, req: Int, path: Int, flags: Int, mode: Int, cb: Int) -> Int;
  fn uv_fs_read(loop: Int, req: Int, file: Int, buf: Int, count: Int, offset: Int, cb: Int) -> Int;
  fn uv_fs_write(loop: Int, req: Int, file: Int, buf: Int, count: Int, offset: Int, cb: Int) -> Int;
  fn uv_fs_close(loop: Int, req: Int, file: Int, cb: Int) -> Int;
}

// ===========================================================================
// Safe Wrappers: Event Loop
// ===========================================================================

pub fn loop_new() -> Result[UvLoop, Str]
  ensures: result.is_ok() || result.is_err();
{
  return Err("stub: libuv C bridge not linked");
}

pub fn loop_close(loop: UvLoop)
  requires: loop > 0;
{
  // stub: no-op until C bridge is linked
}

pub fn loop_run(loop: UvLoop, mode: Int) -> Result[Int, Str]
  requires: loop > 0;
  requires: mode >= 0 && mode <= 2;
{
  return Err("stub: libuv C bridge not linked");
}

// ===========================================================================
// Safe Wrappers: TCP
// ===========================================================================

pub fn tcp_init(loop: UvLoop) -> Result[UvTcp, Str]
  requires: loop > 0;
{
  return Err("stub: libuv C bridge not linked");
}

pub fn tcp_connect(tcp: UvTcp, host: Str, port: Int) -> Result[Int, Str]
  requires: tcp > 0;
  requires: host.len() > 0;
  requires: port > 0;
  requires: port <= 65535;
{
  return Err("stub: libuv C bridge not linked");
}

pub fn tcp_read_start(tcp: UvTcp) -> Result[Int, Str]
  requires: tcp > 0;
{
  return Err("stub: libuv C bridge not linked");
}

pub fn tcp_write(tcp: UvTcp, data: &Vec[UInt8]) -> Result[Int, Str]
  requires: tcp > 0;
  requires: data.len() > 0;
{
  return Err("stub: libuv C bridge not linked");
}

// ===========================================================================
// Safe Wrappers: Timer
// ===========================================================================

pub fn timer_init(loop: UvLoop) -> Result[UvTimer, Str]
  requires: loop > 0;
{
  return Err("stub: libuv C bridge not linked");
}

pub fn timer_start(timer: UvTimer, timeout_ms: Int, repeat_ms: Int) -> Result[Int, Str]
  requires: timer > 0;
  requires: timeout_ms >= 0;
  requires: repeat_ms >= 0;
{
  return Err("stub: libuv C bridge not linked");
}

pub fn timer_stop(timer: UvTimer) -> Result[Int, Str]
  requires: timer > 0;
{
  return Err("stub: libuv C bridge not linked");
}

// ===========================================================================
// Safe Wrappers: File I/O
// ===========================================================================

pub fn fs_open(loop: UvLoop, path: Str, flags: Int, mode: Int) -> Result[Int, Str]
  requires: loop > 0;
  requires: path.len() > 0;
{
  return Err("stub: libuv C bridge not linked");
}

pub fn fs_read(fd: Int, buf: &Vec[UInt8]) -> Result[Int, Str]
  requires: fd > 0;
  requires: buf.len() > 0;
{
  return Err("stub: libuv C bridge not linked");
}

pub fn fs_write(fd: Int, data: &Vec[UInt8]) -> Result[Int, Str]
  requires: fd > 0;
  requires: data.len() > 0;
{
  return Err("stub: libuv C bridge not linked");
}

pub fn fs_close(fd: Int) -> Result[Int, Str]
  requires: fd > 0;
{
  return Err("stub: libuv C bridge not linked");
}
