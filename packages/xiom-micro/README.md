# xiom-micro

> Microservices resilience for XIOM — service discovery, typed RPC, retries/budgets, circuit breakers, bulkheads, tracing, and sagas, built on xiom-http.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/XIOM-lang/XIOM.git )
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

> Status: Design stage — spec only, not yet implemented.

## Overview

`xiom-micro` is the ecosystem's resilience and distributed-call package: small, policy-driven, typed, and explicit. It provides the minimum infrastructure needed to make service-to-service communication safe by default — service discovery, typed RPC envelopes, timeouts, retries with budgets, circuit breakers, bulkheads, distributed tracing, idempotency, and multi-service workflow primitives (outbox and saga).

It is intentionally separate from `xiom-http` so transport primitives stay simple while distributed-systems behavior stays opt-in. Downstream calls are modeled as an explicit pipeline (resolve → check health/breaker → apply timeout → apply retry if safe → propagate trace → enforce bulkhead → execute → typed result). Every resilience primitive is contract-checked: the breaker is a contract-verified state machine, retries require an explicit budget, endpoints are typed values, and saga compensations are explicit functions rather than hidden rollback magic.

## Dependencies

| Package | Role |
|---------|------|
| `xiom-http` | HTTP transport used by the default service client and RPC-over-HTTP |
| `xiom-net` | Low-level networking (TCP) for RPC transports and native connections |
| `xiom-std` | Core types, `Result`, contracts, collections |

## Planned API Reference

> All APIs below are **Planned** — design stage, not yet implemented.

### Discovery (`xiom.micro.discovery`)
| Item | Signature (planned) | Status | Description |
|------|---------------------|--------|-------------|
| `Discovery` | `interface` | Planned | Structural discovery interface for pluggable registries |
| `Registry` | `interface` | Planned | Registry adapter (K8s DNS, Consul-like, static, test) |
| `Resolver.resolve` | `(service: Str) -> Result[Endpoint, ServiceError]` | Planned | Resolve a live endpoint from registry + health |
| `Endpoint` | `type` | Planned | Typed endpoint (address, port, region, health, tags) |

### RPC (`xiom.micro.rpc`)
| Item | Signature (planned) | Status | Description |
|------|---------------------|--------|-------------|
| `RpcClient.call` | `(req: Request[Q]) -> Result[Response[R], RpcError]` | Planned | Typed request/response call |
| `RpcServer.serve` | `(handler) -> Result[Unit, RpcError]` | Planned | Serve typed RPC handlers |
| `Codec` | `interface` | Planned | Encode/decode envelope payloads |
| `Envelope` | `type` | Planned | Explicit request/response envelope |

### Retry & Backoff (`xiom.micro.retry`)
| Item | Signature (planned) | Status | Description |
|------|---------------------|--------|-------------|
| `RetryPolicy.exponential` | `(max_attempts: UInt) -> RetryPolicy` | Planned | Bounded exponential retry policy |
| `RetryBudget` | `type` | Planned | Token budget capping total retries |
| `Backoff.exponential` | `(base_ms, max_ms) -> Backoff` | Planned | Exponential backoff with max delay |
| `Backoff.with_jitter` | `(strategy) -> Backoff` | Planned | Add jitter to avoid retry storms |

### Circuit Breaker (`xiom.micro.breaker`)
| Item | Signature (planned) | Status | Description |
|------|---------------------|--------|-------------|
| `CircuitBreaker.default` | `() -> CircuitBreaker` | Planned | Default open/half-open/closed breaker |
| `CircuitBreaker.state` | `() -> BreakerState` | Planned | Current contract-checked state |
| `BreakerState` | `enum: Closed, Open, HalfOpen` | Planned | Breaker state machine values |

### Bulkhead (`xiom.micro.bulkhead`)
| Item | Signature (planned) | Status | Description |
|------|---------------------|--------|-------------|
| `Bulkhead.new` | `(max_concurrent: UInt) -> Bulkhead` | Planned | Per-dependency concurrency limit |
| `Bulkhead.acquire` | `() -> Result[Permit, BulkheadFull]` | Planned | Acquire a capacity permit |

### Timeout (`xiom.micro.timeout`)
| Item | Signature (planned) | Status | Description |
|------|---------------------|--------|-------------|
| `TimeoutBudget` | `type` | Planned | connect/read/write/total budgets |
| `TimeoutBudget.total` | `(ms: UInt) -> TimeoutBudget` | Planned | Total request deadline |

### Tracing (`xiom.micro.tracing`)
| Item | Signature (planned) | Status | Description |
|------|---------------------|--------|-------------|
| `TraceContext` | `type` | Planned | Trace/span identifiers |
| `TraceContext.propagate` | `(req: &mut Request) -> Unit` | Planned | Inject context into an envelope |
| `Span.start` | `(name: Str) -> Span` | Planned | Begin a span |

### Idempotency (`xiom.micro.idempotency`)
| Item | Signature (planned) | Status | Description |
|------|---------------------|--------|-------------|
| `IdempotencyKey.new` | `() -> IdempotencyKey` | Planned | Generate a unique key |
| `DedupWindow` | `type` | Planned | Deduplication window for replays |

### Workflow — Outbox (`xiom.micro.workflow.outbox`)
| Item | Signature (planned) | Status | Description |
|------|---------------------|--------|-------------|
| `Outbox.enqueue` | `(msg: Message) -> Result[Unit, OutboxError]` | Planned | Atomic local write + queued publish |
| `Outbox.relay` | `() -> Result[UInt, OutboxError]` | Planned | Publish pending messages |

### Workflow — Saga (`xiom.micro.workflow.saga`)
| Item | Signature (planned) | Status | Description |
|------|---------------------|--------|-------------|
| `Saga.new` | `() -> Saga` | Planned | Begin a saga definition |
| `Saga.step` | `(action, compensation) -> Saga` | Planned | Add a step with explicit compensation |
| `Saga.run` | `() -> Result[Unit, SagaError]` | Planned | Execute steps, compensate on failure |

## Design Documents

- [ARCHITECTURE.md](ARCHITECTURE.md) — full package architecture and design goals.
- [SPEC.md](SPEC.md) — module-by-module planned responsibilities and API surface.
- [docs/service-discovery.md](docs/service-discovery.md)
- [docs/retries.md](docs/retries.md)
- [docs/circuit-breaker.md](docs/circuit-breaker.md)
- [docs/bulkheads.md](docs/bulkheads.md)
- [docs/rpc.md](docs/rpc.md)
- [docs/tracing.md](docs/tracing.md)
- [docs/outbox.md](docs/outbox.md)
- [docs/saga.md](docs/saga.md)
- [docs/idempotency.md](docs/idempotency.md)

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/XIOM-lang/XIOM.git )

## License

MIT OR Apache-2.0
