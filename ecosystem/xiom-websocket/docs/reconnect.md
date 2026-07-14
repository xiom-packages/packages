# Reconnect

> Design stage — specification only.

Because WebSocket connections live across unreliable networks, transient drops are normal rather than exceptional. The `reconnect` module makes recovery a **first-class, sequence-based** operation instead of forcing clients to rebuild state from scratch. The design borrows a write-ahead-log discipline: every outbound message carries a **monotonic sequence number**, and the server retains a bounded tail of recent messages per session so a returning client can ask for everything it missed.

When a session is established, the server issues a `ReconnectToken` bound to the session identity. If the connection drops, the client reconnects and calls `resume(token, last_seq)`, presenting the highest sequence number it successfully processed. The server validates the token, confirms **sequence monotonicity** by contract, and replays messages strictly after `last_seq` via `replay_since`. Resubscription to the session's channels happens as part of the same flow, so the client is restored to its prior fan-out topology without duplicate or missed events at the boundary.

This model keeps recovery deterministic. Sequence numbers are strictly increasing per session (`ensures` on the send path), so the gap between `last_seq` and the current head unambiguously identifies the missed range. If the requested range has fallen outside the retained tail, `resume` returns a typed `ReconnectError` and the client is told to perform a full resynchronization rather than receiving a partial, inconsistent replay.

Reconnect is intentionally scoped to transport-and-session recovery. Durable, long-horizon message persistence for recovery is listed as a future capability; the base package guarantees only the bounded in-memory replay tail described here. Contract hotspots are session identity consistency across the reconnect and monotonicity of the sequence numbers used to compute the replay range.
