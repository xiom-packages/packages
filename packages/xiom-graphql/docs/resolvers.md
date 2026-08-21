# Resolvers

> Status: Design stage -- specification only.

## Thin bridges, not business logic

Resolvers in `xiom-graphql` are **thin bridges**. Their job is to translate a GraphQL field into an application call and shape the result to match the schema -- not to contain business logic. Domain rules, persistence, and orchestration belong in the layers beneath the resolver. This preserves the three-layer separation (schema -> resolver -> data source) that keeps GraphQL servers maintainable as they grow.

A resolver that starts accumulating business logic is a signal to push that logic down into a service and keep the resolver as a pass-through.

## The structural Resolver interface

Resolvers are ordinary XIOM functions or structural service methods. There is no decorator-only magic, no hidden reflection container, and no implicit service lookup. The core contract is a structural interface:

```xiom
pub interface Resolver[TInput, TOutput] {
  fn resolve(ctx: &GraphQLContext, input: TInput) -> Result[TOutput, GraphQLError]
}
```

Because the interface is structural, any value that provides a matching `resolve` method satisfies it -- resolver discovery stays explicit and works naturally with XIOM's structural typing. Every resolver returns a `Result[TOutput, GraphQLError]`, so success and failure are both part of the type, never a thrown surprise.

## Explicit binding

Resolvers are bound to named schema fields explicitly at schema-load time:

```xiom
GraphQLSchema.load("schema/root.graphql")
  .with_resolver("Query.user", query_user)
  .with_resolver("Mutation.createUser", create_user)
```

The binding key (`"Type.field"`) ties the resolver to a specific field in the contract. If a field has no bound resolver, the engine uses a default field resolver that reads the property of the same name from the parent value. This makes the wiring auditable: you can read the schema and the bindings side by side and know exactly what serves each field.

## Explicit context and typed errors

Every resolver receives an explicit `GraphQLContext` (see `context.md`) -- nothing is passed implicitly. Failures are returned as `GraphQLError` values, which the execution engine attaches to the response `errors` array with the correct `path`. Nullability rules then decide whether the failure nulls a single field or propagates upward (see `execution.md`).

This combination -- explicit context in, typed `Result` out -- is what keeps resolvers predictable and keeps the boundary between GraphQL and application code honest.
