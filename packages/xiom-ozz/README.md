# xiom.ozz

Ozz-Animation bindings for XIOM via **vendored C++ amalgamations**. The
upstream 0.16.0 sources (MIT) are bundled into two generated translation
units (base + math + animation runtime + offline builder; plus our C
bridge) and compiled into the test binary -- no system library, no SDK, no
separate build step.

> **Status:** `incubating` -- suite green on the pin (v0.64.4): native
> **9/9 x2** with real runtime objects (offline
> `SkeletonBuilder`/`AnimationBuilder` -> runtime `Skeleton`/`Animation` ->
> `LocalToModelJob`/`SamplingJob` with verified poses; 0.3.0 added the clip
> pipeline + the in-package `tools/combine.py` bundler; 0.4.0 adds the
> caller surface: build a clip from caller keys and sample it at caller
> times into owned pose buffers with typed errors). 0.2.0 shipped in
> `eco-v0.1.109`; 0.3.0 published in `eco-v0.1.156` (sha256 `f84988e7...`).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.ozz;

fn main() {
  if ozz_math_ok() {
    io.println("math ok");
  }

  // Build a clip from caller keys: one track per joint; each key carries a
  // time plus joint-local rotation (x, y, z, w), translation (x, y, z) and
  // scale (x, y, z).
  var track = OzzTrack.new();
  track.keys.push(OzzKey.new(0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0));
  track.keys.push(OzzKey.new(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 3.0, 0.0, 1.0, 1.0, 1.0));
  var tracks: Vec[OzzTrack] = Vec[OzzTrack].new();
  tracks.push(track);

  let built = ozz_clip_build(&tracks, 1.0);
  if built.is_ok {
    let clip = built.value;
    let sampled = ozz_clip_sample(&clip, 0.5);   // t within [0, duration]
    if sampled.is_ok {
      let pose = sampled.value;                  // owned pose buffers
      io.println("sampled pose ready");
    } else {
      io.println(sampled.error.message);         // typed OzzError
    }
    let freed = ozz_clip_release(&clip);         // frees the bridge slot
  } else {
    io.println(built.error.message);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Probes | `ozz_math_ok`, `ozz_skeleton_ok`, `ozz_local_to_model_ok`, `ozz_clip_ok`, `ozz_caller_ok`, `ozz_probe` (aggregate) |
| Caller surface (0.4.0) | `ozz_clip_build`, `ozz_clip_info`, `ozz_clip_sample`, `ozz_clip_release` |
| Types | `OzzKey`, `OzzTrack`, `OzzClip`, `OzzClipInfo`, `OzzPose`, `OzzError` |
| Constants | `OZZ_NO_PARENT`, `OZZ_KEY_FLOATS`, `OZZ_POSE_FLOATS`, `OZZ_ERR_*` |

The caller surface builds a clip from caller-supplied keys into
package-owned storage (opaque `OzzClip` handle; release with
`ozz_clip_release`) and samples it at a caller-provided time into fresh
owned buffers: `OzzPose { joints, rotations (4/joint), translations
(3/joint), scales (3/joint) }`. Sampling outside `[0, duration]` is the
typed error `OZZ_ERR_TIME`; unknown/released handles are `OZZ_ERR_HANDLE`;
invalid keys/durations are `OZZ_ERR_ARGS`/`OZZ_ERR_KEYS`. Ozz stores
keyframes quantized, so values sampled at non-key times and at the end
carry ozz's own ~1.6e-4 rotation / ~2^-12 ratio quantization.

Why probe-shaped plus a caller surface: the vendored C++ path is proven
with real runtime objects, and the engine-facing clip flows (build/sample)
are now usable; the remaining asset-pipeline work (blend, IK, tracks,
archive I/O) is Phase 2 (`ROADMAP.md`).

## Build note

Ozz sources cannot be passed individually (`#include "ozz/..."` needs `-I`,
which the xiom link line does not support), so two generated TUs are
vendored: `vendor/ozz_all.cpp` and `vendor/ozz_bridge.cpp`. The bridge and
entry templates live in `src/`; regeneration uses the in-package bundler
`python tools/combine.py` (validated by regenerating the pinned TUs
byte-identically). Generation + re-pin steps are in `SPEC.md` §2.
`port.args.json` passes both TUs as `--c-source` entries.

## Tests

```
scripts/port.ps1 -Package xiom.ozz
```

Expected: 9 `[PASS]`, exit 0.
