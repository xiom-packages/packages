# xiom-realtime — Specification

> **Status: Planned / not implemented.** This document specifies the intended module layout, responsibilities, and conceptual API surface of `xiom-realtime`. No `.xi` implementation source exists yet; signatures are illustrative and subject to change.

## Overview

`xiom-realtime` is the application-level realtime package for the XIOM ecosystem. It layers reusable realtime semantics — channels, rooms, presence, broadcast, ordering, and ephemeral/durable events — on top of `xiom-websocket` (transport) and `xiom-micro` (distributed fan-out).

The design is organized around three layers:

1. **Subscription layer** — who is listening to what.
2. **Presence layer** — who is currently connected or active.
3. **Event layer** — what gets broadcast, ordered, retained, or dropped.

Every legality rule is expressed as an XIOM contract: membership transitions, presence TTL refresh, sequence monotonicity, dedupe windows, event expiry, authorization on join/send, and offline replay bounds.

## Module Map

| Module | File | Layer | Status |
|--------|------|-------|--------|
| Channel | `src/channel.xi` | Subscription | Planned |
| Room | `src/room.xi` | Subscription | Planned |
| Membership | `src/membership.xi` | Subscription | Planned |
| Subscription | `src/subscription.xi` | Subscription | Planned |
| Presence | `src/presence.xi` | Presence | Planned |
| Event | `src/event.xi` | Event | Planned |
| Broadcast | `src/broadcast.xi` | Event | Planned |
| Fan-out | `src/fanout.xi` | Event | Planned |
| Ordering | `src/ordering.xi` | Event | Planned |
| Auth | `src/auth.xi` | Cross-cutting | Planned |
| Typing | `src/typing.xi` | Event (signal) | Planned |
| Activity | `src/activity.xi` | Event | Planned |
| Offline | `src/offline.xi` | Event | Planned |
| Policy | `src/policy.xi` | Cross-cutting | Planned |
| Integration | `src/integration/` | Adapters | Planned |
| Workflows | `src/workflows/` | Composition | Planned |

---

## `src/channel.xi` — Channels *(Planned)*

**Responsibility.** Define a realtime channel as the top-level abstraction for a communication group. A channel is a communication *namespace*; it can map to a chat room, a document session, a notification stream, or any other logical event group. Channels own no persistence themselves — they route.

**Conceptual API.**
- `channel_open(name: Str) -> Channel`
- `channel_close(channel: Channel) -> Result[Unit, RealtimeError]`
- `channel_subscribe(channel: &Channel, sub: Subscription) -> Result[Unit, RealtimeError]`
- `channel_emit(channel: &Channel, event: Event) -> Result[Unit, RealtimeError]`

---

## `src/room.xi` — Rooms *(Planned)*

**Responsibility.** Represent a named realtime room: a *scoped* communication group with explicit membership rules, authorization rules, and a fan-out policy. Rooms are the primary unit products reason about.

**Conceptual API.**
- `room_create(name: Str, policy: Policy) -> Room`
- `room_subscribe(user: &User, room_id: Str) -> Result[Subscription, RealtimeError]` — `requires: user.is_authenticated()`
- `room_leave(user: &User, room_id: Str) -> Result[Unit, RealtimeError]`
- `room_broadcast(room_id: Str, event: Event) -> Result[Unit, RealtimeError]`

---

## `src/membership.xi` — Membership *(Planned)*

**Responsibility.** Track membership changes — joins, leaves, and role metadata — as an explicit, auditable state machine. Membership legality is a contract hotspot: every transition is validated.

**Conceptual API.**
- `membership_join(user: &User, room_id: Str, role: Role) -> Result[Unit, RealtimeError]`
- `membership_leave(user: &User, room_id: Str) -> Result[Unit, RealtimeError]`
- `membership_role(user: &User, room_id: Str) -> Option[Role]`
- `membership_roster(room_id: Str) -> Vec[Member]`

---

## `src/subscription.xi` — Subscriptions *(Planned)*

**Responsibility.** Model client subscriptions to channels and rooms as explicit state with well-defined transitions (subscribe → active → paused → closed). Subscription state transitions are contract-checked.

**Conceptual API.**
- `subscription_add(user: &User, target: Target) -> Result[Subscription, RealtimeError]`
- `subscription_remove(sub: Subscription) -> Result[Unit, RealtimeError]`
- `subscription_state(sub: &Subscription) -> SubscriptionState`

---

## `src/presence.xi` — Presence *(Planned)*

**Responsibility.** Track connected users/participants as **TTL-backed, eventually consistent** state. Presence tolerates node restarts via heartbeat refresh, TTL expiry, reconciliation after reconnect, and node-loss cleanup. Presence TTL refresh is a contract hotspot.

**Conceptual API.**
- `presence_mark_joined(user: &User, room_id: Str)`
- `presence_heartbeat(user: &User, room_id: Str) -> Result[Unit, RealtimeError]`
- `presence_expire(now: Timestamp) -> Vec[PresenceEviction]`
- `presence_reconcile(node_id: Str) -> Result[Unit, RealtimeError]`
- `presence_roster(room_id: Str) -> Vec[Presence]`

---

## `src/event.xi` — Events *(Planned)*

**Responsibility.** Define typed realtime events and their classification. Events are one of four kinds, each with distinct lifecycle rules:

- **Durable** — persisted / replayable.
- **Ephemeral** — droppable if the client is offline.
- **Presence** — visibility and membership state updates.
- **Signal** — short-lived indicators (typing, cursor).

Event expiry rules are a contract hotspot.

