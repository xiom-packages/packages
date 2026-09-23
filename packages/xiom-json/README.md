# xiom.json

> **Status:** Implemented and ported to compiler 0.61.3 / pinned stdlib.
> Conformance: 12/12 PASS (`scripts/port.ps1 -Package xiom.json`,
> `program_exit=0`). **Not published** -- publication remains out of scope.
> **Scope:** JSON parsing, serialization, and manipulation.
> **Deps:** stdlib only (pure XIOM; no FFI).
>
> Port notes and known limitations are recorded in [SPEC.md](SPEC.md)
> ("Port Notes" section).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `json` | JSON parse/serialize and value model |
| `json-path` | JSONPath query engine |
| `json-pointer` | JSON Pointer (RFC 6901) access |
| `json-schema` | JSON Schema validation |
