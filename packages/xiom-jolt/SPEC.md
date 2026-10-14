# SPEC: xiom.jolt -- Jolt Physics bindings (vendored v5.6.0 core)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.jolt` |
| Version | 0.5.0 |
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

`jolt.xi` is the only module with `unsafe`/`extern "C"`.  Five caller
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
- **0.5.0 world queries (tier E1):** `jolt_raycast` (closest hit) and
  `jolt_raycast_any` (first traversal hit, early-out) take an origin +
  displacement in milli and return an owned `JoltQueryHit` (hit flag, packed
  body id, world-space position, surface normal, fraction in milli);
  `jolt_sweep_sphere` / `jolt_sweep_capsule` are closest shape sweeps over
  the same owned hit struct (position/normal at the contact point on the hit
  body; the sweep normal opposes the cast direction, consistent with the
  raycast surface normal); `jolt_overlap_sphere` / `jolt_overlap_capsule`
  return the number of overlapped bodies and the entries are read back with
  `jolt_overlap` (body id + world point).  Every list surface is
  canonicalized to **ascending packed body id**, so the same world and query
  always produce the identical sequence ("deterministic broadphase order");
  the bridge optimizes the broadphase before a query when the body set
  changed, exactly like stepping.  Queries see sensor bodies like any other
  body (filtering is a later tier).
- **0.5.0 capsule shape (tier E2):** `JOLT_SHAPE_CAPSULE` joins
  `jolt_body_add` (`ex` = radius, `ey` = half height of the cylinder
  segment, `ey > 0`; `ex`/`ey` in milli; local axis +Y before the body
  rotation).  Capsules simulate like boxes/spheres (settle/contact) and take
  part in all E1 queries (capsule sweeps + capsule overlaps).
- **0.5.0 contacts + sensors (tier E7):** the bridge installs a
  `ContactListener` that caches the **last step's** active contact manifolds:
  `jolt_contact_count` / `jolt_contact` expose body pair (ascending id), the
  first contact point plus `point_count`, the manifold normal (milli,
  pointing along the shortest path to move `body_b` out of the collision)
  and the penetration depth (micros, negative = speculative);
  `jolt_contact_point` reads every cached point; `jolt_contact_pair_count`
  counts manifolds between two live ids (either order) and rejects unknown/
  removed ids.  `jolt_body_add_sensor` creates a non-physical, static
  trigger volume (shape/extents/pose from the desc; mass/static ignored; it
  reports overlaps with dynamic bodies and takes no part in collision
  response but is hit by queries); `jolt_sensor_event_count` /
  `jolt_sensor_event` report the last step's sensor overlap pairs
  (canonically ordered), and `jolt_sensor_overlap_count` counts a given
  sensor's overlaps, rejecting unknown/removed ids and live non-sensor ids.
  Contacts/events describe the last `Update` only (Jolt reports contacts for
  active bodies; sleeping bodies receive `OnContactRemoved` and disappear
  from the cache).  Caches are bounded (2048 manifolds / 1024 sensor events
  per world, up to 8 points per manifold).

Boundary discipline: handle lifetimes are bridge-owned (registry slots and
Jolt packed body ids, never raw pointers -- B-25); no bare `null` crosses
(B-23); state reads land in bridge-owned scalars and are fetched as scalars
-- no out-param slots, no foreign-pointer reads (B-20/B-24); unknown or
removed body ids are rejected with the typed bridge error code for a bad
body (surfaced as `Err` with the code in the message); all Str composition
stays XIOM-side.  One owned cache slot per out-param; temporary query shapes
are owned by a `RefConst<Shape>` (a freshly `new`ed Jolt `Shape` starts at
refcount 0, so it must be AddRef'd before any `Release()`); all list
surfaces are canonicalized bridge-side.  There is no SKIP path -- the
vendored sources always compile in.  Determinism: the only clock is the dt
argument (fixed step, no wall clock); the job system is single-threaded;
repeated runs (same process and fresh worlds) are bit-identical and covered
by the suite.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- **67 checks**, x2 required:

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
- 0.5.0 E1 queries (query fixture: ground top y=0 + static 1 m box top
  y=1000): closest ray hits box (body/position/normal/fraction); a ray
  offset past the box hits the ground behind it; an upward ray misses; any
  hit finds geometry; the same ray in a fresh world is bit-identical;
  sphere/capsule sweeps hit the box at fraction ~500 and miss upward;
  overlap-sphere finds both bodies in canonical ascending order with a
  point on the box surface; an empty region returns 0; a capsule overlap
  finds the box only; the overlap sequence (ids + points) is identical
  across fresh worlds.
- 0.5.0 E2 capsule: the capsule engine flow settles (y ~1000) and sleeps; a
  90 deg z rotation round-trips; capsule sweeps/overlaps participate in E1.
- 0.5.0 E7 contacts/sensors: the first step of a 100 mm-penetrating box
  reports the deep manifold (pair, up normal, depth ~100000 micros, point
  on the contact surface, point accessor, out-of-range point index
  rejected, order-insensitive pair count); unknown/removed ids rejected;
  out-of-range contact index rejected; contacts go empty once the bodies
  sleep; the repeated scenario is bit-identical; the sensor world reports
  its overlap pair while a sphere falls through (overlap count == event
  count), rejects a live non-sensor id and unknown/removed ids, the sphere
  passes straight through (non-physical), events clear after exit (last
  step only), the sensor is counted/removable like a body, and the repeated
  scenario reports the identical first event.

```
scripts/port.ps1 -Package xiom.jolt -TimeoutSec 600
```

The `--cxx-standard 17` flag and the 26-source list are carried by
`port.args.json`.

## 5. Scope

World/body v0 + external force/torque input + world queries (raycast,
sphere/capsule sweep, sphere/capsule overlap with deterministic order) +
capsule shape + contacts/sensors: enough for the engine contract flow and
its query/trigger asks.  Joints, character controllers, soft bodies and the
deterministic save/restore helper remain later tiers (`ROADMAP.md`, tiers
E3/E4/E5/E6).  The pre-pilot declaration-only module is preserved in git
history.  The generated-tree hash above was re-verified read-only on
2026-10-13 against the committed `vendor/` tree (unchanged by 0.4.0/0.5.0 --
the vendored tree is not touched).
