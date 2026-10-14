// XIOM -- xiom.jolt: Jolt Physics bindings (vendored v5.6.0 core).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C++ core (the ozz/sqlite method, generated).
// `tools/combine.py` mirrors the upstream `Jolt/**` tree into `vendor/Jolt`
// with one textual transform (`#include <Jolt/...>` -> `"Jolt/..."`) and
// emits 25 per-directory TUs plus a shim that compiles the reviewable
// bridge (`src/jolt_bridge.cpp`) from the vendor root (the quoted "Jolt/..."
// includes resolve through the compiler's include stack; the xiom link line
// has no -I passthrough).  Unblocked by compiler v0.64.3 (C++17 default;
// bus item REL-20261010-1548-bindings-7).
//
// The module has three caller layers, all integer-only (floats cross as
// milli/micros; B-20/B-23/B-24/B-25 discipline -- no pointer casts, no bare
// null, no foreign-pointer reads, no out-param slots):
//   * 0.2.0 scalar-return probes: jolt_drop / jolt_impulse_vx run a fixed
//     scenario and return owned values.
//   * 0.3.0 caller-usable world/body surface: jolt_world_create / body
//     add-remove-count / jolt_step(_n) / jolt_body_state -- enough to run
//     the engine contract v0 flow (world + ground + box/sphere + N fixed
//     steps + read-back).  Values are owned; state is cached bridge-side and
//     fetched as scalars, mirroring the JoltDropResult probe style.
//   * 0.4.0 per-body external force/torque input: jolt_body_apply_force /
//     jolt_body_apply_torque (owned scalar args, milli N / milli N.m) target
//     a live dynamic body for the next step only -- Jolt clears accumulated
//     force/torque after every Update, so repeated calls before a step
//     accumulate and each application wakes the body.  Read-back gains
//     angular velocity (w*_milli) so torque effects are observable; unknown
//     or removed ids are rejected with a typed error.
//   * 0.5.0 world queries, capsule shape, contacts + sensors (tiers
//     E1/E2/E7): jolt_raycast / jolt_raycast_any (closest and first-hit),
//     jolt_sweep_sphere / jolt_sweep_capsule (closest shape sweeps),
//     jolt_overlap_sphere / jolt_overlap_capsule (overlap lists) with owned
//     hit structs (hit flag, body id, position, normal, fraction);
//     JOLT_SHAPE_CAPSULE bodies (radius + half height) simulate like boxes
//     and spheres and take part in queries; jolt_body_add_sensor creates
//     non-physical trigger volumes whose overlaps are reported per step;
//     jolt_contact_* reads the last step's active contact manifolds (pair,
//     points, normal, penetration depth).  Every list surface is
//     canonicalized to ascending packed body id, so repeated runs are
//     bit-identical; unknown/removed ids yield typed errors.
// All `unsafe`/`extern "C"` live in this single module (G5).
//
// G2 pin (SPEC.md): upstream tag v5.6.0 + generator + generated-tree sha256.
//
// API subset: probes + world/body v0 + external force/torque input + world
// queries + capsule shape + contacts/sensors.
// Joints, character controllers, soft bodies and deterministic save/restore
// are later tiers (ROADMAP.md).

module xiom.jolt

