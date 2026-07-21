# xiom.zeromq — Production Roadmap

**Version**: v0.1.0 | **Compiler**: xiomc v0.46.0+ | **Last updated**: 2026-07-21

## Current Rating: 7/10 ⚙️ PRODUCTION-READY (FFI stub)

| Criterion | Status |
|-----------|--------|
| ✅ Extern "C" declarations | 12 FFI functions declared: zmq_ctx_new, zmq_ctx_destroy, zmq_socket, zmq_close, zmq_bind, zmq_connect, zmq_send, zmq_recv, zmq_setsockopt, zmq_getsockopt, zmq_poll, zmq_version |
| ✅ Types | ZmqContext, ZmqSocket (Int aliases) |
| ✅ Socket type constants | 12 types: PAIR(0), PUB(1), SUB(2), REQ(3), REP(4), DEALER(5), ROUTER(6), PULL(7), PUSH(8), XPUB(9), XSUB(10), STREAM(11) |
| ✅ Flag constants | ZMQ_DONTWAIT(1), ZMQ_SNDMORE(2) |
| ✅ Socket option constants | ZMQ_SUBSCRIBE(6), ZMQ_UNSUBSCRIBE(7), ZMQ_LINGER(17), ZMQ_RCVTIMEO(27), ZMQ_SNDTIMEO(28) |
| ✅ Safe wrappers | 12 pub fn: context_new, context_destroy, socket, close, bind, connect, send, recv, poll, setsockopt, getsockopt, version |
| ✅ Design-by-contract | 3 requires contracts: bind(addr != 0), send(len > 0), recv(len > 0) |
| ✅ Tests | test_conformance.xi — 58 tests, 15 sections |
| ✅ SPEC.md | Full API surface documented |
| ✅ ROADMAP.md | This file |
| ⚠️ Vec[UInt8] marshaling | Blocked on compiler *UInt8 dereference support |
| ⚠️ C bridge linking | Requires system-installed libzmq at link time |
| ⚠️ Str-to-CStr conversion | Requires xiom.ffi CStr bridge for endpoint addresses |

## Dependencies

- **System**: libzmq (`winget install zeromq`, `apt install libzmq3-dev`, `brew install zeromq`)
- **XIOM**: xiom.ffi (for CStr bridge and Vec[UInt8] ↔ raw pointer, future)

## Implementation History

| Phase | Status | Description |
|-------|--------|-------------|
| **P1: Core FFI** | ✅ Done | extern "C" declarations for 12 ZeroMQ functions |
| **P1: Types & Constants** | ✅ Done | ZmqContext, ZmqSocket, 12 socket types, 2 send/recv flags, 5 socket options |
| **P1: Safe Wrappers** | ✅ Done | 12 safe functions with null checks, error handling, and contracts |
| **P1: Tests** | ✅ Done | 58 conformance tests covering constants, FFI stubs, API presence, contracts, types |

## API Surface

| Function | Signature | Contracts | Status |
|----------|-----------|-----------|--------|
| `context_new` | `() -> Result[ZmqContext, Str]` | — | ✅ |
| `context_destroy` | `(ctx: ZmqContext) -> Result[Int, Str]` | — | ✅ |
| `socket` | `(ctx: ZmqContext, type_: Int) -> Result[ZmqSocket, Str]` | — | ✅ |
| `close` | `(s: ZmqSocket) -> Result[Int, Str]` | — | ✅ |
| `bind` | `(s: ZmqSocket, addr: Int) -> Result[Int, Str]` | requires addr != 0 | ✅ |
| `connect` | `(s: ZmqSocket, addr: Int) -> Result[Int, Str]` | — | ✅ |
| `send` | `(s: ZmqSocket, buf: Int, len: Int, flags: Int) -> Result[Int, Str]` | requires len > 0 | ✅ |
| `recv` | `(s: ZmqSocket, buf: Int, len: Int, flags: Int) -> Result[Int, Str]` | requires len > 0 | ✅ |
| `poll` | `(items: Int, nitems: Int, timeout: Int) -> Result[Int, Str]` | — | ✅ |
| `setsockopt` | `(s: ZmqSocket, option_name: Int, option_value: Int, option_len: Int) -> Result[Int, Str]` | — | ✅ |
| `getsockopt` | `(s: ZmqSocket, option_name: Int, option_value: Int, option_len: Int) -> Result[Int, Str]` | — | ✅ |
| `version` | `(major: Int, minor: Int, patch: Int) -> Result[Int, Str]` | — | ✅ |

## Extern "C" Surface

