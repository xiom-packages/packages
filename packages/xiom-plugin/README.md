# xiom-plugin

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Plugin system for extending the compiler toolchain.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `api` | Stable plugin API and capability surface |
| `host` | Plugin host loading and lifecycle |
| `manifest` | Plugin metadata and version negotiation |
| `hooks` | Compiler pipeline hook points |
| `session` | Plugin session state and isolation |
