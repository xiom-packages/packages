# COVERAGE -- xiom.spirv-cross

Full-API binding of the SPIRV-Cross C interface. All numbers below are
reproducible from committed tooling; no hand counting.

## Counts

| Metric | Value | Source |
|---|---|---|
| **Oracle N** (header-declared `SPVC_PUBLIC_API` functions) | **169** | parse of `spirv_cross_c.h` (spirv_cross_c.h SHA256 `8939834E...26D4F`) |
| **Bound N** (typed wrapper per function) | **169** | generator emission (asserted 1:1) |
| **Resolved N** (runtime, shipped DLL) | **169/169** | `spvc_probe_resolution()` in the suite |
| DLL exports not declared in header | **0** | `tools/check_exports.py` |
| Header functions not exported by DLL | **0** (empty list below) | `tools/check_exports.py` |
| Enum members bound as constants | 242 (23 enums) | generator inventory |
| Macros bound as constants | 19 (+ `SPVC_MAKE_MSL_VERSION` as `spvc_make_msl_version()`) | generator inventory |
| Struct sizeof constants | 17 | generator x64 layout pass |
| Total `pub const` in module | 284 | `spirv_cross.xi` |
| Suite checks | 20 PASS with DLL; 4 PASS (2 x SKIP) without | `xiom --run tests/test_conformance.xi` |

## Commands

From `packages/xiom-spirv-cross`:

```
python tools/gen_spirv_cross.py --check     # oracle + inventory + sizeofs
python tools/gen_spirv_cross.py             # regenerate fragments + module
python tools/check_exports.py               # exports=<n> header=<n> missing=<n> extra=<n>
python tools/embed_spv_xiom.py              # re-embed the SPIR-V fixture
xiom --run tests/test_conformance.xi        # suite (resolved=N/N line)
```

Observed (2026-10-11, Vulkan SDK 1.4.350.0 on PATH):

```
python tools/check_exports.py
exports=169 (spvc_*=169) header=169 missing=0 extra=0

xiom --run tests/test_conformance.xi
  [PASS] loader: resolved=169/169 header-declared spvc_* symbols
  ...
xiom.spirv-cross: suite green
```

With `spirv-cross-c-shared.dll` not on `PATH`:

```
  [PASS] loader: SKIP -- spirv-cross-c-shared.dll not present (resolved=SKIP/169)
  [PASS] functional: SKIP -- parse/compile/reflect probe (no spirv-cross runtime)
xiom.spirv-cross: suite green (DLL absent -- functional probe skipped)
```

## Header-declared functions not exported by the shipped DLL

**None.** `tools/check_exports.py` parses the PE export table of
`spirv-cross-c-shared.dll` (pure stdlib, no dumpbin) and diffs it against the
generator's oracle: `exports=169 (spvc_*=169) header=169 missing=0 extra=0`.
The resolve proof runs in the suite itself: every oracle name is resolved via
`dl.dl_sym` (`spvc_probe_resolution()`), printing `resolved=169/169`.

## Functional probes exercised by the suite

- `spvc_get_version` == header pin 0.68.0 (also `SPVC_C_API_VERSION_*`).
- `spvc_context_create` / `spvc_context_parse_spirv` (141-word embedded
  SPIR-V 1.0 fragment fixture) / `spvc_context_create_compiler(GLSL,
  TAKE_OWNERSHIP)`.
- `spvc_compiler_compile` -> GLSL text contains `void main` (206 bytes).
- `spvc_compiler_create_shader_resources` + `spvc_resources_get_resource_list_for_type`
  for UBO/STAGE_INPUT/STAGE_OUTPUT -> 3 resources (>= 2 required).
- `spvc_compiler_get_entry_points` -> 1 entry point;
  `spvc_compiler_get_execution_model` -> 4 (Fragment).
- `spvc_compiler_get_current_id_bound` (21), `spvc_compiler_get_num_required_extensions` (0),
  `spvc_compiler_add_header_line`, `spvc_compiler_require_extension`,
  compiler options create/set_bool/install (FLIP_VERTEX_Y).
- `spvc_msl_vertex_attribute_init` (defaults into an owned slot),
  `spvc_msl_get_aux_buffer_struct_version` == `SPVC_MSL_AUX_BUFFER_STRUCT_VERSION`.
- Full free chain: `spvc_context_release_allocations` + `spvc_context_destroy`.

## Oracle inventory (169 = 9+6+8+9+40+6+20+27+8+36)

## context family (9 functions)

