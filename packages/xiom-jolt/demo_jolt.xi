// XIOM — Jolt Physics Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// NOTE: xiom v0.46.0 treats opaque FFI Int handles as move-only.
// Multi-step builder patterns (calling multiple setters on the same settings
// handle) trigger E001 borrow errors. The safe wrapper (jolt_safe.xi) provides
// one-shot functions that handle setup internally.
// See AUDIT.md for ownership tracker gap documentation.
module jolt_demo
use xiom.jolt;
use xiom.jolt_safe;

fn test_world_new_destroy() -> Int {
  let r = world_new(1024, 1024, 1024);
  match r {
    Ok(world) => {
      let _ = world_destroy(world);
      return 0;
    };
    Err(_e) => { return 1; };
  };
}

fn test_gravity() -> Int {
  let r = world_new(1024, 1024, 1024);
  match r {
    Ok(world) => {
      let _ = world_set_gravity(world, 0.0, -9.81, 0.0);
      let gr = world_get_gravity(world);
      let _ = world_destroy(world);
      match gr {
        Ok(g) => {
          if g.y < -9.0 { return 0; };
          return 1;
        };
        Err(_e) => { return 1; };
      };
    };
    Err(_e) => { return 1; };
  };
}

fn test_sphere_shape() -> Int {
  let s = shape_sphere(1.0);
  match s {
    Ok(shape) => {
      if shape != 0 { return 0; };
      return 1;
    };
    Err(_e) => { return 1; };
  };
}

fn test_box_shape() -> Int {
  let s = shape_box(1.0, 1.0, 1.0);
  match s {
    Ok(shape) => {
      if shape != 0 { return 0; };
      return 1;
    };
    Err(_e) => { return 1; };
  };
}

fn test_capsule_shape() -> Int {
  let s = shape_capsule(1.0, 0.5);
  match s {
    Ok(shape) => {
      if shape != 0 { return 0; };
      return 1;
    };
    Err(_e) => { return 1; };
  };
}

fn test_plane_shape() -> Int {
  let s = shape_plane(0.0, 1.0, 0.0, 0.0);
  match s {
    Ok(shape) => {
      if shape != 0 { return 0; };
      return 1;
    };
    Err(_e) => { return 1; };
  };
}

fn test_math() -> Int {
  let v = math_vec3(1.0, 2.0, 3.0);
  let len = math_vec3_length(v);
  if len > 0.0 { return 0; };
  return 1;
}

fn main() -> Int {
  var passed: Int = 0;
  if test_world_new_destroy() == 0 { passed = passed + 1; };
  if test_gravity() == 0 { passed = passed + 1; };
  if test_sphere_shape() == 0 { passed = passed + 1; };
  if test_box_shape() == 0 { passed = passed + 1; };
  if test_capsule_shape() == 0 { passed = passed + 1; };
  if test_plane_shape() == 0 { passed = passed + 1; };
  if test_body_create() == 0 { passed = passed + 1; };
  if test_math() == 0 { passed = passed + 1; };
  if passed == 8 { return 0; };
  return 1;
}
