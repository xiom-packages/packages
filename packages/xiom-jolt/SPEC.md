# SPEC: xiom.jolt -- Jolt Physics bindings (vendored v5.6.0 core)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.jolt` |
| Version | 0.6.0 |
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

`jolt.xi` is the only module with `unsafe`/`extern "C"`.  Eight caller
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
- **0.6.0 typed joints (tier E3):** `jolt_joint_add` creates FIXED / HINGE /
  SLIDER / POINT joints from a `JoltJointDesc` between two live bodies or
  between one live body and `JOLT_WORLD` (Jolt's `Body::sFixedToWorld`
  sentinel; the bridge maps -1 onto it and never crosses a pointer).  The
  anchor (`px/py/pz`) and axis (`ax/ay/az`, hinge/slider) are world-space
  milli; `auto_anchor` (fixed/slider) welds/zeroes at the bodies' current
  relative pose; `has_limits` enables hinge limits in milli rad (validated
  inside [-pi, pi] with min <= 0 <= max, Jolt's assert range) or slider
  limits in milli m (min <= 0 <= max).  Hinge/slider motors are configured
  per joint at creation (`motor_frequency_milli` / `motor_damping_milli`
  override Jolt's default 2 Hz critical spring; `motor_max_force_milli` /
  `motor_max_torque_milli` cap the drive) and driven with
  `jolt_joint_set_motor` (velocity target in milli rad/s or milli m/s;
  position target in milli rad or milli m, clamped to the limits by Jolt);
  motor updates wake the joint bodies.  `jolt_joint_state` reads back owned
  values: the hinge angle / slider position (`primary_milli`) and the applied
  impulse (`impulse_milli`: the motor's total lambda for hinge/slider, the
  reaction-impulse magnitude for fixed/point).  `jolt_joint_remove` /
  `jolt_joint_count` manage a per-world joint registry (bridge-assigned ids,
  one owned `Ref<Constraint>` per joint); removing a body removes its joints
  first (Jolt forbids removing a referenced body) and world destruction
  unregisters every constraint before teardown.  Typed errors:
  `kErrBadJoint` (unknown/removed id), `kErrBadJointKind`, `kErrNoMotor`
  (motor op/config on a joint without a motor), `kErrBadLimits`, plus the
  shared bad-body/bad-arg codes; world-world and same-body pairs, two
  non-dynamic bodies and degenerate hinge/slider axes are rejected.
- **0.6.0 convex + compound bodies (tier E6):** `jolt_body_add_convex`
  builds a `ConvexHullShape` from a caller-owned `Vec[Int]` of milli xyz
  triples (4..256 vertices; interior points allowed; the bridge copies the
  points, so the Vec stays caller-owned; a failed hull build is a typed
  `kErrBadHull`).  `jolt_body_add_compound` builds a `StaticCompoundShape`
  from a flat part table (`JOLT_PART_STRIDE` = 13 Int entries per part:
  kind, extents, vertex offset/count for convex slices, local position,
  local quaternion; box/sphere/capsule/convex parts) over a shared vertex
  buffer; malformed part tables are rejected with `kErrBadCompound`.  Both
  body kinds take the usual mass/pose/static inputs, simulate like the
  primitive shapes (settle/contact/sleep) and participate in every E1 query
  and E7 contact/sensor surface with no extra code.

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

Suite: `tests/test_conformance.xi` -- **109 checks**, x2 required:

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
- 0.6.0 E3 joints (25 checks): a zero-gravity world hinge with a +1 rad/s
  velocity motor reaches ~1 rad (999 milli) after 60 fixed steps and the
  repeated flow is bit-identical (angle/impulse/pair -- the joint-driven
  determinism requirement); a position motor converges to +700 milli rad;
  hinge limits [-250, +250] milli rad stop the motor at +250; a world
  slider with a +500 milli m/s motor travels ~500 milli and its
  [-1000, +200] limits clamp at +200; a two-body auto-anchored fixed weld
  under gravity holds the welded box at its spawn pose and reports a
  non-zero reaction impulse; a world point joint keeps the pivot distance
  through a pendulum swing.  Typed errors: unknown body id, same body,
  world-world, degenerate hinge axis, motor config on fixed, limits on
  point, out-of-range hinge limits, unknown joint id (state + remove),
  stale joint id after remove, motor op on fixed, joint count, and
  auto-removal of joints when a body is removed (count drops, state
  rejects).
- 0.6.0 E6 convex/compound (17 checks): a convex hull body built from an
  8-corner + interior-point vertex Vec settles at y=479 and sleeps like the
  box flow, the repeated flow is bit-identical, and the hull is hit by
  raycast/overlap; a 4-part compound (box + sphere + capsule + convex at
  relative transforms) settles at y=479 and sleeps, repeats bit-identically,
  is hit per part by raycasts (convex top at y=1400, sphere top at y=750
  in the fixture), is found by overlap and reports a landing contact
  manifold with the ground; typed errors: too-few hull vertices, unknown
  part kind, out-of-range convex vertex slice, empty part table, wrong
  part-table stride.

```
scripts/port.ps1 -Package xiom.jolt -TimeoutSec 600
```

The `--cxx-standard 17` flag and the 26-source list are carried by
`port.args.json`.

## 5. Scope

World/body v0 + external force/torque input + world queries (raycast,
sphere/capsule sweep, sphere/capsule overlap with deterministic order) +
capsule shape + contacts/sensors + typed joints (fixed/hinge/slider/point
with motors, limits and state read-back) + convex/compound bodies: enough
for the engine contract flow and its query/trigger/joint/shape asks.
Character controllers (E4), soft bodies (E5), collision filtering on query
paths and the deterministic save/restore state helper remain later tiers
(`ROADMAP.md`).  The pre-pilot declaration-only module is preserved in git
history.  The generated-tree hash above was re-verified read-only on
2026-10-13 against the committed `vendor/` tree (unchanged by
0.4.0/0.5.0/0.6.0 -- the vendored tree is not touched).
