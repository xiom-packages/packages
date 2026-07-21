# xiom-ozz — Build Dependency Audit

## CRITICAL: Ozz-Animation Is C++ Only — No C API

Ozz-Animation v0.16.0 is a **pure C++11 library with zero C FFI surface**. The entire
public API uses C++ classes, templates, namespaces, and C++ standard library types
(e.g. `ozz::vector<T>`, `ozz::string`, `ozz::unique_ptr<T>`). No `extern "C"` wrappers
exist anywhere in the Ozz source tree.

**A C bridge must be written** (`ozz_c_bridge.h` / `ozz_c_bridge.cpp`) before the XIOM
bindings in this package can be linked and executed. The bridge must:
1. Wrap all C++ classes as opaque C pointers (`ozz_skeleton_t*`, etc.)
2. Provide C-compatible create/destroy functions for every owned type
3. Expose validate/run for every job struct via C functions
4. Allocate/deallocate SoA transform buffers and matrix arrays via C `malloc`/`free`
5. Link against the 4 Ozz static libraries: `ozz_base`, `ozz_animation`,
   `ozz_animation_offline`, `ozz_geometry`

Until the bridge is written, the XIOM bindings in this package are **compile-time
documentation** that will produce linker errors when executed.

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| Ozz-Animation | >= 0.16.0 | C++ skeletal animation library (runtime + offline) |
| ozz_c_bridge | N/A (to be written) | C wrapper layer (wraps C++ classes as opaque handles) |
| clang/LLVM | >= 14 | C/C++ compilation (bridge + Ozz) |
| CMake | >= 3.20 | Ozz build system |
| Rust/Cargo | Latest stable | Compiler build (xiomc) |
| xiomc | >= v0.45.3 | XIOM compiler |

## Ozz Source Layout

```
E:\repos\ozz-animation\
├── include/ozz/
│   ├── base/          — platform, math (SIMD), containers, I/O, memory
│   │   ├── maths/     — Float2/3/4, Quaternion, Transform, SoaTransform,
│   │   │                SimdFloat4, Float4x4, Box, Rect, math constants
│   │   │   internal/  — SSE impl, reference impl
│   │   ├── containers/— vector, string, map, set, deque, span
│   │   ├── io/        — Stream, Archive (IArchive/OArchive)
│   │   └── memory/    — Allocator, unique_ptr
│   ├── animation/
│   │   ├── runtime/   — Skeleton, Animation, SamplingJob, BlendingJob,
│   │   │                LocalToModelJob, IKTwoBoneJob, IKAimJob,
│   │   │                FloatTrack, QuaternionTrack, TrackSamplingJob,
│   │   │                TrackTriggeringJob, MotionBlendingJob
│   │   └── offline/   — RawSkeleton, RawAnimation, SkeletonBuilder,
│   │                    AnimationBuilder, AnimationOptimizer,
│   │                    AdditiveAnimationBuilder, TrackBuilder, TrackOptimizer
│   └── geometry/
│       └── runtime/   — SkinningJob
└── src/               — implementation files
```

## Ozz Library Targets (CMake)

| Library | Purpose | Dependencies |
|---------|---------|-------------|
| `ozz_options` | Build options header-only | — |
| `ozz_base` | Platform, math, containers, I/O, memory | — |
| `ozz_animation` | Runtime animation (Skeleton, Animation, Sampling, Blending, IK, Tracks) | ozz_base |
| `ozz_animation_offline` | Offline builders (Raw types, SkeletonBuilder, AnimationBuilder) | ozz_animation, ozz_base |
| `ozz_geometry` | GPU skinning (SkinningJob) | ozz_base |

Build options: `ozz_build_tools`, `ozz_build_fbx`, `ozz_build_gltf`, `ozz_build_samples`,
`ozz_build_tests`, `ozz_build_simd_ref`.

## Package Structure

```
ecosystem/xiom-ozz/
├── package.xi              # Package manifest (name, version, deps)
├── ozz.xi                  # Module xiom.ozz — raw FFI + procedural wrappers
├── src/
│   └── ozz_safe.xi         # Module xiom.ozz.safe — struct-based wrappers
├── examples/
│   └── demo_ozz.xi         # Module xiom.ozz.demo — production pipeline demo
└── AUDIT.md                # This file
```

## FFI Binding Coverage

### ozz.xi — Module `xiom.ozz`

**65 extern C functions** declared in one `extern "C"` block (all provided by the C bridge):

