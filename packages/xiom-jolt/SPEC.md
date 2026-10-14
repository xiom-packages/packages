# SPEC: xiom.jolt -- Jolt Physics bindings (vendored v5.6.0 core)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.jolt` |
| Version | 0.4.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | JoltPhysics -- https://github.com/jrouwe/JoltPhysics |
| Upstream version | tag **v5.6.0** |
| Upstream license | MIT (`vendor/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored C++ path is portable |
| Compiler pin | v0.64.4 (`--cxx-standard 17`; m258 included) |
| Modules | `["xiom.jolt"]` (single module; manifest `modules:`) |

## 2. Vendored path (G2 pin)

`tools/combine.py` mirrors `<upstream>/Jolt/**` into `vendor/Jolt/**` with one
textual transform -- `#include <Jolt/...>` becomes `#include "Jolt/..."` --
and emits **25 per-directory TUs** plus a shim that compiles the reviewable
bridge (`src/jolt_bridge.cpp`) from the vendor root.  The quoted includes
resolve through the compiler's include stack (the xiom link line has no `-I`
passthrough); the pinned v0.64.4 toolchain carries C++17.

### Pinned source

| Artifact | Value |
|----------|-------|
| Source of record | tag `v5.6.0`; tarball https://github.com/jrouwe/JoltPhysics/archive/refs/tags/v5.6.0.tar.gz (19,390,751 B, sha256 `6E069EE0172478CC78182047AAC87E5310BA14A67A53348AE14CC37801FD3F8E`) |
| Generated tree sha256 | `ea20c2d1f1f2a16e1fa62efeff5804c9d7b47f51812eefb8ed9ddb4330d6b69b` (generator `tree_hash`, LICENSE excluded; re-verified read-only 2026-10-13) |

Re-pin: extract the new tag, run
`python tools/combine.py <upstream-root> vendor`, record the new tree hash,
re-run `scripts/port.ps1 -Package xiom.jolt` x2 (watchdog >=600 s), update
this table + `README.md`/`AUDIT.md`/`PROVENANCE.md`.

## 3. Design and safe boundary (G5)

`jolt.xi` is the only module with `unsafe`/`extern "C"`.  Three caller
layers over one integer-only bridge (`src/jolt_bridge.cpp`; floats cross as
milli/micros, so XIOM never marshals structs or pointers):

- **0.2.0 probes:** `jolt_drop` builds a static ground + dynamic box
  (single-threaded job system), steps 300 frames at 60 Hz and reports the
  settled center y and sleep state; `jolt_impulse_vx` measures a velocity
  hand-off.
- **0.3.0 world/body surface (engine contract v0 flow):** a fixed registry of
  4 live worlds addressed by slot handles; `jolt_world_create` takes gravity
  (milli m/s^2), a fixed step (micros) and a capacity; `jolt_body_add` /
  `jolt_body_remove` / `jolt_body_count` manage BOX and SPHERE bodies
  (extents/mass/pose/static flag); `jolt_step` / `jolt_step_n` advance by an
  explicit dt; `jolt_body_state` returns owned position (3)/rotation
  (4)/velocity (3)/awake values.
- **0.4.0 external force/torque input (engine buoyancy/water leg):**
  `jolt_body_apply_force` / `jolt_body_apply_torque` take owned scalar args
  (milli-Newtons / milli Newton-metres) and apply them at the body's center
  of mass for the next `Update` only -- Jolt clears the accumulated
  force/torque automatically after every step (repeated calls before a step
  accumulate), and both calls wake a sleeping body (`EActivation::Activate`);
  static bodies are a silent no-op (Jolt semantics).  The owned state
  read-back gains angular velocity (`wx/wy/wz_milli`), so torque effects are
  observable without new pointer surface.

Boundary discipline: handle lifetimes are bridge-owned (registry slots and
Jolt packed body ids, never raw pointers -- B-25); no bare `null` crosses
(B-23); state reads land in bridge-owned scalars and are fetched as scalars
-- no out-param slots, no foreign-pointer reads (B-20/B-24); unknown or
removed body ids are rejected with the typed bridge error code for a bad
body (surfaced as `Err` with the code in the message); all Str composition
stays XIOM-side.  There is no SKIP path -- the vendored sources always
compile in.  Determinism: the only clock is the dt argument (fixed step, no
wall clock); the job system is single-threaded.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- **24 checks**, x2 required:

- 0.2.0 probes (unchanged): drop settles within [400, 600] milli on the
  ground (top at y=0), the body sleeps, the velocity hand-off stays within
  [4500, 5500] milli, and a repeated drop is identical.
- 0.3.0 surface: world create/count/fixed-dt/destroy + stale-handle
  rejection; engine flow (world + static ground box + dynamic box) settles
  and sleeps; the same flow with a sphere settles; a repeated flow is
  bit-identical; free fall is readable between single steps; body
  add/remove/count with stale-id rejection; rotation input round-trips.
- 0.4.0 force/torque input: 60 N on a 1 kg box raises vx to ~1 m/s in one
  1/60 s step (and moves it +x); a second step without re-applying keeps vx
  (no accumulation -- the input was cleared); 6 N.m about z spins wz to
  ~0.6 rad/s and rotation changes; an unknown id and a removed id are both
  rejected by `jolt_body_apply_force`, and a removed id by
  `jolt_body_apply_torque`.

```
scripts/port.ps1 -Package xiom.jolt -TimeoutSec 600
```

The `--cxx-standard 17` flag and the 26-source list are carried by
`port.args.json`.

## 5. Scope

World/body v0 plus per-body external force/torque input: enough for the
engine contract flow (world + ground + box/sphere + N fixed steps +
read-back) and the buoyancy/water application leg (force/torque per body per
frame).  Broad-phase queries, joint variety, character controllers, soft
bodies, and contact events are Phase 5 (`ROADMAP.md`).  The pre-pilot
declaration-only module is preserved in git history.  The generated-tree
hash above was re-verified read-only on 2026-10-13 against the committed
`vendor/` tree (unchanged by 0.4.0 -- the vendored tree is not touched).
