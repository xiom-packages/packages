// XIOM -- xiom.shaderc.symbols -- generated symbol-name oracle
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// GENERATED FILE -- do not edit by hand.
// Source: tools/gen_shaderc.py
// Oracle: C:\VulkanSDK\1.4.350.0\Include\shaderc (shaderc,env,status,visibility).h
// Pinned upstream: google/shaderc v2026.4 (see SPEC.md / PROVENANCE.md).
// Regenerate: python tools/gen_shaderc.py


module xiom.shaderc.symbols

/// Number of shaderc C entry points declared by the pinned headers
/// (the oracle N; equals the SHADERC_EXPORT declaration count).
pub const SHADERC_SYMBOL_COUNT: Int = 45;

/// Oracle function name at `index` (declaration order of the pinned
/// headers); "" for an out-of-range index.
/// Complexity: O(1).
pub fn shaderc_symbol_name(index: Int) -> Str
  requires: index >= 0
{
  if index == 0 { return "shaderc_compiler_initialize"; }
  if index == 1 { return "shaderc_compiler_release"; }
  if index == 2 { return "shaderc_compile_options_initialize"; }
  if index == 3 { return "shaderc_compile_options_clone"; }
  if index == 4 { return "shaderc_compile_options_release"; }
  if index == 5 { return "shaderc_compile_options_add_macro_definition"; }
  if index == 6 { return "shaderc_compile_options_set_source_language"; }
  if index == 7 { return "shaderc_compile_options_set_generate_debug_info"; }
  if index == 8 { return "shaderc_compile_options_set_optimization_level"; }
  if index == 9 { return "shaderc_compile_options_set_forced_version_profile"; }
  if index == 10 { return "shaderc_compile_options_set_include_callbacks"; }
  if index == 11 { return "shaderc_compile_options_set_suppress_warnings"; }
  if index == 12 { return "shaderc_compile_options_set_target_env"; }
  if index == 13 { return "shaderc_compile_options_set_target_spirv"; }
  if index == 14 { return "shaderc_compile_options_set_warnings_as_errors"; }
  if index == 15 { return "shaderc_compile_options_set_limit"; }
  if index == 16 { return "shaderc_compile_options_set_auto_bind_uniforms"; }
  if index == 17 { return "shaderc_compile_options_set_auto_combined_image_sampler"; }
  if index == 18 { return "shaderc_compile_options_set_hlsl_io_mapping"; }
  if index == 19 { return "shaderc_compile_options_set_hlsl_offsets"; }
  if index == 20 { return "shaderc_compile_options_set_binding_base"; }
  if index == 21 { return "shaderc_compile_options_set_binding_base_for_stage"; }
  if index == 22 { return "shaderc_compile_options_set_preserve_bindings"; }
  if index == 23 { return "shaderc_compile_options_set_max_id_bound"; }
  if index == 24 { return "shaderc_compile_options_set_auto_map_locations"; }
  if index == 25 { return "shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage"; }
  if index == 26 { return "shaderc_compile_options_set_hlsl_register_set_and_binding"; }
  if index == 27 { return "shaderc_compile_options_set_hlsl_functionality1"; }
  if index == 28 { return "shaderc_compile_options_set_hlsl_16bit_types"; }
  if index == 29 { return "shaderc_compile_options_set_vulkan_rules_relaxed"; }
  if index == 30 { return "shaderc_compile_options_set_invert_y"; }
  if index == 31 { return "shaderc_compile_options_set_nan_clamp"; }
  if index == 32 { return "shaderc_compile_into_spv"; }
  if index == 33 { return "shaderc_compile_into_spv_assembly"; }
  if index == 34 { return "shaderc_compile_into_preprocessed_text"; }
  if index == 35 { return "shaderc_assemble_into_spv"; }
  if index == 36 { return "shaderc_result_release"; }
  if index == 37 { return "shaderc_result_get_length"; }
  if index == 38 { return "shaderc_result_get_num_warnings"; }
  if index == 39 { return "shaderc_result_get_num_errors"; }
  if index == 40 { return "shaderc_result_get_compilation_status"; }
  if index == 41 { return "shaderc_result_get_bytes"; }
  if index == 42 { return "shaderc_result_get_error_message"; }
  if index == 43 { return "shaderc_get_spv_version"; }
  if index == 44 { return "shaderc_parse_version_profile"; }
  return "";
}
