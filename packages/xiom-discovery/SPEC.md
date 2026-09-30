# xiom.discovery -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.discovery` (`src/discovery.xi`). Manifest: `package.xi` (name
`xiom.discovery`, version `0.1.0`). `xiom.std` is a manifest dependency; the
library module imports `xiom.string`, `xiom.string.compare` and
`xiom.string.join`, and the tests use `xiom.test`, `xiom.io`,
`xiom.string.builder` and `xiom.string.compare`.

Conformance: 22 checks in `tests/test_conformance.xi`
(`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`).

## 1. Scope

A pure, deterministic in-process service-discovery registry -- the semantic
core that a DNS-SD/mDNS responder, a Consul-style agent or a load balancer
would drive:

- registration of instances keyed by (name, address, port) with tags, a
  selection weight and a TTL in integer ticks;
- health states HEALTHY / DRAINING / DOWN with explicit transitions;
- heartbeat/TTL bookkeeping and an expiry sweep;
- explicit deregistration and bulk reaping of DOWN instances;
- lookups by exact name and by name plus one exact tag;
- deterministic, caller-seeded weighted selection;
- a sequence-numbered change log with caller-polled watches.

No threads, no atomics, no locks, no wall clock, no I/O, no FFI, no global
state. The library owns semantics only; a backend owns transport, timers
and concurrency.

## 2. Non-goals

- Wire protocols. mDNS/DNS-SD message encoding lives in `xiom.bonjour`;
  this package never emits or parses bytes.
- Sockets, multicast membership, network I/O of any kind.
- Real-time TTLs. Ticks are logical integers the caller advances; the
  library never reads a clock.
- Persistence, serialization, snapshotting.
- Atomicity or memory ordering; the value follows ordinary XIOM move/borrow
  rules and a concurrent host must serialize access.
- Callbacks. A watch is polled by the caller; the library never calls back
  and there is no unwatch.
- Tag hierarchies, globbing or prefix matching.

## 3. State

```xi
pub type DiscoveryRegistry = {
  names: Vec[Str];           // service name (printable ASCII, non-empty)
  addresses: Vec[Str];       // host address text (printable ASCII, non-empty)
  ports: Vec[Int];           // 1..65535
  tags: Vec[Str];            // comma-joined tag list; "" = no tags
  weights: Vec[Int];         // 1..65535
  ttls: Vec[Int];            // granted TTL, >= 1 tick
  remaining: Vec[Int];       // ticks left, 0 while DOWN
  states: Vec[Int];          // DISCOVERY_STATE_HEALTHY | DRAINING | DOWN
  seq: Int;                  // head change sequence (0 = no changes)
  change_seqs: Vec[Int];     // sequence of each change, 1..seq, no gaps
  change_kinds: Vec[Str];    // event kind (see section 9)
  change_names: Vec[Str];    // service name captured at emission
  change_addresses: Vec[Str];// address captured at emission
  change_ports: Vec[Int];    // port captured at emission
  change_tags: Vec[Str];     // tag list captured at emission
  watch_names: Vec[Str];     // watch name filter ("" = all names)
  watch_tags: Vec[Str];      // watch tag filter ("" = all tags)
  watch_cursors: Vec[Int];   // last delivered sequence per watch
}
```

The eight registration vectors are parallel and share one length; the six
change-log vectors share one length equal to `seq`; the three watch vectors
share one length. `discovery_check_invariant` verifies all of this in O(1).
Every field is an implementation detail: callers go through the
`discovery_*` free functions.

## 4. Instance identity and registration

Identity is the triple (name, address, port). `discovery_register` validates
in this exact order and refuses on the first violation, leaving the registry
unchanged:

| # | Condition | Err |
|---|---|---|
| 1 | `name.len() == 0` | `discovery: empty name` |
| 2 | name has a byte outside 0x20..0x7E | `discovery: name not printable` |
| 3 | `address.len() == 0` | `discovery: empty address` |
| 4 | address has a byte outside 0x20..0x7E | `discovery: address not printable` |
| 5 | `port < 1 || port > 65535` | `discovery: port out of range` |
| 6 | `weight < 1 || weight > 65535` | `discovery: weight out of range` |
| 7 | `ttl < 1` | `discovery: ttl must be >= 1` |
| 8 | a tag is empty | `discovery: empty tag` |
| 8 | a tag has a byte outside 0x20..0x7E | `discovery: tag not printable` |
| 8 | a tag contains `','` (0x2C) | `discovery: tag contains ','` |
| 9 | the triple is already registered | `discovery: duplicate registration` |

Step 8 checks the tags in list order, and within a tag in order empty /
printable / comma as listed. Step 9 ignores tags, weight and TTL: the
first registration of a triple wins. On success the instance is appended in
the HEALTHY state with `remaining = ttl`, one `add` change is emitted
(seq = previous head + 1), and the new slot index is returned as `Ok(slot)`.
Slots are the index into the registration vectors; they shift after any
removal (section 6).

## 5. Health states and transitions

