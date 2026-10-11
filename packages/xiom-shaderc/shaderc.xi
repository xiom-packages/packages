// XIOM -- xiom.shaderc -- shaderc C API bindings (dynamic loader)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// GENERATED FILE -- do not edit by hand.
// Source: tools/gen_shaderc.py
// Oracle: C:\VulkanSDK\1.4.350.0\Include\shaderc (shaderc,env,status,visibility).h
// Pinned upstream: google/shaderc v2026.4 (see SPEC.md / PROVENANCE.md).
// Regenerate: python tools/gen_shaderc.py

//
// DESIGN: dynamic loader path.  The package does NOT link shaderc at
// build time.  shaderc_load() resolves shaderc_shared.dll through
// xiom.ffi.dl at runtime and every call goes through fn-pointer casts
// inside this module -- the only module in the package with `unsafe`.
// When the DLL is absent the suite reports SKIP (green); a present DLL
// missing an oracle symbol reports an ABI failure naming the symbol.

module xiom.shaderc

use xiom.ffi;
use xiom.ffi.dl;

/// Runtime library name resolved by the loader (Windows soname).
pub const SHADERC_SONAME: Str = "shaderc_shared.dll";

/// Failure modes of `shaderc_load`: library absent (callers SKIP) vs
/// present-but-ABI-mismatched (callers FAIL).
pub const SHADERC_LOAD_ABSENT: Int = 0;
pub const SHADERC_LOAD_ABI: Int = 1;

pub type ShadercLoadError = {
  kind: Int;
  message: Str;
}

/// A loaded shaderc library.  `handle` is the dl handle; the `p_*`
/// fields are resolved symbol addresses.  Release with `shaderc_close`.
pub type ShadercLibrary = {
  handle: Int;
  p_shaderc_compiler_initialize: Int;
  p_shaderc_compiler_release: Int;
  p_shaderc_compile_options_initialize: Int;
  p_shaderc_compile_options_clone: Int;
  p_shaderc_compile_options_release: Int;
  p_shaderc_compile_options_add_macro_definition: Int;
  p_shaderc_compile_options_set_source_language: Int;
  p_shaderc_compile_options_set_generate_debug_info: Int;
  p_shaderc_compile_options_set_optimization_level: Int;
  p_shaderc_compile_options_set_forced_version_profile: Int;
  p_shaderc_compile_options_set_include_callbacks: Int;
  p_shaderc_compile_options_set_suppress_warnings: Int;
  p_shaderc_compile_options_set_target_env: Int;
  p_shaderc_compile_options_set_target_spirv: Int;
  p_shaderc_compile_options_set_warnings_as_errors: Int;
  p_shaderc_compile_options_set_limit: Int;
  p_shaderc_compile_options_set_auto_bind_uniforms: Int;
  p_shaderc_compile_options_set_auto_combined_image_sampler: Int;
  p_shaderc_compile_options_set_hlsl_io_mapping: Int;
  p_shaderc_compile_options_set_hlsl_offsets: Int;
  p_shaderc_compile_options_set_binding_base: Int;
  p_shaderc_compile_options_set_binding_base_for_stage: Int;
  p_shaderc_compile_options_set_preserve_bindings: Int;
  p_shaderc_compile_options_set_max_id_bound: Int;
  p_shaderc_compile_options_set_auto_map_locations: Int;
  p_shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage: Int;
  p_shaderc_compile_options_set_hlsl_register_set_and_binding: Int;
  p_shaderc_compile_options_set_hlsl_functionality1: Int;
  p_shaderc_compile_options_set_hlsl_16bit_types: Int;
  p_shaderc_compile_options_set_vulkan_rules_relaxed: Int;
  p_shaderc_compile_options_set_invert_y: Int;
  p_shaderc_compile_options_set_nan_clamp: Int;
  p_shaderc_compile_into_spv: Int;
  p_shaderc_compile_into_spv_assembly: Int;
  p_shaderc_compile_into_preprocessed_text: Int;
  p_shaderc_assemble_into_spv: Int;
  p_shaderc_result_release: Int;
  p_shaderc_result_get_length: Int;
  p_shaderc_result_get_num_warnings: Int;
  p_shaderc_result_get_num_errors: Int;
  p_shaderc_result_get_compilation_status: Int;
  p_shaderc_result_get_bytes: Int;
  p_shaderc_result_get_error_message: Int;
  p_shaderc_get_spv_version: Int;
  p_shaderc_parse_version_profile: Int;
}

