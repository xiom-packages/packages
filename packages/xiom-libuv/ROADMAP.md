# xiom.libuv Roadmap

## Current State -- v0.1.0 (SPEC)

| Component | Status | Notes |
|-----------|--------|-------|
| `xiom.libuv` module | SPEC | Full API surface declared: 13 public functions, 14 extern FFI stubs, 3 type aliases, 3 constants |
| Event Loop | Stub | `loop_new`, `loop_close`, `loop_run` -- all return Err until C bridge linked |
| TCP | Stub | `tcp_init`, `tcp_connect`, `tcp_read_start`, `tcp_write` -- async I/O signatures with contracts |
| Timer | Stub | `timer_init`, `timer_start`, `timer_stop` -- contracts for timeout/repeat >= 0 |
| File I/O | Stub | `fs_open`, `fs_read`, `fs_write`, `fs_close` -- contracts for path/buf/data non-empty |
| C Bridge | Missing | `libuv_bridge.c` not yet implemented -- all FFI stubs return Err |

### Contracts Coverage

- **13 public functions**
- **12 functions** guarded by `requires:` contracts (92%)
- **14 extern "C"** function declarations for libuv FFI
- Missing contract: `loop_new()` -- returns Result, no input to validate

### Test Coverage

- **35 conformance tests** in `tests/test_conformance.xi`
- Covers: types (3), constants (3), event loop stubs (3), TCP stubs (4), timer stubs (3), file I/O stubs (4), contract declarations (12), error handling (2), lifecycle (1)

---

## v0.2.0 -- C Bridge Implementation

- [ ] Create `libuv_bridge.c` with thin FFI wrappers
- [ ] Build system: CMake integration for libuv linking
- [ ] Wire `loop_new()` -> CFFI `uv_loop_new()`
- [ ] Wire `loop_close()` -> CFFI `uv_loop_close()`
- [ ] Wire `loop_run()` -> CFFI `uv_run()`
- [ ] Replace Error stubs with actual FFI call + error translation
- [ ] Tests: run against live libuv.dll (skip if not installed)

## v0.3.0 -- TCP Sockets

- [ ] Wire `tcp_init()` -> CFFI `uv_tcp_init()`
- [ ] Wire `tcp_connect()` -> CFFI `uv_tcp_connect()` with sockaddr building
- [ ] Wire `tcp_read_start()` -> CFFI `uv_read_start()` with buffer callbacks
- [ ] Wire `tcp_write()` -> CFFI `uv_write()` with uv_buf_t marshaling
- [ ] Add `tcp_close()` / `tcp_shutdown()` wrappers
- [ ] Error code mapping: uv_errno_t -> human-readable Str
- [ ] Tests: TCP connect to echo server, read/write roundtrip

## v0.4.0 -- Timers

- [ ] Wire `timer_init()` -> CFFI `uv_timer_init()`
- [ ] Wire `timer_start()` -> CFFI `uv_timer_start()` with callback
- [ ] Wire `timer_stop()` -> CFFI `uv_timer_stop()`
- [ ] Add `timer_again()` wrapper for repeating timers
- [ ] Tests: one-shot timer, repeating timer, timer stop mid-cycle

## v0.5.0 -- File I/O

- [ ] Wire `fs_open()` -> CFFI `uv_fs_open()`
- [ ] Wire `fs_read()` -> CFFI `uv_fs_read()` with Vec buffer bridging
- [ ] Wire `fs_write()` -> CFFI `uv_fs_write()` with Vec data bridging
- [ ] Wire `fs_close()` -> CFFI `uv_fs_close()`
- [ ] Add `fs_stat()`, `fs_unlink()`, `fs_mkdir()` wrappers
- [ ] Tests: file create/read/write/close roundtrip, error paths (ENOENT, EACCES)

## v0.6.0 -- UDP Sockets

- [ ] `udp_init()`, `udp_bind()`, `udp_send()`, `udp_recv_start()`
- [ ] `udp_close()`
- [ ] Tests: UDP send/receive, multicast join/leave

## v0.7.0 -- Async Callback Integration

- [ ] Callback type system: XIOM fn ptr <-> libuv callback marshaling
- [ ] Safe handle lifecycle: Drop trait or explicit `close` with resource tracking
- [ ] XIOM closure capture for async callbacks
- [ ] Tests: event-driven TCP echo server, timer-driven counter

## v1.0.0 -- Stable Release

- [ ] All above features complete
- [ ] 90%+ test coverage on all modules
- [ ] Full API documentation
- [ ] Cross-platform CI: Windows (winget), Linux (apt), macOS (brew)
- [ ] Performance benchmarks (latency, throughput)
- [ ] Security audit of all `unsafe` blocks
- [ ] Formal contract verification (xiom-verify) on public API

---

## Backlog / Future

| Feature | Priority | Notes |
|---------|----------|-------|
| Child processes | Medium | `uv_spawn`, `uv_process_kill` |
| Signals | Low | `uv_signal_init`, `uv_signal_start` (SIGINT, SIGTERM) |
| DNS resolution | Medium | `uv_getaddrinfo`, `uv_getnameinfo` |
| Pipes | Low | `uv_pipe_init` (local IPC, named pipes) |
| TTY | Low | `uv_tty_init`, terminal I/O |
| Thread pool work | Medium | `uv_queue_work` for CPU-bound tasks |
| Idle/Prepare/Check handles | Low | Event loop phase hooks |
| Poll handles | Low | `uv_poll_init` for arbitrary fd watching |
| Async handles | Medium | `uv_async_init` for cross-thread wakeups |
| Stream buffering | Medium | Built-in write queue with backpressure |

---

## Dependency Graph

```
xiom.libuv (this package)
  |-- xiom-std (stdlib: string, collections, ptr)
  |-- libuv C library (system-installed: winget/apt/brew)
  `-- libuv_bridge.c (thin C FFI wrapper)
```
