# xiom-micro Architecture

> **Status: Design stage — specification only, not yet implemented. Depends on xiom-http (transport) and xiom-net.**

`xiom-micro` is the microservices-support package for the XIOM ecosystem. It provides service discovery abstractions, typed RPC clients, retries with budgets, circuit breakers, bulkheads, distributed tracing hooks, idempotency helpers, and workflow primitives for multi-service systems. The goal is not to build an opinionated microservices framework, but to provide the minimum infrastructure needed to make service-to-service communication resilient and explicit.

The package is intentionally separate from `xiom-http` so that transport primitives remain simple while distributed-systems behavior stays opt-in. That matches the ecosystem rule already established for XIOM: keep the core focused, and put higher-level patterns in separate packages.

## What belongs here

- Service discovery abstractions.
- Typed RPC client wrappers.
- Timeouts, retries, and retry budgets.
- Circuit breakers.
- Bulkheads and resource isolation.
- Service registry adapters.
- Distributed tracing propagation.
- Idempotency keys and request deduplication.
- Outbox and saga workflow helpers.
- Health and dependency metadata.

## What stays outside

- HTTP primitives stay in `xiom-http`.
- REST conventions stay in `xiom-rest`.
- GraphQL stays in `xiom-graphql`.
- WebSocket transport stays in `xiom-websocket`.
- Real-time app semantics stay in `xiom-realtime`.

## Design goals

- Make downstream calls safe by default.
- Keep network behavior explicit and budgeted.
- Avoid retry storms and cascading failures.
- Preserve traceability across service boundaries.
- Keep the package useful for both HTTP and RPC transports.
- Use XIOM contracts to enforce call assumptions and workflow invariants.

## Repository scaffold

The scaffold below describes the intended module tree once implementation begins. At the design stage only the manifest and documentation exist; no `.xi` source files are present yet.

```text
xiom-micro/
├── package.xi
├── README.md
├── ARCHITECTURE.md
├── SPEC.md
├── docs/
│   ├── service-discovery.md
│   ├── retries.md
│   ├── circuit-breaker.md
│   ├── bulkheads.md
│   ├── rpc.md
│   ├── tracing.md
│   ├── outbox.md
│   ├── saga.md
│   └── idempotency.md
├── src/                        # planned — not yet implemented
│   ├── mod.xi
│   ├── client.xi
│   ├── request.xi
│   ├── response.xi
│   ├── discovery.xi
│   ├── registry.xi
│   ├── resolver.xi
│   ├── endpoint.xi
│   ├── timeout.xi
│   ├── retry.xi
│   ├── backoff.xi
│   ├── breaker.xi
│   ├── bulkhead.xi
│   ├── idempotency.xi
│   ├── tracing.xi
│   ├── rpc/
│   │   ├── mod.xi
│   │   ├── client.xi
│   │   ├── server.xi
│   │   ├── codec.xi
│   │   ├── envelope.xi
│   │   └── errors.xi
│   ├── workflow/
│   │   ├── mod.xi
│   │   ├── saga.xi
│   │   ├── outbox.xi
│   │   ├── compensation.xi
│   │   └── orchestration.xi
│   ├── health/
│   │   ├── mod.xi
│   │   ├── checks.xi
│   │   └── dependency_graph.xi
│   ├── policy/
│   │   ├── mod.xi
│   │   ├── routing_policy.xi
│   │   ├── retry_policy.xi
│   │   └── breaker_policy.xi
│   └── testing/
│       ├── mod.xi
│       ├── fake_registry.xi
│       ├── fake_transport.xi
│       └── fixtures.xi
└── tests/                      # planned — not yet implemented
    ├── discovery/
    ├── retry/
    ├── breaker/
    ├── workflow/
    └── tracing/
```

## Core module responsibilities

### `src/discovery.xi`
Defines the service discovery abstraction. `xiom-micro` should not force a specific registry; instead it should support client-side and server-side discovery adapters through a structural interface.

### `src/registry.xi`
Registry adapters for Kubernetes DNS/service discovery, Consul-like registries, static service maps, or test registries.

### `src/resolver.xi`
Resolves live service endpoints from a registry and health state.

### `src/endpoint.xi`
Typed endpoint metadata, including address, port, region, health, and capability tags.

### `src/client.xi`
High-level service client that combines discovery, retry, breaker, timeout, and tracing policies.

### `src/request.xi` / `src/response.xi`
RPC or service-call envelope types shared by clients and servers.

### `src/timeout.xi`
Timeout budgets for connect, read, write, and total request duration.

### `src/retry.xi`
Retry logic with budgets, idempotency requirements, and stop conditions. Retry must be capped and budgeted to avoid retry storms.

### `src/backoff.xi`
Exponential backoff, jitter, and max-delay policies.

