# xiom.messaging -- specification

Version: 0.1.0 (package `xiom.messaging`, module `xiom.messaging`).

This document specifies the semantics implemented by
`src/messaging.xi`. It is the normative reference for the conformance suite
in `tests/test_conformance.xi`; where this file and the code disagree, the
code is wrong and must be fixed.

## 1. Model

A `Bus` is a pure in-process value: no threads, no sockets, no wall clock,
no FFI. All state lives in three append-only tables and a set of scalar
counters inside the `Bus` struct:

1. **Subscriptions.** Each `bus_subscribe` appends one row: `sub_id`,
   `client`, `filter`, `filter_len`, `max_attempts`, `max_qos`, `active`.
   Rows are never removed; `bus_unsubscribe` clears `active`.
2. **Deliveries.** Each matching (message, subscription) pair appends one
   delivery slot. A slot has a stable id equal to its 1-based row index and
   a state:

   | State | Meaning |
   |---|---|
   | 0 | queued (eligible once `visible <= tick`) |
   | 1 | in flight (delivered, awaiting ack/reject) |
   | 2 | settled (acked, or QoS 0 settled on delivery) |
   | 3 | dead-lettered |
   | 4 | dropped (unsubscribe) |

   Slots are tombstoned, never reclaimed.
3. **Dead letters.** Each dead-lettered delivery appends one row to the
   dead-letter log, in dead-letter order.

Time is the integer counter `tick`, starting at 0 and advanced only by
`bus_tick`. All ids (`sub_id`, message id, `delivery_id`) are assigned from
1 upward in creation order and never reused.

## 2. Topics, filters and matching

A **topic** is one or more dot-separated segments. Segments are non-empty
and contain neither `#` (0x23) nor `+` (0x2B); `.` (0x2E) is the only
separator. Equivalently: no leading, trailing or doubled `.`, no wildcard
byte anywhere. `topic_is_valid` decides exactly this.

A **filter** is one or more dot-separated non-empty segments where:

- a segment equal to `+` matches exactly one topic segment, and may appear
  in any position;
- a segment equal to `#` matches zero or more trailing topic segments and
  may appear only as the last segment;
- any other segment is a literal and must not contain `#` or `+`.

`filter_is_valid` decides exactly this. Matching (`topic_matches`) is
segment-wise, left to right:

- literal vs literal: exact byte equality;
- `+` vs any one topic segment: match, both advance;
- `#` in the filter: match immediately, consuming the rest of the topic
  (including nothing), so `a.#` matches `a` and `a.b.c`, and `#` matches
  every topic;
- if the filter is exhausted while topic segments remain, the result is
  `false`; if the topic is exhausted while non-`#` filter segments remain,
  the result is `false`.

Publish validates the topic; subscribe validates the filter. The wildcard
bytes never appear in a published topic.

## 3. Subscriptions

```
bus_subscribe(b, client, filter, max_attempts, max_qos) -> Result[Int, Str]
```

- `client` must be non-empty (`messaging: bad client`).
- `filter` must satisfy `filter_is_valid` (`messaging: bad filter`).
- `max_attempts >= 1` (`messaging: bad max attempts`): the number of times
  the delivery may be handed out before it is dead-lettered.
- `max_qos` in 0..2 (`messaging: bad qos`).
- On success the subscription is active with the next id; the returned id
  starts at 1.

```
bus_unsubscribe(b, sub_id) -> Result[Unit, Str]
```

- Unknown id: `messaging: unknown subscription`.
- Already inactive: `messaging: already unsubscribed`.
- Effect: the subscription becomes inactive; every queued (state 0)
  delivery of that subscription becomes dropped (state 4) and increments
  `dropped`. In-flight (state 1) deliveries are left alone: they may still
  be acked (the ack is counted), but they can never be delivered again —
  a timed-out in-flight delivery of an inactive subscription is dropped
  instead of requeued.
- Fan-out and delivery selection skip inactive subscriptions.

`bus_subscription_count` counts active subscriptions.

## 4. Publish and fan-out

```
bus_publish(b, topic, payload, key, qos) -> Result[Int, Str]
```

- `topic` must satisfy `topic_is_valid` (`messaging: bad topic`).
- `qos` in 0..2 (`messaging: bad qos`).
- `payload` and `key` are arbitrary `Str` values (either may be empty).
- The message id is the next id (starting at 1); `messages` increments.
- For every **active** subscription, in row order, if
  `topic_matches(subscription.filter, topic)` then one delivery slot is
  appended carrying a copy of `topic`, `payload`, `key` and the delivered
  QoS:

  ```
  delivered_qos = min(publish qos, subscription max_qos)
  ```

  with initial state 0, `attempts = 0`, `visible = tick`. Duplicate matches
  (one client with two matching subscriptions) create two deliveries; there
  is no deduplication.
- A publish with no matching subscription creates no delivery slots.

## 5. Delivery, ack and redelivery

```
bus_deliver_next(b) -> Delivery
```

Selection is deterministic:

1. **Expire pass.** Every in-flight slot with `visible <= tick` whose
   subscription is active becomes queued; if the subscription is inactive
   it becomes dropped (and increments `dropped`).
2. **Scan.** Walk slots in ascending id order and pick the first queued
   slot with `visible <= tick` that is **not key-blocked** (section 6).
   While scanning, a queued slot whose `attempts >= max_attempts` of its
   subscription is dead-lettered in place (reason `max attempts`) and
   scanning continues. If the subscription is inactive the slot is skipped
   (defensive; unsubscribe already dropped queued slots).
3. If nothing is found, return the sentinel `Delivery` with
   `delivery_id = 0` and all other fields zero/empty.
