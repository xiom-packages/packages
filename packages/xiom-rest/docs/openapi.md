# OpenAPI

> Status: Design stage -- specification only, not yet implemented.

Documentation drifts the moment it is written by hand. `xiom-rest` avoids this by generating OpenAPI descriptions directly from the same declarative `RestModule` definitions used for routing, enriched with the `requires`/`ensures` contract metadata XIOM already carries. The specification is derived from the code, not maintained alongside it, so the docs cannot silently fall out of step with the implementation.

## Generating from resource definitions

`generate(modules)` walks a set of `RestModule` values and produces an `OpenApiDoc { openapi: Str; info: ApiInfo; paths: Vec[PathItem]; }`. Each resource contributes its collection and item paths, each route contributes an operation with its HTTP method, and versioning and deprecation metadata attached during routing flow straight into the document. Because a `RestModule` is a pure description, generation is deterministic: the same modules always yield the same document, which makes the output diffable and reviewable in version control.

## Deriving parameters and schemas

The generator draws on the typed structures the rest of the package already defines. Pagination parameters (`page`, `limit`, `cursor`), the allow-listed filter fields and operators, and the permitted sort keys all become documented query parameters, so the generated spec reflects exactly what the parsing layer will accept. Response bodies are described from the resource types and the standard envelopes (`ItemEnvelope`, `ListEnvelope`, `ErrorEnvelope`), and XIOM contracts contribute constraints -- a `requires` on a field becomes a documented validation rule rather than tribal knowledge.

## Serialization

`to_json(doc)` serializes the document to OpenAPI JSON via `xiom-json`. The result is a standard artifact that can be served from an endpoint, checked into a repository, fed to client-generator tooling, or rendered by any OpenAPI-aware UI. Keeping serialization separate from generation means the in-memory `OpenApiDoc` can also be inspected or transformed programmatically before being emitted.

## Philosophy

OpenAPI support embodies the package's stance that documentation is a projection of the contract, not a parallel manuscript. Because the spec is generated from routes, types, and contracts, three things stay aligned automatically: what the server accepts, what it returns, and what it says it does. This closes the common gap between an API's advertised behavior and its real behavior, with no framework magic and no hand-maintained schema files.
