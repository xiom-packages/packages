# Validation

> Status: Design stage -- specification only.

## Validate before execute

The defining rule of `xiom.graphql`'s engine is that **validation happens before execution**. GraphQL validates an incoming operation against the schema, and if the operation is invalid, execution never starts -- no resolver is called and no data is fetched. `xiom.graphql` makes this explicit by separating the `parse`, `validate`, and `execute` phases, each with its own typed error type.

This is the GraphQL analogue of XIOM's contract-checking philosophy: an operation is a request to run against the schema contract, and the contract is checked up front rather than discovered mid-execution.

## What validation checks

The validate phase runs against the frozen schema and inspects the parsed operation for:

- **Field existence** -- every selected field exists on its parent type.
- **Argument correctness** -- arguments are named, typed, and required-checked against field definitions.
- **Fragment validity** -- fragment type conditions are legal and fragments do not form cycles.
- **Variable usage** -- declared variables are used, used variables are declared, and their types are compatible with the positions they appear in.
- **Selection legality** -- leaf fields have no sub-selections, composite fields do, and unions/interfaces are queried through valid fragments.
- **Directive placement** -- directives appear only in locations their definitions permit, with valid arguments.

## Typed error set

Validation does not throw or short-circuit on the first problem. It collects a set of `ValidationError` values so the client receives a complete report of everything wrong with the operation. Each error carries a human-readable message plus source locations, and is serialized into the standard GraphQL `errors` array.

Because validation is a distinct phase with its own error type, it is impossible to confuse a *validation* failure (the request was malformed or illegal) with an *execution* failure (a resolver failed while producing data). That distinction is preserved end to end -- see `error-model.md`.

## Schema validation vs operation validation

There are two validation surfaces:

- **Schema validation** runs once, at load time, to guarantee the composed schema is internally consistent before it is frozen (see `schema-loading.md`).
- **Operation validation** runs per request, checking the client's query/mutation/subscription against that frozen schema.

Both reuse the same type-system model, so the rules that define a valid schema and the rules that define a valid operation stay consistent.
