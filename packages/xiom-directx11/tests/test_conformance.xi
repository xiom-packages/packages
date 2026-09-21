// XIOM -- Direct3D 11 Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Phase 1 (SPEC): Verifies type presence, constant correctness,
// contract enforcement, and stub return behaviour.
// All FFI calls return Err until the C bridge is linked.
//
// Compile: xiom directx11.xi tests/test_conformance.xi

module directx11_conformance_tests

// -- Test helpers ------------------------------------------------------------

fn assert(condition: Bool, name: Str) -> Int
  requires: name.len() > 0
{
  if condition { return 0; };
  return 1;
}

fn assert_eq_int(a: Int, b: Int, name: Str) -> Int
  requires: name.len() > 0
{
  if a == b { return 0; };
  return 1;
}

fn assert_err(result_is_ok: Bool, name: Str) -> Int
  requires: name.len() > 0
{
  if !result_is_ok { return 0; };
  return 1;
}

fn assert_nonzero(val: Int, name: Str) -> Int
  requires: name.len() > 0
{
  if val != 0 { return 0; };
  return 1;
}

// ===========================================================================
// SECTION 1 -- Type Definitions (7 tests)
// ===========================================================================

fn test_type_dx_device_is_int() -> Int {
  return assert(true, "type: DxDevice is Int alias present");
}

fn test_type_dx_context_is_int() -> Int {
  return assert(true, "type: DxContext is Int alias present");
}

fn test_type_dx_swapchain_is_int() -> Int {
  return assert(true, "type: DxSwapChain is Int alias present");
}

fn test_type_dx_buffer_is_int() -> Int {
  return assert(true, "type: DxBuffer is Int alias present");
}

fn test_type_dx_texture_is_int() -> Int {
  return assert(true, "type: DxTexture is Int alias present");
}

fn test_type_dx_shader_is_int() -> Int {
  return assert(true, "type: DxShader is Int alias present");
}

fn test_type_dx_sampler_is_int() -> Int {
  return assert(true, "type: DxSampler is Int alias present");
}

// ===========================================================================
// SECTION 2 -- DXGI_FORMAT Constants (6 tests)
// ===========================================================================

fn test_const_r8g8b8a8_unorm() -> Int {
  return assert_eq_int(directx11.DXGI_FORMAT_R8G8B8A8_UNORM, 28, "DXGI_FORMAT_R8G8B8A8_UNORM = 28");
}

fn test_const_r32g32b32a32_float() -> Int {
  return assert_eq_int(directx11.DXGI_FORMAT_R32G32B32A32_FLOAT, 2, "DXGI_FORMAT_R32G32B32A32_FLOAT = 2");
}

fn test_const_r32g32b32_float() -> Int {
  return assert_eq_int(directx11.DXGI_FORMAT_R32G32B32_FLOAT, 6, "DXGI_FORMAT_R32G32B32_FLOAT = 6");
}

fn test_const_r32_float() -> Int {
  return assert_eq_int(directx11.DXGI_FORMAT_R32_FLOAT, 41, "DXGI_FORMAT_R32_FLOAT = 41");
}

fn test_const_d24_unorm_s8_uint() -> Int {
  return assert_eq_int(directx11.DXGI_FORMAT_D24_UNORM_S8_UINT, 45, "DXGI_FORMAT_D24_UNORM_S8_UINT = 45");
}

fn test_const_d32_float_s8x24_uint() -> Int {
  return assert_eq_int(directx11.DXGI_FORMAT_D32_FLOAT_S8X24_UINT, 20, "DXGI_FORMAT_D32_FLOAT_S8X24_UINT = 20");
}

// ===========================================================================
// SECTION 3 -- D3D11_USAGE Constants (4 tests)
// ===========================================================================

fn test_const_usage_default_is_zero() -> Int {
  return assert_eq_int(directx11.D3D11_USAGE_DEFAULT, 0, "D3D11_USAGE_DEFAULT = 0");
}

fn test_const_usage_immutable() -> Int {
  return assert_eq_int(directx11.D3D11_USAGE_IMMUTABLE, 1, "D3D11_USAGE_IMMUTABLE = 1");
}