extern "C" {
  fn joltprobe_drop() -> Int32;
  fn joltprobe_awake() -> Int32;
  fn joltprobe_impulse() -> Int32;
  fn joltb_world_create(gravity_x_milli: Int32, gravity_y_milli: Int32, gravity_z_milli: Int32, fixed_dt_micros: Int32, capacity: Int32) -> Int32;
  fn joltb_world_destroy(handle: Int32) -> Int32;
  fn joltb_world_dt(handle: Int32) -> Int32;
  fn joltb_body_add(handle: Int32, shape: Int32, ex_milli: Int32, ey_milli: Int32, ez_milli: Int32, mass_milli: Int32, px_milli: Int32, py_milli: Int32, pz_milli: Int32, rx_milli: Int32, ry_milli: Int32, rz_milli: Int32, rw_milli: Int32, is_static: Int32) -> Int32;
  fn joltb_body_add_sensor(handle: Int32, shape: Int32, ex_milli: Int32, ey_milli: Int32, ez_milli: Int32, px_milli: Int32, py_milli: Int32, pz_milli: Int32, rx_milli: Int32, ry_milli: Int32, rz_milli: Int32, rw_milli: Int32) -> Int32;
  fn joltb_body_remove(handle: Int32, body: Int32) -> Int32;
  fn joltb_body_count(handle: Int32) -> Int32;
  fn joltb_body_apply_force(handle: Int32, body: Int32, fx_milli: Int32, fy_milli: Int32, fz_milli: Int32) -> Int32;
  fn joltb_body_apply_torque(handle: Int32, body: Int32, tx_milli: Int32, ty_milli: Int32, tz_milli: Int32) -> Int32;
  fn joltb_step(handle: Int32, dt_micros: Int32) -> Int32;
  fn joltb_step_n(handle: Int32, dt_micros: Int32, steps: Int32) -> Int32;
  fn joltb_body_state(handle: Int32, body: Int32) -> Int32;
  fn joltb_state_pos(axis: Int32) -> Int32;
  fn joltb_state_rot(axis: Int32) -> Int32;
  fn joltb_state_vel(axis: Int32) -> Int32;
  fn joltb_state_wvel(axis: Int32) -> Int32;
  fn joltb_state_awake() -> Int32;
  fn joltb_raycast_closest(handle: Int32, ox_milli: Int32, oy_milli: Int32, oz_milli: Int32, dx_milli: Int32, dy_milli: Int32, dz_milli: Int32) -> Int32;
  fn joltb_raycast_any(handle: Int32, ox_milli: Int32, oy_milli: Int32, oz_milli: Int32, dx_milli: Int32, dy_milli: Int32, dz_milli: Int32) -> Int32;
  fn joltb_sweep_sphere_closest(handle: Int32, radius_milli: Int32, px_milli: Int32, py_milli: Int32, pz_milli: Int32, dx_milli: Int32, dy_milli: Int32, dz_milli: Int32) -> Int32;
  fn joltb_sweep_capsule_closest(handle: Int32, radius_milli: Int32, half_height_milli: Int32, px_milli: Int32, py_milli: Int32, pz_milli: Int32, rx_milli: Int32, ry_milli: Int32, rz_milli: Int32, rw_milli: Int32, dx_milli: Int32, dy_milli: Int32, dz_milli: Int32) -> Int32;
  fn joltb_overlap_sphere(handle: Int32, radius_milli: Int32, px_milli: Int32, py_milli: Int32, pz_milli: Int32) -> Int32;
  fn joltb_overlap_capsule(handle: Int32, radius_milli: Int32, half_height_milli: Int32, px_milli: Int32, py_milli: Int32, pz_milli: Int32, rx_milli: Int32, ry_milli: Int32, rz_milli: Int32, rw_milli: Int32) -> Int32;
  fn joltb_overlap_fetch(handle: Int32, index: Int32) -> Int32;
  fn joltb_overlap_body() -> Int32;
  fn joltb_overlap_pos(axis: Int32) -> Int32;
  fn joltb_query_hit() -> Int32;
  fn joltb_query_body() -> Int32;
  fn joltb_query_pos(axis: Int32) -> Int32;
  fn joltb_query_nrm(axis: Int32) -> Int32;
  fn joltb_query_fraction() -> Int32;
  fn joltb_contact_count(handle: Int32) -> Int32;
  fn joltb_contact_fetch(handle: Int32, index: Int32) -> Int32;
  fn joltb_contact_point_fetch(handle: Int32, index: Int32, point: Int32) -> Int32;
  fn joltb_contact_pair_count(handle: Int32, body_a: Int32, body_b: Int32) -> Int32;
  fn joltb_contact_body_a() -> Int32;
  fn joltb_contact_body_b() -> Int32;
  fn joltb_contact_point_count() -> Int32;
  fn joltb_contact_normal(axis: Int32) -> Int32;
  fn joltb_contact_depth_micros() -> Int32;
  fn joltb_contact_point(axis: Int32) -> Int32;
  fn joltb_sensor_event_count(handle: Int32) -> Int32;
  fn joltb_sensor_event_fetch(handle: Int32, index: Int32) -> Int32;
  fn joltb_sensor_event_sensor() -> Int32;
  fn joltb_sensor_event_other() -> Int32;
  fn joltb_sensor_overlap_count(handle: Int32, sensor_id: Int32) -> Int32;
}

