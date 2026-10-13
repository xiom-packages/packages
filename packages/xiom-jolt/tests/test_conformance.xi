// xiom.jolt conformance suite -- vendored Jolt Physics v5.6.0 core.
//
// Build+run (the --c-source list rides in port.args.json; Jolt needs C++17,
// carried by the pinned compiler):
//   scripts/port.ps1 -Package xiom.jolt -TimeoutSec 600
//
// Covers the 0.2.0 scalar probes and the 0.3.0 caller-usable world/body
// surface (world lifecycle, body add/remove/count, step control, owned state
// read-back; engine contract v0 flow = world + ground + box/sphere + N fixed
// steps + read-back).

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
  return a.px_milli == b.px_milli && a.py_milli == b.py_milli && a.pz_milli == b.pz_milli && a.rx_milli == b.rx_milli && a.ry_milli == b.ry_milli && a.rz_milli == b.rz_milli && a.rw_milli == b.rw_milli && a.vx_milli == b.vx_milli && a.vy_milli == b.vy_milli && a.vz_milli == b.vz_milli && a.awake == b.awake;
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

  if failed == 0 {
    io.println("xiom.jolt: all tests passed");
  } else {
    io.println("xiom.jolt: tests failed");
  }
  return failed;
}
