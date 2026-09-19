# xiom.websocket -- WebSocket Transport Specification

> **Status: v0.1.0 -- Implemented.** Core types (WsOpcode, WsConnection, WsFrame, WsMessage), extern "C" FFI blocks for socket/handshake/frame operations, frame encode/decode stubs, connection lifecycle, handshake validation, server management, channel subscriptions, close codes, and heartbeat utilities are implemented in `websocket.xi`. See `ROADMAP.md` for planned features.

## Overview

`xiom.websocket` is the ecosystem package providing WebSocket protocol support for XIOM, built on `xiom.http` (upgrade bridge) and `xiom.net` (TCP transport). It covers the RFC 6455 opening handshake, frame codec, connection/session lifecycle, heartbeat, backpressure, reconnect recovery, presence, channels, and a pub/sub backplane interface for cross-node fan-out.

The package is a transport-and-session layer. It is responsible for protocol correctness and connection plumbing; realtime application semantics live in `xiom.realtime` and `xiom.graphql`.

Design principles carried throughout:

- **Contract-checked frame validity** -- every decoded frame is validated against opcode, length, fragmentation, and masking contracts before it reaches a handler.
- **Typed session state** -- session identity, reconnect metadata, and presence are modeled as explicit typed state, never ambient globals.
- **Explicit connection ownership** -- a `WebSocketConnection` owns its socket, send queue, receive loop, and subscriptions, and cleans up deterministically when dropped.
- **WAL-style sequence numbers** -- outbound messages carry monotonic sequence numbers, enabling a reconnecting client to request a replay of everything after its last acknowledged sequence.

## RFC 6455 Protocol Lifecycle

`xiom.websocket` models the connection as a strict state machine:

1. **HTTP request received** -- an ordinary HTTP request arrives via `xiom.http`.
2. **Upgrade headers validated** -- `Upgrade: websocket`, `Connection: Upgrade`, `Sec-WebSocket-Key`, and `Sec-WebSocket-Version: 13` are checked with `requires` contracts.
3. **Protocol switched** -- a `101 Switching Protocols` response is sent with the computed `Sec-WebSocket-Accept` value; the socket detaches from HTTP and enters framed mode.
4. **Frames parsed and validated** -- the framed duplex stream is decoded frame-by-frame; control frames and data frames are dispatched.
5. **Messages routed** -- reassembled messages are delivered to handlers or channel subscriptions.
6. **Heartbeats maintain liveness** -- periodic ping/pong exchanges track connection health and drive TTL refresh.
7. **Close handshake** -- either peer initiates a close frame with a status code; the graceful close state machine drains and acknowledges.
8. **Cleanup** -- the connection is removed from the registry, subscriptions are released, and presence expires.

The connection state transitions are: `Connecting -> Open -> Closing -> Closed`, with `Open` optionally passing through backpressured and reconnecting sub-states.

## Modules

### `src/mod.xi` -- package root
Re-exports the public surface (handshake, connection, message, channel, pubsub) and wires transport submodules.

### `src/server.xi` -- `xiom.websocket.server`
Server-side entry point. Accepts upgrade requests routed from `xiom.http`, produces owned `WebSocketConnection` values, and maintains the local connection registry.

Conceptual surface:
- `server_new(addr: Str, port: Int) -> WebSocketServer`
- `on_connection(server, handler)` -- register a per-connection handler.
- `accept(server, req: HttpRequest) -> Result[WebSocketConnection, HandshakeError]`
- `connections(server) -> &ConnectionRegistry`

### `src/client.xi` -- `xiom.websocket.client`
Client-side connector. Initiates the outbound handshake over an `xiom.net` TCP stream and returns an owned connection.

Conceptual surface:
- `connect(url: Str, opts: ClientOptions) -> Result[WebSocketConnection, ConnectError]`
- `connect_with_subprotocols(url, protocols: Vec[Str]) -> Result[WebSocketConnection, ConnectError]`

### `src/handshake.xi` -- `xiom.websocket.handshake`
The typed HTTP-Upgrade state transition. Validates required headers and computes the accept key.