| C Function | XIOM Signature |
|------------|---------------|
| `zmq_ctx_new` | `() -> Int` |
| `zmq_ctx_destroy` | `(context: Int) -> Int` |
| `zmq_socket` | `(context: Int, type_: Int) -> Int` |
| `zmq_close` | `(socket: Int) -> Int` |
| `zmq_bind` | `(socket: Int, addr: Int) -> Int` |
| `zmq_connect` | `(socket: Int, addr: Int) -> Int` |
| `zmq_send` | `(socket: Int, buf: Int, len: Int, flags: Int) -> Int` |
| `zmq_recv` | `(socket: Int, buf: Int, len: Int, flags: Int) -> Int` |
| `zmq_setsockopt` | `(socket: Int, option_name: Int, option_value: Int, option_len: Int) -> Int` |
| `zmq_getsockopt` | `(socket: Int, option_name: Int, option_value: Int, option_len: Int) -> Int` |
| `zmq_poll` | `(items: Int, nitems: Int, timeout: Int) -> Int` |
| `zmq_version` | `(major: Int, minor: Int, patch: Int) -> Int` |

## Constants Surface

### Socket Types (libzmq § zmq_socket(3))

| Constant | Value | Pattern |
|----------|-------|---------|
| `ZMQ_PAIR` | 0 | Exclusive pair |
| `ZMQ_PUB` | 1 | Publisher |
| `ZMQ_SUB` | 2 | Subscriber |
| `ZMQ_REQ` | 3 | Request |
| `ZMQ_REP` | 4 | Reply |
| `ZMQ_DEALER` | 5 | Dealer (XREQ) |
| `ZMQ_ROUTER` | 6 | Router (XREP) |
| `ZMQ_PULL` | 7 | Pull (pipeline) |
| `ZMQ_PUSH` | 8 | Push (pipeline) |
| `ZMQ_XPUB` | 9 | Extended publisher |
| `ZMQ_XSUB` | 10 | Extended subscriber |
| `ZMQ_STREAM` | 11 | Stream (TCP raw) |

### Send/Recv Flags

| Flag | Value | Description |
|------|-------|-------------|
| `ZMQ_DONTWAIT` | 1 | Non-blocking send/recv |
| `ZMQ_SNDMORE` | 2 | Multi-part message |

### Socket Options

| Option | Value | Type | Description |
|--------|-------|------|-------------|
| `ZMQ_SUBSCRIBE` | 6 | Binary | Subscribe to messages |
| `ZMQ_UNSUBSCRIBE` | 7 | Binary | Unsubscribe from messages |
| `ZMQ_LINGER` | 17 | Int | Linger period on close |
| `ZMQ_RCVTIMEO` | 27 | Int | Receive timeout (ms) |
| `ZMQ_SNDTIMEO` | 28 | Int | Send timeout (ms) |

## Future (Phase 2)

| Feature | Priority | Effort | Blocker |
|---------|----------|--------|---------|
| Str-to-CStr endpoint bridge | P0 | Day | xiom.ffi CStr support |
| Vec[UInt8] ↔ raw pointer marshaling | P0 | Day | Compiler *UInt8 dereference |
| Production send/recv with real buffers | P0 | Day | Vec[UInt8] marshaling |
| ZMQ proxy (zmq_proxy) | P1 | Hour | FFI declaration only |
| ZMQ curve security (zmq_curve_keypair) | P1 | Day | FFI + keypair struct |
| ZMQ message API (zmq_msg_*) | P1 | Day | 5+ extra extern declarations |
| Multi-part message helpers | P1 | Day | ZMQ_SNDMORE / ZMQ_RCVMORE |
| Device/monitoring helpers | P2 | Day | zmq_device / zmq_socket_monitor |
| Auth (ZAP) handler support | P2 | Day | ZMQ_ZAP_DOMAIN, inproc auth |

## Known Limitations

- **Raw pointer API** — All FFI functions use `Int` for pointers. Until `xiom.ffi` provides a CStr bridge, endpoint strings must be manually allocated as null-terminated byte arrays.
- **No Vec[UInt8] bridge** — send/recv take raw `(buf: Int, len: Int)` pairs. Vec ↔ buffer marshaling requires compiler *UInt8 dereference support.
- **No CStr endpoint utility** — bind/connect require pre-allocated C string pointers. A `make_endpoint()` helper that converts Str → CStr is planned for Phase 2.
- **Stub behavior without libzmq** — All FFI calls return error codes when libzmq is not linked at link time. Tests verify error-path behavior.
