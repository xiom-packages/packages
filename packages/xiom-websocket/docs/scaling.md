# Scaling

> Design stage -- specification only.

WebSocket connections are stateful and long-lived, which makes them fundamentally different to scale than stateless HTTP requests. `xiom-websocket` deliberately makes the scaling story **explicit** rather than hiding it behind a single-node abstraction that quietly breaks under load. Real systems scale WebSockets with load balancing plus **sticky routing**, then use a **pub/sub backplane** -- Redis, Kafka, NATS, or similar -- for cross-instance fan-out.

The recommended architecture for XIOM is:

- **Each server instance owns its live connections.** The `connection` registry is local; a node is authoritative only for the sockets it holds.
- **Sticky routing at the load balancer.** A client's traffic returns to the node holding its connection, so per-connection state (send queue, session, heartbeat) stays local and hot.
- **A shared pub/sub backplane for inter-instance broadcast.** When a message must reach subscribers on other nodes, it is published to the backplane and each node delivers it to its local subscribers. The `pubsub` module defines this as a structural `PubSubAdapter` interface so the transport (Redis/Kafka/NATS) is pluggable.
- **Message sequence numbers for recovery.** Monotonic per-session sequence numbers let a reconnecting client request exactly the events it missed, independent of which node it lands on.
- **Heartbeat TTLs to clear ghost presence.** When a node fails silently, its members age out of presence via TTL expiry, so the cluster converges without manual intervention.

To support this, the package exposes a local connection registry, a message-bus abstraction, a fan-out adapter interface, sticky-session awareness, sequence numbers, and TTL-based presence. The division of labor is clear: `xiom-websocket` provides the fan-out plumbing and the primitives for horizontal scale, while the deployment topology (load balancer configuration, backplane choice, capacity planning) remains an operational concern. Higher-level realtime semantics build on top in `xiom-realtime` and `xiom-graphql`.
