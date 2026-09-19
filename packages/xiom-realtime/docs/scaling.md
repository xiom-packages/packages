# Scaling

> Status: Design stage -- specification only, not yet implemented.

`xiom.realtime` is designed on the assumption that **one node is not enough** for serious realtime workloads. A single instance is fine for development and small deployments, but production realtime -- many rooms, many concurrent connections, cross-region users -- requires the package to work correctly across a cluster from the start. The recommended architecture has five parts, and each maps onto a specific module in the package.

- **Per-node local connection handling.** Each instance terminates its own client WebSocket connections (via `xiom.websocket`) and performs local fan-out to the subscribers it hosts. This keeps the hot path -- socket to subscriber -- on a single machine.
- **Shared pub/sub backplane for cross-node fan-out.** When a room's subscribers are spread across instances, events cross the cluster through a backplane or through `xiom.micro` service integration. The fan-out layer ensures each node receives an event once and then fans it out locally, so no node processes traffic for rooms it does not host.
- **Heartbeat-based presence reconciliation.** Presence is TTL-backed and eventually consistent (see the presence model). Nodes publish heartbeats and reconcile rosters through pub/sub; when a node is lost, its presence entries expire naturally rather than requiring coordinated cleanup.
- **Sequence numbers for reconnect recovery.** Central per-room sequence allocation gives every durable event a well-defined position, which is what makes gap detection, deduplication, and cursor-based replay work uniformly across nodes.
- **Optional durable storage.** Messages that must survive disconnects are persisted through the storage bridge, so replay and history survive both client disconnects and node restarts.

The division of labor is what makes this tractable: `xiom.websocket` handles protocol correctness and connection lifecycle, `xiom.micro` handles the distributed-systems resilience (discovery, backplane transport, failure handling) underneath, and `xiom.realtime` sits in the middle owning the realtime semantics -- rooms, presence, ordering, fan-out policy. Because the correctness-critical decisions (authorization, sequence assignment) are made centrally per room before fan-out, adding nodes scales throughput without weakening the guarantees.

Beyond the baseline, the roadmap notes future scaling work: a durable realtime event log, cross-device sync helpers, richer collaboration primitives, and a multi-region presence strategy. These are explicitly out of scope for the initial design but the layering above is intended to accommodate them.

This document is design-stage guidance; none of the scaling machinery is implemented yet.
