# xiom-rest Architecture

> **Status: Design stage — specification only, not yet implemented. Depends on xiom-http.**

`xiom-rest` is the REST-oriented extension package built on top of `xiom-http`. Its purpose is to provide resource-centric API conventions, pagination, filtering, content negotiation, versioning, error mapping, and documentation helpers without bloating the core HTTP foundation. REST best practices consistently emphasize resource naming, correct HTTP method usage, pagination, versioning, status codes, and content negotiation.

The guiding principle is simple: `xiom-http` gives you transport primitives; `xiom-rest` gives you opinionated REST structure. This keeps the core small and auditable while still allowing users to build ergonomic APIs quickly.

## Why this package exists

REST helpers are valuable, but they are not the same thing as the HTTP transport. Keeping them separate lets `xiom-http` stay minimal while `xiom-rest` evolves conventions, response shapes, and docs generation without forcing those opinions into every HTTP user.

The separation also preserves XIOM's contract philosophy. Every REST helper is expected to carry `requires`/`ensures` contracts, surface failures as typed errors, and avoid framework magic or global mutable state. Users who only need raw transport pay no cost for REST conventions they do not use.

## Design goals

- Make REST APIs easy to define without hiding HTTP.
- Keep resource routes explicit and versionable.
- Make pagination and filtering reusable.
- Ensure all helpers remain compatible with XIOM contracts and typed errors.
- Avoid framework magic or global mutable state.

## What belongs here

- Resource-oriented routing helpers.
- Nested resource composition.
- Pagination and cursor helpers.
- Filtering and sorting helpers.
- Versioning conventions.
- Content negotiation helpers.
- REST error mapping.
- OpenAPI/schema export helpers.
- HATEOAS-style link generation if enabled.

## What does not belong here

- HTTP transport itself.
- Low-level request/response types.
- WebSocket support.
- GraphQL execution.
- Microservice discovery.
- Real-time pub/sub primitives.

## Repository scaffold

The scaffold below describes the intended module tree once implementation begins. At the design stage only the manifest and documentation exist; no `.xi` source files are present yet.

```text
xiom-rest/
├── package.xi
├── README.md
├── ARCHITECTURE.md
├── SPEC.md
├── docs/
│   ├── resource-routing.md
│   ├── pagination.md
│   ├── filtering-and-sorting.md
│   ├── versioning.md
│   ├── content-negotiation.md
│   ├── error-model.md
│   └── openapi.md
├── src/                        # planned — not yet implemented
│   ├── mod.xi
│   ├── resource.xi
│   ├── router.xi
│   ├── route_builder.xi
│   ├── versioning.xi
│   ├── pagination.xi
│   ├── filtering.xi
│   ├── sorting.xi
│   ├── negotiation.xi
│   ├── errors.xi
│   ├── links.xi
│   ├── openapi.xi
│   ├── response_shape.xi
│   └── testing/
│       ├── mod.xi
│       └── fixtures.xi
└── tests/                      # planned — not yet implemented
    ├── routing/
    ├── pagination/
    ├── versioning/
    └── negotiation/
```

## Core module responsibilities

### `src/resource.xi`
Defines the resource abstraction: collection endpoints, item endpoints, nested subresources, and relationship paths.

### `src/router.xi`
Translates resource definitions into `xiom-http` route registrations. It should remain thin and deterministic.

### `src/route_builder.xi`
Declarative builder for REST endpoints. Enables concise route definition without losing explicitness.

### `src/versioning.xi`
Route versioning policy, URI versioning, header versioning, and deprecation helpers.

### `src/pagination.xi`
Cursor and page-number pagination primitives. REST guidance strongly recommends explicit pagination to keep large result sets predictable and stable.

### `src/filtering.xi`
Query parameter parsing and typed filter objects for list endpoints.

### `src/sorting.xi`
Sorting keys, order direction, and validation.

### `src/negotiation.xi`
Content negotiation for JSON and optional alternative representations.

### `src/errors.xi`
REST-friendly error mapping from typed XIOM errors to HTTP status codes and structured error bodies.

### `src/links.xi`
Optional HATEOAS-style link builders for discoverability.

### `src/openapi.xi`
OpenAPI generation from route/resource definitions and XIOM contracts.

### `src/response_shape.xi`
Standard envelopes for list responses, single-resource responses, and error payloads.

## Idiomatic XIOM translation of REST ideas

| REST concept | XIOM-rest implementation |
|---|---|
| Resource-oriented URI design | `resource[T]()` builders with collection/item subroutes |
| Nested routers | Route composition through module-scoped builders |
| Pagination | Typed `PageRequest` / `CursorPage` models |
| Filtering/sorting | Structured query types with contract validation |
| Content negotiation | Explicit `Accept` handling with typed serializers |
| Versioning | Versioned route groups and deprecation metadata |
| Error handling | Typed error-to-status mapping with stable payload shape |
| OpenAPI docs | Generated from route/resource definitions and XIOM contracts |

## Recommended default conventions

### Routes
- Use nouns for resources.
- Use plural collection routes and singular item routes.
- Keep nesting shallow.
- Avoid action-heavy URIs unless the operation is truly non-resource-like.

### Pagination
- Prefer cursor pagination for large or mutable datasets.
- Support page/limit only where deterministic offsets are acceptable.
- Return stable next-page metadata.

### Filtering and sorting
- Parse filters into typed structures before business logic runs.
- Reject unknown operators by default.
- Keep sorting keys explicit and validated.

### Errors
- Use structured error bodies.
- Map domain errors to stable HTTP status codes.
- Include machine-readable error codes for clients.

### Versioning
- Version by route group or header.
- Avoid silent breaking changes.
- Deprecate with explicit metadata.

## Example route module

```xiom
module api.users

use xiom_http
use xiom_rest

pub type User = {
  id: UInt;
  name: Str;
  email: Str;
} derive[Eq, Clone, Display]

pub fn routes() -> RestModule {
  return RestModule.new("users")
    .get_list(list_users)
    .post(create_user)
    .get_item(get_user)
    .patch_item(update_user)
    .delete_item(delete_user)
}
```

## Checklist

### Must-have
- [ ] Resource routing helpers.
- [ ] Pagination.
- [ ] Filtering and sorting.
- [ ] Versioning support.
- [ ] Error-to-status mapping.
- [ ] OpenAPI generation.

### Should-have
- [ ] Content negotiation.
- [ ] HATEOAS link helpers.
- [ ] Response envelopes.
- [ ] Testing fixtures.

### Future
- [ ] Policy-driven caching hints.
- [ ] ETag/conditional request helpers.
- [ ] API diff tooling.
- [ ] REST linting.

## References

The conventions above are informed by widely published REST API design guidance, including:

- Microsoft Azure Architecture Center — API design best practices.
- Zuplo — API design patterns.
- Strapi — RESTful API design guide.
- DeepDocs — REST API best practices.
- Grizzly Peak Software — Express.js router patterns for large applications.
