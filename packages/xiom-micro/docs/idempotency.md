# Idempotency

> Status: Design stage — specification only, not yet implemented.

Idempotency means an operation can be applied more than once without changing the result beyond the first application. In a distributed system this property is not a nice-to-have — it is what makes retries, at-least-once messaging, and saga replays *safe*. Any time a call might be delivered twice (a client retry after a timeout, an outbox relay running again after a crash, a broker redelivering a message), idempotency is what prevents the duplicate from double-charging a card or creating two orders. `xiom-micro` provides the tools for this in `idempotency.xi`.

The core mechanism is the **idempotency key**: a unique token generated per logical operation and attached to the request envelope. The receiving side records keys it has already processed within a **deduplication window** and, on seeing a repeat, returns the original result instead of executing the work again. `IdempotencyKey.new()` produces a key and `DedupWindow` bounds how long keys are remembered — long enough to cover realistic retry and redelivery horizons, short enough to keep the dedup store manageable.

Idempotency is tightly coupled to the other resilience primitives. The retry policy (see [retries.md](retries.md)) will only retry operations classified as safe/idempotent, and idempotency keys let a client safely retry even mutating calls because duplicates collapse on the server. The [outbox](outbox.md) publishes at-least-once, so its consumers rely on idempotency to absorb re-published messages, and [sagas](saga.md) depend on it when steps or compensations are re-driven.

The XIOM-native framing is that "safe to repeat" is an explicit, checkable property rather than an assumption. Idempotency keys are typed values, the dedup window has clear bounds, and the classification of a call as replay-safe is a contract at the call site — so replay safety is guaranteed by construction instead of hoped for.
