// XIOM — Box2D Physics Demo & Test Suite
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive test suite for the Box2D bindings: world lifecycle,
// bodies, shapes, joints, ray casts, mass properties, world settings,
// and body state flags.
//
// NOTE: This demo currently cannot run without the following prerequisites:
//   1. Xiom compiler support for struct-by-value FFI (see AUDIT.md §1)
//   2. box2d.dll / libbox2d.so available at link time
//   3. Built-in math intrinsics (sqrt, cos, sin, atan2) wired up
//
// Once these are available, compile and run with:
//   xiom run demo_box2d.xi

module demo_box2d

use xiom.io;
use xiom.box2d;
use xiom.box2d_safe;

// ===========================================================================
// TEST HARNESS
// ===========================================================================

pub type TestResult = {
  passed: Bool;
  message: Str;
}

pub fn assert(condition: Bool, message: Str) -> TestResult {
  return TestResult{ passed: condition, message: message };
}

fn f32_abs(v: Float32) -> Float32 {
  if v < 0.0 {
    return 0.0 - v;
  }
  return v;
}

fn approx_eq(a: Float32, b: Float32, eps: Float32) -> Bool {
  return f32_abs(a - b) <= eps;
}

pub fn run_all(tests: Vec[fn() -> TestResult]) -> Int32 {
  var passed: Int32 = 0;
  var failed: Int32 = 0;
  var i: Int32 = 0;
  while i < tests.len() {
    let result = tests[i]();
    if result.passed {
      io.println("[PASS] " + result.message);
      passed = passed + 1;
    } else {
      io.println("[FAIL] " + result.message);
      failed = failed + 1;
    }
    i = i + 1;
  }
  if failed == 0 {
    io.println("box2d demo: all tests passed");
  } else {
    io.println("box2d demo: some tests FAILED");
  }
  return failed;
}

// ===========================================================================
// TEST 1: World Create / Destroy — basic lifecycle
// ===========================================================================

fn test_world_create_destroy() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let valid = unsafe { b2World_IsValid(w) };
      if valid == 0 {
        destroy_world(w);
        return assert(false, "world reported invalid after create");
      }
      destroy_world(w);
      return assert(true, "world create/destroy lifecycle");
    }
  }
}

// ===========================================================================
// TEST 2: Static Ground — create ground plane, verify body valid
// ===========================================================================

fn test_static_ground() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let ground = create_ground_box(w, 0.0, -1.0, 20.0, 1.0, 0.0);
      match ground {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "ground create failed: " + e2);
        },
        Ok(g) => {
          let valid = unsafe { b2Body_IsValid(g) };
          let btype = unsafe { b2Body_GetType(g) };
          let ok = !is_null_body_id(g) && valid != 0 && btype == B2_STATIC_BODY;
          destroy_world(w);
          return assert(ok, "static ground body valid");
        }
      }
    }
  }
}

// ===========================================================================
// TEST 3: Dynamic Falling Body — y position decreases after 60 steps
// ===========================================================================

fn test_dynamic_falling_body() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let ground = create_ground_box(w, 0.0, -1.0, 20.0, 1.0, 0.0);
      match ground {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "ground create failed: " + e2);
        },
        Ok(_) => {}
      }

      let body = create_body_dynamic(w, 0.0, 5.0, 0.0);
      match body {
        Err(e3) => {
          destroy_world(w);
          return assert(false, "body create failed: " + e3);
        },
        Ok(b) => {
          let shape = create_box_shape(b, 0.5, 0.5);
          match shape {
            Err(e4) => {
              destroy_world(w);
              return assert(false, "shape create failed: " + e4);
            },
            Ok(_) => {}
          }

          var sim_steps: Int32 = 0;
          while sim_steps < 60 {
            step(w, 1.0 / 60.0, 4);
            sim_steps = sim_steps + 1;
          }

          let (_, py) = body_get_position(b);
          let has_fallen = py < 5.0;
          destroy_world(w);
          return assert(has_fallen, "dynamic body fell under gravity");
        }
      }
    }
  }
}

// ===========================================================================
// TEST 4: Box Stack — stack 5 boxes, step, verify contacts exist
// ===========================================================================