| From | Operation | To | Event | Result |
|---|---|---|---|---|
| HEALTHY | `discovery_mark_draining` | DRAINING | `drain` | `Ok(true)` |
| DRAINING | `discovery_mark_draining` | DRAINING | none | `Ok(false)` |
| DOWN | `discovery_mark_draining` | DOWN | none | `Err("discovery: instance is down")` |
| HEALTHY | `discovery_mark_down` | DOWN | `down` | `Ok(true)` |
| DRAINING | `discovery_mark_down` | DOWN | `down` | `Ok(true)` |
| DOWN | `discovery_mark_down` | DOWN | none | `Ok(false)` |
| DRAINING | `discovery_mark_healthy` | HEALTHY | `healthy` | `Ok(true)` |
| DOWN | `discovery_mark_healthy` | HEALTHY | `healthy` | `Ok(true)` |
| HEALTHY | `discovery_mark_healthy` | HEALTHY | none | `Ok(false)` |
| DOWN | `discovery_heartbeat` | HEALTHY | `revive` | `Ok(ttl)` |
| HEALTHY/DRAINING | `discovery_heartbeat` | unchanged | `renew` | `Ok(ttl)` |

All three transition functions return `Err("discovery: unknown instance")`
for an unregistered triple. `discovery_mark_healthy` never touches the
remaining TTL; only registration and heartbeat set `remaining`. DOWN is not
terminal: a heartbeat or `mark_healthy` revives the instance.

## 6. Heartbeat, sweep, deregistration, reap

- `discovery_heartbeat(reg, name, address, port)` resolves the triple,
  sets `remaining = ttls[slot]`, emits `revive` (was DOWN) or `renew`
  (otherwise), and returns `Ok(ttl)`.
- `discovery_sweep(reg, ticks)`:
  - `ticks <= 0` is a no-op returning 0;
  - every not-DOWN instance is visited in registration order:
    `remaining -= ticks`; when the new value would be `<= 0` it becomes 0,
    the state becomes DOWN and an `expire` event is emitted;
  - DOWN instances are skipped (not aged, no repeat events);
  - returns the number expired in this sweep.
  - One sweep therefore emits at most one event per instance, in
    registration order (sub-tick ordering inside a multi-tick window is not
    modeled).
- `discovery_deregister(reg, name, address, port)` removes the instance in
  any state (including DOWN), emits `deregister` with the data captured
  before removal, compacts the parallel vectors, and returns `Ok(true)`.
  Unknown triples are `Err("discovery: unknown instance")`.
- `discovery_reap(reg)` removes every DOWN instance in registration order
  (one `reap` event each, ascending slots) and returns the number removed.
  Live instances are untouched; reaping again with nothing down returns 0.

Slots after a removed slot shift down by one. Any index previously obtained
from `discovery_register`, `discovery_find`, a lookup or a selection must be
re-resolved with `discovery_find` after a deregister or reap.

## 7. Lookups and tag matching

- `discovery_lookup(reg, name)` returns the slots of the live (HEALTHY or
  DRAINING) instances whose name equals `name` byte-for-byte, in registration
  order; empty for an unknown name. DOWN instances are excluded.
- `discovery_lookup_tag(reg, name, tag)` is the same with the additional
  requirement that the slot's joined tag list contains `tag` as a whole
  element.
- Tag matching is delimiter-aware: the joined list `"a,bc"` matches `"a"` and
  `"bc"`, never `"b"` or `"abc"`. An empty tag matches nothing (in both the
  lookup and the selection APIs).
- `discovery_has_tag(reg, index, tag)` applies the same rule to one slot.
- `discovery_tags(reg, index)` exposes the joined list for display.

## 8. Deterministic weighted selection

`discovery_select(reg, name, seed)` and
`discovery_select_tag(reg, name, tag, seed)`:

1. A slot is *eligible* when its name equals `name`, its state is HEALTHY,
   and (for `select_tag`, with `tag` non-empty) it carries `tag`.
   `select_tag` with an empty tag has no eligible slots by definition.
2. `total` is the sum of the eligible weights. If there are no eligible
   slots the result is `Err("discovery: no eligible instance")`.
3. `draw = discovery_lcg_next(seed) % total`.
4. The eligible slots are walked in registration order; the first slot whose
   cumulative weight exceeds `draw` (`draw < acc`) wins. Ties therefore
   resolve to the lowest slot, and no state is consumed: calling again with
   the same seed returns the same slot.

`discovery_lcg_next(state)` is the Numerical Recipes LCG normalized to
31 bits: `s = state mod 2^31` (made non-negative), then
`s' = (1664525 * s + 1013904223) mod 2^31` (made non-negative); the result
is in `0..2147483647`. Pins: `lcg(0) = 1013904223`, `lcg(1) = 1015568748`,
`lcg(2) = 1017233273`, `lcg(42) = 1083814273`, `lcg(-1) = 1012239698`,
`lcg(2147483648) = lcg(0)`.

Pin for the fixture weights 1, 2, 3 (slots 0, 1, 2; `select("api", seed)`):
seed 0 -> slot 1, seed 1 -> slot 0, seed 2 -> slot 2, seed 42 -> slot 1,
seed 100 -> slot 2.

