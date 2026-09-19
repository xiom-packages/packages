# Saga

> Status: Design stage -- specification only, not yet implemented.

Some operations span multiple services and cannot be wrapped in a single ACID transaction -- there is no distributed lock across independently owned databases. A **saga** models such an operation as a sequence of local steps, each with a matching **compensation** that undoes its effect. If every step succeeds, the saga completes; if a step fails, the already-completed steps are compensated in reverse order to return the system to a consistent state. `xiom.micro` provides saga orchestration in `workflow/saga.xi`, with compensation logic in `workflow/compensation.xi`.

The defining rule of `xiom.micro`'s design is that **compensations are explicit functions, not hidden rollback magic**. When you add a step you also declare how to undo it: `Saga.step(action, compensation)`. There is no automatic reversal inferred from some framework -- the developer states, in code, what "undo the reservation" or "refund the payment" actually means. This keeps the semantics honest, because compensation in the real world is rarely a perfect inverse (a refund is not the same as an un-charge), and pretending otherwise causes subtle bugs.

Execution is orchestrated (`workflow/orchestration.xi`): the saga runs steps forward, and on failure walks the completed steps backward invoking their compensations. `Saga.run()` returns `Result[Unit, SagaError]`, so both the success path and the "failed and compensated" path are explicit outcomes the caller must handle. Steps and compensations are typically emitted reliably via the [outbox](outbox.md) and consumed idempotently (see [idempotency.md](idempotency.md)), since sagas run over unreliable networks and may retry.

Ordering is a contract hotspot: compensations must run in the correct reverse order and only for steps that actually committed. Modeling the saga explicitly -- typed steps, typed errors, declared compensations, and contract-checked ordering -- is the XIOM-native alternative to opaque distributed-transaction frameworks that hide when and how state gets rolled back.
