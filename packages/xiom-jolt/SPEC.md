# SPEC: xiom.jolt -- Jolt Physics bindings (vendored v5.6.0 core)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.jolt` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | JoltPhysics -- https://github.com/jrouwe/JoltPhysics |
| Upstream version | tag **v5.6.0** |
| Upstream license | MIT (`vendor/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored C++ path is portable |
| Compiler pin | v0.64.3 **+ m258** (`--cxx-standard`; next archive) |

## 2. Vendored path (G2 pin)

`tools/combine.py` mirrors `<upstream>/Jolt/**` into `vendor/Jolt/**` with one
textual transform -- `#include <Jolt/...>` becomes `#include "Jolt/..."` --
and emits **25 per-directory TUs** plus a shim that compiles the reviewable
bridge (`src/jolt_bridge.cpp`) from the vendor root.  The quoted includes
resolve through the compiler's include stack (the xiom link line has no `-I`
passthrough); on a compiler without m258 the C++17 sources fail by design.

### Pinned source

| Artifact | Value |
|----------|-------|
| Source of record | tag `v5.6.0`; tarball https://github.com/jrouwe/JoltPhysics/archive/refs/tags/v5.6.0.tar.gz (19,390,751 B, sha256 `6E069EE0172478CC78182047AAC87E5310BA14A67A53348AE14CC37801FD3F8E`) |
| Generated tree sha256 | `ea20c2d1...` (printed by the generator; excludes LICENSE) |

Re-pin: extract the new tag, run
`python tools/combine.py <upstream-root> vendor`, record the new tree hash,
re-run `scripts/port.ps1 -Package xiom.jolt` x2 (watchdog >=600 s), update
this table + `README.md`/`AUDIT.md`.

## 3. Design and safe boundary (G5)

`jolt.xi` is the only module with `unsafe`/`extern "C"`; it calls the
scalar-return bridge.  The drop probe builds a static ground + a dynamic
box (single-threaded job system), steps 300 frames at 60 Hz and reports
the settled center y and sleep state; the impulse probe measures a velocity
hand-off.  No out-param slots (B-11 family avoidance); no malloc/free from
XIOM.  There is no SKIP path -- the vendored sources always compile in.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- 4 checks: resting drop settles within
[400, 600] milli on the ground (top at y=0), the body sleeps, the velocity
hand-off stays within [4500, 5500] milli, and a repeated drop is identical.

```
scripts/port.ps1 -Package xiom.jolt
```

Requires the compiler with `--cxx-standard` (m258, next archive); the flag
is carried by `port.args.json`.

## 5. Scope

Pilot: drop + velocity probes.  Broad-phase queries, joint variety,
character controllers, soft bodies, and real content are Phase 2
(`ROADMAP.md`).  The pre-pilot declaration-only module is preserved in git
history.  Verification evidence (local m258 build): drop settles at 479
milli asleep; impulse vx=4995; 4/4 x2, ~34 s/run.
