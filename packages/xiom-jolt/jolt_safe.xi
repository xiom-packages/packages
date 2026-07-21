// XIOM — Jolt Physics Safe Wrappers (v2 — Plain Functions)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Safe wrappers over jolt.xi extern declarations.
// All functions take raw Int handles to avoid cross-module extension method issues.
// Note: Use MOTION_* constants defined here, not from jolt.xi
//       (cross-module const resolution is a known compiler limitation)
//
// See AUDIT.md for compiler gap documentation.

module xiom.jolt_safe
use xiom.jolt;

// ============================================================================
// Helper types
// ============================================================================
pub type Vec3 = {
  x: Float32;
  y: Float32;
  z: Float32;
}

pub type Quat = {
  x: Float32;
  y: Float32;
  z: Float32;
  w: Float32;
}

// ============================================================================
// Local constants (cross-module const not resolved by xiom v0.46.0)
// ============================================================================
pub const MOTION_STATIC: Int = 0;
pub const MOTION_KINEMATIC: Int = 1;
pub const MOTION_DYNAMIC: Int = 2;
pub const LAYER_NON_MOVING: Int = 0;
pub const LAYER_MOVING: Int = 1;
pub const ACTIVATE_VAL: Int = 0;
pub const DONT_ACTIVATE_VAL: Int = 1;

// ============================================================================
// World lifecycle
// ============================================================================
pub fn world_new(max_bodies: Int, max_body_pairs: Int, max_contact_constraints: Int) -> Result[World, Str]
  requires: max_bodies > 0
  requires: max_body_pairs > 0
  requires: max_contact_constraints > 0
{
  if !init() {
    return Err("jolt: failed to initialize");
  }
  let bp_1 = create_broad_phase_layer_interface_table(2, 2);
  let bp_2 = create_broad_phase_layer_interface_table(2, 2);
  let obj_1 = create_object_layer_pair_filter_table(2);
  let obj_2 = create_object_layer_pair_filter_table(2);
  let obj_vs = create_object_vs_broad_phase_layer_filter_table(bp_2, 2, obj_2, 2);
  let raw = create_physics_system(max_bodies, 0, max_body_pairs, max_contact_constraints, bp_1, obj_vs, obj_1);
  if raw == 0 {
    return Err("jolt: failed to create physics system");
  }
  return Ok(raw);
}

pub fn world_destroy(world: World) -> Result[Int, Str] {
  if world == 0 { return Err("jolt: already destroyed"); };
  destroy_physics_system(world);
  shutdown();
  return Ok(0);
}

pub fn world_step(world: World, dt: Float32, collision_steps: Int) -> Result[Int, Str]
  requires: dt > 0.0
  requires: collision_steps > 0
{
  if world == 0 { return Err("jolt: world destroyed"); };
  let js = create_job_system_thread_pool(2048, 8, -1);
  let err = physics_system_update(world, dt, collision_steps, js);
  if err != 0 {
    return Err("jolt: simulation error");
  };
  return Ok(0);
}

pub fn world_set_gravity(world: World, gx: Float32, gy: Float32, gz: Float32) -> Result[Int, Str] {
  if world == 0 { return Err("jolt: world destroyed"); };
  physics_system_set_gravity(world, gx, gy, gz);
  return Ok(0);
}

pub fn world_get_gravity(world: World) -> Result[Vec3, Str] {
  if world == 0 { return Err("jolt: world destroyed"); };
  let (x, y, z) = physics_system_get_gravity(world);
  return Ok(Vec3 { x: x, y: y, z: z });
}

pub fn world_optimize(world: World) -> Result[Int, Str] {
  if world == 0 { return Err("jolt: world destroyed"); };
  physics_system_optimize_broad_phase(world);
  return Ok(0);
}

pub fn world_body_count(world: World) -> Result[Int, Str] {
  if world == 0 { return Err("jolt: world destroyed"); };
  return Ok(physics_system_get_num_bodies(world));
}

pub fn world_active_body_count(world: World) -> Result[Int, Str] {
  if world == 0 { return Err("jolt: world destroyed"); };
  return Ok(physics_system_get_num_active_bodies(world, 0));
}

pub fn world_were_bodies_in_contact(world: World, body1: BodyID, body2: BodyID) -> Result[Bool, Str] {
  if world == 0 { return Err("jolt: world destroyed"); };
  return Ok(physics_system_were_bodies_in_contact(world, body1, body2));
}

pub fn world_add_constraint(world: World, constraint: Constraint) -> Result[Int, Str] {
  if world == 0 { return Err("jolt: world destroyed"); };
  physics_system_add_constraint(world, constraint);
  return Ok(0);
}

pub fn world_remove_constraint(world: World, constraint: Constraint) -> Result[Int, Str] {
  if world == 0 { return Err("jolt: world destroyed"); };
  physics_system_remove_constraint(world, constraint);
  return Ok(0);
}

