// XIOM — Box2D Physics Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Minimal physics simulation: ground plane + stacks of falling boxes.
// Demonstrates world creation, body/shape setup, simulation stepping,
// and body position querying.
//
// NOTE: This demo currently cannot run without the following prerequisites:
//   1. Xiom compiler support for struct-by-value FFI (see AUDIT.md §1)
//   2. box2d.dll / libbox2d.so available at link time
//   3. Built-in math intrinsics (sqrt, cos, sin, atan2) wired up
//
// Once these are available, compile and run with:
//   xiom run demo_box2d.xi

module demo_box2d
use xiom.box2d;
use xiom.box2d_safe;

// ===========================================================================
// TEST UTILITIES
// ===========================================================================

pub type TestResult = {
  passed: Bool;
  message: Str;
}

pub fn assert(condition: Bool, message: Str) -> TestResult {
  return TestResult{ passed: condition, message: message };
}

pub fn run_all(tests: Vec[fn() -> TestResult]) -> Int32 {
  var passed: Int32 = 0;
  var failed: Int32 = 0;
  var i: Int32 = 0;
  while i < tests.len() {
    let result = tests[i]();
    if result.passed {
      passed = passed + 1;
    } else {
      failed = failed + 1;
    }
    i = i + 1;
  }
  return failed;
}

// ===========================================================================
// TEST: World Create / Destroy
// ===========================================================================

fn test_world_create_destroy() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      destroy_world(w);
      return assert(true, "world create/destroy");
    }
  }
}

// ===========================================================================
// TEST: Static Ground Body
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
          let valid = !is_null_body_id(g);
          destroy_world(w);
          return assert(valid, "static ground body valid");
        }
      }
    }
  }
}

// ===========================================================================
// TEST: Dynamic Falling Body
// ===========================================================================

fn test_dynamic_falling_body() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      // Ground
      let ground = create_ground_box(w, 0.0, -1.0, 20.0, 1.0, 0.0);
      match ground {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "ground create failed: " + e2);
        },
        Ok(_) => {}
      }

      // Falling box
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

          // Step simulation several times
          var sim_steps: Int32 = 0;
          while sim_steps < 60 {
            step(w, 1.0 / 60.0, 4);
            sim_steps = sim_steps + 1;
          }

          // Body should have fallen (y < initial 5.0)
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
// TEST: Box Stack
// ===========================================================================

fn test_box_stack() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      // Ground
      let ground = create_ground_box(w, 0.0, -1.0, 20.0, 1.0, 0.0);
      match ground {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "ground create failed: " + e2);
        },
        Ok(_) => {}
      }

      // Stack 3 boxes
      var stack_y: Float32 = 0.5;
      var row: Int32 = 0;
      while row < 3 {
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

      // Step a few times and verify contacts exist
      step(w, 1.0 / 60.0, 4);
      step(w, 1.0 / 60.0, 4);
      step(w, 1.0 / 60.0, 4);

      let contact_count = get_contact_event_count(w);
      let has_contacts = contact_count > 0;
      destroy_world(w);
      return assert(has_contacts, "box stack generated contacts");
    }
  }
}

// ===========================================================================
// TEST: Revolute Joint (Pendulum)
// ===========================================================================

fn test_revolute_joint() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      // Static anchor body
      let anchor = create_body_static(w, 0.0, 3.0, 0.0);
      match anchor {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "anchor create failed: " + e2);
        },
        Ok(a) => {
          // Pendulum bob
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

              // Revolute joint at anchor point
              let joint = create_revolute_joint(w, a, b, 0.0, -2.0);
              match joint {
                Err(e5) => {
                  destroy_world(w);
                  return assert(false, "joint create failed: " + e5);
                },
                Ok(j) => {
                  let valid = !is_null_joint_id(j);
                  destroy_world(w);
                  return assert(valid, "revolute joint valid");
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
// TEST: Ray Cast
// ===========================================================================

fn test_ray_cast() -> TestResult {
  let world = create_world(0.0, -10.0);
  match world {
    Err(e) => return assert(false, "world create failed: " + e),
    Ok(w) => {
      // Ground at y = -1
      let ground = create_ground_box(w, 0.0, -1.0, 20.0, 1.0, 0.0);
      match ground {
        Err(e2) => {
          destroy_world(w);
          return assert(false, "ground create failed: " + e2);
        },
        Ok(_) => {}
      }

      // Ray cast straight down from (0, 5)
      let hit = ray_cast_closest(w, 0.0, 5.0, 0.0, -10.0);
      match hit {
        None => {
          destroy_world(w);
          return assert(false, "ray cast missed ground");
        },
        Some(_) => {
          destroy_world(w);
          return assert(true, "ray cast hit ground");
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
    test_ray_cast,
  ];

  var failed = run_all(tests);

  if failed > 0 {
    return 1;
  }
  return 0;
}