pub type JoltDropResult = {
  final_y_milli: Int;   // settled box-center y in milli
  awake: Bool;          // body still simulating (false = asleep at rest)
}

/// Shape kind: box (ex/ey/ez are half extents in milli).
pub const JOLT_SHAPE_BOX: Int = 0;

/// Shape kind: sphere (ex is the radius in milli; ey/ez ignored).
pub const JOLT_SHAPE_SPHERE: Int = 1;

/// Shape kind: capsule (ex is the radius in milli; ey is the half height of
/// the cylinder segment, so the total height is 2*(ey + ex); ez ignored).
/// The capsule's local axis is +Y before the body rotation is applied.
pub const JOLT_SHAPE_CAPSULE: Int = 2;

/// A bridge-owned live world.  `handle` is a registry slot, never a raw
/// pointer (B-25); it stays valid until `jolt_world_destroy`.
pub type JoltWorld = {
  handle: Int;
  capacity: Int;
  dt_micros: Int;
}

/// Body creation inputs: shape kind, extents, mass, pose and static/dynamic.
/// Lengths in milli; rotation is a quaternion in milli (all-zero => identity).
/// `mass_milli` > 0 overrides the shape-derived mass on dynamic bodies; 0
/// keeps Jolt's density-derived default.
pub type JoltBodyDesc = {
  shape: Int;
  ex_milli: Int;
  ey_milli: Int;
  ez_milli: Int;
  mass_milli: Int;
  px_milli: Int;
  py_milli: Int;
  pz_milli: Int;
  rx_milli: Int;
  ry_milli: Int;
  rz_milli: Int;
  rw_milli: Int;
  is_static: Bool;
}

/// Owned read-back of one body: position (3), rotation (4), linear velocity
/// (3), angular velocity (3) and the awake flag, all from bridge-owned
/// scalars (no out-param slots).
pub type JoltBodyState = {
  px_milli: Int;
  py_milli: Int;
  pz_milli: Int;
  rx_milli: Int;
  ry_milli: Int;
  rz_milli: Int;
  rw_milli: Int;
  vx_milli: Int;
  vy_milli: Int;
  vz_milli: Int;
  wx_milli: Int;
  wy_milli: Int;
  wz_milli: Int;
  awake: Bool;
}

/// One query hit (0.5.0), owned: `hit` false means no geometry was found and
/// every other field is 0.  `body_id` is the packed id of the hit body;
/// position/normal are world-space milli; `fraction_milli` is the hit
/// fraction (0..1000) along the ray/sweep displacement.
pub type JoltQueryHit = {
  hit: Bool;
  body_id: Int;
  px_milli: Int;
  py_milli: Int;
  pz_milli: Int;
  nx_milli: Int;
  ny_milli: Int;
  nz_milli: Int;
  fraction_milli: Int;
}

/// One world-space point in milli (0.5.0).
pub type JoltPoint = {
  x_milli: Int;
  y_milli: Int;
  z_milli: Int;
}

/// One overlap entry (0.5.0), owned: body id plus a world-space milli point
/// on the overlapped body.  Lists are canonically ordered by ascending body
/// id, so repeated runs read back identical sequences.
pub type JoltOverlap = {
  body_id: Int;
  px_milli: Int;
  py_milli: Int;
  pz_milli: Int;
}

/// One active contact manifold from the last step (0.5.0), owned.
/// `body_a` < `body_b` (Jolt id order); the normal points along the shortest
/// path to move `body_b` out of the collision; `depth_micros` is the
/// penetration depth (negative = speculative contact); `point_count` is the
/// number of contact points cached for the manifold (world-space points on
/// `body_a`; the first is inlined in px/py/pz and all are reachable with
/// `jolt_contact_point`).
pub type JoltContact = {
  body_a: Int;
  body_b: Int;
  point_count: Int;
  px_milli: Int;
  py_milli: Int;
  pz_milli: Int;
  nx_milli: Int;
  ny_milli: Int;
  nz_milli: Int;
  depth_micros: Int;
}

/// One sensor overlap event from the last step (0.5.0), owned: the sensor
/// body id and the other body id.  Events are canonically ordered by
/// (sensor_id, other_id).
pub type JoltSensorEvent = {
  sensor_id: Int;
  other_id: Int;
}

