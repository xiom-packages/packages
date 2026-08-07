# xiom-rpc

> **Status:** PLACEHOLDER — reserved, spec pending. No implementation yet.
> **Scope:** Generic RPC framework for serialized remote procedure calls.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `rpc-client` | Client-side proxy for invoking remote procedures. |
| `rpc-server` | Server-side dispatcher for registered handlers. |
| `codec` | Request/response serialization and framing. |
| `registry` | Procedure name to handler registration. |
| `dispatcher` | Call routing, error mapping, and concurrency. |
