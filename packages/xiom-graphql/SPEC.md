# xiom.graphql -- Specification

> **Status: v0.1.0 implemented.** Core types, schema builder, query parser/validator stubs, execution stub, and introspection stub are implemented in `graphql.xi`. Full SDL parser, validation rules, and execution engine are planned for future versions.

## Overview

`xiom.graphql` is the schema-first GraphQL server package for XIOM, layered on top of `xiom.http` for transport, `xiom.json` for payload encoding, and `xiom.websocket` for subscription delivery. It owns SDL loading and composition, schema and operation validation, execution, resolver wiring, the typed error model, introspection, batching, and subscription protocol semantics.

The engine is organized around four explicit phases -- **parse -> validate -> execute -> complete** -- and around the rule that the schema is the single source of truth.

## Module

- **Module:** `xiom.graphql`
- **Version:** 0.1.0
- **Dependencies:** `xiom.string`, `xiom.convert` (pure XIOM)

---

## Implemented Types (v0.1.0)

### `GraphQLSchema`

```xiom
pub type GraphQLSchema = {
  types: Vec[GraphQLType];
  query_type: Str;
  mutation_type: Str;
  subscription_type: Str;
} derive[Clone]
```

### `GraphQLType`

```xiom
pub type GraphQLType = {
  name: Str;
  kind: GraphQLTypeKind;
  fields: Vec[GraphQLField];
  interfaces: Vec[Str];
} derive[Clone]
```

### `GraphQLTypeKind` (enum)

```
pub enum GraphQLTypeKind {
  Scalar, Object, Interface, Union, Enum, InputObject, List, NonNull
} derive[Clone]
```

### `GraphQLField`

```xiom
pub type GraphQLField = {
  name: Str;
  type_ref: Str;
  args: Vec[GraphQLArg];
  is_deprecated: Bool;
  deprecation_reason: Str;
} derive[Clone]
```

### `GraphQLArg`

```xiom
pub type GraphQLArg = {
  name: Str;
  type_ref: Str;
  default_value: Option[Str];
} derive[Clone]
```

### AST Nodes

| Type | Purpose |
|------|---------|
| `GraphQLDocument` | Top-level document with operations and fragments |
| `GraphQLOperation` | Single operation (query/mutation/subscription) with selection set |
| `GraphQLFragment` | Named fragment with type condition and selection set |
| `GraphQLSelectionSet` | Ordered list of selections |
| `GraphQLSelection` (enum) | Field, FragmentSpread, or InlineFragment |
| `GraphQLFieldSelection` | Field selection with alias, args, directives, nested selection set |
| `GraphQLFragmentSpread` | Named fragment spread with directives |
| `GraphQLInlineFragment` | Inline fragment with type condition and selection set |
| `GraphQLArgument` | Named argument with value |
| `GraphQLDirective` | Named directive with arguments |
| `GraphQLValue` (enum) | Int, Float, String, Boolean, Null, Enum, List, Object, Variable |
| `GraphQLObjectField` | Named field within an object value |

### Error Types

| Type | Fields |
|------|--------|
| `GraphQLError` | message, path, locations |
| `ParseError` | message, line, column |
| `ValidationError` | message, rule, path |

### `ExecutionResult`

```xiom
pub type ExecutionResult = {
  data: Option[GraphQLValue];
  errors: Vec[GraphQLError];
} derive[Clone]
```

---

## Implemented API (v0.1.0)

### Schema Builder

| Function | Signature |
|----------|-----------|
| `schema_new` | `() -> GraphQLSchema` |
| `schema_add_type` | `(schema: &mut GraphQLSchema, t: GraphQLType)` |
| `schema_find_type` | `(schema: &GraphQLSchema, name: Str) -> Option[GraphQLType]` |
| `schema_has_type` | `(schema: &GraphQLSchema, name: Str) -> Bool` |

### Type Builder

| Function | Signature |
|----------|-----------|
| `type_new` | `(name: Str, kind: GraphQLTypeKind) -> GraphQLType` |
| `type_add_field` | `(t: &mut GraphQLType, field: GraphQLField)` |
| `type_find_field` | `(t: &GraphQLType, name: Str) -> Option[GraphQLField]` |

### Field & Arg Builder

| Function | Signature |
|----------|-----------|
| `field_new` | `(name: Str, type_ref: Str) -> GraphQLField` |
| `field_add_arg` | `(field: &mut GraphQLField, arg: GraphQLArg)` |
| `field_deprecate` | `(field: &mut GraphQLField, reason: Str)` |
| `arg_new` | `(name: Str, type_ref: Str) -> GraphQLArg` |

### Value Constructors

| Function | Returns |
|----------|---------|
| `value_int(n: Int)` | `GraphQLValue` |
| `value_float(n: Float64)` | `GraphQLValue` |
| `value_string(s: Str)` | `GraphQLValue` |
| `value_bool(b: Bool)` | `GraphQLValue` |
| `value_null()` | `GraphQLValue` |
| `value_variable(name: Str)` | `GraphQLValue` |

### Operation Builder

| Function | Signature |
|----------|-----------|
| `operation_new` | `(op_type: OperationType, name: Str) -> GraphQLOperation` |
| `operation_add_field` | `(op: &mut GraphQLOperation, field: GraphQLFieldSelection)` |

### Query Parser Stubs

| Function | Signature |
|----------|-----------|
| `parse_query` | `(source: Str) -> Result[GraphQLDocument, ParseError]` |

Detects operation keyword (`query`, `mutation`, `subscription`) from source prefix. Full recursive-descent parser planned for v0.2.0.

### Validator Stubs

| Function | Signature |
|----------|-----------|
| `validate_operation` | `(schema: &GraphQLSchema, op: &GraphQLOperation) -> Result[Unit, Vec[ValidationError]]` |
| `validate_document` | `(schema: &GraphQLSchema, doc: &GraphQLDocument) -> Result[Unit, Vec[ValidationError]]` |

Validates root type existence and top-level field existence on the root type. Full validation rule set planned for v0.4.0.

### Execution Stub

| Function | Signature |
|----------|-----------|
| `execute` | `(schema: &GraphQLSchema, doc: &GraphQLDocument, op_name: Str) -> Result[ExecutionResult, GraphQLError]` |

Returns empty data for valid schemas. Full execution engine planned for v0.5.0.

### Introspection Stubs

| Function | Signature |
|----------|-----------|
| `introspect_schema` | `(schema: &GraphQLSchema) -> GraphQLType` |
| `schema_type_count` | `(schema: &GraphQLSchema) -> Int` |

---

## Engine Phases (Summary)

| Phase | Status | Output | Error type |
|-------|--------|--------|------------|
| Parse | Stub | `Document` (AST) | `ParseError` |
| Validate | Stub | validated operation | `Vec[ValidationError]` |
| Execute | Stub | `ExecutionResult` | `GraphQLError` |
| Complete | Planned | `GraphQLResponse` | serialized errors |

## Planned Modules (Future Versions)

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

## Design Rules (Contract Philosophy)

- The schema is the public contract; nothing outside it is served.
- Resolvers are thin and explicit, returning `Result[T, GraphQLError]`.
- Validation always precedes execution -- invalid operations fail before data fetching.
- Batching (DataLoader) is the default recommendation for nested fields.
- Transport and GraphQL protocol are kept separate.
- Subscriptions are transport-agnostic typed streams.
- Contracts at boundaries, typed errors throughout.
