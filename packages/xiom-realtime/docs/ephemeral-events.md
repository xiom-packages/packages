# Ephemeral vs Durable Events

> Status: Design stage -- specification only, not yet implemented.

`xiom.realtime` classifies every event explicitly, because chat messages, typing indicators, and presence updates should not share the same lifecycle rules. Treating them uniformly is a common source of realtime bugs -- either typing noise gets persisted forever, or important messages get dropped when a client is briefly offline. Four kinds are defined:

- **Durable** -- events that should be persisted or replayable. These are the messages that must survive a disconnect: chat messages, committed document edits, notifications the user must not miss. Durable events get sequence numbers, are eligible for deduplication, and are stored (via the storage bridge) so the offline/replay path can resend them.
- **Ephemeral** -- events that can be dropped if the client is offline. They are delivered best-effort to currently connected subscribers and are never queued for later replay. If you weren't there to see it, it didn't matter.
- **Presence** -- visibility and membership state updates. These describe *who is here*, and they have their own TTL-backed lifecycle (see the presence model) rather than being stored as a message log.
- **Signal** -- short-lived indicators such as typing or cursor movement. Signals carry a short expiry (TTL) and are the most disposable class: they are relevant for a second or two and then meaningless.

The lifecycle differences follow directly from the classification. Durable events flow through the full ordering + storage + replay pipeline. Ephemeral and signal events skip sequencing and storage entirely -- paying that cost for a typing indicator would be waste -- and are simply fanned out to connected subscribers, expiring on their own. Presence events feed the presence layer's heartbeat/TTL machinery instead of a message log.

This separation is what lets a single room carry a durable chat history *and* live typing indicators *and* an accurate online roster without the three interfering. The **policy** object on a room encodes the retention and expiry rules for each kind, and **event expiry rules** are a contract hotspot: an event's declared kind and TTL are validated so that, for example, a signal cannot accidentally be marked durable or an ephemeral event cannot request unbounded retention.

**Planned surface:** `event_durable`, `event_ephemeral`, `event_presence`, `event_signal`, with typing/signal helpers in `typing.xi` and `activity.xi`. All are design-stage and not yet implemented.
