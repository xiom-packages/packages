// XIOM -- Direct3D 11 Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Pure SPEC package -- all FFI calls return Err until the C bridge is linked.
// Wraps Direct3D 11 API. Requires Windows SDK (installed with Visual Studio or winget).
// Depends on: xiom.ffi (stdlib), Windows SDK.
//
// Real C bridge will be linked after xiom.ffi matures.
// Compile (when bridge ready):
//   xiom --link d3d11 dxgi directx11.xi directx11_bridge.c

module xiom.directx11

// -- Opaque handle types ----------------------------------------------------

pub type DxDevice = Int;
pub type DxContext = Int;
pub type DxSwapChain = Int;
pub type DxBuffer = Int;
pub type DxTexture = Int;
pub type DxShader = Int;
pub type DxSampler = Int;

// -- DXGI_FORMAT Constants --------------------------------------------------

pub const DXGI_FORMAT_UNKNOWN: Int = 0;
pub const DXGI_FORMAT_R32G32B32A32_FLOAT: Int = 2;
pub const DXGI_FORMAT_R32G32B32A32_UINT: Int = 3;
pub const DXGI_FORMAT_R32G32B32_FLOAT: Int = 6;
pub const DXGI_FORMAT_R32G32B32_UINT: Int = 7;
pub const DXGI_FORMAT_R32G32_FLOAT: Int = 16;
pub const DXGI_FORMAT_R32_FLOAT: Int = 41;
pub const DXGI_FORMAT_R32_UINT: Int = 42;
pub const DXGI_FORMAT_R8G8B8A8_UNORM: Int = 28;
pub const DXGI_FORMAT_R8G8B8A8_UINT: Int = 30;
pub const DXGI_FORMAT_R8G8B8A8_SNORM: Int = 31;
pub const DXGI_FORMAT_B8G8R8A8_UNORM: Int = 87;
pub const DXGI_FORMAT_R16G16B16A16_FLOAT: Int = 10;
pub const DXGI_FORMAT_R16G16_FLOAT: Int = 34;
pub const DXGI_FORMAT_R16_FLOAT: Int = 54;
pub const DXGI_FORMAT_D24_UNORM_S8_UINT: Int = 45;
pub const DXGI_FORMAT_D32_FLOAT: Int = 40;
pub const DXGI_FORMAT_D32_FLOAT_S8X24_UINT: Int = 20;

// -- D3D11_USAGE Constants --------------------------------------------------

pub const D3D11_USAGE_DEFAULT: Int = 0;
pub const D3D11_USAGE_IMMUTABLE: Int = 1;
pub const D3D11_USAGE_DYNAMIC: Int = 2;
pub const D3D11_USAGE_STAGING: Int = 3;

// -- D3D11_CPU_ACCESS_FLAG Constants ----------------------------------------

pub const D3D11_CPU_ACCESS_WRITE: Int = 0x10000;
pub const D3D11_CPU_ACCESS_READ: Int = 0x20000;

// -- D3D11_BIND_FLAG Constants ----------------------------------------------

pub const D3D11_BIND_VERTEX_BUFFER: Int = 0x1;
pub const D3D11_BIND_INDEX_BUFFER: Int = 0x2;
pub const D3D11_BIND_CONSTANT_BUFFER: Int = 0x4;
pub const D3D11_BIND_SHADER_RESOURCE: Int = 0x8;
pub const D3D11_BIND_STREAM_OUTPUT: Int = 0x10;
pub const D3D11_BIND_RENDER_TARGET: Int = 0x20;
pub const D3D11_BIND_DEPTH_STENCIL: Int = 0x40;
pub const D3D11_BIND_UNORDERED_ACCESS: Int = 0x80;

// -- D3D11_PRIMITIVE_TOPOLOGY Constants -------------------------------------

pub const D3D11_PRIMITIVE_TOPOLOGY_UNDEFINED: Int = 0;
pub const D3D11_PRIMITIVE_TOPOLOGY_POINTLIST: Int = 1;
pub const D3D11_PRIMITIVE_TOPOLOGY_LINELIST: Int = 2;
pub const D3D11_PRIMITIVE_TOPOLOGY_LINESTRIP: Int = 3;
pub const D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST: Int = 4;
pub const D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP: Int = 5;

// -- D3D11_MAP Constants ----------------------------------------------------

