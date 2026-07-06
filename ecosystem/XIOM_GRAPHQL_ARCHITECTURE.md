# xiom-graphql Schema-First Design

`xiom-graphql` is the schema-first GraphQL extension package built on top of `xiom-http`. Its purpose is to provide a strongly typed GraphQL server with schema-first development, explicit resolver wiring, query validation, execution planning, and subscription support without turning the core HTTP layer into a GraphQL framework.[web:142][web:145][web:151]

The package follows the same ecosystem rule as the other XIOM web layers: keep the transport core lean, and place higher-level opinionated behavior in separate packages. That lets `xiom-http` remain a minimal HTTP foundation while `xiom-graphql` owns GraphQL-specific concerns such as SDL, resolvers, schema composition, validation, execution, and subscription wiring.[web:123][web:147]

## Why schema-first

Schema-first GraphQL has a strong fit with XIOM because the schema acts as the public contract, and XIOM already treats contracts as first-class. GraphQL itself validates incoming operations against the schema before execution, which makes schema-first a natural match for a language that favors explicit invariants and machine-checkable intent.[web:145][web:149][web:151]

Schema-first also improves separation of concerns. The schema defines the public API, resolvers mediate between API consumers and business logic, and lower layers handle data retrieval and shaping. That separation is a proven way to keep GraphQL servers maintainable as they grow.[web:147][web:151]

## Package responsibilities

`xiom-graphql` should own:

- SDL schema loading and composition.
- Query, mutation, and subscription execution.
- Resolver registration and routing.
- Schema validation and operation validation.
- Variable coercion and argument validation.
- Type-safe context passing.
- Data loader hooks for batching.
- Error mapping to GraphQL-compliant response payloads.
- Introspection and schema export.
- Subscription transport integration via `xiom-websocket`.

## What stays outside

- Low-level HTTP server and request parsing stay in `xiom-http`.
- REST conventions stay in `xiom-rest`.
- WebSocket transport primitives stay in `xiom-websocket`.
- Microservice discovery and RPC stay in `xiom-micro`.
- Real-time room/presence semantics stay in `xiom-realtime`.

## Repository scaffold

```text
xiom-graphql/
├── package.xi
├── README.md
├── ARCHITECTURE.md
├── docs/
│   ├── schema-first.md
│   ├── schema-loading.md
│   ├── validation.md
│   ├── execution.md
│   ├── resolvers.md
│   ├── subscriptions.md
│   ├── context.md
│   ├── error-model.md
│   └── batching-and-dataloaders.md
├── schema/
│   ├── root.graphql
│   ├── scalars.graphql
│   ├── directives.graphql
│   └── examples.graphql
├── src/
│   ├── mod.xi
│   ├── server.xi
│   ├── schema_loader.xi
│   ├── schema_registry.xi
│   ├── type_system.xi
│   ├── validation.xi
│   ├── execution.xi
│   ├── resolver.xi
│   ├── field_resolver.xi
│   ├── mutation.xi
│   ├── query.xi
│   ├── subscription.xi
│   ├── context.xi
│   ├── error.xi
│   ├── introspection.xi
│   ├── dataloader.xi
│   ├── scalars.xi
│   ├── directives.xi
│   ├── transport/
│   │   ├── mod.xi
│   │   ├── websocket_bridge.xi
│   │   └── http_bridge.xi
│   ├── plugins/
│   │   ├── mod.xi
│   │   ├── auth.xi
│   │   ├── tracing.xi
│   │   └── persisted_queries.xi
│   └── testing/
│       ├── mod.xi
│       ├── fixtures.xi
│       └── golden_queries.xi
└── tests/
    ├── schema/
    ├── validation/
    ├── execution/
    ├── errors/
    └── subscriptions/
```

## Core design ideas

### 1. Schema is source of truth

The SDL file(s) define the API surface. Code does not silently invent fields or types outside the schema. This mirrors the schema-first philosophy used by many production GraphQL systems.[web:142][web:149][web:151]

### 2. Resolvers are thin bridges

Resolvers should translate GraphQL fields into application calls, not contain business logic themselves. The architecture should favor a clear separation between schema, resolver, and data source layers, similar to the three-layer idea described in mature GraphQL server designs.[web:147][web:152]

### 3. Validation happens before execution

GraphQL validates an operation against the schema before it executes. `xiom-graphql` should make this explicit by separating parse, validate, and execute phases in the engine, with typed errors for each stage.[web:145][web:154]

