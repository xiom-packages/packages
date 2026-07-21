# Presence

> Status: Design stage — specification only, not yet implemented.

**Presence** answers the question "who is currently connected or active?" It is the second layer of the three-layer realtime model, and it is deliberately designed to be **eventually consistent** rather than globally locked. Locking presence across nodes would make it a bottleneck and a single point of failure; instead, `xiom-realtime` follows the pattern mature realtime systems use — heartbeat-based tracking plus pub/sub synchronization — which is accurate enough for user-facing features like online indicators and active-room rosters.

Presence in XIOM is modeled as **TTL-backed state**. When a user joins, they are marked present with an expiry. To stay present, the client (or the server on its behalf) sends periodic **heartbeats** that refresh the TTL. If heartbeats stop — because the client disconnected, crashed, or its node was lost — the TTL lapses and the entry is evicted. This makes presence self-healing: there is no need for a reliable "goodbye" message, because absence of a heartbeat is itself the signal. Presence TTL refresh is a contract hotspot, so the refresh path is guarded to keep TTLs monotonic and prevent stale writes from resurrecting expired presence.

The presence model supports five operations conceptually: join/leave presence events, heartbeat refresh, TTL expiry, reconciliation after reconnect, and node-loss cleanup. **Reconciliation** matters because a reconnecting client may have a different view of the world than the surviving nodes; the presence layer reconciles the client's claimed state against the authoritative roster. **Node-loss cleanup** handles the case where an entire instance disappears — its presence entries expire naturally via TTL and are cleaned up rather than lingering forever.

Presence updates themselves are a distinct **event kind**. They are not durable messages and not free-form signals; they are visibility/membership state updates with their own lifecycle. Keeping presence events separate from chat messages and typing signals means each can have appropriate retention and delivery rules without interfering with the others.

**Planned surface:** `presence_mark_joined`, `presence_heartbeat`, `presence_expire`, `presence_reconcile`, `presence_roster`. All are design-stage and not yet implemented.
