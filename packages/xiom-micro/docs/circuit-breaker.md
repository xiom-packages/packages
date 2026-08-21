# Circuit Breaker

> Status: Design stage -- specification only, not yet implemented.

A circuit breaker stops a client from hammering a downstream service that is already failing. Instead of waiting for timeout after timeout while the dependency is unhealthy, the breaker **fails fast** -- returning an error immediately -- and periodically probes to see if the service has recovered. In `xiom-micro` the breaker lives in `breaker.xi` and its thresholds are configured through `policy/breaker_policy.xi`.

The breaker is modeled as a **contract-checked state machine** with three states:

- **Closed** -- normal operation; calls flow through and outcomes are recorded.
- **Open** -- the failure rate exceeded the threshold; calls fail fast without touching the network.
- **Half-Open** -- after a cool-down, a limited number of probe calls are admitted to test recovery.

The transitions are the whole point, and each one carries a contract. The breaker **opens** when the observed failure rate crosses its threshold. From open it moves to **half-open** after the cool-down window. From half-open it **closes** only if the probe traffic succeeds; any probe failure sends it straight back to open. Modeling these as explicit, contract-verified transitions means illegal jumps (for example, closing directly from open without probing) are impossible by construction rather than by convention.

Breaker state is first-class operational data: it is emitted into metrics and surfaced in health checks so operators can see *why* calls are being rejected. Combined with bulkheads (which cap concurrency) and timeouts (which bound latency), the breaker completes the fail-fast story -- a struggling dependency degrades gracefully instead of dragging its callers down with it.
