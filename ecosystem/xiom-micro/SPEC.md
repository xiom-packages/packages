# xiom-micro — Specification

> **Status: Planned / not implemented.** This document specifies the intended module layout and conceptual API surface of `xiom-micro`. No `.xi` source files exist yet; only the manifest and documentation are present at the design stage.

## Overview

`xiom-micro` is the resilience and distributed-call package for the XIOM ecosystem. It sits above `xiom-http` (client transport) and `xiom-net` (low-level networking) and provides service discovery, typed RPC, retries with budgets, circuit breakers, bulkheads, timeouts, distributed tracing, idempotency, and multi-service workflow primitives (outbox and saga).

Every primitive is designed around XIOM's philosophy: contracts enforce call assumptions, failures surface as typed `Result` errors, the breaker is a contract-checked state machine, retries require an explicit budget, endpoints are typed values, and saga compensations are explicit functions — never hidden rollback magic.

## Module summary

| Module | File | Responsibility | Status |
|--------|------|----------------|--------|
| Client | `src/client.xi` | High-level service client composing discovery + resilience policies | Planned |
| Request | `src/request.xi` | Outbound call/RPC request envelope | Planned |
| Response | `src/response.xi` | Inbound call/RPC response envelope | Planned |
| Discovery | `src/discovery.xi` | Structural discovery abstraction | Planned |
| Registry | `src/registry.xi` | Registry adapters (K8s, Consul-like, static, test) | Planned |
| Resolver | `src/resolver.xi` | Endpoint resolution from registry + health | Planned |
| Endpoint | `src/endpoint.xi` | Typed endpoint metadata | Planned |
| Timeout | `src/timeout.xi` | Connect/read/write/total timeout budgets | Planned |
| Retry | `src/retry.xi` | Retry policy, budget, stop conditions | Planned |
| Backoff | `src/backoff.xi` | Exponential backoff, jitter, max delay | Planned |
| Breaker | `src/breaker.xi` | Circuit breaker state machine | Planned |
| Bulkhead | `src/bulkhead.xi` | Resource isolation / concurrency limits | Planned |
| Idempotency | `src/idempotency.xi` | Keys, dedup windows, replay safety | Planned |
| Tracing | `src/tracing.xi` | Trace context propagation, spans | Planned |
| RPC | `src/rpc/` | Typed RPC transport abstraction | Planned |
| Workflow | `src/workflow/` | Outbox, saga, compensation, orchestration | Planned |
| Health | `src/health/` | Dependency graph, readiness checks | Planned |
| Policy | `src/policy/` | Routing/retry/breaker policy objects | Planned |
| Testing | `src/testing/` | Fake registry/transport, fixtures | Planned |

---

## Core modules

### `src/client.xi` — Service client — *Planned*
High-level `ServiceClient` that combines discovery, retry, breaker, timeout, bulkhead, and tracing into a single explicit call pipeline. Builder-style configuration (`with_timeout`, `with_retry`, `with_breaker`) produces a typed client whose calls return `Result[T, ServiceError]`.

Conceptual surface:
- `ServiceClient.new(service: Str) -> ServiceClient`
- `with_timeout(ms: UInt) -> ServiceClient`
- `with_retry(policy: RetryPolicy) -> ServiceClient`
- `with_breaker(breaker: CircuitBreaker) -> ServiceClient`
- `with_bulkhead(b: Bulkhead) -> ServiceClient`
- `get[R](path: Str) -> Result[R, ServiceError]`
- `post[Q, R](path: Str, body: Q) -> Result[R, ServiceError]`

### `src/request.xi` — Request envelope — *Planned*
Shared outbound envelope carrying method/path or RPC method name, headers, typed body, trace context, idempotency key, and deadline. Used by both the HTTP client path and the RPC path.

### `src/response.xi` — Response envelope — *Planned*
Shared inbound envelope carrying status, typed body, headers, and trace metadata. Errors are mapped to typed `ServiceError` / `RpcError` variants rather than raw status codes.

### `src/discovery.xi` — Discovery abstraction — *Planned*
Structural `Discovery` interface so `xiom-micro` never forces one registry. Supports client-side and server-side discovery adapters. Conceptual surface: `discover(service: Str) -> Result[Vec[Endpoint], ServiceError]`.

### `src/registry.xi` — Registry adapters — *Planned*
Concrete adapters implementing `Discovery`: Kubernetes DNS/service discovery, Consul-like registries, static service maps, and a deterministic test registry.

