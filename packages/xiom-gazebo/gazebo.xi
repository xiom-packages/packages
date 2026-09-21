// XIOM -- Gazebo Simulation Bindings
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for the Gazebo Sim C API (libgz-sim.so / gz-sim.dll).
// Gazebo is a 3D robot simulation engine supporting rigid-body dynamics,
// sensors, and plugin-based extensibility.
//
// See SPEC.md for scope and ROADMAP.md for planned extensions.

module xiom.gazebo

// ============================================================================
// Opaque handle types
// ============================================================================

pub type World = Int;
pub type Model = Int;
pub type Joint = Int;
pub type Sensor = Int;

// ============================================================================
// Joint type constants
// ============================================================================

pub const JOINT_FIXED: Int = 0;
pub const JOINT_REVOLUTE: Int = 1;
pub const JOINT_PRISMATIC: Int = 2;
pub const JOINT_BALL: Int = 3;

// ============================================================================
// Sensor type constants
// ============================================================================

pub const SENSOR_CAMERA: Int = 0;
pub const SENSOR_LIDAR: Int = 1;
pub const SENSOR_IMU: Int = 2;
pub const SENSOR_CONTACT: Int = 3;
pub const SENSOR_FORCE_TORQUE: Int = 4;

// ============================================================================
// EXTERN "C" -- Gazebo Sim C API (~12 functions)
// ============================================================================

extern "C" {

  // -- Initialization --

  fn gz_init() -> Int;
  fn gz_fini() -> Int;

  // -- World lifecycle --

  fn gz_world_create(name: *UInt8) -> Int;
  fn gz_world_destroy(world: Int);
  fn gz_world_step(world: Int, steps: Int, dt: Float64) -> Int;
  fn gz_world_set_gravity(world: Int, x: Float64, y: Float64, z: Float64);
  fn gz_world_get_gravity(world: Int) -> (Float64, Float64, Float64);

  // -- Model lifecycle --

  fn gz_model_create(world: Int, name: *UInt8, sdf_path: *UInt8) -> Int;
  fn gz_model_destroy(world: Int, model: Int);
  fn gz_model_set_pose(model: Int, px: Float64, py: Float64, pz: Float64, qx: Float64, qy: Float64, qz: Float64, qw: Float64);

  // -- Joint operations --

  fn gz_joint_create(model: Int, name: *UInt8, joint_type: Int) -> Int;
  fn gz_joint_set_force(joint: Int, force: Float64);

  // -- Sensor operations --

  fn gz_sensor_create(model: Int, name: *UInt8, sensor_type: Int) -> Int;
  fn gz_sensor_read(sensor: Int) -> Float64;

}

// ============================================================================
// Safe wrappers with contracts
// ============================================================================

pub fn init() -> Bool
  ensures: result == true;
{
  let rc = gz_init();
  return rc == 0;
}

pub fn shutdown() {
  let _ = gz_fini();
}

pub fn create_world() -> World
  ensures: result != 0;
{
  let raw = gz_world_create(null);
  return raw;
}

pub fn destroy_world(world: World)
  requires: world != 0;
{
  gz_world_destroy(world);
}

pub fn step_simulation(world: World, steps: Int, dt: Float64) -> Int
  requires: world != 0
  requires: steps > 0
  requires: dt > 0.0;
{
  return gz_world_step(world, steps, dt);
}

pub fn set_gravity(world: World, x: Float64, y: Float64, z: Float64)
  requires: world != 0;
{
  gz_world_set_gravity(world, x, y, z);
}

pub fn get_gravity(world: World) -> (Float64, Float64, Float64)
  requires: world != 0;
{
  return gz_world_get_gravity(world);
}

pub fn create_model(world: World) -> Model
  requires: world != 0
  ensures: result != 0;
{
  let raw = gz_model_create(world, null, null);
  return raw;
}

pub fn destroy_model(world: World, model: Model)
  requires: world != 0
  requires: model != 0;
{
  gz_model_destroy(world, model);
}

pub fn model_set_pose(model: Model, px: Float64, py: Float64, pz: Float64, qx: Float64, qy: Float64, qz: Float64, qw: Float64)
  requires: model != 0;
{
  gz_model_set_pose(model, px, py, pz, qx, qy, qz, qw);
}

pub fn create_joint(model: Model, joint_type: Int) -> Joint
  requires: model != 0
  requires: joint_type >= 0 && joint_type <= 3
  ensures: result != 0;
{
  let raw = gz_joint_create(model, null, joint_type);
  return raw;
}

pub fn joint_set_force(joint: Joint, force: Float64)
  requires: joint != 0;
{
  gz_joint_set_force(joint, force);
}

pub fn create_sensor(model: Model, sensor_type: Int) -> Sensor
  requires: model != 0
  requires: sensor_type >= 0 && sensor_type <= 4
  ensures: result != 0;
{
  let raw = gz_sensor_create(model, null, sensor_type);
  return raw;
}

pub fn sensor_read(sensor: Sensor) -> Float64
  requires: sensor != 0;
{
  return gz_sensor_read(sensor);
}
