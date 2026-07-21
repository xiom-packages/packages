# xiom-math — Production Roadmap

**Version**: v0.2.0 | **Rating**: 8/10 | **Compiler**: xiomc v0.49.7

## Current State

| Criterion | Status |
|-----------|--------|
| ✅ Safe wrappers | 68 pub fn, 5 safety contracts |
| ✅ No workarounds | Pure XIOM, no C FFI |
| ✅ Examples | demo_math.xi — 12 methods exercised |
| ✅ Tests | 18 conformance tests |
| ✅ Contracts | div_scalar, element, perspective, ortho guarded |
| ⬜ SPEC.md | Missing |
| ⬜ README.md | Missing |

## Contracts Added
- `Vec2.div_scalar`, `Vec3.div_scalar` → `requires: s != 0.0`
- `Mat4.element` → `requires: row/col in [0,4)`
- `Mat4.perspective` → `requires: fov>0, aspect>0, near>0, far>near`
- `Mat4.ortho` → `requires: left<right, bottom<top, near!=far`

## Future
- `approx_eq` helpers, `Float64` variants, SIMD/GPU acceleration
