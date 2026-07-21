# xiom-websocket Architecture

> **Status: Design stage — specification only, not yet implemented. Depends on xiom-http (upgrade bridge) and xiom-net (TCP transport).**

`xiom-websocket` is the WebSocket extension package for the XIOM ecosystem. It provides WebSocket handshake handling, frame parsing, connection lifecycle management, pub/sub channel abstractions, presence hooks, backpressure controls, and reconnect-oriented session semantics on top of `xiom-http` and `xiom-net`.

The package is intentionally separate from the core HTTP layer because WebSockets are stateful, long-lived connections with protocol-specific rules that should not burden ordinary HTTP applications. In scalable architectures, WebSockets usually need sticky routing plus a pub/sub backplane or message fan-out layer, so the package should make those concerns explicit instead of hiding them.

At the design stage only the manifest and documentation exist; no `.xi` source files are present yet. The scaffold below describes the intended module tree once implementation begins.

## What belongs here

- HTTP upgrade handshake.
- WebSocket frame parsing and serialization.
- Ping/pong heartbeat handling.
- Close codes and graceful shutdown.
- Connection/session lifecycle.
- Subscription management.
- Presence tracking hooks.
- Backpressure and send-queue management.
- Reconnect protocol helpers.
- Broadcast and room/channel abstractions.

## What stays outside

- HTTP server primitives remain in `xiom-http`.
- TCP/UDP transport primitives remain in `xiom-net`.
- REST stays in `xiom-rest`.
- GraphQL execution stays in `xiom-graphql`.
- Microservice discovery stays in `xiom-micro`.
- Realtime app semantics such as chat rooms or collaboration documents stay in `xiom-realtime`.

## Design goals

- Keep protocol handling explicit and testable.
- Support high fan-out without hiding the scaling story.
- Make reconnect behavior and session recovery first-class.
- Keep connection ownership clear and auditable.
- Use XIOM contracts for frame validity, session state, and lifecycle invariants.

## Repository scaffold

```text
xiom-websocket/
├── package.xi
├── README.md
├── ARCHITECTURE.md
├── SPEC.md
├── docs/
│   ├── handshake.md
│   ├── frames.md
│   ├── close-codes.md
│   ├── heartbeat.md
│   ├── reconnect.md
│   ├── presence.md
│   ├── backpressure.md
│   ├── scaling.md
│   └── subprotocols.md
├── src/                        # planned — not yet implemented
│   ├── mod.xi
│   ├── server.xi
│   ├── client.xi
│   ├── handshake.xi
│   ├── upgrade.xi
│   ├── frame.xi
│   ├── opcode.xi
│   ├── close_code.xi
│   ├── message.xi
│   ├── connection.xi
│   ├── session.xi
│   ├── heartbeat.xi
│   ├── backpressure.xi
│   ├── reconnect.xi
│   ├── presence.xi
│   ├── channel.xi
│   ├── pubsub.xi
│   ├── broadcast.xi
│   ├── subprotocol.xi
│   ├── auth.xi
│   ├── transport/
│   │   ├── mod.xi
│   │   ├── http_upgrade_bridge.xi
│   │   └── websocket_stream.xi
│   └── testing/
│       ├── mod.xi
│       ├── frames.xi
│       └── fixtures.xi
└── tests/                      # planned — not yet implemented
    ├── handshake/
    ├── frames/
    ├── lifecycle/
    ├── reconnect/
    ├── presence/
    └── scaling/
```

## Core module responsibilities

### `src/handshake.xi`
Implements the HTTP Upgrade handshake and validates required headers. The handshake should be a strict, typed state transition from HTTP request to WebSocket connection.

### `src/upgrade.xi`
Bridges `xiom-http` request handling into WebSocket mode.

### `src/frame.xi`
Encodes and decodes WebSocket frames, including masking rules, fragmentation, control frames, and payload size checks.

### `src/opcode.xi`
Defines supported opcodes and validation helpers.

### `src/close_code.xi`
Defines close codes and their semantics.

### `src/message.xi`
High-level message type above raw frames.

### `src/connection.xi`
Owns the live socket connection, send queue, receive loop, heartbeat state, and subscription list. Connection lifetime should be explicit and tied to ownership so dropped connections clean up deterministically.

### `src/session.xi`
Represents authenticated user/session context, reconnect metadata, last-seen sequence, and presence info.

### `src/heartbeat.xi`
Ping/pong logic and liveness timers.

### `src/backpressure.xi`
Send-queue limits, overflow policy, and slow-consumer handling.

### `src/reconnect.xi`
Reconnect token handling, resubscription flow, and missed-message recovery helpers.

