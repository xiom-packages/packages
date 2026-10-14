# AUDIT: xiom.ozz

## Status (2026-10-14)

Real vendored implementation at 0.4.0. The pre-pilot files (`ozz.xi` +
`src/ozz_safe.xi` + demo) declared a C bridge (`ozz_c_bridge.h/.cpp`) that
**was never present in the package** and could not build; they are preserved
in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 |
| Upstream | tag 0.16.0 (archive SHA256 verified); 0.17.0 is the next re-pin candidate |
| Link model | `--c-source` x2 (generated TUs); no include paths, no system lib |
| FFI confinement | all `extern "C"` in `ozz.xi` (G5); bridge code is our C++ in `src/ozz-bridge-in.cpp` |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 9/9 x2** via `scripts/port.ps1` (math, skeleton, LocalToModelJob, clip pipeline, caller build t=0, caller end, caller typed edges, caller determinism, aggregate) |

## Design notes

- **Why amalgamation:** ozz sources use `#include "ozz/..."` /`"animation/..."`
  which need `-I include -I src`; the xiom link line has no include
  passthrough (verified against `xiom --help`). The bundler
  (`tools/combine.py`, in-package) produces two TUs (library + our
  bridge) with quoted includes inlined once; per-TU header inlining is
  semantically equivalent to normal `-I` compilation for these sources. The
  generator was validated by regenerating both pinned TUs byte-identically
  before the 0.3.0 additions (quoted-include resolution: including-file
  directory first, then the roots, keyed by resolved path), and the bridge
  TU was regenerated the same way for 0.4.0.
- **0.3.0 clip pipeline:** the library TU gains the offline animation sources
  (`raw_animation.cc`, `raw_animation_utils.cc`, `animation_builder.cc`).
  The probe builds a two-track RawAnimation (child y 1 -> 3 over one second),
  converts it with `AnimationBuilder`, then samples at ratio 0.5 (y == 2)
  and 1.0 (y == 3) through a `SamplingJob::Context` -- a hand-computed pose.
- **0.4.0 caller surface:** `xozz_clip_build/info/sample/release` wrap the
  same builders + `SamplingJob` for caller data. Built clips are owned by a
  bridge slot registry (`ozz::unique_ptr<Animation>`) and referenced from
  XIOM by an integer handle (index + 1) that only the bridge resolves -- the
  dx12 handle discipline (B-25: XIOM never casts a handle back into a
  pointer). Sampling is stateless (fresh `SamplingJob::Context` per call),
  so repeated samples are bit-identical; the C probe and the suite both
  verify determinism across two builds of identical keys.
- **Calibration lesson (0.4.0):** the first test tolerances (1e-4) were
  tighter than ozz's own keyframe quantization. A direct C++ ground-truth
  run (vendored amalgamation, no bridge) showed rotation components off by
  ~1.6e-4 and the end-of-clip interpolation ratio at ~1 - 2^-12 (sampling
  exactly at `duration` lands alpha ~0.999755). Both the C probe and the
  suite now verify end values within 1e-3 -- the tolerance the fixed
  clip probe always used (its 1e-3 window masked the same quantization).
- A single combined TU for the whole library worked on the first compile
  (warnings only) -- no anonymous-namespace/static collisions across the
  concatenated sources.
- Bridge API corrections found by compile iteration: quaternion rotation
  uses `TransformVector(q, v)` (no `q * Float3`), and vector lanes are read
  with `GetX/GetY/GetZ` (SIMD vectors are not structs).
- Wrapper-name lesson repeated from lzfse: wrappers named like their externs
  self-recurse; public names use `_ok` suffixes and the caller-surface
  externs use the `xozz_` prefix (the xspz_/xd12_ idiom).
- Generated TUs are LF-normalized and pinned (`vendor/** -text`), same as
  zstd/lzfse/sqlite.

## Known limitations

- Scope at 0.4.0: probes for math, skeleton, model-space and the clip
  pipeline, plus the caller-key build / caller-time sampling surface;
  blending, IK, tracks and archive I/O are Phase 2 (`ROADMAP.md`).
- The clip registry is process-global and single-threaded by design (tests
  and typical engine use); handles must be released, and a released handle
  is rejected with `OZZ_ERR_HANDLE` (no slot reuse of stale handles).
- Sampling returns local-space transforms only; model-space output still
  goes through `LocalToModelJob` (probe-covered, not yet wrapped for
  caller skeletons).
- The amalgamated TU inlines headers once per TU; compile time grows with
  each added offline source (still a few seconds here).
- Windows-focused testing; the vendored sources are portable C++ but no
  POSIX CI target exists yet.
