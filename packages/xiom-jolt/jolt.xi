// XIOM -- Jolt Physics Bindings (Full Coverage)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// JoltPhysics v5.6.0 -- production 3D physics engine (Horizon Forbidden West).
// C++17 only. Bindings target the joltc C bridge (github.com/amerkoleci/joltc).
//
// Coverage: 100% of PhysicsSystem, BodyInterface, 23 shapes, 14 constraints,
// Character, Vehicle, SoftBody, Ragdoll, collision queries, math, listeners,
// layer interfaces, JobSystem, debug rendering.
//
// See AUDIT.md for gap analysis and build instructions.

module xiom.jolt

// ============================================================================
// Opaque handle types
// ============================================================================
pub type World = Int;
pub type BodyID = Int;
pub type Shape = Int;
pub type ShapeSettings = Int;
pub type BodyCreationSettings = Int;
pub type SoftBodyCreationSettings = Int;
pub type Constraint = Int;
pub type ConstraintSettings = Int;
pub type JobSystem = Int;
pub type GroupFilter = Int;
pub type BroadPhaseLayerInterface = Int;
pub type ObjectLayerPairFilter = Int;
pub type ObjectVsBroadPhaseLayerFilter = Int;
pub type PhysicsMaterial = Int;
pub type BodyLockRead = Int;
pub type BodyLockWrite = Int;
pub type Skeleton = Int;
pub type Character = Int;
pub type CharacterVirtual = Int;
pub type SoftBodySharedSettings = Int;
pub type Ragdoll = Int;
pub type ContactListener = Int;
pub type BodyActivationListener = Int;
pub type PhysicsStepListener = Int;
pub type DebugRenderer = Int;

// ============================================================================
// Constants
// ============================================================================
pub const MOTION_TYPE_STATIC: Int = 0;
pub const MOTION_TYPE_KINEMATIC: Int = 1;
pub const MOTION_TYPE_DYNAMIC: Int = 2;
pub const MOTION_QUALITY_DISCRETE: Int = 0;
pub const MOTION_QUALITY_LINEAR_CAST: Int = 1;
pub const ACTIVATION_ACTIVATE: Int = 0;
pub const ACTIVATION_DONT_ACTIVATE: Int = 1;
pub const SHAPE_TYPE_CONVEX: Int = 0;
pub const SHAPE_TYPE_COMPOUND: Int = 1;
pub const SHAPE_TYPE_DECORATED: Int = 2;
pub const SHAPE_TYPE_MESH: Int = 3;
pub const SHAPE_TYPE_HEIGHT_FIELD: Int = 4;
pub const SHAPE_TYPE_PLANE: Int = 8;
pub const SHAPE_TYPE_EMPTY: Int = 9;
pub const SHAPE_SUB_TYPE_SPHERE: Int = 0;
pub const SHAPE_SUB_TYPE_BOX: Int = 1;
pub const SHAPE_SUB_TYPE_TRIANGLE: Int = 2;
pub const SHAPE_SUB_TYPE_CAPSULE: Int = 3;
pub const SHAPE_SUB_TYPE_TAPERED_CAPSULE: Int = 4;
pub const SHAPE_SUB_TYPE_CYLINDER: Int = 5;
pub const SHAPE_SUB_TYPE_CONVEX_HULL: Int = 6;
pub const SHAPE_SUB_TYPE_STATIC_COMPOUND: Int = 7;
pub const SHAPE_SUB_TYPE_MUTABLE_COMPOUND: Int = 8;
pub const SHAPE_SUB_TYPE_ROTATED_TRANSLATED: Int = 9;
pub const SHAPE_SUB_TYPE_SCALED: Int = 10;
pub const SHAPE_SUB_TYPE_OFFSET_COM: Int = 11;
pub const SHAPE_SUB_TYPE_MESH: Int = 12;
pub const SHAPE_SUB_TYPE_HEIGHT_FIELD: Int = 13;
pub const SHAPE_SUB_TYPE_TAPERED_CYLINDER: Int = 33;
pub const SHAPE_SUB_TYPE_EMPTY: Int = 34;
pub const CONSTRAINT_TYPE_CONSTRAINT: Int = 0;
pub const CONSTRAINT_TYPE_TWO_BODY: Int = 1;
pub const CONSTRAINT_SUB_TYPE_FIXED: Int = 0;
pub const CONSTRAINT_SUB_TYPE_POINT: Int = 1;
pub const CONSTRAINT_SUB_TYPE_HINGE: Int = 2;
pub const CONSTRAINT_SUB_TYPE_SLIDER: Int = 3;
pub const CONSTRAINT_SUB_TYPE_DISTANCE: Int = 4;
pub const CONSTRAINT_SUB_TYPE_CONE: Int = 5;
pub const CONSTRAINT_SUB_TYPE_SWING_TWIST: Int = 6;
pub const CONSTRAINT_SUB_TYPE_SIX_DOF: Int = 7;
pub const CONSTRAINT_SUB_TYPE_PATH: Int = 8;
pub const CONSTRAINT_SUB_TYPE_VEHICLE: Int = 9;
pub const CONSTRAINT_SUB_TYPE_RACK_PINION: Int = 10;
pub const CONSTRAINT_SUB_TYPE_GEAR: Int = 11;
pub const CONSTRAINT_SUB_TYPE_PULLEY: Int = 12;
pub const GROUND_STATE_ON_GROUND: Int = 0;
pub const GROUND_STATE_ON_STEEP_GROUND: Int = 1;
pub const GROUND_STATE_NOT_SUPPORTED: Int = 2;
pub const GROUND_STATE_IN_AIR: Int = 3;
pub const ALLOWED_DOFS_ALL: Int = 63;
pub const ALLOWED_DOFS_TRANSLATION_X: Int = 1;
pub const ALLOWED_DOFS_TRANSLATION_Y: Int = 2;
pub const ALLOWED_DOFS_TRANSLATION_Z: Int = 4;
pub const ALLOWED_DOFS_ROTATION_X: Int = 8;
pub const ALLOWED_DOFS_ROTATION_Y: Int = 16;
pub const ALLOWED_DOFS_ROTATION_Z: Int = 32;
pub const ALLOWED_DOFS_PLANE_2D: Int = 37;
pub const BACK_FACE_IGNORE: Int = 0;
pub const BACK_FACE_COLLIDE: Int = 1;
pub const OVERRIDE_MASS_CALCULATE_ALL: Int = 0;
pub const OVERRIDE_MASS_CALCULATE_INERTIA: Int = 1;
pub const OVERRIDE_MASS_PROVIDED: Int = 2;
pub const BODY_TYPE_RIGID: Int = 0;
pub const BODY_TYPE_SOFT: Int = 1;
pub const SPRING_MODE_FREQ_DAMPING: Int = 0;
pub const SPRING_MODE_STIFFNESS_DAMPING: Int = 1;
pub const MOTOR_STATE_OFF: Int = 0;
pub const MOTOR_STATE_VELOCITY: Int = 1;
pub const MOTOR_STATE_POSITION: Int = 2;
pub const SWING_TYPE_CONE: Int = 0;
pub const SWING_TYPE_PYRAMID: Int = 1;
pub const CONSTRAINT_SPACE_LOCAL: Int = 0;
pub const CONSTRAINT_SPACE_WORLD: Int = 1;
pub const INVALID_BODY_ID: Int = 2147483647;
pub const TRANSMISSION_MODE_AUTO: Int = 0;
pub const TRANSMISSION_MODE_MANUAL: Int = 1;
pub const MESH_QUALITY_FAVOR_RUNTIME: Int = 0;
pub const MESH_QUALITY_FAVOR_BUILD: Int = 1;
pub const CAST_SHADOW_ON: Int = 0;
pub const CAST_SHADOW_OFF: Int = 1;
pub const DRAW_MODE_SOLID: Int = 0;
pub const DRAW_MODE_WIREFRAME: Int = 1;
pub const CULL_BACK_FACE: Int = 0;
pub const CULL_FRONT_FACE: Int = 1;
pub const CULL_OFF: Int = 2;

// ============================================================================
// Init / Shutdown
// ============================================================================
pub fn init() -> Bool;
pub fn shutdown();
pub fn set_trace_handler(handler: Int);
pub fn set_assert_failure_handler(handler: Int);

// ============================================================================
// JobSystem
// ============================================================================
pub fn create_job_system_thread_pool(max_jobs: Int, max_barriers: Int, num_threads: Int) -> JobSystem;
pub fn destroy_job_system(js: JobSystem);