### `src/resolver.xi` — Resolver — *Planned*
Resolves a live endpoint from registry results filtered by current health state. Conceptual surface: `resolve(service: Str) -> Result[Endpoint, ServiceError]` with contract ensuring the returned endpoint is healthy.

### `src/endpoint.xi` — Endpoint metadata — *Planned*
Typed `Endpoint { address, port, region, health, tags }` value used throughout resolution, health, and routing.

### `src/timeout.xi` — Timeout budgets — *Planned*
`TimeoutBudget` splitting connect/read/write/total durations. Contracts ensure sub-budgets do not exceed the total.

### `src/retry.xi` — Retry — *Planned*
`RetryPolicy` with bounded attempts, an explicit `RetryBudget`, and stop conditions. Contract requires the target operation be classified safe/idempotent before retrying. Conceptual surface: `RetryPolicy.exponential(max_attempts) -> RetryPolicy`, `RetryPolicy.with_budget(budget) -> RetryPolicy`.

### `src/backoff.xi` — Backoff — *Planned*
Exponential backoff with configurable base, max delay, and jitter strategy. `Backoff.exponential(base_ms, max_ms)`, `Backoff.with_jitter(strategy)`.

### `src/breaker.xi` — Circuit breaker — *Planned*
Contract-checked state machine with `Closed`, `Open`, and `HalfOpen` states. Opens on failure-rate threshold, admits limited probe traffic when half-open, closes only after recovery. Emits state for metrics/health. Conceptual surface: `CircuitBreaker.default()`, `state() -> BreakerState`, `record_success()`, `record_failure()`.

### `src/bulkhead.xi` — Bulkhead — *Planned*
Per-dependency resource isolation via concurrency/permit limits and typed capacity budgets. Conceptual surface: `Bulkhead.new(max_concurrent)`, `acquire() -> Result[Permit, BulkheadFull]`.

### `src/idempotency.xi` — Idempotency — *Planned*
Idempotency keys, deduplication windows, and replay-safe request handling. Conceptual surface: `IdempotencyKey.new()`, `DedupWindow`.

### `src/tracing.xi` — Tracing — *Planned*
Trace context propagation and span metadata carried explicitly in the request envelope. Conceptual surface: `TraceContext`, `TraceContext.propagate(req)`, `Span.start(name)`.

---

## Subpackages

### `src/rpc/` — Typed RPC — *Planned*
| File | Responsibility |
|------|----------------|
| `mod.xi` | Public RPC surface |
| `client.xi` | Typed RPC caller |
| `server.xi` | Typed RPC handler dispatch |
| `codec.xi` | Payload encode/decode abstraction |
| `envelope.xi` | Explicit request/response envelope |
| `errors.xi` | Typed RPC error variants |

Keeps envelopes explicit and reusable rather than mixing transport details into application logic.

### `src/workflow/` — Multi-service workflows — *Planned*
| File | Responsibility |
|------|----------------|
| `mod.xi` | Public workflow surface |
| `saga.xi` | Orchestrated multi-step workflow with compensations |
| `outbox.xi` | Atomic local write + message publish helper |
| `compensation.xi` | Explicit compensation function registry |
| `orchestration.xi` | Step sequencing and failure handling |

Compensations are explicit functions, not hidden rollback magic.

### `src/health/` — Health — *Planned*
| File | Responsibility |
|------|----------------|
| `mod.xi` | Public health surface |
| `checks.xi` | Readiness/liveness checks |
| `dependency_graph.xi` | Dependency health graph |

### `src/policy/` — Policy objects — *Planned*
| File | Responsibility |
|------|----------------|
| `mod.xi` | Public policy surface |
| `routing_policy.xi` | Endpoint selection / routing rules |
| `retry_policy.xi` | Retry configuration objects |
| `breaker_policy.xi` | Breaker threshold configuration |

### `src/testing/` — Test support — *Planned*
| File | Responsibility |
|------|----------------|
| `mod.xi` | Public testing surface |
| `fake_registry.xi` | Deterministic in-memory registry |
| `fake_transport.xi` | Scriptable transport for failure injection |
| `fixtures.xi` | Reusable resilience test fixtures |

Allows resilience behavior to be tested without real network dependencies.

## Contract hotspots

- Safe/idempotent call classification.
- Retry budget exhaustion.
- Breaker state transitions.
- Timeout budget validity.
- Endpoint resolution consistency.
- Outbox publish preconditions.
- Saga compensation ordering.
- Trace context propagation.
