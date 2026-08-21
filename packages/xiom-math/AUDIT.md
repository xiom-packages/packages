# AUDIT -- xiom-math

## Dependency Audit

| Dependency | Version | Required | Notes |
|---|---|---|---|
| xiom-std | 0.1.0 | Yes | Standard library (xiom.math for sqrt/sin/cos/tan/atan2/acos/abs/min/max) |
| External / FFI | None | No | Pure XIOM -- no C bindings, no native libs |
| Other ecosystem packages | None | No | Self-contained |

## Audit Summary

- **Zero external dependencies** beyond the XIOM standard library
- **No C FFI** -- all math through the pure XIOM `xiom.math` stdlib module
- **No cryptographic requirements**
- **No network or I/O requirements**
- **Thread safety**: All types are plain data structs (value types) with no mutable global state; safe for concurrent read access
- **Memory**: Mat4 uses a const-generic `[16]Float32` array. All types are stack-allocated value types with no heap allocations.

## Design

- **Mat4**: Column-major storage (Vulkan convention), 16-element `[16]Float32` array. `element(row, col)` returns `m[col * 4 + row]`.
- **Quat**: Hamilton convention (w + xi + yj + zk). `to_mat4()` produces column-major rotation matrix.
- **All angles**: Radians throughout.
- **All scalars**: `Float32` for GPU/Vulkan compatibility. Math builtins (sqrt/sin/cos/etc.) operate on `Float64`; explicit `as` casts used at call sites.
- **Module layout**: Sub-modules (`xiom.math.vec2`, `xiom.math.vec3`, `xiom.math.vec4`, `xiom.math.mat4`, `xiom.math.quat`) are standalone. Optional convenience prelude at `xiom.math.prelude` (file `math.xi`) re-exports all 69 methods.

## Compiler Gap Status (v0.46.0 "Production")

| Gap | Description | Status | Workaround |
|-----|-------------|--------|------------|
| **Gap E** | Same-type first explicit param swaps argument positions in cross-module method dispatch. `fn T.lerp(other: T, t: Float32)` called as `a.lerp(b, 0.5)` from another module gives `argument 1 type mismatch: expected Float32, found T`. | **OPEN** | Reorder params: `fn T.lerp(t: Float32, other: T)`. Applied to `Vec2.lerp`, `Vec3.lerp`, `Quat.slerp`. Single-param same-type methods (dot, cross, add, sub, etc.) are unaffected. |
| ~~Gap F~~ | `[N]T` arrays unsupported as struct fields. Parser would reject `m: [16]Float32` in struct definitions. | **CLOSED v0.46** | -- |
| ~~Gap G~~ | Method imports require per-symbol `use` paths. `use xiom.math.vec2;` did not make `Vec2` or `Vec2.new` available. | **CLOSED v0.46** | -- |
| **Gap C** (pre-existing) | Out-parameter move semantics (E001). Passing values to methods/struct constructors triggers "use of moved value" borrow warnings. Non-fatal -- compilation succeeds with `{"status":"ok"}`. | **OPEN** | None needed. Affects all modules uniformly. 7 E001 warnings in `mat4.xi` (look_at), 56+ in coverage test. |
| -- | `module xiom.math` name collision with stdlib `xiom.math`. When `math.xi` (the prelude) claimed `module xiom.math`, it shadowed stdlib math functions in joint compilation. | **FIXED** (design) | Renamed prelude to `module xiom.math.prelude`. All source files use `use xiom.math;` (stdlib) + `use xiom.math.vec2;` etc. (local). |

## Compile Verification (v0.46.0)

| File | Lines | Status | Notes |
|------|-------|--------|-------|
| `src/vec2.xi` | 76 | `{"status":"ok"}` | 0 errors |
| `src/vec3.xi` | 83 | `{"status":"ok"}` | 0 errors |
| `src/vec4.xi` | 44 | `{"status":"ok"}` | 0 errors |
| `src/mat4.xi` | 245 | `{"status":"ok"}` | 6 E001 borrow warnings (non-fatal) |
| `src/quat.xi` | 163 | `{"status":"ok"}` | 0 errors |
| `math.xi` | 74 | `{"status":"ok"}` | Prelude re-export |
| `examples/demo_math.xi` | 79 | `{"status":"ok"}` | 7 E001 borrow warnings (non-fatal) |
| Coverage test (69 methods) | 104 | `{"status":"ok"}` | 100% method coverage, 56 E001 warnings |

## Public API Surface

| Type | Methods | Count |
|------|---------|-------|
| **Vec2** | new, zero, add, sub, mul_scalar, div_scalar, dot, length, length_sq, normalize, lerp, distance, negate, abs, min, max | 16 |
| **Vec3** | new, zero, add, sub, mul_scalar, div_scalar, dot, cross, length, length_sq, normalize, lerp, distance, negate, reflect, project_onto | 16 |
| **Vec4** | new, zero, from_vec3, add, sub, mul_scalar, dot, length, length_sq, normalize, to_vec3 | 11 |
| **Mat4** | identity, zero, translate, rotate, scale, perspective, ortho, look_at, mul_rhs, mul_vec3, mul_vec4, transpose, determinant, inverse, element | 15 |
| **Quat** | identity, from_axis_angle, from_euler, mul_rhs, normalize, conjugate, inverse, to_mat4, slerp, rotate_vec | 10 |
| **Total** | | **68** |

## Security

- No input validation beyond type system guarantees (Float32 bounds enforced by hardware)
- Normalize / inverse operations guard against division by zero
- No secrets, no environment variables, no file I/O