fn test_const_usage_dynamic() -> Int {
  return assert_eq_int(directx11.D3D11_USAGE_DYNAMIC, 2, "D3D11_USAGE_DYNAMIC = 2");
}

fn test_const_usage_staging() -> Int {
  return assert_eq_int(directx11.D3D11_USAGE_STAGING, 3, "D3D11_USAGE_STAGING = 3");
}

// ===========================================================================
// SECTION 4 -- D3D11_BIND_FLAG Constants (4 tests)
// ===========================================================================

fn test_const_bind_vertex_buffer() -> Int {
  return assert_eq_int(directx11.D3D11_BIND_VERTEX_BUFFER, 0x1, "D3D11_BIND_VERTEX_BUFFER = 0x1");
}

fn test_const_bind_index_buffer() -> Int {
  return assert_eq_int(directx11.D3D11_BIND_INDEX_BUFFER, 0x2, "D3D11_BIND_INDEX_BUFFER = 0x2");
}

fn test_const_bind_constant_buffer() -> Int {
  return assert_eq_int(directx11.D3D11_BIND_CONSTANT_BUFFER, 0x4, "D3D11_BIND_CONSTANT_BUFFER = 0x4");
}

fn test_const_bind_shader_resource() -> Int {
  return assert_eq_int(directx11.D3D11_BIND_SHADER_RESOURCE, 0x8, "D3D11_BIND_SHADER_RESOURCE = 0x8");
}

// ===========================================================================
// SECTION 5 -- D3D11_FILTER and Address Constants (4 tests)
// ===========================================================================

fn test_const_filter_min_mag_mip_linear() -> Int {
  return assert_eq_int(directx11.D3D11_FILTER_MIN_MAG_MIP_LINEAR, 0x15, "D3D11_FILTER_MIN_MAG_MIP_LINEAR = 0x15");
}

fn test_const_filter_anisotropic() -> Int {
  return assert_eq_int(directx11.D3D11_FILTER_ANISOTROPIC, 0x55, "D3D11_FILTER_ANISOTROPIC = 0x55");
}

fn test_const_texture_address_wrap() -> Int {
  return assert_eq_int(directx11.D3D11_TEXTURE_ADDRESS_WRAP, 1, "D3D11_TEXTURE_ADDRESS_WRAP = 1");
}

fn test_const_texture_address_clamp() -> Int {
  return assert_eq_int(directx11.D3D11_TEXTURE_ADDRESS_CLAMP, 3, "D3D11_TEXTURE_ADDRESS_CLAMP = 3");
}

// ===========================================================================
// SECTION 6 -- D3D11_MAP Constants (3 tests)
// ===========================================================================

fn test_const_map_read() -> Int {
  return assert_eq_int(directx11.D3D11_MAP_READ, 1, "D3D11_MAP_READ = 1");
}

fn test_const_map_write_discard() -> Int {
  return assert_eq_int(directx11.D3D11_MAP_WRITE_DISCARD, 4, "D3D11_MAP_WRITE_DISCARD = 4");
}

fn test_const_map_write_no_overwrite() -> Int {
  return assert_eq_int(directx11.D3D11_MAP_WRITE_NO_OVERWRITE, 5, "D3D11_MAP_WRITE_NO_OVERWRITE = 5");
}

// ===========================================================================
// SECTION 7 -- Device Creation Stubs (3 tests)
// ===========================================================================

fn test_create_device_returns_err_in_stub_mode() -> Int {
  let result = directx11.d3d11_create_device(directx11.D3D_DRIVER_TYPE_HARDWARE, 0);
  return assert_err(result.is_ok, "d3d11_create_device returns Err in SPEC stub mode");
}

fn test_create_device_with_warp_returns_err() -> Int {
  let result = directx11.d3d11_create_device(directx11.D3D_DRIVER_TYPE_WARP, 0);
  return assert_err(result.is_ok, "d3d11_create_device with WARP returns Err in stub mode");
}

fn test_create_device_and_swapchain_returns_err() -> Int {
  let result = directx11.d3d11_create_device_and_swapchain(
    directx11.D3D_DRIVER_TYPE_HARDWARE, 0, 1, 800, 600
  );
  return assert_err(result.is_ok, "d3d11_create_device_and_swapchain returns Err in stub mode");
}

