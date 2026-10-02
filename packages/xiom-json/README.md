# xiom.json

> **Status:** `ported` -- conformance-tested (44/44); not yet published.
> **Scope:** JSON parsing, serialization, and manipulation.
> **Deps:** stdlib only (pure XIOM; no FFI).
>
> Port notes, contract inventory and known limitations are recorded in
> [SPEC.md](SPEC.md) ("Port Notes" and "Stable Preparation" sections).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `json` | JSON parse/serialize, value model, manipulation (`json_get`/`json_set`/`json_remove`/`json_merge`/`json_clone`), JSONPath subset (`json_path_parse`/`json_get_path`/`json_set_path`), JSON Schema draft-04 subset (`json_schema_validate`) |

All capabilities live in the single module `src/json.xi`. This package
contains no JSON Pointer (RFC 6901) implementation.
