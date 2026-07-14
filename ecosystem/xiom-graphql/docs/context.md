# Context

> Status: Design stage — specification only.

## Explicit, request-scoped context

Every resolver in `xiom-graphql` receives an explicit `GraphQLContext`. There is no ambient global, no thread-local lookup, and no implicit injection — if a resolver needs something, it reads it from the context that was handed to it. This matches XIOM's preference for explicit data flow and makes resolver dependencies visible at the call boundary.

The context is **request-scoped**: it is constructed once per incoming operation and lives for the duration of that operation's execution. It is not shared across requests, which keeps per-request state (auth, loaders, caches) properly isolated.

## What the context carries

```xiom
GraphQLContext {
  request: RequestInfo,        // transport metadata: headers, peer, operation name
  loaders: LoaderRegistry,     // per-request DataLoaders (batching + caching)
  values:  Map[Str, Value],    // application-supplied, request-scoped values
}
```

- **Request info** — metadata extracted by the transport bridge (headers, operation name, and similar), so resolvers can inspect the request without touching the transport directly.
- **Loaders** — the per-request `DataLoader` instances used for batching. Because loaders are scoped to the context, their caches naturally clear between requests (see `batching-and-dataloaders.md`).
- **Values** — a typed bag for application state such as the authenticated user, a database handle, or a trace span, populated by plugins or the server before execution.

## Populated at the boundary

The context is assembled at the transport boundary, before the execute phase begins. Plugins (`plugins/auth.xi`, `plugins/tracing.xi`) and the server hook in here to attach values — for example, `auth` resolves and stores the current principal so downstream resolvers can authorize without re-parsing credentials.

Because population happens once, up front, resolvers can treat the context as a stable, fully-formed input for the whole operation.

## Why explicit context matters

Passing context explicitly keeps three things honest:

1. **Testability** — a resolver can be exercised by constructing a plain `GraphQLContext`, with no global setup.
2. **Isolation** — request-scoped state cannot leak between concurrent operations.
3. **Auditability** — every dependency a resolver uses is visible in its signature, consistent with the thin-resolver rule (see `resolvers.md`).