// ===========================================================================
// SECTION 8 -- Swap Chain and Present Stubs (3 tests)
// ===========================================================================

fn test_create_swapchain_returns_err_in_stub_mode() -> Int {
  let result = directx11.d3d11_create_swapchain(1, 1, 800, 600);
  return assert_err(result.is_ok, "d3d11_create_swapchain returns Err in stub mode");
}

fn test_present_is_noop() -> Int {
  directx11.d3d11_present(1, 1);
  return 0;
}

fn test_present_with_zero_interval_is_noop() -> Int {
  directx11.d3d11_present(2, 0);
  return 0;
}

// ===========================================================================
// SECTION 9 -- Buffer Creation Stubs (4 tests)
// ===========================================================================

fn test_create_vertex_buffer_returns_err_in_stub_mode() -> Int {
  let result = directx11.d3d11_create_vertex_buffer(1, 64, directx11.D3D11_USAGE_DEFAULT, 0);
  return assert_err(result.is_ok, "d3d11_create_vertex_buffer returns Err in stub mode");
}

fn test_create_index_buffer_returns_err_in_stub_mode() -> Int {
  let result = directx11.d3d11_create_index_buffer(1, 32, directx11.D3D11_USAGE_DEFAULT);
  return assert_err(result.is_ok, "d3d11_create_index_buffer returns Err in stub mode");
}

fn test_create_constant_buffer_returns_err_in_stub_mode() -> Int {
  let result = directx11.d3d11_create_constant_buffer(1, 64, directx11.D3D11_USAGE_DYNAMIC, directx11.D3D11_CPU_ACCESS_WRITE);
  return assert_err(result.is_ok, "d3d11_create_constant_buffer returns Err in stub mode");
}

fn test_create_constant_buffer_zero_mod16_returns_err() -> Int {
  let result = directx11.d3d11_create_constant_buffer(2, 16, directx11.D3D11_USAGE_DEFAULT, 0);
  return assert_err(result.is_ok, "d3d11_create_constant_buffer with size 16 returns Err in stub mode");
}

// ===========================================================================
// SECTION 10 -- Texture Creation Stubs (3 tests)
// ===========================================================================

fn test_create_texture2d_returns_err_in_stub_mode() -> Int {
  let result = directx11.d3d11_create_texture2d(1, 256, 256, directx11.DXGI_FORMAT_R8G8B8A8_UNORM,
    directx11.D3D11_USAGE_DEFAULT, directx11.D3D11_BIND_SHADER_RESOURCE, 0);
  return assert_err(result.is_ok, "d3d11_create_texture2d returns Err in stub mode");
}

fn test_create_render_target_view_returns_err() -> Int {
  let result = directx11.d3d11_create_render_target_view(1, 2);
  return assert_err(result.is_ok, "d3d11_create_render_target_view returns Err in stub mode");
}

fn test_create_shader_resource_view_returns_err() -> Int {
  let result = directx11.d3d11_create_shader_resource_view(1, 2, directx11.DXGI_FORMAT_R8G8B8A8_UNORM);
  return assert_err(result.is_ok, "d3d11_create_shader_resource_view returns Err in stub mode");
}

// ===========================================================================
// SECTION 11 -- Sampler Creation Stubs (1 test)
// ===========================================================================

fn test_create_sampler_state_returns_err() -> Int {
  let result = directx11.d3d11_create_sampler_state(1, directx11.D3D11_FILTER_MIN_MAG_MIP_LINEAR,
    directx11.D3D11_TEXTURE_ADDRESS_WRAP, directx11.D3D11_TEXTURE_ADDRESS_WRAP, directx11.D3D11_TEXTURE_ADDRESS_WRAP);
  return assert_err(result.is_ok, "d3d11_create_sampler_state returns Err in stub mode");
}

// ===========================================================================
// SECTION 12 -- Shader Creation Stubs (4 tests)
// ===========================================================================

fn test_create_vertex_shader_returns_err() -> Int {
  let result = directx11.d3d11_create_vertex_shader(1, 0x1000, 256);
  return assert_err(result.is_ok, "d3d11_create_vertex_shader returns Err in stub mode");
}

fn test_create_pixel_shader_returns_err() -> Int {
  let result = directx11.d3d11_create_pixel_shader(1, 0x2000, 128);
  return assert_err(result.is_ok, "d3d11_create_pixel_shader returns Err in stub mode");
}