## 9. Watches and the change log

Every mutation appends exactly one change event `{seq, kind, name, address,
port, tags}` with `seq = previous head + 1` starting at 1. Sequence numbers
never repeat and never have gaps; events are never removed.

| Kind | Emitted by |
|---|---|
| `add` | `discovery_register` |
| `renew` | `discovery_heartbeat` on a not-DOWN instance |
| `revive` | `discovery_heartbeat` on a DOWN instance |
| `drain` | `discovery_mark_draining` (HEALTHY -> DRAINING) |
| `healthy` | `discovery_mark_healthy` (DRAINING/DOWN -> HEALTHY) |
| `down` | `discovery_mark_down` |
| `expire` | `discovery_sweep` reaching zero |
| `deregister` | `discovery_deregister` |
| `reap` | `discovery_reap` per removed instance |

Each event captures the instance data *at emission time*; the data of
removed instances survives in the log.

- `discovery_watch(reg, name, tag) -> id` appends a subscription whose
  cursor is the current head sequence (past events are never replayed) and
  returns its id. Filters: `name == ""` matches every name; `tag == ""`
  matches every event; otherwise the event's name must be equal and its
  captured tag list must contain the tag as a whole element.
- `discovery_watch_poll(reg, id)` returns the indices of the events with
  `seq > cursor` that match the watch's filters, in sequence order, and then
  sets the cursor to the current head sequence. Events that the filters
  skipped are consumed, not replayed. An unknown id returns an empty list
  and changes nothing.
- `discovery_changes_since(reg, name, after_seq)` is the stateless variant:
  indices of events with `seq > after_seq` (and, when `name` is non-empty,
  exactly that name). It never moves a cursor.
- `discovery_change_*` accessors expose the log; `discovery_last_seq` is the
  head. `discovery_watch_count` never decreases (there is no unwatch).

## 10. Error catalog

| Err string | Produced by |
|---|---|
| `discovery: empty name` | register |
| `discovery: name not printable` | register |
| `discovery: empty address` | register |
| `discovery: address not printable` | register |
| `discovery: port out of range` | register |
| `discovery: weight out of range` | register |
| `discovery: ttl must be >= 1` | register |
| `discovery: empty tag` | register |
| `discovery: tag not printable` | register |
| `discovery: tag contains ','` | register |
| `discovery: duplicate registration` | register |
| `discovery: unknown instance` | heartbeat, deregister, mark_draining, mark_down, mark_healthy |
| `discovery: instance is down` | mark_draining |
| `discovery: no eligible instance` | select, select_tag |

## 11. Accessor sentinels

Out-of-range indices never panic:

| Accessor | Out of range |
|---|---|
| `discovery_name`, `discovery_address`, `discovery_tags` | `""` |
| `discovery_port`, `discovery_weight`, `discovery_ttl`, `discovery_remaining` | `-1` (`DISCOVERY_NOT_FOUND`) |
| `discovery_state` | `-1` |
| `discovery_find` | `-1` |
| `discovery_has_tag` | `false` |
| `discovery_state_name` | `"unknown"` for unrecognized codes |
| `discovery_change_seq`, `discovery_change_port` | `-1` |
| `discovery_change_kind`, `discovery_change_name`, `discovery_change_address`, `discovery_change_tags` | `""` |
| `discovery_watch_name`, `discovery_watch_tag` | `""` |
| `discovery_watch_cursor` | `-1` |

## 12. Structural invariant

`discovery_check_invariant(reg)` is true iff all eight registration vectors
have equal length, `seq == change_seqs.len()` and the six change vectors
have equal length, and the three watch vectors have equal length. Every
operation in this specification preserves the invariant.

## 13. Complexity

| Operation | Complexity |
|---|---|
| `discovery_new`, accessors, `state_name`, invariant | O(1) |
| `discovery_register` | O(instance count + tag bytes) |
| heartbeat, deregister, health transitions, `find`, `count` | O(instance count) |
| `discovery_sweep` | O(instance count) (independent of `ticks`) |
| `discovery_reap` | O(instance count) |
| `discovery_lookup` | O(instance count) |
| `discovery_lookup_tag` | O(instance count * tag bytes) |
| `discovery_select`, `discovery_select_tag` | O(instance count * tag bytes) |
| `discovery_watch` | O(1) |
| `discovery_watch_poll`, `discovery_changes_since` | O(change count) |
| `discovery_check_invariant` | O(1) |

## 14. Conformance

`tests/test_conformance.xi` pins, among others: the LCG values and their
normalization; registration and validation with unchanged state on every
Err; the exact (name, address, port) identity; lookup order and DOWN
exclusion; delimiter-aware tag filters; heartbeat refresh, revive and the
`renew` event; TTL expiry with no repeat events; all state transitions and
their idempotent repeats; weighted picks across seeds; tag-scoped selection;
draining semantics; deregistration and reap with event order; name- and
tag-filtered watches with cursor advance; contiguous sequence numbers; the
change log filters; multi-tick sweeps; accessor sentinels; and the empty
registry.
