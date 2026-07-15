// XIOM — Jolt Physics Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Minimal physics simulation: a sphere bouncing on a box floor under gravity.
// Uses the safe wrapper layer (jolt_safe.xi).

module jolt_demo
use xiom.jolt_safe;

fn run_demo() -> Int {
  // --- Create world ---
  let r = JoltWorld.new(1024, 1024, 1024);
  let world: JoltWorld;
  match r {
    Ok(w) => { world = w; };
    Err(msg) => {
      // In production: log fatal error
      return 1;
    };
  }

  // --- Set gravity (Earth-like) ---
  let _ = world.set_gravity(0.0, -9.81, 0.0);

  // --- Floor (static box, 50 x 1 x 50) ---
  let floor_shape = box_shape(50.0, 0.5, 50.0);
  match floor_shape {
    Ok(shape) => {
      let fpos = Vec3 { x: 0.0, y: -2.0, z: 0.0 };
      let frot = Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
      let settings = make_static_body(shape, fpos, frot);
      match settings {
        Ok(s) => {
          let body_result = PhysicsBody.new(world.handle, s, false);
          match body_result {
            Ok(_body) => {};
            Err(_e) => {};
          };
        };
        Err(_e) => {};
      };
    };
    Err(_e) => {};
  };

  // --- Spawning platform (static box) ---
  let platform_shape = box_shape(2.0, 0.2, 2.0);
  match platform_shape {
    Ok(shape) => {
      let ppos = Vec3 { x: 3.0, y: 1.0, z: 0.0 };
      let prot = Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
      let settings = make_static_body(shape, ppos, prot);
      match settings {
        Ok(s) => {
          let _ = PhysicsBody.new(world.handle, s, false);
        };
        Err(_e) => {};
      };
    };
    Err(_e) => {};
  };

  // --- Dynamic sphere ---
  let sphere_shape = sphere_shape(0.5);
  let sphere_body: PhysicsBody;
  match sphere_shape {
    Ok(shape) => {
      let spos = Vec3 { x: 0.0, y: 5.0, z: 0.0 };
      let srot = Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
      let settings = make_dynamic_body(shape, spos, srot);
      match settings {
        Ok(s) => {
          let body_result = PhysicsBody.new(world.handle, s, true);
          match body_result {
            Ok(body) => { sphere_body = body; };
            Err(_e) => { return 1; };
          };
        };
        Err(_e) => { return 1; };
      };
    };
    Err(_e) => { return 1; };
  };

  // --- Optimize before main loop ---
  let _ = world.optimize();

  // --- Simulation loop: 60 Hz, 300 steps (5 seconds) ---
  let dt: Float32 = 1.0 / 60.0;
  var step: Int = 0;
  var active: Bool = true;
  while step < 300 {
    let _ = world.step(dt, 1);

    match sphere_body.position() {
      Ok(pos) => {
        // In a real app: log or render position
      };
      Err(_e) => {
        return 1;
      };
    };

    match sphere_body.is_active() {
      Ok(a) => { active = a; };
      Err(_e) => { return 1; };
    };

    if !active {
      // Body went to sleep — stop simulating
      break;
    };
    step = step + 1;
  };

  // --- Cleanup ---
  let _ = sphere_body.destroy();
  let _ = world.destroy();

  return 0;
}

fn main() -> Int {
  return run_demo();
}
