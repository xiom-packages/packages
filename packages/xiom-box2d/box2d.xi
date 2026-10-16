// XIOM -- xiom.box2d: Box2D v3.1.1 physics bindings (vendored C).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C path (the sqlite/lzfse pattern).  The upstream v3.1.1
// sources are vendored unmodified in `vendor/` (flat layout, so the quoted
// "box2d/..." includes resolve against each file's own directory) and are
// compiled into the test binary with --c-source (port.args.json).  No system
// library, no DLL, no SDK.
//
// The module calls a small integer-only C bridge (src/box2d_bridge.c) that
// owns the float/struct ABI internally; values cross the boundary as
// thousandths (milli).  All `unsafe`/`extern "C"` live in this single
// module (G5); no malloc/free (B-05) -- the probe out-params use XIOM-owned
// slots while the 0.4.0 caller surface is pointer-free (bridge-side scalar
// caches fetched by dedicated accessors; B-20/B-24/B-25 discipline).
//
// G2 pin (SPEC.md): upstream tag v3.1.1 archive SHA256 + per-file SHA256
// table + MIT license.
//
// API subset (pilot + 0.3.0): version, default-world gravity, a resting-drop
// simulation (static ground + dynamic box), an impulse->velocity check, and
// (0.3.0) revolute + prismatic joints with motors.
//
// 0.4.0 adds the caller-usable 2D-solver surface (engine PACKAGE-ASKS A02):
// world create/destroy (2D gravity, fixed dt, capacity), static + dynamic
// bodies with caller shapes (circle/box), step / step N at the world's fixed
// dt, state read by handle (pos/vel/angle/awake; dedicated accessors building
// fresh values -- no out-param slot recycle), body count/mass, broadphase
// queries (closest-raycast, circle/box overlap), contact events (begin/end/
// hit) and the remaining tractable joint types (revolute/prismatic/weld/
// distance/wheel/motor through one typed desc).  Every 0.4.0 entry point is
// pointer-free: state is cached bridge-side and fetched as scalars
// (B-20/B-24/B-25 discipline).

module xiom.box2d

use xiom.ffi;