### `src/breaker.xi`
Circuit breaker state machine with open, half-open, and closed states. Circuit breakers should fail fast when a downstream service is unhealthy.

### `src/bulkhead.xi`
Resource isolation for worker pools, connection pools, and per-dependency budgets.

### `src/idempotency.xi`
Idempotency keys, deduplication windows, and request replay safety.

### `src/tracing.xi`
Trace context propagation and span metadata.

### `src/rpc/`
Typed RPC transport abstraction for callers that want something more structured than raw HTTP. The goal is to keep RPC envelopes explicit and reusable rather than mixing transport details into application logic.

### `src/workflow/`
Workflow helpers for outbox, saga orchestration, and compensation logic. These patterns matter once service boundaries start performing multi-step side effects.

### `src/health/`
Dependency health graph and service readiness checks.

### `src/policy/`
Policy objects for routing, retry, and circuit breaker behavior.

### `src/testing/`
Fake registries and transports so resilience behavior can be tested without real network dependencies.

## Microservice architecture model

`xiom-micro` should model distributed calls as a pipeline:

1. Resolve service endpoint.
2. Check health and breaker state.
3. Apply timeout budget.
4. Apply retry policy only if the call is idempotent or safe to repeat.
5. Propagate trace context.
6. Enforce bulkhead limits.
7. Execute the request.
8. Return typed result or error.

This follows the common microservices resilience pattern set: timeouts, retries, circuit breakers, bulkheads, and tracing are the minimum useful building blocks.

## XIOM-native design translation

| Microservice concept | XIOM translation |
|---|---|
| Service discovery | Structural `Discovery` interface with typed endpoint values |
| Retry | `retry_policy` with explicit budget and idempotency requirements |
| Circuit breaker | Contract-checked state machine with open/half-open/closed states |
| Bulkhead | Scoped resource pool limits and typed capacity budgets |
| Distributed tracing | Explicit context propagation through request envelope |
| Outbox | Atomic write + publish workflow helper |
| Saga | Orchestrated workflow with compensating actions |
| RPC | Typed request/response envelope with codec abstraction |

## Retry and breaker rules

### Retry

- Retry only when the operation is safe to repeat.
- Always require a retry budget.
- Add jitter to backoff.
- Stop after a bounded number of attempts.
- Never hide retries from metrics.

### Circuit breaker

- Open when failure rate exceeds threshold.
- Half-open with limited test traffic.
- Close only after health recovers.
- Emit breaker state in metrics and health checks.

These rules follow common resilient microservice practice and should be documented as hard policy, not informal advice.

## Service discovery strategy

`xiom-micro` should support multiple discovery modes:

- Static registry for local development.
- Client-side discovery for internal services.
- Server-side discovery for simpler deployments.
- Kubernetes DNS/service awareness.
- Test registry for deterministic tests.

The abstraction should be registry-agnostic so the ecosystem can adapt to different infrastructure choices without changing business code.

## Workflow primitives

### Outbox

The outbox pattern should be supported as a first-class helper for atomic local DB write plus message publish workflows.

### Saga

Saga orchestration should allow compensation steps for multi-service operations that cannot be completed in a single transaction.

### Compensation

Compensations should be explicit functions, not hidden rollback magic.

## Example service client

```xiom
pub fn fetch_user(id: UInt) -> Result[User, ServiceError] {
  let client = ServiceClient.new("user-service")
    .with_timeout(2_000)
    .with_retry(RetryPolicy.exponential(3))
    .with_breaker(CircuitBreaker.default())

  return client.get[User]("/users/" + id.to_str())
}
```

## Contract hotspots

- Safe/idempotent call classification.
- Retry budget exhaustion.
- Breaker state transitions.
- Timeout budget validity.
- Endpoint resolution consistency.
- Outbox publish preconditions.
- Saga compensation ordering.
- Trace context propagation.

## Checklist

### Must-have
- [ ] Discovery abstraction.
- [ ] Retry policy with budget.
- [ ] Circuit breaker.
- [ ] Timeout policy.
- [ ] Bulkhead limits.
- [ ] Trace context propagation.
- [ ] Typed RPC envelope.

### Should-have
- [ ] Outbox helper.
- [ ] Saga orchestration.
- [ ] Idempotency keys.
- [ ] Health graph.
- [ ] Test registry and fake transport.

### Future
- [ ] Adaptive retry tuning.
- [ ] Service mesh integrations.
- [ ] Load-shedding policies.
- [ ] Quorum/hedged request helpers.

## Final recommendation

`xiom-micro` should be the ecosystem's resilience and distributed-call package: small, policy-driven, typed, and explicit. It should help XIOM apps survive service failures and multi-step workflows without forcing a heavy framework or hiding operational behavior behind magic.
