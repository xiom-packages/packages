// XIOM -- Ozz-Animation (v0.16.0) FFI Bindings
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for Ozz-Animation v0.16.0 via a C bridge.
// Ozz is a C++ library with NO native C API. A C bridge (ozz_c_bridge.h/.cpp)
// must be compiled separately to provide the functions declared below.
//
// Types:
//   - Opaque handles (C++ classes):          Int (pointer-sized)
//   - Math structs (pass by value):          XIOM struct types
//   - Job input/output buffers (SoA spans):  Int (pointer to allocated buffer)
//   - Counts / enums / booleans:             Int32
//   - Sizes / durations:                     Float32
//
// COMPILER GAPS: see AUDIT.md

module xiom.ozz

// =========================================================================
// Constants
// =========================================================================

pub const OZZ_MAX_JOINTS: Int32 = 1024 as Int32
pub const OZZ_NO_PARENT: Int32 = (-1 as Int32)
pub const OZZ_MAX_TRACKS: Int32 = 65535 as Int32

// =========================================================================
// Math types -- transparent structs matching C bridge ozz_float3_t, etc.
// =========================================================================

pub type Float3 = {
  x: Float32
  y: Float32
  z: Float32
} derive[Clone]

pub type Float4 = {
  x: Float32
  y: Float32
  z: Float32
  w: Float32
} derive[Clone]

pub type Quaternion = {
  x: Float32
  y: Float32
  z: Float32
  w: Float32
} derive[Clone]

pub type Transform = {
  translation: Float3
  rotation: Quaternion
  scale: Float3
} derive[Clone]

// =========================================================================
// extern "C" declarations -- provided by ozz_c_bridge (C wrapper around C++)
// =========================================================================

