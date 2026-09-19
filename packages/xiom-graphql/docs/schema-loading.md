# Schema Loading

> Status: Design stage -- specification only.

## The loading pipeline

`xiom.graphql` loads a schema through an explicit, ordered pipeline. Each stage has a defined input and output, and failures produce typed errors rather than partially-initialized state:

1. **Load SDL files.** Read one or more `.graphql` files from disk into SDL documents. Parse errors at this stage are typed and deterministic.
2. **Merge fragments.** Compose the root schema, scalar definitions, directive definitions, and feature modules into a single candidate schema definition. Composition detects duplicate or conflicting definitions early.
3. **Validate the composed schema.** Check that the merged schema is internally consistent: all referenced types exist, interfaces are satisfied, directive locations are legal, and scalars have codecs.
4. **Bind resolvers to fields.** Attach resolver functions and scalar codecs to their named schema fields. A field without a resolver falls back to the default field resolver (property lookup on the parent value).
5. **Freeze the registry.** Produce an immutable `FrozenSchema` that is safe to share across concurrent executions. After freezing, no further mutation is possible.

## Derive the API from the data shape, not the reverse

The pipeline reflects a practical server design pattern: the public GraphQL schema is *derived from* a lower data-shape layer, not the other way around. The SDL expresses the contract the API wants to present; resolvers and data sources are then written to satisfy that contract. This keeps the public surface stable even when the underlying storage or services change.

## Composition model

Schemas are assembled from multiple SDL fragments so large APIs can be organized by feature:

- `schema/root.graphql` -- the root `Query`, `Mutation`, and `Subscription` types.
- `schema/scalars.graphql` -- custom scalar declarations such as `DateTime` and `JSON`.
- `schema/directives.graphql` -- directive definitions.
- `schema/examples.graphql` -- feature/domain type definitions.

The loader merges these into one schema before validation. Conceptually:

```xiom
GraphQLSchema.load("schema/root.graphql")
  .with_scalar("DateTime", date_time_scalar)
  .with_resolver("Query.user", query_user)
  .with_resolver("Mutation.createUser", create_user)
  .freeze()
```

## Immutability and safety

Freezing is a hard boundary. Once a `FrozenSchema` exists, the registry is read-only, which makes execution predictable and concurrency-safe. Any attempt to register scalars or resolvers after freezing is a programming error and is reported as such. This immutability is what lets the execution engine treat the schema as a stable contract throughout a request's lifetime.