/// Drop a 1 m dynamic box from y=5 onto a static ground and step 300 frames
/// at 60 Hz with a single-threaded job system.
/// Complexity: O(steps).
pub fn jolt_drop() -> Result[JoltDropResult, Str]
  requires: true
{
  let rc = unsafe { joltprobe_drop() as Int };
  if rc < 0 {
    return Err("jolt: drop probe rc=" + jolt_i2s(0 - rc));
  }
  return Ok(JoltDropResult{
    final_y_milli: rc;
    awake: unsafe { joltprobe_awake() as Int } != 0;
  });
}

/// Give a free dynamic box vx = 5 m/s and return the velocity (milli) after
/// one 60 Hz step.  Complexity: O(1).
pub fn jolt_impulse_vx() -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { joltprobe_impulse() as Int };
  if rc < 0 {
    return Err("jolt: impulse probe rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

// ---- caller-usable world/body surface (0.3.0) ------------------------------

/// Create a world with gravity (milli m/s^2 per axis), a fixed step
/// (`dt_micros`) and a body capacity; returns the handle on success.
/// Deterministic: no wall clock is consulted anywhere.
/// Complexity: O(capacity).
pub fn jolt_world_create(gx_milli: Int, gy_milli: Int, gz_milli: Int, dt_micros: Int, capacity: Int) -> Result[JoltWorld, Str]
  requires: dt_micros > 0
  requires: capacity > 0
{
  let rc = unsafe { joltb_world_create(gx_milli as Int32, gy_milli as Int32, gz_milli as Int32, dt_micros as Int32, capacity as Int32) as Int };
  if rc < 0 {
    return Err("jolt: world create rc=" + jolt_i2s(0 - rc));
  }
  return Ok(JoltWorld{
    handle: rc;
    capacity: capacity;
    dt_micros: dt_micros;
  });
}

/// The world's configured fixed step in microseconds.
/// Complexity: O(1).
pub fn jolt_world_dt_micros(w: JoltWorld) -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { joltb_world_dt(w.handle as Int32) as Int };
  if rc < 0 {
    return Err("jolt: world dt rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

/// Destroy the world and every body in it; returns the number of bodies
/// destroyed.  The handle is stale afterwards.  Complexity: O(bodies).
pub fn jolt_world_destroy(w: JoltWorld) -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { joltb_world_destroy(w.handle as Int32) as Int };
  if rc < 0 {
    return Err("jolt: world destroy rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

/// Add a box, sphere or capsule body (see `JoltBodyDesc`); returns the body
/// id.  Capsule bodies (shape 2) need ex (radius) and ey (half height of the
/// cylinder segment) > 0.
/// Complexity: O(bodies) (capacity-checked).
pub fn jolt_body_add(w: JoltWorld, d: JoltBodyDesc) -> Result[Int, Str]
  requires: d.shape == 0 || d.shape == 1 || d.shape == 2
  requires: d.ex_milli > 0
  requires: d.shape != 2 || d.ey_milli > 0
{
  var static_flag: Int = 0;
  if d.is_static { static_flag = 1; }
  let rc = unsafe { joltb_body_add(w.handle as Int32, d.shape as Int32, d.ex_milli as Int32, d.ey_milli as Int32, d.ez_milli as Int32, d.mass_milli as Int32, d.px_milli as Int32, d.py_milli as Int32, d.pz_milli as Int32, d.rx_milli as Int32, d.ry_milli as Int32, d.rz_milli as Int32, d.rw_milli as Int32, static_flag as Int32) as Int };
  if rc < 0 {
    return Err("jolt: body add rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

/// Remove a body by id; returns the number of bodies left.  The id is stale
/// afterwards.  Complexity: O(bodies).
pub fn jolt_body_remove(w: JoltWorld, body_id: Int) -> Result[Int, Str]
  requires: body_id >= 0
{
  let rc = unsafe { joltb_body_remove(w.handle as Int32, body_id as Int32) as Int };
  if rc < 0 {
    return Err("jolt: body remove rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

/// Number of live bodies in the world.  Complexity: O(1).
pub fn jolt_body_count(w: JoltWorld) -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { joltb_body_count(w.handle as Int32) as Int };
  if rc < 0 {
    return Err("jolt: body count rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

/// Apply an external force (milli-Newtons per axis) at a dynamic body's
/// center of mass for the next step; wakes the body.  Jolt clears the
/// accumulated force after every Update, so repeated calls before a step
/// accumulate and a call without a following step has no effect.  Static
/// bodies are a silent no-op (Jolt semantics).  Returns the body id; unknown
/// or removed ids are rejected.  Complexity: O(bodies).
pub fn jolt_body_apply_force(w: JoltWorld, body_id: Int, fx_milli: Int, fy_milli: Int, fz_milli: Int) -> Result[Int, Str]
  requires: body_id >= 0
{
  let rc = unsafe { joltb_body_apply_force(w.handle as Int32, body_id as Int32, fx_milli as Int32, fy_milli as Int32, fz_milli as Int32) as Int };
  if rc < 0 {
    return Err("jolt: apply force rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

/// Apply an external torque (milli Newton-metres per axis) about a dynamic
/// body's center of mass for the next step; same accumulation/clear/wake
/// semantics as `jolt_body_apply_force`.  Returns the body id; unknown or
/// removed ids are rejected.  Complexity: O(bodies).
pub fn jolt_body_apply_torque(w: JoltWorld, body_id: Int, tx_milli: Int, ty_milli: Int, tz_milli: Int) -> Result[Int, Str]
  requires: body_id >= 0
{
  let rc = unsafe { joltb_body_apply_torque(w.handle as Int32, body_id as Int32, tx_milli as Int32, ty_milli as Int32, tz_milli as Int32) as Int };
  if rc < 0 {
    return Err("jolt: apply torque rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

/// Advance the world by one fixed step of `dt_micros`; returns the steps
/// applied (1).  State is readable between steps.
/// Complexity: O(bodies).
pub fn jolt_step(w: JoltWorld, dt_micros: Int) -> Result[Int, Str]
  requires: dt_micros > 0
{
  let rc = unsafe { joltb_step(w.handle as Int32, dt_micros as Int32) as Int };
  if rc < 0 {
    return Err("jolt: step rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

/// Advance the world by `steps` fixed steps of `dt_micros`; returns the
/// steps applied.  Complexity: O(steps * bodies).
pub fn jolt_step_n(w: JoltWorld, dt_micros: Int, steps: Int) -> Result[Int, Str]
  requires: dt_micros > 0
  requires: steps > 0
{
  let rc = unsafe { joltb_step_n(w.handle as Int32, dt_micros as Int32, steps as Int32) as Int };
  if rc < 0 {
    return Err("jolt: step_n rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

/// Read one body's state as owned values (position/rotation/linear velocity/
/// angular velocity in milli + awake).  Complexity: O(bodies).
pub fn jolt_body_state(w: JoltWorld, body_id: Int) -> Result[JoltBodyState, Str]
  requires: body_id >= 0
{
  let rc = unsafe { joltb_body_state(w.handle as Int32, body_id as Int32) as Int };
  if rc < 0 {
    return Err("jolt: body state rc=" + jolt_i2s(0 - rc));
  }
  return Ok(JoltBodyState{
    px_milli: unsafe { joltb_state_pos(0) as Int };
    py_milli: unsafe { joltb_state_pos(1) as Int };
    pz_milli: unsafe { joltb_state_pos(2) as Int };
    rx_milli: unsafe { joltb_state_rot(0) as Int };
    ry_milli: unsafe { joltb_state_rot(1) as Int };
    rz_milli: unsafe { joltb_state_rot(2) as Int };
    rw_milli: unsafe { joltb_state_rot(3) as Int };
    vx_milli: unsafe { joltb_state_vel(0) as Int };
    vy_milli: unsafe { joltb_state_vel(1) as Int };
    vz_milli: unsafe { joltb_state_vel(2) as Int };
    wx_milli: unsafe { joltb_state_wvel(0) as Int };
    wy_milli: unsafe { joltb_state_wvel(1) as Int };
    wz_milli: unsafe { joltb_state_wvel(2) as Int };
    awake: unsafe { joltb_state_awake() as Int } != 0;
  });
}

// ---- world queries (0.5.0, tier E1) ----------------------------------------

/// Closest-hit raycast against the world.  The ray starts at (ox,oy,oz) and
/// runs along the displacement (dx,dy,dz) (all milli); the returned fraction
/// is relative to that displacement.  Deterministic: identical worlds and
/// rays always produce the identical hit (single-threaded broadphase,
/// canonical ordering); sensor bodies are hit like any other body.
/// Complexity: O(broadphase + candidates).
pub fn jolt_raycast(w: JoltWorld, ox_milli: Int, oy_milli: Int, oz_milli: Int, dx_milli: Int, dy_milli: Int, dz_milli: Int) -> Result[JoltQueryHit, Str]
  requires: dx_milli != 0 || dy_milli != 0 || dz_milli != 0
{
  let rc = unsafe { joltb_raycast_closest(w.handle as Int32, ox_milli as Int32, oy_milli as Int32, oz_milli as Int32, dx_milli as Int32, dy_milli as Int32, dz_milli as Int32) as Int };
  return jolt_hit_result("raycast", rc);
}

/// Any-hit raycast: stops at the first hit the traversal meets (not
/// necessarily the closest).  Same inputs, cache and determinism properties
/// as `jolt_raycast`.
/// Complexity: O(broadphase + candidates) (early-out).
pub fn jolt_raycast_any(w: JoltWorld, ox_milli: Int, oy_milli: Int, oz_milli: Int, dx_milli: Int, dy_milli: Int, dz_milli: Int) -> Result[JoltQueryHit, Str]
  requires: dx_milli != 0 || dy_milli != 0 || dz_milli != 0
{
  let rc = unsafe { joltb_raycast_any(w.handle as Int32, ox_milli as Int32, oy_milli as Int32, oz_milli as Int32, dx_milli as Int32, dy_milli as Int32, dz_milli as Int32) as Int };
  return jolt_hit_result("raycast any", rc);
}

/// Closest sphere sweep: a sphere of `radius_milli` starts at (px,py,pz) and
/// travels along (dx,dy,dz); the hit position is the contact point on the
/// hit body and the normal is that body's surface normal there.
/// Deterministic like `jolt_raycast`.
/// Complexity: O(broadphase + candidates).
pub fn jolt_sweep_sphere(w: JoltWorld, radius_milli: Int, px_milli: Int, py_milli: Int, pz_milli: Int, dx_milli: Int, dy_milli: Int, dz_milli: Int) -> Result[JoltQueryHit, Str]
  requires: radius_milli > 0
  requires: dx_milli != 0 || dy_milli != 0 || dz_milli != 0
{
  let rc = unsafe { joltb_sweep_sphere_closest(w.handle as Int32, radius_milli as Int32, px_milli as Int32, py_milli as Int32, pz_milli as Int32, dx_milli as Int32, dy_milli as Int32, dz_milli as Int32) as Int };
  return jolt_hit_result("sweep sphere", rc);
}

/// Closest capsule sweep: radius + half height of the cylinder segment in
/// milli, start pose (position + quaternion in milli; all-zero rotation =
/// identity) and displacement.  The capsule's local axis is +Y before the
/// pose rotation.
/// Complexity: O(broadphase + candidates).
pub fn jolt_sweep_capsule(w: JoltWorld, radius_milli: Int, half_height_milli: Int, px_milli: Int, py_milli: Int, pz_milli: Int, rx_milli: Int, ry_milli: Int, rz_milli: Int, rw_milli: Int, dx_milli: Int, dy_milli: Int, dz_milli: Int) -> Result[JoltQueryHit, Str]
  requires: radius_milli > 0
  requires: half_height_milli > 0
  requires: dx_milli != 0 || dy_milli != 0 || dz_milli != 0
{
  let rc = unsafe { joltb_sweep_capsule_closest(w.handle as Int32, radius_milli as Int32, half_height_milli as Int32, px_milli as Int32, py_milli as Int32, pz_milli as Int32, rx_milli as Int32, ry_milli as Int32, rz_milli as Int32, rw_milli as Int32, dx_milli as Int32, dy_milli as Int32, dz_milli as Int32) as Int };
  return jolt_hit_result("sweep capsule", rc);
}

/// Overlap a sphere with the world; returns the number of hit bodies.
/// Entries are canonically ordered by ascending body id; read each with
/// `jolt_overlap`.  Sensor bodies count as hits.
/// Complexity: O(broadphase + candidates).
pub fn jolt_overlap_sphere(w: JoltWorld, radius_milli: Int, px_milli: Int, py_milli: Int, pz_milli: Int) -> Result[Int, Str]
  requires: radius_milli > 0
{
  let rc = unsafe { joltb_overlap_sphere(w.handle as Int32, radius_milli as Int32, px_milli as Int32, py_milli as Int32, pz_milli as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("overlap sphere", rc));
  }
  return Ok(rc);
}

/// Overlap a capsule (radius + half height, pose; same convention as
/// `jolt_sweep_capsule`) with the world; returns the number of hit bodies.
/// Complexity: O(broadphase + candidates).
pub fn jolt_overlap_capsule(w: JoltWorld, radius_milli: Int, half_height_milli: Int, px_milli: Int, py_milli: Int, pz_milli: Int, rx_milli: Int, ry_milli: Int, rz_milli: Int, rw_milli: Int) -> Result[Int, Str]
  requires: radius_milli > 0
  requires: half_height_milli > 0
{
  let rc = unsafe { joltb_overlap_capsule(w.handle as Int32, radius_milli as Int32, half_height_milli as Int32, px_milli as Int32, py_milli as Int32, pz_milli as Int32, rx_milli as Int32, ry_milli as Int32, rz_milli as Int32, rw_milli as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("overlap capsule", rc));
  }
  return Ok(rc);
}

/// Read one overlap entry from the most recent overlap query on `w`
/// (`jolt_overlap_sphere` / `jolt_overlap_capsule`); the index must be in
/// [0, count).
/// Complexity: O(1).
pub fn jolt_overlap(w: JoltWorld, index: Int) -> Result[JoltOverlap, Str]
  requires: index >= 0
{
  let rc = unsafe { joltb_overlap_fetch(w.handle as Int32, index as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("overlap fetch", rc));
  }
  return Ok(JoltOverlap{
    body_id: unsafe { joltb_overlap_body() as Int };
    px_milli: unsafe { joltb_overlap_pos(0) as Int };
    py_milli: unsafe { joltb_overlap_pos(1) as Int };
    pz_milli: unsafe { joltb_overlap_pos(2) as Int };
  });
}

// ---- contacts + sensors (0.5.0, tier E7) -----------------------------------

/// Add a sensor body: a non-physical trigger volume with the shape/extents/
/// pose of `d` (mass and the static flag are ignored -- sensors are static
/// on the non-moving layer and report overlaps with dynamic bodies).  The id
/// is a normal body id: it participates in counts/removal/queries.
/// Complexity: O(bodies) (capacity-checked).
pub fn jolt_body_add_sensor(w: JoltWorld, d: JoltBodyDesc) -> Result[Int, Str]
  requires: d.shape == 0 || d.shape == 1 || d.shape == 2
  requires: d.ex_milli > 0
  requires: d.shape != 2 || d.ey_milli > 0
{
  let rc = unsafe { joltb_body_add_sensor(w.handle as Int32, d.shape as Int32, d.ex_milli as Int32, d.ey_milli as Int32, d.ez_milli as Int32, d.px_milli as Int32, d.py_milli as Int32, d.pz_milli as Int32, d.rx_milli as Int32, d.ry_milli as Int32, d.rz_milli as Int32, d.rw_milli as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("sensor add", rc));
  }
  return Ok(rc);
}

/// Number of active contact manifolds cached by the last step.  Only active
/// bodies report contacts (sleeping bodies report none), at most one
/// manifold per body/sub-shape pair per step; entries are canonically
/// ordered by (body_a, body_b).
/// Complexity: O(1).
pub fn jolt_contact_count(w: JoltWorld) -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { joltb_contact_count(w.handle as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("contact count", rc));
  }
  return Ok(rc);
}

/// Read one cached contact manifold (index in [0, count)): body pair, point
/// count, normal (milli, points along the shortest path to move `body_b`
/// out of the collision), penetration depth (micros; negative = speculative
/// contact) and the first contact point in world milli (further points via
/// `jolt_contact_point`).
/// Complexity: O(1).
pub fn jolt_contact(w: JoltWorld, index: Int) -> Result[JoltContact, Str]
  requires: index >= 0
{
  let rc = unsafe { joltb_contact_fetch(w.handle as Int32, index as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("contact fetch", rc));
  }
  return Ok(JoltContact{
    body_a: unsafe { joltb_contact_body_a() as Int };
    body_b: unsafe { joltb_contact_body_b() as Int };
    point_count: unsafe { joltb_contact_point_count() as Int };
    px_milli: unsafe { joltb_contact_point(0) as Int };
    py_milli: unsafe { joltb_contact_point(1) as Int };
    pz_milli: unsafe { joltb_contact_point(2) as Int };
    nx_milli: unsafe { joltb_contact_normal(0) as Int };
    ny_milli: unsafe { joltb_contact_normal(1) as Int };
    nz_milli: unsafe { joltb_contact_normal(2) as Int };
    depth_micros: unsafe { joltb_contact_depth_micros() as Int };
  });
}

/// Read contact point `point` (in [0, point_count)) of cached manifold
/// `entry` as a world-space milli position.
/// Complexity: O(1).
pub fn jolt_contact_point(w: JoltWorld, entry: Int, point: Int) -> Result[JoltPoint, Str]
  requires: entry >= 0
  requires: point >= 0
{
  let rc = unsafe { joltb_contact_point_fetch(w.handle as Int32, entry as Int32, point as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("contact point", rc));
  }
  return Ok(JoltPoint{
    x_milli: unsafe { joltb_contact_point(0) as Int };
    y_milli: unsafe { joltb_contact_point(1) as Int };
    z_milli: unsafe { joltb_contact_point(2) as Int };
  });
}

/// Number of cached manifolds between two live bodies (either order) in the
/// last step; unknown or removed ids are rejected with a typed error.
/// Complexity: O(contacts).
pub fn jolt_contact_pair_count(w: JoltWorld, body_a: Int, body_b: Int) -> Result[Int, Str]
  requires: body_a >= 0
  requires: body_b >= 0
{
  let rc = unsafe { joltb_contact_pair_count(w.handle as Int32, body_a as Int32, body_b as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("contact pair count", rc));
  }
  return Ok(rc);
}

/// Number of sensor overlap events cached by the last step.  Events are
/// canonically ordered by (sensor_id, other_id); a pair is reported while
/// the other body is active, matching Jolt's contact-listener semantics.
/// Complexity: O(1).
pub fn jolt_sensor_event_count(w: JoltWorld) -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { joltb_sensor_event_count(w.handle as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("sensor event count", rc));
  }
  return Ok(rc);
}

/// Read one sensor event (index in [0, count)): the sensor body id and the
/// other body it currently overlaps.
/// Complexity: O(1).
pub fn jolt_sensor_event(w: JoltWorld, index: Int) -> Result[JoltSensorEvent, Str]
  requires: index >= 0
{
  let rc = unsafe { joltb_sensor_event_fetch(w.handle as Int32, index as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("sensor event", rc));
  }
  return Ok(JoltSensorEvent{
    sensor_id: unsafe { joltb_sensor_event_sensor() as Int };
    other_id: unsafe { joltb_sensor_event_other() as Int };
  });
}

/// Number of bodies the given sensor overlaps in the last step.  Unknown or
/// removed ids are rejected with a typed error, and so is a live body that
/// is not a sensor.
/// Complexity: O(events).
pub fn jolt_sensor_overlap_count(w: JoltWorld, sensor_id: Int) -> Result[Int, Str]
  requires: sensor_id >= 0
{
  let rc = unsafe { joltb_sensor_overlap_count(w.handle as Int32, sensor_id as Int32) as Int };
  if rc < 0 {
    return Err(jolt_err("sensor overlap count", rc));
  }
  return Ok(rc);
}

// ---- internals -----------------------------------------------------------

fn jolt_err(op: Str, rc: Int) -> Str
  requires: rc < 0
{
  return "jolt: " + op + " rc=" + jolt_i2s(0 - rc);
}

fn jolt_hit_result(op: Str, rc: Int) -> Result[JoltQueryHit, Str]
  requires: rc <= 1
{
  if rc < 0 {
    return Err(jolt_err(op, rc));
  }
  return Ok(JoltQueryHit{
    hit: rc == 0;
    body_id: unsafe { joltb_query_body() as Int };
    px_milli: unsafe { joltb_query_pos(0) as Int };
    py_milli: unsafe { joltb_query_pos(1) as Int };
    pz_milli: unsafe { joltb_query_pos(2) as Int };
    nx_milli: unsafe { joltb_query_nrm(0) as Int };
    ny_milli: unsafe { joltb_query_nrm(1) as Int };
    nz_milli: unsafe { joltb_query_nrm(2) as Int };
    fraction_milli: unsafe { joltb_query_fraction() as Int };
  });
}

fn jolt_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  return buf;
}