### `src/presence.xi`
Tracks who is connected, active, or present in a room/channel.

### `src/channel.xi`
Typed room/channel abstraction for point-to-point and fan-out communication.

### `src/pubsub.xi`
Backplane interface for distributing messages across processes or nodes.

### `src/broadcast.xi`
Broadcast helpers for local and distributed fan-out.

### `src/subprotocol.xi`
Negotiation and validation of custom subprotocols.

### `src/auth.xi`
Authentication hooks for connection establishment and session binding.

### `src/transport/`
The transport layer isolates socket ownership from protocol logic. `http_upgrade_bridge.xi` performs the handoff from an `xiom-http` request into a raw duplex socket, and `websocket_stream.xi` wraps the underlying `xiom-net` TCP stream with the framed read/write loop that the connection layer consumes.

## WebSocket protocol responsibilities

`xiom-websocket` should model the protocol as a strict state machine:

1. HTTP request received.
2. Upgrade headers validated.
3. Protocol switched to WebSocket.
4. Frames parsed and validated.
5. Messages routed to handlers or subscriptions.
6. Heartbeats maintain liveness.
7. Close handshake executes gracefully.
8. Connection state cleaned up deterministically.

This reflects the standard RFC 6455 protocol lifecycle: opening handshake, framed duplex messages, ping/pong, and close semantics.

## Scaling model

WebSocket connections are stateful and long-lived, so the package should make scale architecture explicit rather than hiding it behind a single-node abstraction. Real systems usually scale WebSockets with load balancing plus sticky routing, then use a pub/sub backplane such as Redis, Kafka, or NATS for cross-instance fan-out.

That means `xiom-websocket` should expose:

- Local connection registry.
- Message bus abstraction.
- Fan-out adapter interface.
- Sticky-session awareness.
- Sequence numbers for reconnect recovery.
- Presence tracking with TTL semantics.

## XIOM-native design translation

| WebSocket concept | XIOM translation |
|---|---|
| Upgrade handshake | Typed state transition with `requires` validation |
| Frame parsing | Contract-checked codec with explicit payload size limits |
| Ping/pong | Heartbeat module with typed liveness state |
| Close handshake | Graceful close state machine with explicit codes |
| Backpressure | Bounded send queue and typed overflow behavior |
| Reconnect | Sequence-based recovery plus resubscription |
| Presence | TTL-backed explicit presence state |
| Fan-out | Pub/sub adapter behind a structural interface |

## Scaling architecture recommendation

The recommended model for XIOM is:

- Keep each server instance responsible for its live connections.
- Use sticky routing at the load balancer.
- Use a shared pub/sub backplane for inter-instance broadcast.
- Track message sequence numbers so reconnecting clients can ask for missed events.
- Use heartbeat TTLs to clear ghost presence when a node fails silently.

## Example connection flow

```xiom
pub fn handle_upgrade(req: HttpRequest) -> Result[WebSocketConnection, HttpError]
  requires: req.is_websocket_upgrade()
{
  let conn = websocket.accept(req)?
  conn.on_message(handle_message)
  conn.on_close(handle_close)
  return Ok(conn)
}
```

## Subprotocol strategy

`xiom-websocket` should support custom subprotocols via a typed negotiation step. This lets higher-level packages such as `xiom-graphql` subscriptions or `xiom-realtime` rooms reuse the same transport while defining their own message semantics.

## Contract hotspots

- Valid upgrade request headers.
- Frame length and opcode validity.
- Fragmentation rules.
- Ping/pong timing constraints.
- Close-state legality.
- Session identity consistency.
- Presence TTL refresh requirements.
- Sequence monotonicity for reconnect recovery.

## Checklist

### Must-have
- [ ] HTTP upgrade handshake.
- [ ] Frame encode/decode.
- [ ] Connection lifecycle.
- [ ] Ping/pong heartbeat.
- [ ] Close handshake.
- [ ] Subscription/channel abstraction.
- [ ] Auth hook.

### Should-have
- [ ] Backpressure control.
- [ ] Reconnect support.
- [ ] Sequence numbers.
- [ ] Presence tracking.
- [ ] Pub/sub backplane interface.
- [ ] Custom subprotocol negotiation.

### Future
- [ ] Message persistence for recovery.
- [ ] Multi-room fan-out optimizations.
- [ ] Compression extension support.
- [ ] Transport telemetry and adaptive tuning.

## Final recommendation

`xiom-websocket` should be a transport-and-session package, not a real-time application framework. Keep it focused on protocol correctness, connection lifecycle, heartbeat, backpressure, reconnects, and fan-out plumbing, and let `xiom-realtime` or `xiom-graphql` build the higher-level behavior on top.
