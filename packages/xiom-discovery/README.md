# xiom.discovery

> **Status:** `incubating` -- conformance-tested (22/22); not yet published on the XIOM registry.
> **Scope:** a pure, deterministic in-process service-discovery registry:
> registrations keyed by (name, address, port) with tags and weights,
> heartbeat/TTL bookkeeping on explicit integer ticks, the
> healthy/draining/down health states, the expiry sweep and reap, lookups by
> name and by tag, caller-seeded deterministic weighted selection and
> sequence-numbered change watches. No sockets, no threads, no wall clock,
> no I/O and no FFI.
> **Deps:** `xiom.std` (manifest only). The library module imports only
> `xiom.string`, `xiom.string.compare` and `xiom.string.join`; the tests
> use `xiom.test`, `xiom.io`, `xiom.string.builder` and
> `xiom.string.compare`.

## What it is

`xiom.discovery` is the semantic core that a DNS-SD/mDNS responder, a
Consul-style agent or a load balancer would drive. It is a registry, not a
network service: it never opens sockets, speaks a discovery protocol or runs
a server loop. What it does cover is the bookkeeping such a service needs,
with deterministic rules and exact error strings:

- **registrations**: an instance is the triple (name, address, port) with a
  tag list, a selection weight and a TTL in ticks; the triple is unique;
- **heartbeat / TTL**: heartbeats refresh the remaining TTL on the explicit
  integer clock; `discovery_sweep` ages every live instance and marks the
  ones that reach zero DOWN; DOWN instances stay registered until they are
  deregistered or reaped;
- **health states**: HEALTHY (looked up, selectable), DRAINING (looked up,
  not selectable), DOWN (neither) with one-way and idempotent transitions;
- **lookups**: by exact name, or by name plus one exact tag (delimiter-aware,
  so `blue` never matches `blue2`);
- **weighted selection**: a caller-seeded LCG draws over the eligible
  weights; the same registry and seed always pick the same slot, and heavier
  weights win proportionally;
- **watches**: every mutation appends one change event with a monotonic
  sequence number; a watch is a caller-polled cursor that returns the
  matching events since the last poll;
- **deregistration**: explicit removal of any instance, plus `reap` for
  every DOWN instance in registration order.

See `SPEC.md` for the state machine, the TTL and selection rules and the
exact error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `discovery_new()` | `DiscoveryRegistry` | Empty registry, head sequence 0. |
| `discovery_register(reg, name, address, port, tags, weight, ttl)` | `Result[Int, Str]` | Register a HEALTHY instance; `Ok(slot)`. |
| `discovery_deregister(reg, name, address, port)` | `Result[Bool, Str]` | Remove any instance, emits `deregister`. |
| `discovery_reap(reg)` | `Int` | Remove every DOWN instance; count removed. |
| `discovery_heartbeat(reg, name, address, port)` | `Result[Int, Str]` | Refresh TTL to the granted value; `Ok(ttl)`. |
| `discovery_sweep(reg, ticks)` | `Int` | Age live instances by `ticks`; count expired. |
| `discovery_mark_draining(reg, name, address, port)` | `Result[Bool, Str]` | HEALTHY -> DRAINING (`Ok(true)` once). |
| `discovery_mark_down(reg, name, address, port)` | `Result[Bool, Str]` | HEALTHY/DRAINING -> DOWN. |
| `discovery_mark_healthy(reg, name, address, port)` | `Result[Bool, Str]` | DRAINING/DOWN -> HEALTHY (TTL untouched). |
| `discovery_lookup(reg, name)` | `Vec[Int]` | Live slots with this exact name, in slot order. |
| `discovery_lookup_tag(reg, name, tag)` | `Vec[Int]` | Live slots with this name and exact tag. |
| `discovery_find(reg, name, address, port)` | `Int` | Slot of the triple, or `-1`. |
| `discovery_count(reg)` | `Int` | Registered instances, including DOWN. |
| `discovery_name(reg, index)` | `Str` | Name of slot `index` (`""` out of range). |
| `discovery_address(reg, index)` | `Str` | Address of slot `index` (`""` out of range). |
| `discovery_port(reg, index)` | `Int` | Port of slot `index` (`-1` out of range). |
| `discovery_tags(reg, index)` | `Str` | Comma-joined tags of slot `index` (`""` out of range). |
| `discovery_has_tag(reg, index, tag)` | `Bool` | Exact-tag test on slot `index`. |
| `discovery_weight(reg, index)` | `Int` | Selection weight of slot `index` (`-1` out of range). |
| `discovery_ttl(reg, index)` | `Int` | Granted TTL of slot `index` (`-1` out of range). |
| `discovery_remaining(reg, index)` | `Int` | Ticks left for slot `index` (`-1` out of range). |
| `discovery_state(reg, index)` | `Int` | Health state of slot `index` (`-1` out of range). |
| `discovery_state_name(state)` | `Str` | `"healthy"`, `"draining"`, `"down"`, `"unknown"`. |
| `discovery_lcg_next(state)` | `Int` | One LCG step, normalized into `0..2147483647`. |
| `discovery_select(reg, name, seed)` | `Result[Int, Str]` | Weighted pick over HEALTHY instances of `name`. |
| `discovery_select_tag(reg, name, tag, seed)` | `Result[Int, Str]` | Same, restricted to one exact tag. |
| `discovery_watch(reg, name, tag)` | `Int` | Subscribe from the current head; returns the watch id. |
| `discovery_watch_count(reg)` | `Int` | Watches created (there is no unwatch). |
| `discovery_watch_name(reg, id)` | `Str` | Name filter of a watch (`""` out of range). |
| `discovery_watch_tag(reg, id)` | `Str` | Tag filter of a watch (`""` out of range). |
| `discovery_watch_cursor(reg, id)` | `Int` | Last delivered sequence (`-1` out of range). |
| `discovery_watch_poll(reg, id)` | `Vec[Int]` | Matching change indices since the cursor; advances it. |
| `discovery_change_count(reg)` | `Int` | Events emitted (never truncated). |
| `discovery_last_seq(reg)` | `Int` | Head sequence number (`0` for a fresh registry). |
| `discovery_changes_since(reg, name, after_seq)` | `Vec[Int]` | Change indices with `seq > after_seq`. |
| `discovery_change_seq(reg, index)` | `Int` | Sequence of change `index` (`-1` out of range). |
| `discovery_change_kind(reg, index)` | `Str` | Kind of change `index` (`""` out of range). |
| `discovery_change_name(reg, index)` | `Str` | Service name captured by change `index`. |
| `discovery_change_address(reg, index)` | `Str` | Address captured by change `index`. |
| `discovery_change_port(reg, index)` | `Int` | Port captured by change `index` (`-1` out of range). |
| `discovery_change_tags(reg, index)` | `Str` | Tags captured by change `index`. |
| `discovery_check_invariant(reg)` | `Bool` | Parallel-vector and head-sequence invariant. |