extern "C" {
  fn b2probe_version() -> Int32;
  fn b2probe_gravity(out_gx_milli: *UInt8, out_gy_milli: *UInt8) -> Int32;
  fn b2probe_drop(start_y_milli: Int32, steps: Int32, out_final_y_milli: *UInt8, out_awake: *UInt8) -> Int32;
  fn b2probe_impulse(impulse_milli: Int32, out_vx_milli: *UInt8) -> Int32;
  fn b2probe_revolute_motor(motor_speed_milli: Int32, steps: Int32, out_w_milli: *UInt8, out_angle_milli: *UInt8) -> Int32;
  fn b2probe_prismatic_motor(motor_speed_milli: Int32, steps: Int32, out_translation_milli: *UInt8, out_x_milli: *UInt8, out_y_milli: *UInt8) -> Int32;
  fn b2b_world_create(gx_milli: Int32, gy_milli: Int32, dt_micros: Int32, capacity: Int32) -> Int32;
  fn b2b_world_destroy(handle: Int32) -> Int32;
  fn b2b_world_dt(handle: Int32) -> Int32;
  fn b2b_body_add(handle: Int32, shape: Int32, ex_milli: Int32, ey_milli: Int32, px_milli: Int32, py_milli: Int32, angle_milli: Int32, mass_milli: Int32, is_static: Int32) -> Int32;
  fn b2b_body_remove(handle: Int32, body: Int32) -> Int32;
  fn b2b_body_count(handle: Int32) -> Int32;
  fn b2b_body_mass(handle: Int32, body: Int32) -> Int32;
  fn b2b_step(handle: Int32) -> Int32;
  fn b2b_step_n(handle: Int32, steps: Int32) -> Int32;
  fn b2b_body_state(handle: Int32, body: Int32) -> Int32;
  fn b2b_state_pos_x() -> Int32;
  fn b2b_state_pos_y() -> Int32;
  fn b2b_state_vel_x() -> Int32;
  fn b2b_state_vel_y() -> Int32;
  fn b2b_state_angle() -> Int32;
  fn b2b_state_w() -> Int32;
  fn b2b_state_awake() -> Int32;
  fn b2b_raycast(handle: Int32, ox_milli: Int32, oy_milli: Int32, dx_milli: Int32, dy_milli: Int32) -> Int32;
  fn b2b_ray_hit() -> Int32;
  fn b2b_ray_body() -> Int32;
  fn b2b_ray_point_x() -> Int32;
  fn b2b_ray_point_y() -> Int32;
  fn b2b_ray_normal_x() -> Int32;
  fn b2b_ray_normal_y() -> Int32;
  fn b2b_ray_fraction() -> Int32;
  fn b2b_overlap_circle(handle: Int32, radius_milli: Int32, px_milli: Int32, py_milli: Int32) -> Int32;
  fn b2b_overlap_box(handle: Int32, hx_milli: Int32, hy_milli: Int32, px_milli: Int32, py_milli: Int32, angle_milli: Int32) -> Int32;
  fn b2b_overlap_fetch(handle: Int32, index: Int32) -> Int32;
  fn b2b_overlap_body() -> Int32;
  fn b2b_overlap_x() -> Int32;
  fn b2b_overlap_y() -> Int32;
  fn b2b_contact_count(handle: Int32, kind: Int32) -> Int32;
  fn b2b_contact_fetch(handle: Int32, kind: Int32, index: Int32) -> Int32;
  fn b2b_contact_body_a() -> Int32;
  fn b2b_contact_body_b() -> Int32;
  fn b2b_contact_x() -> Int32;
  fn b2b_contact_y() -> Int32;
  fn b2b_contact_nx() -> Int32;
  fn b2b_contact_ny() -> Int32;
  fn b2b_contact_speed() -> Int32;
  fn b2b_joint_add(handle: Int32, kind: Int32, body_a: Int32, body_b: Int32, ax_milli: Int32, ay_milli: Int32, axis_x_milli: Int32, axis_y_milli: Int32, collide: Int32, has_motor: Int32, motor_speed_milli: Int32, max_effort_milli: Int32, length_milli: Int32) -> Int32;
  fn b2b_joint_remove(handle: Int32, joint: Int32) -> Int32;
  fn b2b_joint_count(handle: Int32) -> Int32;
  fn b2b_joint_state(handle: Int32, joint: Int32) -> Int32;
  fn b2b_joint_state_kind() -> Int32;
  fn b2b_joint_state_primary() -> Int32;
  fn b2b_joint_state_body_a() -> Int32;
  fn b2b_joint_state_body_b() -> Int32;
}

/// Default number of 60 Hz steps used by the drop probes.
pub const B2_DEFAULT_STEPS: Int = 300;

pub type B2Gravity = {
  gx_milli: Int;
  gy_milli: Int;
}

pub type B2DropResult = {
  final_y_milli: Int;
  awake: Bool;
}

pub type B2RevoluteMotor = {
  w_milli: Int;
  angle_milli: Int;
}

pub type B2PrismaticMotor = {
  translation_milli: Int;
  x_milli: Int;
  y_milli: Int;
}

/// Packed upstream version: major << 16 | minor << 8 | revision.
/// Complexity: O(1).
pub fn b2_version() -> Int
  requires: true
{
  unsafe { return b2probe_version() as Int; }
}

/// Decode a packed version into "major.minor.revision".
/// Complexity: O(1).
pub fn b2_version_str(v: Int) -> Str
  requires: v >= 0
{
  let major = v >> 16;
  let minor = (v >> 8) & 255;
  let revision = v & 255;
  return b2_i2s(major) + "." + b2_i2s(minor) + "." + b2_i2s(revision);
}