Conceptual surface:
- `validate_upgrade(req: &HttpRequest) -> Result[Unit, HandshakeError]` -- `requires: req.is_websocket_upgrade()`
- `compute_accept_key(sec_key: Str) -> Str` -- SHA-1 of key + GUID, base64-encoded.
- `build_response(accept_key: Str, subprotocol: Option[Str]) -> HttpResponse`

### `src/upgrade.xi` -- `xiom.websocket.upgrade`
Bridges `xiom.http` request handling into WebSocket mode; detaches the socket from the HTTP pipeline and hands it to the transport layer.

Conceptual surface:
- `upgrade(req: HttpRequest, stream: TcpStream) -> Result[WebSocketConnection, UpgradeError]`
- `is_upgrade_request(req: &HttpRequest) -> Bool`

### `src/frame.xi` -- `xiom.websocket.frame`
Frame codec: encode/decode with masking rules, fragmentation reassembly, control-frame handling, and payload size checks.

Conceptual surface:
- `Frame { fin: Bool; opcode: Opcode; masked: Bool; payload: Vec[Int]; }`
- `frame_decode(bytes: &Vec[Int]) -> Result[Frame, FrameError]`
- `frame_encode(frame: &Frame) -> Vec[Int]`
- `frame_validate(frame: &Frame) -> Result[Unit, FrameError]` -- enforces length and fragmentation contracts.

### `src/opcode.xi` -- `xiom.websocket.opcode`
Opcode enum and classification helpers.

Conceptual surface:
- `Opcode` -- `Continuation`, `Text`, `Binary`, `Close`, `Ping`, `Pong` (reserved ranges rejected).
- `opcode_is_control(op: Opcode) -> Bool`
- `opcode_is_data(op: Opcode) -> Bool`

### `src/close_code.xi` -- `xiom.websocket.close_code`
Close codes and their semantics (normal, going away, protocol error, unsupported data, policy violation, message too big, internal error, etc.).

Conceptual surface:
- `CloseCode` enum with numeric mapping.
- `close_code_is_valid(code: Int) -> Bool`
- `close_code_text(code: CloseCode) -> Str`

### `src/message.xi` -- `xiom.websocket.message`
High-level message type above raw frames, assembled from fragmentation.

Conceptual surface:
- `Message { kind: MessageKind; data: Vec[Int]; seq: UInt; }`
- `MessageKind` -- `Text`, `Binary`.
- `message_from_frames(frames: &Vec[Frame]) -> Result[Message, FrameError]`
- `message_to_frames(msg: &Message, max_frame: Int) -> Vec[Frame]`

### `src/connection.xi` -- `xiom.websocket.connection`
Owns the live socket, send queue, receive loop, heartbeat state, and subscription list. Lifetime is tied to ownership for deterministic cleanup.

Conceptual surface:
- `WebSocketConnection` -- state machine: `Connecting | Open | Closing | Closed`.
- `on_message(conn, handler)`, `on_close(conn, handler)`, `on_error(conn, handler)`
- `send(conn, msg: Message) -> Result[Unit, SendError]`
- `close(conn, code: CloseCode)` -- consumes the connection.

### `src/session.xi` -- `xiom.websocket.session`
Authenticated user/session context, reconnect metadata, last-seen sequence, and presence info.

Conceptual surface:
- `Session { id: SessionId; identity: Identity; last_seq: UInt; presence: PresenceState; }`
- `session_bind(conn, identity: Identity) -> Session`
- `session_touch(session)` -- refresh last-seen.

### `src/heartbeat.xi` -- `xiom.websocket.heartbeat`
Ping/pong logic and liveness timers with typed liveness state.

Conceptual surface:
- `set_interval(conn, ms: Int)`, `set_timeout(conn, ms: Int)`
- `ping(conn)`, `on_pong(conn, handler)`
- `Liveness` -- `Alive | AwaitingPong | Dead`.

### `src/backpressure.xi` -- `xiom.websocket.backpressure`
Send-queue limits, overflow policy, and slow-consumer handling via a bounded queue.

Conceptual surface:
- `OverflowPolicy` -- `DropOldest | DropNewest | CloseConnection | Block`.
- `set_queue_limit(conn, max: Int)`, `set_overflow_policy(conn, policy)`
- `queue_depth(conn) -> Int`

### `src/reconnect.xi` -- `xiom.websocket.reconnect`
Reconnect token handling, resubscription flow, and missed-message recovery using monotonic sequence numbers.