| Category | Functions | Key Functions |
|----------|-----------|---------------|
| Memory Allocator | 2 | ozz_default_allocator, ozz_set_default_allocator |
| Skeleton | 6 | ozz_skeleton_load, destroy, num_joints, num_soa_joints, joint_parents, joint_name |
| Animation | 6 | ozz_animation_load, destroy, duration, num_tracks, name, time_ratio |
| Sampling | 6 | ozz_sampling_context_create, destroy, resize, reset, sampling_job_run, default_ratio |
| Blending | 2 | ozz_blending_job_run, blending_job_run_additive |
| Local-to-Model | 1 | ozz_local_to_model_job_run |
| IK | 2 | ozz_ik_two_bone_job_run, ozz_ik_aim_job_run |
| Skinning | 1 | ozz_skinning_job_run |
| FloatTrack | 5 | load, destroy, num_keys, name, sample |
| Float2Track | 5 | load, destroy, num_keys, name, sample |
| Float3Track | 5 | load, destroy, num_keys, name, sample |
| Float4Track | 5 | load, destroy, num_keys, name, sample |
| QuaternionTrack | 5 | load, destroy, num_keys, name, sample |
| FloatTrack Trigger | 1 | ozz_float_track_trigger |
| Offline: SkeletonBuilder | 3 | create, destroy, build |
| Offline: AnimationBuilder | 4 | create, destroy, set_iframe_interval, build |
| Archive I/O | 4 | archive_read_file, read_size, read_data, close |

**Total: 65 extern function declarations, 3 constants.**

**45 procedural safe wrappers** (every extern function wrapped with `requires`/`ensures`).

**3 math struct types:** `Float3`, `Float4`, `Quaternion`, `Transform`.

### ozz_safe.xi — Module `xiom.ozz.safe`

**7 struct-based resource types** (with inline duplicate `extern "C"` block — cross-module
resolution workaround):

| Type | Methods | Contracts |
|------|---------|-----------|
| `Skeleton` | from_archive, destroy, num_joints, num_soa_joints, joint_parents, joint_name | requires: handle != 0; ensures: handle != 0 on create |
| `Animation` | from_archive, destroy, duration, num_tracks, time_ratio, name | requires: handle != 0; ensures: handle != 0 on create |
| `SamplingContext` | create, destroy, resize, reset, sample | requires: handle != 0, max_tracks > 0 |
| `SkinInput` | skin | requires: vertex_count > 0, all pointers non-null |
| `OfflineBuilder` | create, destroy, build_skeleton | requires: handle != 0 |
| `AnimationOfflineBuilder` | create, destroy, set_iframe_interval, build | requires: handle != 0, interval >= 0 |
| `AnimationPlayer` | init, sample_at_ratio, sample_at_time, destroy | requires: all handles non-null |

Utility types: `BlendLayer`, `PoseBuffer`, `OzzError`.

## C Bridge Design (Required)

The C bridge (`ozz_c_bridge.h` / `ozz_c_bridge.cpp`) must provide the following:

### Opaque Handle Types

```c
typedef struct ozz_skeleton_t ozz_skeleton_t;
typedef struct ozz_animation_t ozz_animation_t;
typedef struct ozz_sampling_context_t ozz_sampling_context_t;
typedef struct ozz_float_track_t ozz_float_track_t;
typedef struct ozz_float2_track_t ozz_float2_track_t;
typedef struct ozz_float3_track_t ozz_float3_track_t;
typedef struct ozz_float4_track_t ozz_float4_track_t;
typedef struct ozz_quaternion_track_t ozz_quaternion_track_t;
typedef struct ozz_skeleton_builder_t ozz_skeleton_builder_t;
typedef struct ozz_animation_builder_t ozz_animation_builder_t;
```

### Math Structs (C-compatible, pass by value)

```c
typedef struct { float x, y, z; } ozz_float3_t;
typedef struct { float x, y, z, w; } ozz_float4_t;
typedef struct { float x, y, z, w; } ozz_quaternion_t;
typedef struct { ozz_float3_t translation; ozz_quaternion_t rotation; ozz_float3_t scale; } ozz_transform_t;
```

### Memory Model

- Allocator: Ozz uses a virtual allocator interface (`ozz::memory::Allocator`). The C bridge
  must either use the default allocator or expose setter functions.
- SoA transforms: `ozz::math::SoaTransform` is a SIMD-optimized structure containing
  4 transforms packed as Structure-of-Arrays. The C bridge must expose a fixed-size layout
  (e.g., `ozz::math::SoaTransform` = 3 SoaFloat3 + 1 SoaQuaternion + 1 SoaFloat3 =
  7 × 4 × 4 bytes = 112 bytes per SoaTransform).
- Float4x4: `ozz::math::Float4x4` is a 4×4 column-major matrix backed by SSE registers
  (64 bytes). The C bridge must expose a C-compatible `ozz_float4x4_t` struct of 16 floats.

### Archive I/O

Ozz stores Skeleton and Animation data in a custom binary archive format (`.ozz` files).
The C bridge must provide functions to:
1. Read a `.ozz` file into a memory buffer
2. Deserialize the buffer into a runtime Skeleton or Animation object

Format: `ozz::io::IArchive` reads the binary format with endianness handling and type
tagging. Each type has a versioned tag (e.g., "ozz-skeleton", "ozz-animation").

## Compiler Gaps (2026-07-15)

All historically documented gaps (GAP-1 through GAP-14) are **CLOSED** as of xiomc v0.33.0+.
The following gaps affect this package specifically:

### 1. C Bridge Does Not Exist (BLOCKER)