/// Default world gravity in thousandths (Box2D default: 0, -10000).
/// Complexity: O(1).
pub fn b2_gravity() -> Result[B2Gravity, Str]
  requires: true
{
  var f_gx = b2_slot();
  var f_gy = b2_slot();
  let rc = unsafe { b2probe_gravity(f_gx.as_mut_ptr(), f_gy.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("box2d: gravity probe rc=" + b2_i2s(rc));
  }
  return Ok(B2Gravity{ gx_milli: b2_slot_read(&f_gx); gy_milli: b2_slot_read(&f_gy); });
}

/// Drop a 1x1 dynamic box from `start_y_milli` onto a static ground (top
/// surface at y = 0) and step `steps` times at 60 Hz; returns the final
/// body-center y (milli) and the awake flag.
/// Complexity: O(steps).
pub fn b2_drop(start_y_milli: Int, steps: Int) -> Result[B2DropResult, Str]
  requires: start_y_milli > 0
  requires: steps > 0
{
  var f_final = b2_slot();
  var f_awake = b2_slot();
  let rc = unsafe { b2probe_drop(start_y_milli as Int32, steps as Int32, f_final.as_mut_ptr(), f_awake.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("box2d: drop probe rc=" + b2_i2s(rc));
  }
  return Ok(B2DropResult{ final_y_milli: b2_slot_read(&f_final); awake: b2_slot_read(&f_awake) != 0 });
}

/// Apply a horizontal impulse (milli N*s) to a free 1x1 dynamic box and
/// return the x velocity (milli m/s) after one step (dv = J / m).
/// Complexity: O(1).
pub fn b2_impulse(impulse_milli: Int) -> Result[Int, Str]
  requires: impulse_milli > 0
{
  var f_vx = b2_slot();
  let rc = unsafe { b2probe_impulse(impulse_milli as Int32, f_vx.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("box2d: impulse probe rc=" + b2_i2s(rc));
  }
  return Ok(b2_slot_read(&f_vx));
}

/// Revolute joint + motor: a 2.0 x 0.2 dynamic bar hinged at the origin
/// (gravity off) driven at `motor_speed_milli` rad/s; after `steps` 60 Hz
/// steps returns the bar angular velocity and the joint angle (milli).
/// Complexity: O(steps).
pub fn b2_revolute_motor(motor_speed_milli: Int, steps: Int) -> Result[B2RevoluteMotor, Str]
  requires: steps > 0
{
  var f_w = b2_slot();
  var f_a = b2_slot();
  let rc = unsafe { b2probe_revolute_motor(motor_speed_milli as Int32, steps as Int32, f_w.as_mut_ptr(), f_a.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("box2d: revolute motor probe rc=" + b2_i2s(rc));
  }
  return Ok(B2RevoluteMotor{ w_milli: b2_slot_read(&f_w); angle_milli: b2_slot_read(&f_a); });
}

/// Prismatic joint + motor: a dynamic slider on the +x axis at y = 2 under
/// default gravity, driven at `motor_speed_milli` m/s; after `steps` 60 Hz
/// steps returns the joint translation and the slider position (milli).
/// The constraint must hold y while the motor translates x.
/// Complexity: O(steps).
pub fn b2_prismatic_motor(motor_speed_milli: Int, steps: Int) -> Result[B2PrismaticMotor, Str]
  requires: steps > 0
{
  var f_t = b2_slot();
  var f_x = b2_slot();
  var f_y = b2_slot();
  let rc = unsafe { b2probe_prismatic_motor(motor_speed_milli as Int32, steps as Int32, f_t.as_mut_ptr(), f_x.as_mut_ptr(), f_y.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("box2d: prismatic motor probe rc=" + b2_i2s(rc));
  }
  return Ok(B2PrismaticMotor{ translation_milli: b2_slot_read(&f_t); x_milli: b2_slot_read(&f_x); y_milli: b2_slot_read(&f_y); });
}

// ---- caller-usable 2D-solver surface (0.4.0) ------------------------------

/// Shape kind (0.4.0): circle; `ex_milli` is the radius.
pub const B2_SHAPE_CIRCLE: Int = 0;

/// Shape kind (0.4.0): box; `ex_milli`/`ey_milli` are the half extents.
pub const B2_SHAPE_BOX: Int = 1;

/// World-side body id (0.4.0) for one-sided joints: the hidden static anchor
/// body every world owns.  Edge/chain shapes are staged (ROADMAP.md).
pub const B2_WORLD: Int = -1;

/// Contact event kind (0.4.0): a touch began this step.
pub const B2_CONTACT_BEGIN: Int = 0;

/// Contact event kind (0.4.0): a touch ended this step.
pub const B2_CONTACT_END: Int = 1;

/// Contact event kind (0.4.0): an impact faster than the world's hit
/// threshold (default 1 m/s) this step; point/normal/speed are set.
pub const B2_CONTACT_HIT: Int = 2;

/// Joint kind (0.4.0): revolute (hinge) -- rotation about the shared anchor.
pub const B2_JOINT_REVOLUTE: Int = 0;

/// Joint kind (0.4.0): prismatic (slider) -- translation along `axis_*`.
pub const B2_JOINT_PRISMATIC: Int = 1;

/// Joint kind (0.4.0): weld -- rigid relative pose at the shared anchor.
pub const B2_JOINT_WELD: Int = 2;

/// Joint kind (0.4.0): distance -- keeps the anchor-to-origin distance
/// (side A anchors at the world point, side B at its body origin).
pub const B2_JOINT_DISTANCE: Int = 3;

/// Joint kind (0.4.0): wheel -- slides along `axis_*`, free to rotate, with
/// an optional rotational motor; keeps Box2D's default linear spring.
pub const B2_JOINT_WHEEL: Int = 4;

/// Joint kind (0.4.0): motor -- drives body B to body A's pose (position and
/// angle); `max_effort_milli` bounds both the force and the torque.
pub const B2_JOINT_MOTOR: Int = 5;

/// A bridge-owned live world.  `handle` is a registry slot, never a raw
/// pointer; it stays valid until `b2_world_destroy`.  `dt_micros` is the
/// fixed step every `b2_step` applies; `capacity` is the body-slot limit
/// (1..256).
pub type B2World = {
  handle: Int;
  capacity: Int;
  dt_micros: Int;
}

/// Body creation inputs (0.4.0): shape kind, extents, pose, mass and the
/// static/dynamic choice.  Lengths/angles in milli; `mass_milli` > 0
/// overrides the density-derived mass on dynamic bodies (0 keeps Box2D's
/// density-1 default; static bodies ignore it).
pub type B2BodyDesc = {
  shape: Int;
  ex_milli: Int;
  ey_milli: Int;
  px_milli: Int;
  py_milli: Int;
  angle_milli: Int;
  mass_milli: Int;
  is_static: Bool;
}

/// Owned body state read-back (0.4.0): position, linear velocity, angle,
/// angular velocity (all milli) and the awake flag, built as fresh values
/// from bridge-owned scalars (no out-param slots).
pub type B2State = {
  px_milli: Int;
  py_milli: Int;
  vx_milli: Int;
  vy_milli: Int;
  angle_milli: Int;
  w_milli: Int;
  awake: Bool;
}

/// One closest-hit ray result (0.4.0), owned: `hit` false means no geometry
/// was found and every other field is 0.  `body_id` is a bridge body id;
/// point/normal are world-space milli; `fraction_milli` is 0..1000 along the
/// cast displacement.
pub type B2RayHit = {
  hit: Bool;
  body_id: Int;
  x_milli: Int;
  y_milli: Int;
  nx_milli: Int;
  ny_milli: Int;
  fraction_milli: Int;
}

/// One overlap entry (0.4.0), owned: the body id plus its origin position at
/// fetch time.  Entries are canonically ordered by ascending body id, so
/// repeated runs read back identical sequences.
pub type B2Overlap = {
  body_id: Int;
  x_milli: Int;
  y_milli: Int;
}

/// One contact event of the last step (0.4.0), owned.  `body_a`/`body_b` are
/// bridge body ids (-1 when that side's shape was already destroyed, e.g.
/// the removed side of an end event).  point/normal/speed are only set for
/// B2_CONTACT_HIT events; begin/end events read them as 0.
pub type B2ContactEvent = {
  body_a: Int;
  body_b: Int;
  x_milli: Int;
  y_milli: Int;
  nx_milli: Int;
  ny_milli: Int;
  speed_milli: Int;
}

/// Joint creation inputs (0.4.0).  `kind` is a B2_JOINT_* value; `body_a`/
/// `body_b` are bridge body ids or B2_WORLD (at least one side must be a
/// live dynamic body).  The anchor (ax/ay) is the shared world-space point
/// for revolute/prismatic/weld/wheel (and side A of distance); the axis
/// (axis_x/axis_y) is the world-space slider direction for prismatic/wheel
/// and must be non-zero there.  `has_motor` + `motor_speed_milli` (milli
/// rad/s for revolute/wheel, milli m/s for prismatic) and `max_effort_milli`
/// (milli N.m for revolute/wheel, milli N for prismatic, both N and N.m for
/// motor) drive the joint; `length_milli` is the distance rest length
/// (0 = the creation distance).  `collide` enables collisions between the
/// two bodies.
pub type B2JointDesc = {
  kind: Int;
  body_a: Int;
  body_b: Int;
  ax_milli: Int;
  ay_milli: Int;
  axis_x_milli: Int;
  axis_y_milli: Int;
  collide: Bool;
  has_motor: Bool;
  motor_speed_milli: Int;
  max_effort_milli: Int;
  length_milli: Int;
}

/// Owned joint state read-back (0.4.0): the kind, the body pair and the
/// primary motion value in milli (`primary_milli`: revolute angle -- Box2D
/// wraps it to [-pi, pi] -- prismatic translation, distance current length;
/// 0 for weld/wheel/motor).
pub type B2JointState = {
  kind: Int;
  primary_milli: Int;
  body_a: Int;
  body_b: Int;
}

/// Create a world with 2D gravity (milli m/s^2), a fixed step (`dt_micros`)
/// and a body capacity (1..256); returns the handle on success.
/// Deterministic: no wall clock is consulted anywhere.
/// Complexity: O(capacity).
pub fn b2_world_create(gx_milli: Int, gy_milli: Int, dt_micros: Int, capacity: Int) -> Result[B2World, Str]
  requires: dt_micros > 0
  requires: capacity > 0
  requires: capacity <= 256
{
  let rc = unsafe { b2b_world_create(gx_milli as Int32, gy_milli as Int32, dt_micros as Int32, capacity as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("world create", rc));
  }
  return Ok(B2World{ handle: rc; capacity: capacity; dt_micros: dt_micros });
}

/// Destroy the world and every body/joint in it; returns the number of
/// bodies destroyed.  The handle is stale afterwards.  Complexity: O(bodies).
pub fn b2_world_destroy(w: B2World) -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { b2b_world_destroy(w.handle as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("world destroy", rc));
  }
  return Ok(rc);
}

/// The world's configured fixed step in microseconds.
/// Complexity: O(1).
pub fn b2_world_dt_micros(w: B2World) -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { b2b_world_dt(w.handle as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("world dt", rc));
  }
  return Ok(rc);
}

/// Add a circle or box body (see `B2BodyDesc`); returns the bridge body id
/// (monotonic per world; ids are never reused, so stale ids are rejected).
/// Contact begin/end and hit events are enabled on every bridge shape.
/// Complexity: O(bodies) (capacity-checked).
pub fn b2_body_add(w: B2World, d: B2BodyDesc) -> Result[Int, Str]
  requires: d.shape == 0 || d.shape == 1
  requires: d.ex_milli > 0
  requires: d.shape != 1 || d.ey_milli > 0
{
  var static_flag: Int = 0;
  if d.is_static { static_flag = 1; }
  let rc = unsafe { b2b_body_add(w.handle as Int32, d.shape as Int32, d.ex_milli as Int32, d.ey_milli as Int32, d.px_milli as Int32, d.py_milli as Int32, d.angle_milli as Int32, d.mass_milli as Int32, static_flag as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("body add", rc));
  }
  return Ok(rc);
}

/// Remove a body by id (and every joint attached to it); returns the number
/// of bodies left.  The id is stale afterwards.  Complexity: O(bodies).
pub fn b2_body_remove(w: B2World, body: Int) -> Result[Int, Str]
  requires: body >= 0
{
  let rc = unsafe { b2b_body_remove(w.handle as Int32, body as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("body remove", rc));
  }
  return Ok(rc);
}

/// Number of live bodies in the world (bridge bodies; the hidden joint
/// anchor does not count).  Complexity: O(1).
pub fn b2_body_count(w: B2World) -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { b2b_body_count(w.handle as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("body count", rc));
  }
  return Ok(rc);
}

/// The body's mass in milli-kg (density-derived, or the caller's override).
/// Complexity: O(bodies).
pub fn b2_body_mass_milli(w: B2World, body: Int) -> Result[Int, Str]
  requires: body >= 0
{
  let rc = unsafe { b2b_body_mass(w.handle as Int32, body as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("body mass", rc));
  }
  return Ok(rc);
}

/// Advance the world by one fixed step (`dt_micros`, 4 Box2D sub-steps);
/// returns 1.  State is readable between steps.
/// Complexity: O(bodies).
pub fn b2_step(w: B2World) -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { b2b_step(w.handle as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("step", rc));
  }
  return Ok(rc);
}

/// Advance the world by `steps` fixed steps; returns the steps applied.
/// Complexity: O(steps * bodies).
pub fn b2_step_n(w: B2World, steps: Int) -> Result[Int, Str]
  requires: steps > 0
{
  let rc = unsafe { b2b_step_n(w.handle as Int32, steps as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("step n", rc));
  }
  return Ok(rc);
}

/// Read one body's state as fresh owned values (position/velocity/angle/
/// angular velocity in milli + awake).  Complexity: O(bodies).
pub fn b2_body_state(w: B2World, body: Int) -> Result[B2State, Str]
  requires: body >= 0
{
  let rc = unsafe { b2b_body_state(w.handle as Int32, body as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("body state", rc));
  }
  return Ok(B2State{
    px_milli: unsafe { b2b_state_pos_x() as Int };
    py_milli: unsafe { b2b_state_pos_y() as Int };
    vx_milli: unsafe { b2b_state_vel_x() as Int };
    vy_milli: unsafe { b2b_state_vel_y() as Int };
    angle_milli: unsafe { b2b_state_angle() as Int };
    w_milli: unsafe { b2b_state_w() as Int };
    awake: unsafe { b2b_state_awake() as Int } != 0;
  });
}

/// Closest-hit raycast: the ray starts at (ox,oy) and runs along the
/// displacement (dx,dy) (all milli); the returned fraction is relative to
/// that displacement.  Deterministic.  Complexity: O(broadphase).
pub fn b2_raycast(w: B2World, ox_milli: Int, oy_milli: Int, dx_milli: Int, dy_milli: Int) -> Result[B2RayHit, Str]
  requires: dx_milli != 0 || dy_milli != 0
{
  let rc = unsafe { b2b_raycast(w.handle as Int32, ox_milli as Int32, oy_milli as Int32, dx_milli as Int32, dy_milli as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("raycast", rc));
  }
  return Ok(B2RayHit{
    hit: unsafe { b2b_ray_hit() as Int } != 0;
    body_id: unsafe { b2b_ray_body() as Int };
    x_milli: unsafe { b2b_ray_point_x() as Int };
    y_milli: unsafe { b2b_ray_point_y() as Int };
    nx_milli: unsafe { b2b_ray_normal_x() as Int };
    ny_milli: unsafe { b2b_ray_normal_y() as Int };
    fraction_milli: unsafe { b2b_ray_fraction() as Int };
  });
}

/// Overlap a circle (center + radius, milli) with the world; returns the
/// number of hit bodies (distinct, canonically ordered by ascending body id;
/// read each with `b2_overlap`).  Complexity: O(broadphase).
pub fn b2_overlap_circle(w: B2World, radius_milli: Int, px_milli: Int, py_milli: Int) -> Result[Int, Str]
  requires: radius_milli > 0
{
  let rc = unsafe { b2b_overlap_circle(w.handle as Int32, radius_milli as Int32, px_milli as Int32, py_milli as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("overlap circle", rc));
  }
  return Ok(rc);
}

/// Overlap an oriented box (half extents + center + angle, milli) with the
/// world; returns the number of hit bodies.
/// Complexity: O(broadphase).
pub fn b2_overlap_box(w: B2World, hx_milli: Int, hy_milli: Int, px_milli: Int, py_milli: Int, angle_milli: Int) -> Result[Int, Str]
  requires: hx_milli > 0
  requires: hy_milli > 0
{
  let rc = unsafe { b2b_overlap_box(w.handle as Int32, hx_milli as Int32, hy_milli as Int32, px_milli as Int32, py_milli as Int32, angle_milli as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("overlap box", rc));
  }
  return Ok(rc);
}

/// Read one entry of the most recent overlap query on `w`; the index must be
/// in [0, count).  The position is the body's origin at fetch time.
/// Complexity: O(1).
pub fn b2_overlap(w: B2World, index: Int) -> Result[B2Overlap, Str]
  requires: index >= 0
{
  let rc = unsafe { b2b_overlap_fetch(w.handle as Int32, index as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("overlap fetch", rc));
  }
  return Ok(B2Overlap{
    body_id: unsafe { b2b_overlap_body() as Int };
    x_milli: unsafe { b2b_overlap_x() as Int };
    y_milli: unsafe { b2b_overlap_y() as Int };
  });
}

/// Number of contact events of `kind` (B2_CONTACT_BEGIN/END/HIT) produced by
/// the last step; end events caused by a removal outside a step become
/// visible after the next step (Box2D swaps/clears its end-event buffers
/// inside b2World_Step).  Events are cached and canonically ordered by
/// ascending body pair.  Complexity: O(events).
pub fn b2_contact_event_count(w: B2World, kind: Int) -> Result[Int, Str]
  requires: kind >= 0
  requires: kind <= 2
{
  let rc = unsafe { b2b_contact_count(w.handle as Int32, kind as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("contact count", rc));
  }
  return Ok(rc);
}

/// Read one contact event of `kind` from the last step (index < count).
/// point/normal/speed are only set for hit events; destroyed sides read -1.
/// Complexity: O(1).
pub fn b2_contact_event(w: B2World, kind: Int, index: Int) -> Result[B2ContactEvent, Str]
  requires: kind >= 0
  requires: kind <= 2
  requires: index >= 0
{
  let rc = unsafe { b2b_contact_fetch(w.handle as Int32, kind as Int32, index as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("contact fetch", rc));
  }
  return Ok(B2ContactEvent{
    body_a: unsafe { b2b_contact_body_a() as Int };
    body_b: unsafe { b2b_contact_body_b() as Int };
    x_milli: unsafe { b2b_contact_x() as Int };
    y_milli: unsafe { b2b_contact_y() as Int };
    nx_milli: unsafe { b2b_contact_nx() as Int };
    ny_milli: unsafe { b2b_contact_ny() as Int };
    speed_milli: unsafe { b2b_contact_speed() as Int };
  });
}

/// Create a joint between two live bodies (or a body and B2_WORLD) from one
/// typed desc (kinds revolute/prismatic/weld/distance/wheel/motor); returns
/// the bridge joint id (monotonic per world; stale ids are rejected).
/// Complexity: O(bodies).
pub fn b2_joint_add(w: B2World, d: B2JointDesc) -> Result[Int, Str]
  requires: d.kind >= 0
  requires: d.kind <= 5
{
  var collide_flag: Int = 0;
  if d.collide { collide_flag = 1; }
  var motor_flag: Int = 0;
  if d.has_motor { motor_flag = 1; }
  let rc = unsafe { b2b_joint_add(w.handle as Int32, d.kind as Int32, d.body_a as Int32, d.body_b as Int32, d.ax_milli as Int32, d.ay_milli as Int32, d.axis_x_milli as Int32, d.axis_y_milli as Int32, collide_flag as Int32, motor_flag as Int32, d.motor_speed_milli as Int32, d.max_effort_milli as Int32, d.length_milli as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("joint add", rc));
  }
  return Ok(rc);
}

/// Remove a joint by id (removing a body also removes its joints); returns
/// the number of joints left.  The id is stale afterwards.
/// Complexity: O(joints).
pub fn b2_joint_remove(w: B2World, joint: Int) -> Result[Int, Str]
  requires: joint >= 0
{
  let rc = unsafe { b2b_joint_remove(w.handle as Int32, joint as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("joint remove", rc));
  }
  return Ok(rc);
}

/// Number of live joints in the world.  Complexity: O(joints).
pub fn b2_joint_count(w: B2World) -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { b2b_joint_count(w.handle as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("joint count", rc));
  }
  return Ok(rc);
}

