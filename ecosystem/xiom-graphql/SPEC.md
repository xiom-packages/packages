# xiom-graphql — Specification

> **Status: Planned / not implemented.** This document specifies the intended module layout and conceptual API surface of `xiom-graphql`. It is a design-stage specification; no `.xi` implementation source exists yet. All signatures are illustrative and subject to change.

## Overview

`xiom-graphql` is the schema-first GraphQL server package for XIOM, layered on top of `xiom-http` for transport, `xiom-json` for payload encoding, and `xiom-websocket` for subscription delivery. It owns SDL loading and composition, schema and operation validation, execution, resolver wiring, the typed error model, introspection, batching, and subscription protocol semantics.

The engine is organized around four explicit phases — **parse → validate → execute → complete** — and around the rule that the schema is the single source of truth. Resolvers are thin bridges returning `Result[T, GraphQLError]`, validation always runs before execution, and the subscription protocol is kept independent of the socket transport.

## Module map

| Module | File | Status |
|--------|------|--------|
| Server entry | `src/server.xi` | Planned |
| Schema loader | `src/schema_loader.xi` | Planned |
| Schema registry | `src/schema_registry.xi` | Planned |
| Type system | `src/type_system.xi` | Planned |
| Validation | `src/validation.xi` | Planned |
| Execution | `src/execution.xi` | Planned |
| Resolver core | `src/resolver.xi` | Planned |
| Field resolver | `src/field_resolver.xi` | Planned |
| Mutation | `src/mutation.xi` | Planned |
| Query | `src/query.xi` | Planned |
| Subscription | `src/subscription.xi` | Planned |
| Context | `src/context.xi` | Planned |
| Error | `src/error.xi` | Planned |
| Introspection | `src/introspection.xi` | Planned |
| DataLoader | `src/dataloader.xi` | Planned |
| Scalars | `src/scalars.xi` | Planned |
| Directives | `src/directives.xi` | Planned |
| Transport bridges | `src/transport/` | Planned |
| Plugins | `src/plugins/` | Planned |

---

## Core modules

### `server.xi` — Server entry point (Planned)

Owns the top-level GraphQL server object and the request lifecycle. Accepts an HTTP request from `xiom-http`, extracts the operation and variables, drives the engine phases, and returns a serialized `GraphQLResponse`. Holds a frozen schema registry and the registered transport bridges.

**Conceptual surface:**
- `GraphQLServer.new(schema: FrozenSchema) -> GraphQLServer`
- `GraphQLServer.handle_http(req: &HttpRequest) -> HttpResponse`
- `GraphQLServer.mount_subscriptions(bridge: WebSocketBridge) -> Result[Unit, GraphQLError]`

### `schema_loader.xi` — SDL loading & composition (Planned)

Loads SDL text from files, parses type definitions, and composes multiple SDL fragments (root, scalars, directives, feature modules) into one candidate schema prior to validation.

**Conceptual surface:**
- `load_sdl(path: Str) -> Result[SdlDocument, ParseError]`
- `compose(fragments: Vec[SdlDocument]) -> Result[SchemaDefinition, GraphQLError]`
- `GraphQLSchema.load(path: Str) -> Result[GraphQLSchema, GraphQLError]`

### `schema_registry.xi` — Typed schema registry (Planned)

Holds the composed, validated, and frozen schema: named types, fields, directives, scalar codecs, and resolver bindings. After `freeze`, the registry is immutable and safe for concurrent execution.

**Conceptual surface:**
- `SchemaRegistry.bind_resolver(field: Str, resolver: Resolver) -> Result[Unit, GraphQLError]`
- `SchemaRegistry.freeze() -> Result[FrozenSchema, GraphQLError]`
- `FrozenSchema.lookup_type(name: Str) -> Option[TypeDef]`

### `type_system.xi` — GraphQL type model (Planned)

Defines the in-memory representation of the GraphQL type system: object, interface, union, enum, input object, scalar, list, and non-null wrappers, plus field and argument definitions.

**Conceptual surface:**
- `TypeDef`, `FieldDef`, `ArgDef`, `TypeRef` (List/NonNull wrappers)
- `is_assignable(from: &TypeRef, to: &TypeRef) -> Bool`