/// Load shaderc_shared.dll and resolve every oracle entry point
/// (45 symbols).  Err(kind=SHADERC_LOAD_ABSENT) when the library cannot
/// be loaded; Err(kind=SHADERC_LOAD_ABI) naming the first missing symbol
/// otherwise (the handle is closed on failure).
/// Complexity: O(symbols).
pub fn shaderc_load() -> Result[ShadercLibrary, ShadercLoadError] {
  let h = dl.dl_open(SHADERC_SONAME);
  if !h.is_ok {
    return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;
  let a0 = dl.dl_sym(handle, "shaderc_compiler_initialize");
  if !a0.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compiler_initialize: " + a0.error }); }
  let a1 = dl.dl_sym(handle, "shaderc_compiler_release");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compiler_release: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "shaderc_compile_options_initialize");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_initialize: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "shaderc_compile_options_clone");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_clone: " + a3.error }); }
  let a4 = dl.dl_sym(handle, "shaderc_compile_options_release");
  if !a4.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_release: " + a4.error }); }
  let a5 = dl.dl_sym(handle, "shaderc_compile_options_add_macro_definition");
  if !a5.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_add_macro_definition: " + a5.error }); }
  let a6 = dl.dl_sym(handle, "shaderc_compile_options_set_source_language");
  if !a6.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_source_language: " + a6.error }); }
  let a7 = dl.dl_sym(handle, "shaderc_compile_options_set_generate_debug_info");
  if !a7.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_generate_debug_info: " + a7.error }); }
  let a8 = dl.dl_sym(handle, "shaderc_compile_options_set_optimization_level");
  if !a8.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_optimization_level: " + a8.error }); }
  let a9 = dl.dl_sym(handle, "shaderc_compile_options_set_forced_version_profile");
  if !a9.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_forced_version_profile: " + a9.error }); }
  let a10 = dl.dl_sym(handle, "shaderc_compile_options_set_include_callbacks");
  if !a10.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_include_callbacks: " + a10.error }); }
  let a11 = dl.dl_sym(handle, "shaderc_compile_options_set_suppress_warnings");
  if !a11.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_suppress_warnings: " + a11.error }); }
  let a12 = dl.dl_sym(handle, "shaderc_compile_options_set_target_env");
  if !a12.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_target_env: " + a12.error }); }
  let a13 = dl.dl_sym(handle, "shaderc_compile_options_set_target_spirv");
  if !a13.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_target_spirv: " + a13.error }); }
  let a14 = dl.dl_sym(handle, "shaderc_compile_options_set_warnings_as_errors");
  if !a14.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_warnings_as_errors: " + a14.error }); }
  let a15 = dl.dl_sym(handle, "shaderc_compile_options_set_limit");
  if !a15.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_limit: " + a15.error }); }
  let a16 = dl.dl_sym(handle, "shaderc_compile_options_set_auto_bind_uniforms");
  if !a16.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_auto_bind_uniforms: " + a16.error }); }
  let a17 = dl.dl_sym(handle, "shaderc_compile_options_set_auto_combined_image_sampler");
  if !a17.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_auto_combined_image_sampler: " + a17.error }); }
  let a18 = dl.dl_sym(handle, "shaderc_compile_options_set_hlsl_io_mapping");
  if !a18.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_hlsl_io_mapping: " + a18.error }); }
  let a19 = dl.dl_sym(handle, "shaderc_compile_options_set_hlsl_offsets");
  if !a19.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_hlsl_offsets: " + a19.error }); }
  let a20 = dl.dl_sym(handle, "shaderc_compile_options_set_binding_base");
  if !a20.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_binding_base: " + a20.error }); }
  let a21 = dl.dl_sym(handle, "shaderc_compile_options_set_binding_base_for_stage");
  if !a21.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_binding_base_for_stage: " + a21.error }); }
  let a22 = dl.dl_sym(handle, "shaderc_compile_options_set_preserve_bindings");
  if !a22.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_preserve_bindings: " + a22.error }); }
  let a23 = dl.dl_sym(handle, "shaderc_compile_options_set_max_id_bound");
  if !a23.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_max_id_bound: " + a23.error }); }
  let a24 = dl.dl_sym(handle, "shaderc_compile_options_set_auto_map_locations");
  if !a24.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_auto_map_locations: " + a24.error }); }
  let a25 = dl.dl_sym(handle, "shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage");
  if !a25.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage: " + a25.error }); }
  let a26 = dl.dl_sym(handle, "shaderc_compile_options_set_hlsl_register_set_and_binding");
  if !a26.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_hlsl_register_set_and_binding: " + a26.error }); }
  let a27 = dl.dl_sym(handle, "shaderc_compile_options_set_hlsl_functionality1");
  if !a27.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_hlsl_functionality1: " + a27.error }); }
  let a28 = dl.dl_sym(handle, "shaderc_compile_options_set_hlsl_16bit_types");
  if !a28.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_hlsl_16bit_types: " + a28.error }); }
  let a29 = dl.dl_sym(handle, "shaderc_compile_options_set_vulkan_rules_relaxed");
  if !a29.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_vulkan_rules_relaxed: " + a29.error }); }
  let a30 = dl.dl_sym(handle, "shaderc_compile_options_set_invert_y");
  if !a30.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_invert_y: " + a30.error }); }
  let a31 = dl.dl_sym(handle, "shaderc_compile_options_set_nan_clamp");
  if !a31.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_options_set_nan_clamp: " + a31.error }); }
  let a32 = dl.dl_sym(handle, "shaderc_compile_into_spv");
  if !a32.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_into_spv: " + a32.error }); }
  let a33 = dl.dl_sym(handle, "shaderc_compile_into_spv_assembly");
  if !a33.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_into_spv_assembly: " + a33.error }); }
  let a34 = dl.dl_sym(handle, "shaderc_compile_into_preprocessed_text");
  if !a34.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_compile_into_preprocessed_text: " + a34.error }); }
  let a35 = dl.dl_sym(handle, "shaderc_assemble_into_spv");
  if !a35.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_assemble_into_spv: " + a35.error }); }
  let a36 = dl.dl_sym(handle, "shaderc_result_release");
  if !a36.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_result_release: " + a36.error }); }
  let a37 = dl.dl_sym(handle, "shaderc_result_get_length");
  if !a37.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_result_get_length: " + a37.error }); }
  let a38 = dl.dl_sym(handle, "shaderc_result_get_num_warnings");
  if !a38.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_result_get_num_warnings: " + a38.error }); }
  let a39 = dl.dl_sym(handle, "shaderc_result_get_num_errors");
  if !a39.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_result_get_num_errors: " + a39.error }); }
  let a40 = dl.dl_sym(handle, "shaderc_result_get_compilation_status");
  if !a40.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_result_get_compilation_status: " + a40.error }); }
  let a41 = dl.dl_sym(handle, "shaderc_result_get_bytes");
  if !a41.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_result_get_bytes: " + a41.error }); }
  let a42 = dl.dl_sym(handle, "shaderc_result_get_error_message");
  if !a42.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_result_get_error_message: " + a42.error }); }
  let a43 = dl.dl_sym(handle, "shaderc_get_spv_version");
  if !a43.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_get_spv_version: " + a43.error }); }
  let a44 = dl.dl_sym(handle, "shaderc_parse_version_profile");
  if !a44.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: "shaderc_parse_version_profile: " + a44.error }); }
  return Ok(ShadercLibrary{
    handle: handle,
    p_shaderc_compiler_initialize: a0.value,
    p_shaderc_compiler_release: a1.value,
    p_shaderc_compile_options_initialize: a2.value,
    p_shaderc_compile_options_clone: a3.value,
    p_shaderc_compile_options_release: a4.value,
    p_shaderc_compile_options_add_macro_definition: a5.value,
    p_shaderc_compile_options_set_source_language: a6.value,
    p_shaderc_compile_options_set_generate_debug_info: a7.value,
    p_shaderc_compile_options_set_optimization_level: a8.value,
    p_shaderc_compile_options_set_forced_version_profile: a9.value,
    p_shaderc_compile_options_set_include_callbacks: a10.value,
    p_shaderc_compile_options_set_suppress_warnings: a11.value,
    p_shaderc_compile_options_set_target_env: a12.value,
    p_shaderc_compile_options_set_target_spirv: a13.value,
    p_shaderc_compile_options_set_warnings_as_errors: a14.value,
    p_shaderc_compile_options_set_limit: a15.value,
    p_shaderc_compile_options_set_auto_bind_uniforms: a16.value,
    p_shaderc_compile_options_set_auto_combined_image_sampler: a17.value,
    p_shaderc_compile_options_set_hlsl_io_mapping: a18.value,
    p_shaderc_compile_options_set_hlsl_offsets: a19.value,
    p_shaderc_compile_options_set_binding_base: a20.value,
    p_shaderc_compile_options_set_binding_base_for_stage: a21.value,
    p_shaderc_compile_options_set_preserve_bindings: a22.value,
    p_shaderc_compile_options_set_max_id_bound: a23.value,
    p_shaderc_compile_options_set_auto_map_locations: a24.value,
    p_shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage: a25.value,
    p_shaderc_compile_options_set_hlsl_register_set_and_binding: a26.value,
    p_shaderc_compile_options_set_hlsl_functionality1: a27.value,
    p_shaderc_compile_options_set_hlsl_16bit_types: a28.value,
    p_shaderc_compile_options_set_vulkan_rules_relaxed: a29.value,
    p_shaderc_compile_options_set_invert_y: a30.value,
    p_shaderc_compile_options_set_nan_clamp: a31.value,
    p_shaderc_compile_into_spv: a32.value,
    p_shaderc_compile_into_spv_assembly: a33.value,
    p_shaderc_compile_into_preprocessed_text: a34.value,
    p_shaderc_assemble_into_spv: a35.value,
    p_shaderc_result_release: a36.value,
    p_shaderc_result_get_length: a37.value,
    p_shaderc_result_get_num_warnings: a38.value,
    p_shaderc_result_get_num_errors: a39.value,
    p_shaderc_result_get_compilation_status: a40.value,
    p_shaderc_result_get_bytes: a41.value,
    p_shaderc_result_get_error_message: a42.value,
    p_shaderc_get_spv_version: a43.value,
    p_shaderc_parse_version_profile: a44.value,
  });
}

