# AUDIT: xiom.ozz

## Status (2026-10-11)

Real vendored implementation at 0.3.0. The pre-pilot files (`ozz.xi` +
`src/ozz_safe.xi` + demo) declared a C bridge (`ozz_c_bridge.h/.cpp`) that
**was never present in the package** and could not build; they are preserved
in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.3 |
| Upstream | tag 0.16.0 (archive SHA256 verified); 0.17.0 is the next re-pin candidate |
| Link model | `--c-source` x2 (generated TUs); no include paths, no system lib |
| FFI confinement | all `extern "C"` in `ozz.xi` (G5); bridge code is our C++ in `src/ozz-bridge-in.cpp` |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 5/5 x2** via `scripts/port.ps1` (math, skeleton, LocalToModelJob, clip pipeline, aggregate) |

## Design notes

- **Why amalgamation:** ozz sources use `#include "ozz/..."` /`"animation/..."`
  which need `-I include -I src`; the xiom link line has no include
  passthrough (verified against `xiom --help`). The bundler
  (`tools/combine.py`, now in-package) produces two TUs (library + our
  bridge) with quoted includes inlined once; per-TU header inlining is
  semantically equivalent to normal `-I` compilation for these sources. The
  generator was validated by regenerating both pinned TUs byte-identically
  before the 0.3.0 additions (quoted-include resolution: including-file
  directory first, then the roots, keyed by resolved path).
- **0.3.0 clip pipeline:** the library TU gains the offline animation sources
  (`raw_animation.cc`, `raw_animation_utils.cc`, `animation_builder.cc`).
  The probe builds a two-track RawAnimation (child y 1 -> 3 over one second),
  converts it with `AnimationBuilder`, then samples at ratio 0.5 (y == 2)
  and 1.0 (y == 3) through a `SamplingJob::Context` -- a hand-computed pose.
- A single combined TU for the whole library worked on the first compile
  (warnings only) -- no anonymous-namespace/static collisions across the
  concatenated sources.
- Bridge API corrections found by compile iteration: quaternion rotation
  uses `TransformVector(q, v)` (no `q * Float3`), and vector lanes are read
  with `GetX/GetY/GetZ` (SIMD vectors are not structs).
- Wrapper-name lesson repeated from lzfse: wrappers named like their externs
  self-recurse; public names use `_ok` suffixes.
- Generated TUs are LF-normalized and pinned (`vendor/** -text`), same as
  zstd/lzfse/sqlite.

## Known limitations

- Scope at 0.3.0: probes for math, skeleton, model-space and the clip
  pipeline; blending, IK, tracks and archive I/O are Phase 2 (`ROADMAP.md`).
- The amalgamated TU inlines headers once per TU; compile time grows with
  each added offline source (still a few seconds here).
- Windows-focused testing; the vendored sources are portable C++ but no
  POSIX CI target exists yet.
