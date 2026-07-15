# AUDIT — xiom-math

## Dependency Audit

| Dependency | Version | Required | Notes |
|---|---|---|---|
| xiom-std | 0.1.0 | Yes | Standard library (xiom.math for sqrt/sin/cos/tan/atan2/acos/abs/min/max) |
| External / FFI | None | No | Pure XIOM — no C bindings, no native libs |
| Other ecosystem packages | None | No | Self-contained |

## Audit Summary

- **Zero external dependencies** beyond the XIOM standard library
- **No C FFI** — all math through the pure XIOM `xiom.math` stdlib module
- **No cryptographic requirements**
- **No network or I/O requirements**
- **Thread safety**: All types are plain data structs (value types) with no mutable global state; safe for concurrent read access
- **Memory**: Mat4 uses a const-generic `[16]Float32` array. All types are stack-allocated value types with no heap allocations.

## Design

- **Mat4**: Column-major storage (Vulkan convention), 16-element `[16]Float32` array. `element(row, col)` returns `m[col * 4 + row]`.
- **Quat**: Hamilton convention (w + xi + yj + zk). `to_mat4()` produces column-major rotation matrix.
- **All angles**: Radians throughout.
- **All scalars**: `Float32` for GPU/Vulkan compatibility. Math builtins (sqrt/sin/cos/etc.) operate on `Float64`; explicit `as` casts used at call sites.

## Known Compiler Gaps (v0.45.3)

These affect correctness but are documented in `docs/ROADMAP.md` §5c.15 for compiler-side fixes:

| Gap | Impact | File |
|-----|--------|------|
| **Gap E**: Same-type first param swaps args cross-module | lerp/slerp use `(other: T, t: Float32)` — correct intent | vec2.xi, vec3.xi, quat.xi |
| **Gap F**: `[N]T` array element type not inferred | `m[i] = 1.0 as Float32` treated as `Int = Float32` | mat4.xi, quat.xi |
| **Gap G**: Method imports require per-symbol `use` | math.xi enumerates all 69 public methods | math.xi |

## Security

- No input validation beyond type system guarantees (Float32 bounds enforced by hardware)
- Normalize / inverse operations guard against division by zero
- No secrets, no environment variables, no file I/O
