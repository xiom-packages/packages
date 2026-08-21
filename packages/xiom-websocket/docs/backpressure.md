# Backpressure

> Design stage -- specification only.

A fast producer and a slow consumer are a natural hazard on any long-lived socket: if the application generates messages faster than a client can receive them, an unbounded send buffer will grow until it exhausts memory. The `backpressure` module makes this failure mode explicit by giving every connection a **bounded send queue** with a **typed overflow policy**, so slow-consumer behavior is a deliberate, observable decision rather than a silent memory leak.

Each connection has a configurable queue limit (`set_queue_limit`) and an `OverflowPolicy` chosen from `DropOldest`, `DropNewest`, `CloseConnection`, or `Block`. When the queue reaches its limit the selected policy is applied: drop the stale head, drop the incoming message, terminate the connection with an appropriate close code, or apply backpressure to the producer. The current depth is inspectable via `queue_depth`, which lets applications and telemetry observe pressure before it becomes critical.

Backpressure interacts cleanly with the rest of the protocol. Control frames -- `Ping`, `Pong`, and `Close` -- bypass the data queue so that heartbeat accuracy and graceful shutdown are never starved by a backlog of application messages. This separation ensures that a slow consumer degrades its own data throughput without breaking liveness detection or the close handshake for that connection.

The policy is per-connection because different workloads want different guarantees: a telemetry stream may prefer `DropOldest` to always show the latest value, while a command channel may prefer `Block` or `CloseConnection` to preserve ordering and integrity. Contract hotspots are the queue-limit bound and the well-defined behavior of each overflow policy at the boundary.
