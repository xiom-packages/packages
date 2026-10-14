// xiom.jolt conformance suite -- vendored Jolt Physics v5.6.0 core.
//
// Build+run (the --c-source list rides in port.args.json; Jolt needs C++17,
// carried by the pinned compiler):
//   scripts/port.ps1 -Package xiom.jolt -TimeoutSec 600
//
// Covers the 0.2.0 scalar probes, the 0.3.0 caller-usable world/body
// surface (world lifecycle, body add/remove/count, step control, owned state
// read-back; engine contract v0 flow = world + ground + box/sphere + N fixed
// steps + read-back), the 0.4.0 per-body external force/torque input
// (apply_force/apply_torque, one-step-only semantics, angular read-back,
// unknown/removed id rejection), the 0.5.0 tiers (E1 world queries
// (raycast closest/any-hit, sphere/capsule sweeps, sphere/capsule overlaps,
// canonical order + determinism), E2 capsule bodies (settle/rotation/query
// participation) and E7 contacts + sensors (manifold reads, typed id errors,
// per-step sensor events, non-physical pass-through)), and the 0.6.0 tiers:
// E3 typed joints (fixed/hinge/slider/point to a body or the world; motors,
// limits, state read-back, typed errors, joint-driven determinism) and
// E6 convex/compound bodies (hull bodies from caller vertex buffers,
// multi-shape compounds; settle + query participation + determinism).

module jolt_conformance

use xiom.io;
use xiom.test;
use xiom.jolt;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let digit = v % 10;
    v = v / 10;
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
  if neg { return "-" + buf; }
  return buf;
}

// Every JoltBodyState field equal, bit for bit.
fn st_same(a: JoltBodyState, b: JoltBodyState) -> Bool {
  return a.px_milli == b.px_milli && a.py_milli == b.py_milli && a.pz_milli == b.pz_milli && a.rx_milli == b.rx_milli && a.ry_milli == b.ry_milli && a.rz_milli == b.rz_milli && a.rw_milli == b.rw_milli && a.vx_milli == b.vx_milli && a.vy_milli == b.vy_milli && a.vz_milli == b.vz_milli && a.wx_milli == b.wx_milli && a.wy_milli == b.wy_milli && a.wz_milli == b.wz_milli && a.awake == b.awake;
}

// Engine contract v0 flow: world (gravity -9.81 m/s^2 y, fixed 1/60 s step) +
// wide static ground box (top at y=0) + one dynamic body dropped from y=5,
// stepped 300 times, then read back.  The world is destroyed before return.
fn engine_flow(shape: Int, ex_milli: Int, ey_milli: Int, ez_milli: Int) -> Result[JoltBodyState, Str] {
  let wr = jolt_world_create(0, -9810, 0, 16666, 64);
  if !wr.is_ok { return Err("create: " + wr.error); }
  let w = wr.value;
  let gd = JoltBodyDesc{
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
  };
  let g = jolt_body_add(w, gd);
  if !g.is_ok { return Err("ground: " + g.error); }
  let bd = JoltBodyDesc{
    shape: shape;
    ex_milli: ex_milli;
    ey_milli: ey_milli;
    ez_milli: ez_milli;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 5000;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: false;
  };
  let b = jolt_body_add(w, bd);
  if !b.is_ok { return Err("body: " + b.error); }
  let s = jolt_step_n(w, 16666, 300);
  if !s.is_ok { return Err("step_n: " + s.error); }
  let st = jolt_body_state(w, b.value);
  let d = jolt_world_destroy(w);
  if !st.is_ok { return Err("state: " + st.error); }
  if !d.is_ok { return Err("destroy: " + d.error); }
  return st;
}

fn engine_check_determinism() -> Bool {
  let a = engine_flow(JOLT_SHAPE_BOX, 500, 500, 500);
  let b = engine_flow(JOLT_SHAPE_BOX, 500, 500, 500);
  if !a.is_ok || !b.is_ok { return false; }
  return st_same(a.value, b.value);
}

// A fresh static 1 m box description at the origin (one fresh value per
// call: XIOM struct values move).
fn static_box_desc() -> JoltBodyDesc {
  return JoltBodyDesc{
    shape: JOLT_SHAPE_BOX;
    ex_milli: 500;
    ey_milli: 500;
    ez_milli: 500;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 0;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: true;
  };
}

// ---- 0.5.0 helpers ---------------------------------------------------------

// Every JoltQueryHit field equal, bit for bit.
fn hit_same(a: JoltQueryHit, b: JoltQueryHit) -> Bool {
  return a.hit == b.hit && a.body_id == b.body_id && a.px_milli == b.px_milli && a.py_milli == b.py_milli && a.pz_milli == b.pz_milli && a.nx_milli == b.nx_milli && a.ny_milli == b.ny_milli && a.nz_milli == b.nz_milli && a.fraction_milli == b.fraction_milli;
}

// Every JoltContact field equal, bit for bit.
fn contact_same(a: JoltContact, b: JoltContact) -> Bool {
  return a.body_a == b.body_a && a.body_b == b.body_b && a.point_count == b.point_count && a.px_milli == b.px_milli && a.py_milli == b.py_milli && a.pz_milli == b.pz_milli && a.nx_milli == b.nx_milli && a.ny_milli == b.ny_milli && a.nz_milli == b.nz_milli && a.depth_micros == b.depth_micros;
}

type QueryFixture = {
  w: JoltWorld;
  ground: Int;
  box: Int;
}

// Zero-gravity query fixture: a wide static ground (top at y=0) plus a
// static 1 m box centered at (0,500,0) (top at y=1000), added in that order
// so the ground has the lower packed body id.
fn query_fixture() -> Result[QueryFixture, Str] {
  let wr = jolt_world_create(0, 0, 0, 16666, 16);
  if !wr.is_ok { return Err("fixture create: " + wr.error); }
  let w = wr.value;
  let gd = JoltBodyDesc{
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
  };
  let g = jolt_body_add(w, gd);
  if !g.is_ok { return Err("fixture ground: " + g.error); }
  let bd = JoltBodyDesc{
    shape: JOLT_SHAPE_BOX;
    ex_milli: 500;
    ey_milli: 500;
    ez_milli: 500;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 500;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: true;
  };
  let b = jolt_body_add(w, bd);
  if !b.is_ok { return Err("fixture box: " + b.error); }
  return Ok(QueryFixture{ w: w; ground: g.value; box: b.value; });
}

// Serialize the first `n` overlap entries (id + point) of the most recent
// overlap query, so two runs can be compared as strings.
fn overlap_seq(w: JoltWorld, n: Int) -> Str {
  var s = "";
  var i = 0;
  while i < n {
    let o = jolt_overlap(w, i);
    if o.is_ok {
      s = s + i2s(o.value.body_id) + ":" + i2s(o.value.px_milli) + ":" + i2s(o.value.py_milli) + ":" + i2s(o.value.pz_milli) + ";";
    } else {
      s = s + "err;";
    }
    i = i + 1;
  }
  return s;
}

// Capsule engine flow: the same settle scenario as `engine_flow` but with a
// dynamic capsule (radius 500, half height 500) dropped from y=5.  The world
// is destroyed before return.
fn engine_flow_capsule() -> Result[JoltBodyState, Str] {
  let wr = jolt_world_create(0, -9810, 0, 16666, 64);
  if !wr.is_ok { return Err("capsule create: " + wr.error); }
  let w = wr.value;
  let gd = JoltBodyDesc{
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
  };
  let g = jolt_body_add(w, gd);
  if !g.is_ok { return Err("capsule ground: " + g.error); }
  let bd = JoltBodyDesc{
    shape: JOLT_SHAPE_CAPSULE;
    ex_milli: 500;
    ey_milli: 500;
    ez_milli: 0;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 5000;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: false;
  };
  let b = jolt_body_add(w, bd);
  if !b.is_ok { return Err("capsule body: " + b.error); }
  let s = jolt_step_n(w, 16666, 300);
  if !s.is_ok { return Err("capsule step_n: " + s.error); }
  let st = jolt_body_state(w, b.value);
  let d = jolt_world_destroy(w);
  if !st.is_ok { return Err("capsule state: " + st.error); }
  if !d.is_ok { return Err("capsule destroy: " + d.error); }
  return st;
}

// One-step contact scenario: ground + dynamic box starting 100 mm inside it
// (center y=400, half extent 500) so the first step reports a deep contact
// manifold; returns the first cached contact (world destroyed).
fn contact_scenario() -> Result[JoltContact, Str] {
  let wr = jolt_world_create(0, -9810, 0, 16666, 16);
  if !wr.is_ok { return Err("contact create: " + wr.error); }
  let w = wr.value;
  let gd = JoltBodyDesc{
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
  };
  let g = jolt_body_add(w, gd);
  if !g.is_ok { return Err("contact ground: " + g.error); }
  let bd = JoltBodyDesc{
    shape: JOLT_SHAPE_BOX;
    ex_milli: 500;
    ey_milli: 500;
    ez_milli: 500;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 400;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: false;
  };
  let b = jolt_body_add(w, bd);
  if !b.is_ok { return Err("contact box: " + b.error); }
  let s = jolt_step(w, 16666);
  if !s.is_ok { return Err("contact step: " + s.error); }
  let c = jolt_contact(w, 0);
  let d = jolt_world_destroy(w);
  if !c.is_ok { return Err("contact read: " + c.error); }
  if !d.is_ok { return Err("contact destroy: " + d.error); }
  return c;
}

type SensorFixture = {
  w: JoltWorld;
  sensor: Int;
  sphere: Int;
}

// Sensor fixture: gravity on, a static 3 m sensor cube centered at
// (0,1000,0) (spans y -500..2500) and a dynamic radius-300 sphere at y=5000
// that free-falls through it (no ground in this world).
fn sensor_fixture() -> Result[SensorFixture, Str] {
  let wr = jolt_world_create(0, -9810, 0, 16666, 16);
  if !wr.is_ok { return Err("sensor create: " + wr.error); }
  let w = wr.value;
  let sd = JoltBodyDesc{
    shape: JOLT_SHAPE_BOX;
    ex_milli: 1500;
    ey_milli: 1500;
    ez_milli: 1500;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 1000;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: false;
  };
  let s = jolt_body_add_sensor(w, sd);
  if !s.is_ok { return Err("sensor add: " + s.error); }
  let bd = JoltBodyDesc{
    shape: JOLT_SHAPE_SPHERE;
    ex_milli: 300;
    ey_milli: 0;
    ez_milli: 0;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 5000;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: false;
  };
  let b = jolt_body_add(w, bd);
  if !b.is_ok { return Err("sensor sphere: " + b.error); }
  return Ok(SensorFixture{ w: w; sensor: s.value; sphere: b.value; });
}

