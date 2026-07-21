# xiom-realtime

> Application-level realtime for XIOM — channels, rooms, presence, broadcast, ordering, and ephemeral/durable events, built on `xiom-websocket` and `xiom-micro`.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

> Status: Design stage — spec only, not yet implemented.

## Overview

`xiom-realtime` turns low-level transport into user-facing realtime behavior. Where `xiom-websocket` owns protocol correctness and connection lifecycle, `xiom-realtime` owns the semantics products actually reason about: **channels**, **rooms**, **presence**, and **fan-out**.

It models realtime in three layers — a **subscription layer** (who is listening to what), a **presence layer** (who is currently connected or active), and an **event layer** (what gets broadcast, ordered, retained, or dropped). Every rule that matters — membership legality, presence TTL refresh, sequence monotonicity, deduplication windows, and authorization on join/send — is expressed as an XIOM contract rather than left to convention.

## Dependencies

| Package | Role |
|---------|------|
| `xiom-websocket` | Transport: WebSocket handshake, frame handling, connection lifecycle |
| `xiom-micro` | Distributed fan-out: cross-node backplane, service integration, resilience |
| `xiom-std` | Core types, collections, contracts |

Realtime product logic lives here; the protocol and the distributed-systems plumbing stay in their respective packages.

## Planned API Reference

> Everything below is **Planned** — no implementation source exists yet. Signatures are illustrative of the intended surface.

### Channels & Rooms (`xiom.realtime.channel`, `xiom.realtime.room`)
| Function | Description | Status |
|----------|-------------|--------|
| `channel_open(name)` | Open or reference a communication namespace | Planned |
| `channel_close(channel)` | Tear down a channel and its subscriptions | Planned |
| `room_create(name, policy)` | Create a scoped room with rules and fan-out policy | Planned |
| `room_subscribe(user, room_id)` | Subscribe a user to a room | Planned |
| `room_leave(user, room_id)` | Remove a user from a room | Planned |

### Membership & Subscriptions (`xiom.realtime.membership`, `xiom.realtime.subscription`)
| Function | Description | Status |
|----------|-------------|--------|
| `membership_join(user, room_id, role)` | Record a join with role metadata | Planned |
| `membership_leave(user, room_id)` | Record a leave | Planned |
| `membership_roster(room_id)` | List current members and roles | Planned |
| `subscription_add(user, target)` | Add a client subscription | Planned |
| `subscription_remove(user, target)` | Remove a subscription | Planned |

### Presence (`xiom.realtime.presence`)
| Function | Description | Status |
|----------|-------------|--------|
| `presence_mark_joined(user, room_id)` | Mark a user present | Planned |
| `presence_heartbeat(user, room_id)` | Refresh presence TTL | Planned |
| `presence_expire(now)` | Evict presence past TTL | Planned |
| `presence_reconcile(node_id)` | Reconcile after reconnect / node loss | Planned |
| `presence_roster(room_id)` | Current active participants | Planned |

### Broadcast & Fan-out (`xiom.realtime.broadcast`, `xiom.realtime.fanout`)
| Function | Description | Status |
|----------|-------------|--------|
| `broadcast_emit(room_id, event)` | Emit a typed event to a room | Planned |
| `broadcast_to_user(user, event)` | Direct a targeted event | Planned |
| `fanout_local(room_id, event)` | Local-only delivery | Planned |
| `fanout_distributed(room_id, event)` | Backplane / `xiom-micro` delivery | Planned |
| `fanout_select(policy)` | Choose a fan-out strategy | Planned |

### Ordering (`xiom.realtime.ordering`)
| Function | Description | Status |
|----------|-------------|--------|
| `ordering_next_seq(room_id)` | Allocate a monotonic sequence number | Planned |
| `ordering_dedupe(room_id, event_id)` | Check event against a dedupe window | Planned |
| `ordering_cursor(user, room_id)` | Return the replay cursor for reconnect | Planned |

### Events (`xiom.realtime.event`, `xiom.realtime.typing`, `xiom.realtime.activity`)
| Function | Description | Status |
|----------|-------------|--------|
| `event_durable(payload)` | Construct a persistable/replayable event | Planned |
| `event_ephemeral(payload, ttl)` | Construct a droppable, short-lived event | Planned |
| `typing_start(user, room_id)` | Emit a typing signal | Planned |
| `typing_stop(user, room_id)` | Clear a typing signal | Planned |
| `activity_emit(room_id, kind)` | Emit a live activity update | Planned |

### Authorization (`xiom.realtime.auth`)
| Function | Description | Status |
|----------|-------------|--------|
| `auth_can_join(user, room_id)` | Contract-checked join rule | Planned |
| `auth_can_send(user, room_id, event)` | Contract-checked send rule | Planned |
| `auth_can_subscribe(user, target)` | Subscription-change rule | Planned |

### Offline (`xiom.realtime.offline`)
| Function | Description | Status |
|----------|-------------|--------|
| `offline_queue(user, event)` | Queue an event for a disconnected client | Planned |
| `offline_replay(user, cursor)` | Replay queued events on reconnect | Planned |
| `offline_bounds(user)` | Report replay bounds / retention window | Planned |

## Design Documents

- [ARCHITECTURE.md](ARCHITECTURE.md) — canonical package architecture
- [SPEC.md](SPEC.md) — planned module specification
- [docs/channels.md](docs/channels.md) — channel abstraction
- [docs/rooms.md](docs/rooms.md) — rooms, membership, and policies
- [docs/presence.md](docs/presence.md) — TTL-backed presence model
- [docs/fanout.md](docs/fanout.md) — local and distributed fan-out
- [docs/ordering.md](docs/ordering.md) — sequence numbers and dedup
- [docs/ephemeral-events.md](docs/ephemeral-events.md) — durable vs ephemeral lifecycle
- [docs/authorization.md](docs/authorization.md) — join/send/subscription rules
- [docs/offline-sync.md](docs/offline-sync.md) — offline queue and replay
- [docs/scaling.md](docs/scaling.md) — multi-node scaling recommendation

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)

## License

MIT OR Apache-2.0