// ============================================================================
// Body lifecycle
// ============================================================================
pub fn body_create(world: World, settings: BodyCreationSettings, activate: Bool) -> Result[BodyID, Str] {
  let body_iface = physics_system_get_body_interface(world);
  let act = ACTIVATE_VAL;
  if !activate { act = DONT_ACTIVATE_VAL; };
  let id = body_interface_create_and_add_body(body_iface, settings, act);
  if id == 0 {
    return Err("jolt: failed to create body");
  };
  return Ok(id);
}

pub fn body_position(world: World, body_id: BodyID) -> Result[Vec3, Str] {
  let body_iface = physics_system_get_body_interface(world);
  let (x, y, z) = body_interface_get_center_of_mass_position(body_iface, body_id);
  return Ok(Vec3 { x: x, y: y, z: z });
}

pub fn body_rotation(world: World, body_id: BodyID) -> Result[Quat, Str] {
  let body_iface = physics_system_get_body_interface(world);
  let (x, y, z, w) = body_interface_get_rotation(body_iface, body_id);
  return Ok(Quat { x: x, y: y, z: z, w: w });
}

pub fn body_velocity(world: World, body_id: BodyID) -> Result[Vec3, Str] {
  let body_iface = physics_system_get_body_interface(world);
  let (x, y, z) = body_interface_get_linear_velocity(body_iface, body_id);
  return Ok(Vec3 { x: x, y: y, z: z });
}

pub fn body_set_velocity(world: World, body_id: BodyID, v: Vec3) -> Result[Int, Str] {
  let body_iface = physics_system_get_body_interface(world);
  body_interface_set_linear_velocity(body_iface, body_id, v.x, v.y, v.z);
  return Ok(0);
}

pub fn body_set_position(world: World, body_id: BodyID, pos: Vec3, rot: Quat, activate: Int) -> Result[Int, Str] {
  let body_iface = physics_system_get_body_interface(world);
  body_interface_set_position_and_rotation(body_iface, body_id, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w, activate);
  return Ok(0);
}

pub fn body_apply_force(world: World, body_id: BodyID, f: Vec3) -> Result[Int, Str] {
  let body_iface = physics_system_get_body_interface(world);
  body_interface_add_force(body_iface, body_id, f.x, f.y, f.z);
  return Ok(0);
}

pub fn body_apply_impulse(world: World, body_id: BodyID, imp: Vec3) -> Result[Int, Str] {
  let body_iface = physics_system_get_body_interface(world);
  body_interface_add_impulse(body_iface, body_id, imp.x, imp.y, imp.z);
  return Ok(0);
}

pub fn body_is_active(world: World, body_id: BodyID) -> Result[Bool, Str] {
  let body_iface = physics_system_get_body_interface(world);
  return Ok(body_interface_is_active(body_iface, body_id));
}

pub fn body_set_friction(world: World, body_id: BodyID, value: Float32) -> Result[Int, Str] {
  let body_iface = physics_system_get_body_interface(world);
  body_interface_set_friction(body_iface, body_id, value);
  return Ok(0);
}

pub fn body_set_restitution(world: World, body_id: BodyID, value: Float32) -> Result[Int, Str] {
  let body_iface = physics_system_get_body_interface(world);
  body_interface_set_restitution(body_iface, body_id, value);
  return Ok(0);
}

pub fn body_remove(world: World, body_id: BodyID) -> Result[Int, Str] {
  let body_iface = physics_system_get_body_interface(world);
  body_interface_remove_body(body_iface, body_id);
  return Ok(0);
}

pub fn body_destroy(world: World, body_id: BodyID) -> Result[Int, Str] {
  let body_iface = physics_system_get_body_interface(world);
  body_interface_destroy_body(body_iface, body_id);
  return Ok(0);
}

// ============================================================================
// Body creation settings builder
// ============================================================================
pub fn body_settings_new() -> Result[BodyCreationSettings, Str] {
  let s = body_creation_settings_new();
  if s == 0 { return Err("jolt: body settings create failed"); };
  return Ok(s);
}

pub fn body_settings_shape(settings: BodyCreationSettings, shape: Shape) -> Result[BodyCreationSettings, Str] {
  body_creation_settings_set_shape(settings, shape);
  return Ok(settings);
}

pub fn body_settings_position(settings: BodyCreationSettings, pos: Vec3) -> Result[BodyCreationSettings, Str] {
  body_creation_settings_set_position(settings, pos.x, pos.y, pos.z);
  return Ok(settings);
}

pub fn body_settings_rotation(settings: BodyCreationSettings, rot: Quat) -> Result[BodyCreationSettings, Str] {
  body_creation_settings_set_rotation(settings, rot.x, rot.y, rot.z, rot.w);
  return Ok(settings);
}

