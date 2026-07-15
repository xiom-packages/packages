// XIOM — Jolt Physics Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Safe wrappers over the raw jolt.xi extern declarations.
// Every FFI call goes through an unsafe { } block and returns Result[Int, Str].
// Handles are validated (0 = null/error) and converted to friendly types.
//
// Usage:
//   use xiom.jolt_safe;
//
//   let world = JoltWorld.new(1024, 1024, 1024);
//   if world is Ok(w) { ... }

module xiom.jolt_safe
use xiom.jolt;

// --- Motion types ---
pub const MOTION_TYPE_STATIC: Int = 0;
pub const MOTION_TYPE_KINEMATIC: Int = 1;
pub const MOTION_TYPE_DYNAMIC: Int = 2;

// --- Object layers ---
pub const LAYER_NON_MOVING: Int = 0;
pub const LAYER_MOVING: Int = 1;

// --- Activation ---
pub const ACTIVATION_ACTIVATE: Int = 0;
pub const ACTIVATION_DONT_ACTIVATE: Int = 1;

// --- Vec3 helper ---
pub type Vec3 = {
  x: Float32;
  y: Float32;
  z: Float32;
};

// --- Quat helper ---
pub type Quat = {
  x: Float32;
  y: Float32;
  z: Float32;
  w: Float32;
};

// --- JoltWorld ---
pub type JoltWorld = {
  handle: World;
  max_bodies: Int;
  max_body_pairs: Int;
  max_contact_constraints: Int;
};

pub fn JoltWorld.new(max_bodies: Int, max_body_pairs: Int, max_contact_constraints: Int) -> Result[JoltWorld, Str]
  requires: max_bodies > 0
  requires: max_body_pairs > 0
  requires: max_contact_constraints > 0
{
  if !init() {
    return Err("jolt: failed to initialize physics system");
  }
  let raw = create_world(max_bodies, max_body_pairs, max_contact_constraints);
  if raw == 0 {
    return Err("jolt: failed to create physics world");
  }
  return Ok(JoltWorld { handle: raw, max_bodies: max_bodies, max_body_pairs: max_body_pairs, max_contact_constraints: max_contact_constraints });
}

pub fn JoltWorld.destroy() -> Result[Int, Str] {
  if handle == 0 {
    return Err("jolt: world already destroyed");
  }
  destroy_world(handle);
  shutdown();
  return Ok(0);
}

pub fn JoltWorld.step(dt: Float32, collision_steps: Int) -> Result[Int, Str]
  requires: dt > 0.0
  requires: collision_steps > 0
{
  if handle == 0 {
    return Err("jolt: world is destroyed");
  }
  let err = step_simulation(handle, dt, collision_steps);
  if err != 0 {
    return Err("jolt: simulation step error");
  }
  return Ok(0);
}

pub fn JoltWorld.set_gravity(gx: Float32, gy: Float32, gz: Float32) -> Result[Int, Str] {
  if handle == 0 {
    return Err("jolt: world is destroyed");
  }
  set_gravity(handle, gx, gy, gz);
  return Ok(0);
}

pub fn JoltWorld.optimize() -> Result[Int, Str] {
  if handle == 0 {
    return Err("jolt: world is destroyed");
  }
  optimize_broad_phase(handle);
  return Ok(0);
}

pub fn JoltWorld.body_count() -> Result[Int, Str] {
  if handle == 0 {
    return Err("jolt: world is destroyed");
  }
  return Ok(get_num_bodies(handle));
}

pub fn JoltWorld.active_body_count() -> Result[Int, Str] {
  if handle == 0 {
    return Err("jolt: world is destroyed");
  }
  return Ok(get_num_active_bodies(handle));
}

// --- PhysicsBody ---
pub type PhysicsBody = {
  handle: BodyID;
  world: Int;
};

pub fn PhysicsBody.new(world_handle: Int, settings: BodyCreationSettings, activate: Bool) -> Result[PhysicsBody, Str] {
  let act = 1;
  if !activate { act = 0; };
  let id = create_and_add_body(world_handle, settings, act);
  if id == 0 {
    return Err("jolt: failed to create body");
  }
  return Ok(PhysicsBody { handle: id, world: world_handle });
}

pub fn PhysicsBody.position() -> Result[Vec3, Str] {
  if world == 0 {
    return Err("jolt: world is destroyed");
  }
  let (px, py, pz) = get_body_position(world, handle);
  return Ok(Vec3 { x: px, y: py, z: pz });
}

