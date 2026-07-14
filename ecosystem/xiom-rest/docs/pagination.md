# Pagination

> Status: Design stage — specification only, not yet implemented.

Pagination keeps large collections predictable, stable, and cheap to serve. `xiom-rest` treats pagination as a first-class, typed concern rather than an ad-hoc convention buried in each handler. Two strategies are supported: page-number pagination for small or stable datasets, and cursor pagination for large or mutable ones. In both cases the request parameters are parsed into typed structures before any business logic runs.

## Page-number pagination

The simplest model exposes `page` and `limit` query parameters and returns a slice of the collection plus metadata. `parse_page_request(query)` validates these into a `PageRequest { page: UInt; limit: UInt; }`, applying sane defaults and an upper bound on `limit` so a client cannot request an unbounded page. The contract `ensures result.limit > 0` guarantees downstream code never has to handle a zero-sized page. Page-number pagination is convenient because offsets are easy to reason about, but it is only appropriate where the underlying data is stable enough that deterministic offsets remain meaningful between requests.

## Cursor pagination

For large or frequently changing datasets, offset-based paging drifts: rows inserted or deleted between requests cause items to be skipped or repeated. Cursor pagination avoids this by encoding an opaque position token. `parse_cursor(query)` reads an optional `cursor` parameter, and handlers return a `CursorPage[T] { items: Vec[T]; next_cursor: Option[Str]; prev_cursor: Option[Str]; }`. The cursor is treated as opaque to clients — they echo it back rather than constructing it — which lets the server change its internal keyset strategy without breaking consumers. This is the recommended default for anything that grows or mutates.

## Response metadata

Both strategies produce stable metadata via `page_meta(req, total)`, yielding a `PageMeta { total: Option[UInt]; page: UInt; limit: UInt; }`. `total` is optional because computing an exact count is sometimes expensive or meaningless for cursor streams. The metadata, together with any `next_cursor`/`prev_cursor` values, is carried in the standard list envelope so clients always find pagination information in a predictable place.

## Contracts and defaults

Parsing functions return `Result[_, RestError]`, so malformed parameters (a negative page, a non-numeric limit) become typed `400`-class errors rather than surprises deep in a query. The default convention is to prefer cursor pagination for large or mutable datasets, support page/limit only where deterministic offsets are acceptable, and always return stable next-page metadata.
