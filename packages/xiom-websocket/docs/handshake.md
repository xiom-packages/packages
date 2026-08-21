# Handshake

> Design stage -- specification only.

The WebSocket connection begins as an ordinary HTTP request and is promoted to a framed duplex socket through the RFC 6455 opening handshake. In `xiom-websocket` this promotion is modeled as a **strict, typed state transition** rather than a loose header check. The `handshake` module exposes a `validate_upgrade` step guarded by a `requires` contract, so an invalid or incomplete upgrade request can never produce a live `WebSocketConnection`.

A valid client upgrade request must present `Upgrade: websocket`, `Connection: Upgrade`, a `Sec-WebSocket-Version: 13` header, and a base64 `Sec-WebSocket-Key`. The server computes the response accept token by concatenating the client key with the fixed RFC GUID, hashing with SHA-1, and base64-encoding the result. It then returns `101 Switching Protocols` with the `Sec-WebSocket-Accept` header and, if negotiation succeeded, a single chosen `Sec-WebSocket-Protocol`. Only after this exchange does the socket detach from the HTTP pipeline.

The handoff itself lives in `upgrade.xi` and `transport/http_upgrade_bridge.xi`: `xiom-http` owns the request until the `101` response is written, then transfers ownership of the raw `xiom-net` TCP stream to the transport layer. This keeps HTTP concerns in `xiom-http` and framing concerns in `xiom-websocket`, with a single, auditable transfer point.

Contract hotspots for this stage are the presence and shape of the upgrade headers, the correctness of the computed accept key, and the legality of any negotiated subprotocol. Failures surface as a typed `HandshakeError` and result in a normal HTTP error response -- never a half-open socket.