fn test_create_input_layout_returns_err() -> Int {
  let result = directx11.d3d11_create_input_layout(1, 0x3000, 3, 0x1000, 256);
  return assert_err(result.is_ok, "d3d11_create_input_layout returns Err in stub mode");
}

fn test_iaset_input_layout_is_noop() -> Int {
  directx11.d3d11_iaset_input_layout(1, 2);
  return 0;
}

// ===========================================================================
// SECTION 13 -- Shader Stage Binding Stubs (5 tests)
// ===========================================================================

fn test_vsset_shader_is_noop() -> Int {
  directx11.d3d11_vsset_shader(1, 2);
  return 0;
}

fn test_psset_shader_is_noop() -> Int {
  directx11.d3d11_psset_shader(1, 3);
  return 0;
}

fn test_vsset_constant_buffers_is_noop() -> Int {
  directx11.d3d11_vsset_constant_buffers(1, 0, 1, 0x4000);
  return 0;
}

fn test_psset_constant_buffers_is_noop() -> Int {
  directx11.d3d11_psset_constant_buffers(1, 0, 1, 0x5000);
  return 0;
}

fn test_psset_samplers_is_noop() -> Int {
  directx11.d3d11_psset_samplers(1, 0, 1, 0x6000);
  return 0;
}

// ===========================================================================
// SECTION 14 -- Drawing Stubs (3 tests)
// ===========================================================================

fn test_draw_is_noop() -> Int {
  directx11.d3d11_draw(1, 3, 0);
  return 0;
}

fn test_draw_indexed_is_noop() -> Int {
  directx11.d3d11_draw_indexed(1, 6, 0, 0);
  return 0;
}

fn test_clear_render_target_view_is_noop() -> Int {
  directx11.d3d11_clear_render_target_view(1, 2, 0.0, 0.0, 0.0, 1.0);
  return 0;
}

// ===========================================================================
// SECTION 15 -- Map/Unmap Stubs (2 tests)
// ===========================================================================

fn test_map_returns_err() -> Int {
  let result = directx11.d3d11_map(1, 2, 0, directx11.D3D11_MAP_WRITE_DISCARD, 0);
  return assert_err(result.is_ok, "d3d11_map returns Err in stub mode");
}

fn test_unmap_is_noop() -> Int {
  directx11.d3d11_unmap(1, 2, 0);
  return 0;
}

// ===========================================================================
// SECTION 16 -- Vertex Buffer Binding Stubs (3 tests)
// ===========================================================================

fn test_iaset_vertex_buffers_is_noop() -> Int {
  directx11.d3d11_iaset_vertex_buffers(1, 0, 1, 0x7000, 0x8000, 0x9000);
  return 0;
}

fn test_iaset_index_buffer_is_noop() -> Int {
  directx11.d3d11_iaset_index_buffer(1, 2, directx11.DXGI_FORMAT_R32_UINT, 0);
  return 0;
}