extern "C" {
  // --- Memory allocator ---
  fn ozz_default_allocator() -> Int
  fn ozz_set_default_allocator(allocator: Int)

  // --- Skeleton ---
  fn ozz_skeleton_load(archive_data: Int, archive_size: Int) -> Int
  fn ozz_skeleton_destroy(skeleton: Int)
  fn ozz_skeleton_num_joints(skeleton: Int) -> Int32
  fn ozz_skeleton_num_soa_joints(skeleton: Int) -> Int32
  fn ozz_skeleton_joint_parents(skeleton: Int, out_count: Int) -> Int
  fn ozz_skeleton_joint_name(skeleton: Int, index: Int32) -> Int
  fn ozz_skeleton_joint_rest_poses(skeleton: Int) -> Int

  // --- Animation ---
  fn ozz_animation_load(archive_data: Int, archive_size: Int) -> Int
  fn ozz_animation_destroy(animation: Int)
  fn ozz_animation_duration(animation: Int) -> Float32
  fn ozz_animation_num_tracks(animation: Int) -> Int32
  fn ozz_animation_name(animation: Int) -> Int
  fn ozz_animation_time_ratio(animation: Int, time: Float32) -> Float32

  // --- Sampling ---
  fn ozz_sampling_context_create(max_tracks: Int32) -> Int
  fn ozz_sampling_context_destroy(context: Int)
  fn ozz_sampling_context_resize(context: Int, max_tracks: Int32) -> Int32
  fn ozz_sampling_context_reset(context: Int)
  fn ozz_sampling_job_run(context: Int, animation: Int, skeleton: Int, ratio: Float32, output: Int, cache: Int) -> Int32
  fn ozz_sampling_job_default_ratio(animation: Int) -> Float32

  // --- Blending ---
  fn ozz_blending_job_run(skeleton: Int, layers: Int, weights: Int, num_layers: Int32, bind_pose: Int, output: Int) -> Int32
  fn ozz_blending_job_run_additive(skeleton: Int, layers: Int, weights: Int, num_layers: Int32, additive_layers: Int, additive_weights: Int, num_additive: Int32, bind_pose: Int, output: Int) -> Int32

  // --- Local-to-model ---
  fn ozz_local_to_model_job_run(skeleton: Int, input: Int, root: Int, from: Int32, to: Int32, from_excluded: Int32, output: Int) -> Int32

  // --- IK ---
  fn ozz_ik_two_bone_job_run(target: Int, mid_axis: Int, pole_vector: Int, twist_angle: Float32, soften: Float32, weight: Float32, start_joint: Int, mid_joint: Int, end_joint: Int, start_correction: Int, mid_correction: Int, reached: Int) -> Int32

  fn ozz_ik_aim_job_run(target: Int, forward: Int, offset: Int, up: Int, pole_vector: Int, twist_angle: Float32, weight: Float32, joint: Int, joint_correction: Int, reached: Int) -> Int32

  // --- Skinning ---
  fn ozz_skinning_job_run(vertex_count: Int32, influences_count: Int32, joint_matrices: Int, joint_inverse_transpose_matrices: Int, joint_indices: Int, joint_indices_stride: Int, joint_weights: Int, joint_weights_stride: Int, in_positions: Int, in_positions_stride: Int, in_normals: Int, in_normals_stride: Int, in_tangents: Int, in_tangents_stride: Int, out_positions: Int, out_positions_stride: Int, out_normals: Int, out_normals_stride: Int, out_tangents: Int, out_tangents_stride: Int) -> Int32

  // --- FloatTrack ---
  fn ozz_float_track_load(archive_data: Int, archive_size: Int) -> Int
  fn ozz_float_track_destroy(track: Int)
  fn ozz_float_track_num_keys(track: Int) -> Int32
  fn ozz_float_track_name(track: Int) -> Int
  fn ozz_float_track_sample(track: Int, ratio: Float32, result: Int) -> Int32
  fn ozz_float_track_trigger(from: Float32, to: Float32, threshold: Float32, track: Int, out_count: Int) -> Int

  // --- Float2Track ---
  fn ozz_float2_track_load(archive_data: Int, archive_size: Int) -> Int
  fn ozz_float2_track_destroy(track: Int)
  fn ozz_float2_track_num_keys(track: Int) -> Int32
  fn ozz_float2_track_name(track: Int) -> Int
  fn ozz_float2_track_sample(track: Int, ratio: Float32, result: Int) -> Int32

  // --- Float3Track ---
  fn ozz_float3_track_load(archive_data: Int, archive_size: Int) -> Int
  fn ozz_float3_track_destroy(track: Int)
  fn ozz_float3_track_num_keys(track: Int) -> Int32
  fn ozz_float3_track_name(track: Int) -> Int
  fn ozz_float3_track_sample(track: Int, ratio: Float32, result: Int) -> Int32

  // --- Float4Track ---
  fn ozz_float4_track_load(archive_data: Int, archive_size: Int) -> Int
  fn ozz_float4_track_destroy(track: Int)
  fn ozz_float4_track_num_keys(track: Int) -> Int32
  fn ozz_float4_track_name(track: Int) -> Int
  fn ozz_float4_track_sample(track: Int, ratio: Float32, result: Int) -> Int32

  // --- QuaternionTrack ---
  fn ozz_quaternion_track_load(archive_data: Int, archive_size: Int) -> Int
  fn ozz_quaternion_track_destroy(track: Int)
  fn ozz_quaternion_track_num_keys(track: Int) -> Int32
  fn ozz_quaternion_track_name(track: Int) -> Int
  fn ozz_quaternion_track_sample(track: Int, ratio: Float32, result: Int) -> Int32

  // --- Offline: SkeletonBuilder ---
  fn ozz_skeleton_builder_create() -> Int
  fn ozz_skeleton_builder_destroy(builder: Int)
  fn ozz_skeleton_builder_build(builder: Int, raw_skeleton_data: Int, raw_skeleton_size: Int) -> Int

  // --- Offline: AnimationBuilder ---
  fn ozz_animation_builder_create() -> Int
  fn ozz_animation_builder_destroy(builder: Int)
  fn ozz_animation_builder_set_iframe_interval(builder: Int, interval: Float32)
  fn ozz_animation_builder_build(builder: Int, raw_animation_data: Int, raw_animation_size: Int) -> Int

  // --- I/O: binary serialization (archive read/write) ---
  fn ozz_archive_read_file(path: Int) -> Int
  fn ozz_archive_read_size(handle: Int) -> Int
  fn ozz_archive_read_data(handle: Int) -> Int
  fn ozz_archive_read_close(handle: Int)
}

// =========================================================================
// Procedural safe wrappers
// =========================================================================

// --- Skeleton ---

pub fn skeleton_load(archive_data: Int, archive_size: Int) -> Result[Int, Str]
  requires: archive_data != 0
  requires: archive_size > 0
  ensures: result is Ok => result.unwrap() != 0
{
  let skel: Int = unsafe { ozz_skeleton_load(archive_data, archive_size) }
  if skel == 0 { return Err("skeleton_load: failed to deserialize skeleton") }
  return Ok(skel)
}

pub fn skeleton_destroy(skeleton: Int)
  requires: skeleton != 0
{
  unsafe { ozz_skeleton_destroy(skeleton) }
}