// Repeated sensor scenario: step 50 frames (the sphere is inside the sensor
// volume) and return the first event.
fn sensor_first_event() -> Result[JoltSensorEvent, Str] {
  let fr = sensor_fixture();
  if !fr.is_ok { return Err("sensor det create: " + fr.error); }
  let f = fr.value;
  let s = jolt_step_n(f.w, 16666, 50);
  let e = jolt_sensor_event(f.w, 0);
  let d = jolt_world_destroy(f.w);
  if !s.is_ok { return Err("sensor det step: " + s.error); }
  if !e.is_ok { return Err("sensor det event: " + e.error); }
  if !d.is_ok { return Err("sensor det destroy: " + d.error); }
  return e;
}

// ---- 0.6.0 helpers (E3 joints, E6 convex/compound) -------------------------

// Every JoltJointState field equal, bit for bit.
fn joint_state_same(a: JoltJointState, b: JoltJointState) -> Bool {
  return a.kind == b.kind && a.primary_milli == b.primary_milli && a.impulse_milli == b.impulse_milli && a.body_a == b.body_a && a.body_b == b.body_b;
}

// A 1 m dynamic box described once for the E3 joint scenes.
fn joint_box_desc(px_milli: Int, py_milli: Int) -> JoltBodyDesc {
  return JoltBodyDesc{
    shape: JOLT_SHAPE_BOX;
    ex_milli: 500;
    ey_milli: 500;
    ez_milli: 500;
    mass_milli: 0;
    px_milli: px_milli;
    py_milli: py_milli;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: false;
  };
}

// Motorized world hinge: zero gravity, box at (0,1000,0), hinge about world
// +Z at its center, velocity motor +1 rad/s, `steps` fixed steps.  Returns
// the joint state (angle + motor impulse); the world is destroyed first.
fn hinge_motor_state(steps: Int) -> Result[JoltJointState, Str] {
  let wr = jolt_world_create(0, 0, 0, 16666, 16);
  if !wr.is_ok { return Err("hinge create: " + wr.error); }
  let w = wr.value;
  let b = jolt_body_add(w, joint_box_desc(0, 1000));
  if !b.is_ok { return Err("hinge body: " + b.error); }
  let jd = JoltJointDesc{
    kind: JOLT_JOINT_HINGE;
    body_a: JOLT_WORLD;
    body_b: b.value;
    px_milli: 0;
    py_milli: 1000;
    pz_milli: 0;
    ax_milli: 0;
    ay_milli: 0;
    az_milli: 1000;
    auto_anchor: false;
    has_limits: false;
    limits_min_milli: 0;
    limits_max_milli: 0;
    motor_frequency_milli: 0;
    motor_damping_milli: 0;
    motor_max_force_milli: 0;
    motor_max_torque_milli: 0;
  };
  let j = jolt_joint_add(w, jd);
  if !j.is_ok { return Err("hinge joint: " + j.error); }
  let m = jolt_joint_set_motor(w, j.value, JOLT_MOTOR_VELOCITY, 1000);
  if !m.is_ok { return Err("hinge motor: " + m.error); }
  let s = jolt_step_n(w, 16666, steps);
  let st = jolt_joint_state(w, j.value);
  let d = jolt_world_destroy(w);
  if !s.is_ok { return Err("hinge step: " + s.error); }
  if !st.is_ok { return Err("hinge state: " + st.error); }
  if !d.is_ok { return Err("hinge destroy: " + d.error); }
  return st;
}

// Position-motor world hinge: same scene, motor state POSITION with
// `target_milli` (milli rad), `steps` steps.  Returns the joint state.
fn hinge_position_state(steps: Int, target_milli: Int) -> Result[JoltJointState, Str] {
  let wr = jolt_world_create(0, 0, 0, 16666, 16);
  if !wr.is_ok { return Err("hinge pos create: " + wr.error); }
  let w = wr.value;
  let b = jolt_body_add(w, joint_box_desc(0, 1000));
  if !b.is_ok { return Err("hinge pos body: " + b.error); }
  let jd = JoltJointDesc{
    kind: JOLT_JOINT_HINGE;
    body_a: JOLT_WORLD;
    body_b: b.value;
    px_milli: 0;
    py_milli: 1000;
    pz_milli: 0;
    ax_milli: 0;
    ay_milli: 0;
    az_milli: 1000;
    auto_anchor: false;
    has_limits: false;
    limits_min_milli: 0;
    limits_max_milli: 0;
    motor_frequency_milli: 0;
    motor_damping_milli: 0;
    motor_max_force_milli: 0;
    motor_max_torque_milli: 0;
  };
  let j = jolt_joint_add(w, jd);
  if !j.is_ok { return Err("hinge pos joint: " + j.error); }
  let m = jolt_joint_set_motor(w, j.value, JOLT_MOTOR_POSITION, target_milli);
  if !m.is_ok { return Err("hinge pos motor: " + m.error); }
  let s = jolt_step_n(w, 16666, steps);
  let st = jolt_joint_state(w, j.value);
  let d = jolt_world_destroy(w);
  if !s.is_ok { return Err("hinge pos step: " + s.error); }
  if !st.is_ok { return Err("hinge pos state: " + st.error); }
  if !d.is_ok { return Err("hinge pos destroy: " + d.error); }
  return st;
}

// Limited world hinge: velocity motor +1 rad/s into limits [-250, +250]
// milli rad; the angle must stop at the +limit.  Returns the joint state.
fn hinge_limits_state(steps: Int) -> Result[JoltJointState, Str] {
  let wr = jolt_world_create(0, 0, 0, 16666, 16);
  if !wr.is_ok { return Err("hinge lim create: " + wr.error); }
  let w = wr.value;
  let b = jolt_body_add(w, joint_box_desc(0, 1000));
  if !b.is_ok { return Err("hinge lim body: " + b.error); }
  let jd = JoltJointDesc{
    kind: JOLT_JOINT_HINGE;
    body_a: JOLT_WORLD;
    body_b: b.value;
    px_milli: 0;
    py_milli: 1000;
    pz_milli: 0;
    ax_milli: 0;
    ay_milli: 0;
    az_milli: 1000;
    auto_anchor: false;
    has_limits: true;
    limits_min_milli: -250;
    limits_max_milli: 250;
    motor_frequency_milli: 0;
    motor_damping_milli: 0;
    motor_max_force_milli: 0;
    motor_max_torque_milli: 0;
  };
  let j = jolt_joint_add(w, jd);
  if !j.is_ok { return Err("hinge lim joint: " + j.error); }
  let m = jolt_joint_set_motor(w, j.value, JOLT_MOTOR_VELOCITY, 1000);
  if !m.is_ok { return Err("hinge lim motor: " + m.error); }
  let s = jolt_step_n(w, 16666, steps);
  let st = jolt_joint_state(w, j.value);
  let d = jolt_world_destroy(w);
  if !s.is_ok { return Err("hinge lim step: " + s.error); }
  if !st.is_ok { return Err("hinge lim state: " + st.error); }
  if !d.is_ok { return Err("hinge lim destroy: " + d.error); }
  return st;
}

// Motorized world slider: zero gravity, box at the origin, slider along
// world +X through its center, motor velocity +500 milli m/s.  `limits_min`/
// `limits_max_milli` enable limits (pass min > max to disable: only the
// `has_limits` flag decides).  Returns the joint state (position + motor
// impulse); destroyed first.
fn slider_motor_state(steps: Int, has_limits: Bool, limits_min_milli: Int, limits_max_milli: Int) -> Result[JoltJointState, Str] {
  let wr = jolt_world_create(0, 0, 0, 16666, 16);
  if !wr.is_ok { return Err("slider create: " + wr.error); }
  let w = wr.value;
  let b = jolt_body_add(w, joint_box_desc(0, 0));
  if !b.is_ok { return Err("slider body: " + b.error); }
  let jd = JoltJointDesc{
    kind: JOLT_JOINT_SLIDER;
    body_a: JOLT_WORLD;
    body_b: b.value;
    px_milli: 0;
    py_milli: 0;
    pz_milli: 0;
    ax_milli: 1000;
    ay_milli: 0;
    az_milli: 0;
    auto_anchor: false;
    has_limits: has_limits;
    limits_min_milli: limits_min_milli;
    limits_max_milli: limits_max_milli;
    motor_frequency_milli: 0;
    motor_damping_milli: 0;
    motor_max_force_milli: 0;
    motor_max_torque_milli: 0;
  };
  let j = jolt_joint_add(w, jd);
  if !j.is_ok { return Err("slider joint: " + j.error); }
  let m = jolt_joint_set_motor(w, j.value, JOLT_MOTOR_VELOCITY, 500);
  if !m.is_ok { return Err("slider motor: " + m.error); }
  let s = jolt_step_n(w, 16666, steps);
  let st = jolt_joint_state(w, j.value);
  let d = jolt_world_destroy(w);
  if !s.is_ok { return Err("slider step: " + s.error); }
  if !st.is_ok { return Err("slider state: " + st.error); }
  if !d.is_ok { return Err("slider destroy: " + d.error); }
  return st;
}

// A fixed-joint weld under gravity: static anchor box at (0,500,0), dynamic
// 1 m box at (1000,500,0), auto-anchored weld.  After 4 steps the welded box
// must not have fallen and the joint must report a non-zero reaction
// impulse.  Returns the joint state and the welded box's position.
type WeldResult = {
  kind: Int;
  impulse_milli: Int;
  body_x_milli: Int;
  body_y_milli: Int;
}

