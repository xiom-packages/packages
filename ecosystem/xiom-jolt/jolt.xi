// XIOM — Jolt Physics Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Jolt Physics is a production-grade 3D physics engine written in C++17.
// It is used in Horizon Forbidden West.
// These bindings target the joltc C bridge (github.com/amerkoleci/joltc)
// which wraps the C++ API in a flat C ABI.
//
// Layer design:
//   jolt.xi       — extern "C" FFI declarations (raw handles)
//   jolt_safe.xi  — safe wrappers with Result[Int, Str] and resource RAII
//   demo_jolt.xi  — minimal physics simulation
//
// See AUDIT.md for compiler gaps and build instructions.

module xiom.jolt

pub type World = Int;
pub type BodyID = Int;
pub type Shape = Int;
pub type JobSystem = Int;
pub type BodyCreationSettings = Int;
pub type ShapeSettings = Int;
pub type ContactListener = Int;
pub type BodyActivationListener = Int;

// --- World lifecycle ---
pub fn init() -> Bool;
pub fn shutdown();

pub fn create_world(max_bodies: Int, max_body_pairs: Int, max_contact_constraints: Int) -> World;
pub fn destroy_world(world: World);

pub fn step_simulation(world: World, delta_time: Float32, collision_steps: Int) -> Int;

pub fn set_gravity(world: World, x: Float32, y: Float32, z: Float32);
pub fn get_gravity(world: World) -> (Float32, Float32, Float32);

pub fn optimize_broad_phase(world: World);
pub fn get_num_bodies(world: World) -> Int;
pub fn get_num_active_bodies(world: World) -> Int;

// --- Shape creation ---
pub fn create_box_shape_settings(half_x: Float32, half_y: Float32, half_z: Float32) -> ShapeSettings;
pub fn create_sphere_shape_settings(radius: Float32) -> ShapeSettings;
pub fn create_capsule_shape_settings(half_height: Float32, radius: Float32) -> ShapeSettings;
pub fn create_cylinder_shape_settings(half_height: Float32, radius: Float32) -> ShapeSettings;
pub fn create_plane_shape_settings(nx: Float32, ny: Float32, nz: Float32, constant: Float32) -> ShapeSettings;

pub fn shape_settings_create_shape(settings: ShapeSettings) -> Shape;
pub fn destroy_shape_settings(settings: ShapeSettings);
pub fn destroy_shape(shape: Shape);

// --- Body creation ---
pub fn create_body_creation_settings(shape: Shape, px: Float32, py: Float32, pz: Float32,
    qx: Float32, qy: Float32, qz: Float32, qw: Float32, motion_type: Int, object_layer: Int) -> BodyCreationSettings;
pub fn set_body_restitution(settings: BodyCreationSettings, value: Float32);
pub fn set_body_friction(settings: BodyCreationSettings, value: Float32);
pub fn set_body_linear_damping(settings: BodyCreationSettings, value: Float32);
pub fn set_body_angular_damping(settings: BodyCreationSettings, value: Float32);
pub fn set_body_gravity_factor(settings: BodyCreationSettings, value: Float32);
pub fn destroy_body_creation_settings(settings: BodyCreationSettings);

// --- Body interface ---
pub fn create_body(world: World, settings: BodyCreationSettings) -> BodyID;
pub fn create_and_add_body(world: World, settings: BodyCreationSettings, activate: Int) -> BodyID;
pub fn add_body(world: World, body_id: BodyID, activate: Int);
pub fn remove_body(world: World, body_id: BodyID);
pub fn destroy_body(world: World, body_id: BodyID);

pub fn get_body_position(world: World, body_id: BodyID) -> (Float32, Float32, Float32);
pub fn get_body_rotation(world: World, body_id: BodyID) -> (Float32, Float32, Float32, Float32);
pub fn get_body_linear_velocity(world: World, body_id: BodyID) -> (Float32, Float32, Float32);
pub fn get_body_angular_velocity(world: World, body_id: BodyID) -> (Float32, Float32, Float32);

pub fn set_body_linear_velocity(world: World, body_id: BodyID, vx: Float32, vy: Float32, vz: Float32);
pub fn set_body_angular_velocity(world: World, body_id: BodyID, avx: Float32, avy: Float32, avz: Float32);
pub fn set_body_position(world: World, body_id: BodyID, px: Float32, py: Float32, pz: Float32,
    qx: Float32, qy: Float32, qz: Float32, qw: Float32);

pub fn add_body_force(world: World, body_id: BodyID, fx: Float32, fy: Float32, fz: Float32);
pub fn add_body_impulse(world: World, body_id: BodyID, ix: Float32, iy: Float32, iz: Float32);
pub fn add_body_torque(world: World, body_id: BodyID, tx: Float32, ty: Float32, tz: Float32);

pub fn is_body_active(world: World, body_id: BodyID) -> Bool;
pub fn body_get_friction(world: World, body_id: BodyID) -> Float32;
pub fn body_get_restitution(world: World, body_id: BodyID) -> Float32;

// --- Ray casting ---
pub fn cast_ray(world: World, origin_x: Float32, origin_y: Float32, origin_z: Float32,
    dir_x: Float32, dir_y: Float32, dir_z: Float32) -> (Bool, BodyID, Float32, Float32, Float32, Float32);

// --- Collision groups ---
pub fn create_group_filter_table(num_groups: Int) -> Int;
pub fn group_filter_table_disable_collision(filter: Int, group1: Int, group2: Int);
pub fn group_filter_table_enable_collision(filter: Int, group1: Int, group2: Int);
pub fn destroy_group_filter(filter: Int);

// --- Constraints ---
pub fn create_distance_constraint(body1: BodyID, body2: BodyID, px1: Float32, py1: Float32, pz1: Float32,
    px2: Float32, py2: Float32, pz2: Float32, min_dist: Float32, max_dist: Float32) -> Int;
pub fn add_constraint(world: World, constraint: Int);
pub fn remove_constraint(world: World, constraint: Int);
pub fn destroy_constraint(constraint: Int);

// --- Job system ---
pub fn create_job_system_thread_pool(max_jobs: Int, max_barriers: Int, num_threads: Int) -> JobSystem;
pub fn destroy_job_system(job_system: JobSystem);
