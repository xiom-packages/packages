# Offline Sync

> Status: Design stage -- specification only, not yet implemented.

Clients disconnect -- networks drop, tabs sleep, phones lose signal -- and then they come back. **Offline sync** is the part of `xiom.realtime` that makes reconnection seamless: a client that was gone for thirty seconds should return to a consistent view without the user noticing the gap. This is expressed in XIOM as a **replay cursor plus a queued-event policy**.

The mechanism builds directly on the ordering layer. Every durable event a client processes advances that client's **cursor** -- the sequence number of the last event it successfully consumed. While a client is disconnected, durable events destined for it can be **queued** (subject to the room's retention policy). On reconnect, the replay path reads the client's cursor and resends exactly the durable events with a higher sequence number, in order. Because ordering guarantees monotonic sequences and the dedupe window catches repeats, replay is gap-free and duplicate-free by construction.

Not everything is replayed. Only **durable** events are eligible; ephemeral events and signals are best-effort by definition and were dropped the moment the client went offline, so there is nothing to catch up on -- replaying stale typing indicators or cursor movements would be noise. Presence is reconciled separately through the presence layer's reconnect reconciliation rather than through message replay. This keeps the offline queue focused and bounded: it holds the messages that actually needed to survive the disconnect.

**Offline replay bounds** are a contract hotspot. Replay is not unlimited -- a client that has been gone for a week should not expect to replay a week of history. Each user has explicit **replay bounds** derived from the room's retention policy, and the replay path is contract-guarded so it never attempts to serve events outside those bounds. When a client is beyond the replay window, it is told to resynchronize from a fresh snapshot rather than replaying, which prevents unbounded memory use and unbounded catch-up work.

**Planned surface:** `offline_queue`, `offline_replay`, `offline_bounds`, coordinating with `ordering_cursor` and the storage bridge. All are design-stage and not yet implemented.
