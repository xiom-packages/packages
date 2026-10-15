# xiom.jolt

Jolt Physics (v5.6.0, MIT) bindings for XIOM. The upstream `Jolt/**` tree is
mirrored into `vendor/` by `tools/combine.py` (25 per-directory TUs + a
bridge shim) and compiled into the test binary with `--c-source`; Jolt
requires C++17, carried by the pinned v0.64.4 toolchain (thread via
`port.args.json`).

> **Status:** `incubating` -- suite **109/109 x2** on the v0.64.4 pin: the
> 0.2.0 probes (drop settles at 479 milli asleep; impulse vx=4995), the
> 0.3.0 caller-usable world/body surface (engine contract v0 flow: world +
> ground + box/sphere + N fixed steps + read-back), the 0.4.0 per-body
> external force/torque input (one-step-only semantics, angular read-back,
> unknown/removed id rejection), the 0.5.0 tiers (E1 raycast/any-hit,
> sphere/capsule sweeps, sphere/capsule overlaps with canonical
> deterministic order; E2 capsule bodies; E7 contact manifolds and
> non-physical sensor volumes with per-step overlap events), and the 0.6.0
> tiers (E3 typed joints -- fixed/hinge/slider/point to a body or the
> world, motors (velocity/position targets), limits, owned state read-back
> and joint-driven determinism; E6 convex hull bodies from caller vertex
> buffers and compound bodies combining box/sphere/capsule/convex parts);
> run record in `STATUS.json`. 0.2.0 published in `eco-v0.1.161`
> (sha256 `f08d65ca...`); 0.3.0 in `eco-v0.1.176` (sha256 `3ac3df4e...`);
> 0.4.0 in `eco-v0.1.179` (sha256 `9315bbc7...`); 0.5.0 in `eco-v0.1.180`
> (sha256 `1035c987...`); **0.6.0 in `eco-v0.1.181` (sha256 `e5c777f8...`)**.
> **Lane:** bindings (`keywords: ["binding"]`).
> **Published**: `0.6.0` in `eco-v0.1.181` (sha256 `e5c777f8...`).

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

Worlds are bridge-owned: handles are registry slots, valid until
`jolt_world_destroy`; body ids are stale after `jolt_body_remove` and are
rejected (its joints are removed with it); joint ids are bridge-assigned and
stale after `jolt_joint_remove`. Force/torque input is one-step-only by Jolt
design (cleared after every `Update`), so re-apply per frame; contacts and
sensor events describe the last step only (active bodies only). Queries
canonicalize every list to ascending body id, so repeated runs return
identical sequences; sensor bodies are visible to queries (filtering is a
later tier). Convex/compound vertex and part buffers stay caller-owned: the
bridge copies them per call, so the Vecs can be reused or dropped
immediately after. The bridge integer-encodes everything (milli/micros) and
never crosses pointers. Generator + pins: `SPEC.md`; upstream/license
ledger: `PROVENANCE.md`; toolchain requirement and verification record:
`AUDIT.md`.

## Tests

```
scripts/port.ps1 -Package xiom.jolt -TimeoutSec 600
```

109 `[PASS]` expected, x2 recorded in `STATUS.json`.
