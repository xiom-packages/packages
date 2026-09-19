# xiom.helm

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Kubernetes package management (charts, releases, repositories, values).
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `chart` | Chart package creation and validation |
| `release` | Release install, upgrade, rollback |
| `repo` | Repository index and sync |
| `values` | Value templating and overrides |
| `template` | Chart-to-manifest rendering |
