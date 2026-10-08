# xiom.ozz -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Vendored C++ amalgamation (G2 pinned) | Done -- 0.16.0, two generated TUs |
| FFI core + C bridge (single confined module) | Done |
| Math probes (Float3/Quaternion) | Done -- 4/4 x2 |
| Offline RawSkeleton -> runtime Skeleton | Done |
| LocalToModelJob (model-space matrices) | Done |
| Animation clip build + sampling | Phase 2 |
| Blending / motion blending / IK jobs | Phase 2 |
| Tracks (float/quaternion vectors) | Phase 2 |
| Archive I/O (Save/Load via streams) | Phase 2 |
| Re-pin to 0.17.0 | backlog |

## Phase 2 (next touches)

1. Clip pipeline: `AnimationBuilder` (offline) from a RawAnimation built via
   the bridge, then `SamplingJob` with a `SamplingCache`; verify a sampling
   output against a hand-computed pose (no asset files needed).
2. Blending: `BlendingJob` on two sampled poses; `LocalToModelJob` after
   blending.
3. IK: `IKTwoBoneJob`/`IKAimJob` probes (they are already compiled in and
   only need bridge endpoints).
4. Archive I/O: expose `Save`/`Load` through XIOM `Vec[UInt8]` streams so
   skeletons/animations can round-trip without files.
5. Re-pin to 0.17.0 (check `SoaTransform`/job API changes; regenerate the
   two TUs with the documented procedure).
6. Consumer note: PULSE/XVECTOR do not need ozz; keep the API stable for
   game/media consumers when they appear.
