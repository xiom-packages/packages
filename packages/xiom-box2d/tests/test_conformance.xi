// xiom.box2d conformance suite -- vendored Box2D v3.1.1 (C API).
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.box2d

module box2d_conformance

use xiom.io;
use xiom.test;
use xiom.box2d;

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

// ---- 0.4.0 helpers ---------------------------------------------------------

fn near(v: Int, target: Int, tol: Int) -> Bool {
  let d = v - target;
  if d < 0 {
    return (0 - d) <= tol;
  }
  return d <= tol;
}

fn pair01(a: Int, b: Int) -> Bool {
  return (a == 0 && b == 1) || (a == 1 && b == 0);
}

// Fresh body/joint descs: XIOM struct values move, so every call returns a
// new value (and the same desc can be reused across steps/loops).

fn box_desc(ex: Int, ey: Int, px: Int, py: Int, angle: Int, mass: Int, is_static: Bool) -> B2BodyDesc {
  return B2BodyDesc{
    shape: B2_SHAPE_BOX;
    ex_milli: ex;
    ey_milli: ey;
    px_milli: px;
    py_milli: py;
    angle_milli: angle;
    mass_milli: mass;
    is_static: is_static;
  };
}

fn circle_desc(r: Int, px: Int, py: Int, mass: Int, is_static: Bool) -> B2BodyDesc {
  return B2BodyDesc{
    shape: B2_SHAPE_CIRCLE;
    ex_milli: r;
    ey_milli: 0;
    px_milli: px;
    py_milli: py;
    angle_milli: 0;
    mass_milli: mass;
    is_static: is_static;
  };
}

fn joint_desc(kind: Int, a: Int, b: Int, ax: Int, ay: Int, axx: Int, axy: Int, has_motor: Bool, speed: Int, effort: Int, length: Int) -> B2JointDesc {
  return B2JointDesc{
    kind: kind;
    body_a: a;
    body_b: b;
    ax_milli: ax;
    ay_milli: ay;
    axis_x_milli: axx;
    axis_y_milli: axy;
    collide: false;
    has_motor: has_motor;
    motor_speed_milli: speed;
    max_effort_milli: effort;
    length_milli: length;
  };
}

fn weld_desc(a: Int, b: Int, ax: Int, ay: Int) -> B2JointDesc {
  return joint_desc(B2_JOINT_WELD, a, b, ax, ay, 0, 0, false, 0, 0, 0);
}

fn distance_desc(a: Int, b: Int, ax: Int, ay: Int, length: Int) -> B2JointDesc {
  return joint_desc(B2_JOINT_DISTANCE, a, b, ax, ay, 0, 0, false, 0, 0, length);
}

fn revolute_desc(a: Int, b: Int, ax: Int, ay: Int, speed: Int, torque: Int) -> B2JointDesc {
  return joint_desc(B2_JOINT_REVOLUTE, a, b, ax, ay, 0, 0, true, speed, torque, 0);
}

fn prismatic_desc(a: Int, b: Int, ax: Int, ay: Int, axx: Int, axy: Int, speed: Int, force: Int) -> B2JointDesc {
  return joint_desc(B2_JOINT_PRISMATIC, a, b, ax, ay, axx, axy, true, speed, force, 0);
}

fn wheel_desc(a: Int, b: Int, ax: Int, ay: Int, axx: Int, axy: Int, speed: Int, torque: Int) -> B2JointDesc {
  return joint_desc(B2_JOINT_WHEEL, a, b, ax, ay, axx, axy, true, speed, torque, 0);
}

fn motor_desc(a: Int, b: Int, effort: Int) -> B2JointDesc {
  return joint_desc(B2_JOINT_MOTOR, a, b, 0, 0, 0, 0, false, 0, effort, 0);
}

// Joint scenario read-back: kind/primary/pair from the joint, motion from
// body B.
pub type JointProbe = {
  kind: Int;
  primary_milli: Int;
  w_milli: Int;
  x_milli: Int;
  y_milli: Int;
  angle_milli: Int;
  body_a: Int;
  body_b: Int;
}

fn joint_probe(w: B2World, body: Int, joint: Int) -> Result[JointProbe, Str] {
  let s = b2_body_state(w, body);
  if !s.is_ok { return Err("probe state: " + s.error); }
  let js = b2_joint_state(w, joint);
  if !js.is_ok { return Err("probe joint state: " + js.error); }
  return Ok(JointProbe{
    kind: js.value.kind;
    primary_milli: js.value.primary_milli;
    w_milli: s.value.w_milli;
    x_milli: s.value.px_milli;
    y_milli: s.value.py_milli;
    angle_milli: s.value.angle_milli;
    body_a: js.value.body_a;
    body_b: js.value.body_b;
  });
}