pub const D3D11_MAP_READ: Int = 1;
pub const D3D11_MAP_WRITE: Int = 2;
pub const D3D11_MAP_READ_WRITE: Int = 3;
pub const D3D11_MAP_WRITE_DISCARD: Int = 4;
pub const D3D11_MAP_WRITE_NO_OVERWRITE: Int = 5;

// -- D3D11_FILTER Constants -------------------------------------------------

pub const D3D11_FILTER_MIN_MAG_MIP_POINT: Int = 0;
pub const D3D11_FILTER_MIN_MAG_POINT_MIP_LINEAR: Int = 0x1;
pub const D3D11_FILTER_MIN_POINT_MAG_LINEAR_MIP_POINT: Int = 0x4;
pub const D3D11_FILTER_MIN_POINT_MAG_MIP_LINEAR: Int = 0x5;
pub const D3D11_FILTER_MIN_LINEAR_MAG_MIP_POINT: Int = 0x10;
pub const D3D11_FILTER_MIN_LINEAR_MAG_POINT_MIP_LINEAR: Int = 0x11;
pub const D3D11_FILTER_MIN_MAG_LINEAR_MIP_POINT: Int = 0x14;
pub const D3D11_FILTER_MIN_MAG_MIP_LINEAR: Int = 0x15;
pub const D3D11_FILTER_ANISOTROPIC: Int = 0x55;

// -- D3D11_TEXTURE_ADDRESS_MODE Constants -----------------------------------

pub const D3D11_TEXTURE_ADDRESS_WRAP: Int = 1;
pub const D3D11_TEXTURE_ADDRESS_MIRROR: Int = 2;
pub const D3D11_TEXTURE_ADDRESS_CLAMP: Int = 3;
pub const D3D11_TEXTURE_ADDRESS_BORDER: Int = 4;
pub const D3D11_TEXTURE_ADDRESS_MIRROR_ONCE: Int = 5;

// -- D3D11_INPUT_CLASSIFICATION Constants -----------------------------------

pub const D3D11_INPUT_PER_VERTEX_DATA: Int = 0;
pub const D3D11_INPUT_PER_INSTANCE_DATA: Int = 1;

// -- D3D11_DRIVER_TYPE Constants --------------------------------------------

pub const D3D_DRIVER_TYPE_HARDWARE: Int = 1;
pub const D3D_DRIVER_TYPE_WARP: Int = 5;
pub const D3D_DRIVER_TYPE_REFERENCE: Int = 6;
pub const D3D_DRIVER_TYPE_SOFTWARE: Int = 7;

// -- D3D11_CREATE_DEVICE_FLAG Constants -------------------------------------

pub const D3D11_CREATE_DEVICE_DEBUG: Int = 0x2;
pub const D3D11_CREATE_DEVICE_SINGLETHREADED: Int = 0x10;
pub const D3D11_CREATE_DEVICE_BGRA_SUPPORT: Int = 0x20;

// -- D3D11_SRV_DIMENSION Constants ------------------------------------------

pub const D3D11_SRV_DIMENSION_UNKNOWN: Int = 0;
pub const D3D11_SRV_DIMENSION_BUFFER: Int = 1;
pub const D3D11_SRV_DIMENSION_TEXTURE1D: Int = 2;
pub const D3D11_SRV_DIMENSION_TEXTURE1DARRAY: Int = 3;
pub const D3D11_SRV_DIMENSION_TEXTURE2D: Int = 4;
pub const D3D11_SRV_DIMENSION_TEXTURE2DARRAY: Int = 5;
pub const D3D11_SRV_DIMENSION_TEXTURE2DMS: Int = 6;
pub const D3D11_SRV_DIMENSION_TEXTURE2DMSARRAY: Int = 7;
pub const D3D11_SRV_DIMENSION_TEXTURE3D: Int = 8;
pub const D3D11_SRV_DIMENSION_TEXTURECUBE: Int = 9;

// ===========================================================================
// extern "C" -- Raw D3D11 Declarations (27 functions)
// ===========================================================================
// These map 1:1 to d3d11.dll / dxgi.dll.
// Pointers are typed as Int for SPEC phase; cast to concrete types when
// the C bridge is linked.