pub fn skeleton_num_joints(skeleton: Int) -> Int32
  requires: skeleton != 0
{
  return unsafe { ozz_skeleton_num_joints(skeleton) }
}

pub fn skeleton_num_soa_joints(skeleton: Int) -> Int32
  requires: skeleton != 0
{
  return unsafe { ozz_skeleton_num_soa_joints(skeleton) }
}

pub fn skeleton_joint_parents(skeleton: Int, out_count: Int) -> Int
  requires: skeleton != 0
  requires: out_count != 0
{
  return unsafe { ozz_skeleton_joint_parents(skeleton, out_count) }
}

// --- Animation ---

pub fn animation_load(archive_data: Int, archive_size: Int) -> Result[Int, Str]
  requires: archive_data != 0
  requires: archive_size > 0
  ensures: result is Ok => result.unwrap() != 0
{
  let anim: Int = unsafe { ozz_animation_load(archive_data, archive_size) }
  if anim == 0 { return Err("animation_load: failed to deserialize animation") }
  return Ok(anim)
}

pub fn animation_destroy(animation: Int)
  requires: animation != 0
{
  unsafe { ozz_animation_destroy(animation) }
}

pub fn animation_duration(animation: Int) -> Float32
  requires: animation != 0
{
  return unsafe { ozz_animation_duration(animation) }
}

pub fn animation_num_tracks(animation: Int) -> Int32
  requires: animation != 0
{
  return unsafe { ozz_animation_num_tracks(animation) }
}

// --- Sampling ---

pub fn sampling_context_create(max_tracks: Int32) -> Result[Int, Str]
  requires: max_tracks > 0
  ensures: result is Ok => result.unwrap() != 0
{
  let ctx: Int = unsafe { ozz_sampling_context_create(max_tracks) }
  if ctx == 0 { return Err("sampling_context_create: allocation failed") }
  return Ok(ctx)
}

pub fn sampling_context_destroy(context: Int)
  requires: context != 0
{
  unsafe { ozz_sampling_context_destroy(context) }
}

pub fn sampling_context_resize(context: Int, max_tracks: Int32) -> Bool
  requires: context != 0
  requires: max_tracks > 0
{
  let res: Int32 = unsafe { ozz_sampling_context_resize(context, max_tracks) }
  return res != 0
}

pub fn sampling_context_reset(context: Int)
  requires: context != 0
{
  unsafe { ozz_sampling_context_reset(context) }
}

pub fn sample_animation(context: Int, animation: Int, skeleton: Int, ratio: Float32, output: Int, cache: Int) -> Bool
  requires: context != 0
  requires: animation != 0
  requires: skeleton != 0
  requires: output != 0
  requires: cache != 0
{
  let res: Int32 = unsafe { ozz_sampling_job_run(context, animation, skeleton, ratio, output, cache) }
  return res != 0
}

// --- Blending ---

pub fn blend_poses(skeleton: Int, layers: Int, weights: Int, num_layers: Int32, bind_pose: Int, output: Int) -> Bool
  requires: skeleton != 0
  requires: layers != 0
  requires: weights != 0
  requires: num_layers > 0
  requires: bind_pose != 0
  requires: output != 0
{
  let res: Int32 = unsafe { ozz_blending_job_run(skeleton, layers, weights, num_layers, bind_pose, output) }
  return res != 0
}

pub fn blend_poses_additive(skeleton: Int, layers: Int, weights: Int, num_layers: Int32, additive_layers: Int, additive_weights: Int, num_additive: Int32, bind_pose: Int, output: Int) -> Bool
  requires: skeleton != 0
  requires: num_layers > 0
  requires: bind_pose != 0
  requires: output != 0
{
  let res: Int32 = unsafe { ozz_blending_job_run_additive(skeleton, layers, weights, num_layers, additive_layers, additive_weights, num_additive, bind_pose, output) }
  return res != 0
}

// --- Local-to-model ---

pub fn local_to_model(skeleton: Int, input: Int, root: Int, from: Int32, to: Int32, from_excluded: Int32, output: Int) -> Bool
  requires: skeleton != 0
  requires: input != 0
  requires: output != 0
{
  let res: Int32 = unsafe { ozz_local_to_model_job_run(skeleton, input, root, from, to, from_excluded, output) }
  return res != 0
}

// --- IK ---