// Weld: static world anchor + dynamic box welded at (0, 2); gravity must not
// move the box.  World destroyed before return.
fn weld_probe() -> Result[JointProbe, Str] {
  let wr = b2_world_create(0, -10000, 16667, 16);
  if !wr.is_ok { return Err("weld create: " + wr.error); }
  let w = wr.value;
  let b = b2_body_add(w, box_desc(500, 500, 0, 2000, 0, 0, false));
  if !b.is_ok { return Err("weld body: " + b.error); }
  let j = b2_joint_add(w, weld_desc(B2_WORLD, b.value, 0, 2000));
  if !j.is_ok { return Err("weld joint: " + j.error); }
  let st = b2_step_n(w, 60);
  if !st.is_ok { return Err("weld step: " + st.error); }
  let p = joint_probe(w, b.value, j.value);
  let jc = b2_joint_count(w);
  if !jc.is_ok { return Err("weld count: " + jc.error); }
  if jc.value != 1 { return Err("weld joint count != 1"); }
  let dd = b2_world_destroy(w);
  if !dd.is_ok { return Err("weld destroy: " + dd.error); }
  return p;
}

// Distance: world anchor at the origin + dynamic box at (2, 0); gravity makes
// it swing while the constraint holds the radius at 2 m.  World destroyed.
fn distance_probe() -> Result[JointProbe, Str] {
  let wr = b2_world_create(0, -10000, 16667, 16);
  if !wr.is_ok { return Err("distance create: " + wr.error); }
  let w = wr.value;
  let b = b2_body_add(w, box_desc(500, 500, 2000, 0, 0, 0, false));
  if !b.is_ok { return Err("distance body: " + b.error); }
  let j = b2_joint_add(w, distance_desc(B2_WORLD, b.value, 0, 0, 0));
  if !j.is_ok { return Err("distance joint: " + j.error); }
  let st = b2_step_n(w, 60);
  if !st.is_ok { return Err("distance step: " + st.error); }
  let p = joint_probe(w, b.value, j.value);
  let dd = b2_world_destroy(w);
  if !dd.is_ok { return Err("distance destroy: " + dd.error); }
  return p;
}

// Wheel: gravity-off bar on a world-anchored wheel joint driven at 2 rad/s.
fn wheel_probe() -> Result[JointProbe, Str] {
  let wr = b2_world_create(0, 0, 16667, 16);
  if !wr.is_ok { return Err("wheel create: " + wr.error); }
  let w = wr.value;
  let b = b2_body_add(w, box_desc(1000, 100, 0, 0, 0, 0, false));
  if !b.is_ok { return Err("wheel body: " + b.error); }
  let j = b2_joint_add(w, wheel_desc(B2_WORLD, b.value, 0, 0, 1000, 0, 2000, 1000));
  if !j.is_ok { return Err("wheel joint: " + j.error); }
  let st = b2_step_n(w, 120);
  if !st.is_ok { return Err("wheel step: " + st.error); }
  let p = joint_probe(w, b.value, j.value);
  let dd = b2_world_destroy(w);
  if !dd.is_ok { return Err("wheel destroy: " + dd.error); }
  return p;
}

// Motor: static hub + dynamic box created at 1 rad, driven back to the hub's
// pose by the motor joint (gravity off).  World destroyed before return.
fn motor_probe() -> Result[JointProbe, Str] {
  let wr = b2_world_create(0, 0, 16667, 16);
  if !wr.is_ok { return Err("motor create: " + wr.error); }
  let w = wr.value;
  let a = b2_body_add(w, box_desc(500, 500, 0, 0, 0, 0, true));
  if !a.is_ok { return Err("motor hub: " + a.error); }
  let b = b2_body_add(w, box_desc(500, 500, 0, 0, 1000, 0, false));
  if !b.is_ok { return Err("motor body: " + b.error); }
  let j = b2_joint_add(w, motor_desc(a.value, b.value, 1000000));
  if !j.is_ok { return Err("motor joint: " + j.error); }
  let st = b2_step_n(w, 120);
  if !st.is_ok { return Err("motor step: " + st.error); }
  let p = joint_probe(w, b.value, j.value);
  let dd = b2_world_destroy(w);
  if !dd.is_ok { return Err("motor destroy: " + dd.error); }
  return p;
}

// Revolute through the generic desc (gravity-off rotor at 2 rad/s): mirrors
// the 0.3.0 fixed-scenario probe through the caller surface.
fn revolute_desc_probe() -> Result[JointProbe, Str] {
  let wr = b2_world_create(0, 0, 16667, 16);
  if !wr.is_ok { return Err("revolute create: " + wr.error); }
  let w = wr.value;
  let b = b2_body_add(w, box_desc(1000, 100, 0, 0, 0, 0, false));
  if !b.is_ok { return Err("revolute body: " + b.error); }
  let j = b2_joint_add(w, revolute_desc(B2_WORLD, b.value, 0, 0, 2000, 1000000));
  if !j.is_ok { return Err("revolute joint: " + j.error); }
  let st = b2_step_n(w, 120);
  if !st.is_ok { return Err("revolute step: " + st.error); }
  let p = joint_probe(w, b.value, j.value);
  let dd = b2_world_destroy(w);
  if !dd.is_ok { return Err("revolute destroy: " + dd.error); }
  return p;
}