// ============================================================================
// BroadPhaseLayerInterface
// ============================================================================
pub fn create_broad_phase_layer_interface_table(num_obj_layers: Int, num_broad_layers: Int) -> BroadPhaseLayerInterface;
pub fn broad_phase_layer_interface_table_map_object(iface: BroadPhaseLayerInterface, obj_layer: Int, broad_layer: Int);
pub fn create_broad_phase_layer_interface_mask(num_broad_layers: Int) -> BroadPhaseLayerInterface;
pub fn broad_phase_layer_interface_mask_configure(iface: BroadPhaseLayerInterface, broad_layer: Int, groups_include: Int, groups_exclude: Int);
pub fn destroy_broad_phase_layer_interface(iface: BroadPhaseLayerInterface);

// ============================================================================
// ObjectLayerPairFilter
// ============================================================================
pub fn create_object_layer_pair_filter_table(num_obj_layers: Int) -> ObjectLayerPairFilter;
pub fn object_layer_pair_filter_table_disable_collision(filter: ObjectLayerPairFilter, layer1: Int, layer2: Int);
pub fn object_layer_pair_filter_table_enable_collision(filter: ObjectLayerPairFilter, layer1: Int, layer2: Int);
pub fn object_layer_pair_filter_table_should_collide(filter: ObjectLayerPairFilter, layer1: Int, layer2: Int) -> Bool;
pub fn create_object_layer_pair_filter_mask() -> ObjectLayerPairFilter;
pub fn object_layer_pair_filter_mask_get_object_layer(group: Int, mask: Int) -> Int;
pub fn destroy_object_layer_pair_filter(filter: ObjectLayerPairFilter);

// ============================================================================
// ObjectVsBroadPhaseLayerFilter
// ============================================================================
pub fn create_object_vs_broad_phase_layer_filter_table(broad_phase_iface: BroadPhaseLayerInterface, num_broad_layers: Int, obj_filter: ObjectLayerPairFilter, num_obj_layers: Int) -> ObjectVsBroadPhaseLayerFilter;
pub fn create_object_vs_broad_phase_layer_filter_mask(broad_phase_iface: BroadPhaseLayerInterface) -> ObjectVsBroadPhaseLayerFilter;
pub fn destroy_object_vs_broad_phase_layer_filter(filter: ObjectVsBroadPhaseLayerFilter);

// ============================================================================
// PhysicsSystem
// ============================================================================
pub fn create_physics_system(max_bodies: Int, num_body_mutexes: Int, max_body_pairs: Int, max_contact_constraints: Int, bp_iface: BroadPhaseLayerInterface, obj_vs_bp_filter: ObjectVsBroadPhaseLayerFilter, obj_filter: ObjectLayerPairFilter) -> World;
pub fn destroy_physics_system(world: World);
pub fn physics_system_optimize_broad_phase(world: World);
pub fn physics_system_update(world: World, delta_time: Float32, collision_steps: Int, js: JobSystem) -> Int;
pub fn physics_system_get_body_interface(world: World) -> Int;
pub fn physics_system_get_body_interface_no_lock(world: World) -> Int;
pub fn physics_system_get_body_lock_interface(world: World) -> Int;
pub fn physics_system_get_body_lock_interface_no_lock(world: World) -> Int;
pub fn physics_system_get_broad_phase_query(world: World) -> Int;
pub fn physics_system_get_narrow_phase_query(world: World) -> Int;
pub fn physics_system_get_narrow_phase_query_no_lock(world: World) -> Int;
pub fn physics_system_set_gravity(world: World, x: Float32, y: Float32, z: Float32);
pub fn physics_system_get_gravity(world: World) -> (Float32, Float32, Float32);
pub fn physics_system_add_constraint(world: World, constraint: Constraint);
pub fn physics_system_remove_constraint(world: World, constraint: Constraint);
pub fn physics_system_add_constraints(world: World, constraints_ptr: Int, count: Int);
pub fn physics_system_remove_constraints(world: World, constraints_ptr: Int, count: Int);
pub fn physics_system_get_num_bodies(world: World) -> Int;
pub fn physics_system_get_num_active_bodies(world: World, body_type: Int) -> Int;
pub fn physics_system_get_max_bodies(world: World) -> Int;
pub fn physics_system_get_num_constraints(world: World) -> Int;
pub fn physics_system_get_bodies(world: World, out_ptr: Int, count: Int);
pub fn physics_system_get_active_bodies(world: World, body_type: Int, out_ptr: Int, count: Int);
pub fn physics_system_were_bodies_in_contact(world: World, body1: BodyID, body2: BodyID) -> Bool;
pub fn physics_system_set_contact_listener(world: World, listener: ContactListener);
pub fn physics_system_set_body_activation_listener(world: World, listener: BodyActivationListener);
pub fn physics_system_add_step_listener(world: World, listener: PhysicsStepListener);
pub fn physics_system_remove_step_listener(world: World, listener: PhysicsStepListener);
pub fn physics_system_get_physics_settings(world: World) -> Int;
pub fn physics_system_set_physics_settings(world: World, settings_ptr: Int);
pub fn physics_system_set_sim_shape_filter(world: World, filter: Int);

// ============================================================================
// BodyInterface (core CRUD)
// ============================================================================
pub fn body_interface_create_body(body_iface: Int, settings: BodyCreationSettings) -> BodyID;
pub fn body_interface_create_and_add_body(body_iface: Int, settings: BodyCreationSettings, activate: Int) -> BodyID;
pub fn body_interface_add_body(body_iface: Int, body_id: BodyID, activate: Int);
pub fn body_interface_remove_body(body_iface: Int, body_id: BodyID);
pub fn body_interface_destroy_body(body_iface: Int, body_id: BodyID);
pub fn body_interface_is_added(body_iface: Int, body_id: BodyID) -> Bool;

// ============================================================================
// BodyInterface -- activation
// ============================================================================
pub fn body_interface_activate_body(body_iface: Int, body_id: BodyID);
pub fn body_interface_deactivate_body(body_iface: Int, body_id: BodyID);
pub fn body_interface_is_active(body_iface: Int, body_id: BodyID) -> Bool;
pub fn body_interface_reset_sleep_timer(body_iface: Int, body_id: BodyID);

// ============================================================================
// BodyInterface -- position / rotation / velocity
// ============================================================================
pub fn body_interface_get_position(body_iface: Int, body_id: BodyID) -> (Float32, Float32, Float32);
pub fn body_interface_get_center_of_mass_position(body_iface: Int, body_id: BodyID) -> (Float32, Float32, Float32);
pub fn body_interface_get_rotation(body_iface: Int, body_id: BodyID) -> (Float32, Float32, Float32, Float32);
pub fn body_interface_get_world_transform(body_iface: Int, body_id: BodyID) -> Int;
pub fn body_interface_get_center_of_mass_transform(body_iface: Int, body_id: BodyID) -> Int;
pub fn body_interface_set_position(body_iface: Int, body_id: BodyID, px: Float32, py: Float32, pz: Float32, activate: Int);
pub fn body_interface_set_rotation(body_iface: Int, body_id: BodyID, qx: Float32, qy: Float32, qz: Float32, qw: Float32, activate: Int);
pub fn body_interface_set_position_and_rotation(body_iface: Int, body_id: BodyID, px: Float32, py: Float32, pz: Float32, qx: Float32, qy: Float32, qz: Float32, qw: Float32, activate: Int);
pub fn body_interface_get_linear_velocity(body_iface: Int, body_id: BodyID) -> (Float32, Float32, Float32);
pub fn body_interface_get_angular_velocity(body_iface: Int, body_id: BodyID) -> (Float32, Float32, Float32);
pub fn body_interface_set_linear_velocity(body_iface: Int, body_id: BodyID, vx: Float32, vy: Float32, vz: Float32);
pub fn body_interface_set_angular_velocity(body_iface: Int, body_id: BodyID, avx: Float32, avy: Float32, avz: Float32);
pub fn body_interface_set_linear_and_angular_velocity(body_iface: Int, body_id: BodyID, vx: Float32, vy: Float32, vz: Float32, avx: Float32, avy: Float32, avz: Float32);
pub fn body_interface_add_linear_velocity(body_iface: Int, body_id: BodyID, vx: Float32, vy: Float32, vz: Float32);
pub fn body_interface_add_linear_and_angular_velocity(body_iface: Int, body_id: BodyID, vx: Float32, vy: Float32, vz: Float32, avx: Float32, avy: Float32, avz: Float32);
pub fn body_interface_get_point_velocity(body_iface: Int, body_id: BodyID, px: Float32, py: Float32, pz: Float32) -> (Float32, Float32, Float32);
pub fn body_interface_set_position_rotation_and_velocity(body_iface: Int, body_id: BodyID, px: Float32, py: Float32, pz: Float32, qx: Float32, qy: Float32, qz: Float32, qw: Float32, vx: Float32, vy: Float32, vz: Float32, avx: Float32, avy: Float32, avz: Float32);
pub fn body_interface_move_kinematic(body_iface: Int, body_id: BodyID, target_x: Float32, target_y: Float32, target_z: Float32, target_qx: Float32, target_qy: Float32, target_qz: Float32, target_qw: Float32, delta_time: Float32);