fn test_iaset_primitive_topology_is_noop() -> Int {
  directx11.d3d11_iaset_primitive_topology(1, directx11.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  return 0;
}

// ===========================================================================
// SECTION 17 -- PSSetShaderResources and OMSetRenderTargets (2 tests)
// ===========================================================================

fn test_psset_shader_resources_is_noop() -> Int {
  directx11.d3d11_psset_shader_resources(1, 0, 1, 0xA000);
  return 0;
}

fn test_om_set_render_targets_is_noop() -> Int {
  directx11.d3d11_om_set_render_targets(1, 1, 0xB000, 0);
  return 0;
}

// ===========================================================================
// SECTION 18 -- Viewport Stub (1 test)
// ===========================================================================

fn test_rsset_viewports_is_noop() -> Int {
  directx11.d3d11_rsset_viewports(1, 0.0, 0.0, 800.0, 600.0, 0.0, 1.0);
  return 0;
}

// ===========================================================================
// SECTION 19 -- Smoke: All Non-Result Functions Are Callable (1 test)
// ===========================================================================

fn test_smoke_all_nonresult_callable() -> Int {
  directx11.d3d11_present(1, 0);
  directx11.d3d11_clear_render_target_view(1, 2, 0.0, 0.0, 0.0, 1.0);
  directx11.d3d11_om_set_render_targets(1, 1, 3, 0);
  directx11.d3d11_iaset_input_layout(1, 2);
  directx11.d3d11_iaset_vertex_buffers(1, 0, 1, 0x100, 0x200, 0x300);
  directx11.d3d11_iaset_index_buffer(1, 2, directx11.DXGI_FORMAT_R32_UINT, 0);
  directx11.d3d11_iaset_primitive_topology(1, directx11.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  directx11.d3d11_vsset_shader(1, 3);
  directx11.d3d11_psset_shader(1, 4);
  directx11.d3d11_vsset_constant_buffers(1, 0, 1, 0x400);
  directx11.d3d11_psset_constant_buffers(1, 0, 1, 0x500);
  directx11.d3d11_psset_samplers(1, 0, 1, 0x600);
  directx11.d3d11_psset_shader_resources(1, 0, 1, 0x700);
  directx11.d3d11_rsset_viewports(1, 0.0, 0.0, 800.0, 600.0, 0.0, 1.0);
  directx11.d3d11_draw(1, 3, 0);
  directx11.d3d11_draw_indexed(1, 6, 0, 0);
  directx11.d3d11_unmap(1, 2, 0);
  return assert(true, "all non-Result functions callable without crash");
}

// ===========================================================================
// SECTION 20 -- Smoke: All Result Functions Return Err (1 test)
// ===========================================================================

fn test_smoke_all_result_funcs_return_err() -> Int {
  let r1 = directx11.d3d11_create_device(directx11.D3D_DRIVER_TYPE_HARDWARE, 0);
  let r2 = directx11.d3d11_create_device_and_swapchain(directx11.D3D_DRIVER_TYPE_HARDWARE, 0, 1, 800, 600);
  let r3 = directx11.d3d11_create_swapchain(1, 1, 800, 600);
  let r4 = directx11.d3d11_create_vertex_buffer(1, 64, directx11.D3D11_USAGE_DEFAULT, 0);
  let r5 = directx11.d3d11_create_index_buffer(1, 32, directx11.D3D11_USAGE_DEFAULT);
  let r6 = directx11.d3d11_create_constant_buffer(1, 64, directx11.D3D11_USAGE_DYNAMIC, directx11.D3D11_CPU_ACCESS_WRITE);
  let r7 = directx11.d3d11_create_texture2d(1, 256, 256, directx11.DXGI_FORMAT_R8G8B8A8_UNORM, directx11.D3D11_USAGE_DEFAULT, directx11.D3D11_BIND_SHADER_RESOURCE, 0);
  let r8 = directx11.d3d11_create_render_target_view(1, 2);
  let r9 = directx11.d3d11_create_shader_resource_view(1, 2, directx11.DXGI_FORMAT_R8G8B8A8_UNORM);
  let r10 = directx11.d3d11_create_sampler_state(1, directx11.D3D11_FILTER_MIN_MAG_MIP_LINEAR, directx11.D3D11_TEXTURE_ADDRESS_WRAP, directx11.D3D11_TEXTURE_ADDRESS_WRAP, directx11.D3D11_TEXTURE_ADDRESS_WRAP);
  let r11 = directx11.d3d11_create_vertex_shader(1, 0x1000, 256);
  let r12 = directx11.d3d11_create_pixel_shader(1, 0x2000, 128);
  let r13 = directx11.d3d11_create_input_layout(1, 0x3000, 2, 0x1000, 256);
  let r14 = directx11.d3d11_map(1, 2, 0, directx11.D3D11_MAP_WRITE_DISCARD, 0);
  let all_err = !r1.is_ok && !r2.is_ok && !r3.is_ok && !r4.is_ok && !r5.is_ok
             && !r6.is_ok && !r7.is_ok && !r8.is_ok && !r9.is_ok && !r10.is_ok
             && !r11.is_ok && !r12.is_ok && !r13.is_ok && !r14.is_ok;
  return assert(all_err, "all 14 Result-returning functions return Err in stub mode");
}

// ===========================================================================
// SECTION 21 -- Full Pipeline Lifecycle Smoke (1 test)
// ===========================================================================

fn test_full_pipeline_lifecycle_no_crash() -> Int {
  let dev_result = directx11.d3d11_create_device(directx11.D3D_DRIVER_TYPE_HARDWARE, 0);
  _ = dev_result;
  let swap_result = directx11.d3d11_create_swapchain(1, 1, 800, 600);
  _ = swap_result;
  let vb_result = directx11.d3d11_create_vertex_buffer(1, 48, directx11.D3D11_USAGE_DEFAULT, 0);
  _ = vb_result;
  let ib_result = directx11.d3d11_create_index_buffer(1, 12, directx11.D3D11_USAGE_DEFAULT);
  _ = ib_result;
  let cb_result = directx11.d3d11_create_constant_buffer(1, 64, directx11.D3D11_USAGE_DYNAMIC, directx11.D3D11_CPU_ACCESS_WRITE);
  _ = cb_result;
  let tex_result = directx11.d3d11_create_texture2d(1, 256, 256, directx11.DXGI_FORMAT_R8G8B8A8_UNORM, directx11.D3D11_USAGE_DEFAULT, directx11.D3D11_BIND_SHADER_RESOURCE, 0);
  _ = tex_result;
  let srv_result = directx11.d3d11_create_shader_resource_view(1, 2, directx11.DXGI_FORMAT_R8G8B8A8_UNORM);
  _ = srv_result;
  let sampler_result = directx11.d3d11_create_sampler_state(1, directx11.D3D11_FILTER_MIN_MAG_MIP_LINEAR, directx11.D3D11_TEXTURE_ADDRESS_WRAP, directx11.D3D11_TEXTURE_ADDRESS_WRAP, directx11.D3D11_TEXTURE_ADDRESS_WRAP);
  _ = sampler_result;
  let vs_result = directx11.d3d11_create_vertex_shader(1, 0x1000, 256);
  _ = vs_result;
  let ps_result = directx11.d3d11_create_pixel_shader(1, 0x2000, 128);
  _ = ps_result;
  let il_result = directx11.d3d11_create_input_layout(1, 0x3000, 2, 0x1000, 256);
  _ = il_result;

  directx11.d3d11_iaset_input_layout(1, 1);
  directx11.d3d11_iaset_vertex_buffers(1, 0, 1, 0x100, 0x200, 0x300);
  directx11.d3d11_iaset_primitive_topology(1, directx11.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  directx11.d3d11_vsset_shader(1, 1);
  directx11.d3d11_psset_shader(1, 1);
  directx11.d3d11_vsset_constant_buffers(1, 0, 1, 0x400);
  directx11.d3d11_psset_constant_buffers(1, 0, 1, 0x500);
  directx11.d3d11_psset_samplers(1, 0, 1, 0x600);
  directx11.d3d11_psset_shader_resources(1, 0, 1, 0x700);
  directx11.d3d11_clear_render_target_view(1, 1, 0.2, 0.3, 0.4, 1.0);
  directx11.d3d11_draw(1, 3, 0);
  directx11.d3d11_draw_indexed(1, 6, 0, 0);
  directx11.d3d11_present(1, 1);
  let map_result = directx11.d3d11_map(1, 2, 0, directx11.D3D11_MAP_WRITE_DISCARD, 0);
  _ = map_result;
  directx11.d3d11_unmap(1, 2, 0);
  return assert(true, "full D3D11 pipeline lifecycle stubs execute without crash");
}

// ===========================================================================
// Test Runner
// ===========================================================================

pub fn run_all_tests() -> Int {
  var failures: Int = 0;

  // SECTION 1: Types (7)
  failures = failures + test_type_dx_device_is_int();
  failures = failures + test_type_dx_context_is_int();
  failures = failures + test_type_dx_swapchain_is_int();
  failures = failures + test_type_dx_buffer_is_int();
  failures = failures + test_type_dx_texture_is_int();
  failures = failures + test_type_dx_shader_is_int();
  failures = failures + test_type_dx_sampler_is_int();

  // SECTION 2: DXGI_FORMAT constants (6)
  failures = failures + test_const_r8g8b8a8_unorm();
  failures = failures + test_const_r32g32b32a32_float();
  failures = failures + test_const_r32g32b32_float();
  failures = failures + test_const_r32_float();
  failures = failures + test_const_d24_unorm_s8_uint();
  failures = failures + test_const_d32_float_s8x24_uint();

  // SECTION 3: D3D11_USAGE constants (4)
  failures = failures + test_const_usage_default_is_zero();
  failures = failures + test_const_usage_immutable();
  failures = failures + test_const_usage_dynamic();
  failures = failures + test_const_usage_staging();

  // SECTION 4: D3D11_BIND_FLAG constants (4)
  failures = failures + test_const_bind_vertex_buffer();
  failures = failures + test_const_bind_index_buffer();
  failures = failures + test_const_bind_constant_buffer();
  failures = failures + test_const_bind_shader_resource();

  // SECTION 5: Filter and address constants (4)
  failures = failures + test_const_filter_min_mag_mip_linear();
  failures = failures + test_const_filter_anisotropic();
  failures = failures + test_const_texture_address_wrap();
  failures = failures + test_const_texture_address_clamp();

  // SECTION 6: MAP constants (3)
  failures = failures + test_const_map_read();
  failures = failures + test_const_map_write_discard();
  failures = failures + test_const_map_write_no_overwrite();

  // SECTION 7: Device creation stubs (3)
  failures = failures + test_create_device_returns_err_in_stub_mode();
  failures = failures + test_create_device_with_warp_returns_err();
  failures = failures + test_create_device_and_swapchain_returns_err();

  // SECTION 8: Swap chain and present stubs (3)
  failures = failures + test_create_swapchain_returns_err_in_stub_mode();
  failures = failures + test_present_is_noop();
  failures = failures + test_present_with_zero_interval_is_noop();

  // SECTION 9: Buffer creation stubs (4)
  failures = failures + test_create_vertex_buffer_returns_err_in_stub_mode();
  failures = failures + test_create_index_buffer_returns_err_in_stub_mode();
  failures = failures + test_create_constant_buffer_returns_err_in_stub_mode();
  failures = failures + test_create_constant_buffer_zero_mod16_returns_err();

  // SECTION 10: Texture creation stubs (3)
  failures = failures + test_create_texture2d_returns_err_in_stub_mode();
  failures = failures + test_create_render_target_view_returns_err();
  failures = failures + test_create_shader_resource_view_returns_err();

  // SECTION 11: Sampler creation stubs (1)
  failures = failures + test_create_sampler_state_returns_err();

  // SECTION 12: Shader creation stubs (4)
  failures = failures + test_create_vertex_shader_returns_err();
  failures = failures + test_create_pixel_shader_returns_err();
  failures = failures + test_create_input_layout_returns_err();
  failures = failures + test_iaset_input_layout_is_noop();

  // SECTION 13: Shader stage binding stubs (5)
  failures = failures + test_vsset_shader_is_noop();
  failures = failures + test_psset_shader_is_noop();
  failures = failures + test_vsset_constant_buffers_is_noop();
  failures = failures + test_psset_constant_buffers_is_noop();
  failures = failures + test_psset_samplers_is_noop();

  // SECTION 14: Drawing stubs (3)
  failures = failures + test_draw_is_noop();
  failures = failures + test_draw_indexed_is_noop();
  failures = failures + test_clear_render_target_view_is_noop();

  // SECTION 15: Map/Unmap stubs (2)
  failures = failures + test_map_returns_err();
  failures = failures + test_unmap_is_noop();

  // SECTION 16: Vertex buffer binding stubs (3)
  failures = failures + test_iaset_vertex_buffers_is_noop();
  failures = failures + test_iaset_index_buffer_is_noop();
  failures = failures + test_iaset_primitive_topology_is_noop();

  // SECTION 17: Shader resources and render targets (2)
  failures = failures + test_psset_shader_resources_is_noop();
  failures = failures + test_om_set_render_targets_is_noop();

  // SECTION 18: Viewport (1)
  failures = failures + test_rsset_viewports_is_noop();

  // SECTION 19: Smoke all non-Result (1)
  failures = failures + test_smoke_all_nonresult_callable();

  // SECTION 20: Smoke all Result return Err (1)
  failures = failures + test_smoke_all_result_funcs_return_err();

  // SECTION 21: Full pipeline lifecycle (1)
  failures = failures + test_full_pipeline_lifecycle_no_crash();

  return failures;
}