pub fn ik_two_bone(target: Int, mid_axis: Int, pole_vector: Int, twist_angle: Float32, soften: Float32, weight: Float32, start_joint: Int, mid_joint: Int, end_joint: Int, start_correction: Int, mid_correction: Int, reached: Int) -> Bool
  requires: target != 0
  requires: start_joint != 0
  requires: mid_joint != 0
  requires: end_joint != 0
  requires: start_correction != 0
  requires: mid_correction != 0
{
  let res: Int32 = unsafe { ozz_ik_two_bone_job_run(target, mid_axis, pole_vector, twist_angle, soften, weight, start_joint, mid_joint, end_joint, start_correction, mid_correction, reached) }
  return res != 0
}

pub fn ik_aim(target: Int, forward: Int, offset: Int, up: Int, pole_vector: Int, twist_angle: Float32, weight: Float32, joint: Int, joint_correction: Int, reached: Int) -> Bool
  requires: target != 0
  requires: joint != 0
  requires: joint_correction != 0
{
  let res: Int32 = unsafe { ozz_ik_aim_job_run(target, forward, offset, up, pole_vector, twist_angle, weight, joint, joint_correction, reached) }
  return res != 0
}

// --- Skinning ---

pub fn skin_vertices(vertex_count: Int32, influences_count: Int32, joint_matrices: Int, joint_inverse_transpose_matrices: Int, joint_indices: Int, joint_indices_stride: Int, joint_weights: Int, joint_weights_stride: Int, in_positions: Int, in_positions_stride: Int, in_normals: Int, in_normals_stride: Int, in_tangents: Int, in_tangents_stride: Int, out_positions: Int, out_positions_stride: Int, out_normals: Int, out_normals_stride: Int, out_tangents: Int, out_tangents_stride: Int) -> Bool
  requires: vertex_count > 0
  requires: joint_matrices != 0
  requires: joint_indices != 0
  requires: joint_weights != 0
  requires: in_positions != 0
  requires: out_positions != 0
{
  let res: Int32 = unsafe { ozz_skinning_job_run(vertex_count, influences_count, joint_matrices, joint_inverse_transpose_matrices, joint_indices, joint_indices_stride, joint_weights, joint_weights_stride, in_positions, in_positions_stride, in_normals, in_normals_stride, in_tangents, in_tangents_stride, out_positions, out_positions_stride, out_normals, out_normals_stride, out_tangents, out_tangents_stride) }
  return res != 0
}

// --- Track sample helpers ---

pub fn float_track_sample(track: Int, ratio: Float32, result: Int) -> Bool
  requires: track != 0
  requires: result != 0
{
  let res: Int32 = unsafe { ozz_float_track_sample(track, ratio, result) }
  return res != 0
}

pub fn float2_track_sample(track: Int, ratio: Float32, result: Int) -> Bool
  requires: track != 0
  requires: result != 0
{
  let res: Int32 = unsafe { ozz_float2_track_sample(track, ratio, result) }
  return res != 0
}

pub fn float3_track_sample(track: Int, ratio: Float32, result: Int) -> Bool
  requires: track != 0
  requires: result != 0
{
  let res: Int32 = unsafe { ozz_float3_track_sample(track, ratio, result) }
  return res != 0
}

pub fn float4_track_sample(track: Int, ratio: Float32, result: Int) -> Bool
  requires: track != 0
  requires: result != 0
{
  let res: Int32 = unsafe { ozz_float4_track_sample(track, ratio, result) }
  return res != 0
}

pub fn quaternion_track_sample(track: Int, ratio: Float32, result: Int) -> Bool
  requires: track != 0
  requires: result != 0
{
  let res: Int32 = unsafe { ozz_quaternion_track_sample(track, ratio, result) }
  return res != 0
}

// --- Track loading ---

pub fn float_track_load(archive_data: Int, archive_size: Int) -> Result[Int, Str]
  requires: archive_data != 0
  requires: archive_size > 0
  ensures: result is Ok => result.unwrap() != 0
{
  let track: Int = unsafe { ozz_float_track_load(archive_data, archive_size) }
  if track == 0 { return Err("float_track_load: failed") }
  return Ok(track)
}

pub fn float2_track_load(archive_data: Int, archive_size: Int) -> Result[Int, Str]
  requires: archive_data != 0
  requires: archive_size > 0
  ensures: result is Ok => result.unwrap() != 0
{
  let track: Int = unsafe { ozz_float2_track_load(archive_data, archive_size) }
  if track == 0 { return Err("float2_track_load: failed") }
  return Ok(track)
}

pub fn float3_track_load(archive_data: Int, archive_size: Int) -> Result[Int, Str]
  requires: archive_data != 0
  requires: archive_size > 0
  ensures: result is Ok => result.unwrap() != 0
{
  let track: Int = unsafe { ozz_float3_track_load(archive_data, archive_size) }
  if track == 0 { return Err("float3_track_load: failed") }
  return Ok(track)
}

