# Tracing

> Status: Design stage -- specification only, not yet implemented.

In a distributed system a single user action fans out into many service calls. Without distributed tracing, a failure or latency spike is nearly impossible to attribute -- you see a slow request but not *which* downstream hop caused it. `xiom.micro` treats trace propagation as a core resilience concern, handled by `tracing.xi`, because you cannot operate what you cannot observe.

The model is deliberately explicit. A `TraceContext` (trace id, span id, and parent linkage) rides inside the request envelope rather than in ambient thread-local state. When a client makes a downstream call, it `propagate`s the current context into the outgoing request; the receiving service reads it back out and starts child spans from it. Because the context travels *with* the typed envelope, the causal chain is preserved across every service boundary and transport (HTTP or RPC) without relying on hidden globals.

Spans (`Span.start(name)`) mark units of work with timing and metadata, and they compose with the rest of the pipeline: retries, breaker trips, and bulkhead rejections are all recorded against the active span. This means a trace does not just show "call took 3s" -- it shows the retries that were attempted, whether the breaker was open, and where the deadline was consumed.

Keeping propagation explicit and typed is the XIOM-native choice. Trace context is a value with a contract that it be carried forward on every hop, so "we lost the trace at the RPC boundary" becomes a checkable invariant (a listed contract hotspot) rather than a debugging mystery.
