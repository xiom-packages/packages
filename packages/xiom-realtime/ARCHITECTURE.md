# xiom.realtime Architecture

> **Status: Design stage -- specification only, not yet implemented. Depends on `xiom.websocket` (transport) and `xiom.micro` (distributed fan-out).**

`xiom.realtime` is the application-level realtime package for the XIOM ecosystem. It sits above `xiom.websocket` and turns low-level transport, pub/sub fan-out, and presence mechanics into reusable realtime building blocks such as channels, rooms, subscriptions, typing indicators, live updates, and broadcast orchestration.

The package is intentionally separate from transport because realtime product logic is not the same thing as sockets. `xiom.websocket` owns protocol correctness and connection lifecycle; `xiom.realtime` owns the user-facing realtime semantics that sit on top of that transport.

## What belongs here

- Channel and room abstractions.
- Room membership and subscription state.
- Broadcast orchestration.
- Presence tracking and reconciliation.
- Typing indicators and ephemeral events.
- Live activity streams.
- Offline queueing hooks.
- Event ordering metadata.
- Fan-out policies.
- Realtime authorization rules.
- Integration with `xiom.websocket` and `xiom.micro`.

## What stays outside

- WebSocket handshake and frame handling stay in `xiom.websocket`.
- HTTP transport stays in `xiom.http`.
- REST stays in `xiom.rest`.
- GraphQL stays in `xiom.graphql`.
- Service discovery and resilience stay in `xiom.micro`.

## Design goals

- Keep realtime semantics reusable across products.
- Model rooms and subscriptions explicitly.
- Make presence eventually consistent but predictable.
- Support fan-out at local and distributed scale.
- Keep ephemeral events separate from durable messages.
- Enforce realtime rules with XIOM contracts.

## Repository scaffold

```text
xiom-realtime/
|-- package.xi
|-- README.md
|-- ARCHITECTURE.md
|-- SPEC.md
|-- docs/
|   |-- channels.md
|   |-- rooms.md
|   |-- presence.md
|   |-- fanout.md
|   |-- ordering.md
|   |-- ephemeral-events.md
|   |-- authorization.md
|   |-- offline-sync.md
|   `-- scaling.md
|-- src/
|   |-- mod.xi
|   |-- channel.xi
|   |-- room.xi
|   |-- membership.xi
|   |-- subscription.xi
|   |-- presence.xi
|   |-- event.xi
|   |-- broadcast.xi
|   |-- fanout.xi
|   |-- ordering.xi
|   |-- auth.xi
|   |-- typing.xi
|   |-- activity.xi
|   |-- offline.xi
|   |-- policy.xi
|   |-- integration/
|   |   |-- mod.xi
|   |   |-- websocket_bridge.xi
|   |   |-- micro_bridge.xi
|   |   `-- storage_bridge.xi
|   |-- workflows/
|   |   |-- mod.xi
|   |   |-- chat.xi
|   |   |-- collaboration.xi
|   |   `-- notifications.xi
|   `-- testing/
|       |-- mod.xi
|       |-- fixtures.xi
|       `-- fake_bus.xi
`-- tests/
    |-- channels/
    |-- presence/
    |-- ordering/
    |-- fanout/
    `-- offline/