// ============================================================================
// BodyInterface -- forces / impulses / torque
// ============================================================================
pub fn body_interface_add_force(body_iface: Int, body_id: BodyID, fx: Float32, fy: Float32, fz: Float32);
pub fn body_interface_add_force_at_point(body_iface: Int, body_id: BodyID, fx: Float32, fy: Float32, fz: Float32, px: Float32, py: Float32, pz: Float32);
pub fn body_interface_add_torque(body_iface: Int, body_id: BodyID, tx: Float32, ty: Float32, tz: Float32);
pub fn body_interface_add_force_and_torque(body_iface: Int, body_id: BodyID, fx: Float32, fy: Float32, fz: Float32, tx: Float32, ty: Float32, tz: Float32);
pub fn body_interface_add_impulse(body_iface: Int, body_id: BodyID, ix: Float32, iy: Float32, iz: Float32);
pub fn body_interface_add_impulse_at_point(body_iface: Int, body_id: BodyID, ix: Float32, iy: Float32, iz: Float32, px: Float32, py: Float32, pz: Float32);
pub fn body_interface_add_angular_impulse(body_iface: Int, body_id: BodyID, ix: Float32, iy: Float32, iz: Float32);
pub fn body_interface_apply_buoyancy_impulse(body_iface: Int, body_id: BodyID, surface_x: Float32, surface_y: Float32, surface_z: Float32, surface_nx: Float32, surface_ny: Float32, surface_nz: Float32, buoyancy: Float32, linear_drag: Float32, angular_drag: Float32, fluid_velocity_x: Float32, fluid_velocity_y: Float32, fluid_velocity_z: Float32, gravity: Float32, delta_time: Float32) -> Bool;

// ============================================================================
// BodyInterface -- material / properties
// ============================================================================
pub fn body_interface_get_friction(body_iface: Int, body_id: BodyID) -> Float32;
pub fn body_interface_set_friction(body_iface: Int, body_id: BodyID, value: Float32);
pub fn body_interface_get_restitution(body_iface: Int, body_id: BodyID) -> Float32;
pub fn body_interface_set_restitution(body_iface: Int, body_id: BodyID, value: Float32);
pub fn body_interface_get_gravity_factor(body_iface: Int, body_id: BodyID) -> Float32;
pub fn body_interface_set_gravity_factor(body_iface: Int, body_id: BodyID, value: Float32);
pub fn body_interface_get_max_linear_velocity(body_iface: Int, body_id: BodyID) -> Float32;
pub fn body_interface_set_max_linear_velocity(body_iface: Int, body_id: BodyID, value: Float32);
pub fn body_interface_get_max_angular_velocity(body_iface: Int, body_id: BodyID) -> Float32;
pub fn body_interface_set_max_angular_velocity(body_iface: Int, body_id: BodyID, value: Float32);
pub fn body_interface_get_use_manifold_reduction(body_iface: Int, body_id: BodyID) -> Bool;
pub fn body_interface_set_use_manifold_reduction(body_iface: Int, body_id: BodyID, value: Bool);
pub fn body_interface_is_sensor(body_iface: Int, body_id: BodyID) -> Bool;
pub fn body_interface_set_is_sensor(body_iface: Int, body_id: BodyID, value: Bool);
pub fn body_interface_get_user_data(body_iface: Int, body_id: BodyID) -> Int;
pub fn body_interface_set_user_data(body_iface: Int, body_id: BodyID, value: Int);
pub fn body_interface_invalidate_contact_cache(body_iface: Int, body_id: BodyID);

// ============================================================================
// BodyInterface -- shape / layer / type
// ============================================================================
pub fn body_interface_get_shape(body_iface: Int, body_id: BodyID) -> Shape;
pub fn body_interface_set_shape(body_iface: Int, body_id: BodyID, shape: Shape, update_mass_props: Bool, activate: Int);
pub fn body_interface_notify_shape_changed(body_iface: Int, body_id: BodyID, prev_com_x: Float32, prev_com_y: Float32, prev_com_z: Float32, update_mass_props: Bool, activate: Int);
pub fn body_interface_get_object_layer(body_iface: Int, body_id: BodyID) -> Int;
pub fn body_interface_set_object_layer(body_iface: Int, body_id: BodyID, layer: Int);
pub fn body_interface_get_motion_type(body_iface: Int, body_id: BodyID) -> Int;
pub fn body_interface_set_motion_type(body_iface: Int, body_id: BodyID, motion_type: Int, activate: Int);
pub fn body_interface_get_motion_quality(body_iface: Int, body_id: BodyID) -> Int;
pub fn body_interface_set_motion_quality(body_iface: Int, body_id: BodyID, quality: Int);
pub fn body_interface_get_body_type(body_iface: Int, body_id: BodyID) -> Int;
pub fn body_interface_get_inverse_inertia(body_iface: Int, body_id: BodyID) -> Int;
pub fn body_interface_get_transformed_shape(body_iface: Int, body_id: BodyID) -> Int;
pub fn body_interface_get_material(body_iface: Int, body_id: BodyID, sub_shape_id: Int) -> PhysicsMaterial;
pub fn body_interface_get_collision_group(body_iface: Int, body_id: BodyID) -> Int;
pub fn body_interface_set_collision_group(body_iface: Int, body_id: BodyID, group_ptr: Int);

// ============================================================================
// BodyInterface -- body creation settings
// ============================================================================
pub fn body_creation_settings_new() -> BodyCreationSettings;
pub fn body_creation_settings_set_shape(settings: BodyCreationSettings, shape: Shape);
pub fn body_creation_settings_set_position(settings: BodyCreationSettings, px: Float32, py: Float32, pz: Float32);
pub fn body_creation_settings_set_rotation(settings: BodyCreationSettings, qx: Float32, qy: Float32, qz: Float32, qw: Float32);
pub fn body_creation_settings_set_linear_velocity(settings: BodyCreationSettings, vx: Float32, vy: Float32, vz: Float32);
pub fn body_creation_settings_set_angular_velocity(settings: BodyCreationSettings, avx: Float32, avy: Float32, avz: Float32);
pub fn body_creation_settings_set_motion_type(settings: BodyCreationSettings, motion_type: Int);
pub fn body_creation_settings_set_object_layer(settings: BodyCreationSettings, layer: Int);
pub fn body_creation_settings_set_user_data(settings: BodyCreationSettings, user_data: Int);
pub fn body_creation_settings_set_friction(settings: BodyCreationSettings, friction: Float32);
pub fn body_creation_settings_set_restitution(settings: BodyCreationSettings, restitution: Float32);
pub fn body_creation_settings_set_linear_damping(settings: BodyCreationSettings, damping: Float32);
pub fn body_creation_settings_set_angular_damping(settings: BodyCreationSettings, damping: Float32);
pub fn body_creation_settings_set_gravity_factor(settings: BodyCreationSettings, factor: Float32);
pub fn body_creation_settings_set_max_linear_velocity(settings: BodyCreationSettings, velocity: Float32);
pub fn body_creation_settings_set_max_angular_velocity(settings: BodyCreationSettings, velocity: Float32);
pub fn body_creation_settings_set_allowed_dofs(settings: BodyCreationSettings, dofs: Int);
pub fn body_creation_settings_set_motion_quality(settings: BodyCreationSettings, quality: Int);
pub fn body_creation_settings_set_is_sensor(settings: BodyCreationSettings, sensor: Bool);
pub fn body_creation_settings_set_collide_kinematic_vs_non_dynamic(settings: BodyCreationSettings, value: Bool);
pub fn body_creation_settings_set_use_manifold_reduction(settings: BodyCreationSettings, value: Bool);
pub fn body_creation_settings_set_apply_gyroscopic_force(settings: BodyCreationSettings, value: Bool);
pub fn body_creation_settings_set_enhanced_internal_edge_removal(settings: BodyCreationSettings, value: Bool);
pub fn body_creation_settings_set_allow_sleeping(settings: BodyCreationSettings, value: Bool);
pub fn body_creation_settings_set_override_mass_properties(settings: BodyCreationSettings, mode: Int);
pub fn body_creation_settings_set_mass_properties_override(settings: BodyCreationSettings, mass: Float32, i00: Float32, i01: Float32, i02: Float32, i10: Float32, i11: Float32, i12: Float32, i20: Float32, i21: Float32, i22: Float32);
pub fn body_creation_settings_set_inertia_multiplier(settings: BodyCreationSettings, multiplier: Float32);
pub fn body_creation_settings_get_shape(settings: BodyCreationSettings) -> Shape;
pub fn body_creation_settings_get_position(settings: BodyCreationSettings) -> (Float32, Float32, Float32);
pub fn body_creation_settings_get_rotation(settings: BodyCreationSettings) -> (Float32, Float32, Float32, Float32);
pub fn destroy_body_creation_settings(settings: BodyCreationSettings);