fn fixed_weld_result() -> Result[WeldResult, Str] {
  let wr = jolt_world_create(0, -9810, 0, 16666, 16);
  if !wr.is_ok { return Err("weld create: " + wr.error); }
  let w = wr.value;
  let ad = JoltBodyDesc{
    shape: JOLT_SHAPE_BOX;
    ex_milli: 500;
    ey_milli: 500;
    ez_milli: 500;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 500;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: true;
  };
  let a = jolt_body_add(w, ad);
  if !a.is_ok { return Err("weld anchor: " + a.error); }
  let b = jolt_body_add(w, joint_box_desc(1000, 500));
  if !b.is_ok { return Err("weld body: " + b.error); }
  let jd = JoltJointDesc{
    kind: JOLT_JOINT_FIXED;
    body_a: a.value;
    body_b: b.value;
    px_milli: 0;
    py_milli: 0;
    pz_milli: 0;
    ax_milli: 0;
    ay_milli: 0;
    az_milli: 0;
    auto_anchor: true;
    has_limits: false;
    limits_min_milli: 0;
    limits_max_milli: 0;
    motor_frequency_milli: 0;
    motor_damping_milli: 0;
    motor_max_force_milli: 0;
    motor_max_torque_milli: 0;
  };
  let j = jolt_joint_add(w, jd);
  if !j.is_ok { return Err("weld joint: " + j.error); }
  let s = jolt_step_n(w, 16666, 4);
  let st = jolt_joint_state(w, j.value);
  let bs = jolt_body_state(w, b.value);
  let d = jolt_world_destroy(w);
  if !s.is_ok { return Err("weld step: " + s.error); }
  if !st.is_ok { return Err("weld state: " + st.error); }
  if !bs.is_ok { return Err("weld body state: " + bs.error); }
  if !d.is_ok { return Err("weld destroy: " + d.error); }
  return Ok(WeldResult{
    kind: st.value.kind;
    impulse_milli: st.value.impulse_milli;
    body_x_milli: bs.value.px_milli;
    body_y_milli: bs.value.py_milli;
  });
}

// Point-joint (ball) world pendulum under gravity: dynamic box COM starts at
// (1000, 2000, 0), pinned to the world point (0, 2000, 0) at distance 1000.
// After 120 steps the pivot distance must hold (squared-distance reported in
// milli^2) and the body must have swung below the start height.
type PendulumResult = {
  dist_sq_milli: Int;
  py_milli: Int;
}

fn point_pendulum_result(steps: Int) -> Result[PendulumResult, Str] {
  let wr = jolt_world_create(0, -9810, 0, 16666, 16);
  if !wr.is_ok { return Err("point create: " + wr.error); }
  let w = wr.value;
  let b = jolt_body_add(w, joint_box_desc(1000, 2000));
  if !b.is_ok { return Err("point body: " + b.error); }
  let jd = JoltJointDesc{
    kind: JOLT_JOINT_POINT;
    body_a: JOLT_WORLD;
    body_b: b.value;
    px_milli: 0;
    py_milli: 2000;
    pz_milli: 0;
    ax_milli: 0;
    ay_milli: 0;
    az_milli: 0;
    auto_anchor: false;
    has_limits: false;
    limits_min_milli: 0;
    limits_max_milli: 0;
    motor_frequency_milli: 0;
    motor_damping_milli: 0;
    motor_max_force_milli: 0;
    motor_max_torque_milli: 0;
  };
  let j = jolt_joint_add(w, jd);
  if !j.is_ok { return Err("point joint: " + j.error); }
  let s = jolt_step_n(w, 16666, steps);
  let bs = jolt_body_state(w, b.value);
  let d = jolt_world_destroy(w);
  if !s.is_ok { return Err("point step: " + s.error); }
  if !bs.is_ok { return Err("point body state: " + bs.error); }
  if !d.is_ok { return Err("point destroy: " + d.error); }
  let dx = bs.value.px_milli - 0;
  let dy = bs.value.py_milli - 2000;
  return Ok(PendulumResult{
    dist_sq_milli: dx * dx + dy * dy;
    py_milli: bs.value.py_milli;
  });
}

// Push one xyz milli triple.
fn verts_push(v: &mut Vec[Int], x: Int, y: Int, z: Int) {
  v.push(x);
  v.push(y);
  v.push(z);
}

// Eight cube corners (+-s) plus one interior point, as xyz milli triples
// (proves interior points are accepted by the hull builder).
fn convex_cube_verts(s: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  verts_push(&mut v, -s, -s, -s);
  verts_push(&mut v, s, -s, -s);
  verts_push(&mut v, -s, s, -s);
  verts_push(&mut v, s, s, -s);
  verts_push(&mut v, -s, -s, s);
  verts_push(&mut v, s, -s, s);
  verts_push(&mut v, -s, s, s);
  verts_push(&mut v, s, s, s);
  verts_push(&mut v, 0, 0, 0);
  return v;
}

// Convex engine flow (0.6.0, E6): the same settle scenario as `engine_flow`
// but the dynamic body is a convex hull of the (s=500) cube corners dropped
// from y=5.  The world is destroyed before return.
fn convex_engine_flow() -> Result[JoltBodyState, Str] {
  let wr = jolt_world_create(0, -9810, 0, 16666, 64);
  if !wr.is_ok { return Err("convex create: " + wr.error); }
  let w = wr.value;
  let gd = JoltBodyDesc{
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
  };
  let g = jolt_body_add(w, gd);
  if !g.is_ok { return Err("convex ground: " + g.error); }
  var verts = convex_cube_verts(500);
  let bd = JoltBodyDesc{
    shape: JOLT_SHAPE_CONVEX;
    ex_milli: 0;
    ey_milli: 0;
    ez_milli: 0;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 5000;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: false;
  };
  let b = jolt_body_add_convex(w, bd, &verts);
  if !b.is_ok { return Err("convex body: " + b.error); }
  let s = jolt_step_n(w, 16666, 300);
  if !s.is_ok { return Err("convex step_n: " + s.error); }
  let st = jolt_body_state(w, b.value);
  let d = jolt_world_destroy(w);
  if !st.is_ok { return Err("convex state: " + st.error); }
  if !d.is_ok { return Err("convex destroy: " + d.error); }
  return st;
}

// Compound part table (0.6.0, E6): 4 parts, JOLT_PART_STRIDE entries each --
// box (+-500) at the origin, sphere (r=250) at (+750,0,0), capsule
// (r=200, half 100) laid along x (90 deg about z) at (-750,0,0), convex cube
// (half 200) on top at (0,700,0) slicing the shared 8-corner vertex buffer.
fn compound_parts() -> Vec[Int] {
  var p = Vec[Int].new();
  // part 0: box, ex/ey/ez = 500, at origin, identity.
  p.push(JOLT_SHAPE_BOX);
  p.push(500); p.push(500); p.push(500);
  p.push(0); p.push(0);
  p.push(0); p.push(0); p.push(0);
  p.push(0); p.push(0); p.push(0); p.push(0);
  // part 1: sphere, ex = 250, at (+750,0,0), identity.
  p.push(JOLT_SHAPE_SPHERE);
  p.push(250); p.push(0); p.push(0);
  p.push(0); p.push(0);
  p.push(750); p.push(0); p.push(0);
  p.push(0); p.push(0); p.push(0); p.push(0);
  // part 2: capsule, radius 200 / half height 100, at (-750,0,0), rotated
  // 90 deg about z (quat 0,0,0.707,0.707).
  p.push(JOLT_SHAPE_CAPSULE);
  p.push(200); p.push(100); p.push(0);
  p.push(0); p.push(0);
  p.push(-750); p.push(0); p.push(0);
  p.push(0); p.push(0); p.push(707); p.push(707);
  // part 3: convex cube (half 200 = vertices [0,8) of the shared buffer),
  // at (0,700,0), identity.
  p.push(JOLT_SHAPE_CONVEX);
  p.push(0); p.push(0); p.push(0);
  p.push(0); p.push(8);
  p.push(0); p.push(700); p.push(0);
  p.push(0); p.push(0); p.push(0); p.push(0);
  return p;
}

// The shared 8-corner (+-200) vertex buffer for the compound's convex part.
fn compound_verts() -> Vec[Int] {
  return convex_cube_verts(200);
}

// A fresh static compound desc at the origin (one fresh value per call: XIOM
// struct values move) for the typed-error probes.
fn compound_error_desc() -> JoltBodyDesc {
  return JoltBodyDesc{
    shape: JOLT_SHAPE_COMPOUND;
    ex_milli: 0;
    ey_milli: 0;
    ez_milli: 0;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 0;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: true;
  };
}

// Compound engine flow (0.6.0, E6): the box-part bottom (y=-500) lands on
// the ground; the body settles and sleeps like the primitive flows.  The
// world is destroyed before return.
fn compound_engine_flow() -> Result[JoltBodyState, Str] {
  let wr = jolt_world_create(0, -9810, 0, 16666, 64);
  if !wr.is_ok { return Err("compound create: " + wr.error); }
  let w = wr.value;
  let gd = JoltBodyDesc{
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
  };
  let g = jolt_body_add(w, gd);
  if !g.is_ok { return Err("compound ground: " + g.error); }
  var parts = compound_parts();
  var verts = compound_verts();
  let bd = JoltBodyDesc{
    shape: JOLT_SHAPE_COMPOUND;
    ex_milli: 0;
    ey_milli: 0;
    ez_milli: 0;
    mass_milli: 0;
    px_milli: 0;
    py_milli: 5000;
    pz_milli: 0;
    rx_milli: 0;
    ry_milli: 0;
    rz_milli: 0;
    rw_milli: 0;
    is_static: false;
  };
  let b = jolt_body_add_compound(w, bd, &parts, &verts);
  if !b.is_ok { return Err("compound body: " + b.error); }
  let s = jolt_step_n(w, 16666, 300);
  if !s.is_ok { return Err("compound step_n: " + s.error); }
  let st = jolt_body_state(w, b.value);
  let d = jolt_world_destroy(w);
  if !st.is_ok { return Err("compound state: " + st.error); }
  if !d.is_ok { return Err("compound destroy: " + d.error); }
  return st;
}

