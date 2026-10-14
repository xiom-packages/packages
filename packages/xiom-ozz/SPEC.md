# SPEC: xiom.ozz -- Ozz-Animation bindings (vendored C++ amalgamations)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.ozz` |
| Version | 0.4.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | ozz-animation -- https://github.com/guillaumeblanc/ozz-animation |
| Upstream version pinned | tag **0.16.0** (0.17.0 is the next re-pin candidate) |
| Upstream license | MIT (`vendor/LICENSE.md`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (no platform-specific XIOM code) |
| Compiler pin | v0.64.4 |

## 2. Vendored path (G2 pin)

Ozz is a C++ library with no C API, and the xiom link line has **no
include-path passthrough**, so the upstream sources cannot be passed as
individual `--c-source` entries (their `#include "ozz/..."` /
`"animation/..."` paths need `-I`). The package therefore vendors two
**generated translation units** produced with the upstream-style
`combine.py` bundler (roots `include/` + `src/`):

- `vendor/ozz_all.cpp` -- base + math + animation runtime + offline skeleton
  and animation builders concatenated with all quoted includes inlined (one
  TU).
- `vendor/ozz_bridge.cpp` -- our `extern "C"` bridge with the ozz headers it
  needs inlined (one TU). Bridge source template documented below.

Both are compiled with `--c-source` (port.args.json); no system library, no
separate build step, no SDK. The two generator inputs are vendored as
reviewable sources: `src/ozz-in.cpp` (library entry list) and
`src/ozz-bridge-in.cpp` (our `extern "C"` bridge). The bundler is
`tools/combine.py` (in-package, validated by regenerating the pinned TUs
byte-identically).

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/ozz_all.cpp` | 772,432 | `126B6B5579499C3C9CB685C9605DDFDE1160114399C04D43938B3555C203F2EF` |
| `vendor/ozz_bridge.cpp` | 421,372 | `44D335ABDCA03573A833B4A26E954C6BDF99DFB9B3789FBE6CDA4D2C4720287F` |
| `vendor/LICENSE.md` | 1,183 | `3DDD93E9888FE70B9D61675CEB1C4278A579DC67171678F015DE114EFE815852` |

### Archive provenance

| Artifact | Value |
|----------|-------|
| Download | https://github.com/guillaumeblanc/ozz-animation/archive/refs/tags/0.16.0.tar.gz |
| Size / SHA256 | 37,101,794 bytes / `A7A34322344E9D839EAF637BBC463404C6AED3F52583DEA95C856FEA580C2693` |

### Generation procedure (re-pin)

1. Download the new tag archive; verify the SHA256 and extract it.
2. Build an entry template listing the library sources in dependency order
   (`src/ozz-in.cpp`; base: memory/allocator, platform, log,
   containers/string_archive, encode/group_varint, io/archive, io/stream,
   maths/{simd_math, math_archive, simd_math_archive, soa_math_archive,
   box}; runtime: the 13 `animation/runtime/*.cc`; offline: raw_skeleton.cc,
   skeleton_builder.cc, raw_animation.cc, raw_animation_utils.cc,
   animation_builder.cc).
3. Regenerate both TUs with the in-package bundler:
   `python tools/combine.py -r <archive>/include -r <archive>/src -o
   vendor/ozz_all.cpp src/ozz-in.cpp` and the same with
   `src/ozz-bridge-in.cpp -o vendor/ozz_bridge.cpp`.  The tool inlines
   quoted includes once (including-file directory first, then the roots),
   keeps system includes verbatim, normalizes LF, and prints the SHA256.
4. Update the hash table and version rows, re-run
   `scripts/port.ps1 -Package xiom.ozz` (x2).

`.gitattributes` pins `vendor/** -text`.

## 3. Design and safe boundary (G5)

`ozz.xi` is the only module with `extern "C"`; probe wrappers are
`ozz_math_ok`, `ozz_skeleton_ok`, `ozz_local_to_model_ok`, `ozz_clip_ok`,
`ozz_caller_ok`, `ozz_probe` (aggregate `Result[Unit, Str]`), plus
`OZZ_NO_PARENT`. The C bridge (`extern "C"`) provides `ozz_probe_math`,
`ozz_probe_skeleton`, `ozz_probe_local_to_model`, `ozz_probe_clip`,
`ozz_probe_caller`, `ozz_probe_all` and is compiled inside
`vendor/ozz_bridge.cpp`. The clip probe builds a two-track RawAnimation
(child y 1 -> 3 over one second), converts it with the offline
AnimationBuilder, then samples at ratio 0.5 (child y == 2) and 1.0 (child
y == 3) through a `SamplingJob::Context` -- a hand-computed pose check.

### 0.4.0 caller surface

Wrappers: `ozz_clip_build(tracks, duration) -> Result[OzzClip, OzzError]`,
`ozz_clip_info(clip)`, `ozz_clip_sample(clip, time) -> Result[OzzPose,
OzzError]`, `ozz_clip_release(clip)`; types `OzzKey` (time + rotation xyzw +
translation xyz + scale xyz), `OzzTrack`, `OzzClip`, `OzzClipInfo`,
`OzzPose`, `OzzError`.

- **Build**: the XIOM wrapper flattens `Vec[OzzTrack]` into two XIOM-owned
  flat buffers (per-track key counts as floats; key records of 11 floats)
  and calls `xozz_clip_build`, which fills a `RawAnimation` (all three
  channels share each key's time), validates it and converts it with the
  `AnimationBuilder`. Built clips live in a bridge-side slot registry
  (owning `ozz::unique_ptr<Animation>`); XIOM holds only an opaque integer
  handle (index + 1). Handles cross as `Int64` parameters and are cast back
  to slots only inside the bridge (B-25: no XIOM-side pointer casts of
  handles). `xozz_clip_release` frees the slot; a released handle returns
  `OZZ_ERR_HANDLE` like any unknown one.
- **Sample**: `xozz_clip_sample` looks the clip up, rejects `time < 0` or
  `time > duration` with `OZZ_ERR_TIME` (NaN-safe), computes
  `ratio = time / duration`, runs a stateless `SamplingJob` with a fresh
  `Context` and de-SoAs the per-joint local transforms into one XIOM-owned
  float buffer (10 floats per joint). The wrapper splits that buffer into
  owned `rotations` (4/joint), `translations` (3/joint) and `scales`
  (3/joint) vectors.
- **Discipline** (v0.64.4): every out-param has its own XIOM-owned buffer
  read with plain vector indexing (one owned slot per out-param; B-24); no
  pointer casts, no bare `null`, no foreign-pointer reads and no pointer
  arithmetic in XIOM (B-20/B-23/B-25); no `&mut` of call-result temporaries
  (B-21); no `Result[Option[T]]` shapes (B-26); errors are typed
  (`OzzError { code, message }`, codes mirror the bridge `OZZ_RC_*`).
- **Quantization note**: ozz stores keyframes quantized (rotation
  components ~1.6e-4; time ratios ~2^-12 -- e.g. sampling exactly at
  `duration` yields alpha ~0.999755). Suite and probe tolerances are 1e-3
  for end values, matching the fixed-scenario clip probe.

Wrapper-name note: a wrapper named like its extern self-recurses (the lzfse
lesson); public names use `_ok` suffixes and the caller-surface externs use
the `xozz_` prefix (the xspz_/xd12_ idiom).

## 4. Test matrix (recorded 2026-10-14, compiler v0.64.4)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored amalgamations | `scripts/port.ps1 -Package xiom.ozz` | **PASS 9/9 x2** -- math (dot/cross + 90-degree axis rotation), offline RawSkeleton -> runtime Skeleton (2 joints, parents -1/0), LocalToModelJob (child at (0,1,0) in model space), clip pipeline (AnimationBuilder -> SamplingJob: ratio 0.5 -> child y 2.0, ratio 1.0 -> child y 3.0), caller_build (caller keys -> t=0 pose in owned buffers: root identity, child rot identity / y=1 / scale 1), caller_end (t=duration -> child y=3, scale 2, 90-degree Z within ozz quantization), caller_edge (t>duration and t<0 -> OZZ_ERR_TIME; ghost and released handles -> OZZ_ERR_HANDLE; empty/duration-0/out-of-range keys -> OZZ_ERR_ARGS/OZZ_ERR_KEYS), caller_determinism (two builds of the same keys sample bit-identically at t=0.5; resample stable), aggregate green (all five C probes) |

No SKIP path exists (the library is compiled in). The two TUs compile in a
few seconds each at the link line's default optimization.

## 5. Scope

0.4.0: adds the caller surface on top of the 0.3.0 pipeline -- clips can be
built from caller-supplied keys and sampled at caller-provided times into
owned pose buffers with typed bounds errors, all through the bridge-owned
clip registry. Blending jobs, IK jobs, tracks and archive I/O remain Phase 2
(`ROADMAP.md`). The pre-pilot files declared a C bridge that was never
present and are preserved in git history.
