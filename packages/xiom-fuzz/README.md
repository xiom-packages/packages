# xiom-fuzz

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Coverage-guided fuzzing driver and corpus management.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `fuzz/gen` | Arbitrary byte and structured input mutation |
| `fuzz/corpus` | Seed corpus storage and minimization |
| `fuzz/driver` | Runs targets under coverage-guided feedback |