### `validation.xi` — Operation & schema validation (Planned)

Implements the validate phase. Checks the parsed operation against the schema: field existence, argument types, fragment validity, variable usage, and directive placement. Produces a set of typed `ValidationError` values. Invalid operations never proceed to execution.

**Conceptual surface:**
- `validate_schema(schema: &SchemaDefinition) -> Result[Unit, Vec[GraphQLError]]`
- `validate_operation(schema: &FrozenSchema, doc: &Document) -> Result[Unit, Vec[ValidationError]]`

### `execution.xi` — Execution engine (Planned)

Implements the execute and complete phases. Walks the validated operation, invokes field resolvers in dependency order, applies null/error propagation rules, coerces results against the schema, and assembles the response payload.

**Conceptual surface:**
- `execute(schema: &FrozenSchema, doc: &Document, ctx: &GraphQLContext) -> ExecutionResult`
- `complete(result: ExecutionResult) -> GraphQLResponse`

### `resolver.xi` — Resolver core (Planned)

Defines the structural `Resolver` interface and the machinery for registering and dispatching resolvers. Resolvers are ordinary XIOM functions or structural service methods — no reflection, no hidden container.

**Conceptual surface:**
```xiom
pub interface Resolver[TInput, TOutput] {
  fn resolve(ctx: &GraphQLContext, input: TInput) -> Result[TOutput, GraphQLError]
}
```

### `field_resolver.xi` — Per-field resolution (Planned)

Provides the per-field resolution abstraction used by the execution engine, including default resolvers (property lookup on the parent value) and argument coercion into resolver inputs.

**Conceptual surface:**
- `FieldResolver = fn(ctx: &GraphQLContext, parent: Value, args: Args) -> Result[Value, GraphQLError]`
- `default_field_resolver(field: &FieldDef) -> FieldResolver`

### `query.xi` — Root Query resolution (Planned)

Query-operation specific behavior: parallel-safe field resolution and read-oriented execution semantics for the root `Query` type.

**Conceptual surface:**
- `resolve_query(schema, op, ctx) -> ExecutionResult`

### `mutation.xi` — Root Mutation resolution (Planned)

Mutation-operation specific behavior: sequential (ordered) execution of top-level mutation fields, as required by the GraphQL specification.

**Conceptual surface:**
- `resolve_mutation(schema, op, ctx) -> ExecutionResult`

### `subscription.xi` — Subscription protocol (Planned)

Defines subscriptions as typed event streams. Owns the subscribe/next/complete protocol semantics independent of any socket transport. The GraphQL layer defines the event contract; the transport bridge carries frames.

**Conceptual surface:**
```xiom
pub interface Subscription[T] {
  fn subscribe(ctx: &GraphQLContext, args: Args) -> Result[EventStream[T], GraphQLError]
}
```
- `EventStream[T].next() -> Result[Option[T], GraphQLError]`

### `context.xi` — Request-scoped context (Planned)

Defines `GraphQLContext`, the explicit request-scoped struct passed to every resolver. Carries request metadata, authentication state, active dataloaders, and user-supplied values. Nothing is passed implicitly.

**Conceptual surface:**
- `GraphQLContext { request: RequestInfo; loaders: LoaderRegistry; values: Map[Str, Value]; }`
- `GraphQLContext.loader[K, V](name: Str) -> Option[DataLoader[K, V]]`

### `error.xi` — Typed error model (Planned)

Defines the GraphQL error hierarchy and serialization: `GraphQLError`, `ParseError`, and `ValidationError`. Preserves the validation/execution distinction and maps errors into spec-compliant response payloads with `message`, `path`, `locations`, and `extensions`.

**Conceptual surface:**
- `GraphQLError { message: Str; path: Vec[PathSeg]; locations: Vec[Location]; extensions: Json; }`
- `GraphQLError.to_json() -> Json`

### `introspection.xi` — Introspection & schema export (Planned)

Implements the standard `__schema` / `__type` introspection fields and SDL export so tools can discover the API from the frozen registry.

**Conceptual surface:**
- `introspect(schema: &FrozenSchema) -> Json`
- `export_sdl(schema: &FrozenSchema) -> Str`