// Prismatic through the generic desc: gravity-held slider driven +x at 1 m/s.
fn prismatic_desc_probe() -> Result[JointProbe, Str] {
  let wr = b2_world_create(0, -10000, 16667, 16);
  if !wr.is_ok { return Err("prismatic create: " + wr.error); }
  let w = wr.value;
  let b = b2_body_add(w, box_desc(250, 250, 0, 2000, 0, 0, false));
  if !b.is_ok { return Err("prismatic body: " + b.error); }
  let j = b2_joint_add(w, prismatic_desc(B2_WORLD, b.value, 0, 2000, 1000, 0, 1000, 1000000));
  if !j.is_ok { return Err("prismatic joint: " + j.error); }
  let st = b2_step_n(w, 120);
  if !st.is_ok { return Err("prismatic step: " + st.error); }
  let p = joint_probe(w, b.value, j.value);
  let dd = b2_world_destroy(w);
  if !dd.is_ok { return Err("prismatic destroy: " + dd.error); }
  return p;
}

// Free fall: gravity (0,-10) for 60 fixed steps; the box started at y=10.
fn freefall_probe() -> Result[B2State, Str] {
  let wr = b2_world_create(0, -10000, 16667, 8);
  if !wr.is_ok { return Err("freefall create: " + wr.error); }
  let w = wr.value;
  let b = b2_body_add(w, box_desc(500, 500, 0, 10000, 0, 0, false));
  if !b.is_ok { return Err("freefall body: " + b.error); }
  let st = b2_step_n(w, 60);
  if !st.is_ok { return Err("freefall step: " + st.error); }
  let s = b2_body_state(w, b.value);
  let dd = b2_world_destroy(w);
  return s;
}

// Static body under gravity: must not move.
fn static_probe() -> Result[B2State, Str] {
  let wr = b2_world_create(0, -10000, 16667, 8);
  if !wr.is_ok { return Err("static create: " + wr.error); }
  let w = wr.value;
  let b = b2_body_add(w, box_desc(500, 500, 0, 5000, 0, 0, true));
  if !b.is_ok { return Err("static body: " + b.error); }
  let st = b2_step_n(w, 60);
  if !st.is_ok { return Err("static step: " + st.error); }
  let s = b2_body_state(w, b.value);
  let dd = b2_world_destroy(w);
  return s;
}

// Body removal: the second body is removed and must be rejected afterwards;
// returns the remaining count.
fn remove_probe() -> Result[Int, Str] {
  let wr = b2_world_create(0, -10000, 16667, 8);
  if !wr.is_ok { return Err("remove create: " + wr.error); }
  let w = wr.value;
  let g = b2_body_add(w, box_desc(10000, 500, 0, -500, 0, 0, true));
  if !g.is_ok { return Err("remove ground: " + g.error); }
  let b = b2_body_add(w, circle_desc(500, 0, 2000, 0, false));
  if !b.is_ok { return Err("remove body: " + b.error); }
  let rm = b2_body_remove(w, b.value);
  if !rm.is_ok { return Err("remove: " + rm.error); }
  let s = b2_body_state(w, b.value);
  if s.is_ok { return Err("removed body still readable"); }
  let dd = b2_world_destroy(w);
  if !dd.is_ok { return Err("remove destroy: " + dd.error); }
  return rm;
}

// Query fixture + results: static ground (id 0, top y=0) and a static 1 m box
// at (0, 2) (id 1); three rays and four shape overlaps.  World destroyed.
pub type QueryProbe = {
  r1_hit: Bool;
  r1_body: Int;
  r1_frac: Int;
  r1_ny: Int;
  r2_hit: Bool;
  r2_body: Int;
  r2_frac: Int;
  r3_hit: Bool;
  oc1: Int;
  oc1_body: Int;
  oc1_x: Int;
  oc1_y: Int;
  oc2: Int;
  oc2_body: Int;
  oc3: Int;
  ob1: Int;
  ob1_body: Int;
}