Conceptual surface:
- `issue_token(session: &Session) -> ReconnectToken`
- `resume(token: ReconnectToken, last_seq: UInt) -> Result[Session, ReconnectError]` -- `requires: seq monotonicity`.
- `replay_since(session: &Session, seq: UInt) -> Vec[Message]`

### `src/presence.xi` -- `xiom.websocket.presence`
Tracks who is connected/active/present in a room or channel, with TTL semantics to clear ghosts.

Conceptual surface:
- `PresenceState` -- `Online | Away | Offline`.
- `mark_present(channel, session, ttl_ms: Int)`
- `expire_stale(channel, now: Int)`
- `members(channel) -> Vec[SessionId]`

### `src/channel.xi` -- `xiom.websocket.channel`
Typed room/channel abstraction for point-to-point and fan-out communication.

Conceptual surface:
- `Channel { name: Str; members: ConnectionSet; }`
- `channel(name: Str) -> Channel`
- `subscribe(conn, ch)`, `unsubscribe(conn, ch)`
- `publish(ch, msg: Message)`

### `src/pubsub.xi` -- `xiom.websocket.pubsub`
Backplane interface for distributing messages across processes or nodes; a structural interface with pluggable adapters (Redis, Kafka, NATS).

Conceptual surface:
- `PubSubAdapter` -- structural interface: `publish(topic, payload)`, `subscribe(topic, handler)`.
- `bind_backplane(adapter: PubSubAdapter)`
- `publish_remote(topic: Str, msg: &Message)`

### `src/broadcast.xi` -- `xiom.websocket.broadcast`
Broadcast helpers for local and distributed fan-out.

Conceptual surface:
- `broadcast_local(ch: &Channel, msg: Message)`
- `broadcast_all(server, msg: Message)`
- `broadcast_distributed(topic: Str, msg: Message)` -- local delivery plus backplane publish.

### `src/subprotocol.xi` -- `xiom.websocket.subprotocol`
Negotiation and validation of custom subprotocols.

Conceptual surface:
- `negotiate(offered: &Vec[Str], supported: &Vec[Str]) -> Option[Str]`
- `register(name: Str, spec: SubprotocolSpec)`
- `SubprotocolSpec { name: Str; validate_message; }`

### `src/auth.xi` -- `xiom.websocket.auth`
Authentication hooks for connection establishment and session binding.

Conceptual surface:
- `AuthHook` -- structural interface: `authenticate(req: &HttpRequest) -> Result[Identity, AuthError]`.
- `on_authenticate(server, hook: AuthHook)`
- `bind_session(conn, identity: Identity) -> Session`

### `src/transport/` -- `xiom.websocket.transport`
Isolates socket ownership from protocol logic.

- `transport/mod.xi` -- transport re-exports.
- `transport/http_upgrade_bridge.xi` -- performs the handoff from an `xiom.http` request into a raw duplex socket.
- `transport/websocket_stream.xi` -- wraps the underlying `xiom.net` `TcpStream` with the framed read/write loop consumed by the connection layer.

Conceptual surface:
- `WebSocketStream { inner: TcpStream; read_buf: Vec[Int]; }`
- `read_frame(stream) -> Result[Frame, FrameError]`
- `write_frame(stream, frame: &Frame) -> Result[Unit, SendError]`

## Contract Hotspots

- Valid upgrade request headers (`requires` on `validate_upgrade`).
- Frame length and opcode validity.
- Fragmentation rules (continuation ordering, control frames not fragmented).
- Ping/pong timing constraints.
- Close-state legality (no sends after `Closing`).
- Session identity consistency across reconnect.
- Presence TTL refresh requirements.
- Sequence monotonicity for reconnect recovery (`ensures` seq strictly increasing).

## Implementation Status

| Area | Status |
|------|--------|
| Handshake / upgrade | Planned |
| Frame codec / opcodes / close codes | Planned |
| Connection / session lifecycle | Planned |
| Heartbeat | Planned |
| Backpressure | Planned |
| Reconnect / sequence recovery | Planned |
| Presence | Planned |
| Channels / pub/sub / broadcast | Planned |
| Subprotocols | Planned |
| Auth hooks | Planned |
| Transport bridge | Planned |