fn main() -> Int {
  io.println("=== xiom.jolt conformance tests (vendored v5.6.0) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Resting drop: 1 m box from y=5 settles on a ground (top at y=0);
  //    the center lands at ~0.5 (half extent) within tolerance.
  let d = jolt_drop();
  if d.is_ok {
    failed = failed + report(d.value.final_y_milli >= 400 && d.value.final_y_milli <= 600,
      "drop: final_y=" + i2s(d.value.final_y_milli) + " milli, awake=" + b2s(d.value.awake));
    failed = failed + report(!d.value.awake, "drop: body asleep after settling");
  } else {
    failed = failed + report(false, "drop: " + d.error);
  }

  // 2. Velocity hand-off: a free box given vx=5 m/s keeps it through a step.
  let im = jolt_impulse_vx();
  if im.is_ok {
    failed = failed + report(im.value >= 4500 && im.value <= 5500,
      "impulse: vx=" + i2s(im.value) + " milli");
  } else {
    failed = failed + report(false, "impulse: " + im.error);
  }

  // 3. Determinism: a repeated drop yields the same final y.
  let d2 = jolt_drop();
  let same = d.is_ok && d2.is_ok && d2.value.final_y_milli == d.value.final_y_milli;
  failed = failed + report(same, "determinism: repeated drop identical");

  // 4. World lifecycle: create / count / fixed dt / destroy / stale handle.
  let w1 = jolt_world_create(0, -9810, 0, 16666, 64);
  if w1.is_ok {
    let world = w1.value;
    let c0 = jolt_body_count(world);
    failed = failed + report(c0.is_ok && c0.value == 0, "world: empty at create");
    let dt = jolt_world_dt_micros(world);
    failed = failed + report(dt.is_ok && dt.value == 16666, "world: fixed dt reported (micros)");
    let del = jolt_world_destroy(world);
    failed = failed + report(del.is_ok && del.value == 0, "world: destroy empty ok");
    let del2 = jolt_world_destroy(world);
    failed = failed + report(!del2.is_ok, "world: stale handle rejected");
  } else {
    failed = failed + report(false, "world: create failed: " + w1.error);
  }

  // 5. Engine v0 flow (box): settles asleep on the static ground.
  let e1 = engine_flow(JOLT_SHAPE_BOX, 500, 500, 500);
  if e1.is_ok {
    let s1 = e1.value;
    failed = failed + report(s1.py_milli >= 400 && s1.py_milli <= 600,
      "engine: box settled y=" + i2s(s1.py_milli) + " milli");
    failed = failed + report(!s1.awake, "engine: box asleep after settling");
  } else {
    failed = failed + report(false, "engine: box flow: " + e1.error);
  }

  // 6. Engine v0 flow (sphere): settles on the static ground.
  let e2 = engine_flow(JOLT_SHAPE_SPHERE, 500, 0, 0);
  if e2.is_ok {
    let s2 = e2.value;
    failed = failed + report(s2.py_milli >= 400 && s2.py_milli <= 600,
      "engine: sphere settled y=" + i2s(s2.py_milli) + " milli");
  } else {
    failed = failed + report(false, "engine: sphere flow: " + e2.error);
  }

  // 7. Determinism: a repeated engine flow yields a bit-identical state.
  failed = failed + report(engine_check_determinism(), "engine: repeated flow bit-identical state");

  // 8. State readable between single steps (free fall, no ground).
  let w8 = jolt_world_create(0, -9810, 0, 16666, 16);
  if w8.is_ok {
    let world = w8.value;
    let fd = JoltBodyDesc{
      shape: JOLT_SHAPE_BOX;
      ex_milli: 500;
      ey_milli: 500;
      ez_milli: 500;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 10000;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: false;
    };
    let b = jolt_body_add(world, fd);
    if b.is_ok {
      let s1 = jolt_step(world, 16666);
      let r1 = jolt_body_state(world, b.value);
      let s2 = jolt_step(world, 16666);
      let r2 = jolt_body_state(world, b.value);
      if s1.is_ok && s2.is_ok && r1.is_ok && r2.is_ok {
        let y1 = r1.value.py_milli;
        let y2 = r2.value.py_milli;
        let vy1 = r1.value.vy_milli;
        failed = failed + report(y1 < 10000 && y2 < y1 && vy1 < 0,
          "steps: free fall readable between steps (y " + i2s(y1) + " -> " + i2s(y2) + " milli, vy=" + i2s(vy1) + ")");
      } else {
        failed = failed + report(false, "steps: read-back failed");
      }
    } else {
      failed = failed + report(false, "steps: add failed: " + b.error);
    }
    let d8 = jolt_world_destroy(world);
  } else {
    failed = failed + report(false, "steps: create failed: " + w8.error);
  }

  // 9. Body add/remove/count + stale ids.
  let w9 = jolt_world_create(0, -9810, 0, 16666, 16);
  if w9.is_ok {
    let world = w9.value;
    let a = jolt_body_add(world, static_box_desc());
    let b = jolt_body_add(world, static_box_desc());
    let c = jolt_body_add(world, static_box_desc());
    if a.is_ok && b.is_ok && c.is_ok {
      let n3 = jolt_body_count(world);
      failed = failed + report(n3.is_ok && n3.value == 3, "bodies: count 3 after adds");
      let aid = a.value;
      let rem = jolt_body_remove(world, aid);
      let n2 = jolt_body_count(world);
      failed = failed + report(rem.is_ok && rem.value == 2 && n2.is_ok && n2.value == 2, "bodies: count 2 after remove");
      let st = jolt_body_state(world, aid);
      failed = failed + report(!st.is_ok, "bodies: removed id rejected by state read");
      let rem2 = jolt_body_remove(world, aid);
      failed = failed + report(!rem2.is_ok, "bodies: double remove rejected");
    } else {
      failed = failed + report(false, "bodies: adds failed");
    }
    let d9 = jolt_world_destroy(world);
  } else {
    failed = failed + report(false, "bodies: create failed: " + w9.error);
  }

  // 10. Rotation input round-trips (static box rotated 45 deg about z:
  //     (0, 0, 0.383, 0.924) in milli; the bridge normalizes).
  let w10 = jolt_world_create(0, 0, 0, 16666, 4);
  if w10.is_ok {
    let world = w10.value;
    let rd = JoltBodyDesc{
      shape: JOLT_SHAPE_BOX;
      ex_milli: 500;
      ey_milli: 500;
      ez_milli: 500;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 0;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 383;
      rw_milli: 924;
      is_static: true;
    };
    let b = jolt_body_add(world, rd);
    if b.is_ok {
      let st = jolt_body_state(world, b.value);
      if st.is_ok {
        let rz = st.value.rz_milli;
        let rw = st.value.rw_milli;
        failed = failed + report(rz >= 378 && rz <= 388 && rw >= 919 && rw <= 929, "rotation: 45deg z round-trip");
      } else {
        failed = failed + report(false, "rotation: state read: " + st.error);
      }
    } else {
      failed = failed + report(false, "rotation: add: " + b.error);
    }
    let d10 = jolt_world_destroy(world);
  } else {
    failed = failed + report(false, "rotation: create failed: " + w10.error);
  }

  // 11. External force/torque input (0.4.0): apply_force / apply_torque on a
  //     zero-gravity world.  The input applies to the next step only (Jolt
  //     clears accumulated force/torque after every Update) and wakes the
  //     body.  60 N on a 1 kg box (mass_milli override) for dt=1/60 s gives
  //     dv=1 m/s; 6 N.m about z gives dw = (6 / (1/6)) * 1/60 = 0.6 rad/s.
  let w11 = jolt_world_create(0, 0, 0, 16666, 8);
  if w11.is_ok {
    let world = w11.value;
    let fd = JoltBodyDesc{
      shape: JOLT_SHAPE_BOX;
      ex_milli: 500;
      ey_milli: 500;
      ez_milli: 500;
      mass_milli: 1000;
      px_milli: 0;
      py_milli: 0;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: false;
    };
    let b = jolt_body_add(world, fd);
    if b.is_ok {
      let bid = b.value;
      let af = jolt_body_apply_force(world, bid, 60000, 0, 0);
      let s1 = jolt_step(world, 16666);
      let st1 = jolt_body_state(world, bid);
      if af.is_ok && s1.is_ok && st1.is_ok {
        failed = failed + report(st1.value.vx_milli >= 900 && st1.value.vx_milli <= 1100 && st1.value.px_milli > 0,
          "force: 60 N on 1 kg accelerated vx to " + i2s(st1.value.vx_milli) + " milli (px=" + i2s(st1.value.px_milli) + ")");
      } else {
        failed = failed + report(false, "force: apply/step/state failed");
      }
      let s2 = jolt_step(world, 16666);
      let st2 = jolt_body_state(world, bid);
      if s2.is_ok && st2.is_ok {
        failed = failed + report(st2.value.vx_milli >= 900 && st2.value.vx_milli <= 1100,
          "force: cleared after one step (vx held at " + i2s(st2.value.vx_milli) + " milli, no re-acceleration)");
      } else {
        failed = failed + report(false, "force: second step read-back failed");
      }
      let at = jolt_body_apply_torque(world, bid, 0, 0, 6000);
      let s3 = jolt_step(world, 16666);
      let st3 = jolt_body_state(world, bid);
      if at.is_ok && s3.is_ok && st3.is_ok {
        failed = failed + report(st3.value.wz_milli >= 500 && st3.value.wz_milli <= 700 && st3.value.rz_milli != 0,
          "torque: 6 N.m about z changed angular state (wz=" + i2s(st3.value.wz_milli) + " milli, rz=" + i2s(st3.value.rz_milli) + ")");
      } else {
        failed = failed + report(false, "torque: apply/step/state failed");
      }
      let unk = jolt_body_apply_force(world, 99999999, 1000, 0, 0);
      failed = failed + report(!unk.is_ok, "force: unknown id rejected");
      let rem = jolt_body_remove(world, bid);
      let rf = jolt_body_apply_force(world, bid, 1000, 0, 0);
      let rt = jolt_body_apply_torque(world, bid, 0, 0, 1000);
      failed = failed + report(rem.is_ok && !rf.is_ok, "force: removed id rejected");
      failed = failed + report(!rt.is_ok, "torque: removed id rejected");
    } else {
      failed = failed + report(false, "force: add failed: " + b.error);
    }
    let d11 = jolt_world_destroy(world);
  } else {
    failed = failed + report(false, "force: create failed: " + w11.error);
  }

  // 12. Queries (0.5.0, E1): raycast closest/any on the query fixture
  //     (ground top y=0, static 1 m box centered at (0,500,0), top y=1000).
  let qf = query_fixture();
  if qf.is_ok {
    let f = qf.value;

    // Closest hit: a 3 m downward ray from y=2000 hits the box top.
    let r1 = jolt_raycast(f.w, 0, 2000, 0, 0, -3000, 0);
    if r1.is_ok {
      let h = r1.value;
      failed = failed + report(h.hit && h.body_id == f.box && h.py_milli >= 950 && h.py_milli <= 1050,
        "raycast: closest body=box y=" + i2s(h.py_milli) + " milli");
      failed = failed + report(h.ny_milli >= 900 && h.fraction_milli >= 325 && h.fraction_milli <= 341,
        "raycast: normal up (ny=" + i2s(h.ny_milli) + ") fraction=" + i2s(h.fraction_milli) + " milli");
    } else {
      failed = failed + report(false, "raycast: " + r1.error);
      failed = failed + report(false, "raycast: " + r1.error);
    }

    // Past the box (x=1500) the same ray hits the ground at fraction ~666.
    let r2 = jolt_raycast(f.w, 1500, 2000, 0, 0, -3000, 0);
    if r2.is_ok {
      failed = failed + report(r2.value.hit && r2.value.body_id == f.ground && r2.value.py_milli >= -50 && r2.value.py_milli <= 50 && r2.value.fraction_milli >= 650 && r2.value.fraction_milli <= 683,
        "raycast: ground behind box (body=" + i2s(r2.value.body_id) + " y=" + i2s(r2.value.py_milli) + " fraction=" + i2s(r2.value.fraction_milli) + ")");
    } else {
      failed = failed + report(false, "raycast: ground cast: " + r2.error);
    }

    // An upward ray misses everything.
    let r3 = jolt_raycast(f.w, 0, 2000, 0, 0, 3000, 0);
    failed = failed + report(r3.is_ok && !r3.value.hit, "raycast: upward ray misses (hit flag false)");

    // Any-hit: first traversal hit is a fixture body (not necessarily box).
    let r4 = jolt_raycast_any(f.w, 0, 2000, 0, 0, -3000, 0);
    failed = failed + report(r4.is_ok && r4.value.hit && (r4.value.body_id == f.box || r4.value.body_id == f.ground),
      "raycast: any-hit finds geometry (body=" + i2s(r4.value.body_id) + ")");

    // Determinism: the same ray in a second fresh world is bit-identical.
    let qf2 = query_fixture();
    if qf2.is_ok {
      let r5 = jolt_raycast(f.w, 0, 2000, 0, 0, -3000, 0);
      let r6 = jolt_raycast(qf2.value.w, 0, 2000, 0, 0, -3000, 0);
      failed = failed + report(r5.is_ok && r6.is_ok && hit_same(r5.value, r6.value), "raycast: bit-identical hit across fresh worlds");
      let dq2 = jolt_world_destroy(qf2.value.w);
    } else {
      failed = failed + report(false, "raycast: second fixture: " + qf2.error);
    }

    // Sphere sweep (r=500) from y=3000 contacts the box top at fraction ~500.
    let s1 = jolt_sweep_sphere(f.w, 500, 0, 3000, 0, 0, -3000, 0);
    if s1.is_ok {
      let h = s1.value;
      failed = failed + report(h.hit && h.body_id == f.box && h.py_milli >= 950 && h.py_milli <= 1050 && h.fraction_milli >= 490 && h.fraction_milli <= 510,
        "sweep: sphere closest body=box y=" + i2s(h.py_milli) + " fraction=" + i2s(h.fraction_milli) + " milli");
    } else {
      failed = failed + report(false, "sweep: sphere: " + s1.error);
    }
    let s2 = jolt_sweep_sphere(f.w, 500, 0, 3000, 0, 0, 3000, 0);
    failed = failed + report(s2.is_ok && !s2.value.hit, "sweep: sphere upward misses");

    // Capsule sweep (r=500, half height 500) from y=3500 contacts at ~500.
    let s3 = jolt_sweep_capsule(f.w, 500, 500, 0, 3500, 0, 0, 0, 0, 0, 0, -3000, 0);
    if s3.is_ok {
      let h = s3.value;
      failed = failed + report(h.hit && h.body_id == f.box && h.py_milli >= 950 && h.py_milli <= 1050 && h.fraction_milli >= 490 && h.fraction_milli <= 510,
        "sweep: capsule closest body=box y=" + i2s(h.py_milli) + " fraction=" + i2s(h.fraction_milli) + " milli");
    } else {
      failed = failed + report(false, "sweep: capsule: " + s3.error);
    }
    let s4 = jolt_sweep_capsule(f.w, 500, 500, 0, 3500, 0, 0, 0, 0, 0, 0, 3000, 0);
    failed = failed + report(s4.is_ok && !s4.value.hit, "sweep: capsule upward misses");

    // Overlap: a radius-800 sphere at (0,500,0) overlaps both the box and
    // the ground; the list is canonical (ascending body id: ground, box).
    let o1 = jolt_overlap_sphere(f.w, 800, 0, 500, 0);
    if o1.is_ok {
      failed = failed + report(o1.value == 2, "overlap: sphere finds " + i2s(o1.value) + " bodies (ground+box)");
      let e0 = jolt_overlap(f.w, 0);
      let e1 = jolt_overlap(f.w, 1);
      failed = failed + report(e0.is_ok && e1.is_ok && e0.value.body_id == f.ground && e1.value.body_id == f.box && f.ground < f.box,
        "overlap: canonical ascending order (ground, box)");
      failed = failed + report(e1.is_ok && e1.value.py_milli >= 0 && e1.value.py_milli <= 1100 && e1.value.px_milli >= -600 && e1.value.px_milli <= 600,
        "overlap: entry point on box surface (y=" + i2s(e1.value.py_milli) + " milli)");
      let seq_a = overlap_seq(f.w, 2);
      let o2 = jolt_overlap_sphere(f.w, 800, 0, 5000, 0);
      failed = failed + report(o2.is_ok && o2.value == 0, "overlap: empty region returns 0");
      // A vertical capsule (r=300, half 700) at y=1900 spans 900..2900:
      // overlapping the box (top 1000) but not the ground.
      let o3 = jolt_overlap_capsule(f.w, 300, 700, 0, 1900, 0, 0, 0, 0, 0);
      if o3.is_ok {
        let c0 = jolt_overlap(f.w, 0);
        failed = failed + report(o3.value == 1 && c0.is_ok && c0.value.body_id == f.box, "overlap: capsule finds box only");
      } else {
        failed = failed + report(false, "overlap: capsule: " + o3.error);
      }
      // Determinism: the same overlap query in a fresh world yields the
      // identical canonical sequence (ids + points).
      let qf3 = query_fixture();
      if qf3.is_ok {
        let ofresh = jolt_overlap_sphere(qf3.value.w, 800, 0, 500, 0);
        let seq_b = overlap_seq(qf3.value.w, 2);
        failed = failed + report(ofresh.is_ok && seq_b == seq_a && seq_a != "", "overlap: stable canonical order across fresh worlds");
        let dq3 = jolt_world_destroy(qf3.value.w);
      } else {
        failed = failed + report(false, "overlap: third fixture: " + qf3.error);
      }
    } else {
      failed = failed + report(false, "overlap: sphere: " + o1.error);
      failed = failed + report(false, "overlap: sphere: " + o1.error);
      failed = failed + report(false, "overlap: sphere: " + o1.error);
      failed = failed + report(false, "overlap: empty: " + o1.error);
      failed = failed + report(false, "overlap: capsule: " + o1.error);
      failed = failed + report(false, "overlap: determinism: " + o1.error);
    }
    let dqf = jolt_world_destroy(f.w);
  } else {
    failed = failed + report(false, "queries: fixture failed: " + qf.error);
  }

  // 13. Capsule shape (0.5.0, E2): a (r=500, half height 500) capsule
  //     settles on the ground like the box/sphere flows (center ~979).
  let cap = engine_flow_capsule();
  if cap.is_ok {
    let s = cap.value;
    failed = failed + report(s.py_milli >= 850 && s.py_milli <= 1100, "capsule: settled y=" + i2s(s.py_milli) + " milli");
    failed = failed + report(!s.awake, "capsule: asleep after settling");
  } else {
    failed = failed + report(false, "capsule: flow: " + cap.error);
    failed = failed + report(false, "capsule: flow: " + cap.error);
  }

  // Capsule rotation input round-trips (static capsule rotated 90 deg about
  // z: (0, 0, 0.707, 0.707) in milli).
  let w13 = jolt_world_create(0, 0, 0, 16666, 8);
  if w13.is_ok {
    let world = w13.value;
    let rd = JoltBodyDesc{
      shape: JOLT_SHAPE_CAPSULE;
      ex_milli: 500;
      ey_milli: 500;
      ez_milli: 0;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 0;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 707;
      rw_milli: 707;
      is_static: true;
    };
    let b = jolt_body_add(world, rd);
    if b.is_ok {
      let st = jolt_body_state(world, b.value);
      if st.is_ok {
        failed = failed + report(st.value.rz_milli >= 700 && st.value.rz_milli <= 714 && st.value.rw_milli >= 700 && st.value.rw_milli <= 714,
          "capsule: 90deg z rotation round-trip (rz=" + i2s(st.value.rz_milli) + ")");
      } else {
        failed = failed + report(false, "capsule: state read: " + st.error);
      }
    } else {
      failed = failed + report(false, "capsule: add: " + b.error);
    }
    let d13 = jolt_world_destroy(world);
  } else {
    failed = failed + report(false, "capsule: create failed: " + w13.error);
  }

  // 14. Contacts (0.5.0, E7): the first step of a 100 mm-penetrating drop
  //     reports the contact manifold (pair, normal, depth, points).
  let w14 = jolt_world_create(0, -9810, 0, 16666, 16);
  if w14.is_ok {
    let world = w14.value;
    let gd14 = JoltBodyDesc{
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
    };
    let g14 = jolt_body_add(world, gd14);
    let bd14 = JoltBodyDesc{
      shape: JOLT_SHAPE_BOX;
      ex_milli: 500;
      ey_milli: 500;
      ez_milli: 500;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 400;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: false;
    };
    let b14 = jolt_body_add(world, bd14);
    if g14.is_ok && b14.is_ok {
      let s14 = jolt_step(world, 16666);
      let cc = jolt_contact_count(world);
      if s14.is_ok && cc.is_ok && cc.value >= 1 {
        failed = failed + report(true, "contacts: " + i2s(cc.value) + " manifold(s) after the landing step");
        let ct = jolt_contact(world, 0);
        if ct.is_ok {
          let c = ct.value;
          failed = failed + report((c.body_a == g14.value && c.body_b == b14.value) || (c.body_a == b14.value && c.body_b == g14.value),
            "contacts: pair is ground+box");
          failed = failed + report(c.ny_milli >= 900, "contacts: normal points up (ny=" + i2s(c.ny_milli) + " milli)");
          failed = failed + report(c.depth_micros >= 20000, "contacts: deep penetration depth=" + i2s(c.depth_micros) + " micros");
          failed = failed + report(c.point_count >= 1 && c.py_milli >= -200 && c.py_milli <= 200,
            "contacts: point on contact surface (py=" + i2s(c.py_milli) + ", n=" + i2s(c.point_count) + ")");
          let p1 = jolt_contact_point(world, 0, 0);
          failed = failed + report(p1.is_ok && p1.value.y_milli >= -200 && p1.value.y_milli <= 200, "contacts: point accessor matches manifold");
          let pbad = jolt_contact_point(world, 0, 64);
          failed = failed + report(!pbad.is_ok, "contacts: point index out of range rejected");
        } else {
          failed = failed + report(false, "contacts: read: " + ct.error);
          failed = failed + report(false, "contacts: read: " + ct.error);
          failed = failed + report(false, "contacts: read: " + ct.error);
          failed = failed + report(false, "contacts: read: " + ct.error);
          failed = failed + report(false, "contacts: read: " + ct.error);
          failed = failed + report(false, "contacts: read: " + ct.error);
        }
        let pc = jolt_contact_pair_count(world, g14.value, b14.value);
        let pc2 = jolt_contact_pair_count(world, b14.value, g14.value);
        failed = failed + report(pc.is_ok && pc.value >= 1 && pc2.is_ok && pc2.value == pc.value, "contacts: pair count order-insensitive");
      } else {
        failed = failed + report(false, "contacts: no manifold after the landing step");
        failed = failed + report(false, "contacts: manifold read skipped");
        failed = failed + report(false, "contacts: normal check skipped");
        failed = failed + report(false, "contacts: depth check skipped");
        failed = failed + report(false, "contacts: point check skipped");
        failed = failed + report(false, "contacts: point accessor skipped");
        failed = failed + report(false, "contacts: point range skipped");
        failed = failed + report(false, "contacts: pair count skipped");
      }
      let unk14 = jolt_contact_pair_count(world, g14.value, 99999999);
      failed = failed + report(!unk14.is_ok, "contacts: unknown id rejected by pair count");
      let oob = jolt_contact(world, 100000);
      failed = failed + report(!oob.is_ok, "contacts: out-of-range index rejected");
      let rem14 = jolt_body_remove(world, b14.value);
      let rc14 = jolt_contact_pair_count(world, g14.value, b14.value);
      failed = failed + report(rem14.is_ok && !rc14.is_ok, "contacts: removed id rejected by pair count");
    } else {
      failed = failed + report(false, "contacts: fixture add failed");
    }
    let d14 = jolt_world_destroy(world);
  } else {
    failed = failed + report(false, "contacts: create failed: " + w14.error);
  }

  // Contacts go empty once the bodies sleep (Jolt reports contacts for
  // active bodies only; sleeping bodies receive OnContactRemoved).
  let w15 = jolt_world_create(0, -9810, 0, 16666, 16);
  if w15.is_ok {
    let world = w15.value;
    let gd15 = JoltBodyDesc{
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
    };
    let g15 = jolt_body_add(world, gd15);
    let bd15 = JoltBodyDesc{
      shape: JOLT_SHAPE_BOX;
      ex_milli: 500;
      ey_milli: 500;
      ez_milli: 500;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 600;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: false;
    };
    let b15 = jolt_body_add(world, bd15);
    if g15.is_ok && b15.is_ok {
      let s15 = jolt_step_n(world, 16666, 300);
      let st15 = jolt_body_state(world, b15.value);
      let cc15 = jolt_contact_count(world);
      failed = failed + report(s15.is_ok && st15.is_ok && !st15.value.awake && cc15.is_ok && cc15.value == 0,
        "contacts: empty once asleep (count=" + i2s(cc15.value) + ", awake=" + b2s(st15.value.awake) + ")");
    } else {
      failed = failed + report(false, "contacts: sleep fixture add failed");
    }
    let d15 = jolt_world_destroy(world);
  } else {
    failed = failed + report(false, "contacts: sleep create failed: " + w15.error);
  }

  // Determinism: the one-step contact scenario repeated is bit-identical.
  let c1 = contact_scenario();
  let c2 = contact_scenario();
  var csame = false;
  if c1.is_ok && c2.is_ok {
    csame = contact_same(c1.value, c2.value);
  }
  failed = failed + report(csame, "contacts: repeated scenario bit-identical");

  // 15. Sensors (0.5.0, E7): a non-physical volume reports overlaps while a
  //     sphere falls through it (50 frames => y~1526, inside the volume).
  let sf = sensor_fixture();
  if sf.is_ok {
    let f = sf.value;
    let n0 = jolt_body_count(f.w);
    failed = failed + report(n0.is_ok && n0.value == 2, "sensor: counted as a body");
    let s50 = jolt_step_n(f.w, 16666, 50);
    let ec = jolt_sensor_event_count(f.w);
    failed = failed + report(s50.is_ok && ec.is_ok && ec.value >= 1, "sensor: overlap event while sphere passes through");
    let ev = jolt_sensor_event(f.w, 0);
    failed = failed + report(ev.is_ok && ev.value.sensor_id == f.sensor && ev.value.other_id == f.sphere, "sensor: event pair (sensor, sphere)");
    let oc = jolt_sensor_overlap_count(f.w, f.sensor);
    failed = failed + report(oc.is_ok && ec.is_ok && oc.value == ec.value, "sensor: overlap count matches events");
    let notsensor = jolt_sensor_overlap_count(f.w, f.sphere);
    failed = failed + report(!notsensor.is_ok, "sensor: live non-sensor id rejected");
    let unk15 = jolt_sensor_overlap_count(f.w, 99999999);
    failed = failed + report(!unk15.is_ok, "sensor: unknown id rejected");
    // Non-physical: keep stepping; the sphere must fall straight through.
    let s80 = jolt_step_n(f.w, 16666, 30);
    let st80 = jolt_body_state(f.w, f.sphere);
    failed = failed + report(s80.is_ok && st80.is_ok && st80.value.py_milli < -3000,
      "sensor: sphere passes through (py=" + i2s(st80.value.py_milli) + " milli)");
    let ec2 = jolt_sensor_event_count(f.w);
    failed = failed + report(ec2.is_ok && ec2.value == 0, "sensor: events cleared after exit (last step only)");
    let rem15 = jolt_body_remove(f.w, f.sensor);
    let after15 = jolt_body_count(f.w);
    failed = failed + report(rem15.is_ok && after15.is_ok && after15.value == 1, "sensor: removable like a body");
    let gone15 = jolt_sensor_overlap_count(f.w, f.sensor);
    failed = failed + report(!gone15.is_ok, "sensor: removed id rejected");
    let dsf = jolt_world_destroy(f.w);
  } else {
    failed = failed + report(false, "sensor: fixture failed: " + sf.error);
  }

  // Determinism: the repeated sensor scenario reports the identical first
  // event.
  let se1 = sensor_first_event();
  let se2 = sensor_first_event();
  failed = failed + report(se1.is_ok && se2.is_ok && se1.value.sensor_id == se2.value.sensor_id && se1.value.other_id == se2.value.other_id,
    "sensor: repeated scenario identical first event");

  // 16. Typed joints (0.6.0, E3): motorized world hinges, sliders, limits,
  //     welds, pendulums and the typed error surface.

  // Motorized world hinge (zero gravity): velocity motor +1 rad/s for 60
  // fixed steps ramps the relative angle to ~1 rad (1000 milli).
  let h1 = hinge_motor_state(60);
  if h1.is_ok {
    failed = failed + report(h1.value.kind == JOLT_JOINT_HINGE && h1.value.primary_milli >= 850 && h1.value.primary_milli <= 1050,
      "joints: motorized hinge angle=" + i2s(h1.value.primary_milli) + " milli after 60 steps");
  } else {
    failed = failed + report(false, "joints: hinge motor flow: " + h1.error);
  }

  // Joint-driven determinism: the repeated motorized-hinge flow is
  // bit-identical (angle, impulse and pair).
  let h2 = hinge_motor_state(60);
  var h2msg = "joints: repeated motorized hinge bit-identical";
  if h2.is_ok { h2msg = h2msg + " (angle=" + i2s(h2.value.primary_milli) + " milli)"; }
  failed = failed + report(h1.is_ok && h2.is_ok && joint_state_same(h1.value, h2.value), h2msg);

  // Position motor: drive the hinge to +700 milli rad; 120 steps converge
  // near the target angle.
  let hp = hinge_position_state(120, 700);
  if hp.is_ok {
    failed = failed + report(hp.value.primary_milli >= 450 && hp.value.primary_milli <= 800,
      "joints: position motor drove hinge to " + i2s(hp.value.primary_milli) + " milli (target 700)");
  } else {
    failed = failed + report(false, "joints: hinge position flow: " + hp.error);
  }

  // Limits: a +1 rad/s velocity motor into [-250, +250] milli rad stops at
  // the upper limit instead of passing it.
  let hl = hinge_limits_state(120);
  if hl.is_ok {
    failed = failed + report(hl.value.primary_milli >= 150 && hl.value.primary_milli <= 320,
      "joints: hinge limit clamped angle=" + i2s(hl.value.primary_milli) + " milli (limit 250)");
  } else {
    failed = failed + report(false, "joints: hinge limits flow: " + hl.error);
  }

  // Motorized world slider (zero gravity): +500 milli m/s along +X for 60
  // steps slides the body to ~500 milli.
  let sl1 = slider_motor_state(60, false, 0, 0);
  if sl1.is_ok {
    failed = failed + report(sl1.value.kind == JOLT_JOINT_SLIDER && sl1.value.primary_milli >= 300 && sl1.value.primary_milli <= 600,
      "joints: motorized slider position=" + i2s(sl1.value.primary_milli) + " milli after 60 steps");
  } else {
    failed = failed + report(false, "joints: slider motor flow: " + sl1.error);
  }

  // Slider limits: +500 milli m/s into [-1000, +200] clamps at +200.
  let sl2 = slider_motor_state(120, true, -1000, 200);
  if sl2.is_ok {
    failed = failed + report(sl2.value.primary_milli >= 150 && sl2.value.primary_milli <= 260,
      "joints: slider limit clamped position=" + i2s(sl2.value.primary_milli) + " milli (limit 200)");
  } else {
    failed = failed + report(false, "joints: slider limits flow: " + sl2.error);
  }

  // Two-body fixed weld under gravity: the welded box neither falls nor
  // drifts, and the joint reports a non-zero reaction impulse.
  let wl = fixed_weld_result();
  if wl.is_ok {
    failed = failed + report(wl.value.kind == JOLT_JOINT_FIXED && wl.value.body_y_milli >= 470 && wl.value.body_y_milli <= 530 && wl.value.body_x_milli >= 970 && wl.value.body_x_milli <= 1030,
      "joints: fixed weld held body at (" + i2s(wl.value.body_x_milli) + "," + i2s(wl.value.body_y_milli) + ") milli");
    failed = failed + report(wl.value.impulse_milli > 0,
      "joints: fixed weld reaction impulse=" + i2s(wl.value.impulse_milli) + " milli");
  } else {
    failed = failed + report(false, "joints: fixed weld flow: " + wl.error);
    failed = failed + report(false, "joints: fixed weld flow: " + wl.error);
  }

  // Point joint: the pivot distance holds through a gravity swing.
  let pd = point_pendulum_result(120);
  if pd.is_ok {
    failed = failed + report(pd.value.dist_sq_milli >= 810000 && pd.value.dist_sq_milli <= 1210000,
      "joints: point pivot distance holds (d^2=" + i2s(pd.value.dist_sq_milli) + " milli^2)");
    failed = failed + report(pd.value.py_milli < 1900,
      "joints: point pendulum swung (y=" + i2s(pd.value.py_milli) + " milli)");
  } else {
    failed = failed + report(false, "joints: point pendulum flow: " + pd.error);
    failed = failed + report(false, "joints: point pendulum flow: " + pd.error);
  }

  // Typed joint errors: bad ids, unsupported combos, degenerate axes and
  // stale handles after remove/body-removal.
  let jw = jolt_world_create(0, 0, 0, 16666, 8);
  if jw.is_ok {
    let w = jw.value;
    let jb = jolt_body_add(w, joint_box_desc(0, 0));
    if jb.is_ok {
      let bid = jb.value;

      let e1 = jolt_joint_add(w, JoltJointDesc{
        kind: JOLT_JOINT_HINGE; body_a: JOLT_WORLD; body_b: 99999999;
        px_milli: 0; py_milli: 0; pz_milli: 0;
        ax_milli: 0; ay_milli: 0; az_milli: 1000;
        auto_anchor: false; has_limits: false;
        limits_min_milli: 0; limits_max_milli: 0;
        motor_frequency_milli: 0; motor_damping_milli: 0;
        motor_max_force_milli: 0; motor_max_torque_milli: 0;
      });
      failed = failed + report(!e1.is_ok, "joints: unknown body id rejected");

      let e2 = jolt_joint_add(w, JoltJointDesc{
        kind: JOLT_JOINT_HINGE; body_a: bid; body_b: bid;
        px_milli: 0; py_milli: 0; pz_milli: 0;
        ax_milli: 0; ay_milli: 0; az_milli: 1000;
        auto_anchor: false; has_limits: false;
        limits_min_milli: 0; limits_max_milli: 0;
        motor_frequency_milli: 0; motor_damping_milli: 0;
        motor_max_force_milli: 0; motor_max_torque_milli: 0;
      });
      failed = failed + report(!e2.is_ok, "joints: same body both sides rejected");

      let e3 = jolt_joint_add(w, JoltJointDesc{
        kind: JOLT_JOINT_HINGE; body_a: JOLT_WORLD; body_b: JOLT_WORLD;
        px_milli: 0; py_milli: 0; pz_milli: 0;
        ax_milli: 0; ay_milli: 0; az_milli: 1000;
        auto_anchor: false; has_limits: false;
        limits_min_milli: 0; limits_max_milli: 0;
        motor_frequency_milli: 0; motor_damping_milli: 0;
        motor_max_force_milli: 0; motor_max_torque_milli: 0;
      });
      failed = failed + report(!e3.is_ok, "joints: world-world rejected");

      let e4 = jolt_joint_add(w, JoltJointDesc{
        kind: JOLT_JOINT_HINGE; body_a: JOLT_WORLD; body_b: bid;
        px_milli: 0; py_milli: 0; pz_milli: 0;
        ax_milli: 0; ay_milli: 0; az_milli: 0;
        auto_anchor: false; has_limits: false;
        limits_min_milli: 0; limits_max_milli: 0;
        motor_frequency_milli: 0; motor_damping_milli: 0;
        motor_max_force_milli: 0; motor_max_torque_milli: 0;
      });
      failed = failed + report(!e4.is_ok, "joints: degenerate hinge axis rejected");

      let e5 = jolt_joint_add(w, JoltJointDesc{
        kind: JOLT_JOINT_FIXED; body_a: JOLT_WORLD; body_b: bid;
        px_milli: 0; py_milli: 0; pz_milli: 0;
        ax_milli: 0; ay_milli: 0; az_milli: 0;
        auto_anchor: true; has_limits: false;
        limits_min_milli: 0; limits_max_milli: 0;
        motor_frequency_milli: 1000; motor_damping_milli: 0;
        motor_max_force_milli: 0; motor_max_torque_milli: 0;
      });
      failed = failed + report(!e5.is_ok, "joints: motor config on fixed rejected");

      let e6 = jolt_joint_add(w, JoltJointDesc{
        kind: JOLT_JOINT_POINT; body_a: JOLT_WORLD; body_b: bid;
        px_milli: 0; py_milli: 0; pz_milli: 0;
        ax_milli: 0; ay_milli: 0; az_milli: 0;
        auto_anchor: false; has_limits: true;
        limits_min_milli: -100; limits_max_milli: 100;
        motor_frequency_milli: 0; motor_damping_milli: 0;
        motor_max_force_milli: 0; motor_max_torque_milli: 0;
      });
      failed = failed + report(!e6.is_ok, "joints: limits on point rejected");

      let e7 = jolt_joint_add(w, JoltJointDesc{
        kind: JOLT_JOINT_HINGE; body_a: JOLT_WORLD; body_b: bid;
        px_milli: 0; py_milli: 0; pz_milli: 0;
        ax_milli: 0; ay_milli: 0; az_milli: 1000;
        auto_anchor: false; has_limits: true;
        limits_min_milli: 100; limits_max_milli: 200;
        motor_frequency_milli: 0; motor_damping_milli: 0;
        motor_max_force_milli: 0; motor_max_torque_milli: 0;
      });
      failed = failed + report(!e7.is_ok, "joints: out-of-range hinge limits rejected");

      let e8 = jolt_joint_state(w, 12345);
      failed = failed + report(!e8.is_ok, "joints: unknown joint id rejected by state");
      let e9 = jolt_joint_remove(w, 12345);
      failed = failed + report(!e9.is_ok, "joints: unknown joint id rejected by remove");

      // A valid hinge: add, count, remove, stale-state.
      let hj = jolt_joint_add(w, JoltJointDesc{
        kind: JOLT_JOINT_HINGE; body_a: JOLT_WORLD; body_b: bid;
        px_milli: 0; py_milli: 0; pz_milli: 0;
        ax_milli: 0; ay_milli: 0; az_milli: 1000;
        auto_anchor: false; has_limits: false;
        limits_min_milli: 0; limits_max_milli: 0;
        motor_frequency_milli: 0; motor_damping_milli: 0;
        motor_max_force_milli: 0; motor_max_torque_milli: 0;
      });
      if hj.is_ok {
        let jc1 = jolt_joint_count(w);
        failed = failed + report(jc1.is_ok && jc1.value == 1, "joints: count 1 after one add");
        let jr = jolt_joint_remove(w, hj.value);
        failed = failed + report(jr.is_ok && jr.value == 0, "joints: remove returns joints left (0)");
        let sg = jolt_joint_state(w, hj.value);
        failed = failed + report(!sg.is_ok, "joints: removed joint id rejected by state");
      } else {
        failed = failed + report(false, "joints: valid hinge add: " + hj.error);
        failed = failed + report(false, "joints: valid hinge add: " + hj.error);
        failed = failed + report(false, "joints: valid hinge add: " + hj.error);
      }

      // A valid fixed weld: motor op rejected; removing the body removes it.
      let fj = jolt_joint_add(w, JoltJointDesc{
        kind: JOLT_JOINT_FIXED; body_a: JOLT_WORLD; body_b: bid;
        px_milli: 0; py_milli: 0; pz_milli: 0;
        ax_milli: 0; ay_milli: 0; az_milli: 0;
        auto_anchor: true; has_limits: false;
        limits_min_milli: 0; limits_max_milli: 0;
        motor_frequency_milli: 0; motor_damping_milli: 0;
        motor_max_force_milli: 0; motor_max_torque_milli: 0;
      });
      if fj.is_ok {
        let sm = jolt_joint_set_motor(w, fj.value, JOLT_MOTOR_VELOCITY, 1000);
        failed = failed + report(!sm.is_ok, "joints: motor op on fixed rejected");
        let rem = jolt_body_remove(w, bid);
        let jc2 = jolt_joint_count(w);
        failed = failed + report(rem.is_ok && jc2.is_ok && jc2.value == 0, "joints: removing a body removes its joints");
        let sg2 = jolt_joint_state(w, fj.value);
        failed = failed + report(!sg2.is_ok, "joints: joint state rejects after body removal");
      } else {
        failed = failed + report(false, "joints: fixed add: " + fj.error);
        failed = failed + report(false, "joints: fixed add: " + fj.error);
        failed = failed + report(false, "joints: fixed add: " + fj.error);
      }
    } else {
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
      failed = failed + report(false, "joints: error fixture body: " + jb.error);
    }
    let djw = jolt_world_destroy(w);
  } else {
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
    failed = failed + report(false, "joints: error world create: " + jw.error);
  }

  // 17. Convex hull bodies (0.6.0, E6): settle flow, determinism and E1
  //     query participation.
  let cx1 = convex_engine_flow();
  if cx1.is_ok {
    failed = failed + report(cx1.value.py_milli >= 400 && cx1.value.py_milli <= 600,
      "convex: settled y=" + i2s(cx1.value.py_milli) + " milli");
    failed = failed + report(!cx1.value.awake, "convex: asleep after settling");
  } else {
    failed = failed + report(false, "convex: flow: " + cx1.error);
    failed = failed + report(false, "convex: flow: " + cx1.error);
  }
  let cx2 = convex_engine_flow();
  failed = failed + report(cx1.is_ok && cx2.is_ok && st_same(cx1.value, cx2.value), "convex: repeated flow bit-identical");

  let cq = jolt_world_create(0, 0, 0, 16666, 8);
  if cq.is_ok {
    let w = cq.value;
    var cverts = convex_cube_verts(500);
    let cd = JoltBodyDesc{
      shape: JOLT_SHAPE_CONVEX;
      ex_milli: 0;
      ey_milli: 0;
      ez_milli: 0;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 500;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: true;
    };
    let cb = jolt_body_add_convex(w, cd, &cverts);
    if cb.is_ok {
      let ray = jolt_raycast(w, 0, 2000, 0, 0, -3000, 0);
      var rmsg = "convex: raycast hits the hull top";
      if ray.is_ok { rmsg = rmsg + " y=" + i2s(ray.value.py_milli) + " milli"; }
      failed = failed + report(ray.is_ok && ray.value.hit && ray.value.body_id == cb.value && ray.value.py_milli >= 950 && ray.value.py_milli <= 1050, rmsg);
      let ov = jolt_overlap_sphere(w, 800, 0, 500, 0);
      if ov.is_ok {
        let oe = jolt_overlap(w, 0);
        failed = failed + report(ov.value == 1 && oe.is_ok && oe.value.body_id == cb.value, "convex: overlap finds the hull");
      } else {
        failed = failed + report(false, "convex: overlap: " + ov.error);
      }
    } else {
      failed = failed + report(false, "convex: query add: " + cb.error);
      failed = failed + report(false, "convex: query add: " + cb.error);
    }
    let dcq = jolt_world_destroy(w);
  } else {
    failed = failed + report(false, "convex: query create: " + cq.error);
    failed = failed + report(false, "convex: query create: " + cq.error);
  }

  // 18. Compound bodies (0.6.0, E6): settle flow, determinism, per-part E1
  //     queries and a landing contact.
  let cp1 = compound_engine_flow();
  if cp1.is_ok {
    failed = failed + report(cp1.value.py_milli >= 300 && cp1.value.py_milli <= 700,
      "compound: settled y=" + i2s(cp1.value.py_milli) + " milli");
    failed = failed + report(!cp1.value.awake, "compound: asleep after settling");
  } else {
    failed = failed + report(false, "compound: flow: " + cp1.error);
    failed = failed + report(false, "compound: flow: " + cp1.error);
  }
  let cp2 = compound_engine_flow();
  failed = failed + report(cp1.is_ok && cp2.is_ok && st_same(cp1.value, cp2.value), "compound: repeated flow bit-identical");

  let oq = jolt_world_create(0, 0, 0, 16666, 8);
  if oq.is_ok {
    let w = oq.value;
    var qparts = compound_parts();
    var qverts = compound_verts();
    let cd = JoltBodyDesc{
      shape: JOLT_SHAPE_COMPOUND;
      ex_milli: 0;
      ey_milli: 0;
      ez_milli: 0;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 500;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: true;
    };
    let cb = jolt_body_add_compound(w, cd, &qparts, &qverts);
    if cb.is_ok {
      let r1 = jolt_raycast(w, 0, 3000, 0, 0, -3000, 0);
      var m1 = "compound: raycast hits the convex part";
      if r1.is_ok { m1 = m1 + " y=" + i2s(r1.value.py_milli); }
      failed = failed + report(r1.is_ok && r1.value.hit && r1.value.body_id == cb.value && r1.value.py_milli >= 1370 && r1.value.py_milli <= 1430, m1);
      let r2 = jolt_raycast(w, 750, 3000, 0, 0, -3000, 0);
      var m2 = "compound: raycast hits the sphere part";
      if r2.is_ok { m2 = m2 + " y=" + i2s(r2.value.py_milli); }
      failed = failed + report(r2.is_ok && r2.value.hit && r2.value.body_id == cb.value && r2.value.py_milli >= 720 && r2.value.py_milli <= 780, m2);
      let ov = jolt_overlap_sphere(w, 700, 0, 500, 0);
      failed = failed + report(ov.is_ok && ov.value >= 1, "compound: overlap finds the compound");
    } else {
      failed = failed + report(false, "compound: query add: " + cb.error);
      failed = failed + report(false, "compound: query add: " + cb.error);
      failed = failed + report(false, "compound: query add: " + cb.error);
    }
    let doq = jolt_world_destroy(w);
  } else {
    failed = failed + report(false, "compound: query create: " + oq.error);
    failed = failed + report(false, "compound: query create: " + oq.error);
    failed = failed + report(false, "compound: query create: " + oq.error);
  }

  // Compound landing contact: the first step of a 100 mm-penetrating drop
  // reports a manifold between the ground and the compound.
  let lw = jolt_world_create(0, -9810, 0, 16666, 16);
  if lw.is_ok {
    let w = lw.value;
    let gd = JoltBodyDesc{
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
    };
    let g = jolt_body_add(w, gd);
    var lparts = compound_parts();
    var lverts = compound_verts();
    let bd = JoltBodyDesc{
      shape: JOLT_SHAPE_COMPOUND;
      ex_milli: 0;
      ey_milli: 0;
      ez_milli: 0;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 400;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: false;
    };
    let cb = jolt_body_add_compound(w, bd, &lparts, &lverts);
    if g.is_ok && cb.is_ok {
      let s = jolt_step(w, 16666);
      let cc = jolt_contact_count(w);
      let pc = jolt_contact_pair_count(w, g.value, cb.value);
      failed = failed + report(s.is_ok && cc.is_ok && cc.value >= 1 && pc.is_ok && pc.value >= 1,
        "compound: landing step reports a contact manifold (count=" + i2s(cc.value) + ")");
    } else {
      failed = failed + report(false, "compound: landing fixture add failed");
    }
    let dlw = jolt_world_destroy(w);
  } else {
    failed = failed + report(false, "compound: landing create failed: " + lw.error);
  }

  // Typed convex/compound errors: bad hull vertex counts, bad part tables.
  let ew = jolt_world_create(0, 0, 0, 16666, 4);
  if ew.is_ok {
    let w = ew.value;

    // Convex hull with only 3 vertices (below the hull minimum).
    var tiny = Vec[Int].new();
    verts_push(&mut tiny, -500, -500, -500);
    verts_push(&mut tiny, 500, -500, -500);
    verts_push(&mut tiny, 0, 500, 0);
    let cd = JoltBodyDesc{
      shape: JOLT_SHAPE_CONVEX;
      ex_milli: 0;
      ey_milli: 0;
      ez_milli: 0;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 0;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: true;
    };
    let x1 = jolt_body_add_convex(w, cd, &tiny);
    failed = failed + report(!x1.is_ok, "convex: too-few vertices rejected");

    // Compound with an unknown part kind (9).
    var empty = Vec[Int].new();
    var badk = Vec[Int].new();
    badk.push(9);
    badk.push(0); badk.push(0); badk.push(0);
    badk.push(0); badk.push(0);
    badk.push(0); badk.push(0); badk.push(0);
    badk.push(0); badk.push(0); badk.push(0); badk.push(0);
    let x2 = jolt_body_add_compound(w, compound_error_desc(), &badk, &empty);
    failed = failed + report(!x2.is_ok, "compound: unknown part kind rejected");

    // Convex part slicing vertices that do not exist.
    var v8 = compound_verts();
    var badv = Vec[Int].new();
    badv.push(JOLT_SHAPE_CONVEX);
    badv.push(0); badv.push(0); badv.push(0);
    badv.push(0); badv.push(99);
    badv.push(0); badv.push(0); badv.push(0);
    badv.push(0); badv.push(0); badv.push(0); badv.push(0);
    let x3 = jolt_body_add_compound(w, compound_error_desc(), &badv, &v8);
    failed = failed + report(!x3.is_ok, "compound: out-of-range convex vertex slice rejected");

    // Empty part table.
    let x4 = jolt_body_add_compound(w, compound_error_desc(), &empty, &empty);
    failed = failed + report(!x4.is_ok, "compound: empty parts rejected");

    // Part table with the wrong stride.
    var bads = Vec[Int].new();
    var bi = 0;
    while bi < 12 {
      bads.push(0);
      bi = bi + 1;
    }
    let x5 = jolt_body_add_compound(w, compound_error_desc(), &bads, &empty);
    failed = failed + report(!x5.is_ok, "compound: wrong part-table stride rejected");

    let dew = jolt_world_destroy(w);
  } else {
    failed = failed + report(false, "convex/compound errors: create failed: " + ew.error);
    failed = failed + report(false, "convex/compound errors: create failed: " + ew.error);
    failed = failed + report(false, "convex/compound errors: create failed: " + ew.error);
    failed = failed + report(false, "convex/compound errors: create failed: " + ew.error);
    failed = failed + report(false, "convex/compound errors: create failed: " + ew.error);
  }

  if failed == 0 {
    io.println("xiom.jolt: all tests passed");
  } else {
    io.println("xiom.jolt: tests failed");
  }
  return failed;
}