fn query_probe() -> Result[QueryProbe, Str] {
  let wr = b2_world_create(0, 0, 16667, 16);
  if !wr.is_ok { return Err("query create: " + wr.error); }
  let w = wr.value;
  let g = b2_body_add(w, box_desc(10000, 500, 0, -500, 0, 0, true));
  if !g.is_ok { return Err("query ground: " + g.error); }
  let b = b2_body_add(w, box_desc(500, 500, 0, 2000, 0, 0, true));
  if !b.is_ok { return Err("query box: " + b.error); }

  let ray1 = b2_raycast(w, 0, 10000, 0, -20000);
  if !ray1.is_ok { return Err("query ray1: " + ray1.error); }
  let ray2 = b2_raycast(w, 5000, 10000, 0, -20000);
  if !ray2.is_ok { return Err("query ray2: " + ray2.error); }
  let ray3 = b2_raycast(w, 50000, 10000, 0, -20000);
  if !ray3.is_ok { return Err("query ray3: " + ray3.error); }

  let oc1 = b2_overlap_circle(w, 1000, 0, 2000);
  if !oc1.is_ok { return Err("query oc1: " + oc1.error); }
  var oc1_body: Int = -1;
  var oc1_x: Int = 0;
  var oc1_y: Int = 0;
  if oc1.value == 1 {
    let e = b2_overlap(w, 0);
    if !e.is_ok { return Err("query oc1 entry: " + e.error); }
    oc1_body = e.value.body_id;
    oc1_x = e.value.x_milli;
    oc1_y = e.value.y_milli;
  }
  let oc2 = b2_overlap_circle(w, 400, 0, 0);
  if !oc2.is_ok { return Err("query oc2: " + oc2.error); }
  var oc2_body: Int = -1;
  if oc2.value == 1 {
    let e = b2_overlap(w, 0);
    if !e.is_ok { return Err("query oc2 entry: " + e.error); }
    oc2_body = e.value.body_id;
  }
  let oc3 = b2_overlap_circle(w, 100, 0, 8000);
  if !oc3.is_ok { return Err("query oc3: " + oc3.error); }
  let ob1 = b2_overlap_box(w, 100, 100, 0, 2000, 0);
  if !ob1.is_ok { return Err("query ob1: " + ob1.error); }
  var ob1_body: Int = -1;
  if ob1.value == 1 {
    let e = b2_overlap(w, 0);
    if !e.is_ok { return Err("query ob1 entry: " + e.error); }
    ob1_body = e.value.body_id;
  }

  let dd = b2_world_destroy(w);
  if !dd.is_ok { return Err("query destroy: " + dd.error); }
  return Ok(QueryProbe{
    r1_hit: ray1.value.hit;
    r1_body: ray1.value.body_id;
    r1_frac: ray1.value.fraction_milli;
    r1_ny: ray1.value.ny_milli;
    r2_hit: ray2.value.hit;
    r2_body: ray2.value.body_id;
    r2_frac: ray2.value.fraction_milli;
    r3_hit: ray3.value.hit;
    oc1: oc1.value;
    oc1_body: oc1_body;
    oc1_x: oc1_x;
    oc1_y: oc1_y;
    oc2: oc2.value;
    oc2_body: oc2_body;
    oc3: oc3.value;
    ob1: ob1.value;
    ob1_body: ob1_body;
  });
}

// Contact scenario: a dynamic circle dropped onto a wide static ground; the
// step that starts the touch is found by polling begin events, then the hit
// event of that same step is read, then the circle is removed to generate an
// end event.  World destroyed before return.
pub type ContactProbe = {
  steps_to_touch: Int;
  begin_a: Int;
  begin_b: Int;
  hit_count: Int;
  hit_a: Int;
  hit_b: Int;
  hit_x: Int;
  hit_y: Int;
  hit_nx: Int;
  hit_ny: Int;
  hit_speed: Int;
  end_count: Int;
  end_a: Int;
  end_b: Int;
}

