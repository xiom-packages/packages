# xiom-rest — Specification

> **Status: Planned / not implemented.** This document describes the intended public API surface of `xiom-rest`. All signatures are conceptual sketches to guide implementation; nothing here exists as `.xi` source yet. `xiom-rest` depends on `xiom-http`, `xiom-json`, and `xiom-std`.

## Overview

`xiom-rest` layers resource-oriented REST conventions on top of the `xiom-http` transport. It provides resource routing, pagination, filtering, sorting, versioning, content negotiation, error mapping, HATEOAS links, response envelopes, and OpenAPI generation. Every helper is expected to carry XIOM contracts (`requires`/`ensures`), surface failures as typed errors, and avoid global mutable state or framework magic.

Type sketches use XIOM bracket generics (`Vec[T]`, `Result[T, E]`, `Option[T]`).

---

### `xiom.rest.resource` (`src/resource.xi`) — Planned

Defines the resource abstraction: collection endpoints, item endpoints, nested subresources, and relationship paths. Central builder is `RestModule`.

**Planned types:**
- `RestModule { name: Str; base_path: Str; routes: Vec[RouteDef]; children: Vec[RestModule]; }`
- `RouteDef { method: HttpMethod; kind: RouteKind; handler: HandlerRef; }`
- `RouteKind` — enum: `List`, `Create`, `Item`, `Replace`, `Update`, `Delete`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `RestModule.new` | `(name: Str) -> RestModule` | Create a resource module; `requires name.len() > 0` |
| `RestModule.get_list` | `(self, h: ListHandler) -> RestModule` | Register `GET /{name}` |
| `RestModule.post` | `(self, h: CreateHandler) -> RestModule` | Register `POST /{name}` |
| `RestModule.get_item` | `(self, h: ItemHandler) -> RestModule` | Register `GET /{name}/{id}` |
| `RestModule.patch_item` | `(self, h: ItemHandler) -> RestModule` | Register `PATCH /{name}/{id}` |
| `RestModule.put_item` | `(self, h: ItemHandler) -> RestModule` | Register `PUT /{name}/{id}` |
| `RestModule.delete_item` | `(self, h: ItemHandler) -> RestModule` | Register `DELETE /{name}/{id}` |
| `RestModule.nest` | `(self, child: RestModule) -> RestModule` | Compose a nested subresource |

**Responsibility:** own the resource-to-route mapping; remain declarative and side-effect-free until handed to the router.

---

### `xiom.rest.router` (`src/router.xi`) — Planned

Translates `RestModule` definitions into `xiom-http` route registrations. Thin and deterministic — no business logic.

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `mount` | `(app: &mut HttpApp, module: &RestModule) -> Result[Unit, RestError]` | Register all routes from a module |
| `mount_all` | `(app: &mut HttpApp, modules: Vec[RestModule]) -> Result[Unit, RestError]` | Register a set of modules |
| `resolve_path` | `(module: &RestModule, kind: RouteKind) -> Str` | Compute the concrete path for a route kind |

**Responsibility:** deterministic expansion of resource definitions into concrete `xiom-http` handlers.

---

### `xiom.rest.route_builder` (`src/route_builder.xi`) — Planned

Declarative builder for REST endpoints, enabling concise definition without losing explicitness.

**Planned types:**
- `RouteBuilder { method: HttpMethod; path: Str; middleware: Vec[Middleware]; }`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `route` | `(method: HttpMethod, path: Str) -> RouteBuilder` | Start a route definition; `requires path.len() > 0` |
| `RouteBuilder.with` | `(self, m: Middleware) -> RouteBuilder` | Attach middleware |
| `RouteBuilder.handle` | `(self, h: HandlerRef) -> RouteDef` | Finalize into a `RouteDef` |

**Responsibility:** provide an ergonomic, explicit route-definition surface that lowers to `RouteDef`.

---

### `xiom.rest.versioning` (`src/versioning.xi`) — Planned

Route versioning policy: URI versioning, header versioning, and deprecation helpers.

**Planned types:**
- `VersionPolicy` — enum: `Uri`, `Header`
- `Deprecation { since: Str; sunset: Option[Str]; message: Str; }`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `versioned` | `(version: Str, module: RestModule) -> RestModule` | Wrap a module under a version group |
| `with_policy` | `(module: RestModule, policy: VersionPolicy) -> RestModule` | Set the version resolution strategy |
| `deprecate` | `(module: RestModule, meta: Deprecation) -> RestModule` | Attach deprecation metadata |
| `resolve_version` | `(req: &HttpRequest, policy: VersionPolicy) -> Result[Str, RestError]` | Extract requested version |

**Responsibility:** make versions explicit and prevent silent breaking changes.

---

### `xiom.rest.pagination` (`src/pagination.xi`) — Planned

Cursor and page-number pagination primitives.

**Planned types:**
- `PageRequest { page: UInt; limit: UInt; }`
- `Cursor { token: Str; }`
- `CursorPage[T] { items: Vec[T]; next_cursor: Option[Str]; prev_cursor: Option[Str]; }`
- `PageMeta { total: Option[UInt]; page: UInt; limit: UInt; }`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `parse_page_request` | `(query: &Query) -> Result[PageRequest, RestError]` | Parse `page`/`limit`; `ensures result.limit > 0` |
| `parse_cursor` | `(query: &Query) -> Result[Option[Cursor], RestError]` | Parse `cursor` token |
| `make_cursor_page` | `(items: Vec[T], next: Option[Str]) -> CursorPage[T]` | Build a cursor page envelope |
| `page_meta` | `(req: &PageRequest, total: Option[UInt]) -> PageMeta` | Build pagination metadata |

