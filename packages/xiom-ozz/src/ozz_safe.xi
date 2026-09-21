// XIOM -- Ozz-Animation Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Struct-based safe resource management for Ozz-Animation v0.16.0.
// All create/destroy pairs with Result[T, OzzError] + design-by-contract.
//
// COVERAGE: 6 resource types spanning the full animation pipeline:
//   Skeleton, Animation, SamplingContext, SkinOutput, PoseBuffer, BlendLayer

module xiom.ozz.safe

// =========================================================================
// Cross-module extern block (workaround for compiler gap: cross-module
// extern resolution is broken -- T001 errors on import)
// =========================================================================

extern "C" {
  fn ozz_skeleton_load(archive_data: Int, archive_size: Int) -> Int
  fn ozz_skeleton_destroy(skeleton: Int)
  fn ozz_skeleton_num_joints(skeleton: Int) -> Int32
  fn ozz_skeleton_num_soa_joints(skeleton: Int) -> Int32
  fn ozz_skeleton_joint_parents(skeleton: Int, out_count: Int) -> Int
  fn ozz_skeleton_joint_name(skeleton: Int, index: Int32) -> Int

  fn ozz_animation_load(archive_data: Int, archive_size: Int) -> Int
  fn ozz_animation_destroy(animation: Int)
  fn ozz_animation_duration(animation: Int) -> Float32
  fn ozz_animation_num_tracks(animation: Int) -> Int32
  fn ozz_animation_name(animation: Int) -> Int
  fn ozz_animation_time_ratio(animation: Int, time: Float32) -> Float32

  fn ozz_sampling_context_create(max_tracks: Int32) -> Int
  fn ozz_sampling_context_destroy(context: Int)
  fn ozz_sampling_context_resize(context: Int, max_tracks: Int32) -> Int32
  fn ozz_sampling_context_reset(context: Int)
  fn ozz_sampling_job_run(context: Int, animation: Int, skeleton: Int, ratio: Float32, output: Int, cache: Int) -> Int32

  fn ozz_blending_job_run(skeleton: Int, layers: Int, weights: Int, num_layers: Int32, bind_pose: Int, output: Int) -> Int32
  fn ozz_blending_job_run_additive(skeleton: Int, layers: Int, weights: Int, num_layers: Int32, additive_layers: Int, additive_weights: Int, num_additive: Int32, bind_pose: Int, output: Int) -> Int32

  fn ozz_local_to_model_job_run(skeleton: Int, input: Int, root: Int, from: Int32, to: Int32, from_excluded: Int32, output: Int) -> Int32

  fn ozz_skinning_job_run(vertex_count: Int32, influences_count: Int32, joint_matrices: Int, joint_inverse_transpose_matrices: Int, joint_indices: Int, joint_indices_stride: Int, joint_weights: Int, joint_weights_stride: Int, in_positions: Int, in_positions_stride: Int, in_normals: Int, in_normals_stride: Int, in_tangents: Int, in_tangents_stride: Int, out_positions: Int, out_positions_stride: Int, out_normals: Int, out_normals_stride: Int, out_tangents: Int, out_tangents_stride: Int) -> Int32

  fn ozz_skeleton_builder_create() -> Int
  fn ozz_skeleton_builder_destroy(builder: Int)
  fn ozz_skeleton_builder_build(builder: Int, raw_skeleton_data: Int, raw_skeleton_size: Int) -> Int

  fn ozz_animation_builder_create() -> Int
  fn ozz_animation_builder_destroy(builder: Int)
  fn ozz_animation_builder_set_iframe_interval(builder: Int, interval: Float32)
  fn ozz_animation_builder_build(builder: Int, raw_animation_data: Int, raw_animation_size: Int) -> Int
}

// =========================================================================
// OzzError
// =========================================================================

pub type OzzError = {
  message: Str
} derive[Clone]

// =========================================================================
// Math types (local copies for self-contained module)
// =========================================================================

pub type Float3 = {
  x: Float32
  y: Float32
  z: Float32
} derive[Clone]

pub type Quaternion = {
  x: Float32
  y: Float32
  z: Float32
  w: Float32
} derive[Clone]

// =========================================================================
// Skeleton -- const runtime skeleton (joint hierarchy, rest poses)
// =========================================================================

pub type Skeleton = {
  handle: Int
} derive[Clone]

pub fn Skeleton.from_archive(archive_data: Int, archive_size: Int) -> Result[Skeleton, OzzError]
  requires: archive_data != 0
  requires: archive_size > 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let skel: Int = unsafe { ozz_skeleton_load(archive_data, archive_size) }
  if skel == 0 { return Err(OzzError{ message: "failed to deserialize skeleton" }) }
  return Ok(Skeleton{ handle: skel })
}

pub fn Skeleton.destroy()
  requires: handle != 0
{
  unsafe { ozz_skeleton_destroy(handle) }
}

pub fn Skeleton.num_joints() -> Int32
  requires: handle != 0
{
  return unsafe { ozz_skeleton_num_joints(handle) }
}