/// Read one joint's state as fresh owned values (kind, body pair, primary
/// motion value in milli).  Complexity: O(joints).
pub fn b2_joint_state(w: B2World, joint: Int) -> Result[B2JointState, Str]
  requires: joint >= 0
{
  let rc = unsafe { b2b_joint_state(w.handle as Int32, joint as Int32) as Int };
  if rc < 0 {
    return Err(b2_err("joint state", rc));
  }
  return Ok(B2JointState{
    kind: unsafe { b2b_joint_state_kind() as Int };
    primary_milli: unsafe { b2b_joint_state_primary() as Int };
    body_a: unsafe { b2b_joint_state_body_a() as Int };
    body_b: unsafe { b2b_joint_state_body_b() as Int };
  });
}

// ---- internals -----------------------------------------------------------

// 8-byte zeroed out-param slot owned by XIOM (no malloc/free in confined
// blocks; finding B-05).
fn b2_slot() -> Vec[UInt8]
  requires: true
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 8 {
    slot.push(0 as UInt8);
    i = i + 1;
  }
  return slot;
}

// Signed 32-bit read of the low word (the bridge writes C `int`).
fn b2_slot_read(slot: &Vec[UInt8]) -> Int
  requires: true
{
  let raw = ffi.ptr_read_u32_le(slot.as_mut_ptr());
  if raw >= 2147483648 {
    return raw - 4294967296;
  }
  return raw;
}

fn b2_i2s(n: Int) -> Str
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

// Signed decimal for error messages (bridge rc codes are negative).
fn b2_i2s_signed(n: Int) -> Str
  requires: true
{
  if n < 0 {
    return "-" + b2_i2s(0 - n);
  }
  return b2_i2s(n);
}

// Typed error message for a negative bridge return code.
fn b2_err(op: Str, rc: Int) -> Str
  requires: rc < 0
{
  return "box2d: " + op + " rc=" + b2_i2s_signed(rc);
}