pub fn float4_track_load(archive_data: Int, archive_size: Int) -> Result[Int, Str]
  requires: archive_data != 0
  requires: archive_size > 0
  ensures: result is Ok => result.unwrap() != 0
{
  let track: Int = unsafe { ozz_float4_track_load(archive_data, archive_size) }
  if track == 0 { return Err("float4_track_load: failed") }
  return Ok(track)
}

pub fn quaternion_track_load(archive_data: Int, archive_size: Int) -> Result[Int, Str]
  requires: archive_data != 0
  requires: archive_size > 0
  ensures: result is Ok => result.unwrap() != 0
{
  let track: Int = unsafe { ozz_quaternion_track_load(archive_data, archive_size) }
  if track == 0 { return Err("quaternion_track_load: failed") }
  return Ok(track)
}

// --- Track destroy helpers ---

pub fn float_track_destroy(track: Int)
  requires: track != 0
{
  unsafe { ozz_float_track_destroy(track) }
}

pub fn float2_track_destroy(track: Int)
  requires: track != 0
{
  unsafe { ozz_float2_track_destroy(track) }
}

pub fn float3_track_destroy(track: Int)
  requires: track != 0
{
  unsafe { ozz_float3_track_destroy(track) }
}

pub fn float4_track_destroy(track: Int)
  requires: track != 0
{
  unsafe { ozz_float4_track_destroy(track) }
}

pub fn quaternion_track_destroy(track: Int)
  requires: track != 0
{
  unsafe { ozz_quaternion_track_destroy(track) }
}

// --- Offline builders ---

pub fn skeleton_builder_create() -> Result[Int, Str]
  ensures: result is Ok => result.unwrap() != 0
{
  let builder: Int = unsafe { ozz_skeleton_builder_create() }
  if builder == 0 { return Err("skeleton_builder_create: failed") }
  return Ok(builder)
}

pub fn skeleton_builder_destroy(builder: Int)
  requires: builder != 0
{
  unsafe { ozz_skeleton_builder_destroy(builder) }
}

pub fn skeleton_builder_build(builder: Int, raw_skeleton_data: Int, raw_skeleton_size: Int) -> Result[Int, Str]
  requires: builder != 0
  requires: raw_skeleton_data != 0
  requires: raw_skeleton_size > 0
  ensures: result is Ok => result.unwrap() != 0
{
  let skel: Int = unsafe { ozz_skeleton_builder_build(builder, raw_skeleton_data, raw_skeleton_size) }
  if skel == 0 { return Err("skeleton_builder_build: failed") }
  return Ok(skel)
}

pub fn animation_builder_create() -> Result[Int, Str]
  ensures: result is Ok => result.unwrap() != 0
{
  let builder: Int = unsafe { ozz_animation_builder_create() }
  if builder == 0 { return Err("animation_builder_create: failed") }
  return Ok(builder)
}

pub fn animation_builder_destroy(builder: Int)
  requires: builder != 0
{
  unsafe { ozz_animation_builder_destroy(builder) }
}

pub fn animation_builder_set_iframe_interval(builder: Int, interval: Float32)
  requires: builder != 0
{
  unsafe { ozz_animation_builder_set_iframe_interval(builder, interval) }
}

pub fn animation_builder_build(builder: Int, raw_animation_data: Int, raw_animation_size: Int) -> Result[Int, Str]
  requires: builder != 0
  requires: raw_animation_data != 0
  requires: raw_animation_size > 0
  ensures: result is Ok => result.unwrap() != 0
{
  let anim: Int = unsafe { ozz_animation_builder_build(builder, raw_animation_data, raw_animation_size) }
  if anim == 0 { return Err("animation_builder_build: failed") }
  return Ok(anim)
}

// --- Archive I/O helpers ---

pub fn archive_read_file(path: Int) -> Result[Int, Str]
  requires: path != 0
  ensures: result is Ok => result.unwrap() != 0
{
  let handle: Int = unsafe { ozz_archive_read_file(path) }
  if handle == 0 { return Err("archive_read_file: could not open file") }
  return Ok(handle)
}

pub fn archive_read_data(handle: Int) -> Int
  requires: handle != 0
{
  return unsafe { ozz_archive_read_data(handle) }
}

pub fn archive_read_size(handle: Int) -> Int
  requires: handle != 0
{
  return unsafe { ozz_archive_read_size(handle) }
}

pub fn archive_read_close(handle: Int)
  requires: handle != 0
{
  unsafe { ozz_archive_read_close(handle) }
}