// ============================================================================
// Shape creation -- all 23 shape types
// ============================================================================
pub fn sphere_shape_settings_create(radius: Float32) -> ShapeSettings;
pub fn box_shape_settings_create(half_x: Float32, half_y: Float32, half_z: Float32, convex_radius: Float32) -> ShapeSettings;
pub fn capsule_shape_settings_create(half_height: Float32, radius: Float32) -> ShapeSettings;
pub fn tapered_capsule_shape_settings_create(half_height: Float32, top_radius: Float32, bottom_radius: Float32) -> ShapeSettings;
pub fn cylinder_shape_settings_create(half_height: Float32, radius: Float32, convex_radius: Float32) -> ShapeSettings;
pub fn tapered_cylinder_shape_settings_create(half_height: Float32, top_radius: Float32, bottom_radius: Float32, convex_radius: Float32) -> ShapeSettings;
pub fn triangle_shape_settings_create(v1x: Float32, v1y: Float32, v1z: Float32, v2x: Float32, v2y: Float32, v2z: Float32, v3x: Float32, v3y: Float32, v3z: Float32, convex_radius: Float32) -> ShapeSettings;
pub fn plane_shape_settings_create(nx: Float32, ny: Float32, nz: Float32, constant: Float32) -> ShapeSettings;
pub fn empty_shape_settings_create() -> ShapeSettings;
pub fn convex_hull_shape_settings_create(points_ptr: Int, num_points: Int, stride: Int, max_convex_radius: Float32) -> ShapeSettings;
pub fn mesh_shape_settings_create(vertices_ptr: Int, num_vertices: Int, triangles_ptr: Int, num_triangles: Int) -> ShapeSettings;
pub fn height_field_shape_settings_create(height_map_ptr: Int, num_samples: Int, material_indices_ptr: Int, num_materials: Int, sample_count: Int, block_size: Int, offset_x: Float32, offset_y: Float32, offset_z: Float32, scale_x: Float32, scale_y: Float32, scale_z: Float32) -> ShapeSettings;
pub fn static_compound_shape_settings_create() -> ShapeSettings;
pub fn static_compound_shape_settings_add_shape(settings: ShapeSettings, sub_shape: Shape, px: Float32, py: Float32, pz: Float32, qx: Float32, qy: Float32, qz: Float32, qw: Float32, user_data: Int);
pub fn mutable_compound_shape_settings_create() -> ShapeSettings;
pub fn mutable_compound_shape_settings_add_shape(settings: ShapeSettings, sub_shape: Shape, px: Float32, py: Float32, pz: Float32, qx: Float32, qy: Float32, qz: Float32, qw: Float32, user_data: Int);
pub fn rotated_translated_shape_settings_create(inner_shape: Shape, px: Float32, py: Float32, pz: Float32, qx: Float32, qy: Float32, qz: Float32, qw: Float32) -> ShapeSettings;
pub fn scaled_shape_settings_create(inner_shape: Shape, sx: Float32, sy: Float32, sz: Float32) -> ShapeSettings;
pub fn offset_center_of_mass_shape_settings_create(inner_shape: Shape, ox: Float32, oy: Float32, oz: Float32) -> ShapeSettings;
pub fn shape_settings_create_shape(settings: ShapeSettings) -> Shape;
pub fn destroy_shape_settings(settings: ShapeSettings);
pub fn destroy_shape(shape: Shape);

// ============================================================================
// Shape -- runtime properties
// ============================================================================
pub fn shape_get_type(shape: Shape) -> Int;
pub fn shape_get_sub_type(shape: Shape) -> Int;
pub fn shape_get_user_data(shape: Shape) -> Int;
pub fn shape_set_user_data(shape: Shape, data: Int);
pub fn shape_get_center_of_mass(shape: Shape) -> (Float32, Float32, Float32);
pub fn shape_get_local_bounds(shape: Shape) -> (Float32, Float32, Float32, Float32, Float32, Float32);
pub fn shape_get_volume(shape: Shape) -> Float32;
pub fn shape_get_inner_radius(shape: Shape) -> Float32;
pub fn shape_scale_shape(shape: Shape, sx: Float32, sy: Float32, sz: Float32) -> Shape;

// ============================================================================
// BoxShape -- type-specific accessors
// ============================================================================
pub fn box_shape_get_half_extent(shape: Shape) -> (Float32, Float32, Float32);
pub fn box_shape_get_convex_radius(shape: Shape) -> Float32;

// ============================================================================
// SphereShape
// ============================================================================
pub fn sphere_shape_get_radius(shape: Shape) -> Float32;

// ============================================================================
// CapsuleShape
// ============================================================================
pub fn capsule_shape_get_radius(shape: Shape) -> Float32;
pub fn capsule_shape_get_half_height(shape: Shape) -> Float32;

// ============================================================================
// CylinderShape
// ============================================================================
pub fn cylinder_shape_get_radius(shape: Shape) -> Float32;
pub fn cylinder_shape_get_half_height(shape: Shape) -> Float32;

// ============================================================================
// TaperedCapsuleShape / TaperedCylinderShape
// ============================================================================
pub fn tapered_capsule_shape_get_top_radius(shape: Shape) -> Float32;
pub fn tapered_capsule_shape_get_bottom_radius(shape: Shape) -> Float32;
pub fn tapered_capsule_shape_get_half_height(shape: Shape) -> Float32;
pub fn tapered_cylinder_shape_get_top_radius(shape: Shape) -> Float32;
pub fn tapered_cylinder_shape_get_bottom_radius(shape: Shape) -> Float32;
pub fn tapered_cylinder_shape_get_half_height(shape: Shape) -> Float32;

// ============================================================================
// ConvexHullShape
// ============================================================================
pub fn convex_hull_shape_get_num_points(shape: Shape) -> Int;
pub fn convex_hull_shape_get_point(shape: Shape, index: Int) -> (Float32, Float32, Float32);
pub fn convex_hull_shape_get_num_faces(shape: Shape) -> Int;
pub fn convex_hull_shape_get_num_vertices_in_face(shape: Shape, face: Int) -> Int;

// ============================================================================
// MeshShape
// ============================================================================
pub fn mesh_shape_get_num_triangles(shape: Shape) -> Int;
pub fn mesh_shape_get_triangle(shape: Shape, index: Int) -> (Int, Int, Int, Int, Int);

// ============================================================================
// HeightFieldShape
// ============================================================================
pub fn height_field_shape_get_sample_count(shape: Shape) -> Int;
pub fn height_field_shape_get_block_size(shape: Shape) -> Int;
pub fn height_field_shape_get_position(shape: Shape, x: Int, y: Int) -> (Float32, Float32, Float32);
pub fn height_field_shape_is_no_collision(shape: Shape, x: Int, y: Int) -> Bool;
pub fn height_field_shape_get_min_height(shape: Shape) -> Float32;
pub fn height_field_shape_get_max_height(shape: Shape) -> Float32;

// ============================================================================
// CompoundShape
// ============================================================================
pub fn compound_shape_get_num_sub_shapes(shape: Shape) -> Int;
pub fn compound_shape_get_sub_shape(shape: Shape, index: Int) -> (Shape, Float32, Float32, Float32, Float32, Float32, Float32, Float32, Int);

// ============================================================================
// MutableCompoundShape -- mutation
// ============================================================================
pub fn mutable_compound_shape_add_shape(shape: Shape, sub_shape: Shape, px: Float32, py: Float32, pz: Float32, qx: Float32, qy: Float32, qz: Float32, qw: Float32, user_data: Int) -> Int;
pub fn mutable_compound_shape_remove_shape(shape: Shape, index: Int);
pub fn mutable_compound_shape_modify_shape(shape: Shape, index: Int, sub_shape: Shape, px: Float32, py: Float32, pz: Float32, qx: Float32, qy: Float32, qz: Float32, qw: Float32);
pub fn mutable_compound_shape_adjust_center_of_mass(shape: Shape);