fn test_box_stack() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let ground = create_ground_box(w, 0.0, -1.0, 20.0, 1.0, 0.0);
      match ground {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "ground create failed: " + e2);
        },
        Ok(_) => {}
      }

      var stack_y: Float32 = 0.5;
      var row: Int32 = 0;
      while row < 5 {
        let body = create_body_dynamic(w, 0.0, stack_y, 0.0);
        match body {
          Err(e3) => {
            destroy_world(w);
            return assert(false, "stack body create failed: " + e3);
          },
          Ok(b) => {
            let shape = create_box_shape(b, 0.5, 0.5);
            match shape {
              Err(e4) => {
                destroy_world(w);
                return assert(false, "stack shape create failed: " + e4);
              },
              Ok(_) => {}
            }
          }
        }
        stack_y = stack_y + 1.1;
        row = row + 1;
      }

      var total_contacts: Int32 = 0;
      var sim_steps: Int32 = 0;
      while sim_steps < 60 {
        step(w, 1.0 / 60.0, 4);
        total_contacts = total_contacts + get_contact_event_count(w);
        sim_steps = sim_steps + 1;
      }

      let has_contacts = total_contacts > 0;
      destroy_world(w);
      return assert(has_contacts, "box stack of 5 generated contacts");
    }
  }
}

// ===========================================================================
// TEST 5: Revolute Joint — pendulum (anchor + bob + joint), joint valid
// ===========================================================================

fn test_revolute_joint() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let anchor = create_body_static(w, 0.0, 3.0, 0.0);
      match anchor {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "anchor create failed: " + e2);
        },
        Ok(a) => {
          let bob = create_body_dynamic(w, 0.0, 1.0, 0.0);
          match bob {
            Err(e3) => {
              destroy_world(w);
              return assert(false, "bob create failed: " + e3);
            },
            Ok(b) => {
              let bob_shape = create_box_shape(b, 0.3, 0.3);
              match bob_shape {
                Err(e4) => {
                  destroy_world(w);
                  return assert(false, "bob shape failed: " + e4);
                },
                Ok(_) => {}
              }

              let joint = create_revolute_joint(w, a, b, 0.0, -2.0);
              match joint {
                Err(e5) => {
                  destroy_world(w);
                  return assert(false, "revolute joint create failed: " + e5);
                },
                Ok(j) => {
                  let valid = unsafe { b2Joint_IsValid(j) };
                  let jtype = unsafe { b2Joint_GetType(j) };
                  var sim_steps: Int32 = 0;
                  while sim_steps < 10 {
                    step(w, 1.0 / 60.0, 4);
                    sim_steps = sim_steps + 1;
                  }
                  let still_valid = unsafe { b2Joint_IsValid(j) };
                  let ok = !is_null_joint_id(j) && valid != 0
                        && jtype == B2_REVOLUTE_JOINT && still_valid != 0;
                  destroy_world(w);
                  return assert(ok, "revolute joint (pendulum) valid");
                }
              }
            }
          }
        }
      }
    }
  }
}

// ===========================================================================
// TEST 6: Distance Joint — two bodies connected by spring, joint valid
// ===========================================================================

fn test_distance_joint() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let anchor = create_body_static(w, 0.0, 4.0, 0.0);
      match anchor {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "anchor create failed: " + e2);
        },
        Ok(a) => {
          let bob = create_body_dynamic(w, 0.0, 2.0, 0.0);
          match bob {
            Err(e3) => {
              destroy_world(w);
              return assert(false, "bob create failed: " + e3);
            },
            Ok(b) => {
              let bob_shape = create_circle_shape(b, 0.3);
              match bob_shape {
                Err(e4) => {
                  destroy_world(w);
                  return assert(false, "bob shape failed: " + e4);
                },
                Ok(_) => {}
              }

              let joint = create_distance_joint(w, a, b, 0.0, 0.0, 0.0, 0.0, 2.0);
              match joint {
                Err(e5) => {
                  destroy_world(w);
                  return assert(false, "distance joint create failed: " + e5);
                },
                Ok(j) => {
                  let valid = unsafe { b2Joint_IsValid(j) };
                  let jtype = unsafe { b2Joint_GetType(j) };
                  var sim_steps: Int32 = 0;
                  while sim_steps < 10 {
                    step(w, 1.0 / 60.0, 4);
                    sim_steps = sim_steps + 1;
                  }
                  let still_valid = unsafe { b2Joint_IsValid(j) };
                  let ok = !is_null_joint_id(j) && valid != 0
                        && jtype == B2_DISTANCE_JOINT && still_valid != 0;
                  destroy_world(w);
                  return assert(ok, "distance joint (spring) valid");
                }
              }
            }
          }
        }
      }
    }
  }
}

// ===========================================================================
// TEST 7: Ray Cast — cast ray down at ground, verify hit
// ===========================================================================