/// Release a loaded library handle.
/// Complexity: O(1).
pub fn shaderc_close(lib: &ShadercLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

// =========================================================================
// Typed wrappers -- one per SHADERC_EXPORT function (oracle order)
// =========================================================================

#[unsafe_direct]
pub fn shaderc_compiler_initialize(lib: &ShadercLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_compiler_initialize = lib.p_shaderc_compiler_initialize as fn() -> Int;
    return f_compiler_initialize() as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_compiler_release(lib: &ShadercLibrary, compiler: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compiler_release = lib.p_shaderc_compiler_release as fn(Int);
    f_compiler_release(compiler);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_initialize(lib: &ShadercLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_initialize = lib.p_shaderc_compile_options_initialize as fn() -> Int;
    return f_compile_options_initialize() as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_clone(lib: &ShadercLibrary, options: Int) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_clone = lib.p_shaderc_compile_options_clone as fn(Int) -> Int;
    return f_compile_options_clone(options) as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_release(lib: &ShadercLibrary, options: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_release = lib.p_shaderc_compile_options_release as fn(Int);
    f_compile_options_release(options);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_add_macro_definition(lib: &ShadercLibrary, options: Int, name: Str, value: Str) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_add_macro_definition = lib.p_shaderc_compile_options_add_macro_definition as fn(Int, *UInt8, Int, *UInt8, Int);
    f_compile_options_add_macro_definition(options, name.c_str(), name.len(), value.c_str(), value.len());
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_source_language(lib: &ShadercLibrary, options: Int, lang: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_source_language = lib.p_shaderc_compile_options_set_source_language as fn(Int, Int);
    f_compile_options_set_source_language(options, lang);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_generate_debug_info(lib: &ShadercLibrary, options: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_generate_debug_info = lib.p_shaderc_compile_options_set_generate_debug_info as fn(Int);
    f_compile_options_set_generate_debug_info(options);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_optimization_level(lib: &ShadercLibrary, options: Int, level: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_optimization_level = lib.p_shaderc_compile_options_set_optimization_level as fn(Int, Int);
    f_compile_options_set_optimization_level(options, level);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_forced_version_profile(lib: &ShadercLibrary, options: Int, version: Int, profile: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_forced_version_profile = lib.p_shaderc_compile_options_set_forced_version_profile as fn(Int, Int, Int);
    f_compile_options_set_forced_version_profile(options, version, profile);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_include_callbacks(lib: &ShadercLibrary, options: Int, resolver: Int, result_releaser: Int, user_data: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_include_callbacks = lib.p_shaderc_compile_options_set_include_callbacks as fn(Int, Int, Int, Int);
    f_compile_options_set_include_callbacks(options, resolver, result_releaser, user_data);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_suppress_warnings(lib: &ShadercLibrary, options: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_suppress_warnings = lib.p_shaderc_compile_options_set_suppress_warnings as fn(Int);
    f_compile_options_set_suppress_warnings(options);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_target_env(lib: &ShadercLibrary, options: Int, target: Int, version: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_target_env = lib.p_shaderc_compile_options_set_target_env as fn(Int, Int, Int);
    f_compile_options_set_target_env(options, target, version);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_target_spirv(lib: &ShadercLibrary, options: Int, version: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_target_spirv = lib.p_shaderc_compile_options_set_target_spirv as fn(Int, Int);
    f_compile_options_set_target_spirv(options, version);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_warnings_as_errors(lib: &ShadercLibrary, options: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_warnings_as_errors = lib.p_shaderc_compile_options_set_warnings_as_errors as fn(Int);
    f_compile_options_set_warnings_as_errors(options);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_limit(lib: &ShadercLibrary, options: Int, limit: Int, value: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_limit = lib.p_shaderc_compile_options_set_limit as fn(Int, Int, Int);
    f_compile_options_set_limit(options, limit, value);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_auto_bind_uniforms(lib: &ShadercLibrary, options: Int, auto_bind: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_auto_bind_uniforms = lib.p_shaderc_compile_options_set_auto_bind_uniforms as fn(Int, UInt8);
    let b_auto_bind: UInt8 = if auto_bind { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_auto_bind_uniforms(options, b_auto_bind);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_auto_combined_image_sampler(lib: &ShadercLibrary, options: Int, upgrade: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_auto_combined_image_sampler = lib.p_shaderc_compile_options_set_auto_combined_image_sampler as fn(Int, UInt8);
    let b_upgrade: UInt8 = if upgrade { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_auto_combined_image_sampler(options, b_upgrade);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_hlsl_io_mapping(lib: &ShadercLibrary, options: Int, hlsl_iomap: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_hlsl_io_mapping = lib.p_shaderc_compile_options_set_hlsl_io_mapping as fn(Int, UInt8);
    let b_hlsl_iomap: UInt8 = if hlsl_iomap { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_hlsl_io_mapping(options, b_hlsl_iomap);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_hlsl_offsets(lib: &ShadercLibrary, options: Int, hlsl_offsets: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_hlsl_offsets = lib.p_shaderc_compile_options_set_hlsl_offsets as fn(Int, UInt8);
    let b_hlsl_offsets: UInt8 = if hlsl_offsets { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_hlsl_offsets(options, b_hlsl_offsets);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_binding_base(lib: &ShadercLibrary, options: Int, kind: Int, base: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_binding_base = lib.p_shaderc_compile_options_set_binding_base as fn(Int, Int, Int);
    f_compile_options_set_binding_base(options, kind, base);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_binding_base_for_stage(lib: &ShadercLibrary, options: Int, shader_kind: Int, kind: Int, base: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_binding_base_for_stage = lib.p_shaderc_compile_options_set_binding_base_for_stage as fn(Int, Int, Int, Int);
    f_compile_options_set_binding_base_for_stage(options, shader_kind, kind, base);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_preserve_bindings(lib: &ShadercLibrary, options: Int, preserve_bindings: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_preserve_bindings = lib.p_shaderc_compile_options_set_preserve_bindings as fn(Int, UInt8);
    let b_preserve_bindings: UInt8 = if preserve_bindings { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_preserve_bindings(options, b_preserve_bindings);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_max_id_bound(lib: &ShadercLibrary, options: Int, max_id_bound: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_max_id_bound = lib.p_shaderc_compile_options_set_max_id_bound as fn(Int, Int);
    f_compile_options_set_max_id_bound(options, max_id_bound);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_auto_map_locations(lib: &ShadercLibrary, options: Int, auto_map: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_auto_map_locations = lib.p_shaderc_compile_options_set_auto_map_locations as fn(Int, UInt8);
    let b_auto_map: UInt8 = if auto_map { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_auto_map_locations(options, b_auto_map);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage(lib: &ShadercLibrary, options: Int, shader_kind: Int, reg: Str, set: Str, binding: Str) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_hlsl_register_set_and_binding_for_stage = lib.p_shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage as fn(Int, Int, *UInt8, *UInt8, *UInt8);
    f_compile_options_set_hlsl_register_set_and_binding_for_stage(options, shader_kind, reg.c_str(), set.c_str(), binding.c_str());
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_hlsl_register_set_and_binding(lib: &ShadercLibrary, options: Int, reg: Str, set: Str, binding: Str) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_hlsl_register_set_and_binding = lib.p_shaderc_compile_options_set_hlsl_register_set_and_binding as fn(Int, *UInt8, *UInt8, *UInt8);
    f_compile_options_set_hlsl_register_set_and_binding(options, reg.c_str(), set.c_str(), binding.c_str());
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_hlsl_functionality1(lib: &ShadercLibrary, options: Int, enable: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_hlsl_functionality1 = lib.p_shaderc_compile_options_set_hlsl_functionality1 as fn(Int, UInt8);
    let b_enable: UInt8 = if enable { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_hlsl_functionality1(options, b_enable);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_hlsl_16bit_types(lib: &ShadercLibrary, options: Int, enable: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_hlsl_16bit_types = lib.p_shaderc_compile_options_set_hlsl_16bit_types as fn(Int, UInt8);
    let b_enable: UInt8 = if enable { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_hlsl_16bit_types(options, b_enable);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_vulkan_rules_relaxed(lib: &ShadercLibrary, options: Int, enable: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_vulkan_rules_relaxed = lib.p_shaderc_compile_options_set_vulkan_rules_relaxed as fn(Int, UInt8);
    let b_enable: UInt8 = if enable { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_vulkan_rules_relaxed(options, b_enable);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_invert_y(lib: &ShadercLibrary, options: Int, enable: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_invert_y = lib.p_shaderc_compile_options_set_invert_y as fn(Int, UInt8);
    let b_enable: UInt8 = if enable { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_invert_y(options, b_enable);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_options_set_nan_clamp(lib: &ShadercLibrary, options: Int, enable: Bool) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_options_set_nan_clamp = lib.p_shaderc_compile_options_set_nan_clamp as fn(Int, UInt8);
    let b_enable: UInt8 = if enable { 1 as UInt8 } else { 0 as UInt8 };
    f_compile_options_set_nan_clamp(options, b_enable);
  }
}

#[unsafe_direct]
pub fn shaderc_compile_into_spv(lib: &ShadercLibrary, compiler: Int, source_text: Str, shader_kind: Int, input_file_name: Str, entry_point_name: Str, additional_options: Int) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_into_spv = lib.p_shaderc_compile_into_spv as fn(Int, *UInt8, Int, Int, *UInt8, *UInt8, Int) -> Int;
    return f_compile_into_spv(compiler, source_text.c_str(), source_text.len(), shader_kind, input_file_name.c_str(), entry_point_name.c_str(), additional_options) as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_compile_into_spv_assembly(lib: &ShadercLibrary, compiler: Int, source_text: Str, shader_kind: Int, input_file_name: Str, entry_point_name: Str, additional_options: Int) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_into_spv_assembly = lib.p_shaderc_compile_into_spv_assembly as fn(Int, *UInt8, Int, Int, *UInt8, *UInt8, Int) -> Int;
    return f_compile_into_spv_assembly(compiler, source_text.c_str(), source_text.len(), shader_kind, input_file_name.c_str(), entry_point_name.c_str(), additional_options) as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_compile_into_preprocessed_text(lib: &ShadercLibrary, compiler: Int, source_text: Str, shader_kind: Int, input_file_name: Str, entry_point_name: Str, additional_options: Int) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_compile_into_preprocessed_text = lib.p_shaderc_compile_into_preprocessed_text as fn(Int, *UInt8, Int, Int, *UInt8, *UInt8, Int) -> Int;
    return f_compile_into_preprocessed_text(compiler, source_text.c_str(), source_text.len(), shader_kind, input_file_name.c_str(), entry_point_name.c_str(), additional_options) as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_assemble_into_spv(lib: &ShadercLibrary, compiler: Int, source_assembly: Str, additional_options: Int) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_assemble_into_spv = lib.p_shaderc_assemble_into_spv as fn(Int, *UInt8, Int, Int) -> Int;
    return f_assemble_into_spv(compiler, source_assembly.c_str(), source_assembly.len(), additional_options) as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_result_release(lib: &ShadercLibrary, result: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_result_release = lib.p_shaderc_result_release as fn(Int);
    f_result_release(result);
  }
}

#[unsafe_direct]
pub fn shaderc_result_get_length(lib: &ShadercLibrary, result: Int) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_result_get_length = lib.p_shaderc_result_get_length as fn(Int) -> Int;
    return f_result_get_length(result) as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_result_get_num_warnings(lib: &ShadercLibrary, result: Int) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_result_get_num_warnings = lib.p_shaderc_result_get_num_warnings as fn(Int) -> Int;
    return f_result_get_num_warnings(result) as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_result_get_num_errors(lib: &ShadercLibrary, result: Int) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_result_get_num_errors = lib.p_shaderc_result_get_num_errors as fn(Int) -> Int;
    return f_result_get_num_errors(result) as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_result_get_compilation_status(lib: &ShadercLibrary, shaderc_compilation_result_t: Int) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f_result_get_compilation_status = lib.p_shaderc_result_get_compilation_status as fn(Int) -> Int;
    return f_result_get_compilation_status(shaderc_compilation_result_t) as Int;
  }
}

#[unsafe_direct]
pub fn shaderc_result_get_bytes(lib: &ShadercLibrary, result: Int) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f_result_get_bytes = lib.p_shaderc_result_get_bytes as fn(Int) -> *UInt8;
    let p = f_result_get_bytes(result);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

#[unsafe_direct]
pub fn shaderc_result_get_error_message(lib: &ShadercLibrary, result: Int) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f_result_get_error_message = lib.p_shaderc_result_get_error_message as fn(Int) -> *UInt8;
    let p = f_result_get_error_message(result);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

#[unsafe_direct]
pub fn shaderc_get_spv_version(lib: &ShadercLibrary, version: Int, revision: Int) -> Unit
  requires: lib.handle != 0
{
  unsafe {
    let f_get_spv_version = lib.p_shaderc_get_spv_version as fn(Int, Int);
    f_get_spv_version(version, revision);
  }
}

#[unsafe_direct]
pub fn shaderc_parse_version_profile(lib: &ShadercLibrary, input: Str, version: Int, profile: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f_parse_version_profile = lib.p_shaderc_parse_version_profile as fn(*UInt8, Int, Int) -> UInt8;
    return (f_parse_version_profile(input.c_str(), version, profile) as Int) != 0;
  }
}


// =========================================================================
// Owned-slot decode helpers (B-11..B-20 shape): each helper creates fresh
// XIOM-owned 4-byte slots per call (never reuses slot memory across calls),
// lets C write through the slot pointers, then reads byte-indexed.  Binary
// output is copied into an owned Vec with ffi.memcpy before any byte-level
// read; no foreign pointer is ever read directly.
// =========================================================================

fn shaderc_slot4() -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 4 {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn shaderc_read_u32(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 4
{
  return (buf[0] as Int) | ((buf[1] as Int) << 8) | ((buf[2] as Int) << 16) | ((buf[3] as Int) << 24);
}

/// shaderc_get_spv_version decoded: the version/revision the compiler emits.
pub type ShadercSpvVersion = {
  version: Int;
  revision: Int;
}

#[unsafe_direct]
/// Decoded shaderc_get_spv_version() -- two owned slots, one per out-param.
/// Complexity: O(1).
pub fn shaderc_get_spv_version_values(lib: &ShadercLibrary) -> ShadercSpvVersion
  requires: lib.handle != 0
{
  unsafe {
    let f_ver = lib.p_shaderc_get_spv_version as fn(Int, Int);
    var vslot = shaderc_slot4();
    var rslot = shaderc_slot4();
    let va = vslot.as_mut_ptr() as Int;
    let ra = rslot.as_mut_ptr() as Int;
    f_ver(va, ra);
    return ShadercSpvVersion{ version: shaderc_read_u32(&vslot), revision: shaderc_read_u32(&rslot) };
  }
}

/// shaderc_parse_version_profile decoded outcome.
pub type ShadercVersionProfile = {
  ok: Bool;
  version: Int;
  profile: Int;
}

#[unsafe_direct]
/// Decoded shaderc_parse_version_profile() -- two owned slots, one per
/// out-param, fresh per call.
/// Complexity: O(len).
pub fn shaderc_parse_version_profile_values(lib: &ShadercLibrary, input: Str) -> ShadercVersionProfile
  requires: lib.handle != 0
{
  unsafe {
    let f_parse = lib.p_shaderc_parse_version_profile as fn(*UInt8, Int, Int) -> UInt8;
    var vslot = shaderc_slot4();
    var pslot = shaderc_slot4();
    let va = vslot.as_mut_ptr() as Int;
    let pa = pslot.as_mut_ptr() as Int;
    let ok = f_parse(input.c_str(), va, pa);
    return ShadercVersionProfile{ ok: (ok as Int) != 0, version: shaderc_read_u32(&vslot), profile: shaderc_read_u32(&pslot) };
  }
}

#[unsafe_direct]
/// First 32-bit word of a result's SPIR-V binary (the module magic 0x07230203
/// for SPIR-V output) -- the byte-level readback proof.
/// Complexity: O(1).
pub fn shaderc_result_first_word(lib: &ShadercLibrary, result: Int) -> Int
  requires: lib.handle != 0
  requires: result != 0
{
  unsafe {
    let f_bytes = lib.p_shaderc_result_get_bytes as fn(Int) -> *UInt8;
    let f_len = lib.p_shaderc_result_get_length as fn(Int) -> Int;
    if f_len(result) < 4 { return 0; }
    let p = f_bytes(result);
    if (p as Int) == 0 { return 0; }
    var buf = shaderc_slot4();
    ffi.memcpy(buf.as_mut_ptr(), (p as Int) as *UInt8, 4);
    return shaderc_read_u32(&buf);
  }
}

#[unsafe_direct]
/// Copy up to `max_bytes` of a result's output into an XIOM-owned Vec.
/// Complexity: O(n).
pub fn shaderc_result_copy_bytes(lib: &ShadercLibrary, result: Int, max_bytes: Int) -> Vec[UInt8]
  requires: lib.handle != 0
  requires: result != 0
  requires: max_bytes >= 0
{
  unsafe {
    let f_bytes = lib.p_shaderc_result_get_bytes as fn(Int) -> *UInt8;
    let f_len = lib.p_shaderc_result_get_length as fn(Int) -> Int;
    let total = f_len(result);
    if total <= 0 { return Vec[UInt8].new(); }
    let p = f_bytes(result);
    if (p as Int) == 0 { return Vec[UInt8].new(); }
    var n = total;
    if n > max_bytes { n = max_bytes; }
    // NOTE: push loop, NOT Vec.with_len -- with_len has a zero-fill overflow
    // on this toolchain (see AUDIT.md, "Vec.with_len finding"); the pushed
    // buffer is sized to n elements and the memcpy writes exactly n bytes.
    var buf: Vec[UInt8] = Vec[UInt8].new();
    var j: Int = 0;
    while j < n {
      buf.push(0 as UInt8);
      j = j + 1;
    }
    ffi.memcpy(buf.as_mut_ptr(), (p as Int) as *UInt8, n);
    return buf;
  }
}

#[unsafe_direct]
/// Text output of a result (SPIR-V assembly / preprocessed source), read as
/// the NUL-terminated C string the result holds.
/// Complexity: O(len).
pub fn shaderc_result_get_text(lib: &ShadercLibrary, result: Int) -> Str
  requires: lib.handle != 0
  requires: result != 0
{
  unsafe {
    let f_bytes = lib.p_shaderc_result_get_bytes as fn(Int) -> *UInt8;
    let p = f_bytes(result);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