```

> The `src/` and `tests/` trees describe the **planned** module layout. This package is design-stage: no `.xi` implementation source exists yet.

## Core module responsibilities

### `src/channel.xi`
Defines a realtime channel as the top-level abstraction for communication groups. Channels can map to chat rooms, document sessions, notification streams, or any other event group.

### `src/room.xi`
Represents a named realtime room with membership rules, authorization rules, and fan-out policies.

### `src/membership.xi`
Tracks membership changes, joins, leaves, and role metadata.

### `src/subscription.xi`
Models client subscriptions to channels and rooms.

### `src/presence.xi`
Tracks connected users or participants. Presence should be eventually consistent and tolerant of node restarts, similar to the way distributed realtime systems commonly use pub/sub plus tracker-style state synchronization.

### `src/event.xi`
Defines typed realtime events, including durable and ephemeral variants.

### `src/broadcast.xi`
Broadcast helpers for local and distributed event delivery.

### `src/fanout.xi`
Fan-out strategy selection, including local-only, shard-aware, or backplane-assisted distribution.

### `src/ordering.xi`
Sequence numbers, deduplication, and ordering metadata.

### `src/auth.xi`
Realtime authorization checks for joins, sends, and privileged room actions.

### `src/typing.xi`
Typing indicators and other short-lived signals.

### `src/activity.xi`
Live activity streams such as "user is online," "document updated," or "message received."

### `src/offline.xi`
Offline queue and replay hooks for clients that reconnect after being disconnected.

### `src/policy.xi`
Policy objects for message retention, fan-out scope, presence TTL, and event expiry.

### `src/integration/`
Bridges to `xiom.websocket`, `xiom.micro`, and optionally storage layers for durable event persistence.

### `src/workflows/`
Higher-level reusable realtime workflows such as chat, collaboration, and notifications.

## Realtime model

`xiom.realtime` should think in terms of three layers:

1. **Subscription layer** -- who is listening to what.
2. **Presence layer** -- who is currently connected or active.
3. **Event layer** -- what gets broadcast, ordered, retained, or dropped.

This mirrors the way mature realtime systems separate channel delivery, presence tracking, and cluster-wide pub/sub fan-out.

## Presence model

Presence should be eventually consistent rather than globally locked. In practice, realtime systems often use heartbeat-based tracking plus pub/sub sync to keep presence accurate enough for user-facing features like online indicators and active-room rosters.

The package should support:

- Join/leave presence events.
- Heartbeat refresh.
- TTL expiry.
- Reconciliation after reconnect.
- Node-loss cleanup.

## Event model

Realtime events should be explicitly classified:

- **Durable** -- should be persisted or replayable.
- **Ephemeral** -- can be dropped if the client is offline.
- **Presence** -- state updates for visibility and membership.
- **Signal** -- short-lived indicators like typing or cursor movement.

This separation keeps chat messages, typing events, and presence updates from sharing the same lifecycle rules.

## Fan-out model

`xiom.realtime` should support both local fan-out and distributed fan-out. In distributed mode, events are routed through a backplane or through `xiom.micro` service integrations so multiple instances can share the same logical room without forcing every node to process every event.

## Ordering and deduplication

Realtime systems often fail when events arrive twice, late, or out of order. `xiom.realtime` should therefore include explicit ordering metadata, dedupe windows, and replay cursors for reconnect flows.

## Authorization model

Realtime authorization should be checked at three points:

- On join.
- On send.
- On subscription changes.

That keeps room access and broadcast rights separate and auditable.

## XIOM-native design translation

| Realtime concept | XIOM translation |
|---|---|
| Channel | Structural type representing a communication namespace |
| Room | Scoped communication group with explicit rules |
| Presence | TTL-backed eventually consistent state |
| Broadcast | Typed event emission with fan-out policy |
| Typing indicator | Ephemeral event with short expiry |
| Ordering | Sequence metadata with deduplication |
| Offline sync | Replay cursor plus queued event policy |
| Authorization | Contract-checked join/send rules |

## Example workflow

```xiom
pub fn join_room(ctx: &RealtimeContext, room_id: Str) -> Result[Subscription, RealtimeError]
  requires: ctx.user.is_authenticated()
{
  room.auth.can_join(ctx.user, room_id)?
  let sub = room.subscribe(ctx.user, room_id)?
  presence.mark_joined(ctx.user, room_id)
  return Ok(sub)
}
```

## Scaling recommendation

The package should assume that one node is not enough for serious realtime workloads. A practical architecture is:

- per-node local connection handling,
- shared pub/sub backplane for cross-node fan-out,
- heartbeat-based presence reconciliation,
- sequence numbers for reconnect recovery,
- optional durable storage for messages that must survive disconnects.

## Contract hotspots

- Membership legality.
- Subscription state transitions.
- Presence TTL refresh.
- Event expiry rules.
- Sequence monotonicity.
- Deduplication windows.
- Authorization on send/join.
- Offline replay bounds.

## Checklist

### Must-have
- [ ] Channel and room abstractions.
- [ ] Membership and subscription tracking.
- [ ] Presence tracking.
- [ ] Broadcast and fan-out.
- [ ] Authorization rules.
- [ ] Event typing and classification.

### Should-have
- [ ] Typing indicators.
- [ ] Sequence ordering.
- [ ] Dedupe windows.
- [ ] Offline replay hooks.
- [ ] Distributed fan-out integration.

### Future
- [ ] Durable realtime event log.
- [ ] Cross-device sync helpers.
- [ ] Rich collaboration primitives.
- [ ] Multi-region presence strategy.

## Final recommendation

`xiom.realtime` should be the package that turns transport into user-facing realtime behavior. Keep it centered on channels, rooms, presence, fan-out, ordering, and ephemeral/durable event semantics, while letting `xiom.websocket` handle the actual protocol and `xiom.micro` handle the distributed-system resilience underneath.