pub fn PhysicsBody.velocity() -> Result[Vec3, Str] {
  if world == 0 {
    return Err("jolt: world is destroyed");
  }
  let (vx, vy, vz) = get_body_linear_velocity(world, handle);
  return Ok(Vec3 { x: vx, y: vy, z: vz });
}

pub fn PhysicsBody.set_velocity(vx: Float32, vy: Float32, vz: Float32) -> Result[Int, Str] {
  if world == 0 {
    return Err("jolt: world is destroyed");
  }
  set_body_linear_velocity(world, handle, vx, vy, vz);
  return Ok(0);
}

pub fn PhysicsBody.apply_force(fx: Float32, fy: Float32, fz: Float32) -> Result[Int, Str] {
  if world == 0 {
    return Err("jolt: world is destroyed");
  }
  add_body_force(world, handle, fx, fy, fz);
  return Ok(0);
}

pub fn PhysicsBody.apply_impulse(ix: Float32, iy: Float32, iz: Float32) -> Result[Int, Str] {
  if world == 0 {
    return Err("jolt: world is destroyed");
  }
  add_body_impulse(world, handle, ix, iy, iz);
  return Ok(0);
}

pub fn PhysicsBody.is_active() -> Result[Bool, Str] {
  if world == 0 {
    return Err("jolt: world is destroyed");
  }
  return Ok(is_body_active(world, handle));
}

pub fn PhysicsBody.remove() -> Result[Int, Str] {
  if world == 0 {
    return Err("jolt: world is destroyed");
  }
  remove_body(world, handle);
  return Ok(0);
}

pub fn PhysicsBody.destroy() -> Result[Int, Str] {
  if world == 0 {
    return Err("jolt: world is destroyed");
  }
  destroy_body(world, handle);
  return Ok(0);
}

// --- Shape builders ---
pub fn box_shape(half_x: Float32, half_y: Float32, half_z: Float32) -> Result[Shape, Str]
  requires: half_x > 0.0
  requires: half_y > 0.0
  requires: half_z > 0.0
{
  let settings = create_box_shape_settings(half_x, half_y, half_z);
  if settings == 0 {
    return Err("jolt: failed to create box shape settings");
  }
  let shape = shape_settings_create_shape(settings);
  destroy_shape_settings(settings);
  if shape == 0 {
    return Err("jolt: failed to create box shape");
  }
  return Ok(shape);
}

pub fn sphere_shape(radius: Float32) -> Result[Shape, Str]
  requires: radius > 0.0
{
  let settings = create_sphere_shape_settings(radius);
  if settings == 0 {
    return Err("jolt: failed to create sphere shape settings");
  }
  let shape = shape_settings_create_shape(settings);
  destroy_shape_settings(settings);
  if shape == 0 {
    return Err("jolt: failed to create sphere shape");
  }
  return Ok(shape);
}

pub fn capsule_shape(half_height: Float32, radius: Float32) -> Result[Shape, Str]
  requires: half_height > 0.0
  requires: radius > 0.0
{
  let settings = create_capsule_shape_settings(half_height, radius);
  if settings == 0 {
    return Err("jolt: failed to create capsule shape settings");
  }
  let shape = shape_settings_create_shape(settings);
  destroy_shape_settings(settings);
  if shape == 0 {
    return Err("jolt: failed to create capsule shape");
  }
  return Ok(shape);
}

pub fn plane_shape(nx: Float32, ny: Float32, nz: Float32, constant: Float32) -> Result[Shape, Str] {
  let settings = create_plane_shape_settings(nx, ny, nz, constant);
  if settings == 0 {
    return Err("jolt: failed to create plane shape settings");
  }
  let shape = shape_settings_create_shape(settings);
  destroy_shape_settings(settings);
  if shape == 0 {
    return Err("jolt: failed to create plane shape");
  }
  return Ok(shape);
}

// --- Body creation settings builder ---
pub fn make_body_settings(shape: Shape, pos: Vec3, rot: Quat, motion_type: Int) -> Result[BodyCreationSettings, Str] {
  let settings = create_body_creation_settings(shape, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w, motion_type, 0);
  if settings == 0 {
    return Err("jolt: failed to create body creation settings");
  }
  return Ok(settings);
}

pub fn make_dynamic_body(shape: Shape, pos: Vec3, rot: Quat) -> Result[BodyCreationSettings, Str] {
  return make_body_settings(shape, pos, rot, MOTION_TYPE_DYNAMIC);
}

pub fn make_static_body(shape: Shape, pos: Vec3, rot: Quat) -> Result[BodyCreationSettings, Str] {
  return make_body_settings(shape, pos, rot, MOTION_TYPE_STATIC);
}