fn test_ray_cast() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let ground = create_ground_box(w, 0.0, -1.0, 20.0, 1.0, 0.0);
      match ground {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "ground create failed: " + e2);
        },
        Ok(_) => {}
      }

      let hit = ray_cast_closest(w, 0.0, 5.0, 0.0, -10.0);
      match hit {
        None => {
          destroy_world(w);
          return assert(false, "ray cast missed ground");
        },
        Some(h) => {
          let (_, hy, fraction) = h;
          let ok = hy < 1.0 && fraction > 0.0 && fraction <= 1.0;
          destroy_world(w);
          return assert(ok, "ray cast hit ground at sane point");
        }
      }
    }
  }
}

// ===========================================================================
// TEST 8: Body Properties — type, position, velocity get/set
// ===========================================================================

fn test_body_properties() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let body = create_body_dynamic(w, 2.0, 3.0, 0.0);
      match body {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "body create failed: " + e2);
        },
        Ok(b) => {
          let btype = unsafe { b2Body_GetType(b) };
          if btype != B2_DYNAMIC_BODY {
            destroy_world(w);
            return assert(false, "body type not dynamic");
          }

          let (px, py) = body_get_position(b);
          if !approx_eq(px, 2.0, 0.001) || !approx_eq(py, 3.0, 0.001) {
            destroy_world(w);
            return assert(false, "initial position mismatch");
          }

          body_set_position(b, 5.0, 7.0, 0.0);
          let (nx, ny) = body_get_position(b);
          if !approx_eq(nx, 5.0, 0.001) || !approx_eq(ny, 7.0, 0.001) {
            destroy_world(w);
            return assert(false, "set position not reflected in get");
          }

          body_set_velocity(b, 1.5, -2.5);
          let (vx, vy) = body_get_velocity(b);
          if !approx_eq(vx, 1.5, 0.001) || !approx_eq(vy, -2.5, 0.001) {
            destroy_world(w);
            return assert(false, "set linear velocity not reflected in get");
          }

          body_set_angular_velocity(b, 3.0);
          let omega = body_get_angular_velocity(b);
          if !approx_eq(omega, 3.0, 0.001) {
            destroy_world(w);
            return assert(false, "set angular velocity not reflected in get");
          }

          destroy_world(w);
          return assert(true, "body properties get/set");
        }
      }
    }
  }
}

// ===========================================================================
// TEST 9: Shape Properties — friction/restitution/density get/set
// ===========================================================================

fn test_shape_properties() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let body = create_body_dynamic(w, 0.0, 2.0, 0.0);
      match body {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "body create failed: " + e2);
        },
        Ok(b) => {
          let shape = create_box_shape_with_material(b, 0.5, 0.5, 2.0, 0.4, 0.1);
          match shape {
            Err(e3) => {
              destroy_world(w);
              return assert(false, "shape create failed: " + e3);
            },
            Ok(s) => {
              let friction0 = unsafe { b2Shape_GetFriction(s) };
              let restitution0 = unsafe { b2Shape_GetRestitution(s) };
              let density0 = unsafe { b2Shape_GetDensity(s) };
              if !approx_eq(friction0, 0.4, 0.001)
                || !approx_eq(restitution0, 0.1, 0.001)
                || !approx_eq(density0, 2.0, 0.001) {
                destroy_world(w);
                return assert(false, "initial shape material mismatch");
              }

              shape_set_friction(s, 0.9);
              let friction1 = unsafe { b2Shape_GetFriction(s) };
              if !approx_eq(friction1, 0.9, 0.001) {
                destroy_world(w);
                return assert(false, "set friction not reflected in get");
              }

              shape_set_restitution(s, 0.5);
              let restitution1 = unsafe { b2Shape_GetRestitution(s) };
              if !approx_eq(restitution1, 0.5, 0.001) {
                destroy_world(w);
                return assert(false, "set restitution not reflected in get");
              }

              unsafe { b2Shape_SetDensity(s, 3.0, 1 as Int32); }
              let density1 = unsafe { b2Shape_GetDensity(s) };
              if !approx_eq(density1, 3.0, 0.001) {
                destroy_world(w);
                return assert(false, "set density not reflected in get");
              }

              destroy_world(w);
              return assert(true, "shape properties get/set");
            }
          }
        }
      }
    }
  }
}

// ===========================================================================
// TEST 10: Mass — positive mass for dynamic body with shape
// ===========================================================================

