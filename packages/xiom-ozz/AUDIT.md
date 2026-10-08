# AUDIT: xiom.ozz

## Status (2026-10-08)

Real vendored implementation at 0.2.0. The pre-pilot files (`ozz.xi` +
`src/ozz_safe.xi` + demo) declared a C bridge (`ozz_c_bridge.h/.cpp`) that
**was never present in the package** and could not build; they are preserved
in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Upstream | tag 0.16.0 (archive SHA256 verified); 0.17.0 is the next re-pin candidate |
| Link model | `--c-source` x2 (generated TUs); no include paths, no system lib |
| FFI confinement | all `extern "C"` in `ozz.xi` (G5); bridge code is our C++ in `src/ozz-bridge-in.cpp` |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 4/4 x2** via `scripts/port.ps1` (math, skeleton, LocalToModelJob, aggregate) |

## Design notes

- **Why amalgamation:** ozz sources use `#include "ozz/..."` /`"animation/..."`
  which need `-I include -I src`; the xiom link line has no include
  passthrough (verified against `xiom --help`). The upstream-style
  `combine.py` bundler produced two TUs (library + our bridge) with all
  quoted includes inlined; per-TU header inlining is semantically equivalent
  to normal `-I` compilation for these sources.
- A single combined TU for the whole library worked on the first compile
  (2.3 s, warnings only) -- no anonymous-namespace/static collisions across
  the 27 concatenated sources.
- Bridge API corrections found by compile iteration: quaternion rotation
  uses `TransformVector(q, v)` (no `q * Float3`), and matrix translation
  lanes are read with `GetX/GetY/GetZ` (SIMD vectors are not structs).
- Wrapper-name lesson repeated from lzfse: wrappers named like their externs
  self-recurse; public names use `_ok` suffixes.
- Generated TUs are LF-normalized and pinned (`vendor/** -text`), same as
  zstd/lzfse/sqlite.

## Known limitations

- Pilot scope: probes only (no animation clip build/sample, blending, IK,
  tracks, archive I/O) -- Phase 2 roadmap.
- The amalgamated TU inlines headers once per TU; compile time is a few
  seconds here but will grow if more offline sources are added.
- Windows-focused testing; the vendored sources are portable C++ but no
  POSIX CI target exists yet.
