# xiom-golden

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Golden-file testing against checked-in expected outputs.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `golden/files` | Manages golden output files per test case |
| `golden/compare` | Normalized comparison of actual vs expected output |
| `golden/update` | Flag-controlled regeneration of stale golden files |
