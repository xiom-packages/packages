// XIOM — Jolt Physics Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Covers all public functions in xiom.jolt_safe and xiom.jolt.
// Test convention: return 0 = pass, non-zero = fail.
module jolt_conformance_test
use xiom.jolt;
use xiom.jolt_safe;

fn setup_world() -> World
  ensures: result != 0
{
  let r = world_new(1024, 1024, 1024);
  match r {
    Ok(w) => { return w; };
    Err(_e) => { return 0; };
  };
}

fn cleanup_world(world: World) {
  if world != 0 { let _ = world_destroy(world); };
}

fn test_vec3_create() -> Int
  ensures: result == 0
{
  let v = math_vec3(1.0, 2.0, 3.0);
  if v.x == 1.0 && v.y == 2.0 && v.z == 3.0 { return 0; };
  return 1;
}

fn test_quat_identity() -> Int
  ensures: result == 0
{
  let q = math_quat_identity();
  if q.x == 0.0 && q.y == 0.0 && q.z == 0.0 && q.w == 1.0 { return 0; };
  return 1;
}

fn test_quat_identity_q() -> Int
  ensures: result == 0
{
  let (x, y, z, w) = math_quat_identity_q();
  if x == 0.0 && y == 0.0 && z == 0.0 && w == 1.0 { return 0; };
  return 1;
}

fn test_math_vec3_length() -> Int
  ensures: result == 0
{
  let v = math_vec3(3.0, 0.0, 0.0);
  let len = math_vec3_length(v);
  if len > 2.9 && len < 3.1 { return 0; };
  return 1;
}

fn test_math_vec3_length_zero() -> Int
  ensures: result == 0
{
  let v = math_vec3(0.0, 0.0, 0.0);
  let len = math_vec3_length(v);
  if len == 0.0 { return 0; };
  return 1;
}

fn test_math_vec3_normalize() -> Int
  ensures: result == 0
{
  let v = math_vec3(5.0, 0.0, 0.0);
  let n = math_vec3_normalize(v);
  let len = math_vec3_length(n);
  if len > 0.99 && len < 1.01 { return 0; };
  return 1;
}

fn test_math_quat_axis_angle() -> Int
  ensures: result == 0
{
  let axis = math_vec3(0.0, 1.0, 0.0);
  let q = math_quat_axis_angle(axis, 0.0);
  if q.x == 0.0 && q.w == 1.0 { return 0; };
  return 1;
}

fn test_constants_motion() -> Int
  ensures: result == 0
{
  if MOTION_STATIC == 0 && MOTION_KINEMATIC == 1 && MOTION_DYNAMIC == 2 { return 0; };
  return 1;
}

fn test_constants_layers() -> Int
  ensures: result == 0
{
  if LAYER_NON_MOVING == 0 && LAYER_MOVING == 1 { return 0; };
  return 1;
}

fn test_constants_activation() -> Int
  ensures: result == 0
{
  if ACTIVATE_VAL == 0 && DONT_ACTIVATE_VAL == 1 { return 0; };
  return 1;
}

fn test_world_new() -> Int
  ensures: result == 0
{
  let r = world_new(1024, 1024, 1024);
  match r {
    Ok(w) => {
      if w == 0 { return 1; };
      let _ = world_destroy(w);
      return 0;
    };
    Err(_e) => { return 1; };
  };
}