- `spvc_get_version`
- `spvc_get_commit_revision_and_timestamp`
- `spvc_context_create`
- `spvc_context_destroy`
- `spvc_context_release_allocations`
- `spvc_context_get_last_error_string`
- `spvc_context_set_error_callback`
- `spvc_context_parse_spirv`
- `spvc_context_create_compiler`

## compiler family (6 functions)

- `spvc_compiler_get_current_id_bound`
- `spvc_compiler_compile`
- `spvc_compiler_flatten_buffer_block`
- `spvc_compiler_variable_is_depth_or_compare`
- `spvc_compiler_mask_stage_output_by_location`
- `spvc_compiler_mask_stage_output_by_builtin`

## glsl family (8 functions)

- `spvc_compiler_create_compiler_options`
- `spvc_compiler_options_set_bool`
- `spvc_compiler_options_set_uint`
- `spvc_compiler_install_compiler_options`
- `spvc_compiler_add_header_line`
- `spvc_compiler_require_extension`
- `spvc_compiler_get_num_required_extensions`
- `spvc_compiler_get_required_extension`

## hlsl family (9 functions)

- `spvc_hlsl_resource_binding_init`
- `spvc_compiler_hlsl_set_root_constants_layout`
- `spvc_compiler_hlsl_add_vertex_attribute_remap`
- `spvc_compiler_hlsl_remap_num_workgroups_builtin`
- `spvc_compiler_hlsl_set_resource_binding_flags`
- `spvc_compiler_hlsl_add_resource_binding`
- `spvc_compiler_hlsl_is_resource_used`
- `spvc_compiler_buffer_is_hlsl_counter_buffer`
- `spvc_compiler_buffer_get_hlsl_counter_buffer`

## msl family (40 functions)

- `spvc_msl_vertex_attribute_init`
- `spvc_msl_shader_interface_var_init`
- `spvc_msl_shader_input_init`
- `spvc_msl_shader_interface_var_init_2`
- `spvc_msl_resource_binding_init`
- `spvc_msl_resource_binding_init_2`
- `spvc_msl_get_aux_buffer_struct_version`
- `spvc_msl_constexpr_sampler_init`
- `spvc_msl_sampler_ycbcr_conversion_init`
- `spvc_compiler_msl_is_rasterization_disabled`
- `spvc_compiler_msl_needs_aux_buffer`
- `spvc_compiler_msl_needs_swizzle_buffer`
- `spvc_compiler_msl_needs_buffer_size_buffer`
- `spvc_compiler_msl_needs_output_buffer`
- `spvc_compiler_msl_needs_patch_output_buffer`
- `spvc_compiler_msl_needs_input_threadgroup_mem`
- `spvc_compiler_msl_add_vertex_attribute`
- `spvc_compiler_msl_add_resource_binding`
- `spvc_compiler_msl_add_resource_binding_2`
- `spvc_compiler_msl_add_shader_input`
- `spvc_compiler_msl_add_shader_input_2`
- `spvc_compiler_msl_add_shader_output`
- `spvc_compiler_msl_add_shader_output_2`
- `spvc_compiler_msl_add_discrete_descriptor_set`
- `spvc_compiler_msl_set_argument_buffer_device_address_space`
- `spvc_compiler_msl_is_vertex_attribute_used`
- `spvc_compiler_msl_is_shader_input_used`
- `spvc_compiler_msl_is_shader_output_used`
- `spvc_compiler_msl_is_resource_used`
- `spvc_compiler_msl_remap_constexpr_sampler`
- `spvc_compiler_msl_remap_constexpr_sampler_by_binding`
- `spvc_compiler_msl_remap_constexpr_sampler_ycbcr`
- `spvc_compiler_msl_remap_constexpr_sampler_by_binding_ycbcr`
- `spvc_compiler_msl_set_fragment_output_components`
- `spvc_compiler_msl_get_automatic_resource_binding`
- `spvc_compiler_msl_get_automatic_resource_binding_secondary`
- `spvc_compiler_msl_add_dynamic_buffer`
- `spvc_compiler_msl_add_inline_uniform_block`
- `spvc_compiler_msl_set_combined_sampler_suffix`
- `spvc_compiler_msl_get_combined_sampler_suffix`

## resources family (6 functions)

- `spvc_compiler_get_active_interface_variables`
- `spvc_compiler_set_enabled_interface_variables`
- `spvc_compiler_create_shader_resources`
- `spvc_compiler_create_shader_resources_for_active_variables`
- `spvc_resources_get_resource_list_for_type`
- `spvc_resources_get_builtin_resource_list_for_type`

## type family (20 functions)

