# Bulkheads

> Status: Design stage -- specification only, not yet implemented.

The bulkhead pattern takes its name from ship design: a hull is divided into watertight compartments so that a breach in one does not flood the whole vessel. Applied to services, a bulkhead isolates the resources used to talk to each dependency so that one slow or failing dependency cannot consume every worker, connection, or thread and starve calls to healthy dependencies. In `xiom.micro`, `bulkhead.xi` provides this isolation.

Without bulkheads, a single misbehaving downstream is enough to take out an entire service: requests pile up waiting on it, the shared worker pool fills, and unrelated endpoints begin to fail because there is no capacity left to serve them. A bulkhead prevents this by giving each dependency its own bounded slice of capacity -- a maximum concurrency limit, a dedicated connection-pool budget, or a per-dependency permit count.

The conceptual surface is a `Bulkhead` created with a capacity limit and an `acquire()` operation that returns a `Permit` or a typed `BulkheadFull` error. When the compartment is full, calls fail fast with an explicit error rather than queuing unboundedly. This pairs naturally with the circuit breaker (fail fast on unhealthy dependencies) and timeouts (bound how long any single call may hold a permit).

In XIOM terms, capacity is a **typed budget**, not an implicit side effect of thread scheduling. Limits are scoped resource pools with contracts, and exhaustion is a first-class, observable outcome. That makes overload behavior predictable and testable -- you can inject a saturated bulkhead in tests and assert that the rest of the service keeps serving.
