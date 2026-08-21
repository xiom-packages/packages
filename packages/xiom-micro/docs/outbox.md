# Outbox

> Status: Design stage -- specification only, not yet implemented.

The outbox pattern solves the *dual-write problem*: a service often needs to both change its local database **and** publish a message (an event, a command, a notification) as part of the same logical operation. Doing these as two independent network/IO actions is unsafe -- if the process crashes between them, you either update the database without publishing, or publish without committing, and the system ends up inconsistent. `xiom-micro` supports the outbox as a first-class workflow helper in `workflow/outbox.xi`.

The idea is to make the publish **part of the same local transaction as the business write**. Instead of publishing directly, the service writes the outgoing message into an *outbox table* in the same database transaction that performs the business change. Because both writes commit atomically, there is no window where one succeeds without the other. A separate **relay** step then reads pending rows from the outbox and publishes them to the message broker, marking each as sent once acknowledged.

The conceptual surface is small: `Outbox.enqueue(msg)` records a message atomically alongside local state, and `Outbox.relay()` publishes pending messages and reports how many were sent. Because the relay may run more than once (a crash after publish but before marking sent is always possible), messages are published *at least once* -- so consumers must be idempotent (see [idempotency.md](idempotency.md)). This trade is deliberate: at-least-once with idempotent consumers is far easier to reason about than trying to achieve exactly-once across a database and a broker.

In XIOM terms the atomicity requirement is a contract hotspot: `enqueue` carries the precondition that it runs inside the business transaction, and the relay's publish preconditions are explicit. The outbox is a building block for larger flows -- a saga (see [saga.md](saga.md)) frequently uses the outbox to emit its step and compensation messages reliably.