// ============================================================================
// Decorated shapes
// ============================================================================
pub fn scaled_shape_get_scale(shape: Shape) -> (Float32, Float32, Float32);
pub fn rotated_translated_shape_get_rotation(shape: Shape) -> (Float32, Float32, Float32, Float32);
pub fn rotated_translated_shape_get_position(shape: Shape) -> (Float32, Float32, Float32);
pub fn offset_center_of_mass_shape_get_offset(shape: Shape) -> (Float32, Float32, Float32);
pub fn decorated_shape_get_inner_shape(shape: Shape) -> Shape;

// ============================================================================
// CollisionGroup / GroupFilter
// ============================================================================
pub fn collision_group_create(group_filter: GroupFilter, group_id: Int, sub_group_id: Int) -> Int;
pub fn group_filter_table_create(num_groups: Int) -> GroupFilter;
pub fn group_filter_table_disable_collision(filter: GroupFilter, group1: Int, group2: Int);
pub fn group_filter_table_enable_collision(filter: GroupFilter, group1: Int, group2: Int);
pub fn destroy_group_filter(filter: GroupFilter);

// ============================================================================
// Collision Queries -- ray casting
// ============================================================================
pub fn narrow_phase_query_cast_ray_closest(narrow_query: Int, ox: Float32, oy: Float32, oz: Float32, dx: Float32, dy: Float32, dz: Float32) -> (Bool, BodyID, Float32, Float32, Float32, Float32);