extern "C" {
  // -- Device creation ------------------------------------------------------
  fn D3D11CreateDevice(
    pAdapter: Int,
    driverType: Int,
    software: Int,
    flags: Int,
    featureLevels: Int,
    featureLevelsCount: Int,
    sdkVersion: Int,
    ppDevice: Int,
    pFeatureLevel: Int,
    ppImmediateContext: Int
  ) -> Int;

  fn D3D11CreateDeviceAndSwapChain(
    pAdapter: Int,
    driverType: Int,
    software: Int,
    flags: Int,
    featureLevels: Int,
    featureLevelsCount: Int,
    sdkVersion: Int,
    pSwapChainDesc: Int,
    ppSwapChain: Int,
    ppDevice: Int,
    pFeatureLevel: Int,
    ppImmediateContext: Int
  ) -> Int;

  // -- Swap chain -----------------------------------------------------------
  fn CreateSwapChain(
    pDevice: Int,
    pSwapChainDesc: Int,
    ppSwapChain: Int
  ) -> Int;

  // -- Render target view ---------------------------------------------------
  fn CreateRenderTargetView(
    pDevice: Int,
    pResource: Int,
    pDesc: Int,
    ppRenderTargetView: Int
  ) -> Int;

  fn ClearRenderTargetView(
    pContext: Int,
    pRenderTargetView: Int,
    colorRGBA: Int
  );

  fn OMSetRenderTargets(
    pContext: Int,
    numViews: Int,
    ppRenderTargetViews: Int,
    pDepthStencilView: Int
  );

  // -- Buffer creation ------------------------------------------------------
  fn CreateBuffer(
    pDevice: Int,
    pDesc: Int,
    pInitialData: Int,
    ppBuffer: Int
  ) -> Int;

  // -- Texture creation -----------------------------------------------------
  fn CreateTexture2D(
    pDevice: Int,
    pDesc: Int,
    pInitialData: Int,
    ppTexture2D: Int
  ) -> Int;

  fn CreateShaderResourceView(
    pDevice: Int,
    pResource: Int,
    pDesc: Int,
    ppSRView: Int
  ) -> Int;

  // -- Sampler --------------------------------------------------------------
  fn CreateSamplerState(
    pDevice: Int,
    pSamplerDesc: Int,
    ppSamplerState: Int
  ) -> Int;

  // -- Shaders --------------------------------------------------------------
  fn CreateVertexShader(
    pDevice: Int,
    pShaderBytecode: Int,
    bytecodeLength: Int,
    pClassLinkage: Int,
    ppVertexShader: Int
  ) -> Int;

  fn CreatePixelShader(
    pDevice: Int,
    pShaderBytecode: Int,
    bytecodeLength: Int,
    pClassLinkage: Int,
    ppPixelShader: Int
  ) -> Int;

  fn CreateInputLayout(
    pDevice: Int,
    pInputElementDescs: Int,
    numElements: Int,
    pShaderBytecode: Int,
    bytecodeLength: Int,
    ppInputLayout: Int
  ) -> Int;

  fn IASetInputLayout(
    pContext: Int,
    pInputLayout: Int
  );

  // -- Vertex buffers -------------------------------------------------------
  fn IASetVertexBuffers(
    pContext: Int,
    startSlot: Int,
    numBuffers: Int,
    ppVertexBuffers: Int,
    pStrides: Int,
    pOffsets: Int
  );

  fn IASetIndexBuffer(
    pContext: Int,
    pIndexBuffer: Int,
    format: Int,
    offset: Int
  );

  fn IASetPrimitiveTopology(
    pContext: Int,
    topology: Int
  );

  // -- Shader stage binding -------------------------------------------------
  fn VSSetShader(
    pContext: Int,
    pVertexShader: Int,
    pClassInstances: Int,
    numClassInstances: Int
  );

  fn PSSetShader(
    pContext: Int,
    pPixelShader: Int,
    pClassInstances: Int,
    numClassInstances: Int
  );

  fn VSSetConstantBuffers(
    pContext: Int,
    startSlot: Int,
    numBuffers: Int,
    ppConstantBuffers: Int
  );

  fn PSSetConstantBuffers(
    pContext: Int,
    startSlot: Int,
    numBuffers: Int,
    ppConstantBuffers: Int
  );

  fn PSSetSamplers(
    pContext: Int,
    startSlot: Int,
    numSamplers: Int,
    ppSamplers: Int
  );

  fn PSSetShaderResources(
    pContext: Int,
    startSlot: Int,
    numViews: Int,
    ppShaderResourceViews: Int
  );

  // -- Viewport and rasterizer ----------------------------------------------
  fn RSSetViewports(
    pContext: Int,
    numViewports: Int,
    pViewports: Int
  );

  // -- Drawing --------------------------------------------------------------
  fn Draw(
    pContext: Int,
    vertexCount: Int,
    startVertexLocation: Int
  );

  fn DrawIndexed(
    pContext: Int,
    indexCount: Int,
    startIndexLocation: Int,
    baseVertexLocation: Int
  );

  // -- Present / sync -------------------------------------------------------
  fn Present(
    pSwapChain: Int,
    syncInterval: Int,
    flags: Int
  ) -> Int;

  // -- Resource mapping -----------------------------------------------------
  fn Map(
    pContext: Int,
    pResource: Int,
    subresource: Int,
    mapType: Int,
    mapFlags: Int,
    pMappedResource: Int
  ) -> Int;

  fn Unmap(
    pContext: Int,
    pResource: Int,
    subresource: Int
  );
}

