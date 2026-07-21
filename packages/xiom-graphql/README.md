# xiom-graphql

> Schema-first GraphQL server for XIOM — SDL loading, validation, execution, resolvers, and subscriptions, built on xiom-http.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/XIOM-lang/XIOM.git )
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

> Status: Design stage — spec only, not yet implemented.

## Overview

`xiom-graphql` is the schema-first GraphQL extension package built on top of `xiom-http`. It provides a strongly typed GraphQL server where the schema is the public contract, resolvers are thin bridges to application logic, operations are validated before execution, and subscriptions are carried over a transport that is kept separate from the GraphQL protocol itself.

The design follows four guiding properties:

- **Schema-first** — SDL files define the API surface; code never invents fields or types outside the schema.
- **Resolver-thin** — resolvers translate GraphQL fields into application calls; business logic lives elsewhere.
- **Validation-heavy** — parse, validate, and execute are explicit phases, each with typed errors, and invalid operations fail before any data is fetched.
- **Transport-separated** — the HTTP and WebSocket layers stay in their own packages; `xiom-graphql` owns only the GraphQL protocol and event semantics.

This keeps `xiom-http` a lean transport foundation while `xiom-graphql` owns GraphQL-specific concerns: SDL, resolvers, schema composition, validation, execution, and subscription wiring.

## Dependencies

| Package | Role |
|---------|------|
| `xiom-http` | HTTP transport for query and mutation requests (the `http_bridge`) |
| `xiom-json` | Request/response payload encoding and variable coercion |
| `xiom-websocket` | Subscription transport (the `websocket_bridge`) |
| `xiom-std` | Core types, `Result`, `Option`, collections, contracts |

## Planned API Reference

> All APIs below are **Planned** — this package is design-stage and ships no `.xi` implementation yet. Signatures are illustrative and subject to change.

### Schema loading — Planned

| Symbol | Signature (planned) | Description |
|--------|---------------------|-------------|
| `GraphQLSchema.load` | `(path: Str) -> Result[GraphQLSchema, GraphQLError]` | Load and compose SDL file(s) into a typed schema |
| `GraphQLSchema.with_scalar` | `(name: Str, codec: ScalarCodec) -> GraphQLSchema` | Register a custom scalar codec |
| `GraphQLSchema.with_resolver` | `(field: Str, resolver: Resolver) -> GraphQLSchema` | Bind a resolver to a schema field |
| `GraphQLSchema.freeze` | `() -> Result[FrozenSchema, GraphQLError]` | Validate and freeze the registry for execution |

### Execution phases — Planned

| Symbol | Signature (planned) | Description |
|--------|---------------------|-------------|
| `parse` | `(query: Str) -> Result[Document, ParseError]` | Query text → AST |
| `validate` | `(schema: &FrozenSchema, doc: &Document) -> Result[Unit, Vec[ValidationError]]` | Validate operation against schema |
| `execute` | `(schema: &FrozenSchema, doc: &Document, ctx: &GraphQLContext) -> ExecutionResult` | Walk operation, call resolvers |
| `complete` | `(result: ExecutionResult) -> GraphQLResponse` | Serialize data + errors in GraphQL format |

### Resolvers — Planned

| Symbol | Signature (planned) | Description |
|--------|---------------------|-------------|
| `Resolver[TInput, TOutput]` | `interface { fn resolve(ctx, input) -> Result[TOutput, GraphQLError] }` | Structural resolver contract |
| `FieldResolver` | `(ctx: &GraphQLContext, parent, args) -> Result[Value, GraphQLError]` | Per-field resolution function |
| `query.*` / `mutation.*` | resolver bindings | Root Query/Mutation field resolvers |

### Subscriptions — Planned

| Symbol | Signature (planned) | Description |
|--------|---------------------|-------------|
| `Subscription[T]` | `interface { fn subscribe(ctx) -> Result[EventStream[T], GraphQLError] }` | Typed subscription contract |
| `EventStream[T]` | `stream` | Transport-agnostic event stream |
| `websocket_bridge` | transport adapter | Carries subscription frames over `xiom-websocket` |

### Errors — Planned

| Symbol | Signature (planned) | Description |
|--------|---------------------|-------------|
| `GraphQLError` | `struct { message: Str; path: Vec[Str]; locations: Vec[Location]; extensions: Json; }` | GraphQL-compliant error |
| `ParseError` | `struct` | Typed parse-stage failure |
| `ValidationError` | `struct` | Typed validate-stage failure |

### DataLoader — Planned

| Symbol | Signature (planned) | Description |
|--------|---------------------|-------------|
| `DataLoader[K, V]` | `interface { fn load(key: K) -> Result[V, GraphQLError]; fn load_many(keys: Vec[K]) -> Result[Vec[V], GraphQLError] }` | Batched, cached loader |
| `BatchFn[K, V]` | `(keys: Vec[K]) -> Result[Vec[V], GraphQLError]` | User-supplied batch function |

## Example (planned usage)

```xiom
module api.graphql

use xiom_http
use xiom_graphql

pub fn schema() -> GraphQLSchema {
  return GraphQLSchema.load("schema/root.graphql")
    .with_scalar("DateTime", date_time_scalar)
    .with_resolver("Query.user", query_user)
    .with_resolver("Mutation.createUser", create_user)
}
```

## Design Documents

- [ARCHITECTURE.md](ARCHITECTURE.md) — canonical package architecture and design rationale.
- [SPEC.md](SPEC.md) — module-by-module specification and conceptual API surface.
- [docs/schema-first.md](docs/schema-first.md) — why the schema is the source of truth.
- [docs/schema-loading.md](docs/schema-loading.md) — the SDL load/compose/validate/bind/freeze pipeline.
- [docs/validation.md](docs/validation.md) — validate-before-execute and the validation error set.
- [docs/execution.md](docs/execution.md) — parse → validate → execute → complete engine.
- [docs/resolvers.md](docs/resolvers.md) — the structural `Resolver` interface and thin-resolver rule.
- [docs/subscriptions.md](docs/subscriptions.md) — transport-agnostic typed event streams.
- [docs/context.md](docs/context.md) — request-scoped context passing.
- [docs/error-model.md](docs/error-model.md) — validation vs execution vs transport errors.
- [docs/batching-and-dataloaders.md](docs/batching-and-dataloaders.md) — N+1 mitigation and the loader abstraction.

## Design (schema) examples

The `schema/` directory contains illustrative SDL used by the docs. These are design examples and are **not** wired into any runtime:

- `schema/root.graphql` — example root `Query`/`Mutation`/`Subscription`.
- `schema/scalars.graphql` — custom scalar examples (`DateTime`, `JSON`).
- `schema/directives.graphql` — example directive definitions.
- `schema/examples.graphql` — example object/input/enum type definitions.

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/XIOM-lang/XIOM.git )

## License

MIT OR Apache-2.0