pub fn Skeleton.num_soa_joints() -> Int32
  requires: handle != 0
{
  return unsafe { ozz_skeleton_num_soa_joints(handle) }
}

pub fn Skeleton.joint_parents(out_count: Int) -> Int
  requires: handle != 0
  requires: out_count != 0
{
  return unsafe { ozz_skeleton_joint_parents(handle, out_count) }
}

pub fn Skeleton.joint_name(index: Int32) -> Int
  requires: handle != 0
  requires: index >= 0
{
  return unsafe { ozz_skeleton_joint_name(handle, index) }
}

// =========================================================================
// Animation -- const runtime clip (keyframes, duration)
// =========================================================================

pub type Animation = {
  handle: Int
} derive[Clone]

pub fn Animation.from_archive(archive_data: Int, archive_size: Int) -> Result[Animation, OzzError]
  requires: archive_data != 0
  requires: archive_size > 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let anim: Int = unsafe { ozz_animation_load(archive_data, archive_size) }
  if anim == 0 { return Err(OzzError{ message: "failed to deserialize animation" }) }
  return Ok(Animation{ handle: anim })
}

pub fn Animation.destroy()
  requires: handle != 0
{
  unsafe { ozz_animation_destroy(handle) }
}

pub fn Animation.duration() -> Float32
  requires: handle != 0
{
  return unsafe { ozz_animation_duration(handle) }
}

pub fn Animation.num_tracks() -> Int32
  requires: handle != 0
{
  return unsafe { ozz_animation_num_tracks(handle) }
}

pub fn Animation.time_ratio(time: Float32) -> Float32
  requires: handle != 0
  requires: time >= 0.0
{
  return unsafe { ozz_animation_time_ratio(handle, time) }
}

pub fn Animation.name() -> Int
  requires: handle != 0
{
  return unsafe { ozz_animation_name(handle) }
}

// =========================================================================
// SamplingContext -- frame-coherent sampling cache
// =========================================================================

pub type SamplingContext = {
  handle: Int
} derive[Clone]

pub fn SamplingContext.create(max_tracks: Int32) -> Result[SamplingContext, OzzError]
  requires: max_tracks > 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let ctx: Int = unsafe { ozz_sampling_context_create(max_tracks) }
  if ctx == 0 { return Err(OzzError{ message: "failed to create sampling context" }) }
  return Ok(SamplingContext{ handle: ctx })
}

pub fn SamplingContext.destroy()
  requires: handle != 0
{
  unsafe { ozz_sampling_context_destroy(handle) }
}

pub fn SamplingContext.resize(max_tracks: Int32) -> Bool
  requires: handle != 0
  requires: max_tracks > 0
{
  let res: Int32 = unsafe { ozz_sampling_context_resize(handle, max_tracks) }
  return res != 0
}

pub fn SamplingContext.reset()
  requires: handle != 0
{
  unsafe { ozz_sampling_context_reset(handle) }
}

pub fn SamplingContext.sample(animation: Int, skeleton: Int, ratio: Float32, output: Int, cache: Int) -> Bool
  requires: handle != 0
  requires: animation != 0
  requires: skeleton != 0
  requires: output != 0
  requires: cache != 0
{
  let res: Int32 = unsafe { ozz_sampling_job_run(handle, animation, skeleton, ratio, output, cache) }
  return res != 0
}

// =========================================================================
// PoseBuffer -- allocated SoA pose buffer for sample/blend output
// =========================================================================

pub type PoseBuffer = {
  ptr: Int
  soa_count: Int32
  bytes_per_soa: Int
} derive[Clone]

// =========================================================================
// BlendLayer -- a single animation layer with weight for blending
// =========================================================================

pub type BlendLayer = {
  pose_ptr: Int
  weight: Float32
} derive[Clone]

pub fn BlendLayer.create(pose_ptr: Int, weight: Float32) -> BlendLayer
  requires: pose_ptr != 0
  requires: weight >= 0.0
{
  return BlendLayer{ pose_ptr: pose_ptr, weight: weight }
}

// =========================================================================
// Skinning -- vertex skinning job using matrix palette
// =========================================================================

pub type SkinInput = {
  vertex_count: Int32
  influences_count: Int32
  joint_matrices: Int
  joint_indices: Int
  joint_indices_stride: Int
  joint_weights: Int
  joint_weights_stride: Int
  in_positions: Int
  in_positions_stride: Int
  in_normals: Int
  in_normals_stride: Int
  out_positions: Int
  out_positions_stride: Int
  out_normals: Int
  out_normals_stride: Int
}

pub fn SkinInput.skin() -> Bool
  requires: vertex_count > 0
  requires: joint_matrices != 0
  requires: joint_indices != 0
  requires: joint_weights != 0
  requires: in_positions != 0
  requires: out_positions != 0
{
  let res: Int32 = unsafe { ozz_skinning_job_run(vertex_count, influences_count, joint_matrices, 0, joint_indices, joint_indices_stride, joint_weights, joint_weights_stride, in_positions, in_positions_stride, in_normals, in_normals_stride, 0, 0, out_positions, out_positions_stride, out_normals, out_normals_stride, 0, 0) }
  return res != 0
}