### 4. DataLoader-style batching is first-class

GraphQL’s N+1 problem is a real production concern, so `xiom-graphql` should provide an explicit batching hook rather than leaving batching to convention.

### 5. Subscriptions are transport-agnostic at the API layer

The subscription engine should be independent of the socket transport, so `xiom-websocket` can supply the transport while `xiom-graphql` owns the protocol and event semantics.

## Idiomatic XIOM translation

| GraphQL concept | XIOM translation |
|---|---|
| Schema Definition Language | `.graphql` files loaded and validated into a typed schema registry [web:142][web:149] |
| Resolvers | Structural interfaces and explicit functions returning `Result[T, GraphQLError]` [web:151] |
| Operation validation | Compiler-like schema validation phase before execution [web:145][web:154] |
| Context | Explicit request-scoped struct passed to resolvers |
| DataLoader | Batched loader interface with ownership-safe caches |
| Subscriptions | Typed event streams bridged to `xiom-websocket` |
| Directives | Declarative behavior extensions with explicit hooks |
| Scalars | Strongly typed scalar codecs with contract validation |

## GraphQL engine phases

### Parse

Convert incoming query text into an AST. Parse errors should be typed and deterministic.

### Validate

Check the query against the schema, fragments, variables, selections, and directive rules before execution. Invalid operations must fail before data fetching starts.[web:145][web:154]

### Execute

Walk the validated operation and call resolvers in dependency order. This stage is responsible for collecting field data, applying null/error propagation rules, and returning the final response.

### Complete

Finalize the response, serialize errors in GraphQL format, and apply response-level invariants.

## Schema loading model

`xiom-graphql` should support a schema loading pipeline like this:

1. Load SDL files.
2. Merge root schema, scalar definitions, directives, and feature modules.
3. Validate the composed schema.
4. Bind resolvers to fields.
5. Freeze the schema registry for execution.

This mirrors the practical server design pattern where the public GraphQL schema is derived from a lower data shape layer, not the other way around.[web:147][web:151]

## Resolver architecture

Resolvers should be ordinary XIOM functions or structural service methods. They receive an explicit context object and return typed results. No decorator-only magic, no hidden reflection container, and no implicit service lookup.

```xiom
pub interface Resolver[TInput, TOutput] {
  fn resolve(ctx: &GraphQLContext, input: TInput) -> Result[TOutput, GraphQLError]
}
```

This keeps resolver discovery explicit and works naturally with XIOM’s structural typing.

## Error model

GraphQL has a well-defined validation and execution error model. `xiom-graphql` should preserve that distinction:

- Validation errors: request is invalid, execution does not start.[web:145]
- Execution errors: some field resolution failed, partial data may still be returned depending on nullability rules.[web:145][web:154]
- Transport errors: HTTP or websocket-level failures stay in the transport layer.

## Subscription architecture

Subscriptions should be modeled as explicit typed streams. The GraphQL layer defines the event contract; the websocket package carries frames; the app decides what event sources produce the payloads.

## Batching and N+1 mitigation

`xiom-graphql` should expose a first-class loader abstraction so users can batch resolver-side fetches. The package should document the N+1 problem clearly and make batching the default recommendation for nested fields.

## Example structure

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

## Design rules

- Keep schema files as the public contract.
- Keep resolvers thin and explicit.
- Validate operations before execution.
- Batch data access by default.
- Keep transport and GraphQL protocol separate.
- Keep subscriptions transport-agnostic.
- Use contracts at boundaries and typed errors throughout.

## Checklist

### Must-have
- [ ] SDL loading and composition.
- [ ] Query parsing and validation.
- [ ] Resolver binding.
- [ ] Execution engine.
- [ ] Typed error model.
- [ ] Context handling.
- [ ] Introspection.

### Should-have
- [ ] DataLoader-style batching.
- [ ] Subscription support.
- [ ] Custom scalars.
- [ ] Directives.
- [ ] Persisted queries.

### Future
- [ ] Query complexity limits.
- [ ] Cost analysis.
- [ ] Federation support.
- [ ] Schema diff tooling.

## Final recommendation

`xiom-graphql` should be schema-first, resolver-thin, validation-heavy, and transport-separated. That gives you the strongest combination of GraphQL ergonomics and XIOM correctness: the schema is the contract, resolvers are explicit, validation happens before execution, and higher-level capabilities remain modular instead of leaking into the HTTP foundation.[web:142][web:145][web:147][web:151]
