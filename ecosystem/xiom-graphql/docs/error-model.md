# Error Model

> Status: Design stage — specification only.

## Three distinct error categories

GraphQL has a well-defined error model, and `xiom-graphql` preserves its distinctions rather than collapsing everything into a single failure type. Errors fall into three categories, each surfacing at a different layer:

### Validation errors

The request is invalid — a field does not exist, an argument is mistyped, a variable is misused, a directive is misplaced. **Execution does not start.** No resolver is called and no data is fetched. Validation errors are produced by the validate phase (see `validation.md`) as a set, so the client gets a complete report of what is wrong before running anything.

### Execution errors

The request was valid, but resolving a field failed. Execution errors are per-field: a resolver returned a `GraphQLError`, or produced null for a non-null field. **Partial data may still be returned**, depending on nullability rules — the error propagates only as far up the tree as GraphQL's null propagation requires (see `execution.md`). Each execution error carries a `path` pointing at the field that failed.

### Transport errors

Failures at the HTTP or WebSocket level — a dropped connection, a malformed HTTP frame, a closed socket. These stay in the transport layer (`xiom-http`, `xiom-websocket`) and are **not** GraphQL errors. The GraphQL engine never sees them, and they never appear in the GraphQL `errors` array.

## Typed errors throughout

Each phase has its own error type, so the category of a failure is never ambiguous:

- `ParseError` — from the parse phase.
- `ValidationError` — from the validate phase (collected as `Vec[ValidationError]`).
- `GraphQLError` — the field-level error returned by resolvers and attached during execution.

`GraphQLError` is the type that resolvers return via `Result[T, GraphQLError]`, and it is the type serialized into responses:

```xiom
GraphQLError {
  message:    Str,           // human-readable description
  path:       Vec[PathSeg],  // path to the field that produced the error
  locations:  Vec[Location], // source positions in the query
  extensions: Json,          // machine-readable, application-defined detail
}
```

## Serialization

The complete phase serializes all collected errors into the standard GraphQL `errors` array alongside any `data`. Validation errors appear with `data` absent (execution never ran); execution errors appear alongside whatever partial `data` survived propagation. This gives clients a spec-compliant, predictable payload in every case, and lets them distinguish "your request was illegal" from "your request ran but something failed" purely from the response shape.