fn contact_probe() -> Result[ContactProbe, Str] {
  let wr = b2_world_create(0, -10000, 16667, 16);
  if !wr.is_ok { return Err("contact create: " + wr.error); }
  let w = wr.value;
  let g = b2_body_add(w, box_desc(10000, 500, 0, -500, 0, 0, true));
  if !g.is_ok { return Err("contact ground: " + g.error); }
  let c = b2_body_add(w, circle_desc(500, 0, 3000, 0, false));
  if !c.is_ok { return Err("contact circle: " + c.error); }

  var found: Int = -1;
  var i: Int = 0;
  while i < 300 {
    let st = b2_step(w);
    if !st.is_ok { return Err("contact step: " + st.error); }
    let nb = b2_contact_event_count(w, B2_CONTACT_BEGIN);
    if !nb.is_ok { return Err("contact count: " + nb.error); }
    if nb.value > 0 {
      found = i;
      break;
    }
    i = i + 1;
  }
  if found < 0 { return Err("contact never began"); }

  let be = b2_contact_event(w, B2_CONTACT_BEGIN, 0);
  if !be.is_ok { return Err("begin event: " + be.error); }
  let nh = b2_contact_event_count(w, B2_CONTACT_HIT);
  if !nh.is_ok { return Err("hit count: " + nh.error); }

  var ha: Int = -2;
  var hb: Int = -2;
  var hx: Int = 0;
  var hy: Int = 0;
  var hnx: Int = 0;
  var hny: Int = 0;
  var hs: Int = 0;
  if nh.value > 0 {
    let he = b2_contact_event(w, B2_CONTACT_HIT, 0);
    if !he.is_ok { return Err("hit event: " + he.error); }
    ha = he.value.body_a;
    hb = he.value.body_b;
    hx = he.value.x_milli;
    hy = he.value.y_milli;
    hnx = he.value.nx_milli;
    hny = he.value.ny_milli;
    hs = he.value.speed_milli;
  }

  let rm = b2_body_remove(w, c.value);
  if !rm.is_ok { return Err("contact remove: " + rm.error); }
  // Removal-generated end events are buffered for the next step (Box2D
  // swaps/clears its end-event buffers inside b2World_Step), so step once.
  let st2 = b2_step(w);
  if !st2.is_ok { return Err("contact end step: " + st2.error); }
  let ne = b2_contact_event_count(w, B2_CONTACT_END);
  if !ne.is_ok { return Err("end count: " + ne.error); }
  var ea: Int = -2;
  var eb: Int = -2;
  if ne.value > 0 {
    let ee = b2_contact_event(w, B2_CONTACT_END, 0);
    if !ee.is_ok { return Err("end event: " + ee.error); }
    ea = ee.value.body_a;
    eb = ee.value.body_b;
  }

  let dd = b2_world_destroy(w);
  if !dd.is_ok { return Err("contact destroy: " + dd.error); }
  return Ok(ContactProbe{
    steps_to_touch: found;
    begin_a: be.value.body_a;
    begin_b: be.value.body_b;
    hit_count: nh.value;
    hit_a: ha;
    hit_b: hb;
    hit_x: hx;
    hit_y: hy;
    hit_nx: hnx;
    hit_ny: hny;
    hit_speed: hs;
    end_count: ne.value;
    end_a: ea;
    end_b: eb;
  });
}

