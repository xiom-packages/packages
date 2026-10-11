# xiom.ozz -- Roadmap

**Version**: v0.3.0 | **Compiler**: xiom v0.64.3 | **Last updated**: 2026-10-11

## Current state

| Criterion | Status |
|-----------|--------|
| Vendored C++ amalgamation (G2 pinned) | Done -- 0.16.0, two generated TUs |
| In-package bundler `tools/combine.py` (regeneration validated byte-identically) | Done -- 0.3.0 |
| FFI core + C bridge (single confined module) | Done |
| Math probes (Float3/Quaternion) | Done -- 5/5 x2 |
| Offline RawSkeleton -> runtime Skeleton | Done |
| LocalToModelJob (model-space matrices) | Done |
| Animation clip build + sampling (`AnimationBuilder` -> `SamplingJob`, hand-checked pose) | Done -- 0.3.0 |
| Blending / motion blending / IK jobs | Phase 2 |
| Tracks (float/quaternion vectors) | Phase 2 |
| Archive I/O (Save/Load via streams) | Phase 2 |
| Re-pin to 0.17.0 | backlog |

## Phase 2 (next touches)

1. ~~Clip pipeline~~ Done 0.3.0 (`AnimationBuilder` -> `SamplingJob` with a
   context; ratio 0.5/1.0 verified against a hand-computed pose).
2. Blending: `BlendingJob` on two sampled poses; `LocalToModelJob` after
   blending.
3. IK: `IKTwoBoneJob`/`IKAimJob` probes (the runtime sources are already
   compiled in; only bridge endpoints are missing).
4. Archive I/O: expose `Save`/`Load` through XIOM `Vec[UInt8]` streams so
   skeletons/animations can round-trip without files.
5. Re-pin to 0.17.0 (check `SoaTransform`/job API changes; regenerate the
   two TUs with `tools/combine.py` per SPEC.md section 2).
6. Consumer note: PULSE/XVECTOR do not need ozz; keep the API stable for
   game/media consumers when they appear.
