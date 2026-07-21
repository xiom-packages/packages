# Schema-First Design

> Status: Design stage — specification only.

## The schema is the contract

In `xiom-graphql`, the GraphQL SDL is the single source of truth for the API. Every type, field, argument, and directive that a client can reach is declared in `.graphql` files. Code never invents fields or types outside the schema, and it never silently exposes more than the schema promises. This mirrors the schema-first philosophy used by mature production GraphQL systems, where the schema is designed first and the implementation is written to satisfy it.

This is a deliberate fit with XIOM. XIOM already treats contracts as first-class: functions carry preconditions and postconditions, and boundaries are machine-checkable. GraphQL adds a second, complementary contract layer — it validates every incoming operation against the schema *before* execution begins. Schema-first is therefore the natural pairing for a language that favors explicit invariants and verifiable intent.

## Separation of concerns

Schema-first also enforces a clean three-layer separation that keeps servers maintainable as they grow:

1. **Schema** — defines the public API surface and its shapes.
2. **Resolvers** — thin bridges that mediate between API consumers and application logic.
3. **Data sources** — retrieve and shape the underlying data.

Because the schema is authored independently of the resolvers, the public contract can be reviewed, versioned, and diffed on its own terms. Consumers depend on the schema, not on implementation details, and the implementation is free to change as long as it continues to honor the declared contract.

## Consequences for the package

Treating the schema as the source of truth drives several concrete design choices elsewhere in `xiom-graphql`:

- Schema loading composes SDL fragments and freezes an immutable registry (see `schema-loading.md`).
- Validation runs against the frozen schema before any resolver is called (see `validation.md`).
- Resolvers are bound to named schema fields explicitly, never discovered by reflection (see `resolvers.md`).
- Introspection is derived directly from the same registry, so tooling always sees exactly what is served.

The result is a server where the schema you read is the API you get — nothing more, nothing less.
