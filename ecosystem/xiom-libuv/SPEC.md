# xiom-libuv — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: SPEC only — no implementation yet
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

## API surface

```xiom
module xiom.libuv

// Event loop
pub fn loop_new() -> Result[Loop, Str]
pub fn loop_run(l: &mut Loop, mode: Int) -> Result[Int, Str]
pub fn loop_close(l: Loop)

// TCP
pub fn tcp_new(l: &Loop) -> Result[Tcp, Str]
pub fn tcp_connect(t: &mut Tcp, addr: Str, port: Int, cb: fn(Result[Tcp, Str]))
pub fn tcp_read_start(t: &mut Tcp, cb: fn(Vec[UInt8]))
pub fn tcp_write(t: &mut Tcp, data: &Vec[UInt8], cb: fn(Result[Int, Str]))

// Timer
pub fn timer_new(l: &Loop) -> Result[Timer, Str]
pub fn timer_start(t: &mut Timer, cb: fn(), timeout_ms: Int, repeat_ms: Int)

// File I/O
pub fn fs_open(l: &Loop, path: Str, flags: Int, mode: Int, cb: fn(Result[File, Str]))
pub fn fs_read(f: &File, buf: &mut Vec[UInt8], offset: Int, cb: fn(Result[Int, Str]))
pub fn fs_write(f: &File, data: &Vec[UInt8], offset: Int, cb: fn(Result[Int, Str]))
```

## Contract coverage target
- Loop: `requires: l != 0`
- Callbacks: XIOM closures with captured state
- Resource cleanup: Drop trait or explicit free

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Event loop, TCP connect/read/write | Weekend |
| 2 | Timers, file I/O, UDP | Weekend |
| 3 | Child processes, signals, DNS | Weekend |
