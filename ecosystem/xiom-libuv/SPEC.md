# xiom-libuv — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: SPEC with XIOM bindings — all FFI stubs return Err (Phase 2 = C bridge)
**Depends on**: xiom.ffi (stdlib)

## What it wraps
libuv — cross-platform asynchronous I/O library (used by Node.js).
Event loop, TCP/UDP sockets, file I/O, timers, child processes.

## Dependencies

| What | How | Size |
|------|-----|------|
| libuv | System-installed. `winget install libuv`, `apt install libuv1-dev` | ~2MB |
| C compiler | For building bridge .obj | — |

## Bundling strategy
**System-installed only.** libuv is ~2MB and available everywhere.

## Files

| File | Purpose |
|------|---------|
| `libuv.xi` | Main module: types, constants, extern FFI declarations, safe wrappers with contracts |
| `tests/test_conformance.xi` | 35 conformance tests (types, constants, stubs, contracts, error handling, lifecycle) |
| `ROADMAP.md` | Phased implementation plan v0.1.0 → v1.0.0 |
| `SPEC.md` | This document |

## API surface (implemented)

```xiom
module xiom.libuv

pub type UvLoop = Int;
pub type UvTcp = Int;
pub type UvTimer = Int;

pub const UV_RUN_DEFAULT: Int = 0;
pub const UV_RUN_ONCE: Int = 1;
pub const UV_RUN_NOWAIT: Int = 2;

// Event loop — 3 functions, 2 with contracts
pub fn loop_new() -> Result[UvLoop, Str]
pub fn loop_close(loop: UvLoop)                         // requires: loop > 0
pub fn loop_run(loop: UvLoop, mode: Int) -> Result[Int, Str]  // requires: loop > 0, mode >= 0 && mode <= 2

// TCP — 4 functions, all with contracts
pub fn tcp_init(loop: UvLoop) -> Result[UvTcp, Str]   // requires: loop > 0
pub fn tcp_connect(tcp: UvTcp, host: Str, port: Int) -> Result[Int, Str]  // requires: tcp > 0, host.len() > 0, port > 0, port <= 65535
pub fn tcp_read_start(tcp: UvTcp) -> Result[Int, Str] // requires: tcp > 0
pub fn tcp_write(tcp: UvTcp, data: &Vec[UInt8]) -> Result[Int, Str]  // requires: tcp > 0, data.len() > 0

// Timer — 3 functions, all with contracts
pub fn timer_init(loop: UvLoop) -> Result[UvTimer, Str]  // requires: loop > 0
pub fn timer_start(timer: UvTimer, timeout_ms: Int, repeat_ms: Int) -> Result[Int, Str]  // requires: timer > 0, timeout_ms >= 0, repeat_ms >= 0
pub fn timer_stop(timer: UvTimer) -> Result[Int, Str]    // requires: timer > 0

// File I/O — 4 functions, all with contracts
pub fn fs_open(loop: UvLoop, path: Str, flags: Int, mode: Int) -> Result[Int, Str]  // requires: loop > 0, path.len() > 0
pub fn fs_read(fd: Int, buf: &Vec[UInt8]) -> Result[Int, Str]  // requires: fd > 0, buf.len() > 0
pub fn fs_write(fd: Int, data: &Vec[UInt8]) -> Result[Int, Str]  // requires: fd > 0, data.len() > 0
pub fn fs_close(fd: Int) -> Result[Int, Str]  // requires: fd > 0

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
```

## Contract coverage
- **13 public functions** total
- **12 functions** guarded by `requires:` contracts (92%)
- **14 extern "C"** FFI declarations
- All contracts validate: non-zero handles, non-empty strings/buffers, valid port/flag ranges

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Event loop, TCP, timers, file I/O (SPEC + stubs) | Done |
| 2 | C bridge (`libuv_bridge.c`), event loop + TCP wiring | Weekend |
| 3 | Timers, file I/O, UDP | Weekend |
| 4 | Callbacks, async patterns, child processes, signals, DNS | Weekend |
