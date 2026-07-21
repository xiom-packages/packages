# AUDIT — xiom-jolt (Jolt Physics Bindings)

## Status: BLOCKED — C Bridge Required

JoltPhysics (`E:\repos\JoltPhysics`, upstream: `jrouwe/JoltPhysics` v5.6.0) is a
**pure C++17 library with no C API**. It cannot be called from XIOM directly.

| Item | Status |
|------|--------|
| JoltPhysics C API | **NOT PRESENT** — pure C++17 |
| Third-party C bridge | Exists: `github.com/amerkoleci/joltc` (MIT) |
| XIOM `extern "C"` blocks | ✅ Supported (GAP-2 closed) |
| XIOM `unsafe { }` blocks | ✅ Supported |
| XIOM tail expressions | ✅ Supported (GAP-11 closed) |
| XIOM `Ok(())` unit literal | ✅ Supported (GAP-12 closed) |
| `requires:` contracts | ✅ Supported (GAP-4 closed) |
| Compiled C bridge binary | **MISSING** — must be built separately |

## What Exists

| File | Purpose |
|------|---------|
| `package.xi` | Package manifest (`xiom-jolt v0.1.0`) |
| `jolt.xi` | Flat FFI surface: 50+ functions covering world lifecycle, shapes, bodies, rays, constraints |
| `jolt.xiom-bind` | Raw C ABI declarations mapping to `joltc.dll` (the C bridge) |
| `jolt_safe.xi` | Safe wrappers: `JoltWorld`, `PhysicsBody`, shape builders, `Result[Int, Str]` error handling |
| `demo_jolt.xi` | Minimal physics demo: sphere bouncing on a box floor (300 steps at 60 Hz) |

## C Bridge Gap

The joltc library (amerkoleci/joltc) wraps JoltPhysics in a C ABI:
- ~300+ functions in a flat C namespace (`JPH_*` prefix)
- Opaque handle types (`JPH_PhysicsSystem*`, `JPH_BodyID`, etc.)
- Pod structs for math types (`JPH_Vec3`, `JPH_Quat`, etc.)

**To make these bindings functional:**
1. Clone and build joltc:
   ```
   git clone https://github.com/amerkoleci/joltc
   cd joltc && cmake -B build && cmake --build build --config Release
   ```
2. Place `joltc.dll` / `libjoltc.so` in the XIOM application directory or system path.
3. Generate extern declarations from `.xiom-bind`:
   ```
   xiom ffigen packages/xiom-jolt/jolt.xiom-bind > packages/xiom-jolt/jolt_extern.xi
   ```
4. Compile with `xiomc --link joltc`.

Alternatively, a custom C bridge could be written that wraps Jolt's C++ directly,
following the pattern used by `xiom-vulkan/bridge/xiom_vk_bridge.c`.

## Compiler Gaps Affecting This Package

All previously reported gaps (GAP-1 through GAP-14) are closed as of xiomc v0.33.0.
This package should compile once the C bridge binary is available.

| Gap | Relevance | Status |
|-----|-----------|--------|
| GAP-2 (`extern "C"` blocks) | Required for FFI | ✅ CLOSED |
| GAP-11 (tail expressions) | Used in safe wrappers | ✅ CLOSED |
| GAP-12 (unit literal `()`) | Used in Result[Int, Str] | ✅ CLOSED |
| GAP-14 (bare `is Ok`/`is Err`) | Used in match arms | ✅ CLOSED |
| GAP-10 (trailing `;` after block) | Used in if statements | ✅ CLOSED |
| GAP-4 (`=>` in contracts) | Used in `requires:` | ✅ CLOSED |

## API Coverage

| JoltPhysics Feature | Bound | Notes |
|---------------------|-------|-------|
| World lifecycle | ✅ | create, destroy, step, gravity |
| Body creation/destruction | ✅ | create, add, remove, destroy |
| Shapes (box, sphere, capsule, cylinder, plane) | ✅ | Via settings pattern |
| Body properties (friction, restitution, damping, gravity factor) | ✅ | setters on creation settings |
| Force/impulse/torque | ✅ | add_force, add_impulse, add_torque |
| Position/velocity queries | ✅ | get_position, get_velocity |
| Ray casting | ✅ | Single ray hit |
| Collision groups | ✅ | GroupFilterTable |
| Constraints | ✅ | DistanceConstraint (basic) |
| Job system | ✅ | Thread pool |
| ConvexHullShape | ❌ | Needs mesh data upload |
| MeshShape / HeightField | ❌ | Needs vertex/index buffer API |
| Character controller | ❌ | Complex setup |
| Vehicles | ❌ | Wheeled/tracked/motorcycle |
| Soft bodies | ❌ | GPU compute pipeline |
| Ragdolls | ❌ | Skeleton + animation |
| Custom contact/activation listeners | ❌ | Callback bridging not yet supported in XIOM |

## Platform Support

| Platform | JoltPhysics | joltc C Bridge | XIOM bindings |
|----------|-------------|----------------|---------------|
| Windows x64 | ✅ (SSE/AVX) | ✅ | ✅ (expected) |
| Linux x64 | ✅ (SSE/AVX) | ✅ | ✅ (expected) |
| macOS (ARM/x64) | ✅ | ✅ | ✅ (expected) |
| Android (ARM) | ✅ | ⚠️ | ⚠️ (untested) |
| iOS | ✅ | ⚠️ | ⚠️ (untested) |

## Next Steps

1. **Build joltc** — obtain the C bridge binary for the target platform.
2. **Generate extern** — run `xiom ffigen` on `jolt.xiom-bind`.
3. **Link test** — compile `demo_jolt.xi` against the bridge.
4. **Expand API** — add ConvexHullShape, MeshShape, character controller, and vehicle bindings.
5. **Add tests** — smoke tests for world lifecycle, body creation, and simulation stepping.

## References

- JoltPhysics: https://github.com/jrouwe/JoltPhysics
- joltc (C bridge): https://github.com/amerkoleci/joltc
- JoltPhysics README C bindings section: https://github.com/jrouwe/JoltPhysics#bindings-for-other-languages
- Architecture: `E:\repos\JoltPhysics\Docs\Architecture.md`
- HelloWorld example: `E:\repos\JoltPhysics\HelloWorld\HelloWorld.cpp`
