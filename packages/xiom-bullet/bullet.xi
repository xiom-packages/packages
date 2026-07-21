// XIOM — Bullet Physics Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.bullet

pub type World = Int;
pub type RigidBody = Int;
pub type CollisionShape = Int;

pub fn create_world() -> World
  ensures: result != 0;

pub fn destroy_world(world: World)
  requires: world != 0;

pub fn step_simulation(world: World, time_step: Float32) -> Int
  requires: world != 0
  requires: time_step > 0.0;

pub fn set_gravity(world: World, x: Float32, y: Float32, z: Float32)
  requires: world != 0;

pub fn add_body(world: World, body: RigidBody)
  requires: world != 0
  requires: body != 0;

pub fn remove_body(world: World, body: RigidBody)
  requires: world != 0
  requires: body != 0;

pub fn create_box_shape(half_x: Float32, half_y: Float32, half_z: Float32) -> CollisionShape
  requires: half_x > 0.0
  requires: half_y > 0.0
  requires: half_z > 0.0
  ensures: result != 0;

pub fn create_sphere_shape(radius: Float32) -> CollisionShape
  requires: radius > 0.0
  ensures: result != 0;

pub fn create_capsule_shape(radius: Float32, height: Float32) -> CollisionShape
  requires: radius > 0.0
  requires: height > 0.0
  ensures: result != 0;

pub fn create_plane_shape(nx: Float32, ny: Float32, nz: Float32, constant: Float32) -> CollisionShape
  ensures: result != 0;

pub fn create_rigid_body(mass: Float32, shape: CollisionShape) -> RigidBody
  requires: mass >= 0.0
  requires: shape != 0
  ensures: result != 0;

pub fn set_velocity(body: RigidBody, vx: Float32, vy: Float32, vz: Float32)
  requires: body != 0;

pub fn set_angular_velocity(body: RigidBody, avx: Float32, avy: Float32, avz: Float32)
  requires: body != 0;

pub fn apply_force(body: RigidBody, fx: Float32, fy: Float32, fz: Float32)
  requires: body != 0;

pub fn apply_impulse(body: RigidBody, ix: Float32, iy: Float32, iz: Float32)
  requires: body != 0;

pub fn set_restitution(body: RigidBody, value: Float32)
  requires: body != 0
  requires: value >= 0.0 && value <= 1.0;

pub fn set_friction(body: RigidBody, value: Float32)
  requires: body != 0
  requires: value >= 0.0;

pub fn get_position(body: RigidBody) -> (Float32, Float32, Float32)
  requires: body != 0;