fn main() -> Int {
  io.println("=== xiom.box2d conformance tests (vendored v3.1.1) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Version pin (v3.1.x).
  let v = b2_version();
  let major = v >> 16;
  let minor = (v >> 8) & 255;
  failed = failed + report(major == 3 && minor == 1, "version: " + b2_version_str(v));

  // 2. Default gravity read back from a live world.
  let g = b2_gravity();
  if g.is_ok {
    failed = failed + report(g.value.gx_milli == 0 && g.value.gy_milli == -10000,
      "gravity: (" + i2s(g.value.gx_milli) + ", " + i2s(g.value.gy_milli) + ") milli");
  } else {
    failed = failed + report(false, "gravity: " + g.error);
  }

  // 3. Resting drop: 1x1 box from y=10 settles on a ground (top at y=0);
  //    the center lands at ~0.5 (half extent) within tolerance.
  let d = b2_drop(10000, B2_DEFAULT_STEPS);
  if d.is_ok {
    failed = failed + report(d.value.final_y_milli >= 400 && d.value.final_y_milli <= 600,
      "drop: final_y=" + i2s(d.value.final_y_milli) + " milli, awake=" + b2s(d.value.awake));
  } else {
    failed = failed + report(false, "drop: " + d.error);
  }

  // 4. Impulse -> velocity on a free box (mass 1 kg): dv = J / m.
  let im = b2_impulse(5000);
  if im.is_ok {
    failed = failed + report(im.value >= 4500 && im.value <= 5500,
      "impulse: vx=" + i2s(im.value) + " milli");
  } else {
    failed = failed + report(false, "impulse: " + im.error);
  }

  // 5. Determinism: a repeated drop yields the same final y.
  let d2 = b2_drop(10000, B2_DEFAULT_STEPS);
  let same = d.is_ok && d2.is_ok && d2.value.final_y_milli == d.value.final_y_milli;
  failed = failed + report(same, "determinism: repeated drop identical");

  // 6. Revolute joint + motor: gravity-off rotor driven at 2 rad/s; after
  //    120 steps (2 s) the angular velocity is at the motor speed and the
  //    joint angle integrates to 4 rad -- Box2D wraps revolute angles to
  //    [-pi, pi], so 4 - 2*pi ~ -2283 milli.
  let rj = b2_revolute_motor(2000, 120);
  if rj.is_ok {
    let w_ok = rj.value.w_milli >= 1950 && rj.value.w_milli <= 2050;
    let a_ok = rj.value.angle_milli >= -2403 && rj.value.angle_milli <= -2163;
    failed = failed + report(w_ok && a_ok,
      "revolute motor: w=" + i2s(rj.value.w_milli) + " angle=" + i2s(rj.value.angle_milli) + " milli");
  } else {
    failed = failed + report(false, "revolute motor: " + rj.error);
  }

  // 7. Prismatic joint + motor: gravity pulls down but the joint holds y=2
  //    while the motor drives +x at 1 m/s -> translation ~2 m.
  let pj = b2_prismatic_motor(1000, 120);
  if pj.is_ok {
    let t_ok = pj.value.translation_milli >= 1900 && pj.value.translation_milli <= 2100;
    let y_ok = pj.value.y_milli >= 1990 && pj.value.y_milli <= 2010;
    failed = failed + report(t_ok && y_ok,
      "prismatic motor: translation=" + i2s(pj.value.translation_milli) + " y=" + i2s(pj.value.y_milli) + " milli");
  } else {
    failed = failed + report(false, "prismatic motor: " + pj.error);
  }

  // 8. World create (0.4.0): fixed dt readback + empty count + destroy.
  let w8 = b2_world_create(0, -10000, 16667, 64);
  if w8.is_ok {
    let dt8 = b2_world_dt_micros(w8.value);
    let bc8 = b2_body_count(w8.value);
    if dt8.is_ok && bc8.is_ok {
      failed = failed + report(dt8.value == 16667 && bc8.value == 0,
        "world: dt=" + i2s(dt8.value) + " us, bodies=" + i2s(bc8.value));
    } else {
      failed = failed + report(false, "world: dt/count lookup failed");
    }
    let dd8 = b2_world_destroy(w8.value);
    if !dd8.is_ok { failed = failed + report(false, "world destroy: " + dd8.error); }
  } else {
    failed = failed + report(false, "world create: " + w8.error);
  }

  // 9. Body add + count + ids + capacity rejection.
  let w9 = b2_world_create(0, -10000, 16667, 3);
  if w9.is_ok {
    let b0 = b2_body_add(w9.value, box_desc(500, 500, 0, 0, 0, 0, true));
    let b1 = b2_body_add(w9.value, circle_desc(500, 0, 2000, 0, false));
    let b2r = b2_body_add(w9.value, box_desc(100, 100, 1000, 0, 0, 0, false));
    let b3 = b2_body_add(w9.value, box_desc(100, 100, 2000, 0, 0, 0, false));
    let cnt9 = b2_body_count(w9.value);
    if b0.is_ok && b1.is_ok && b2r.is_ok && cnt9.is_ok {
      failed = failed + report(b0.value == 0 && b1.value == 1 && b2r.value == 2 && cnt9.value == 3 && !b3.is_ok,
        "bodies: ids 0,1,2 count=" + i2s(cnt9.value) + ", 4th rejected=" + b2s(!b3.is_ok));
    } else {
      failed = failed + report(false, "bodies: add/count failed");
    }
    let dd9 = b2_world_destroy(w9.value);
    if !dd9.is_ok { failed = failed + report(false, "bodies destroy: " + dd9.error); }
  } else {
    failed = failed + report(false, "bodies world: " + w9.error);
  }

  // 10. State read by handle: fresh values (pos/vel/angle/awake), no slots.
  let w10 = b2_world_create(0, 0, 16667, 8);
  if w10.is_ok {
    let b10 = b2_body_add(w10.value, box_desc(500, 500, 1234, 567, 300, 0, false));
    if b10.is_ok {
      let s10 = b2_body_state(w10.value, b10.value);
      if s10.is_ok {
        let ok10 = s10.value.px_milli == 1234 && s10.value.py_milli == 567 &&
          s10.value.vx_milli == 0 && s10.value.vy_milli == 0 &&
          near(s10.value.angle_milli, 300, 2) && s10.value.awake;
        failed = failed + report(ok10,
          "state: pos=(" + i2s(s10.value.px_milli) + "," + i2s(s10.value.py_milli) + ") angle=" + i2s(s10.value.angle_milli) + " awake=" + b2s(s10.value.awake));
      } else {
        failed = failed + report(false, "state: " + s10.error);
      }
    } else {
      failed = failed + report(false, "state body: " + b10.error);
    }
    let dd10 = b2_world_destroy(w10.value);
    if !dd10.is_ok { failed = failed + report(false, "state destroy: " + dd10.error); }
  } else {
    failed = failed + report(false, "state world: " + w10.error);
  }

  // 11. Static body under gravity: must not move.
  let sp = static_probe();
  if sp.is_ok {
    failed = failed + report(sp.value.px_milli == 0 && sp.value.py_milli == 5000 && sp.value.vy_milli == 0,
      "static: pos=(" + i2s(sp.value.px_milli) + "," + i2s(sp.value.py_milli) + ") vy=" + i2s(sp.value.vy_milli) + " awake=" + b2s(sp.value.awake));
  } else {
    failed = failed + report(false, "static: " + sp.error);
  }

  // 12. Free fall: gravity (0,-10) at 60 Hz for 1 s; semi-implicit Euler
  //     with 4 sub-steps lands the box near y = 10 - 5.02 = 4.98 m.
  let ff = freefall_probe();
  if ff.is_ok {
    let ok12 = ff.value.py_milli >= 4850 && ff.value.py_milli <= 5100 &&
      ff.value.vy_milli >= -10120 && ff.value.vy_milli <= -9880;
    failed = failed + report(ok12,
      "freefall: y=" + i2s(ff.value.py_milli) + " vy=" + i2s(ff.value.vy_milli) + " awake=" + b2s(ff.value.awake));
  } else {
    failed = failed + report(false, "freefall: " + ff.error);
  }

  // 13. Mass readback: density default (1 kg box), caller override, circle area.
  let w13 = b2_world_create(0, 0, 16667, 8);
  if w13.is_ok {
    let m1 = b2_body_add(w13.value, box_desc(500, 500, 0, 0, 0, 0, false));
    let m2 = b2_body_add(w13.value, box_desc(500, 500, 1000, 0, 0, 2000, false));
    let m3 = b2_body_add(w13.value, circle_desc(500, 2000, 0, 0, false));
    if m1.is_ok && m2.is_ok && m3.is_ok {
      let mass1 = b2_body_mass_milli(w13.value, m1.value);
      let mass2 = b2_body_mass_milli(w13.value, m2.value);
      let mass3 = b2_body_mass_milli(w13.value, m3.value);
      if mass1.is_ok && mass2.is_ok && mass3.is_ok {
        failed = failed + report(mass1.value == 1000 && mass2.value == 2000 && near(mass3.value, 785, 3),
          "mass: box=" + i2s(mass1.value) + " override=" + i2s(mass2.value) + " circle=" + i2s(mass3.value));
      } else {
        failed = failed + report(false, "mass lookup failed");
      }
    } else {
      failed = failed + report(false, "mass add failed");
    }
    let dd13 = b2_world_destroy(w13.value);
    if !dd13.is_ok { failed = failed + report(false, "mass destroy: " + dd13.error); }
  } else {
    failed = failed + report(false, "mass world: " + w13.error);
  }

  // 14. Body remove: count drops and the id is rejected afterwards.
  let rm14 = remove_probe();
  if rm14.is_ok {
    failed = failed + report(rm14.value == 1, "remove: remaining=" + i2s(rm14.value) + " (stale id rejected)");
  } else {
    failed = failed + report(false, "remove: " + rm14.error);
  }

  // 15/16. Broadphase queries on static ground (id 0) + static box (id 1).
  let qp = query_probe();
  if qp.is_ok {
    let q = qp.value;
    let ok15 = q.r1_hit && q.r1_body == 1 && near(q.r1_frac, 375, 25) && q.r1_ny >= 500 &&
      q.r2_hit && q.r2_body == 0 && near(q.r2_frac, 500, 25) && !q.r3_hit;
    failed = failed + report(ok15,
      "raycast: box f=" + i2s(q.r1_frac) + " ny=" + i2s(q.r1_ny) + ", ground f=" + i2s(q.r2_frac) + ", miss=" + b2s(!q.r3_hit));
    let ok16 = q.oc1 == 1 && q.oc1_body == 1 && q.oc1_x == 0 && near(q.oc1_y, 2000, 5) &&
      q.oc2 == 1 && q.oc2_body == 0 && q.oc3 == 0 &&
      q.ob1 == 1 && q.ob1_body == 1;
    failed = failed + report(ok16,
      "overlap: box-hit=" + i2s(q.oc1_body) + " ground-hit=" + i2s(q.oc2_body) + " empty=" + i2s(q.oc3) + " boxq=" + i2s(q.ob1_body));
  } else {
    failed = failed + report(false, "queries: " + qp.error);
  }

  // 17/18/19. Contact events: begin + hit on the touch step, end on removal.
  let cp = contact_probe();
  if cp.is_ok {
    let c = cp.value;
    let begin_ok = c.steps_to_touch >= 0 && pair01(c.begin_a, c.begin_b);
    let hit_ok = c.hit_count >= 1 && pair01(c.hit_a, c.hit_b) && c.hit_speed >= 1000 &&
      near(c.hit_x, 0, 200) && near(c.hit_y, 0, 200) && (c.hit_ny >= 500 || c.hit_ny <= -500);
    let end_ok = c.end_count >= 1 && ((c.end_a == 0 && c.end_b == -1) || (c.end_a == -1 && c.end_b == 0));
    failed = failed + report(begin_ok,
      "contact begin: step=" + i2s(c.steps_to_touch) + " pair=(" + i2s(c.begin_a) + "," + i2s(c.begin_b) + ")");
    failed = failed + report(hit_ok,
      "contact hit: n=" + i2s(c.hit_count) + " speed=" + i2s(c.hit_speed) + " y=" + i2s(c.hit_y) + " ny=" + i2s(c.hit_ny));
    failed = failed + report(end_ok,
      "contact end: n=" + i2s(c.end_count) + " pair=(" + i2s(c.end_a) + "," + i2s(c.end_b) + ")");
  } else {
    failed = failed + report(false, "contacts: " + cp.error);
  }

  // 20. Weld joint (world anchor at (0,2)): gravity must not move the box.
  let weld = weld_probe();
  if weld.is_ok {
    let p = weld.value;
    failed = failed + report(p.kind == B2_JOINT_WELD && p.body_a == B2_WORLD && p.body_b >= 0 && near(p.x_milli, 0, 20) && near(p.y_milli, 2000, 20),
      "weld: pos=(" + i2s(p.x_milli) + "," + i2s(p.y_milli) + ") kind=" + i2s(p.kind));
  } else {
    failed = failed + report(false, "weld: " + weld.error);
  }

  // 21. Distance joint: pendulum holds radius 2 m while swinging down.
  let dist = distance_probe();
  if dist.is_ok {
    let p = dist.value;
    let r2 = p.x_milli * p.x_milli + p.y_milli * p.y_milli;
    let ok21 = p.kind == B2_JOINT_DISTANCE && near(p.primary_milli, 2000, 50) && near(r2, 4000000, 200000) && p.y_milli < -500;
    failed = failed + report(ok21,
      "distance: len=" + i2s(p.primary_milli) + " pos=(" + i2s(p.x_milli) + "," + i2s(p.y_milli) + ")");
  } else {
    failed = failed + report(false, "distance: " + dist.error);
  }

  // 22. Wheel joint motor: 2 rad/s bar spins in place.
  let wh = wheel_probe();
  if wh.is_ok {
    let p = wh.value;
    let ok22 = p.kind == B2_JOINT_WHEEL && p.w_milli >= 1900 && p.w_milli <= 2100 && near(p.x_milli, 0, 20) && near(p.y_milli, 0, 20);
    failed = failed + report(ok22,
      "wheel: w=" + i2s(p.w_milli) + " pos=(" + i2s(p.x_milli) + "," + i2s(p.y_milli) + ")");
  } else {
    failed = failed + report(false, "wheel: " + wh.error);
  }

  // 23. Motor joint: box created at 1 rad is driven back to the hub pose.
  let mo = motor_probe();
  if mo.is_ok {
    let p = mo.value;
    let ok23 = p.kind == B2_JOINT_MOTOR && near(p.angle_milli, 0, 50) && near(p.x_milli, 0, 50) && near(p.y_milli, 0, 50);
    failed = failed + report(ok23,
      "motor: angle=" + i2s(p.angle_milli) + " pos=(" + i2s(p.x_milli) + "," + i2s(p.y_milli) + ")");
  } else {
    failed = failed + report(false, "motor: " + mo.error);
  }

  // 24. Revolute through the generic desc (wraps like the 0.3.0 probe).
  let rev = revolute_desc_probe();
  if rev.is_ok {
    let p = rev.value;
    let ok24 = p.kind == B2_JOINT_REVOLUTE && p.w_milli >= 1950 && p.w_milli <= 2050 && p.primary_milli >= -2403 && p.primary_milli <= -2163;
    failed = failed + report(ok24,
      "revolute desc: w=" + i2s(p.w_milli) + " angle=" + i2s(p.primary_milli));
  } else {
    failed = failed + report(false, "revolute desc: " + rev.error);
  }

  // 25. Prismatic through the generic desc (mirrors the 0.3.0 probe).
  let pr = prismatic_desc_probe();
  if pr.is_ok {
    let p = pr.value;
    let ok25 = p.kind == B2_JOINT_PRISMATIC && p.primary_milli >= 1900 && p.primary_milli <= 2100 && p.y_milli >= 1990 && p.y_milli <= 2010;
    failed = failed + report(ok25,
      "prismatic desc: translation=" + i2s(p.primary_milli) + " y=" + i2s(p.y_milli));
  } else {
    failed = failed + report(false, "prismatic desc: " + pr.error);
  }

  // 26. Typed errors: unknown/stale ids and bad indices are rejected.
  let w26 = b2_world_create(0, -10000, 16667, 8);
  if w26.is_ok {
    let b26 = b2_body_add(w26.value, box_desc(100, 100, 0, 0, 0, 0, false));
    if b26.is_ok {
      let s1 = b2_body_state(w26.value, 123);
      let s2 = b2_overlap(w26.value, 99);
      let s3 = b2_joint_state(w26.value, 0);
      let jbad = b2_joint_add(w26.value, weld_desc(B2_WORLD, B2_WORLD, 0, 0));
      let d26 = b2_world_destroy(w26.value);
      let s4 = b2_body_count(w26.value);
      failed = failed + report(!s1.is_ok && !s2.is_ok && !s3.is_ok && !jbad.is_ok && d26.is_ok && !s4.is_ok,
        "errors: unknown body/overlap/joint rejected, stale world rejected");
    } else {
      failed = failed + report(false, "errors: body add failed");
    }
  } else {
    failed = failed + report(false, "errors: world create failed");
  }

  if failed == 0 {
    io.println("xiom.box2d: all tests passed");
  } else {
    io.println("xiom.box2d: tests failed");
  }
  return failed;
}