4. Otherwise the chosen slot is charged one attempt and handed out:

   ```
   attempts  += 1
   visible    = tick + min(cap, base * 2^(attempts - 1))
   state      = 1                       (QoS > 0)
   state      = 2, settled += 1         (QoS == 0: settles on delivery)
   ```

   `attempts` (and all counters) increment; `redelivered` increments when
   the charged attempt is >= 2. The returned `Delivery` copies
   `delivery_id`, `message_id`, `subscription_id`, `client`, `topic`,
   `payload`, `key`, `qos` and `attempt` (the charged attempt number).

`bus_ack(b, delivery_id) -> Result[Unit, Str]`

- `delivery_id` outside `1..delivery count`: `messaging: unknown delivery`.
- Slot not in flight (queued, settled, dead-lettered, dropped):
  `messaging: delivery not in flight`.
- Effect: state 2, `acked` increments. QoS 0 deliveries are already settled
  and can never be acked.

`bus_reject(b, delivery_id, reason) -> Result[Unit, Str]`

- Same id/state validation and messages as `bus_ack`, checked in this
  order: unknown id, then not-in-flight, then empty reason.
- `reason == ""`: `messaging: empty reject reason`.
- Effect: the delivery is dead-lettered immediately with
  `reason = "rejected: " + reason`.

### Backoff schedule

```
bus_backoff_ticks(base, cap, attempt) =
  base < 1              -> 0
  attempt < 1           -> treated as 1
  otherwise             -> min(cap, base * 2^(attempt - 1))
```

The doubling is a loop, not a shift, and saturates at `cap`; `attempt` is
the 1-based number of the delivery just charged. Defaults: `base = 1`,
`cap = 64`. `bus_set_backoff` rejects `base < 1` or `cap < base` with
`messaging: bad backoff`; the schedule is read per attempt, so changing it
affects later attempts of existing deliveries.

## 6. Ordering guarantee

A delivery's **key** is the `key` string published with its message. For a
fixed subscription, delivery order is constrained as follows:

- **Keyed.** A queued slot with a non-empty key is *key-blocked* while any
  earlier (lower-id) slot of the same subscription with an equal key is
  queued (state 0) or in flight (state 1). Key-blocked slots are never
  selected. Since slots are created in publish order, this yields strict
  publish-order delivery per (subscription, key). Settling (ack, reject,
  dead-letter, drop) releases the key immediately.
- **Unkeyed.** The empty key imposes no blocking: empty-key deliveries are
  selected in plain id (FIFO) order and never wait for anything but
  visibility.
- **Across subscriptions.** Ordering is not coordinated between
  subscriptions; each subscription's queue is independent. Across
  different keys there is no ordering constraint (selection is id order).

## 7. Error catalog

All errors are `Err(Str)` values from this closed set:

| Message | Raised by |
|---|---|
| `messaging: bad topic` | `bus_publish` (invalid topic) |
| `messaging: bad filter` | `bus_subscribe` (invalid filter) |
| `messaging: bad client` | `bus_subscribe` (empty client) |
| `messaging: bad max attempts` | `bus_subscribe` (`max_attempts < 1`) |
| `messaging: bad qos` | `bus_subscribe` / `bus_publish` (qos outside 0..2) |
| `messaging: bad backoff` | `bus_set_backoff` (`base < 1` or `cap < base`) |
| `messaging: negative tick` | `bus_tick` (`ticks < 0`) |
| `messaging: unknown subscription` | `bus_unsubscribe`, `bus_queue_depth` |
| `messaging: already unsubscribed` | `bus_unsubscribe` (second call) |
| `messaging: unknown delivery` | `bus_ack`, `bus_reject` (id never issued) |
| `messaging: delivery not in flight` | `bus_ack`, `bus_reject` (wrong state) |
| `messaging: empty reject reason` | `bus_reject` (`reason == ""`) |
| `messaging: dead letter index out of range` | `bus_dead_letter_at` |

Dead-letter reasons are exactly `max attempts` or
`rejected: <reason string as given>`.

## 8. Counters (`bus_stats` and friends)

| Field | Meaning |
|---|---|
| `subscriptions` | active subscriptions (computed) |
| `messages` | messages published (`next_msg_id - 1`) |
| `deliveries` | delivery slots ever created |
| `attempts` | delivery attempts charged |
| `acked` | explicit acks accepted |
| `settled` | QoS 0 deliveries settled on delivery |
| `redelivered` | charged attempts with `attempt >= 2` |
| `dead_lettered` | dead letters written |
| `dropped` | slots dropped by unsubscribe (queued at unsubscribe, or in-flight and timed out after it) |
| `pending` | slots in state 0 (computed) |
| `inflight` | slots in state 1 (computed) |

## 9. Determinism

All operations are pure functions of the current `Bus` value and their
arguments; all iteration is over append-only tables in index order; no
ambient time or randomness is read. Two identical call sequences on two
fresh buses therefore produce identical ids, deliveries, dead letters and
counters (suite check 19 replays a scenario and compares transcripts).

## 10. Complexity

| Operation | Complexity |
|---|---|
| `topic_is_valid`, `filter_is_valid`, `topic_matches` | O(input length) |
| `bus_subscribe`, `bus_unsubscribe` | O(filter) / O(deliveries) |
| `bus_publish` | O(subscriptions x filter length) |
| `bus_deliver_next` | O(deliveries^2) worst case (key scan), O(deliveries) typical |
| `bus_ack`, `bus_reject`, `bus_dead_letter_at` | O(1) |
| `bus_pending_count`, `bus_inflight_count`, `bus_queue_depth`, `bus_stats` | O(deliveries) |

## 11. Out of scope

Sockets, serialization, persistence, client sessions/retention, QoS 2
two-phase handshakes, priorities, TTL per message, flow control and
multi-threaded scheduling.
