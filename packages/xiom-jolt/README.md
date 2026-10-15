# xiom.jolt

Jolt Physics (v5.6.0, MIT) bindings for XIOM. The upstream `Jolt/**` tree is
mirrored into `vendor/` by `tools/combine.py` (25 per-directory TUs + a
bridge shim) and compiled into the test binary with `--c-source`; Jolt
requires C++17, carried by the pinned v0.64.4 toolchain (thread via
`port.args.json`).

> **Status:** `incubating` -- suite **159/159 x2** on the v0.64.4 pin: the
> 0.2.0 probes (drop settles at 479 milli asleep; impulse vx=4995), the
> 0.3.0 caller-usable world/body surface (engine contract v0 flow: world +
> ground + box/sphere + N fixed steps + read-back), the 0.4.0 per-body
> external force/torque input (one-step-only semantics, angular read-back,
> unknown/removed id rejection), the 0.5.0 tiers (E1 raycast/any-hit,
> sphere/capsule sweeps, sphere/capsule overlaps with canonical
> deterministic order; E2 capsule bodies; E7 contact manifolds and
> non-physical sensor volumes with per-step overlap events), the 0.6.0
> tiers (E3 typed joints -- fixed/hinge/slider/point to a body or the
> world, motors (velocity/position targets), limits, owned state read-back
> and joint-driven determinism; E6 convex hull bodies from caller vertex
> buffers and compound bodies combining box/sphere/capsule/convex parts),
> and the 0.7.0 tiers (E4 soft bodies -- cloth grid / rope / volume presets
> over caller-driven size parameters, simulate under gravity with
> constraint solving, particle state read-back into owned scalars and a
> caller-owned buffer, settle/drape + determinism; E5 heightfield terrain
> -- collider from caller samples + scale/quantization, a box settling on
> it, E1 raycasts hitting height/normal); run record in `STATUS.json`.
> 0.2.0 published in `eco-v0.1.161` (sha256 `f08d65ca...`); 0.3.0 in
> `eco-v0.1.176` (sha256 `3ac3df4e...`); 0.4.0 in `eco-v0.1.179`
> (sha256 `9315bbc7...`); 0.5.0 in `eco-v0.1.180` (sha256 `1035c987...`);
> 0.6.0 and 0.7.0 not yet published.
> **Lane:** bindings (`keywords: ["binding"]`).
> **Published**: `0.5.0` in `eco-v0.1.180` (sha256 `1035c987...`).

## Quick start

```xiom
use xiom.io;
use xiom.jolt;

fn main() {
  // Probes (0.2.0)
  let d = jolt_drop();
  if d.is_ok {
    io.println("settled (see JoltDropResult)");
  }

  // World/body surface (0.3.0): world + ground + falling box + N steps + read-back
  let wr = jolt_world_create(0, -9810, 0, 16666, 64);
  if wr.is_ok {
    let w = wr.value;
    let ground = jolt_body_add(w, JoltBodyDesc{
      shape: JOLT_SHAPE_BOX;
      ex_milli: 20000;
      ey_milli: 500;
      ez_milli: 20000;
      mass_milli: 0;
      px_milli: 0;
      py_milli: -500;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: true;
    });
    let box = jolt_body_add(w, JoltBodyDesc{
      shape: JOLT_SHAPE_BOX;
      ex_milli: 500;
      ey_milli: 500;
      ez_milli: 500;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 5000;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: false;
    });
    let stepped = jolt_step_n(w, 16666, 300);
    if stepped.is_ok && box.is_ok {
      let st = jolt_body_state(w, box.value);
      if st.is_ok {
        io.println("box y (milli)");
      }
    }
    let gone = jolt_world_destroy(w);
  }
}
```

External force/torque (0.4.0) targets a live dynamic body for the next step
only -- Jolt clears the accumulated input after every `Update` (repeated
calls before a step accumulate) and each call wakes a sleeping body:

```xiom
// 60 N on 1 kg => dv = 1 m/s after one 1/60 s step; 6 N.m about z spins it
let pushed = jolt_body_apply_force(w, box.value, 60000, 0, 0);
let spun = jolt_body_apply_torque(w, box.value, 0, 0, 6000);
if !pushed.is_ok {
  io.println("stale or unknown body id: " + pushed.error);
}
```

World queries (0.5.0) return owned hits; overlap lists are canonically
ordered (ascending body id) so repeated runs read back identical sequences:

```xiom
// Closest hit of a 1 m downward ray (fraction is milli of the displacement)
let ray = jolt_raycast(w, 0, 2000, 0, 0, -1000, 0);
if ray.is_ok && ray.value.hit {
  io.println("hit body id at y (milli):");
}
// Closest capsule sweep, sphere overlap, sensor trigger volume
let sweep = jolt_sweep_capsule(w, 500, 500, 0, 3000, 0, 0, 0, 0, 0, 0, -3000, 0);
let n = jolt_overlap_sphere(w, 800, 0, 500, 0);
let sensor = jolt_body_add_sensor(w, JoltBodyDesc{
  shape: JOLT_SHAPE_BOX;
  ex_milli: 1500; ey_milli: 1500; ez_milli: 1500;
  mass_milli: 0;
  px_milli: 0; py_milli: 1000; pz_milli: 0;
  rx_milli: 0; ry_milli: 0; rz_milli: 0; rw_milli: 0;
  is_static: false;
});
```

