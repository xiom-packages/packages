# Fan-out

> Status: Design stage — specification only, not yet implemented.

**Fan-out** is the act of taking a single emitted event and delivering it to every subscriber that should receive it. `xiom-realtime` treats fan-out as an explicit, policy-driven decision rather than an implementation detail, because the right strategy depends entirely on scale and topology.

Two modes are supported. **Local fan-out** delivers an event to the subscribers connected to the current node. It is fast, involves no network hop beyond the client sockets, and is sufficient when a room's participants all happen to be connected to the same instance. **Distributed fan-out** is used when a logical room spans multiple instances. In distributed mode, events are routed through a backplane or through `xiom-micro` service integration, so that every node hosting a subscriber receives the event exactly once and then performs its own local fan-out to its connected clients. The crucial property is that no node is forced to process every event for every room — only the events for rooms it actually hosts subscribers for.

The **fan-out policy** attached to a room (or channel) selects the strategy: local-only, shard-aware, or backplane-assisted. Shard-aware fan-out lets rooms be partitioned across nodes deterministically, so a given room's traffic is concentrated where its subscribers are. Backplane-assisted fan-out uses `xiom-micro` as the cross-node transport, decoupling the realtime layer from any single message broker.

Fan-out is intentionally kept downstream of ordering and authorization. By the time the fan-out layer sees an event it has already been assigned a sequence number and passed the send authorization check, so fan-out can focus purely on efficient, correct delivery. This layering is what keeps the distributed case tractable: the hard correctness questions (who may send, what order events take) are answered once, centrally, before the event is scattered across the cluster.

**Planned surface:** `fanout_local`, `fanout_distributed`, `fanout_select`, driven by the `FanoutPolicy` in `policy.xi`. All are design-stage and not yet implemented.
