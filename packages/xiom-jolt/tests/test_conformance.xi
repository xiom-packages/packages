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
// unknown/removed id rejection), and the 0.5.0 tiers: E1 world queries
// (raycast closest/any-hit, sphere/capsule sweeps, sphere/capsule overlaps,
// canonical order + determinism), E2 capsule bodies (settle/rotation/query
// participation) and E7 contacts + sensors (manifold reads, typed id errors,
// per-step sensor events, non-physical pass-through).

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

  if failed == 0 {
    io.println("xiom.jolt: all tests passed");
  } else {
    io.println("xiom.jolt: tests failed");
  }
  return failed;
}