Contact reads (0.5.0) describe the last step's active manifolds; sleeping
bodies report no contacts (Jolt semantics):

```xiom
let cc = jolt_contact_count(w);
if cc.is_ok && cc.value > 0 {
  let c = jolt_contact(w, 0);
  if c.is_ok {
    // c.value.body_a / body_b, point (px/py/pz), normal, depth_micros
  }
}
```

Joints (0.6.0) connect two bodies or a body and `JOLT_WORLD`; motors and
limits are configured at creation, driven and read back as owned values:

```xiom
// Motorized hinge to the world about +Z through the body center
let j = jolt_joint_add(w, JoltJointDesc{
  kind: JOLT_JOINT_HINGE;
  body_a: JOLT_WORLD;
  body_b: box.value;
  px_milli: 0; py_milli: 1000; pz_milli: 0;
  ax_milli: 0; ay_milli: 0; az_milli: 1000;
  auto_anchor: false;
  has_limits: true;
  limits_min_milli: -250; limits_max_milli: 250;
  motor_frequency_milli: 0; motor_damping_milli: 0;
  motor_max_force_milli: 0; motor_max_torque_milli: 0;
});
if j.is_ok {
  let m = jolt_joint_set_motor(w, j.value, JOLT_MOTOR_VELOCITY, 1000); // milli rad/s
  let st = jolt_joint_state(w, j.value); // angle + applied impulse
}
```

Convex and compound bodies (0.6.0) are built from caller-owned buffers
(push-growth, never `Vec.with_len`); the points/parts are copied
bridge-side:

```xiom
// Convex hull from a flat xyz-triple buffer (milli)
var verts = Vec[Int].new();
verts.push(-500); verts.push(-500); verts.push(-500);
// ... more corners ...
let hull = jolt_body_add_convex(w, JoltBodyDesc{
  shape: JOLT_SHAPE_CONVEX;
  ex_milli: 0; ey_milli: 0; ez_milli: 0; mass_milli: 0;
  px_milli: 0; py_milli: 5000; pz_milli: 0;
  rx_milli: 0; ry_milli: 0; rz_milli: 0; rw_milli: 0;
  is_static: false;
}, &verts);

// Compound of JOLT_PART_STRIDE-entry parts over a shared vertex buffer
let comp = jolt_body_add_compound(w, compound_desc, &parts, &comp_verts);
```

Soft bodies (0.7.0) come from presets over caller-driven size parameters;
the bridge owns the particles/constraints and reads state back as owned
values or into a caller-owned buffer:

```xiom
// A 6x6 cloth pinned along one row (JOLT_SOFT_GRID) at (0, 2000, 0)
let cloth = jolt_soft_add(w, JoltSoftDesc{
  kind: JOLT_SOFT_GRID;
  nx: 6; nz: 6; spacing_milli: 500;
  px_milli: 0; py_milli: 2000; pz_milli: 0;
  rx_milli: 0; ry_milli: 0; rz_milli: 0; rw_milli: 0;
  pin_edge: true;
});
if cloth.is_ok {
  let st = jolt_soft_state(w, cloth.value); // vertex_count + center + awake
  // Bulk particle positions: 3 * vertex_count entries (push-growth buffer)
  var pos = Vec[Int].new();
  var i = 0;
  while i < st.value.vertex_count * 3 {
    pos.push(0);
    i = i + 1;
  }
  let n = jolt_soft_vertices_into(w, cloth.value, &mut pos);
  let v0 = jolt_soft_vertex(w, cloth.value, 0); // position + velocity
}
```

Heightfield terrain (0.7.0) is built from caller-owned height samples; rigid
bodies settle on it and E1 queries hit it with its height and normal:

```xiom
// 5x5 samples (milli) with horizontal spacing 2000 and vertical scale 4000
var hs = Vec[Int].new();
var s = 0;
while s < 25 {
  hs.push(2000); // a flat plateau at 2 m
  s = s + 1;
}
let terrain = jolt_body_add_heightfield(w, 2000, 4000, 2000, 0, 0, 0, 0, &hs);
if terrain.is_ok {
  let ray = jolt_raycast(w, 4000, 10000, 4000, 0, -10000, 0); // y ~= 2000
}
```

All lengths are thousandths (milli), all times microseconds, forces
milli-Newtons and torques milli Newton-metres; rotation is a quaternion in
milli (all-zero = identity). Fixed `dt` only -- no wall clock.

## API

