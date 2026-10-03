# xiom.realtime

> **Status:** `incubating` -- conformance-tested (10/10); not yet published.
> **Scope:** Application-level realtime -- channels, rooms, presence, broadcast, ordering, ephemeral/durable events.
> **Deps:** stdlib; xiom.websocket, xiom.micro.

## Libs inventory

| Lib | Description |
|-----|-------------|
| `realtime/clock` | Monotonic and deadline-aware clock abstractions |
| `realtime/loop` | Tick-based event and update loop primitives |
| `realtime/task` | Deferred and periodic task scheduling |
