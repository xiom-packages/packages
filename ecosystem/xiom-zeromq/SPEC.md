# xiom-zeromq — SPEC

**Phase**: 4 (Enterprise) | **Priority**: Medium
**Status**: PRODUCTION | **Depends on**: xiom.ffi (for CStr bridge, future)

## What it wraps
libzmq — high-performance asynchronous messaging library (ZeroMQ).
Supports PUB/SUB, REQ/REP, PUSH/PULL, and other messaging patterns.

## Dependencies: System-installed. `winget install zeromq`, `apt install libzmq3-dev`, `brew install zeromq`.

## Bundling strategy: System-installed only.

## Types
```xiom
pub type ZmqContext = Int
pub type ZmqSocket = Int
```

## Socket type constants
```xiom
pub const ZMQ_PAIR:   Int = 0
pub const ZMQ_PUB:    Int = 1
pub const ZMQ_SUB:    Int = 2
pub const ZMQ_REQ:    Int = 3
pub const ZMQ_REP:    Int = 4
pub const ZMQ_DEALER: Int = 5
pub const ZMQ_ROUTER: Int = 6
pub const ZMQ_PULL:   Int = 7
pub const ZMQ_PUSH:   Int = 8
pub const ZMQ_XPUB:   Int = 9
pub const ZMQ_XSUB:   Int = 10
pub const ZMQ_STREAM: Int = 11
```

## Flag constants
```xiom
pub const ZMQ_DONTWAIT: Int = 1
pub const ZMQ_SNDMORE:  Int = 2
```

## Socket option constants
```xiom
pub const ZMQ_SUBSCRIBE:   Int = 6
pub const ZMQ_UNSUBSCRIBE: Int = 7
pub const ZMQ_LINGER:      Int = 17
pub const ZMQ_RCVTIMEO:    Int = 27
pub const ZMQ_SNDTIMEO:    Int = 28
```

## API (implemented)
```xiom
pub fn context_new() -> Result[ZmqContext, Str]

pub fn context_destroy(ctx: ZmqContext) -> Result[Int, Str]

pub fn socket(ctx: ZmqContext, type_: Int) -> Result[ZmqSocket, Str]

pub fn close(s: ZmqSocket) -> Result[Int, Str]

pub fn bind(s: ZmqSocket, addr: Int) -> Result[Int, Str]
  requires: addr != 0

pub fn connect(s: ZmqSocket, addr: Int) -> Result[Int, Str]

pub fn send(s: ZmqSocket, buf: Int, len: Int, flags: Int) -> Result[Int, Str]
  requires: len > 0

pub fn recv(s: ZmqSocket, buf: Int, len: Int, flags: Int) -> Result[Int, Str]
  requires: len > 0

pub fn poll(items: Int, nitems: Int, timeout: Int) -> Result[Int, Str]

pub fn setsockopt(s: ZmqSocket, option_name: Int, option_value: Int, option_len: Int) -> Result[Int, Str]

pub fn getsockopt(s: ZmqSocket, option_name: Int, option_value: Int, option_len: Int) -> Result[Int, Str]

pub fn version(major: Int, minor: Int, patch: Int) -> Result[Int, Str]
```

## Extern "C" declarations
```xiom
extern "C" {
  fn zmq_ctx_new() -> Int;
  fn zmq_ctx_destroy(context: Int) -> Int;
  fn zmq_socket(context: Int, type_: Int) -> Int;
  fn zmq_close(socket: Int) -> Int;
  fn zmq_bind(socket: Int, addr: Int) -> Int;
  fn zmq_connect(socket: Int, addr: Int) -> Int;
  fn zmq_send(socket: Int, buf: Int, len: Int, flags: Int) -> Int;
  fn zmq_recv(socket: Int, buf: Int, len: Int, flags: Int) -> Int;
  fn zmq_setsockopt(socket: Int, option_name: Int, option_value: Int, option_len: Int) -> Int;
  fn zmq_getsockopt(socket: Int, option_name: Int, option_value: Int, option_len: Int) -> Int;
  fn zmq_poll(items: Int, nitems: Int, timeout: Int) -> Int;
  fn zmq_version(major: Int, minor: Int, patch: Int) -> Int;
}
```

## Files
| File | Lines | Description |
|------|-------|-------------|
| `src/zeromq.xi` | ~240 | Main module: types, constants, 12 extern C + 12 safe wrappers with 3 requires contracts |
| `tests/test_conformance.xi` | ~440 | 58 conformance tests (15 sections) |
| `ROADMAP.md` | — | Single-phase roadmap, known limitations, future work |
| `SPEC.md` | — | This file |

## Test Coverage (58 tests, 15 sections)
1. Socket type constants — 7 tests: PUB, SUB, REQ, REP, PULL, PUSH, 12 types defined
2. zmq_ctx_new / zmq_ctx_destroy — 3 tests: callable, null context, valid handle
3. zmq_socket / zmq_close — 4 tests: callable, null context, all 12 types, close null
4. zmq_bind / zmq_connect — 3 tests: null socket, connect null, stubs callable
5. zmq_send / zmq_recv — 4 tests: null socket, with length, error paths
6. zmq_setsockopt / zmq_getsockopt — 3 tests: null sockopt, SUBSCRIBE stub
7. zmq_poll — 3 tests: zero items, timeout, block indefinitely
8. zmq_version — 1 test: callable with null pointers
9. API presence — 12 tests: all 12 safe wrapper signatures
10. Contract declarations — 3 tests: bind(addr != 0), send(len > 0), recv(len > 0)
11. Type definitions — 2 tests: ZmqContext, ZmqSocket
12. Flag constants — 2 tests: ZMQ_DONTWAIT, ZMQ_SNDMORE
13. Socket option constants — 4 tests: SUBSCRIBE, LINGER, RCVTIMEO, SNDTIMEO
14. Safe wrapper stubs — 6 tests: context_new, socket, bind, send, recv error paths
15. Extern count — 1 test: 12 ZeroMQ C functions declared

## Known Limitations
- send() and recv() use raw `(buf: Int, len: Int)` — Vec[UInt8] bridge blocked on compiler *UInt8 dereference support
- bind() and connect() require pre-allocated C string pointers — CStr bridge blocked on xiom.ffi
- All FFI calls return error codes when libzmq is not linked at link time
- FFI error-checking and null-guard logic is complete; only buffer marshaling is stubbed

## Effort: Day (implemented)