- `spvc_compiler_get_type_handle`
- `spvc_type_get_base_type_id`
- `spvc_type_get_basetype`
- `spvc_type_get_bit_width`
- `spvc_type_get_vector_size`
- `spvc_type_get_columns`
- `spvc_type_get_num_array_dimensions`
- `spvc_type_array_dimension_is_literal`
- `spvc_type_get_array_dimension`
- `spvc_type_get_num_member_types`
- `spvc_type_get_member_type`
- `spvc_type_get_storage_class`
- `spvc_type_get_image_sampled_type`
- `spvc_type_get_image_dimension`
- `spvc_type_get_image_is_depth`
- `spvc_type_get_image_arrayed`
- `spvc_type_get_image_multisampled`
- `spvc_type_get_image_is_storage`
- `spvc_type_get_image_storage_format`
- `spvc_type_get_image_access_qualifier`

## constant family (27 functions)

- `spvc_compiler_get_specialization_constants`
- `spvc_compiler_get_constant_handle`
- `spvc_compiler_get_work_group_size_specialization_constants`
- `spvc_constant_get_scalar_fp16`
- `spvc_constant_get_scalar_fp32`
- `spvc_constant_get_scalar_fp64`
- `spvc_constant_get_scalar_u32`
- `spvc_constant_get_scalar_i32`
- `spvc_constant_get_scalar_u16`
- `spvc_constant_get_scalar_i16`
- `spvc_constant_get_scalar_u8`
- `spvc_constant_get_scalar_i8`
- `spvc_constant_get_subconstants`
- `spvc_constant_get_scalar_u64`
- `spvc_constant_get_scalar_i64`
- `spvc_constant_get_type`
- `spvc_constant_set_scalar_fp16`
- `spvc_constant_set_scalar_fp32`
- `spvc_constant_set_scalar_fp64`
- `spvc_constant_set_scalar_u32`
- `spvc_constant_set_scalar_i32`
- `spvc_constant_set_scalar_u64`
- `spvc_constant_set_scalar_i64`
- `spvc_constant_set_scalar_u16`
- `spvc_constant_set_scalar_i16`
- `spvc_constant_set_scalar_u8`
- `spvc_constant_set_scalar_i8`

## buffer family (8 functions)

- `spvc_compiler_get_declared_struct_size`
- `spvc_compiler_get_declared_struct_size_runtime_array`
- `spvc_compiler_get_declared_struct_member_size`
- `spvc_compiler_type_struct_member_offset`
- `spvc_compiler_type_struct_member_array_stride`
- `spvc_compiler_type_struct_member_matrix_stride`
- `spvc_compiler_get_active_buffer_ranges`
- `spvc_compiler_get_buffer_block_decorations`

## reflect family (36 functions)

- `spvc_compiler_set_decoration`
- `spvc_compiler_set_decoration_string`
- `spvc_compiler_set_name`
- `spvc_compiler_set_member_decoration`
- `spvc_compiler_set_member_decoration_string`
- `spvc_compiler_set_member_name`
- `spvc_compiler_unset_decoration`
- `spvc_compiler_unset_member_decoration`
- `spvc_compiler_has_decoration`
- `spvc_compiler_has_member_decoration`
- `spvc_compiler_get_name`
- `spvc_compiler_get_decoration`
- `spvc_compiler_get_decoration_string`
- `spvc_compiler_get_member_decoration`
- `spvc_compiler_get_member_decoration_string`
- `spvc_compiler_get_member_name`
- `spvc_compiler_get_entry_points`
- `spvc_compiler_set_entry_point`
- `spvc_compiler_rename_entry_point`
- `spvc_compiler_get_cleansed_entry_point_name`
- `spvc_compiler_set_execution_mode`
- `spvc_compiler_unset_execution_mode`
- `spvc_compiler_set_execution_mode_with_arguments`
- `spvc_compiler_get_execution_modes`
- `spvc_compiler_get_execution_mode_argument`
- `spvc_compiler_get_execution_mode_argument_by_index`
- `spvc_compiler_get_execution_model`
- `spvc_compiler_update_active_builtins`
- `spvc_compiler_has_active_builtin`
- `spvc_compiler_build_dummy_sampler_for_combined_images`
- `spvc_compiler_build_combined_image_samplers`
- `spvc_compiler_get_combined_image_samplers`
- `spvc_compiler_get_binary_offset_for_decoration`
- `spvc_compiler_get_declared_capabilities`
- `spvc_compiler_get_declared_extensions`
- `spvc_compiler_get_remapped_declared_block_name`
