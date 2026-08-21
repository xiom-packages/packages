# xiom-mongo

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** MongoDB client: BSON documents, collections, queries, and cursors.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `bson` | BSON document encoding and decoding. |
| `mongo` | MongoDB wire-protocol client (connect, CRUD, aggregation). |
| `mongo_cursor` | Cursor-based iteration over query results. |
