# Presence

> Design stage — specification only.

Presence answers the question "who is connected and active right now?" for a given room or channel. The `presence` module tracks this as **explicit, TTL-backed state** rather than inferring it from connection objects alone, because in a distributed deployment a connection may be owned by a different node than the one asking the question. Each member has a `PresenceState` of `Online`, `Away`, or `Offline`, and an associated expiry.

Presence entries are refreshed by liveness signals: each successful heartbeat `Pong` (and optionally explicit activity) calls `mark_present` with a fresh TTL. A background sweep (`expire_stale`) removes entries whose TTL has lapsed. This TTL discipline is what clears **ghost presence** when a node fails silently — if a server crashes without sending close frames, its members simply stop refreshing and age out, so the rest of the cluster converges to an accurate view without manual cleanup.

Membership queries (`members`) return the current set for a channel and are designed to compose with the pub/sub backplane: presence changes can be published as ordinary messages so that other nodes update their local view. This keeps presence consistent with the same fan-out plumbing used for application messages, rather than introducing a separate, special-cased replication path.

Presence in `xiom-websocket` is a transport-level hook, not a full social-graph feature. It provides the primitives — join, refresh, expire, query — that higher-level packages such as `xiom-realtime` build richer presence semantics on top of. Contract hotspots are the presence TTL refresh requirement and the consistency of session identity used as the presence key.
