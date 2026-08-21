# Filtering and Sorting

> Status: Design stage -- specification only, not yet implemented.

Filtering and sorting let clients narrow and order collection results without bespoke endpoints for every query shape. `xiom-rest` models both as typed, validated structures produced from query parameters *before* any business logic executes. This keeps handlers clean, makes queries auditable, and prevents untrusted input from flowing directly into data-access code.

## Typed filters

A filter is a `FilterClause { field: Str; op: FilterOp; value: Str; }`, where `FilterOp` is a closed enum (`Eq`, `Ne`, `Lt`, `Lte`, `Gt`, `Gte`, `In`, `Like`). `parse_filters(query, allowed)` turns raw query parameters into a `FilterSet`, validating each clause against an explicit allow-list of fields. The allow-list is the security boundary: any field not on it is rejected, and unknown operators are rejected by default. This deliberately conservative stance means a client cannot filter on columns the API did not intend to expose, and it prevents accidental leakage of internal schema.

## Typed sorting

Sorting mirrors the same discipline. A `SortSpec { key: Str; dir: SortDir; }` pairs a sort key with a direction (`Asc` or `Desc`), and `parse_sort(query, allowed)` parses one or more sort specifications from the query string against an allow-list of sortable keys. Multi-key sorts are represented as an ordered `Vec[SortSpec]`, so precedence is explicit. As with filters, unknown keys are rejected rather than silently ignored, which avoids the subtle bug where a client believes it is sorting but the server quietly returns unsorted data.

## Why parse before logic

Parsing into typed structures up front separates three concerns cleanly: transport (the query string), policy (what is allowed), and business logic (how the query is executed). Because a `FilterSet` and `Vec[SortSpec]` are just data, they can be inspected, logged, unit-tested, and translated to different backends (SQL, an in-memory store, an external service) without change to the parsing layer. This is the "parse, don't validate later" principle applied to query handling.

## Contracts and errors

`parse_filters` and `parse_sort` return `Result[_, RestError]`. Any violation -- an unknown field, an unsupported operator, a malformed value -- becomes a typed `400`-class error with a machine-readable code, never a panic and never a silently dropped clause. This keeps the contract with clients honest: a query is either accepted in full and understood, or rejected with a clear reason.
