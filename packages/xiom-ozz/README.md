# xiom.ozz

Ozz-Animation bindings for XIOM via **vendored C++ amalgamations**. The
upstream 0.16.0 sources (MIT) are bundled into two generated translation
units (base + math + animation runtime + offline builder; plus our C
bridge) and compiled into the test binary -- no system library, no SDK, no
separate build step.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1): 4/4 with
> real runtime objects (offline `SkeletonBuilder` -> runtime `Skeleton` ->
> `LocalToModelJob` with verified model-space translations).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.ozz;

fn main() {
  let p = ozz_probe();
  if p.is_ok {
    io.println("ozz runtime checks green");
  } else {
    io.println(p.error);
  }
  if ozz_math_ok() {
    io.println("math ok");
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Probes | `ozz_math_ok`, `ozz_skeleton_ok`, `ozz_local_to_model_ok`, `ozz_probe` (aggregate) |
| Constants | `OZZ_NO_PARENT` |

Why probe-shaped: the pilot proves the vendored C++ toolchain path and real
runtime objects; the asset pipeline (build/sample clips, blend, IK, tracks,
archive I/O) is Phase 2 (`ROADMAP.md`).

## Build note

Ozz sources cannot be passed individually (`#include "ozz/..."` needs `-I`,
which the xiom link line does not support), so two generated TUs are
vendored: `vendor/ozz_all.cpp` and `vendor/ozz_bridge.cpp`. The bridge and
entry templates live in `src/`; generation + re-pin steps are in `SPEC.md`
§2. `port.args.json` passes both TUs as `--c-source` entries.

## Tests

```
scripts/port.ps1 -Package xiom.ozz
```

Expected: 4 `[PASS]`, exit 0.
