# xiom.messaging

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.0` on the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no threads, no sockets) deterministic
> in-process message bus: dotted topics, `+`/`#` wildcard subscriptions,
> fan-out to per-subscriber queues, acknowledgement accounting, exponential
> backoff redelivery, dead-letter routing and strict per-key ordering.
> **Deps:** `xiom.std` only. The library module imports `xiom.string` and
> `xiom.string.compare`; the tests use `xiom.test`, `xiom.io` and
> `xiom.convert` from it. No FFI.

## What it is

`xiom.messaging` is a model, not a client: it brokers messages between
subscribers inside one process, driven entirely by explicit calls. There is
no network, no wall clock and no threads — time is an integer `tick` that
you advance with `bus_tick`, so every scenario replays to the exact same
delivery ids, payloads and counters on every run.

A `Bus` value owns an append-only subscription table, an append-only table
of delivery slots (queued / in flight / settled / dead-lettered / dropped)
and a dead-letter log. `bus_publish` fans a message out to every active
subscription whose filter matches, creating one delivery slot per matching
subscription; `bus_deliver_next` hands out the next eligible delivery;
`bus_ack` or `bus_reject` settles it; `bus_tick` advances the logical clock
so timed-out in-flight deliveries become eligible for redelivery under the
exponential backoff schedule.

## API

| Function | Returns | Description |
|---|---|---|
| `bus_new()` | `Bus` | Empty bus: tick 0, backoff base 1 / cap 64. |
| `bus_tick(b, ticks)` | `Result[Unit, Str]` | Advance the logical clock (negative rejected). |
| `topic_is_valid(topic)` | `Bool` | Dotted, non-empty segments; no `+`/`#`. |
| `filter_is_valid(filter)` | `Bool` | `+` any segment; `#` only as the final lone segment. |
| `topic_matches(filter, topic)` | `Bool` | Wildcard match: `+` one segment, `#` zero or more trailing. |
| `bus_backoff_ticks(base, cap, attempt)` | `Int` | `min(cap, base * 2^(attempt-1))`, computed by doubling. |
| `bus_set_backoff(b, base, cap)` | `Result[Unit, Str]` | Configure redelivery delay (base >= 1, cap >= base). |
| `bus_subscribe(b, client, filter, max_attempts, max_qos)` | `Result[Int, Str]` | Add a subscription; returns its stable id. |
| `bus_unsubscribe(b, sub_id)` | `Result[Unit, Str]` | Cancel; drops queued deliveries, keeps in-flight acks. |
| `bus_subscription_count(b)` | `Int` | Active subscriptions. |
| `bus_publish(b, topic, payload, key, qos)` | `Result[Int, Str]` | Fan out; returns the stable message id. |
| `bus_deliver_next(b)` | `Delivery` | Next eligible delivery, or the `delivery_id` 0 sentinel. |
| `bus_ack(b, delivery_id)` | `Result[Unit, Str]` | Acknowledge an in-flight delivery. |
| `bus_reject(b, delivery_id, reason)` | `Result[Unit, Str]` | Dead-letter an in-flight delivery as `rejected: <reason>`. |
| `bus_pending_count(b)` | `Int` | Queued deliveries on the whole bus. |
| `bus_inflight_count(b)` | `Int` | Deliveries awaiting an ack. |
| `bus_queue_depth(b, sub_id)` | `Result[Int, Str]` | Queued deliveries for one subscription. |
| `bus_dead_letter_count(b)` | `Int` | Dead-letter records. |
| `bus_dead_letter_at(b, index)` | `Result[DeadLetter, Str]` | One dead-letter record (0-based). |
| `bus_stats(b)` | `BusStats` | All counters and gauges in one snapshot. |

The public structs are `Bus` (all fields internal state), `Delivery{delivery_id,
message_id, subscription_id, client, topic, payload, key, qos, attempt}`,
`DeadLetter{delivery_id, message_id, subscription_id, client, topic, payload,
reason, attempts, tick}` and `BusStats{subscriptions, messages, deliveries,
attempts, acked, settled, redelivered, dead_lettered, dropped, pending,
inflight}`.

## Semantics in one screen

- **Fan-out.** One delivery slot per matching subscription, in subscription
  id order. Two subscriptions of the same client both receive a copy (no
  deduplication).
- **QoS.** The delivered QoS is `min(published QoS, subscription max_qos)`.
  QoS 0 deliveries settle on delivery (no ack); QoS 1/2 deliveries go in
  flight until acked.
- **Redelivery.** An in-flight delivery whose backoff has elapsed becomes
  eligible again on the next `bus_deliver_next`, charging one more attempt.
  Delay after attempt n is `min(cap, base * 2^(n-1))` ticks.
- **Dead letter.** When a timed-out delivery has already used
  `max_attempts` attempts it is dead-lettered instead of redelivered;
  `bus_reject` dead-letters immediately with `rejected: <reason>`.
- **Ordering.** Deliveries with the same non-empty key on the same
  subscription are handed out strictly in publish order: a later keyed
  delivery is never eligible while an earlier one with the same key is
  queued or in flight. Empty keys are unordered (plain FIFO).

`SPEC.md` pins every error message, boundary and state transition.

## Usage

The wildcard syntax is `+` (exactly one segment) and `#` (zero or more
trailing segments).

```xi
use xiom.messaging;
use xiom.io;

var bus = bus_new();
bus_subscribe(&mut bus, "orders-svc", "orders.#", 3, 1);
bus_publish(&mut bus, "orders.eu.new", "order-1", "order-1", 1);

let d = bus_deliver_next(&mut bus);      // delivery_id 1, client "orders-svc"
// ... hand d.payload to the subscriber ...
bus_ack(&mut bus, d.delivery_id);        // settled; gone for good
```

`&mut` is required at every mutation call site: passing a `Bus` without it
copies the value and the mutation is silently lost.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.messaging
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **In-process model only.** No sockets, no serialization, no persistence,
  no replication; payloads are in-memory `Str` values.
- **Explicit clock.** Nothing happens unless the caller ticks and delivers;
  there is no scheduler and no thread.
- **Linear scans.** Fan-out, selection and key blocking are O(n) / O(n^2)
  over the delivery table; this is a testable model, not a high-throughput
  broker.
- **Append-only tables.** Acked, dead-lettered and dropped delivery slots
  are tombstoned, never reclaimed; a long-lived bus grows monotonically.
- **No client sessions.** Unsubscribing drops queued work; there is no
  resume/offline queue and no message retention for new subscribers.
- **`max_qos` is a delivery label.** QoS 1 and QoS 2 behave identically in
  this model (both ack-required, same backoff); the two-phase QoS 2
  handshake is out of scope.

## Install / publish

```
xiom pkg install xiom.messaging@0.1.0     # consumer
xiom pkg publish                          # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