| Area | Functions |
|------|-----------|
| Probes | `jolt_drop` -> `JoltDropResult` (final_y_milli/awake); `jolt_impulse_vx` -> vx in milli |
| World | `jolt_world_create` -> `JoltWorld` (handle/capacity/dt_micros); `jolt_world_dt_micros`; `jolt_world_destroy` -> bodies destroyed |
| Bodies | `jolt_body_add(w, JoltBodyDesc)` -> id (`JOLT_SHAPE_BOX` / `JOLT_SHAPE_SPHERE` / `JOLT_SHAPE_CAPSULE`); `jolt_body_add_sensor` -> sensor id; `jolt_body_remove` -> count left; `jolt_body_count` |
| Shapes (E6) | `jolt_body_add_convex(w, d, &verts_milli)` -> id (hull from a Vec[Int] xyz-triple buffer, 4..256 vertices); `jolt_body_add_compound(w, d, &parts, &verts_milli)` -> id (flat `JOLT_PART_STRIDE` part table: box/sphere/capsule/convex at relative transforms) |
| Force input | `jolt_body_apply_force(w, id, fx_milli, fy_milli, fz_milli)` -> id; `jolt_body_apply_torque(w, id, tx_milli, ty_milli, tz_milli)` -> id (next step only; wakes the body; unknown/removed ids rejected) |
| Stepping | `jolt_step(w, dt_micros)`; `jolt_step_n(w, dt_micros, n)` |
| Read-back | `jolt_body_state(w, id)` -> `JoltBodyState` (position 3, rotation 4, linear velocity 3, angular velocity 3, awake) |
| Queries (E1) | `jolt_raycast` / `jolt_raycast_any` -> `JoltQueryHit`; `jolt_sweep_sphere` / `jolt_sweep_capsule` -> `JoltQueryHit`; `jolt_overlap_sphere` / `jolt_overlap_capsule` -> count; `jolt_overlap(w, i)` -> `JoltOverlap` |
| Contacts (E7) | `jolt_contact_count`; `jolt_contact(w, i)` -> `JoltContact` (body_a/body_b, point_count, first point, normal, depth_micros); `jolt_contact_point(w, i, j)` -> `JoltPoint`; `jolt_contact_pair_count(w, a, b)` |
| Sensors (E7) | `jolt_sensor_event_count`; `jolt_sensor_event(w, i)` -> `JoltSensorEvent` (sensor_id/other_id); `jolt_sensor_overlap_count(w, sensor_id)` |
| Joints (E3) | `jolt_joint_add(w, JoltJointDesc)` -> joint id (`JOLT_JOINT_FIXED` / `HINGE` / `SLIDER` / `POINT`; body-to-body or `JOLT_WORLD`; anchors/axes in milli; limits + motor config per joint); `jolt_joint_set_motor(w, id, state, target_milli)` -> state (`JOLT_MOTOR_OFF`/`VELOCITY`/`POSITION`); `jolt_joint_state(w, id)` -> `JoltJointState` (kind, primary_milli angle/position, impulse_milli); `jolt_joint_remove` -> count left; `jolt_joint_count` |
| Soft bodies (E4) | `jolt_soft_add(w, JoltSoftDesc)` -> soft id (`JOLT_SOFT_GRID` cloth / `JOLT_SOFT_ROPE` / `JOLT_SOFT_VOLUME` cube; caller-driven nx/nz/spacing + pose + pin_edge); `jolt_soft_state(w, id)` -> `JoltSoftState` (vertex_count, center, awake); `jolt_soft_vertex(w, id, i)` -> `JoltSoftVertex` (world position + velocity); `jolt_soft_vertices_into(w, id, &mut pos_milli)` -> positions written (3 * vertex_count entries); `jolt_soft_remove` -> count left; `jolt_soft_count` |
| Heightfield (E5) | `jolt_body_add_heightfield(w, sx_milli, sy_milli, sz_milli, px, py, pz, bits, &samples_milli)` -> body id (square row-major sample grid n=isqrt(len), 4..257; samples in [0, sy]; bits 8/16 or 0 = default 8) |

Worlds are bridge-owned: handles are registry slots, valid until
`jolt_world_destroy`; body ids are stale after `jolt_body_remove` and are
rejected (its joints are removed with it); joint ids are bridge-assigned and
stale after `jolt_joint_remove`; soft ids are bridge-assigned and stale
after `jolt_soft_remove`. Force/torque input is one-step-only by Jolt
design (cleared after every `Update`), so re-apply per frame; contacts and
sensor events describe the last step only (active bodies only). Queries
canonicalize every list to ascending body id, so repeated runs return
identical sequences; sensor bodies are visible to queries (filtering is a
later tier). Convex/compound vertex and part buffers stay caller-owned: the
bridge copies them per call, so the Vecs can be reused or dropped
immediately after. Soft bodies keep their particles and constraints
bridge-side (presets over size parameters, nothing marshalled);
`jolt_soft_vertices_into` is the one out-buffer surface: the bridge writes
3 * vertex_count milli entries through the caller Vec's address and the
buffer must be sized with push-growth first. The heightfield sample grid
crosses as a borrowed address for the call only (copied into the shape).
The bridge integer-encodes everything (milli/micros) and never crosses
pointers. Generator + pins: `SPEC.md`; upstream/license ledger:
`PROVENANCE.md`; toolchain requirement and verification record: `AUDIT.md`.

## Tests

```
scripts/port.ps1 -Package xiom.jolt -TimeoutSec 600
```

159 `[PASS]` expected, x2 recorded in `STATUS.json`.
