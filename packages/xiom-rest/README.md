# xiom-rest

> REST resource routing, pagination, filtering, content negotiation, and OpenAPI helpers built on xiom-http.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/XIOM-lang/XIOM.git )
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

> Status: Design stage — spec only, not yet implemented.

## Overview

xiom-rest is the REST-oriented extension package layered on top of `xiom-http`. It adds resource-centric routing, pagination, filtering, sorting, versioning, content negotiation, error mapping, and OpenAPI generation — opinionated REST structure without hiding the underlying HTTP transport. The core stays small and auditable while these conventions evolve independently, and every helper is designed around XIOM contracts (`requires`/`ensures`) and typed errors rather than framework magic.

## Dependencies

| Package | Version | Role |
|---------|---------|------|
| `xiom-http` | `0.1.0` | HTTP transport, request/response types, routing primitives |
| `xiom-json` | `0.1.0` | Serialization of resources, envelopes, and error bodies |
| `xiom-std` | `0.1.0` | Core types, `Result`/`Option`, collections |

## Installation

```bash
xiom install xiom-rest
```

## Planned API Reference

> All items below are **Planned** — the signatures are conceptual and subject to change during implementation.

### Resources (`xiom.rest.resource`) — Planned
| Item | Signature | Status |
|------|-----------|--------|
| `RestModule.new` | `(name: Str) -> RestModule` | Planned |
| `RestModule.get_list` | `(handler: ListHandler) -> RestModule` | Planned |
| `RestModule.post` | `(handler: CreateHandler) -> RestModule` | Planned |
| `RestModule.get_item` | `(handler: ItemHandler) -> RestModule` | Planned |
| `RestModule.patch_item` | `(handler: ItemHandler) -> RestModule` | Planned |
| `RestModule.delete_item` | `(handler: ItemHandler) -> RestModule` | Planned |
| `RestModule.nest` | `(child: RestModule) -> RestModule` | Planned |

### Pagination (`xiom.rest.pagination`) — Planned
| Item | Signature | Status |
|------|-----------|--------|
| `PageRequest` | `{ page: UInt; limit: UInt; }` | Planned |
| `CursorPage[T]` | `{ items: Vec[T]; next_cursor: Option[Str]; }` | Planned |
| `parse_page_request` | `(query: &Query) -> Result[PageRequest, RestError]` | Planned |
| `parse_cursor` | `(query: &Query) -> Result[Cursor, RestError]` | Planned |

### Filtering & Sorting (`xiom.rest.filtering`, `xiom.rest.sorting`) — Planned
| Item | Signature | Status |
|------|-----------|--------|
| `FilterSet` | `{ clauses: Vec[FilterClause]; }` | Planned |
| `parse_filters` | `(query: &Query, allowed: Vec[Str]) -> Result[FilterSet, RestError]` | Planned |
| `SortSpec` | `{ key: Str; dir: SortDir; }` | Planned |
| `parse_sort` | `(query: &Query, allowed: Vec[Str]) -> Result[Vec[SortSpec], RestError]` | Planned |

### Versioning (`xiom.rest.versioning`) — Planned
| Item | Signature | Status |
|------|-----------|--------|
| `VersionPolicy` | `enum { Uri, Header }` | Planned |
| `versioned` | `(v: Str, module: RestModule) -> RestModule` | Planned |
| `deprecate` | `(module: RestModule, meta: Deprecation) -> RestModule` | Planned |

### Content Negotiation (`xiom.rest.negotiation`) — Planned
| Item | Signature | Status |
|------|-----------|--------|
| `negotiate` | `(accept: Str, offered: Vec[MediaType]) -> Result[MediaType, RestError]` | Planned |
| `Representation[T]` | `{ media_type: MediaType; encode: fn(&T) -> Vec[Int]; }` | Planned |

### Errors (`xiom.rest.errors`) — Planned
| Item | Signature | Status |
|------|-----------|--------|
| `RestError` | `{ code: Str; status: Int; message: Str; }` | Planned |
| `to_response` | `(err: &RestError) -> HttpResponse` | Planned |
| `map_status` | `(err: &RestError) -> Int` | Planned |

### OpenAPI (`xiom.rest.openapi`) — Planned
| Item | Signature | Status |
|------|-----------|--------|
| `OpenApiDoc` | `{ version: Str; paths: Vec[PathItem]; }` | Planned |
| `generate` | `(modules: Vec[RestModule]) -> OpenApiDoc` | Planned |
| `to_json` | `(doc: &OpenApiDoc) -> Str` | Planned |

## Example (Planned)

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

## Design Documents

- [ARCHITECTURE.md](ARCHITECTURE.md) — package rationale, scaffold, module responsibilities, conventions.
- [SPEC.md](SPEC.md) — planned per-module public API surface.
- [docs/resource-routing.md](docs/resource-routing.md) — resource abstraction and route composition.
- [docs/pagination.md](docs/pagination.md) — cursor and page-number pagination.
- [docs/filtering-and-sorting.md](docs/filtering-and-sorting.md) — typed filters and sort specs.
- [docs/versioning.md](docs/versioning.md) — URI/header versioning and deprecation.
- [docs/content-negotiation.md](docs/content-negotiation.md) — `Accept` handling and representations.
- [docs/error-model.md](docs/error-model.md) — typed error-to-status mapping.
- [docs/openapi.md](docs/openapi.md) — OpenAPI generation from routes and contracts.

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/XIOM-lang/XIOM.git )

## License

MIT OR Apache-2.0
