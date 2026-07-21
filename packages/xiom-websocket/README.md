# xiom-websocket

> WebSocket transport for XIOM — handshake, framing, connection lifecycle, heartbeat, backpressure, reconnect, and pub/sub, built on xiom-http and xiom-net.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

> Status: Design stage — spec only, not yet implemented.

## Overview

`xiom-websocket` is a WebSocket **transport-and-session** package, not a realtime application framework. It handles protocol correctness — the RFC 6455 opening handshake, frame codec, ping/pong heartbeats, graceful close, connection/session lifecycle, backpressure, reconnect recovery, and fan-out plumbing — while leaving higher-level behavior (chat rooms, collaboration documents, subscription semantics) to packages such as `xiom-realtime` and `xiom-graphql`.

The package is deliberately separate from the core HTTP layer because WebSockets are stateful, long-lived connections with protocol-specific rules that should not burden ordinary HTTP applications. It builds on `xiom-http` for the upgrade bridge and `xiom-net` for the underlying TCP transport, and it keeps the scaling story (sticky routing plus a pub/sub backplane) explicit rather than hidden.

Every public surface is expected to carry XIOM contracts: contract-checked frame validity, typed session state, explicit connection ownership, and WAL-style monotonic sequence numbers for reconnect recovery.

## Installation

```bash
xiom install xiom-websocket
```

> Not yet available — this package is at the design/specification stage.

## Dependencies

| Package | Role |
|---------|------|
| **xiom-http** | HTTP upgrade handshake bridge (request → WebSocket switch) |
| **xiom-net** | TCP transport for the framed duplex socket stream |
| **xiom-std** | Core types, contracts, collections |

## Planned API Reference

> All items below are **Planned** — no implementation exists yet.

### Handshake (`xiom.websocket.handshake`)
| Function | Signature | Status |
|----------|-----------|--------|
| `accept` | `(req: HttpRequest) -> Result[WebSocketConnection, HandshakeError]` | Planned |
| `validate_upgrade` | `(req: &HttpRequest) -> Result[Unit, HandshakeError]` | Planned |
| `compute_accept_key` | `(sec_key: Str) -> Str` | Planned |

### Frames (`xiom.websocket.frame`)
| Function | Signature | Status |
|----------|-----------|--------|
| `frame_decode` | `(bytes: &Vec[Int]) -> Result[Frame, FrameError]` | Planned |
| `frame_encode` | `(frame: &Frame) -> Vec[Int]` | Planned |
| `opcode_is_control` | `(op: Opcode) -> Bool` | Planned |
| `frame_validate` | `(frame: &Frame) -> Result[Unit, FrameError]` | Planned |

### Connection / Session (`xiom.websocket.connection`)
| Function | Signature | Status |
|----------|-----------|--------|
| `on_message` | `(conn: &mut WebSocketConnection, handler)` | Planned |
| `on_close` | `(conn: &mut WebSocketConnection, handler)` | Planned |
| `send` | `(conn: &mut WebSocketConnection, msg: Message) -> Result[Unit, SendError]` | Planned |
| `close` | `(conn: WebSocketConnection, code: CloseCode)` | Planned |
| `session_of` | `(conn: &WebSocketConnection) -> &Session` | Planned |

### Heartbeat (`xiom.websocket.heartbeat`)
| Function | Signature | Status |
|----------|-----------|--------|
| `ping` | `(conn: &mut WebSocketConnection)` | Planned |
| `on_pong` | `(conn: &mut WebSocketConnection, handler)` | Planned |
| `set_interval` | `(conn: &mut WebSocketConnection, ms: Int)` | Planned |

### Backpressure (`xiom.websocket.backpressure`)
| Function | Signature | Status |
|----------|-----------|--------|
| `set_queue_limit` | `(conn: &mut WebSocketConnection, max: Int)` | Planned |
| `set_overflow_policy` | `(conn: &mut WebSocketConnection, policy: OverflowPolicy)` | Planned |
| `queue_depth` | `(conn: &WebSocketConnection) -> Int` | Planned |

### Reconnect (`xiom.websocket.reconnect`)
| Function | Signature | Status |
|----------|-----------|--------|
| `issue_token` | `(session: &Session) -> ReconnectToken` | Planned |
| `resume` | `(token: ReconnectToken, last_seq: UInt) -> Result[Session, ReconnectError]` | Planned |
| `replay_since` | `(session: &Session, seq: UInt) -> Vec[Message]` | Planned |

### Channels / PubSub (`xiom.websocket.channel`, `xiom.websocket.pubsub`)
| Function | Signature | Status |
|----------|-----------|--------|
| `channel` | `(name: Str) -> Channel` | Planned |
| `subscribe` | `(conn: &mut WebSocketConnection, ch: &Channel)` | Planned |
| `broadcast` | `(ch: &Channel, msg: Message)` | Planned |
| `bind_backplane` | `(adapter: PubSubAdapter)` | Planned |

### Subprotocols (`xiom.websocket.subprotocol`)
| Function | Signature | Status |
|----------|-----------|--------|
| `negotiate` | `(offered: &Vec[Str], supported: &Vec[Str]) -> Option[Str]` | Planned |
| `register` | `(name: Str, spec: SubprotocolSpec)` | Planned |

## Design Documents

- [ARCHITECTURE.md](ARCHITECTURE.md) — full package architecture, module tree, protocol state machine, scaling model.
- [SPEC.md](SPEC.md) — per-module specification and conceptual API surface.
- [docs/handshake.md](docs/handshake.md) — HTTP upgrade handshake.
- [docs/frames.md](docs/frames.md) — frame codec, opcodes, fragmentation, masking.
- [docs/close-codes.md](docs/close-codes.md) — close codes and graceful shutdown.
- [docs/heartbeat.md](docs/heartbeat.md) — ping/pong liveness.
- [docs/reconnect.md](docs/reconnect.md) — sequence-based reconnect recovery.
- [docs/presence.md](docs/presence.md) — TTL-backed presence tracking.
- [docs/backpressure.md](docs/backpressure.md) — send-queue limits and slow consumers.
- [docs/scaling.md](docs/scaling.md) — sticky routing and pub/sub backplane.
- [docs/subprotocols.md](docs/subprotocols.md) — subprotocol negotiation.

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)

## License

MIT OR Apache-2.0
