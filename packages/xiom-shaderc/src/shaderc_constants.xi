// XIOM -- xiom.shaderc.constants -- generated enum constants
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// GENERATED FILE -- do not edit by hand.
// Source: tools/gen_shaderc.py
// Oracle: C:\VulkanSDK\1.4.350.0\Include\shaderc (shaderc,env,status,visibility).h
// Pinned upstream: google/shaderc v2026.4 (see SPEC.md / PROVENANCE.md).
// Regenerate: python tools/gen_shaderc.py


module xiom.shaderc.constants

/// Number of enum constants bound from the pinned headers.
pub const SHADERC_CONSTANT_COUNT: Int = 191;

// ---- shaderc_source ----
pub const shaderc_source_language_glsl: Int = 0;
pub const shaderc_source_language_hlsl: Int = 1;
// ---- shaderc_vertex ----
pub const shaderc_vertex_shader: Int = 0;
// ---- shaderc_fragment ----
pub const shaderc_fragment_shader: Int = 1;
// ---- shaderc_compute ----
pub const shaderc_compute_shader: Int = 2;
// ---- shaderc_geometry ----
pub const shaderc_geometry_shader: Int = 3;
// ---- shaderc_tess ----
pub const shaderc_tess_control_shader: Int = 4;
pub const shaderc_tess_evaluation_shader: Int = 5;
// ---- shaderc_glsl ----
pub const shaderc_glsl_vertex_shader: Int = 0;
pub const shaderc_glsl_fragment_shader: Int = 1;
pub const shaderc_glsl_compute_shader: Int = 2;
pub const shaderc_glsl_geometry_shader: Int = 3;
pub const shaderc_glsl_tess_control_shader: Int = 4;
pub const shaderc_glsl_tess_evaluation_shader: Int = 5;
pub const shaderc_glsl_infer_from_source: Int = 6;
pub const shaderc_glsl_default_vertex_shader: Int = 7;
pub const shaderc_glsl_default_fragment_shader: Int = 8;
pub const shaderc_glsl_default_compute_shader: Int = 9;
pub const shaderc_glsl_default_geometry_shader: Int = 10;
pub const shaderc_glsl_default_tess_control_shader: Int = 11;
pub const shaderc_glsl_default_tess_evaluation_shader: Int = 12;
// ---- shaderc_spirv ----
pub const shaderc_spirv_assembly: Int = 13;
// ---- shaderc_raygen ----
pub const shaderc_raygen_shader: Int = 14;
// ---- shaderc_anyhit ----
pub const shaderc_anyhit_shader: Int = 15;
// ---- shaderc_closesthit ----
pub const shaderc_closesthit_shader: Int = 16;
// ---- shaderc_miss ----
pub const shaderc_miss_shader: Int = 17;
// ---- shaderc_intersection ----
pub const shaderc_intersection_shader: Int = 18;
// ---- shaderc_callable ----
pub const shaderc_callable_shader: Int = 19;
// ---- shaderc_glsl ----
pub const shaderc_glsl_raygen_shader: Int = 14;
pub const shaderc_glsl_anyhit_shader: Int = 15;
pub const shaderc_glsl_closesthit_shader: Int = 16;
pub const shaderc_glsl_miss_shader: Int = 17;
pub const shaderc_glsl_intersection_shader: Int = 18;
pub const shaderc_glsl_callable_shader: Int = 19;
pub const shaderc_glsl_default_raygen_shader: Int = 20;
pub const shaderc_glsl_default_anyhit_shader: Int = 21;
pub const shaderc_glsl_default_closesthit_shader: Int = 22;
pub const shaderc_glsl_default_miss_shader: Int = 23;
pub const shaderc_glsl_default_intersection_shader: Int = 24;
pub const shaderc_glsl_default_callable_shader: Int = 25;
// ---- shaderc_task ----
pub const shaderc_task_shader: Int = 26;
// ---- shaderc_mesh ----
pub const shaderc_mesh_shader: Int = 27;
// ---- shaderc_glsl ----
pub const shaderc_glsl_task_shader: Int = 26;
pub const shaderc_glsl_mesh_shader: Int = 27;
pub const shaderc_glsl_default_task_shader: Int = 28;
pub const shaderc_glsl_default_mesh_shader: Int = 29;
// ---- shaderc_profile ----
pub const shaderc_profile_none: Int = 0;
pub const shaderc_profile_core: Int = 1;
pub const shaderc_profile_compatibility: Int = 2;
pub const shaderc_profile_es: Int = 3;
// ---- shaderc_optimization ----
pub const shaderc_optimization_level_zero: Int = 0;
pub const shaderc_optimization_level_size: Int = 1;
pub const shaderc_optimization_level_performance: Int = 2;
// ---- shaderc_limit ----
pub const shaderc_limit_max_lights: Int = 0;
pub const shaderc_limit_max_clip_planes: Int = 1;
pub const shaderc_limit_max_texture_units: Int = 2;
pub const shaderc_limit_max_texture_coords: Int = 3;
pub const shaderc_limit_max_vertex_attribs: Int = 4;
pub const shaderc_limit_max_vertex_uniform_components: Int = 5;
pub const shaderc_limit_max_varying_floats: Int = 6;
pub const shaderc_limit_max_vertex_texture_image_units: Int = 7;
pub const shaderc_limit_max_combined_texture_image_units: Int = 8;
pub const shaderc_limit_max_texture_image_units: Int = 9;
pub const shaderc_limit_max_fragment_uniform_components: Int = 10;
pub const shaderc_limit_max_draw_buffers: Int = 11;
pub const shaderc_limit_max_vertex_uniform_vectors: Int = 12;
pub const shaderc_limit_max_varying_vectors: Int = 13;
pub const shaderc_limit_max_fragment_uniform_vectors: Int = 14;
pub const shaderc_limit_max_vertex_output_vectors: Int = 15;
pub const shaderc_limit_max_fragment_input_vectors: Int = 16;
pub const shaderc_limit_min_program_texel_offset: Int = 17;
pub const shaderc_limit_max_program_texel_offset: Int = 18;
pub const shaderc_limit_max_clip_distances: Int = 19;
pub const shaderc_limit_max_compute_work_group_count_x: Int = 20;
pub const shaderc_limit_max_compute_work_group_count_y: Int = 21;
pub const shaderc_limit_max_compute_work_group_count_z: Int = 22;
pub const shaderc_limit_max_compute_work_group_size_x: Int = 23;
pub const shaderc_limit_max_compute_work_group_size_y: Int = 24;
pub const shaderc_limit_max_compute_work_group_size_z: Int = 25;
pub const shaderc_limit_max_compute_uniform_components: Int = 26;
pub const shaderc_limit_max_compute_texture_image_units: Int = 27;
pub const shaderc_limit_max_compute_image_uniforms: Int = 28;
pub const shaderc_limit_max_compute_atomic_counters: Int = 29;
pub const shaderc_limit_max_compute_atomic_counter_buffers: Int = 30;
pub const shaderc_limit_max_varying_components: Int = 31;
pub const shaderc_limit_max_vertex_output_components: Int = 32;
pub const shaderc_limit_max_geometry_input_components: Int = 33;
pub const shaderc_limit_max_geometry_output_components: Int = 34;
pub const shaderc_limit_max_fragment_input_components: Int = 35;
pub const shaderc_limit_max_image_units: Int = 36;
pub const shaderc_limit_max_combined_image_units_and_fragment_outputs: Int = 37;
pub const shaderc_limit_max_combined_shader_output_resources: Int = 38;
pub const shaderc_limit_max_image_samples: Int = 39;
pub const shaderc_limit_max_vertex_image_uniforms: Int = 40;
pub const shaderc_limit_max_tess_control_image_uniforms: Int = 41;
pub const shaderc_limit_max_tess_evaluation_image_uniforms: Int = 42;
pub const shaderc_limit_max_geometry_image_uniforms: Int = 43;
pub const shaderc_limit_max_fragment_image_uniforms: Int = 44;
pub const shaderc_limit_max_combined_image_uniforms: Int = 45;
pub const shaderc_limit_max_geometry_texture_image_units: Int = 46;
pub const shaderc_limit_max_geometry_output_vertices: Int = 47;
pub const shaderc_limit_max_geometry_total_output_components: Int = 48;
pub const shaderc_limit_max_geometry_uniform_components: Int = 49;
pub const shaderc_limit_max_geometry_varying_components: Int = 50;
pub const shaderc_limit_max_tess_control_input_components: Int = 51;
pub const shaderc_limit_max_tess_control_output_components: Int = 52;
pub const shaderc_limit_max_tess_control_texture_image_units: Int = 53;
pub const shaderc_limit_max_tess_control_uniform_components: Int = 54;
pub const shaderc_limit_max_tess_control_total_output_components: Int = 55;
pub const shaderc_limit_max_tess_evaluation_input_components: Int = 56;
pub const shaderc_limit_max_tess_evaluation_output_components: Int = 57;
pub const shaderc_limit_max_tess_evaluation_texture_image_units: Int = 58;
pub const shaderc_limit_max_tess_evaluation_uniform_components: Int = 59;
pub const shaderc_limit_max_tess_patch_components: Int = 60;
pub const shaderc_limit_max_patch_vertices: Int = 61;
pub const shaderc_limit_max_tess_gen_level: Int = 62;
pub const shaderc_limit_max_viewports: Int = 63;
pub const shaderc_limit_max_vertex_atomic_counters: Int = 64;
pub const shaderc_limit_max_tess_control_atomic_counters: Int = 65;
pub const shaderc_limit_max_tess_evaluation_atomic_counters: Int = 66;
pub const shaderc_limit_max_geometry_atomic_counters: Int = 67;
pub const shaderc_limit_max_fragment_atomic_counters: Int = 68;
pub const shaderc_limit_max_combined_atomic_counters: Int = 69;
pub const shaderc_limit_max_atomic_counter_bindings: Int = 70;
pub const shaderc_limit_max_vertex_atomic_counter_buffers: Int = 71;
pub const shaderc_limit_max_tess_control_atomic_counter_buffers: Int = 72;
pub const shaderc_limit_max_tess_evaluation_atomic_counter_buffers: Int = 73;
pub const shaderc_limit_max_geometry_atomic_counter_buffers: Int = 74;
pub const shaderc_limit_max_fragment_atomic_counter_buffers: Int = 75;
pub const shaderc_limit_max_combined_atomic_counter_buffers: Int = 76;
pub const shaderc_limit_max_atomic_counter_buffer_size: Int = 77;
pub const shaderc_limit_max_transform_feedback_buffers: Int = 78;
pub const shaderc_limit_max_transform_feedback_interleaved_components: Int = 79;
pub const shaderc_limit_max_cull_distances: Int = 80;
pub const shaderc_limit_max_combined_clip_and_cull_distances: Int = 81;
pub const shaderc_limit_max_samples: Int = 82;
pub const shaderc_limit_max_mesh_output_vertices_nv: Int = 83;
pub const shaderc_limit_max_mesh_output_primitives_nv: Int = 84;
pub const shaderc_limit_max_mesh_work_group_size_x_nv: Int = 85;
pub const shaderc_limit_max_mesh_work_group_size_y_nv: Int = 86;
pub const shaderc_limit_max_mesh_work_group_size_z_nv: Int = 87;
pub const shaderc_limit_max_task_work_group_size_x_nv: Int = 88;
pub const shaderc_limit_max_task_work_group_size_y_nv: Int = 89;
pub const shaderc_limit_max_task_work_group_size_z_nv: Int = 90;
pub const shaderc_limit_max_mesh_view_count_nv: Int = 91;
pub const shaderc_limit_max_mesh_output_vertices_ext: Int = 92;
pub const shaderc_limit_max_mesh_output_primitives_ext: Int = 93;
pub const shaderc_limit_max_mesh_work_group_size_x_ext: Int = 94;
pub const shaderc_limit_max_mesh_work_group_size_y_ext: Int = 95;
pub const shaderc_limit_max_mesh_work_group_size_z_ext: Int = 96;
pub const shaderc_limit_max_task_work_group_size_x_ext: Int = 97;
pub const shaderc_limit_max_task_work_group_size_y_ext: Int = 98;
pub const shaderc_limit_max_task_work_group_size_z_ext: Int = 99;
pub const shaderc_limit_max_mesh_view_count_ext: Int = 100;
pub const shaderc_limit_max_dual_source_draw_buffers_ext: Int = 101;
// ---- shaderc_uniform ----
pub const shaderc_uniform_kind_image: Int = 0;
pub const shaderc_uniform_kind_sampler: Int = 1;
pub const shaderc_uniform_kind_texture: Int = 2;
pub const shaderc_uniform_kind_buffer: Int = 3;
pub const shaderc_uniform_kind_storage_buffer: Int = 4;
pub const shaderc_uniform_kind_unordered_access_view: Int = 5;
// ---- shaderc_include ----
pub const shaderc_include_type_relative: Int = 0;
pub const shaderc_include_type_standard: Int = 1;
// ---- shaderc_target ----
pub const shaderc_target_env_vulkan: Int = 0;
pub const shaderc_target_env_opengl: Int = 1;
pub const shaderc_target_env_opengl_compat: Int = 2;
pub const shaderc_target_env_webgpu: Int = 3;
pub const shaderc_target_env_default: Int = 0;
// ---- shaderc_env ----
pub const shaderc_env_version_vulkan_1_0: Int = 4194304;
pub const shaderc_env_version_vulkan_1_1: Int = 4198400;
pub const shaderc_env_version_vulkan_1_2: Int = 4202496;
pub const shaderc_env_version_vulkan_1_3: Int = 4206592;
pub const shaderc_env_version_vulkan_1_4: Int = 4210688;
pub const shaderc_env_version_opengl_4_5: Int = 450;
pub const shaderc_env_version_webgpu: Int = 451;
// ---- shaderc_spirv ----
pub const shaderc_spirv_version_1_0: Int = 65536;
pub const shaderc_spirv_version_1_1: Int = 65792;
pub const shaderc_spirv_version_1_2: Int = 66048;
pub const shaderc_spirv_version_1_3: Int = 66304;
pub const shaderc_spirv_version_1_4: Int = 66560;
pub const shaderc_spirv_version_1_5: Int = 66816;
pub const shaderc_spirv_version_1_6: Int = 67072;
// ---- shaderc_compilation ----
pub const shaderc_compilation_status_success: Int = 0;
pub const shaderc_compilation_status_invalid_stage: Int = 1;
pub const shaderc_compilation_status_compilation_error: Int = 2;
pub const shaderc_compilation_status_internal_error: Int = 3;
pub const shaderc_compilation_status_null_result_object: Int = 4;
pub const shaderc_compilation_status_invalid_assembly: Int = 5;
pub const shaderc_compilation_status_validation_error: Int = 6;
pub const shaderc_compilation_status_transformation_error: Int = 7;
pub const shaderc_compilation_status_configuration_error: Int = 8;