### `dataloader.xi` — Batching & caching (Planned)

First-class batching abstraction to mitigate the N+1 problem. Collects keys requested during a resolution tick, dispatches a single batch function, and caches results per request via the context.

**Conceptual surface:**
```xiom
pub interface DataLoader[K, V] {
  fn load(key: K) -> Result[V, GraphQLError]
  fn load_many(keys: Vec[K]) -> Result[Vec[V], GraphQLError]
}
```
- `DataLoader.new(batch: BatchFn[K, V]) -> DataLoader[K, V]`

### `scalars.xi` — Scalar codecs (Planned)

Strongly typed scalar codecs with contract validation. Provides built-in scalars and a `ScalarCodec` interface for custom scalars (e.g. `DateTime`, `JSON`) registered via `with_scalar`.

**Conceptual surface:**
```xiom
pub interface ScalarCodec[T] {
  fn parse(input: Value) -> Result[T, GraphQLError]
  fn serialize(value: T) -> Result[Value, GraphQLError]
}
```

### `directives.xi` — Directives (Planned)

Declarative behavior extensions with explicit hooks. Defines directive definitions, argument validation, and execution-time hook points (e.g. `@deprecated`, `@skip`, `@include`, and custom directives).

**Conceptual surface:**
- `DirectiveDef { name: Str; locations: Vec[DirectiveLocation]; args: Vec[ArgDef]; }`
- `DirectiveHook = fn(ctx: &GraphQLContext, args: Args) -> Result[DirectiveEffect, GraphQLError]`

---

## Transport (`src/transport/`) — Planned

Adapters that connect the transport-agnostic GraphQL engine to concrete transports. The engine never depends on a specific socket or HTTP implementation directly.

| File | Responsibility |
|------|----------------|
| `transport/mod.xi` | Transport bridge interfaces and registration |
| `transport/http_bridge.xi` | Maps `xiom-http` requests/responses to GraphQL operations (queries & mutations) |
| `transport/websocket_bridge.xi` | Carries subscription frames over `xiom-websocket` (subscribe/next/complete) |

**Conceptual surface:**
- `HttpBridge.dispatch(req: &HttpRequest, server: &GraphQLServer) -> HttpResponse`
- `WebSocketBridge.attach(server: &GraphQLServer, socket: WebSocket) -> Result[Unit, GraphQLError]`

---

## Plugins (`src/plugins/`) — Planned

Optional, opt-in behavior layered around the engine via explicit hooks. Plugins never leak into the transport core.

| File | Responsibility |
|------|----------------|
| `plugins/mod.xi` | Plugin interface and pipeline registration |
| `plugins/auth.xi` | Authentication/authorization hooks over `GraphQLContext` |
| `plugins/tracing.xi` | Per-field tracing and timing spans |
| `plugins/persisted_queries.xi` | Persisted (allow-listed) query support |

**Conceptual surface:**
```xiom
pub interface Plugin {
  fn on_parse(ctx: &GraphQLContext, doc: &Document) -> Result[Unit, GraphQLError]
  fn on_validate(ctx: &GraphQLContext, doc: &Document) -> Result[Unit, GraphQLError]
  fn on_execute(ctx: &GraphQLContext) -> Result[Unit, GraphQLError]
}
```

---

## Engine phases (summary)

| Phase | Module | Output | Error type |
|-------|--------|--------|------------|
| Parse | `schema_loader` / query parser | `Document` (AST) | `ParseError` |
| Validate | `validation` | validated operation | `Vec[ValidationError]` |
| Execute | `execution`, `resolver`, `field_resolver`, `query`, `mutation`, `subscription` | `ExecutionResult` | `GraphQLError` (per field) |
| Complete | `execution`, `error` | `GraphQLResponse` | serialized errors |

## Design rules (contract philosophy)

- The schema is the public contract; nothing outside it is served.
- Resolvers are thin and explicit, returning `Result[T, GraphQLError]`.
- Validation always precedes execution — invalid operations fail before data fetching.
- Batching (DataLoader) is the default recommendation for nested fields.
- Transport and GraphQL protocol are kept separate.
- Subscriptions are transport-agnostic typed streams.
- Contracts at boundaries, typed errors throughout.