**Conceptual API.**
- `event_durable(payload: Bytes) -> Event`
- `event_ephemeral(payload: Bytes, ttl: Duration) -> Event`
- `event_presence(update: PresenceUpdate) -> Event`
- `event_signal(kind: SignalKind, ttl: Duration) -> Event`

---

## `src/broadcast.xi` — Broadcast *(Planned)*

**Responsibility.** Broadcast helpers for local and distributed event delivery. Broadcast is typed event emission bound to a fan-out policy.

**Conceptual API.**
- `broadcast_emit(room_id: Str, event: Event) -> Result[Unit, RealtimeError]`
- `broadcast_to_user(user: &User, event: Event) -> Result[Unit, RealtimeError]`
- `broadcast_with_policy(room_id: Str, event: Event, policy: FanoutPolicy) -> Result[Unit, RealtimeError]`

---

## `src/fanout.xi` — Fan-out *(Planned)*

**Responsibility.** Select the fan-out strategy: local-only, shard-aware, or backplane-assisted. Distributed fan-out routes through a backplane or `xiom-micro` so multiple instances share one logical room without every node processing every event.

**Conceptual API.**
- `fanout_local(room_id: Str, event: Event) -> Result[Unit, RealtimeError]`
- `fanout_distributed(room_id: Str, event: Event) -> Result[Unit, RealtimeError]`
- `fanout_select(policy: FanoutPolicy) -> FanoutStrategy`

---

## `src/ordering.xi` — Ordering & Dedup *(Planned)*

**Responsibility.** Provide sequence numbers, deduplication windows, and replay cursors. Sequence monotonicity and dedupe windows are contract hotspots that keep events from arriving twice, late, or out of order.

**Conceptual API.**
- `ordering_next_seq(room_id: Str) -> Seq` — `ensures: result > previous`
- `ordering_dedupe(room_id: Str, event_id: Str) -> Bool`
- `ordering_cursor(user: &User, room_id: Str) -> Cursor`

---

## `src/auth.xi` — Authorization *(Planned)*

**Responsibility.** Realtime authorization checked at three points — **join**, **send**, and **subscription change** — keeping room access and broadcast rights separate and auditable. All checks are contract-enforced.

**Conceptual API.**
- `auth_can_join(user: &User, room_id: Str) -> Result[Unit, AuthError]`
- `auth_can_send(user: &User, room_id: Str, event: &Event) -> Result[Unit, AuthError]`
- `auth_can_subscribe(user: &User, target: &Target) -> Result[Unit, AuthError]`

---

## `src/typing.xi` — Typing Signals *(Planned)*

**Responsibility.** Typing indicators and other short-lived signals, modeled as ephemeral events with short expiry — never durable, never replayed.

**Conceptual API.**
- `typing_start(user: &User, room_id: Str)`
- `typing_stop(user: &User, room_id: Str)`
- `typing_active(room_id: Str) -> Vec[User]`

---

## `src/activity.xi` — Activity Streams *(Planned)*

**Responsibility.** Live activity streams such as "user is online," "document updated," or "message received." Activity events summarize state changes for UI consumption.

**Conceptual API.**
- `activity_emit(room_id: Str, kind: ActivityKind) -> Result[Unit, RealtimeError]`
- `activity_stream(room_id: Str) -> Stream[Activity]`

---

## `src/offline.xi` — Offline Sync *(Planned)*

**Responsibility.** Offline queue and replay hooks for clients that reconnect after being disconnected. Offline replay bounds are a contract hotspot: replay is cursor-driven and retention-bounded, and only durable events are eligible.

**Conceptual API.**
- `offline_queue(user: &User, event: Event) -> Result[Unit, RealtimeError]`
- `offline_replay(user: &User, cursor: Cursor) -> Result[Vec[Event], RealtimeError]`
- `offline_bounds(user: &User) -> ReplayBounds`

---

## `src/policy.xi` — Policies *(Planned)*

**Responsibility.** Policy objects for message retention, fan-out scope, presence TTL, and event expiry. Policies make lifecycle rules explicit and reusable across rooms.

**Conceptual API.**
- `policy_new() -> Policy`
- `policy_retention(policy: &mut Policy, dur: Duration)`
- `policy_presence_ttl(policy: &mut Policy, ttl: Duration)`
- `policy_fanout_scope(policy: &mut Policy, scope: FanoutScope)`

---

## `src/integration/` — Integration Bridges *(Planned)*

**Responsibility.** Adapters connecting realtime semantics to the surrounding ecosystem.

| File | Responsibility |
|------|----------------|
| `integration/websocket_bridge.xi` | Bind subscriptions/broadcast to `xiom-websocket` connections and frames |
| `integration/micro_bridge.xi` | Route distributed fan-out and presence sync through `xiom-micro` |
| `integration/storage_bridge.xi` | Persist durable events for replay via an optional storage layer |

---

## `src/workflows/` — Reusable Workflows *(Planned)*

**Responsibility.** Higher-level, opinionated compositions of the primitives above.

| File | Responsibility |
|------|----------------|
| `workflows/chat.xi` | Chat rooms: durable messages, typing signals, presence rosters |
| `workflows/collaboration.xi` | Document collaboration: ordered edits, cursors, activity |
| `workflows/notifications.xi` | Notification streams: targeted delivery, offline queueing |

---

## Contract Hotspots

- Membership legality.
- Subscription state transitions.
- Presence TTL refresh.
- Event expiry rules.
- Sequence monotonicity.
- Deduplication windows.
- Authorization on send/join.
- Offline replay bounds.