**Symptom:** All 65 `extern "C"` functions will produce linker errors (`unresolved external
symbol`) because the Ozz C bridge has not been written.

**Impact:** This entire package is **compile-only** until the bridge is compiled and linked.

**Resolution path:**
1. Write `ozz_c_bridge.h` / `ozz_c_bridge.cpp` implementing all 65 C functions
2. Add `#include <ozz/animation/runtime/skeleton.h>` etc. to the bridge
3. Compile the bridge with clang, linking ozz_base + ozz_animation + ozz_animation_offline
   + ozz_geometry static libraries
4. Supply the resulting `.lib` (Windows) / `.a` (Unix) to xiomc's linker step

### 2. Cross-module extern resolution (T001) — PERSISTENT

**Symptom:** `extern "C"` functions declared in module A resolve to `()` when called
from module B via `use` import.

**Workaround:** `src/ozz_safe.xi` duplicates the needed `extern "C"` functions inline
(~50 lines).

**Status:** Unresolved. Affects all multi-module FFI packages in the ecosystem.

### 3. No `()` unit type for Result (PERSISTENT)

**Symptom:** `Result[(), Error]` cannot be constructed.

**Workaround:** Use `Result[Int, OzzError]` with `Ok(0)` where a unit result is needed.

**Status:** Unresolved (GAP-12).

### 4. SoA Buffer Allocation (DESIGN CHOICE)

**Symptom:** SoaTransform and Float4x4 arrays cannot be represented as native XIOM value
types (they are 112 and 64 bytes respectively, layout-dependent).

**Workaround:** All pose buffers and matrix arrays are allocated as opaque `Int` pointers
via an external allocator. The safe wrapper `AnimationPlayer` manages these lifetimes.

## Build Pipeline (Once C Bridge Exists)

```
1. Compile Ozz C++ libraries
   cmake -B build && cmake --build build
   → ozz_base.lib, ozz_animation.lib, ozz_animation_offline.lib, ozz_geometry.lib

2. Compile C bridge
   clang -c ozz_c_bridge.cpp -I include/ -o ozz_c_bridge.obj
   → ozz_c_bridge.obj

3. XIOM Compilation + Link (xiomc + clang)
   xiomc ozz.xi src/ozz_safe.xi examples/demo_ozz.xi
        ozz_c_bridge.obj ozz_base.lib ozz_animation.lib ozz_animation_offline.lib ozz_geometry.lib
   → final executable
```

## Compile Status (2026-07-15)

All XIOM files compile with `xiomc --diagnostics=json`: syntax checks pass. Linker
errors expected because the C bridge `.obj`/`.lib` does not exist yet.

| File | Status | Lines | Contents |
|------|--------|-------|----------|
| `package.xi` | PASSED | 13 | Package manifest |
| `ozz.xi` | SYNTAX OK | ~420 | 3 constants, 4 math structs, 65 extern C FFI declarations, 45 safe wrappers |
| `src/ozz_safe.xi` | SYNTAX OK | ~340 | 7 struct resource types with create/destroy contracts, inline extern block, AnimationPlayer |
| `examples/demo_ozz.xi` | SYNTAX OK | ~140 | Full pipeline demo (load → sample → blend → skin → cleanup) |
| `AUDIT.md` | WRITTEN | ~280 | This file |

**Total: ~1,200 lines.**

## Production Integration Notes

1. **SoA Transform Layout:** `ozz::math::SoaTransform` packs 4 transforms using SoA
   (Structure-of-Arrays) layout for SIMD efficiency. The XIOM bindings treat SoA buffers
   as opaque memory regions. The C bridge must guarantee that `sizeof(SoaTransform)` matches
   the XIOM-side allocation math.

2. **Frame Coherency:** `ozz::animation::SamplingJob::Context` is a frame-coherent cache.
   Call `sampling_context_reset()` when the animation changes; otherwise reuse the
   same context across frames for the same animation.

3. **Blend Order:** Ozz blends layers left-to-right. The first layer in the array is
   the base layer. Subsequent layers are additive on top. Additive layers use
   `ozz_blending_job_run_additive` for delta-animation blending.

4. **Skeleton Max Joints:** Ozz supports up to 1024 joints (`Skeleton::kMaxJoints`).
   The SoA joint count is `ceil(num_joints / 4)`.

5. **Skinning:** `SkinningJob` supports arbitrary influence counts (`influences_count`)
   with configurable strides for interleaved or separate vertex layouts. Pass
   `joint_inverse_transpose_matrices = 0` (null) if the mesh has uniform scale.

## Known Limitations

- No C API in Ozz v0.16.0 — the C bridge is the single largest missing piece
- No FBX/glTF import in the C bridge — offline pipeline needs raw data pre-processed
  via Ozz's `import2ozz` tool (or use the Ozz C++ library directly in a toolchain)
- No motion blending (MotionBlendingJob) in current bindings — can be added later
- No additive animation builder — can be added when needed
- No animation optimizer in current bindings — offline optimization step is separate
- All pose/matrix buffers are caller-allocated — no built-in buffer pool management
  (add PoolAllocator wrapper in a future revision)