// ===========================================================================
// Safe Wrappers: Device
// ===========================================================================

pub fn d3d11_create_device(driver_type: Int, flags: Int) -> Result[(DxDevice, DxContext), Str]
  requires: driver_type == D3D_DRIVER_TYPE_HARDWARE || driver_type == D3D_DRIVER_TYPE_WARP || driver_type == D3D_DRIVER_TYPE_REFERENCE || driver_type == D3D_DRIVER_TYPE_SOFTWARE
  ensures:  result.is_ok || result.is_err
{
  return Err("d3d11_create_device: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

pub fn d3d11_create_device_and_swapchain(
  driver_type: Int, flags: Int, hwnd: Int, width: Int, height: Int
) -> Result[(DxDevice, DxContext, DxSwapChain), Str]
  requires: driver_type == D3D_DRIVER_TYPE_HARDWARE || driver_type == D3D_DRIVER_TYPE_WARP || driver_type == D3D_DRIVER_TYPE_REFERENCE || driver_type == D3D_DRIVER_TYPE_SOFTWARE
  requires: width > 0
  requires: height > 0
  ensures:  result.is_ok || result.is_err
{
  return Err("d3d11_create_device_and_swapchain: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

// ===========================================================================
// Safe Wrappers: Swap Chain
// ===========================================================================

pub fn d3d11_present(swap: DxSwapChain, sync_interval: Int)
  requires: swap != 0
  requires: sync_interval >= 0
  requires: sync_interval <= 4
{
}

pub fn d3d11_create_swapchain(
  dev: DxDevice, hwnd: Int, width: Int, height: Int
) -> Result[DxSwapChain, Str]
  requires: dev != 0
  requires: width > 0
  requires: height > 0
{
  return Err("d3d11_create_swapchain: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

// ===========================================================================
// Safe Wrappers: Render Target
// ===========================================================================

pub fn d3d11_create_render_target_view(
  dev: DxDevice, resource: DxTexture
) -> Result[DxTexture, Str]
  requires: dev != 0
  requires: resource != 0
{
  return Err("d3d11_create_render_target_view: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

pub fn d3d11_clear_render_target_view(ctx: DxContext, rtv: DxTexture, r: Float32, g: Float32, b: Float32, a: Float32)
  requires: ctx != 0
  requires: rtv != 0
  requires: r >= 0.0 && r <= 1.0
  requires: g >= 0.0 && g <= 1.0
  requires: b >= 0.0 && b <= 1.0
  requires: a >= 0.0 && a <= 1.0
{
}

pub fn d3d11_om_set_render_targets(ctx: DxContext, count: Int, rtvs: Int, dsv: Int)
  requires: ctx != 0
  requires: count >= 0
  requires: count <= 8
{
}

// ===========================================================================
// Safe Wrappers: Buffer
// ===========================================================================

pub fn d3d11_create_vertex_buffer(
  dev: DxDevice, size: Int, usage: Int, cpu_access: Int
) -> Result[DxBuffer, Str]
  requires: dev != 0
  requires: size > 0
  requires: usage == D3D11_USAGE_DEFAULT || usage == D3D11_USAGE_IMMUTABLE || usage == D3D11_USAGE_DYNAMIC || usage == D3D11_USAGE_STAGING
{
  return Err("d3d11_create_vertex_buffer: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

pub fn d3d11_create_index_buffer(
  dev: DxDevice, size: Int, usage: Int
) -> Result[DxBuffer, Str]
  requires: dev != 0
  requires: size > 0
  requires: usage == D3D11_USAGE_DEFAULT || usage == D3D11_USAGE_IMMUTABLE || usage == D3D11_USAGE_DYNAMIC || usage == D3D11_USAGE_STAGING
{
  return Err("d3d11_create_index_buffer: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

pub fn d3d11_create_constant_buffer(
  dev: DxDevice, size: Int, usage: Int, cpu_access: Int
) -> Result[DxBuffer, Str]
  requires: dev != 0
  requires: size > 0
  requires: size % 16 == 0
  requires: usage == D3D11_USAGE_DEFAULT || usage == D3D11_USAGE_DYNAMIC || usage == D3D11_USAGE_STAGING
{
  return Err("d3d11_create_constant_buffer: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

pub fn d3d11_iaset_vertex_buffers(
  ctx: DxContext, start_slot: Int, count: Int, buffers: Int, strides: Int, offsets: Int
)
  requires: ctx != 0
  requires: start_slot >= 0
  requires: count >= 0
  requires: count <= 32
{
}

pub fn d3d11_iaset_index_buffer(ctx: DxContext, buf: DxBuffer, format: Int, offset: Int)
  requires: ctx != 0
  requires: buf != 0
  requires: format == DXGI_FORMAT_R32_UINT || format == DXGI_FORMAT_R16_UINT || format == DXGI_FORMAT_R8_UINT
  requires: offset >= 0
{
}

pub fn d3d11_iaset_primitive_topology(ctx: DxContext, topology: Int)
  requires: ctx != 0
  requires: topology == D3D11_PRIMITIVE_TOPOLOGY_UNDEFINED || topology == D3D11_PRIMITIVE_TOPOLOGY_POINTLIST || topology == D3D11_PRIMITIVE_TOPOLOGY_LINELIST || topology == D3D11_PRIMITIVE_TOPOLOGY_LINESTRIP || topology == D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST || topology == D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP
{
}

// ===========================================================================
// Safe Wrappers: Texture
// ===========================================================================

pub fn d3d11_create_texture2d(
  dev: DxDevice, width: Int, height: Int, format: Int, usage: Int, bind_flags: Int, cpu_access: Int
) -> Result[DxTexture, Str]
  requires: dev != 0
  requires: width > 0
  requires: height > 0
  requires: usage == D3D11_USAGE_DEFAULT || usage == D3D11_USAGE_IMMUTABLE || usage == D3D11_USAGE_DYNAMIC || usage == D3D11_USAGE_STAGING
{
  return Err("d3d11_create_texture2d: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

pub fn d3d11_create_shader_resource_view(
  dev: DxDevice, resource: DxTexture, format: Int
) -> Result[DxTexture, Str]
  requires: dev != 0
  requires: resource != 0
{
  return Err("d3d11_create_shader_resource_view: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

// ===========================================================================
// Safe Wrappers: Sampler
// ===========================================================================

pub fn d3d11_create_sampler_state(
  dev: DxDevice, filter: Int, address_u: Int, address_v: Int, address_w: Int
) -> Result[DxSampler, Str]
  requires: dev != 0
  requires: filter >= 0
  requires: address_u == D3D11_TEXTURE_ADDRESS_WRAP || address_u == D3D11_TEXTURE_ADDRESS_MIRROR || address_u == D3D11_TEXTURE_ADDRESS_CLAMP || address_u == D3D11_TEXTURE_ADDRESS_BORDER || address_u == D3D11_TEXTURE_ADDRESS_MIRROR_ONCE
  requires: address_v == D3D11_TEXTURE_ADDRESS_WRAP || address_v == D3D11_TEXTURE_ADDRESS_MIRROR || address_v == D3D11_TEXTURE_ADDRESS_CLAMP || address_v == D3D11_TEXTURE_ADDRESS_BORDER || address_v == D3D11_TEXTURE_ADDRESS_MIRROR_ONCE
  requires: address_w == D3D11_TEXTURE_ADDRESS_WRAP || address_w == D3D11_TEXTURE_ADDRESS_MIRROR || address_w == D3D11_TEXTURE_ADDRESS_CLAMP || address_w == D3D11_TEXTURE_ADDRESS_BORDER || address_w == D3D11_TEXTURE_ADDRESS_MIRROR_ONCE
{
  return Err("d3d11_create_sampler_state: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

// ===========================================================================
// Safe Wrappers: Shaders
// ===========================================================================

pub fn d3d11_create_vertex_shader(
  dev: DxDevice, bytecode: Int, bytecode_len: Int
) -> Result[DxShader, Str]
  requires: dev != 0
  requires: bytecode != 0
  requires: bytecode_len > 0
{
  return Err("d3d11_create_vertex_shader: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

pub fn d3d11_create_pixel_shader(
  dev: DxDevice, bytecode: Int, bytecode_len: Int
) -> Result[DxShader, Str]
  requires: dev != 0
  requires: bytecode != 0
  requires: bytecode_len > 0
{
  return Err("d3d11_create_pixel_shader: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

pub fn d3d11_create_input_layout(
  dev: DxDevice, elements: Int, num_elements: Int, bytecode: Int, bytecode_len: Int
) -> Result[DxBuffer, Str]
  requires: dev != 0
  requires: num_elements > 0
  requires: num_elements <= 32
  requires: bytecode != 0
  requires: bytecode_len > 0
{
  return Err("d3d11_create_input_layout: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

pub fn d3d11_iaset_input_layout(ctx: DxContext, layout: DxBuffer)
  requires: ctx != 0
  requires: layout != 0
{
}

pub fn d3d11_vsset_shader(ctx: DxContext, shader: DxShader)
  requires: ctx != 0
  requires: shader != 0
{
}

pub fn d3d11_psset_shader(ctx: DxContext, shader: DxShader)
  requires: ctx != 0
  requires: shader != 0
{
}

pub fn d3d11_vsset_constant_buffers(ctx: DxContext, start_slot: Int, count: Int, buffers: Int)
  requires: ctx != 0
  requires: start_slot >= 0
  requires: count >= 0
  requires: count <= 16
{
}

pub fn d3d11_psset_constant_buffers(ctx: DxContext, start_slot: Int, count: Int, buffers: Int)
  requires: ctx != 0
  requires: start_slot >= 0
  requires: count >= 0
  requires: count <= 16
{
}

pub fn d3d11_psset_samplers(ctx: DxContext, start_slot: Int, count: Int, samplers: Int)
  requires: ctx != 0
  requires: start_slot >= 0
  requires: count >= 0
  requires: count <= 16
{
}

pub fn d3d11_psset_shader_resources(ctx: DxContext, start_slot: Int, count: Int, views: Int)
  requires: ctx != 0
  requires: start_slot >= 0
  requires: count >= 0
  requires: count <= 128
{
}

// ===========================================================================
// Safe Wrappers: Viewport and Drawing
// ===========================================================================

pub fn d3d11_rsset_viewports(ctx: DxContext, x: Float32, y: Float32, w: Float32, h: Float32, min_depth: Float32, max_depth: Float32)
  requires: ctx != 0
  requires: w >= 0.0
  requires: h >= 0.0
  requires: min_depth >= 0.0 && min_depth <= 1.0
  requires: max_depth >= 0.0 && max_depth <= 1.0 && max_depth >= min_depth
{
}

pub fn d3d11_draw(ctx: DxContext, vertex_count: Int, start_vertex: Int)
  requires: ctx != 0
  requires: vertex_count > 0
  requires: start_vertex >= 0
{
}

pub fn d3d11_draw_indexed(ctx: DxContext, index_count: Int, start_index: Int, base_vertex: Int)
  requires: ctx != 0
  requires: index_count > 0
  requires: start_index >= 0
{
}

// ===========================================================================
// Safe Wrappers: Resource Mapping
// ===========================================================================

pub fn d3d11_map(
  ctx: DxContext, resource: Int, subresource: Int, map_type: Int, map_flags: Int
) -> Result[Int, Str]
  requires: ctx != 0
  requires: resource != 0
  requires: subresource >= 0
  requires: map_type == D3D11_MAP_READ || map_type == D3D11_MAP_WRITE || map_type == D3D11_MAP_READ_WRITE || map_type == D3D11_MAP_WRITE_DISCARD || map_type == D3D11_MAP_WRITE_NO_OVERWRITE
{
  return Err("d3d11_map: C bridge not yet linked -- xiom.directx11 is in SPEC phase");
}

pub fn d3d11_unmap(ctx: DxContext, resource: Int, subresource: Int)
  requires: ctx != 0
  requires: resource != 0
  requires: subresource >= 0
{
}