fn test_world_new_zero_bodies() -> Int
  ensures: result == 1
{
  let r = world_new(0, 1024, 1024);
  match r {
    Ok(_w) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_world_new_negative_bodies() -> Int
  ensures: result == 1
{
  let r = world_new(-1, 1024, 1024);
  match r {
    Ok(_w) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_world_destroy() -> Int
  ensures: result == 0
{
  let r = world_new(1024, 1024, 1024);
  match r {
    Ok(w) => {
      let dr = world_destroy(w);
      match dr {
        Ok(_) => { return 0; };
        Err(_e) => { return 1; };
      };
    };
    Err(_e) => { return 1; };
  };
}

fn test_world_destroy_twice() -> Int
  ensures: result == 0
{
  let r = world_new(1024, 1024, 1024);
  match r {
    Ok(w) => {
      let _ = world_destroy(w);
      let dr2 = world_destroy(w);
      match dr2 {
        Ok(_) => { return 1; };
        Err(_e) => { return 0; };
      };
    };
    Err(_e) => { return 1; };
  };
}

fn test_world_destroy_null() -> Int
  ensures: result == 0
{
  let r = world_destroy(0);
  match r {
    Ok(_) => { return 1; };
    Err(_e) => { return 0; };
  };
}

fn test_world_gravity() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let _ = world_set_gravity(w, 0.0, -20.0, 0.0);
  let gr = world_get_gravity(w);
  cleanup_world(w);
  match gr {
    Ok(g) => {
      if g.y < -19.9 && g.y > -20.1 { return 0; };
      return 1;
    };
    Err(_e) => { return 1; };
  };
}

fn test_world_get_gravity_null() -> Int
  ensures: result == 0
{
  let r = world_get_gravity(0);
  match r {
    Ok(_g) => { return 1; };
    Err(_e) => { return 0; };
  };
}

fn test_world_set_gravity_null() -> Int
  ensures: result == 0
{
  let r = world_set_gravity(0, 0.0, -9.81, 0.0);
  match r {
    Ok(_) => { return 1; };
    Err(_e) => { return 0; };
  };
}

fn test_world_step_positive_dt() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let r = world_step(w, 0.016, 1);
  cleanup_world(w);
  match r {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_world_step_zero_dt() -> Int
  ensures: result == 1
{
  let w = setup_world();
  if w == 0 { return 1; };
  let r = world_step(w, 0.0, 1);
  cleanup_world(w);
  match r {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_world_step_negative_dt() -> Int
  ensures: result == 1
{
  let w = setup_world();
  if w == 0 { return 1; };
  let r = world_step(w, -0.016, 1);
  cleanup_world(w);
  match r {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_world_step_null() -> Int
  ensures: result == 0
{
  let r = world_step(0, 0.016, 1);
  match r {
    Ok(_) => { return 1; };
    Err(_e) => { return 0; };
  };
}

fn test_world_body_count() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let r = world_body_count(w);
  cleanup_world(w);
  match r {
    Ok(count) => {
      if count >= 0 { return 0; };
      return 1;
    };
    Err(_e) => { return 1; };
  };
}

fn test_world_body_count_null() -> Int
  ensures: result == 0
{
  let r = world_body_count(0);
  match r {
    Ok(_) => { return 1; };
    Err(_e) => { return 0; };
  };
}

fn test_world_active_body_count() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let r = world_active_body_count(w);
  cleanup_world(w);
  match r {
    Ok(count) => {
      if count >= 0 { return 0; };
      return 1;
    };
    Err(_e) => { return 1; };
  };
}

fn test_world_optimize() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let r = world_optimize(w);
  cleanup_world(w);
  match r {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_world_optimize_null() -> Int
  ensures: result == 0
{
  let r = world_optimize(0);
  match r {
    Ok(_) => { return 1; };
    Err(_e) => { return 0; };
  };
}

fn test_world_contact_query_null() -> Int
  ensures: result == 0
{
  let r = world_were_bodies_in_contact(0, 1, 2);
  match r {
    Ok(_) => { return 1; };
    Err(_e) => { return 0; };
  };
}

fn test_shape_sphere() -> Int
  ensures: result == 0
{
  let s = shape_sphere(1.0);
  match s {
    Ok(shape) => {
      if shape == 0 { return 1; };
      return 0;
    };
    Err(_e) => { return 1; };
  };
}

fn test_shape_sphere_zero_radius() -> Int
  ensures: result == 1
{
  let s = shape_sphere(0.0);
  match s {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_shape_sphere_negative_radius() -> Int
  ensures: result == 1
{
  let s = shape_sphere(-1.0);
  match s {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_shape_box() -> Int
  ensures: result == 0
{
  let s = shape_box(1.0, 1.0, 1.0);
  match s {
    Ok(shape) => {
      if shape == 0 { return 1; };
      return 0;
    };
    Err(_e) => { return 1; };
  };
}

fn test_shape_box_zero_half_extent() -> Int
  ensures: result == 1
{
  let s = shape_box(0.0, 1.0, 1.0);
  match s {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_shape_box_negative_half_extent() -> Int
  ensures: result == 1
{
  let s = shape_box(-1.0, 1.0, 1.0);
  match s {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_shape_capsule() -> Int
  ensures: result == 0
{
  let s = shape_capsule(1.0, 0.5);
  match s {
    Ok(shape) => {
      if shape == 0 { return 1; };
      return 0;
    };
    Err(_e) => { return 1; };
  };
}

fn test_shape_capsule_zero_radius() -> Int
  ensures: result == 1
{
  let s = shape_capsule(1.0, 0.0);
  match s {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_shape_capsule_zero_height() -> Int
  ensures: result == 1
{
  let s = shape_capsule(0.0, 0.5);
  match s {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_shape_cylinder() -> Int
  ensures: result == 0
{
  let s = shape_cylinder(1.0, 0.5);
  match s {
    Ok(shape) => {
      if shape == 0 { return 1; };
      return 0;
    };
    Err(_e) => { return 1; };
  };
}

fn test_shape_cylinder_zero_radius() -> Int
  ensures: result == 1
{
  let s = shape_cylinder(1.0, 0.0);
  match s {
    Ok(_) => { return 0; };
    Err(_e) => { return 1; };
  };
}

fn test_shape_plane_up() -> Int
  ensures: result == 0
{
  let s = shape_plane(0.0, 1.0, 0.0, 0.0);
  match s {
    Ok(shape) => {
      if shape == 0 { return 1; };
      return 0;
    };
    Err(_e) => { return 1; };
  };
}

fn test_shape_plane_flat() -> Int
  ensures: result == 0
{
  let s = shape_plane(0.0, 1.0, 0.0, -5.0);
  match s {
    Ok(shape) => {
      if shape == 0 { return 1; };
      return 0;
    };
    Err(_e) => { return 1; };
  };
}

fn test_body_settings_new() -> Int
  ensures: result == 0
{
  let r = body_settings_new();
  match r {
    Ok(s) => {
      if s == 0 { return 1; };
      return 0;
    };
    Err(_e) => { return 1; };
  };
}

fn test_body_settings_chain() -> Int
  ensures: result == 0
{
  let r = body_settings_new();
  match r {
    Ok(s) => {
      let s = body_settings_motion_type(s, MOTION_STATIC);
      match s {
        Ok(s2) => {
          let s2 = body_settings_friction(s2, 0.5);
          match s2 {
            Ok(s3) => {
              let s3 = body_settings_restitution(s3, 0.3);
              match s3 {
                Ok(s4) => {
                  let s4 = body_settings_gravity_factor(s4, 1.0);
                  match s4 {
                    Ok(s5) => {
                      if s5 != 0 { return 0; };
                      return 1;
                    };
                    Err(_) => { return 1; };
                  };
                };
                Err(_) => { return 1; };
              };
            };
            Err(_) => { return 1; };
          };
        };
        Err(_) => { return 1; };
      };
    };
    Err(_e) => { return 1; };
  };
}

fn test_body_settings_layer() -> Int
  ensures: result == 0
{
  let r = body_settings_new();
  match r {
    Ok(s) => {
      let s = body_settings_layer(s, LAYER_NON_MOVING);
      match s {
        Ok(_s) => { return 0; };
        Err(_) => { return 1; };
      };
    };
    Err(_e) => { return 1; };
  };
}

fn test_body_settings_linear_damping() -> Int
  ensures: result == 0
{
  let r = body_settings_new();
  match r {
    Ok(s) => {
      let s = body_settings_linear_damping(s, 0.1);
      match s {
        Ok(_s) => { return 0; };
        Err(_) => { return 1; };
      };
    };
    Err(_e) => { return 1; };
  };
}

fn test_body_settings_position() -> Int
  ensures: result == 0
{
  let r = body_settings_new();
  match r {
    Ok(s) => {
      let s = body_settings_position(s, math_vec3(5.0, 10.0, -3.0));
      match s {
        Ok(_s) => { return 0; };
        Err(_) => { return 1; };
      };
    };
    Err(_e) => { return 1; };
  };
}

fn test_body_settings_rotation() -> Int
  ensures: result == 0
{
  let r = body_settings_new();
  match r {
    Ok(s) => {
      let axis = math_vec3(0.0, 1.0, 0.0);
      let q = math_quat_axis_angle(axis, 1.57);
      let s = body_settings_rotation(s, q);
      match s {
        Ok(_s) => { return 0; };
        Err(_) => { return 1; };
      };
    };
    Err(_e) => { return 1; };
  };
}

fn test_body_settings_velocity() -> Int
  ensures: result == 0
{
  let r = body_settings_new();
  match r {
    Ok(s) => {
      let s = body_settings_velocity(s, math_vec3(1.0, 0.0, 0.0));
      match s {
        Ok(_s) => { return 0; };
        Err(_) => { return 1; };
      };
    };
    Err(_e) => { return 1; };
  };
}

fn test_body_create_destroy() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_sphere(1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_position(bcs2, math_vec3(0.0, 5.0, 0.0));
              match bcs2 {
                Ok(bcs3) => {
                  let bcs3 = body_settings_motion_type(bcs3, MOTION_DYNAMIC);
                  match bcs3 {
                    Ok(bcs4) => {
                      let body_r = body_create(w, bcs4, true);
                      match body_r {
                        Ok(_bid) => {
                          let _ = world_step(w, 0.016, 1);
                          cleanup_world(w);
                          return 0;
                        };
                        Err(_e) => { cleanup_world(w); return 1; };
                      };
                    };
                    Err(_) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_position() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_sphere(1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_position(bcs2, math_vec3(3.0, 5.0, 7.0));
              match bcs2 {
                Ok(bcs3) => {
                  let bcs3 = body_settings_motion_type(bcs3, MOTION_KINEMATIC);
                  match bcs3 {
                    Ok(bcs4) => {
                      let body_r = body_create(w, bcs4, true);
                      match body_r {
                        Ok(bid) => {
                          let pr = body_position(w, bid);
                          cleanup_world(w);
                          match pr {
                            Ok(p) => {
                              if p.x > 2.9 && p.x < 3.1 &&
                                 p.y > 4.9 && p.y < 5.1 &&
                                 p.z > 6.9 && p.z < 7.1 { return 0; };
                              return 1;
                            };
                            Err(_) => { return 1; };
                          };
                        };
                        Err(_e) => { cleanup_world(w); return 1; };
                      };
                    };
                    Err(_) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_rotation() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_box(1.0, 1.0, 1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_motion_type(bcs2, MOTION_STATIC);
              match bcs2 {
                Ok(bcs3) => {
                  let body_r = body_create(w, bcs3, false);
                  match body_r {
                    Ok(bid) => {
                      let rr = body_rotation(w, bid);
                      cleanup_world(w);
                      match rr {
                        Ok(_q) => { return 0; };
                        Err(_) => { return 1; };
                      };
                    };
                    Err(_e) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_velocity() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_sphere(1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_position(bcs2, math_vec3(0.0, 5.0, 0.0));
              match bcs2 {
                Ok(bcs3) => {
                  let bcs3 = body_settings_motion_type(bcs3, MOTION_DYNAMIC);
                  match bcs3 {
                    Ok(bcs4) => {
                      let body_r = body_create(w, bcs4, true);
                      match body_r {
                        Ok(bid) => {
                          let _ = world_step(w, 0.016, 1);
                          let vr = body_velocity(w, bid);
                          cleanup_world(w);
                          match vr {
                            Ok(_v) => { return 0; };
                            Err(_) => { return 1; };
                          };
                        };
                        Err(_e) => { cleanup_world(w); return 1; };
                      };
                    };
                    Err(_) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_set_velocity() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_sphere(1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_position(bcs2, math_vec3(0.0, 5.0, 0.0));
              match bcs2 {
                Ok(bcs3) => {
                  let bcs3 = body_settings_motion_type(bcs3, MOTION_DYNAMIC);
                  match bcs3 {
                    Ok(bcs4) => {
                      let body_r = body_create(w, bcs4, true);
                      match body_r {
                        Ok(bid) => {
                          let vr = body_set_velocity(w, bid, math_vec3(10.0, 0.0, 0.0));
                          let _ = world_step(w, 0.016, 1);
                          let vr2 = body_velocity(w, bid);
                          cleanup_world(w);
                          match vr {
                            Ok(_) => {
                              match vr2 {
                                Ok(v) => {
                                  if v.x > 0.0 { return 0; };
                                  return 1;
                                };
                                Err(_) => { return 1; };
                              };
                            };
                            Err(_) => { return 1; };
                          };
                        };
                        Err(_e) => { cleanup_world(w); return 1; };
                      };
                    };
                    Err(_) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_set_position() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_box(1.0, 1.0, 1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_motion_type(bcs2, MOTION_KINEMATIC);
              match bcs2 {
                Ok(bcs3) => {
                  let body_r = body_create(w, bcs3, true);
                  match body_r {
                    Ok(bid) => {
                      let new_pos = math_vec3(10.0, 0.0, 0.0);
                      let rot = math_quat_identity();
                      let pr = body_set_position(w, bid, new_pos, rot, ACTIVATE_VAL);
                      let _ = world_step(w, 0.016, 1);
                      cleanup_world(w);
                      match pr {
                        Ok(_) => { return 0; };
                        Err(_) => { return 1; };
                      };
                    };
                    Err(_e) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_apply_force() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_sphere(1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_position(bcs2, math_vec3(0.0, 10.0, 0.0));
              match bcs2 {
                Ok(bcs3) => {
                  let bcs3 = body_settings_motion_type(bcs3, MOTION_DYNAMIC);
                  match bcs3 {
                    Ok(bcs4) => {
                      let body_r = body_create(w, bcs4, true);
                      match body_r {
                        Ok(bid) => {
                          let fr = body_apply_force(w, bid, math_vec3(0.0, -100.0, 0.0));
                          let _ = world_step(w, 0.016, 1);
                          cleanup_world(w);
                          match fr {
                            Ok(_) => { return 0; };
                            Err(_) => { return 1; };
                          };
                        };
                        Err(_e) => { cleanup_world(w); return 1; };
                      };
                    };
                    Err(_) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_apply_impulse() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_sphere(1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_position(bcs2, math_vec3(0.0, 10.0, 0.0));
              match bcs2 {
                Ok(bcs3) => {
                  let bcs3 = body_settings_motion_type(bcs3, MOTION_DYNAMIC);
                  match bcs3 {
                    Ok(bcs4) => {
                      let body_r = body_create(w, bcs4, true);
                      match body_r {
                        Ok(bid) => {
                          let ir = body_apply_impulse(w, bid, math_vec3(0.0, 50.0, 0.0));
                          let _ = world_step(w, 0.016, 1);
                          cleanup_world(w);
                          match ir {
                            Ok(_) => { return 0; };
                            Err(_) => { return 1; };
                          };
                        };
                        Err(_e) => { cleanup_world(w); return 1; };
                      };
                    };
                    Err(_) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_is_active() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_sphere(1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_position(bcs2, math_vec3(0.0, 5.0, 0.0));
              match bcs2 {
                Ok(bcs3) => {
                  let bcs3 = body_settings_motion_type(bcs3, MOTION_DYNAMIC);
                  match bcs3 {
                    Ok(bcs4) => {
                      let body_r = body_create(w, bcs4, true);
                      match body_r {
                        Ok(bid) => {
                          let ar = body_is_active(w, bid);
                          cleanup_world(w);
                          match ar {
                            Ok(_active) => { return 0; };
                            Err(_) => { return 1; };
                          };
                        };
                        Err(_e) => { cleanup_world(w); return 1; };
                      };
                    };
                    Err(_) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_friction() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_box(1.0, 1.0, 1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_motion_type(bcs2, MOTION_STATIC);
              match bcs2 {
                Ok(bcs3) => {
                  let body_r = body_create(w, bcs3, false);
                  match body_r {
                    Ok(bid) => {
                      let fr = body_set_friction(w, bid, 0.8);
                      cleanup_world(w);
                      match fr {
                        Ok(_) => { return 0; };
                        Err(_) => { return 1; };
                      };
                    };
                    Err(_e) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_restitution() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_box(1.0, 1.0, 1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_motion_type(bcs2, MOTION_STATIC);
              match bcs2 {
                Ok(bcs3) => {
                  let body_r = body_create(w, bcs3, false);
                  match body_r {
                    Ok(bid) => {
                      let rr = body_set_restitution(w, bid, 0.9);
                      cleanup_world(w);
                      match rr {
                        Ok(_) => { return 0; };
                        Err(_) => { return 1; };
                      };
                    };
                    Err(_e) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_body_remove_destroy() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let sr = shape_sphere(1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_motion_type(bcs2, MOTION_STATIC);
              match bcs2 {
                Ok(bcs3) => {
                  let body_r = body_create(w, bcs3, false);
                  match body_r {
                    Ok(bid) => {
                      let rr = body_remove(w, bid);
                      let _ = world_step(w, 0.016, 1);
                      let dr = body_destroy(w, bid);
                      cleanup_world(w);
                      match rr {
                        Ok(_) => {
                          match dr {
                            Ok(_) => { return 0; };
                            Err(_) => { return 1; };
                          };
                        };
                        Err(_) => { return 1; };
                      };
                    };
                    Err(_e) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_simulation_gravity_drop() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let _ = world_set_gravity(w, 0.0, -9.81, 0.0);
  let sr = shape_sphere(1.0);
  match sr {
    Ok(shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_position(bcs2, math_vec3(0.0, 10.0, 0.0));
              match bcs2 {
                Ok(bcs3) => {
                  let bcs3 = body_settings_motion_type(bcs3, MOTION_DYNAMIC);
                  match bcs3 {
                    Ok(bcs4) => {
                      let body_r = body_create(w, bcs4, true);
                      match body_r {
                        Ok(_bid) => {
                          let _ = world_step(w, 0.016, 2);
                          cleanup_world(w);
                          return 0;
                        };
                        Err(_e) => { cleanup_world(w); return 1; };
                      };
                    };
                    Err(_) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_e) => { cleanup_world(w); return 1; };
      };
    };
    Err(_e) => { cleanup_world(w); return 1; };
  };
}

fn test_simulation_ground_and_ball() -> Int
  ensures: result == 0
{
  let w = setup_world();
  if w == 0 { return 1; };
  let _ = world_set_gravity(w, 0.0, -9.81, 0.0);
  let sr = shape_plane(0.0, 1.0, 0.0, 0.0);
  match sr {
    Ok(ground_shape) => {
      let br = body_settings_new();
      match br {
        Ok(bcs) => {
          let bcs = body_settings_shape(bcs, ground_shape);
          match bcs {
            Ok(bcs2) => {
              let bcs2 = body_settings_motion_type(bcs2, MOTION_STATIC);
              match bcs2 {
                Ok(bcs3) => {
                  let body_r = body_create(w, bcs3, false);
                  match body_r {
                    Ok(_ground_id) => {
                      let br2 = shape_sphere(0.5);
                      match br2 {
                        Ok(ball_shape) => {
                          let br3 = body_settings_new();
                          match br3 {
                            Ok(bcs4) => {
                              let bcs4 = body_settings_shape(bcs4, ball_shape);
                              match bcs4 {
                                Ok(bcs5) => {
                                  let bcs5 = body_settings_position(bcs5, math_vec3(0.0, 5.0, 0.0));
                                  match bcs5 {
                                    Ok(bcs6) => {
                                      let bcs6 = body_settings_motion_type(bcs6, MOTION_DYNAMIC);
                                      match bcs6 {
                                        Ok(bcs7) => {
                                          let body_r2 = body_create(w, bcs7, true);
                                          match body_r2 {
                                            Ok(_bid2) => {
                                              let _ = world_step(w, 0.016, 2);
                                              cleanup_world(w);
                                              return 0;
                                            };
                                            Err(_) => { cleanup_world(w); return 1; };
                                          };
                                        };
                                        Err(_) => { cleanup_world(w); return 1; };
                                      };
                                    };
                                    Err(_) => { cleanup_world(w); return 1; };
                                  };
                                };
                                Err(_) => { cleanup_world(w); return 1; };
                              };
                            };
                            Err(_) => { cleanup_world(w); return 1; };
                          };
                        };
                        Err(_) => { cleanup_world(w); return 1; };
                      };
                    };
                    Err(_) => { cleanup_world(w); return 1; };
                  };
                };
                Err(_) => { cleanup_world(w); return 1; };
              };
            };
            Err(_) => { cleanup_world(w); return 1; };
          };
        };
        Err(_) => { cleanup_world(w); return 1; };
      };
    };
    Err(_) => { cleanup_world(w); return 1; };
  };
}

fn test_jolt_math_vec3() -> Int
  ensures: result == 0
{
  let len = vec3_length(3.0, 0.0, 0.0);
  if len > 2.9 && len < 3.1 { return 0; };
  return 1;
}

fn test_jolt_math_dot() -> Int
  ensures: result == 0
{
  let d = vec3_dot(1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
  if d > 0.99 && d < 1.01 { return 0; };
  return 1;
}

fn test_jolt_math_cross() -> Int
  ensures: result == 0
{
  let (cx, cy, cz) = vec3_cross(1.0, 0.0, 0.0, 0.0, 1.0, 0.0);
  if cx < 0.01 && cy < 0.01 && cz > 0.99 && cz < 1.01 { return 0; };
  return 1;
}

fn test_jolt_math_normalize() -> Int
  ensures: result == 0
{
  let (x, y, z) = vec3_normalize(5.0, 0.0, 0.0);
  let len = vec3_length(x, y, z);
  if len > 0.99 && len < 1.01 { return 0; };
  return 1;
}

fn test_jolt_math_slerp() -> Int
  ensures: result == 0
{
  let q1 = quat_s_identity();
  let (q2x, q2y, q2z, q2w) = quat_s_rotation(0.0, 1.0, 0.0, 1.57);
  let (rx, ry, rz, rw) = quat_slerp(q1.0, q1.1, q1.2, q1.3, q2x, q2y, q2z, q2w, 0.5);
  let axis_len = vec3_length(rx, ry, rz);
  if rw > 0.0 && axis_len > 0.0 { return 0; };
  return 1;
}

fn test_jolt_math_negate() -> Int
  ensures: result == 0
{
  let (x, y, z) = vec3_negate(3.0, -2.0, 5.0);
  if x == -3.0 && y == 2.0 && z == -5.0 { return 0; };
  return 1;
}

fn test_jolt_math_euler() -> Int
  ensures: result == 0
{
  let (_x, _y, _z, w) = quat_s_euler_angles(0.0, 0.0, 0.0);
  if w == 1.0 { return 0; };
  return 1;
}

fn test_jolt_math_from_to() -> Int
  ensures: result == 0
{
  let (x, y, z, w) = quat_s_from_to(1.0, 0.0, 0.0, 0.0, 1.0, 0.0);
  let axis_len = vec3_length(x, y, z);
  if axis_len > 0.0 { return 0; };
  return 1;
}

fn test_jolt_init_shutdown() -> Int
  ensures: result == 0
{
  let ok = init();
  if ok {
    shutdown();
    return 0;
  };
  return 1;
}

fn test_jolt_empty_shape() -> Int
  ensures: result == 0
{
  let ss = empty_shape_settings_create();
  if ss == 0 { return 1; };
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  destroy_shape(shape);
  return 0;
}

fn test_jolt_triangle_shape() -> Int
  ensures: result == 0
{
  let ss = triangle_shape_settings_create(
    0.0, 0.0, 0.0,
    1.0, 0.0, 0.0,
    0.0, 1.0, 0.0,
    0.05
  );
  if ss == 0 { return 1; };
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  destroy_shape(shape);
  return 0;
}

fn test_jolt_shape_get_type() -> Int
  ensures: result == 0
{
  let ss = sphere_shape_settings_create(1.0);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let st = shape_get_type(shape);
  let sst = shape_get_sub_type(shape);
  destroy_shape(shape);
  if st == SHAPE_TYPE_CONVEX && sst == SHAPE_SUB_TYPE_SPHERE { return 0; };
  return 1;
}

fn test_jolt_shape_user_data() -> Int
  ensures: result == 0
{
  let ss = box_shape_settings_create(1.0, 1.0, 1.0, 0.05);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  shape_set_user_data(shape, 42);
  let data = shape_get_user_data(shape);
  destroy_shape(shape);
  if data == 42 { return 0; };
  return 1;
}

fn test_jolt_shape_center_of_mass() -> Int
  ensures: result == 0
{
  let ss = sphere_shape_settings_create(1.0);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let (cx, cy, cz) = shape_get_center_of_mass(shape);
  destroy_shape(shape);
  if cx == 0.0 && cy == 0.0 && cz == 0.0 { return 0; };
  return 1;
}

fn test_jolt_shape_volume() -> Int
  ensures: result == 0
{
  let ss = sphere_shape_settings_create(1.0);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let vol = shape_get_volume(shape);
  destroy_shape(shape);
  if vol > 0.0 { return 0; };
  return 1;
}

fn test_jolt_shape_inner_radius() -> Int
  ensures: result == 0
{
  let ss = sphere_shape_settings_create(1.0);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let r = shape_get_inner_radius(shape);
  destroy_shape(shape);
  if r > 0.9 && r < 1.1 { return 0; };
  return 1;
}

fn test_jolt_shape_local_bounds() -> Int
  ensures: result == 0
{
  let ss = sphere_shape_settings_create(1.0);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let (min_x, min_y, min_z, max_x, max_y, max_z) = shape_get_local_bounds(shape);
  destroy_shape(shape);
  if min_x < 0.0 && max_x > 0.0 { return 0; };
  return 1;
}

fn test_jolt_shape_scale() -> Int
  ensures: result == 0
{
  let ss = sphere_shape_settings_create(1.0);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let scaled = shape_scale_shape(shape, 2.0, 2.0, 2.0);
  let vol = shape_get_volume(scaled);
  destroy_shape(scaled);
  destroy_shape(shape);
  if vol > 0.0 { return 0; };
  return 1;
}

fn test_jolt_box_accessors() -> Int
  ensures: result == 0
{
  let ss = box_shape_settings_create(2.0, 3.0, 4.0, 0.05);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let (hx, hy, hz) = box_shape_get_half_extent(shape);
  let _cr = box_shape_get_convex_radius(shape);
  destroy_shape(shape);
  if hx > 1.9 && hx < 2.1 && hy > 2.9 && hy < 3.1 && hz > 3.9 && hz < 4.1 { return 0; };
  return 1;
}

fn test_jolt_sphere_accessor() -> Int
  ensures: result == 0
{
  let ss = sphere_shape_settings_create(1.5);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let r = sphere_shape_get_radius(shape);
  destroy_shape(shape);
  if r > 1.4 && r < 1.6 { return 0; };
  return 1;
}

fn test_jolt_capsule_accessors() -> Int
  ensures: result == 0
{
  let ss = capsule_shape_settings_create(2.0, 0.5);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let r = capsule_shape_get_radius(shape);
  let h = capsule_shape_get_half_height(shape);
  destroy_shape(shape);
  if r > 0.4 && r < 0.6 && h > 1.9 && h < 2.1 { return 0; };
  return 1;
}

fn test_jolt_cylinder_accessors() -> Int
  ensures: result == 0
{
  let ss = cylinder_shape_settings_create(3.0, 1.0, 0.05);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let r = cylinder_shape_get_radius(shape);
  let h = cylinder_shape_get_half_height(shape);
  destroy_shape(shape);
  if r > 0.9 && r < 1.1 && h > 2.9 && h < 3.1 { return 0; };
  return 1;
}

fn test_jolt_tapered_capsule_accessors() -> Int
  ensures: result == 0
{
  let ss = tapered_capsule_shape_settings_create(2.0, 0.5, 0.3);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let tr = tapered_capsule_shape_get_top_radius(shape);
  let br = tapered_capsule_shape_get_bottom_radius(shape);
  let hh = tapered_capsule_shape_get_half_height(shape);
  destroy_shape(shape);
  if tr > 0.4 && tr < 0.6 && br > 0.2 && br < 0.4 && hh > 1.9 && hh < 2.1 { return 0; };
  return 1;
}

fn test_jolt_tapered_cylinder_accessors() -> Int
  ensures: result == 0
{
  let ss = tapered_cylinder_shape_settings_create(2.0, 0.5, 0.3, 0.05);
  let shape = shape_settings_create_shape(ss);
  if shape == 0 { return 1; };
  let tr = tapered_cylinder_shape_get_top_radius(shape);
  let br = tapered_cylinder_shape_get_bottom_radius(shape);
  let hh = tapered_cylinder_shape_get_half_height(shape);
  destroy_shape(shape);
  if tr > 0.4 && tr < 0.6 && br > 0.2 && br < 0.4 && hh > 1.9 && hh < 2.1 { return 0; };
  return 1;
}

fn test_jolt_scaled_shape() -> Int
  ensures: result == 0
{
  let ss = sphere_shape_settings_create(1.0);
  let inner = shape_settings_create_shape(ss);
  let dss = scaled_shape_settings_create(inner, 2.0, 3.0, 4.0);
  let decorated = shape_settings_create_shape(dss);
  let (sx, sy, sz) = scaled_shape_get_scale(decorated);
  let inner2 = decorated_shape_get_inner_shape(decorated);
  destroy_shape(decorated);
  destroy_shape(inner);
  destroy_shape(inner2);
  if sx > 1.9 && sx < 2.1 && sy > 2.9 && sy < 3.1 && sz > 3.9 && sz < 4.1 { return 0; };
  return 1;
}

fn test_jolt_offset_com_shape() -> Int
  ensures: result == 0
{
  let ss = sphere_shape_settings_create(1.0);
  let inner = shape_settings_create_shape(ss);
  let dss = offset_center_of_mass_shape_settings_create(inner, 0.5, 0.0, 0.0);
  let decorated = shape_settings_create_shape(dss);
  let (ox, oy, oz) = offset_center_of_mass_shape_get_offset(decorated);
  let inner2 = decorated_shape_get_inner_shape(decorated);
  destroy_shape(decorated);
  destroy_shape(inner);
  destroy_shape(inner2);
  if ox > 0.4 && ox < 0.6 && oy == 0.0 && oz == 0.0 { return 0; };
  return 1;
}

fn test_jolt_rotated_translated_shape() -> Int
  ensures: result == 0
{
  let ss = sphere_shape_settings_create(1.0);
  let inner = shape_settings_create_shape(ss);
  let (iqx, iqy, iqz, iqw) = quat_s_identity();
  let dss = rotated_translated_shape_settings_create(inner, 1.0, 2.0, 3.0, iqx, iqy, iqz, iqw);
  let decorated = shape_settings_create_shape(dss);
  let (px, py, pz) = rotated_translated_shape_get_position(decorated);
  let (qx, qy, qz, qw) = rotated_translated_shape_get_rotation(decorated);
  let inner2 = decorated_shape_get_inner_shape(decorated);
  destroy_shape(decorated);
  destroy_shape(inner);
  destroy_shape(inner2);
  if px > 0.9 && px < 1.1 && py > 1.9 && py < 2.1 && pz > 2.9 && pz < 3.1 && qw == 1.0 { return 0; };
  return 1;
}

fn test_jolt_constraint_fixed_create() -> Int
  ensures: result == 0
{
  let cs = fixed_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_constraint_point_create() -> Int
  ensures: result == 0
{
  let cs = point_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_constraint_distance_create() -> Int
  ensures: result == 0
{
  let cs = distance_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_constraint_hinge_create() -> Int
  ensures: result == 0
{
  let cs = hinge_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_constraint_slider_create() -> Int
  ensures: result == 0
{
  let cs = slider_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_constraint_cone_create() -> Int
  ensures: result == 0
{
  let cs = cone_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_constraint_swing_twist_create() -> Int
  ensures: result == 0
{
  let cs = swing_twist_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_constraint_six_dof_create() -> Int
  ensures: result == 0
{
  let cs = six_dof_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_constraint_gear_create() -> Int
  ensures: result == 0
{
  let cs = gear_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_constraint_rack_pinion_create() -> Int
  ensures: result == 0
{
  let cs = rack_and_pinion_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_constraint_pulley_create() -> Int
  ensures: result == 0
{
  let cs = pulley_constraint_settings_create();
  if cs != 0 {
    destroy_constraint_settings(cs);
    return 0;
  };
  return 1;
}

fn test_jolt_physics_material() -> Int
  ensures: result == 0
{
  let m = physics_material_create(0.8, 0.2);
  if m == 0 { return 1; };
  let f = physics_material_get_friction(m);
  let r = physics_material_get_restitution(m);
  destroy_physics_material(m);
  if f > 0.7 && f < 0.9 && r > 0.1 && r < 0.3 { return 0; };
  return 1;
}

fn test_jolt_group_filter() -> Int
  ensures: result == 0
{
  let gf = group_filter_table_create(4);
  if gf == 0 { return 1; };
  group_filter_table_disable_collision(gf, 0, 1);
  group_filter_table_enable_collision(gf, 0, 2);
  let cg = collision_group_create(gf, 0, 0);
  destroy_group_filter(gf);
  if cg != 0 { return 0; };
  return 1;
}

fn test_jolt_narrow_phase_query_exists() -> Int
  ensures: result == 0
{
  let ok = init();
  if !ok { return 1; };
  let bp1 = create_broad_phase_layer_interface_table(2, 2);
  let bp2 = create_broad_phase_layer_interface_table(2, 2);
  let obj1 = create_object_layer_pair_filter_table(2);
  let obj2 = create_object_layer_pair_filter_table(2);
  let ovs = create_object_vs_broad_phase_layer_filter_table(bp2, 2, obj2, 2);
  let world = create_physics_system(1024, 0, 1024, 1024, bp1, ovs, obj1);
  if world == 0 { shutdown(); return 1; };
  let narrow = physics_system_get_narrow_phase_query(world);
  destroy_physics_system(world);
  shutdown();
  // Verify narrow query interface is reachable (no crash)
  if narrow != 0 { return 0; };
  return 1;
}

fn test_jolt_skeleton() -> Int
  ensures: result == 0
{
  let sk = skeleton_create();
  if sk == 0 { return 1; };
  let root = skeleton_add_joint(sk, "root", "");
  let child = skeleton_add_joint(sk, "spine", "root");
  let count = skeleton_get_joint_count(sk);
  destroy_skeleton(sk);
  if root >= 0 && child >= 0 && count == 2 { return 0; };
  return 1;
}

// ============================================================================
// Test runner
// ============================================================================

fn main() -> Int {
  var passed: Int = 0;
  var total: Int = 0;

  total = total + 1; if test_vec3_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_quat_identity() == 0 { passed = passed + 1; };
  total = total + 1; if test_quat_identity_q() == 0 { passed = passed + 1; };
  total = total + 1; if test_math_vec3_length() == 0 { passed = passed + 1; };
  total = total + 1; if test_math_vec3_length_zero() == 0 { passed = passed + 1; };
  total = total + 1; if test_math_vec3_normalize() == 0 { passed = passed + 1; };
  total = total + 1; if test_math_quat_axis_angle() == 0 { passed = passed + 1; };
  total = total + 1; if test_constants_motion() == 0 { passed = passed + 1; };
  total = total + 1; if test_constants_layers() == 0 { passed = passed + 1; };
  total = total + 1; if test_constants_activation() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_new() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_new_zero_bodies() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_new_negative_bodies() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_destroy() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_destroy_twice() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_destroy_null() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_gravity() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_get_gravity_null() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_set_gravity_null() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_step_positive_dt() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_step_zero_dt() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_step_negative_dt() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_step_null() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_body_count() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_body_count_null() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_active_body_count() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_optimize() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_optimize_null() == 0 { passed = passed + 1; };
  total = total + 1; if test_world_contact_query_null() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_sphere() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_sphere_zero_radius() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_sphere_negative_radius() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_box() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_box_zero_half_extent() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_box_negative_half_extent() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_capsule() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_capsule_zero_radius() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_capsule_zero_height() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_cylinder() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_cylinder_zero_radius() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_plane_up() == 0 { passed = passed + 1; };
  total = total + 1; if test_shape_plane_flat() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_settings_new() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_settings_chain() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_settings_layer() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_settings_linear_damping() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_settings_position() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_settings_rotation() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_settings_velocity() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_create_destroy() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_position() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_rotation() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_velocity() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_set_velocity() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_set_position() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_apply_force() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_apply_impulse() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_is_active() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_friction() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_restitution() == 0 { passed = passed + 1; };
  total = total + 1; if test_body_remove_destroy() == 0 { passed = passed + 1; };
  total = total + 1; if test_simulation_gravity_drop() == 0 { passed = passed + 1; };
  total = total + 1; if test_simulation_ground_and_ball() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_math_vec3() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_math_dot() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_math_cross() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_math_normalize() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_math_slerp() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_math_negate() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_math_euler() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_math_from_to() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_init_shutdown() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_empty_shape() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_triangle_shape() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_shape_get_type() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_shape_user_data() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_shape_center_of_mass() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_shape_volume() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_shape_inner_radius() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_shape_local_bounds() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_shape_scale() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_box_accessors() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_sphere_accessor() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_capsule_accessors() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_cylinder_accessors() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_tapered_capsule_accessors() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_tapered_cylinder_accessors() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_scaled_shape() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_offset_com_shape() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_rotated_translated_shape() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_fixed_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_point_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_distance_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_hinge_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_slider_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_cone_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_swing_twist_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_six_dof_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_gear_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_rack_pinion_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_constraint_pulley_create() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_physics_material() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_group_filter() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_narrow_phase_query_exists() == 0 { passed = passed + 1; };
  total = total + 1; if test_jolt_skeleton() == 0 { passed = passed + 1; };

  if passed == total { return 0; };
  return 1;
}