**Responsibility:** keep large result sets predictable and stable; prefer cursors for mutable datasets.

---

### `xiom.rest.filtering` (`src/filtering.xi`) — Planned

Query parameter parsing and typed filter objects for list endpoints.

**Planned types:**
- `FilterOp` — enum: `Eq`, `Ne`, `Lt`, `Lte`, `Gt`, `Gte`, `In`, `Like`
- `FilterClause { field: Str; op: FilterOp; value: Str; }`
- `FilterSet { clauses: Vec[FilterClause]; }`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `parse_filters` | `(query: &Query, allowed: Vec[Str]) -> Result[FilterSet, RestError]` | Parse and validate filters against an allow-list |
| `FilterSet.get` | `(self, field: Str) -> Option[FilterClause]` | Look up a clause by field |

**Responsibility:** produce typed, validated filters before business logic runs; reject unknown operators by default.

---

### `xiom.rest.sorting` (`src/sorting.xi`) — Planned

Sorting keys, order direction, and validation.

**Planned types:**
- `SortDir` — enum: `Asc`, `Desc`
- `SortSpec { key: Str; dir: SortDir; }`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `parse_sort` | `(query: &Query, allowed: Vec[Str]) -> Result[Vec[SortSpec], RestError]` | Parse `sort` params against an allow-list |
| `SortSpec.to_str` | `(self) -> Str` | Serialize a sort spec |

**Responsibility:** keep sorting keys explicit and validated.

---

### `xiom.rest.negotiation` (`src/negotiation.xi`) — Planned

Content negotiation for JSON and optional alternative representations.

**Planned types:**
- `MediaType { main: Str; sub: Str; quality: Float; }`
- `Representation[T] { media_type: MediaType; encode: fn(&T) -> Vec[Int]; }`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `parse_accept` | `(header: Str) -> Vec[MediaType]` | Parse an `Accept` header into ranked media types |
| `negotiate` | `(accept: Str, offered: Vec[MediaType]) -> Result[MediaType, RestError]` | Choose the best representation |
| `encode` | `(rep: &Representation[T], value: &T) -> Vec[Int]` | Encode a value in the chosen representation |

**Responsibility:** explicit `Accept` handling with typed serializers; default to JSON.

---

### `xiom.rest.errors` (`src/errors.xi`) — Planned

REST-friendly mapping from typed XIOM errors to HTTP status codes and structured error bodies.

**Planned types:**
- `RestError { code: Str; status: Int; message: Str; details: Option[Str]; }`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `RestError.new` | `(code: Str, status: Int, message: Str) -> RestError` | Construct; `requires status >= 100, status < 600` |
| `not_found` / `bad_request` / `conflict` / `unprocessable` | `(message: Str) -> RestError` | Common constructors |
| `map_status` | `(err: &RestError) -> Int` | Resolve the HTTP status code |
| `to_response` | `(err: &RestError) -> HttpResponse` | Render a stable structured error body |

**Responsibility:** map domain errors to stable status codes with machine-readable error codes.

---

### `xiom.rest.links` (`src/links.xi`) — Planned

Optional HATEOAS-style link builders for discoverability.

**Planned types:**
- `Link { rel: Str; href: Str; method: HttpMethod; }`
- `LinkSet { links: Vec[Link]; }`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `self_link` | `(base: Str, id: Str) -> Link` | Build a `self` relation |
| `collection_link` | `(base: Str) -> Link` | Build a collection relation |
| `LinkSet.add` | `(self, link: Link) -> LinkSet` | Append a link |

**Responsibility:** generate discoverability links when HATEOAS is enabled; entirely optional.

---

### `xiom.rest.openapi` (`src/openapi.xi`) — Planned

OpenAPI generation from route/resource definitions and XIOM contracts.

**Planned types:**
- `OpenApiDoc { openapi: Str; info: ApiInfo; paths: Vec[PathItem]; }`
- `PathItem { path: Str; operations: Vec[Operation]; }`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `generate` | `(modules: Vec[RestModule]) -> OpenApiDoc` | Build an OpenAPI document from resource modules |
| `to_json` | `(doc: &OpenApiDoc) -> Str` | Serialize to OpenAPI JSON via `xiom-json` |

**Responsibility:** derive documentation from route definitions and contract metadata, not hand-written schemas.

---

### `xiom.rest.response_shape` (`src/response_shape.xi`) — Planned

Standard envelopes for list responses, single-resource responses, and error payloads.

**Planned types:**
- `ItemEnvelope[T] { data: T; links: Option[LinkSet]; }`
- `ListEnvelope[T] { data: Vec[T]; meta: PageMeta; links: Option[LinkSet]; }`
- `ErrorEnvelope { error: RestError; }`

**Planned API:**
| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `item` | `(value: T) -> ItemEnvelope[T]` | Wrap a single resource |
| `list` | `(items: Vec[T], meta: PageMeta) -> ListEnvelope[T]` | Wrap a collection with metadata |
| `error` | `(err: RestError) -> ErrorEnvelope` | Wrap an error payload |

**Responsibility:** provide consistent, stable response shapes across all endpoints.

---

## Testing (Planned)

- `src/testing/mod.xi` — test helpers and harness entry point.
- `src/testing/fixtures.xi` — reusable resource/request fixtures for routing, pagination, versioning, and negotiation tests.
