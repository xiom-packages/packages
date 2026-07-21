// XIOM — Ozz-Animation Production Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates full animation pipeline using xiom.ozz and xiom.ozz.safe:
//   1. Load skeleton + animation from Ozz binary archives
//   2. Create sampling context + pose buffers
//   3. Sample animation at a time ratio → local-space pose
//   4. Convert local → model-space (matrix palette for skinning)
//   5. Blend two animations as layers
//   6. Run skinning job
//
// This is a compile-time skeleton showing patterns used in production engines.
// Requires a compiled Ozz C bridge library and .ozz archive files to execute.

module xiom.ozz.demo

use xiom.io

fn main() -> Int {
  io.println("Ozz-Animation Production Demo")
  io.println("==============================")
  io.println("")

  demo_pipeline()
  demo_explanation()

  return 0
}

fn demo_pipeline() {
  io.println("--- Full Pipeline (compile-time skeleton) ---")
  io.println("")

  io.println("Step 1: Load skeleton from .ozz archive")
  io.println("  let archive = archive_read_file(path_ptr)?;")
  io.println("  let skeleton = Skeleton.from_archive(archive.data(), archive.size())?;")
  io.println("  archive_read_close(archive);")
  io.println("")

  io.println("Step 2: Load animation from .ozz archive")
  io.println("  let archive = archive_read_file(path_ptr)?;")
  io.println("  let anim = Animation.from_archive(archive.data(), archive.size())?;")
  io.println("  io.println(animation.name());")
  io.println("  io.println(animation.duration());")
  io.println("")

  io.println("Step 3: Allocate pose buffers")
  io.println("  let soa_count = skeleton.num_soa_joints();")
  io.println("  let local_pose = alloc(soa_count * sizeof_soa_transform);")
  io.println("  let local_cache = alloc(soa_count * sizeof_soa_transform);")
  io.println("  let model_mats = alloc(soa_count * 64); // 64 bytes per Float4x4")
  io.println("")

  io.println("Step 4: Create player and sample")
  io.println("  let player = AnimationPlayer.init(skeleton, anim, local_pose, local_cache, model_mats)?;")
  io.println("  player.sample_at_ratio(0.5);  // frame at 50%%")
  io.println("")

  io.println("Step 5: Blend two animations")
  io.println("  // Sample anim1 → pose1, anim2 → pose2")
  io.println("  sample(anim1, skeleton, 0.3, pose1, cache1);")
  io.println("  sample(anim2, skeleton, 0.7, pose2, cache2);")
  io.println("  let layers = [BlendLayer.create(pose1, 0.6), BlendLayer.create(pose2, 0.4)];")
  io.println("  // C bridge call: ozz_blending_job_run(...)")
  io.println("  blend_poses(skeleton, layers_ptr, weights_ptr, 2, bind_pose, output);")
  io.println("")

  io.println("Step 6: Local-to-model conversion")
  io.println("  local_to_model(skeleton, local_pose, 0, 0, num_soa_joints, 0, model_mats);")
  io.println("  // model_mats now contains world-space matrices ready for skinning")
  io.println("")

  io.println("Step 7: Skin a mesh")
  io.println("  let skin = SkinInput{ vertex_count: 1024, ... };")
  io.println("  skin.skin();")
  io.println("")

  io.println("Step 8: Cleanup")
  io.println("  player.destroy();")
  io.println("  anim.destroy();")
  io.println("  skeleton.destroy();")
  io.println("  free(local_pose); free(local_cache); free(model_mats);")
  io.println("")

  io.println("--- Pipeline OK (compile-time verification) ---")
  io.println("")
}

fn demo_explanation() {
  io.println("=== Per-frame loop pattern ===")
  io.println("")
  io.println("1. sample_animation(ctx, anim, skeleton, ratio, local_pose, cache);")
  io.println("2. local_to_model(skeleton, local_pose, root_ptr, 0, num_joints, 0, model_mats);")
  io.println("3. skin_mesh(model_mats, in_verts, out_verts);")
  io.println("4. Submit out_verts to GPU")
  io.println("")

  io.println("=== Procedural API (xiom.ozz) ===")
  io.println("    let ctx = sampling_context_create(num_tracks)?;")
  io.println("    sample_animation(ctx, anim, skeleton, 0.5, pose, cache);")
  io.println("    blend_poses(skeleton, layers, weights, 2, bind_pose, output);")
  io.println("    local_to_model(skeleton, input, root, 0, 64, 0, matrices);")
  io.println("    skin_vertices(vc, 4, matrices, ..., out_positions, ...);")
  io.println("    sampling_context_destroy(ctx);")
  io.println("")

  io.println("=== Struct-based API (xiom.ozz.safe) ===")
  io.println("    let skeleton = Skeleton.from_archive(data, size)?;")
  io.println("    let anim = Animation.from_archive(data, size)?;")
  io.println("    let player = AnimationPlayer.init(skeleton, anim, pose, cache, mats)?;")
  io.println("    player.sample_at_ratio(0.5);")
  io.println("    player.destroy();")
  io.println("    anim.destroy();")
  io.println("    skeleton.destroy();")
  io.println("")

  io.println("=== Data flow ===")
  io.println("  .ozz file  →  archive  →  Skeleton / Animation (runtime)")
  io.println("  Animation + ratio  →  SamplingJob  →  SoaTransform (local pose)")
  io.println("  Skeleton + SoaTransform  →  LocalToModelJob  →  Float4x4[] (model pose)")
  io.println("  Skeleton + Float4x4[] + mesh  →  SkinningJob  →  vertices (world)")
  io.println("")

  io.println("=== Key types ===")
  io.println("  Skeleton:        joint hierarchy, parent indices, rest poses (max 1024)")
  io.println("  Animation:       compressed keyframes, duration, num_tracks")
  io.println("  SamplingContext: frame-coherent cache for SamplingJob")
  io.println("  SoaTransform:    4-wide Structure-of-Arrays local transform")
  io.println("  Float4x4:        4x4 column-major matrix (SSE-backed)")
  io.println("  SkinningJob:     GPU-style matrix palette skinning")
  io.println("")
}