fn test_mass() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let body = create_body_dynamic(w, 0.0, 2.0, 0.0);
      match body {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "body create failed: " + e2);
        },
        Ok(b) => {
          let shape = create_box_shape_with_material(b, 0.5, 0.5, 2.0, 0.6, 0.0);
          match shape {
            Err(e3) => {
              destroy_world(w);
              return assert(false, "shape create failed: " + e3);
            },
            Ok(_) => {}
          }

          // 1x1 box with density 2.0 => mass = 2.0
          let mass = body_get_mass(b);
          let ok = mass > 0.0 && approx_eq(mass, 2.0, 0.1);
          destroy_world(w);
          return assert(ok, "dynamic body mass positive and correct");
        }
      }
    }
  }
}

// ===========================================================================
// TEST 11: World Settings — gravity, sleep, continuous
// ===========================================================================

fn test_world_settings() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let g0 = unsafe { b2World_GetGravity(w) };
      if !approx_eq(g0.x, 0.0, 0.001) || !approx_eq(g0.y, -10.0, 0.001) {
        destroy_world(w);
        return assert(false, "initial gravity mismatch");
      }

      set_gravity(w, 0.0, -3.5);
      let g1 = unsafe { b2World_GetGravity(w) };
      if !approx_eq(g1.y, -3.5, 0.001) {
        destroy_world(w);
        return assert(false, "set gravity not reflected in get");
      }

      unsafe { b2World_EnableSleeping(w, 0 as Int32); }
      let sleep_off = unsafe { b2World_IsSleepingEnabled(w) };
      unsafe { b2World_EnableSleeping(w, 1 as Int32); }
      let sleep_on = unsafe { b2World_IsSleepingEnabled(w) };
      if sleep_off != 0 || sleep_on == 0 {
        destroy_world(w);
        return assert(false, "sleep toggle not reflected in get");
      }

      unsafe { b2World_EnableContinuous(w, 0 as Int32); }
      let cont_off = unsafe { b2World_IsContinuousEnabled(w) };
      unsafe { b2World_EnableContinuous(w, 1 as Int32); }
      let cont_on = unsafe { b2World_IsContinuousEnabled(w) };
      if cont_off != 0 || cont_on == 0 {
        destroy_world(w);
        return assert(false, "continuous toggle not reflected in get");
      }

      destroy_world(w);
      return assert(true, "world settings gravity/sleep/continuous");
    }
  }
}

// ===========================================================================
// TEST 12: Body State — awake, enabled, bullet
// ===========================================================================

fn test_body_state() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      let body = create_body_dynamic(w, 0.0, 2.0, 0.0);
      match body {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "body create failed: " + e2);
        },
        Ok(b) => {
          if !body_is_awake(b) {
            destroy_world(w);
            return assert(false, "new dynamic body not awake");
          }
          body_set_awake(b, false);
          if body_is_awake(b) {
            destroy_world(w);
            return assert(false, "body still awake after sleep request");
          }
          body_set_awake(b, true);
          if !body_is_awake(b) {
            destroy_world(w);
            return assert(false, "body not awake after wake request");
          }

          let enabled0 = unsafe { b2Body_IsEnabled(b) };
          unsafe { b2Body_Disable(b); }
          let enabled1 = unsafe { b2Body_IsEnabled(b) };
          unsafe { b2Body_Enable(b); }
          let enabled2 = unsafe { b2Body_IsEnabled(b) };
          if enabled0 == 0 || enabled1 != 0 || enabled2 == 0 {
            destroy_world(w);
            return assert(false, "enable/disable toggle not reflected in get");
          }

          let bullet0 = unsafe { b2Body_IsBullet(b) };
          unsafe { b2Body_SetBullet(b, 1 as Int32); }
          let bullet1 = unsafe { b2Body_IsBullet(b) };
          unsafe { b2Body_SetBullet(b, 0 as Int32); }
          let bullet2 = unsafe { b2Body_IsBullet(b) };
          if bullet0 != 0 || bullet1 == 0 || bullet2 != 0 {
            destroy_world(w);
            return assert(false, "bullet toggle not reflected in get");
          }

          destroy_world(w);
          return assert(true, "body state awake/enabled/bullet");
        }
      }
    }
  }
}

// ===========================================================================
// MAIN
// ===========================================================================

fn main() -> Int32 {
  var tests = [
    test_world_create_destroy,
    test_static_ground,
    test_dynamic_falling_body,
    test_box_stack,
    test_revolute_joint,
    test_distance_joint,
    test_ray_cast,
    test_body_properties,
    test_shape_properties,
    test_mass,
    test_world_settings,
    test_body_state,
  ];

  var failed = run_all(tests);

  if failed > 0 {
    return 1;
  }
  return 0;
}
