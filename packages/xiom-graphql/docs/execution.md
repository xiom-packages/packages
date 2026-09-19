# Execution

> Status: Design stage -- specification only.

## Four explicit phases

The `xiom.graphql` engine processes every operation through four explicit phases. Keeping them separate makes the pipeline predictable and gives each stage a dedicated, typed failure mode.

### Parse

Convert the incoming query text into an abstract syntax tree (`Document`). Parsing is deterministic, and any syntax problem is reported as a typed `ParseError` with source position. Nothing beyond lexing/parsing happens here.

### Validate

Check the parsed operation against the frozen schema -- fields, arguments, fragments, variables, selections, and directive placement. Invalid operations fail here, before any data fetching starts, producing a set of `ValidationError` values. See `validation.md` for the full rule set.

### Execute

Walk the validated operation and call resolvers in dependency order. This stage:

- resolves each selected field via its bound resolver (or the default field resolver),
- coerces arguments and results against the schema types,
- applies GraphQL's null and error propagation rules, and
- collects field-level `GraphQLError` values without aborting sibling resolution unless nullability forces it.

Query fields may resolve concurrently; top-level mutation fields resolve sequentially, as the GraphQL specification requires. Subscriptions produce an event stream rather than a single result (see `subscriptions.md`).

### Complete

Finalize the response: assemble the `data` tree, serialize collected errors into the standard GraphQL `errors` array, and apply response-level invariants before handing the payload back to the transport bridge.

## Null and error propagation

When a resolver fails or returns null for a non-null field, the error propagates to the nearest nullable ancestor, following GraphQL's propagation rules. This means partial data may still be returned: a failure deep in the tree does not necessarily discard the whole response. The engine records the failure as a `GraphQLError` with a `path` pointing at the offending field, so clients can correlate errors with the data they affected.

## Transport-agnostic

Execution operates on a `Document`, a `FrozenSchema`, and a `GraphQLContext` -- none of which reference HTTP or WebSocket directly. The transport bridges (`http_bridge`, `websocket_bridge`) adapt concrete requests into these engine inputs and serialize the results back out. This keeps the engine independent of how a request arrived.