pub fn body_settings_motion_type(settings: BodyCreationSettings, mt: Int) -> Result[BodyCreationSettings, Str] {
  body_creation_settings_set_motion_type(settings, mt);
  return Ok(settings);
}

pub fn body_settings_layer(settings: BodyCreationSettings, layer: Int) -> Result[BodyCreationSettings, Str] {
  body_creation_settings_set_object_layer(settings, layer);
  return Ok(settings);
}

pub fn body_settings_friction(settings: BodyCreationSettings, friction: Float32) -> Result[BodyCreationSettings, Str] {
  body_creation_settings_set_friction(settings, friction);
  return Ok(settings);
}

pub fn body_settings_restitution(settings: BodyCreationSettings, rest: Float32) -> Result[BodyCreationSettings, Str] {
  body_creation_settings_set_restitution(settings, rest);
  return Ok(settings);
}

pub fn body_settings_gravity_factor(settings: BodyCreationSettings, gf: Float32) -> Result[BodyCreationSettings, Str] {
  body_creation_settings_set_gravity_factor(settings, gf);
  return Ok(settings);
}

pub fn body_settings_linear_damping(settings: BodyCreationSettings, d: Float32) -> Result[BodyCreationSettings, Str] {
  body_creation_settings_set_linear_damping(settings, d);
  return Ok(settings);
}

pub fn body_settings_velocity(settings: BodyCreationSettings, v: Vec3) -> Result[BodyCreationSettings, Str] {
  body_creation_settings_set_linear_velocity(settings, v.x, v.y, v.z);
  return Ok(settings);
}

// ============================================================================
// Shape factories
// ============================================================================
pub fn shape_sphere(radius: Float32) -> Result[Shape, Str]
  requires: radius > 0.0
{
  let s = sphere_shape_settings_create(radius);
  if s == 0 { return Err("jolt: sphere settings failed"); };
  let shape = shape_settings_create_shape(s);
  if shape == 0 { return Err("jolt: sphere shape failed"); };
  return Ok(shape);
}

pub fn shape_box(half_x: Float32, half_y: Float32, half_z: Float32) -> Result[Shape, Str]
  requires: half_x > 0.0
  requires: half_y > 0.0
  requires: half_z > 0.0
{
  let s = box_shape_settings_create(half_x, half_y, half_z, 0.05);
  if s == 0 { return Err("jolt: box settings failed"); };
  let shape = shape_settings_create_shape(s);
  if shape == 0 { return Err("jolt: box shape failed"); };
  return Ok(shape);
}

pub fn shape_capsule(half_height: Float32, radius: Float32) -> Result[Shape, Str]
  requires: half_height > 0.0
  requires: radius > 0.0
{
  let s = capsule_shape_settings_create(half_height, radius);
  if s == 0 { return Err("jolt: capsule settings failed"); };
  let shape = shape_settings_create_shape(s);
  if shape == 0 { return Err("jolt: capsule shape failed"); };
  return Ok(shape);
}

pub fn shape_cylinder(half_height: Float32, radius: Float32) -> Result[Shape, Str]
  requires: half_height > 0.0
  requires: radius > 0.0
{
  let s = cylinder_shape_settings_create(half_height, radius, 0.05);
  if s == 0 { return Err("jolt: cylinder settings failed"); };
  let shape = shape_settings_create_shape(s);
  if shape == 0 { return Err("jolt: cylinder shape failed"); };
  return Ok(shape);
}

pub fn shape_plane(nx: Float32, ny: Float32, nz: Float32, constant: Float32) -> Result[Shape, Str] {
  let s = plane_shape_settings_create(nx, ny, nz, constant);
  if s == 0 { return Err("jolt: plane settings failed"); };
  let shape = shape_settings_create_shape(s);
  if shape == 0 { return Err("jolt: plane shape failed"); };
  return Ok(shape);
}

// ============================================================================
// Math helpers
// ============================================================================
pub fn math_vec3(x: Float32, y: Float32, z: Float32) -> Vec3 {
  return Vec3 { x: x, y: y, z: z };
}

pub fn math_vec3_length(v: Vec3) -> Float32 {
  return vec3_length(v.x, v.y, v.z);
}

pub fn math_vec3_normalize(v: Vec3) -> Vec3 {
  let (x, y, z) = vec3_normalize(v.x, v.y, v.z);
  return Vec3 { x: x, y: y, z: z };
}

pub fn math_quat_identity() -> Quat {
  let (x, y, z, w) = quat_s_identity();
  return Quat { x: x, y: y, z: z, w: w };
}

pub fn math_quat_axis_angle(axis: Vec3, angle: Float32) -> Quat {
  let (x, y, z, w) = quat_s_rotation(axis.x, axis.y, axis.z, angle);
  return Quat { x: x, y: y, z: z, w: w };
}

pub fn math_quat_identity_q() -> (Float32, Float32, Float32, Float32) {
  return quat_s_identity();
}