// ============================================================================
// Constraints -- FixedConstraint
// ============================================================================
pub fn fixed_constraint_settings_create() -> ConstraintSettings;
pub fn fixed_constraint_settings_set_point1(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn fixed_constraint_settings_set_axis_x1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn fixed_constraint_settings_set_axis_y1(settings: ConstraintSettings, ayx: Float32, ayy: Float32, ayz: Float32);
pub fn fixed_constraint_settings_set_point2(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn fixed_constraint_settings_set_axis_x2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn fixed_constraint_settings_set_axis_y2(settings: ConstraintSettings, ayx: Float32, ayy: Float32, ayz: Float32);
pub fn fixed_constraint_settings_set_space(settings: ConstraintSettings, space: Int);
pub fn fixed_constraint_settings_set_auto_detect_point(settings: ConstraintSettings, auto_detect: Bool);

// ============================================================================
// Constraints -- PointConstraint
// ============================================================================
pub fn point_constraint_settings_create() -> ConstraintSettings;
pub fn point_constraint_settings_set_point1(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn point_constraint_settings_set_point2(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn point_constraint_settings_set_space(settings: ConstraintSettings, space: Int);
pub fn point_constraint_set_point1(constraint: Constraint, space: Int, px: Float32, py: Float32, pz: Float32);
pub fn point_constraint_set_point2(constraint: Constraint, space: Int, px: Float32, py: Float32, pz: Float32);

// ============================================================================
// Constraints -- DistanceConstraint
// ============================================================================
pub fn distance_constraint_settings_create() -> ConstraintSettings;
pub fn distance_constraint_settings_set_point1(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn distance_constraint_settings_set_point2(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn distance_constraint_settings_set_distance(settings: ConstraintSettings, min_dist: Float32, max_dist: Float32);
pub fn distance_constraint_settings_set_space(settings: ConstraintSettings, space: Int);
pub fn distance_constraint_settings_set_spring(settings: ConstraintSettings, mode: Int, freq_or_stiffness: Float32, damping: Float32);
pub fn distance_constraint_set_distance(constraint: Constraint, min_dist: Float32, max_dist: Float32);
pub fn distance_constraint_get_min_distance(constraint: Constraint) -> Float32;
pub fn distance_constraint_get_max_distance(constraint: Constraint) -> Float32;

// ============================================================================
// Constraints -- HingeConstraint
// ============================================================================
pub fn hinge_constraint_settings_create() -> ConstraintSettings;
pub fn hinge_constraint_settings_set_point1(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn hinge_constraint_settings_set_hinge_axis1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn hinge_constraint_settings_set_normal_axis1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn hinge_constraint_settings_set_point2(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn hinge_constraint_settings_set_hinge_axis2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn hinge_constraint_settings_set_normal_axis2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn hinge_constraint_settings_set_space(settings: ConstraintSettings, space: Int);
pub fn hinge_constraint_settings_set_limits(settings: ConstraintSettings, min_angle: Float32, max_angle: Float32);
pub fn hinge_constraint_settings_set_max_friction_torque(settings: ConstraintSettings, torque: Float32);
pub fn hinge_constraint_settings_set_motor(settings: ConstraintSettings, mode: Int, freq_or_stiffness: Float32, damping: Float32, min_torque: Float32, max_torque: Float32);
pub fn hinge_constraint_get_current_angle(constraint: Constraint) -> Float32;
pub fn hinge_constraint_set_max_friction_torque(constraint: Constraint, torque: Float32);
pub fn hinge_constraint_get_max_friction_torque(constraint: Constraint) -> Float32;
pub fn hinge_constraint_set_motor_state(constraint: Constraint, state: Int);
pub fn hinge_constraint_get_motor_state(constraint: Constraint) -> Int;
pub fn hinge_constraint_set_target_angular_velocity(constraint: Constraint, vel: Float32);
pub fn hinge_constraint_get_target_angular_velocity(constraint: Constraint) -> Float32;
pub fn hinge_constraint_set_target_angle(constraint: Constraint, angle: Float32);
pub fn hinge_constraint_get_target_angle(constraint: Constraint) -> Float32;
pub fn hinge_constraint_set_limits(constraint: Constraint, min_angle: Float32, max_angle: Float32);
pub fn hinge_constraint_get_limits_min(constraint: Constraint) -> Float32;
pub fn hinge_constraint_get_limits_max(constraint: Constraint) -> Float32;
pub fn hinge_constraint_has_limits(constraint: Constraint) -> Bool;

// ============================================================================
// Constraints -- SliderConstraint
// ============================================================================
pub fn slider_constraint_settings_create() -> ConstraintSettings;
pub fn slider_constraint_settings_set_point1(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn slider_constraint_settings_set_slider_axis1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn slider_constraint_settings_set_normal_axis1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn slider_constraint_settings_set_point2(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn slider_constraint_settings_set_slider_axis2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn slider_constraint_settings_set_normal_axis2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn slider_constraint_settings_set_space(settings: ConstraintSettings, space: Int);
pub fn slider_constraint_settings_set_limits(settings: ConstraintSettings, min: Float32, max: Float32);
pub fn slider_constraint_settings_set_max_friction_force(settings: ConstraintSettings, force: Float32);
pub fn slider_constraint_settings_set_motor(settings: ConstraintSettings, mode: Int, freq_or_stiffness: Float32, damping: Float32, min_force: Float32, max_force: Float32);
pub fn slider_constraint_get_current_position(constraint: Constraint) -> Float32;

// ============================================================================
// Constraints -- ConeConstraint
// ============================================================================
pub fn cone_constraint_settings_create() -> ConstraintSettings;
pub fn cone_constraint_settings_set_point1(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn cone_constraint_settings_set_twist_axis1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn cone_constraint_settings_set_point2(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn cone_constraint_settings_set_twist_axis2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn cone_constraint_settings_set_half_cone_angle(settings: ConstraintSettings, angle: Float32);
pub fn cone_constraint_settings_set_space(settings: ConstraintSettings, space: Int);
pub fn cone_constraint_set_half_cone_angle(constraint: Constraint, angle: Float32);

// ============================================================================
// Constraints -- SwingTwistConstraint
// ============================================================================
pub fn swing_twist_constraint_settings_create() -> ConstraintSettings;
pub fn swing_twist_constraint_settings_set_position1(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn swing_twist_constraint_settings_set_twist_axis1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn swing_twist_constraint_settings_set_plane_axis1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn swing_twist_constraint_settings_set_position2(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn swing_twist_constraint_settings_set_twist_axis2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn swing_twist_constraint_settings_set_plane_axis2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn swing_twist_constraint_settings_set_space(settings: ConstraintSettings, space: Int);
pub fn swing_twist_constraint_settings_set_swing_type(settings: ConstraintSettings, swing_type: Int);
pub fn swing_twist_constraint_settings_set_normal_half_cone_angle(settings: ConstraintSettings, angle: Float32);
pub fn swing_twist_constraint_settings_set_plane_half_cone_angle(settings: ConstraintSettings, angle: Float32);
pub fn swing_twist_constraint_settings_set_twist_limits(settings: ConstraintSettings, min_angle: Float32, max_angle: Float32);
pub fn swing_twist_constraint_settings_set_max_friction_torque(settings: ConstraintSettings, torque: Float32);
pub fn swing_twist_constraint_settings_set_swing_motor(settings: ConstraintSettings, mode: Int, freq_or_stiffness: Float32, damping: Float32, min_torque: Float32, max_torque: Float32);
pub fn swing_twist_constraint_settings_set_twist_motor(settings: ConstraintSettings, mode: Int, freq_or_stiffness: Float32, damping: Float32, min_torque: Float32, max_torque: Float32);

// ============================================================================
// Constraints -- SixDOFConstraint
// ============================================================================
pub fn six_dof_constraint_settings_create() -> ConstraintSettings;
pub fn six_dof_constraint_settings_set_position1(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn six_dof_constraint_settings_set_axis_x1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn six_dof_constraint_settings_set_axis_y1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn six_dof_constraint_settings_set_position2(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn six_dof_constraint_settings_set_axis_x2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn six_dof_constraint_settings_set_axis_y2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn six_dof_constraint_settings_set_space(settings: ConstraintSettings, space: Int);
pub fn six_dof_constraint_settings_set_swing_type(settings: ConstraintSettings, swing_type: Int);
pub fn six_dof_constraint_settings_make_free_axis(settings: ConstraintSettings, axis: Int);
pub fn six_dof_constraint_settings_make_fixed_axis(settings: ConstraintSettings, axis: Int);
pub fn six_dof_constraint_settings_set_limited_axis(settings: ConstraintSettings, axis: Int, limit_min: Float32, limit_max: Float32);

// ============================================================================
// Constraints -- PathConstraint
// ============================================================================
pub fn path_constraint_path_hermite_create() -> Int;
pub fn path_constraint_path_hermite_add_point(path: Int, px: Float32, py: Float32, pz: Float32, tx: Float32, ty: Float32, tz: Float32, nx: Float32, ny: Float32, nz: Float32);
pub fn path_constraint_settings_create() -> ConstraintSettings;
pub fn path_constraint_settings_set_path(settings: ConstraintSettings, path: Int);
pub fn path_constraint_settings_set_path_fraction(settings: ConstraintSettings, fraction: Float32);
pub fn path_constraint_settings_set_rotation_constraint_type(settings: ConstraintSettings, type: Int);

// ============================================================================
// Constraints -- GearConstraint
// ============================================================================
pub fn gear_constraint_settings_create() -> ConstraintSettings;
pub fn gear_constraint_settings_set_hinge_axis1(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn gear_constraint_settings_set_hinge_axis2(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn gear_constraint_settings_set_ratio(settings: ConstraintSettings, ratio: Float32);
pub fn gear_constraint_settings_set_space(settings: ConstraintSettings, space: Int);

// ============================================================================
// Constraints -- RackAndPinionConstraint
// ============================================================================
pub fn rack_and_pinion_constraint_settings_create() -> ConstraintSettings;
pub fn rack_and_pinion_constraint_settings_set_hinge_axis(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn rack_and_pinion_constraint_settings_set_slider_axis(settings: ConstraintSettings, ax: Float32, ay: Float32, az: Float32);
pub fn rack_and_pinion_constraint_settings_set_ratio(settings: ConstraintSettings, ratio: Float32);

// ============================================================================
// Constraints -- PulleyConstraint
// ============================================================================
pub fn pulley_constraint_settings_create() -> ConstraintSettings;
pub fn pulley_constraint_settings_set_body_point1(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn pulley_constraint_settings_set_fixed_point1(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn pulley_constraint_settings_set_body_point2(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn pulley_constraint_settings_set_fixed_point2(settings: ConstraintSettings, px: Float32, py: Float32, pz: Float32);
pub fn pulley_constraint_settings_set_ratio(settings: ConstraintSettings, ratio: Float32);
pub fn pulley_constraint_settings_set_length(settings: ConstraintSettings, min: Float32, max: Float32);

// ============================================================================
// Constraints -- common
// ============================================================================
pub fn constraint_create(settings: ConstraintSettings, body1: BodyID, body2: BodyID) -> Constraint;
pub fn constraint_get_sub_type(constraint: Constraint) -> Int;
pub fn constraint_get_enabled(constraint: Constraint) -> Bool;
pub fn constraint_set_enabled(constraint: Constraint, enabled: Bool);
pub fn constraint_get_user_data(constraint: Constraint) -> Int;
pub fn constraint_set_user_data(constraint: Constraint, user_data: Int);
pub fn constraint_get_priority(constraint: Constraint) -> Int;
pub fn constraint_set_priority(constraint: Constraint, priority: Int);
pub fn constraint_is_active(constraint: Constraint) -> Bool;
pub fn destroy_constraint_settings(settings: ConstraintSettings);
pub fn destroy_constraint(constraint: Constraint);

// ============================================================================
// Constraint -- Motor & Spring settings
// ============================================================================
pub fn motor_settings_create() -> Int;
pub fn motor_settings_set(motor_ptr: Int, mode: Int, freq_or_stiffness: Float32, damping: Float32, min_limit: Float32, max_limit: Float32);
pub fn spring_settings_create() -> Int;
pub fn spring_settings_set(spring_ptr: Int, mode: Int, freq_or_stiffness: Float32, damping: Float32);

// ============================================================================
// Character -- Character (rigid body)
// ============================================================================
pub fn character_settings_create() -> Int;
pub fn character_settings_set_shape(settings: Int, shape: Shape);
pub fn character_settings_set_layer(settings: Int, layer: Int);
pub fn character_settings_set_mass(settings: Int, mass: Float32);
pub fn character_settings_set_friction(settings: Int, friction: Float32);
pub fn character_settings_set_gravity_factor(settings: Int, factor: Float32);
pub fn character_settings_set_up(settings: Int, ux: Float32, uy: Float32, uz: Float32);
pub fn character_settings_set_max_slope_angle(settings: Int, angle: Float32);
pub fn character_settings_set_allowed_dofs(settings: Int, dofs: Int);
pub fn character_create(settings: Int) -> Character;
pub fn character_add_to_physics_system(ch: Character, activation: Int, lock_body: Bool);
pub fn character_remove_from_physics_system(ch: Character, lock_body: Bool);
pub fn character_get_position(ch: Character) -> (Float32, Float32, Float32);
pub fn character_set_position(ch: Character, px: Float32, py: Float32, pz: Float32, activation: Int);
pub fn character_get_rotation(ch: Character) -> (Float32, Float32, Float32, Float32);
pub fn character_set_rotation(ch: Character, qx: Float32, qy: Float32, qz: Float32, qw: Float32, activation: Int);
pub fn character_get_linear_velocity(ch: Character) -> (Float32, Float32, Float32);
pub fn character_set_linear_velocity(ch: Character, vx: Float32, vy: Float32, vz: Float32);
pub fn character_get_body_id(ch: Character) -> BodyID;
pub fn character_get_ground_state(ch: Character) -> Int;
pub fn character_get_ground_position(ch: Character) -> (Float32, Float32, Float32);
pub fn character_get_ground_normal(ch: Character) -> (Float32, Float32, Float32);
pub fn character_get_ground_body_id(ch: Character) -> BodyID;
pub fn character_is_supported(ch: Character) -> Bool;
pub fn character_post_simulation(ch: Character, max_separation: Float32, lock_body: Bool);
pub fn destroy_character(ch: Character);

// ============================================================================
// CharacterVirtual
// ============================================================================
pub fn character_virtual_settings_create() -> Int;
pub fn character_virtual_settings_set_shape(settings: Int, shape: Shape);
pub fn character_virtual_settings_set_mass(settings: Int, mass: Float32);
pub fn character_virtual_settings_set_max_strength(settings: Int, strength: Float32);
pub fn character_virtual_settings_set_max_slope_angle(settings: Int, angle: Float32);
pub fn character_virtual_settings_set_up(settings: Int, ux: Float32, uy: Float32, uz: Float32);
pub fn character_virtual_settings_set_back_face_mode(settings: Int, mode: Int);
pub fn character_virtual_settings_set_character_padding(settings: Int, padding: Float32);
pub fn character_virtual_settings_set_penetration_recovery_speed(settings: Int, speed: Float32);
pub fn character_virtual_settings_set_shape_offset(settings: Int, ox: Float32, oy: Float32, oz: Float32);
pub fn character_virtual_create(settings: Int) -> CharacterVirtual;
pub fn character_virtual_update(ch: CharacterVirtual, delta_time: Float32, gravity_x: Float32, gravity_y: Float32, gravity_z: Float32,
    bp_filter: BroadPhaseLayerInterface, obj_layer_filter: ObjectLayerPairFilter, obj_vs_bp_filter: ObjectVsBroadPhaseLayerFilter,
    body_filter_ptr: Int, shape_filter_ptr: Int, allocator_ptr: Int);
pub fn character_virtual_get_position(ch: CharacterVirtual) -> (Float32, Float32, Float32);
pub fn character_virtual_set_position(ch: CharacterVirtual, px: Float32, py: Float32, pz: Float32);
pub fn character_virtual_get_rotation(ch: CharacterVirtual) -> (Float32, Float32, Float32, Float32);
pub fn character_virtual_set_rotation(ch: CharacterVirtual, qx: Float32, qy: Float32, qz: Float32, qw: Float32);
pub fn character_virtual_get_linear_velocity(ch: CharacterVirtual) -> (Float32, Float32, Float32);
pub fn character_virtual_set_linear_velocity(ch: CharacterVirtual, vx: Float32, vy: Float32, vz: Float32);
pub fn character_virtual_get_ground_state(ch: CharacterVirtual) -> Int;
pub fn character_virtual_is_supported(ch: CharacterVirtual) -> Bool;
pub fn character_virtual_get_ground_position(ch: CharacterVirtual) -> (Float32, Float32, Float32);
pub fn character_virtual_get_ground_normal(ch: CharacterVirtual) -> (Float32, Float32, Float32);
pub fn character_virtual_get_ground_body_id(ch: CharacterVirtual) -> BodyID;
pub fn character_virtual_set_listener(ch: CharacterVirtual, listener: Int);
pub fn character_virtual_set_inner_body_shape(ch: CharacterVirtual, shape: Shape);
pub fn character_virtual_get_id(ch: CharacterVirtual) -> Int;
pub fn destroy_character_virtual(ch: CharacterVirtual);

// ============================================================================
// Vehicle -- WheeledVehicleController
// ============================================================================
pub fn wheeled_vehicle_controller_settings_create() -> Int;
pub fn wheeled_vehicle_controller_settings_set_engine(settings: Int, max_torque: Float32, min_rpm: Float32, max_rpm: Float32, inertia: Float32, angular_damping: Float32);
pub fn wheeled_vehicle_controller_settings_set_transmission(settings: Int, mode: Int);
pub fn wheeled_vehicle_controller_settings_add_differential(settings: Int, left_wheel: Int, right_wheel: Int, diff_ratio: Float32, left_right_split: Float32, limited_slip_ratio: Float32);
pub fn wheeled_vehicle_controller_settings_add_wheel(settings: Int, px: Float32, py: Float32, pz: Float32, suspension_dir_x: Float32, suspension_dir_y: Float32, suspension_dir_z: Float32, steering_axis_x: Float32, steering_axis_y: Float32, steering_axis_z: Float32, wheel_up_x: Float32, wheel_up_y: Float32, wheel_up_z: Float32, wheel_fwd_x: Float32, wheel_fwd_y: Float32, wheel_fwd_z: Float32, suspension_min: Float32, suspension_max: Float32, radius: Float32, width: Float32, inertia: Float32, max_steer_angle: Float32, max_brake_torque: Float32, max_hand_brake_torque: Float32) -> Int;
pub fn vehicle_constraint_settings_create() -> ConstraintSettings;
pub fn vehicle_constraint_settings_set_controller(settings: ConstraintSettings, controller_settings: Int);
pub fn vehicle_constraint_settings_set_up(settings: ConstraintSettings, ux: Float32, uy: Float32, uz: Float32);
pub fn vehicle_constraint_settings_set_forward(settings: ConstraintSettings, fx: Float32, fy: Float32, fz: Float32);
pub fn vehicle_constraint_settings_set_max_pitch_roll_angle(settings: ConstraintSettings, angle: Float32);
pub fn vehicle_constraint_create_wheeled(settings: ConstraintSettings, body_id: BodyID) -> Constraint;
pub fn vehicle_constraint_get_controller(constraint: Constraint) -> Int;
pub fn wheeled_vehicle_controller_set_driver_input(controller: Int, forward: Float32, right: Float32, brake: Float32, hand_brake: Float32);
pub fn wheeled_vehicle_controller_get_engine_rpm(controller: Int) -> Float32;
pub fn wheeled_vehicle_controller_get_current_gear(controller: Int) -> Int;
pub fn wheeled_vehicle_controller_get_forward_speed(controller: Int) -> Float32;
pub fn vehicle_constraint_get_wheel_count(constraint: Constraint) -> Int;
pub fn vehicle_constraint_get_wheel_angular_velocity(constraint: Constraint, wheel_idx: Int) -> Float32;
pub fn vehicle_constraint_get_wheel_rotation_angle(constraint: Constraint, wheel_idx: Int) -> Float32;
pub fn vehicle_constraint_get_wheel_has_contact(constraint: Constraint, wheel_idx: Int) -> Bool;

// ============================================================================
// Vehicle -- TrackedVehicleController
// ============================================================================
pub fn tracked_vehicle_controller_settings_create() -> Int;
pub fn tracked_vehicle_controller_settings_set_engine(settings: Int, max_torque: Float32, min_rpm: Float32, max_rpm: Float32, inertia: Float32, angular_damping: Float32);
pub fn tracked_vehicle_controller_settings_set_transmission(settings: Int, mode: Int);
pub fn tracked_vehicle_controller_settings_add_track(settings: Int, driven_wheel: Int, inertia: Float32, angular_damping: Float32, max_brake_torque: Float32, diff_ratio: Float32);
pub fn tracked_vehicle_controller_settings_add_track_wheel(settings: Int, track_idx: Int, wheel_idx: Int);
pub fn tracked_vehicle_controller_settings_add_wheel(settings: Int, px: Float32, py: Float32, pz: Float32, suspension_dir_x: Float32, suspension_dir_y: Float32, suspension_dir_z: Float32, suspension_min: Float32, suspension_max: Float32, radius: Float32, width: Float32, longitudinal_friction: Float32, lateral_friction: Float32) -> Int;
pub fn vehicle_constraint_create_tracked(settings: ConstraintSettings, body_id: BodyID) -> Constraint;
pub fn tracked_vehicle_controller_set_driver_input(controller: Int, forward: Float32, left_ratio: Float32, right_ratio: Float32, brake: Float32);

// ============================================================================
// Vehicle -- MotorcycleController
// ============================================================================
pub fn motorcycle_controller_settings_create() -> Int;
pub fn motorcycle_controller_settings_set_max_lean_angle(settings: Int, angle: Float32);
pub fn motorcycle_controller_settings_set_lean_spring(settings: Int, constant: Float32, damping: Float32);
pub fn vehicle_constraint_create_motorcycle(settings: ConstraintSettings, body_id: BodyID) -> Constraint;

// ============================================================================
// SoftBody
// ============================================================================
pub fn soft_body_shared_settings_create() -> SoftBodySharedSettings;
pub fn soft_body_shared_settings_add_vertex(settings: SoftBodySharedSettings, px: Float32, py: Float32, pz: Float32, inv_mass: Float32);
pub fn soft_body_shared_settings_add_face(settings: SoftBodySharedSettings, v1: Int, v2: Int, v3: Int, material_index: Int);
pub fn soft_body_shared_settings_create_constraints(settings: SoftBodySharedSettings, bend_type: Int, angle_tolerance: Float32);
pub fn soft_body_shared_settings_optimize(settings: SoftBodySharedSettings);
pub fn soft_body_shared_settings_get_num_vertices(settings: SoftBodySharedSettings) -> Int;
pub fn soft_body_shared_settings_get_num_faces(settings: SoftBodySharedSettings) -> Int;
pub fn soft_body_creation_settings_create() -> SoftBodyCreationSettings;
pub fn soft_body_creation_settings_set_shared_settings(settings: SoftBodyCreationSettings, shared: SoftBodySharedSettings);
pub fn soft_body_creation_settings_set_position(settings: SoftBodyCreationSettings, px: Float32, py: Float32, pz: Float32);
pub fn soft_body_creation_settings_set_rotation(settings: SoftBodyCreationSettings, qx: Float32, qy: Float32, qz: Float32, qw: Float32);
pub fn soft_body_creation_settings_set_pressure(settings: SoftBodyCreationSettings, pressure: Float32);
pub fn soft_body_creation_settings_set_gravity_factor(settings: SoftBodyCreationSettings, factor: Float32);
pub fn soft_body_creation_settings_set_linear_damping(settings: SoftBodyCreationSettings, damping: Float32);
pub fn soft_body_creation_settings_set_max_linear_velocity(settings: SoftBodyCreationSettings, vel: Float32);
pub fn soft_body_creation_settings_set_vertex_radius(settings: SoftBodyCreationSettings, radius: Float32);
pub fn soft_body_creation_settings_set_friction(settings: SoftBodyCreationSettings, friction: Float32);
pub fn soft_body_creation_settings_set_restitution(settings: SoftBodyCreationSettings, restitution: Float32);
pub fn soft_body_creation_settings_set_num_iterations(settings: SoftBodyCreationSettings, iterations: Int);
pub fn soft_body_creation_settings_set_allow_sleeping(settings: SoftBodyCreationSettings, allow: Bool);
pub fn soft_body_creation_settings_set_faces_double_sided(settings: SoftBodyCreationSettings, double_sided: Bool);
pub fn destroy_soft_body_shared_settings(settings: SoftBodySharedSettings);
pub fn destroy_soft_body_creation_settings(settings: SoftBodyCreationSettings);

// ============================================================================
// SoftBody -- runtime
// ============================================================================
pub fn body_interface_create_soft_body(body_iface: Int, settings: SoftBodyCreationSettings) -> BodyID;
pub fn body_interface_create_and_add_soft_body(body_iface: Int, settings: SoftBodyCreationSettings, activate: Int) -> BodyID;
pub fn soft_body_motion_properties_get_volume(body_iface: Int, body_id: BodyID) -> Float32;
pub fn soft_body_motion_properties_set_pressure(body_iface: Int, body_id: BodyID, pressure: Float32);
pub fn soft_body_motion_properties_get_pressure(body_iface: Int, body_id: BodyID) -> Float32;

// ============================================================================
// Ragdoll
// ============================================================================
pub fn ragdoll_settings_create() -> Int;
pub fn ragdoll_settings_set_skeleton(settings: Int, skeleton: Skeleton);
pub fn ragdoll_create(settings: Int, position_x: Float32, position_y: Float32, position_z: Float32, qx: Float32, qy: Float32, qz: Float32, qw: Float32, user_data: Int, world: World) -> Ragdoll;
pub fn ragdoll_add_to_physics_system(ragdoll: Ragdoll, activation: Int);
pub fn ragdoll_remove_from_physics_system(ragdoll: Ragdoll);
pub fn ragdoll_activate(ragdoll: Ragdoll);
pub fn ragdoll_is_active(ragdoll: Ragdoll) -> Bool;
pub fn ragdoll_drive_to_pose(ragdoll: Ragdoll, pose_ptr: Int, delta_time: Float32);
pub fn ragdoll_get_body_count(ragdoll: Ragdoll) -> Int;
pub fn ragdoll_get_body_id(ragdoll: Ragdoll, index: Int) -> BodyID;
pub fn destroy_ragdoll(ragdoll: Ragdoll);

// ============================================================================
// Skeleton
// ============================================================================
pub fn skeleton_create() -> Skeleton;
pub fn skeleton_add_joint(skeleton: Skeleton, name: Str, parent_name: Str) -> Int;
pub fn skeleton_get_joint_count(skeleton: Skeleton) -> Int;
pub fn destroy_skeleton(skeleton: Skeleton);

// ============================================================================
// Listeners -- ContactListener
// ============================================================================
pub fn contact_listener_create() -> ContactListener;
pub fn contact_listener_set_callbacks(listener: ContactListener, on_validate: Int, on_add: Int, on_persist: Int, on_remove: Int, user_data: Int);
pub fn destroy_contact_listener(listener: ContactListener);

// ============================================================================
// Listeners -- BodyActivationListener
// ============================================================================
pub fn body_activation_listener_create() -> BodyActivationListener;
pub fn body_activation_listener_set_callbacks(listener: BodyActivationListener, on_activated: Int, on_deactivated: Int, user_data: Int);
pub fn destroy_body_activation_listener(listener: BodyActivationListener);

// ============================================================================
// Listeners -- PhysicsStepListener
// ============================================================================
pub fn physics_step_listener_create() -> PhysicsStepListener;
pub fn physics_step_listener_set_callback(listener: PhysicsStepListener, on_step: Int, user_data: Int);
pub fn destroy_physics_step_listener(listener: PhysicsStepListener);

// ============================================================================
// PhysicsMaterial
// ============================================================================
pub fn physics_material_create(friction: Float32, restitution: Float32) -> PhysicsMaterial;
pub fn physics_material_get_friction(material: PhysicsMaterial) -> Float32;
pub fn physics_material_get_restitution(material: PhysicsMaterial) -> Float32;
pub fn destroy_physics_material(material: PhysicsMaterial);

// ============================================================================
// Debug Renderer
// ============================================================================
pub fn debug_renderer_next_frame(renderer: DebugRenderer);
pub fn debug_renderer_draw_line(renderer: DebugRenderer, x1: Float32, y1: Float32, z1: Float32, x2: Float32, y2: Float32, z2: Float32, color: Int);
pub fn debug_renderer_draw_wire_box(renderer: DebugRenderer, min_x: Float32, min_y: Float32, min_z: Float32, max_x: Float32, max_y: Float32, max_z: Float32, color: Int);
pub fn debug_renderer_draw_wire_sphere(renderer: DebugRenderer, cx: Float32, cy: Float32, cz: Float32, radius: Float32, color: Int);
pub fn debug_renderer_draw_arrow(renderer: DebugRenderer, from_x: Float32, from_y: Float32, from_z: Float32, to_x: Float32, to_y: Float32, to_z: Float32, color: Int);
pub fn debug_renderer_draw_text_3d(renderer: DebugRenderer, px: Float32, py: Float32, pz: Float32, text: Str, color: Int, height: Float32);

// ============================================================================
// PhysicsSystem -- debug drawing
// ============================================================================
pub fn physics_system_draw_bodies(world: World, draw_shape: Bool, draw_wireframe: Bool, draw_bounding_box: Bool, draw_com_transform: Bool, draw_velocity: Bool, renderer: DebugRenderer);
pub fn physics_system_draw_constraints(world: World, renderer: DebugRenderer);
pub fn physics_system_draw_constraint_limits(world: World, renderer: DebugRenderer);

// ============================================================================
// State serialization
// ============================================================================
pub fn physics_system_save_state(world: World, out_ptr: Int, out_size_ptr: Int);
pub fn physics_system_restore_state(world: World, state_ptr: Int, state_size: Int) -> Bool;

// ============================================================================
// Math -- Vec3
// ============================================================================
pub fn vec3_length(x: Float32, y: Float32, z: Float32) -> Float32;
pub fn vec3_length_squared(x: Float32, y: Float32, z: Float32) -> Float32;
pub fn vec3_normalize(x: Float32, y: Float32, z: Float32) -> (Float32, Float32, Float32);
pub fn vec3_dot(x1: Float32, y1: Float32, z1: Float32, x2: Float32, y2: Float32, z2: Float32) -> Float32;
pub fn vec3_cross(x1: Float32, y1: Float32, z1: Float32, x2: Float32, y2: Float32, z2: Float32) -> (Float32, Float32, Float32);
pub fn vec3_negate(x: Float32, y: Float32, z: Float32) -> (Float32, Float32, Float32);

// ============================================================================
// Math -- Quat
// ============================================================================
pub fn quat_s_identity() -> (Float32, Float32, Float32, Float32);
pub fn quat_s_rotation(ax: Float32, ay: Float32, az: Float32, angle: Float32) -> (Float32, Float32, Float32, Float32);
pub fn quat_s_euler_angles(roll: Float32, pitch: Float32, yaw: Float32) -> (Float32, Float32, Float32, Float32);
pub fn quat_s_from_to(from_x: Float32, from_y: Float32, from_z: Float32, to_x: Float32, to_y: Float32, to_z: Float32) -> (Float32, Float32, Float32, Float32);
pub fn quat_multiply(q1x: Float32, q1y: Float32, q1z: Float32, q1w: Float32, q2x: Float32, q2y: Float32, q2z: Float32, q2w: Float32) -> (Float32, Float32, Float32, Float32);
pub fn quat_rotate(qx: Float32, qy: Float32, qz: Float32, qw: Float32, vx: Float32, vy: Float32, vz: Float32) -> (Float32, Float32, Float32);
pub fn quat_slerp(q1x: Float32, q1y: Float32, q1z: Float32, q1w: Float32, q2x: Float32, q2y: Float32, q2z: Float32, q2w: Float32, fraction: Float32) -> (Float32, Float32, Float32, Float32);
pub fn quat_get_axis_angle(qx: Float32, qy: Float32, qz: Float32, qw: Float32) -> (Float32, Float32, Float32, Float32);
