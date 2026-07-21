# RPC

> Status: Design stage — specification only, not yet implemented.

`xiom-micro` offers a typed RPC layer for callers who want something more structured than hand-assembling raw HTTP requests. The goal is not to invent a new wire protocol but to keep the *shape* of a service call explicit and reusable: a typed request goes in, a typed response comes out, and transport details stay out of application logic. The RPC layer lives under `src/rpc/`.

The design centers on an explicit **envelope** (`envelope.xi`). Every call is a `Request[Q]` carrying the RPC method, headers, a typed payload, trace context, an optional idempotency key, and a deadline; every reply is a `Response[R]` carrying status, a typed payload, and trace metadata. Because the envelope is a real value rather than an ad-hoc dictionary, it can be logged, tested, replayed, and reasoned about. Payload serialization is delegated to a pluggable `Codec` (`codec.xi`), so the same client and server code works regardless of whether the bytes on the wire are JSON, a binary format, or something else.

`client.xi` and `server.xi` provide the caller and handler-dispatch sides. The client composes the same resilience pipeline as the general service client — resolution, health/breaker checks, timeouts, budgeted retries, tracing, and bulkheads — so RPC calls are resilient by default, not as an afterthought. The server side dispatches typed handlers and maps failures to typed variants in `errors.xi` rather than leaking transport status codes into business code.

The default transport is RPC-over-HTTP via `xiom-http`, with `xiom-net` available for lower-level connections. The XIOM philosophy shows up in the typing: request/response types are checked, codecs are explicit interfaces, and errors are `Result` values — no reflection, no hidden global stubs, and no magic proxy objects.