// =========================================================================
// OfflineBuilder -- builds runtime Skeleton/Animation from raw data
// =========================================================================

pub type OfflineBuilder = {
  handle: Int
} derive[Clone]

pub fn OfflineBuilder.create() -> Result[OfflineBuilder, OzzError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let builder: Int = unsafe { ozz_skeleton_builder_create() }
  if builder == 0 { return Err(OzzError{ message: "failed to create offline builder" }) }
  return Ok(OfflineBuilder{ handle: builder })
}

pub fn OfflineBuilder.destroy()
  requires: handle != 0
{
  unsafe { ozz_skeleton_builder_destroy(handle) }
}

pub fn OfflineBuilder.build_skeleton(raw_skeleton_data: Int, raw_skeleton_size: Int) -> Result[Skeleton, OzzError]
  requires: handle != 0
  requires: raw_skeleton_data != 0
  requires: raw_skeleton_size > 0
{
  let skel: Int = unsafe { ozz_skeleton_builder_build(handle, raw_skeleton_data, raw_skeleton_size) }
  if skel == 0 { return Err(OzzError{ message: "failed to build skeleton" }) }
  return Ok(Skeleton{ handle: skel })
}

// =========================================================================
// AnimationOfflineBuilder -- builds runtime Animation from raw data
// =========================================================================

pub type AnimationOfflineBuilder = {
  handle: Int
} derive[Clone]

pub fn AnimationOfflineBuilder.create() -> Result[AnimationOfflineBuilder, OzzError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let builder: Int = unsafe { ozz_animation_builder_create() }
  if builder == 0 { return Err(OzzError{ message: "failed to create animation builder" }) }
  return Ok(AnimationOfflineBuilder{ handle: builder })
}

pub fn AnimationOfflineBuilder.destroy()
  requires: handle != 0
{
  unsafe { ozz_animation_builder_destroy(handle) }
}

pub fn AnimationOfflineBuilder.set_iframe_interval(interval: Float32)
  requires: handle != 0
  requires: interval >= 0.0
{
  unsafe { ozz_animation_builder_set_iframe_interval(handle, interval) }
}

pub fn AnimationOfflineBuilder.build(raw_animation_data: Int, raw_animation_size: Int) -> Result[Animation, OzzError]
  requires: handle != 0
  requires: raw_animation_data != 0
  requires: raw_animation_size > 0
{
  let anim: Int = unsafe { ozz_animation_builder_build(handle, raw_animation_data, raw_animation_size) }
  if anim == 0 { return Err(OzzError{ message: "failed to build animation" }) }
  return Ok(Animation{ handle: anim })
}

// =========================================================================
// AnimationPlayer -- high-level player managing skeleton, animation,
//                       sampling context, and pose buffers
// =========================================================================

pub type AnimationPlayer = {
  skeleton: Skeleton
  animation: Animation
  sampling_context: SamplingContext
  local_pose: Int
  local_cache: Int
  model_matrices: Int
  num_soa_joints: Int32
} derive[Clone]

pub fn AnimationPlayer.init(skeleton: Skeleton, animation: Animation, local_pose: Int, local_cache: Int, model_matrices: Int) -> Result[AnimationPlayer, OzzError]
  requires: skeleton.handle != 0
  requires: animation.handle != 0
  requires: local_pose != 0
  requires: local_cache != 0
  requires: model_matrices != 0
{
  let num_tracks: Int32 = animation.num_tracks()
  let ctx_result = SamplingContext.create(num_tracks)
  match ctx_result {
    Err(e) => { return Err(e) }
    Ok(ctx) => {
      return Ok(AnimationPlayer{
        skeleton: skeleton
        animation: animation
        sampling_context: ctx
        local_pose: local_pose
        local_cache: local_cache
        model_matrices: model_matrices
        num_soa_joints: skeleton.num_soa_joints()
      })
    }
  }
}

pub fn AnimationPlayer.sample_at_ratio(ratio: Float32) -> Bool
  requires: sampling_context.handle != 0
  requires: local_pose != 0
  requires: local_cache != 0
  requires: ratio >= 0.0
  requires: ratio <= 1.0
{
  let success = sampling_context.sample(animation.handle, skeleton.handle, ratio, local_pose, local_cache)
  if !success { return false }
  let model_ok: Int32 = unsafe { ozz_local_to_model_job_run(skeleton.handle, local_pose, 0, 0, num_soa_joints, 0, model_matrices) }
  return model_ok != 0
}

pub fn AnimationPlayer.sample_at_time(time: Float32) -> Bool
  requires: sampling_context.handle != 0
  requires: local_pose != 0
  requires: local_cache != 0
  requires: time >= 0.0
{
  let ratio: Float32 = animation.time_ratio(time)
  return sample_at_ratio(ratio)
}

pub fn AnimationPlayer.destroy()
  requires: sampling_context.handle != 0
{
  sampling_context.destroy()
}