Constants: `DISCOVERY_STATE_HEALTHY` (0), `DISCOVERY_STATE_DRAINING` (1),
`DISCOVERY_STATE_DOWN` (2), `DISCOVERY_DEFAULT_TTL` (30),
`DISCOVERY_LCG_MULTIPLIER` (1664525), `DISCOVERY_LCG_INCREMENT` (1013904223),
`DISCOVERY_LCG_MODULUS` (2147483648), `DISCOVERY_NOT_FOUND` (-1).

Errors are `Err("discovery: ...")` strings; the full catalog is in `SPEC.md`.

## Rules at a glance

- **Identity** is (name, address, port); a duplicate registration is
  refused, and deregister/heartbeat/health transitions address one triple.
- **TTL**: registration grants `ttl` ticks (`remaining = ttl`). A heartbeat
  refreshes `remaining` to the granted TTL. `sweep(ticks)` subtracts `ticks`
  from every live instance; reaching zero marks it DOWN (event `expire`).
  DOWN instances are not aged and never re-expire.
- **States**: HEALTHY -> DRAINING (`drain`), HEALTHY/DRAINING -> DOWN
  (`down`), DRAINING/DOWN -> HEALTHY (`healthy`), DOWN -> HEALTHY also via a
  heartbeat (`revive`). Repeats return `Ok(false)` and emit nothing.
- **Lookups** return live (HEALTHY or DRAINING) slots in registration order.
  Tag matching is exact and delimiter-aware; an empty tag matches nothing.
- **Selection** considers only HEALTHY instances:
  `draw = discovery_lcg_next(seed) % total_weight`, then the first eligible
  slot in registration order whose cumulative weight exceeds `draw`.
  Same registry + seed = same slot; ties resolve to the lower slot.
- **Watches** start at the current head and return only future events.
  A poll jumps the cursor to the head, consuming events the filters
  skipped. `changes_since` is the manual-cursor variant.
- **Change events**: `add`, `renew`, `revive`, `drain`, `healthy`, `down`,
  `expire`, `deregister`, `reap`; each carries the instance data captured at
  emission time, so it survives removal.

## Usage

```xi
use xiom.discovery;

var reg = discovery_new();

// Register two instances of "api" (weights 1 and 3, TTL 5 ticks).
var tags = Vec[Str].new();
tags.push("v1");
tags.push("blue");
let a = discovery_register(&mut reg, "api", "10.0.0.1", 8080, &tags, 1, 5);
let b = discovery_register(&mut reg, "api", "10.0.0.2", 8080, &tags, 3, 5);

// Time passes in explicit ticks; heartbeats refresh the TTL.
discovery_sweep(&mut reg, 4);
let ttl = discovery_heartbeat(&mut reg, "api", "10.0.0.1", 8080);

// Deterministic weighted pick: the same registry and seed pick the same slot.
let pick = discovery_select(&reg, "api", 42);
if pick.is_ok {
  let slot: Int = pick.value;
  let winner: Str = discovery_name(&reg, slot);
}

// Watch changes by sequence number: subscribe, then poll.
let w = discovery_watch(&mut reg, "api", "");
discovery_mark_draining(&mut reg, "api", "10.0.0.2", 8080);
let events: Vec[Int] = discovery_watch_poll(&mut reg, w);
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.discovery
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Model only.** No sockets, no multicast, no mDNS/Bonjour wire format (see
  `xiom.bonjour` for the codec), no cache, no retry and no server loop; the
  transport and the decision to act on a watch are the caller's concern.
- **Single registry value.** There is no global state and no persistence:
  the registry is an ordinary XIOM value, and a concurrent host must
  serialize access itself (no atomics, no locks).
- **Slots shift.** Deregister and reap compact the parallel vectors, so a
  slot index is only stable until the next removal; re-resolve with
  `discovery_find`.
- **Tags are a joined string.** Each instance has one comma-joined tag list;
  tags must be non-empty printable ASCII without `','`. Tag matching is a
  whole-element comparison, not a prefix search.
- **Logical ticks only.** TTLs are integer ticks advanced by `sweep`; there
  is no wall clock and no unit conversion.
- **Selection is deterministic, not secret.** The LCG is caller-seeded for
  reproducibility; do not use it where an adversary must not predict the
  pick.
- **The change log never truncates.** Good for tests and replays; a
  long-running registry that never drains it keeps growing.
- **Flags, not callbacks.** A watch is polled; the library never calls back
  into the caller, and there is no unwatch.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
