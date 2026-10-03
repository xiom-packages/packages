# xiom.websocket

> **Status:** `incubating` -- conformance-tested (10/10); published at `v0.1.0` on the XIOM registry.
> **Scope:** WebSocket client/server with RFC 6455 framing.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `websocket-client` | WebSocket client connecting to remote endpoints. |
| `websocket-server` | WebSocket server accepting and hosting connections. |
| `frame` | Frame encode/decode with masking and fragmentation. |
| `handshake` | HTTP upgrade and Sec-WebSocket-Key validation. |
| `ping-pong` | Heartbeat via ping/pong control frames. |
