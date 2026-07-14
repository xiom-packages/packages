# Close Codes

> Design stage — specification only.

Closing a WebSocket is a two-way handshake, not an abrupt socket teardown. Either peer may initiate closure by sending a `Close` control frame carrying a numeric status code and an optional UTF-8 reason. The receiving peer echoes a `Close` frame, and only then is the underlying TCP connection torn down. The `close_code` module defines the status codes and their semantics, and the connection state machine drives the graceful `Open → Closing → Closed` transition.

The standard codes include `1000` (normal closure), `1001` (going away), `1002` (protocol error), `1003` (unsupported data), `1007` (invalid frame payload data), `1008` (policy violation), `1009` (message too big), `1010` (mandatory extension), and `1011` (internal server error). Certain codes are reserved and must never appear on the wire (for example `1005` "no status received" and `1006` "abnormal closure" are status indicators only). The `close_code_is_valid` helper enforces the legal ranges so an application cannot emit a reserved code.

In `xiom-websocket`, once a connection enters the `Closing` state, further `send` calls are rejected by contract — no message may be queued after closure has begun. The send queue is drained or discarded per the configured policy, subscriptions are released, and presence for the session is allowed to expire. This deterministic teardown is what makes connection ownership auditable: a dropped connection always reaches `Closed` and always releases its resources.

Contract hotspots for this stage are close-state legality (no sends after `Closing`), the validity of the emitted status code, and the requirement that a received close is acknowledged before the socket is released.
