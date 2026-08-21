// XIOM -- Direct3D 12 Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Pure SPEC package -- all FFI calls return Err until the C bridge is linked.
// Wraps Direct3D 12 API. Requires Windows SDK (installed with Visual Studio or winget).
// Depends on: xiom.ffi (stdlib), Windows SDK.
//
// Real C bridge will be linked after xiom.ffi matures.
// Compile (when bridge ready):
//   xiom --link d3d12 dxgi dxguid directx12.xi directx12_bridge.c

module xiom.directx12

// -- Opaque handle types (10 types) ------------------------------------------

pub type DxDevice          = Int;
pub type DxCommandQueue    = Int;
pub type DxSwapChain       = Int;
pub type DxResource        = Int;
pub type DxDescriptorHeap  = Int;
pub type DxCommandAllocator = Int;
pub type DxCommandList     = Int;
pub type DxFence           = Int;
pub type DxRootSignature   = Int;
pub type DxPipelineState   = Int;

// -- DXGI_FORMAT Constants ---------------------------------------------------

pub const DXGI_FORMAT_UNKNOWN:               Int = 0;
pub const DXGI_FORMAT_R32G32B32A32_FLOAT:    Int = 2;
pub const DXGI_FORMAT_R32G32B32A32_UINT:     Int = 3;
pub const DXGI_FORMAT_R32G32B32_FLOAT:       Int = 6;
pub const DXGI_FORMAT_R32G32B32_UINT:        Int = 7;
pub const DXGI_FORMAT_R32G32_FLOAT:          Int = 16;
pub const DXGI_FORMAT_R32_FLOAT:             Int = 41;
pub const DXGI_FORMAT_R32_UINT:              Int = 42;
pub const DXGI_FORMAT_R16_UINT:              Int = 57;
pub const DXGI_FORMAT_R8G8B8A8_UNORM:        Int = 28;
pub const DXGI_FORMAT_R8G8B8A8_UINT:         Int = 30;
pub const DXGI_FORMAT_R8G8B8A8_SNORM:        Int = 31;
pub const DXGI_FORMAT_B8G8R8A8_UNORM:        Int = 87;
pub const DXGI_FORMAT_R16G16B16A16_FLOAT:    Int = 10;
pub const DXGI_FORMAT_R16G16_FLOAT:          Int = 34;
pub const DXGI_FORMAT_D24_UNORM_S8_UINT:     Int = 45;
pub const DXGI_FORMAT_D32_FLOAT:             Int = 40;
pub const DXGI_FORMAT_D32_FLOAT_S8X24_UINT:  Int = 20;

// -- D3D12_RESOURCE_STATES Constants -----------------------------------------

pub const D3D12_RESOURCE_STATE_COMMON:                     Int = 0;
pub const D3D12_RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER: Int = 0x1;
pub const D3D12_RESOURCE_STATE_INDEX_BUFFER:               Int = 0x2;
pub const D3D12_RESOURCE_STATE_RENDER_TARGET:              Int = 0x4;
pub const D3D12_RESOURCE_STATE_UNORDERED_ACCESS:           Int = 0x8;
pub const D3D12_RESOURCE_STATE_DEPTH_WRITE:                Int = 0x10;
pub const D3D12_RESOURCE_STATE_DEPTH_READ:                 Int = 0x20;
pub const D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE:      Int = 0x40;
pub const D3D12_RESOURCE_STATE_STREAM_OUT:                 Int = 0x80;
pub const D3D12_RESOURCE_STATE_INDIRECT_ARGUMENT:          Int = 0x100;
pub const D3D12_RESOURCE_STATE_COPY_DEST:                  Int = 0x400;
pub const D3D12_RESOURCE_STATE_COPY_SOURCE:                Int = 0x800;
pub const D3D12_RESOURCE_STATE_RESOLVE_DEST:               Int = 0x1000;
pub const D3D12_RESOURCE_STATE_RESOLVE_SOURCE:             Int = 0x2000;
pub const D3D12_RESOURCE_STATE_GENERIC_READ:               Int = 0x63;
pub const D3D12_RESOURCE_STATE_PRESENT:                    Int = 0;
pub const D3D12_RESOURCE_STATE_PREDICATION:                Int = 0x200;
pub const D3D12_RESOURCE_STATE_VIDEO_DECODE_READ:          Int = 0x10000;
pub const D3D12_RESOURCE_STATE_VIDEO_DECODE_WRITE:         Int = 0x20000;

// -- D3D12_COMMAND_LIST_TYPE Constants ---------------------------------------

pub const D3D12_COMMAND_LIST_TYPE_DIRECT:    Int = 0;
pub const D3D12_COMMAND_LIST_TYPE_BUNDLE:    Int = 1;
pub const D3D12_COMMAND_LIST_TYPE_COMPUTE:   Int = 2;
pub const D3D12_COMMAND_LIST_TYPE_COPY:      Int = 3;

// -- D3D12_DESCRIPTOR_HEAP_TYPE Constants ------------------------------------

pub const D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV: Int = 0;
pub const D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER:     Int = 1;
pub const D3D12_DESCRIPTOR_HEAP_TYPE_RTV:         Int = 2;
pub const D3D12_DESCRIPTOR_HEAP_TYPE_DSV:         Int = 3;

// -- D3D12_FENCE_FLAGS Constants ---------------------------------------------

pub const D3D12_FENCE_FLAG_NONE:  Int = 0;
pub const D3D12_FENCE_FLAG_SHARED: Int = 0x1;
pub const D3D12_FENCE_FLAG_SHARED_CROSS_ADAPTER: Int = 0x2;

// -- D3D12_HEAP_TYPE Constants -----------------------------------------------

pub const D3D12_HEAP_TYPE_DEFAULT:   Int = 1;
pub const D3D12_HEAP_TYPE_UPLOAD:    Int = 2;
pub const D3D12_HEAP_TYPE_READBACK:  Int = 3;
pub const D3D12_HEAP_TYPE_CUSTOM:    Int = 4;

// -- D3D12_PRIMITIVE_TOPOLOGY Constants --------------------------------------

pub const D3D_PRIMITIVE_TOPOLOGY_UNDEFINED:     Int = 0;
pub const D3D_PRIMITIVE_TOPOLOGY_POINTLIST:     Int = 1;
pub const D3D_PRIMITIVE_TOPOLOGY_LINELIST:      Int = 2;
pub const D3D_PRIMITIVE_TOPOLOGY_LINESTRIP:     Int = 3;
pub const D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST:  Int = 4;
pub const D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP: Int = 5;

// -- D3D12_CLEAR_FLAGS Constants ---------------------------------------------

pub const D3D12_CLEAR_FLAG_DEPTH:   Int = 0x1;
pub const D3D12_CLEAR_FLAG_STENCIL: Int = 0x2;

// ===========================================================================
// extern "C" -- Raw D3D12 Declarations (22 functions)
// ===========================================================================

extern "C" {
  // -- Device creation --------------------------------------------------------
  fn D3D12CreateDevice(
    pAdapter: Int,
    minimumFeatureLevel: Int,
    riid: Int,
    ppDevice: Int
  ) -> Int;

  fn D3D12GetDebugInterface(
    riid: Int,
    ppDebug: Int
  ) -> Int;

  // -- Command queue ----------------------------------------------------------
  fn D3D12CreateCommandQueue(
    pDevice: Int,
    pDesc: Int,
    riid: Int,
    ppCommandQueue: Int
  ) -> Int;

  // -- Swap chain (DXGI) ------------------------------------------------------
  fn CreateDXGIFactory2(
    flags: Int,
    riid: Int,
    ppFactory: Int
  ) -> Int;

  fn CreateSwapChainForHwnd(
    pFactory: Int,
    pCommandQueue: Int,
    hwnd: Int,
    pDesc: Int,
    pFullscreenDesc: Int,
    pRestrictToOutput: Int,
    ppSwapChain: Int
  ) -> Int;

  fn D3D12Present(
    pSwapChain: Int,
    syncInterval: Int,
    flags: Int
  ) -> Int;

  // -- Resource creation ------------------------------------------------------
  fn D3D12CreateCommittedResource(
    pDevice: Int,
    pHeapProperties: Int,
    heapFlags: Int,
    pDesc: Int,
    initialResourceState: Int,
    pOptimizedClearValue: Int,
    riid: Int,
    ppResource: Int
  ) -> Int;

  fn D3D12CreateUploadBuffer(
    pDevice: Int,
    size: Int,
    ppResource: Int
  ) -> Int;

  fn D3D12CreateDefaultBuffer(
    pDevice: Int,
    size: Int,
    usage: Int,
    ppResource: Int
  ) -> Int;

  fn D3D12CreateTexture2D(
    pDevice: Int,
    width: Int,
    height: Int,
    format: Int,
    ppResource: Int
  ) -> Int;

  // -- Descriptor heap --------------------------------------------------------
  fn D3D12CreateDescriptorHeap(
    pDevice: Int,
    pDesc: Int,
    riid: Int,
    ppHeap: Int
  ) -> Int;

  // -- Command allocator / list -----------------------------------------------
  fn D3D12CreateCommandAllocator(
    pDevice: Int,
    cmdListType: Int,
    riid: Int,
    ppAllocator: Int
  ) -> Int;

  fn D3D12CreateGraphicsCommandList(
    pDevice: Int,
    cmdListType: Int,
    pAllocator: Int,
    pInitialState: Int,
    riid: Int,
    ppCommandList: Int
  ) -> Int;

  fn D3D12CloseCommandList(
    pCommandList: Int
  ) -> Int;

  fn D3D12ExecuteCommandLists(
    pCommandQueue: Int,
    numCommandLists: Int,
    ppCommandLists: Int
  );

  // -- Drawing / Rendering ----------------------------------------------------
  fn D3D12ClearRenderTargetView(
    pCommandList: Int,
    cpuDescriptorHandle: Int,
    colorRGBA: Int
  );

  fn D3D12ClearDepthStencilView(
    pCommandList: Int,
    cpuDescriptorHandle: Int,
    clearFlags: Int,
    depth: Float32,
    stencil: Int
  );

  fn D3D12DrawInstanced(
    pCommandList: Int,
    vertexCount: Int,
    instanceCount: Int,
    startVertex: Int,
    startInstance: Int
  );

  // -- Fence / Sync -----------------------------------------------------------
  fn D3D12CreateFence(
    pDevice: Int,
    initialValue: Int,
    flags: Int,
    riid: Int,
    ppFence: Int
  ) -> Int;

  fn D3D12SignalFence(
    pCommandQueue: Int,
    pFence: Int,
    value: Int
  ) -> Int;

  fn D3D12WaitFence(
    pFence: Int,
    value: Int
  ) -> Int;

  // -- Root signature / Pipeline state ----------------------------------------
  fn D3D12CreateRootSignature(
    pDevice: Int,
    nodeMask: Int,
    pBlob: Int,
    blobLengthInBytes: Int,
    riid: Int,
    ppRootSignature: Int
  ) -> Int;
}

// ===========================================================================
// Safe Wrappers: Device
// ===========================================================================

pub fn d3d12_create_device(adapter: Int) -> Result[DxDevice, Str]
  ensures: result.is_ok || result.is_err
{
  return Err("d3d12_create_device: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

pub fn d3d12_get_debug_interface() -> Result[Int, Str]
  ensures: result.is_ok || result.is_err
{
  return Err("d3d12_get_debug_interface: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

// ===========================================================================
// Safe Wrappers: Command Queue
// ===========================================================================

pub fn d3d12_create_command_queue(dev: DxDevice, cmd_list_type: Int) -> Result[DxCommandQueue, Str]
  requires: dev != 0
  requires: cmd_list_type == D3D12_COMMAND_LIST_TYPE_DIRECT || cmd_list_type == D3D12_COMMAND_LIST_TYPE_COMPUTE || cmd_list_type == D3D12_COMMAND_LIST_TYPE_COPY
{
  return Err("d3d12_create_command_queue: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

// ===========================================================================
// Safe Wrappers: Swap Chain
// ===========================================================================

pub fn dxgi_create_swapchain(
  queue: DxCommandQueue, hwnd: Int, width: Int, height: Int
) -> Result[DxSwapChain, Str]
  requires: queue != 0
  requires: width > 0
  requires: height > 0
  requires: hwnd != 0
{
  return Err("dxgi_create_swapchain: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

pub fn d3d12_present(swap: DxSwapChain, sync_interval: Int)
  requires: swap != 0
  requires: sync_interval >= 0
  requires: sync_interval <= 4
{
}

// ===========================================================================
// Safe Wrappers: Resources
// ===========================================================================

pub fn d3d12_create_committed_resource(
  dev: DxDevice, heap_type: Int, size: Int, initial_state: Int, flags: Int
) -> Result[DxResource, Str]
  requires: dev != 0
  requires: size > 0
  requires: heap_type == D3D12_HEAP_TYPE_DEFAULT || heap_type == D3D12_HEAP_TYPE_UPLOAD || heap_type == D3D12_HEAP_TYPE_READBACK
{
  return Err("d3d12_create_committed_resource: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

pub fn d3d12_create_upload_buffer(dev: DxDevice, size: Int) -> Result[DxResource, Str]
  requires: dev != 0
  requires: size > 0
{
  return Err("d3d12_create_upload_buffer: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

pub fn d3d12_create_default_buffer(dev: DxDevice, size: Int, usage: Int) -> Result[DxResource, Str]
  requires: dev != 0
  requires: size > 0
{
  return Err("d3d12_create_default_buffer: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

pub fn d3d12_create_texture2d(
  dev: DxDevice, width: Int, height: Int, format: Int
) -> Result[DxResource, Str]
  requires: dev != 0
  requires: width > 0
  requires: height > 0
{
  return Err("d3d12_create_texture2d: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

// ===========================================================================
// Safe Wrappers: Descriptor Heap
// ===========================================================================

pub fn d3d12_create_descriptor_heap(
  dev: DxDevice, heap_type: Int, num_descriptors: Int, flags: Int
) -> Result[DxDescriptorHeap, Str]
  requires: dev != 0
  requires: num_descriptors > 0
  requires: num_descriptors <= 4096
  requires: heap_type == D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV || heap_type == D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER || heap_type == D3D12_DESCRIPTOR_HEAP_TYPE_RTV || heap_type == D3D12_DESCRIPTOR_HEAP_TYPE_DSV
{
  return Err("d3d12_create_descriptor_heap: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

// ===========================================================================
// Safe Wrappers: Command Allocator / Command List
// ===========================================================================

pub fn d3d12_create_command_allocator(
  dev: DxDevice, cmd_list_type: Int
) -> Result[DxCommandAllocator, Str]
  requires: dev != 0
  requires: cmd_list_type == D3D12_COMMAND_LIST_TYPE_DIRECT || cmd_list_type == D3D12_COMMAND_LIST_TYPE_BUNDLE || cmd_list_type == D3D12_COMMAND_LIST_TYPE_COMPUTE || cmd_list_type == D3D12_COMMAND_LIST_TYPE_COPY
{
  return Err("d3d12_create_command_allocator: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

pub fn d3d12_create_graphics_command_list(
  dev: DxDevice, cmd_list_type: Int, alloc: DxCommandAllocator
) -> Result[DxCommandList, Str]
  requires: dev != 0
  requires: alloc != 0
  requires: cmd_list_type == D3D12_COMMAND_LIST_TYPE_DIRECT || cmd_list_type == D3D12_COMMAND_LIST_TYPE_BUNDLE || cmd_list_type == D3D12_COMMAND_LIST_TYPE_COMPUTE || cmd_list_type == D3D12_COMMAND_LIST_TYPE_COPY
{
  return Err("d3d12_create_graphics_command_list: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

pub fn d3d12_close_command_list(cl: DxCommandList)
  requires: cl != 0
{
}

pub fn d3d12_execute_command_lists(queue: DxCommandQueue, lists: Vec[DxCommandList])
  requires: queue != 0
  requires: lists.len() > 0
{
}

// ===========================================================================
// Safe Wrappers: Rendering
// ===========================================================================

pub fn d3d12_clear_rtv(
  cl: DxCommandList, rtv_handle: Int, r: Float32, g: Float32, b: Float32, a: Float32
)
  requires: cl != 0
  requires: r >= 0.0 && r <= 1.0
  requires: g >= 0.0 && g <= 1.0
  requires: b >= 0.0 && b <= 1.0
  requires: a >= 0.0 && a <= 1.0
{
}

pub fn d3d12_clear_dsv(
  cl: DxCommandList, dsv_handle: Int, clear_flags: Int,
  depth: Float32, stencil: Int
)
  requires: cl != 0
  requires: depth >= 0.0 && depth <= 1.0
{
}

pub fn d3d12_draw_instanced(
  cl: DxCommandList, vertex_count: Int, instance_count: Int,
  start_vertex: Int, start_instance: Int
)
  requires: cl != 0
  requires: vertex_count > 0
  requires: instance_count > 0
  requires: start_vertex >= 0
  requires: start_instance >= 0
{
}

// ===========================================================================
// Safe Wrappers: Fence / Sync
// ===========================================================================

pub fn d3d12_create_fence(dev: DxDevice, initial_value: Int) -> Result[DxFence, Str]
  requires: dev != 0
  requires: initial_value >= 0
{
  return Err("d3d12_create_fence: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

pub fn d3d12_signal_fence(queue: DxCommandQueue, fence: DxFence, value: Int)
  requires: queue != 0
  requires: fence != 0
  requires: value >= 0
{
}

pub fn d3d12_wait_fence(fence: DxFence, value: Int)
  requires: fence != 0
  requires: value >= 0
{
}

// ===========================================================================
// Safe Wrappers: Root Signature / Pipeline State
// ===========================================================================

pub fn d3d12_create_root_signature(
  dev: DxDevice, blob: Int, blob_len: Int
) -> Result[DxRootSignature, Str]
  requires: dev != 0
  requires: blob != 0
  requires: blob_len > 0
{
  return Err("d3d12_create_root_signature: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}

pub fn d3d12_create_pipeline_state(
  dev: DxDevice, root_sig: DxRootSignature, vs_bytecode: Int,
  vs_len: Int, ps_bytecode: Int, ps_len: Int
) -> Result[DxPipelineState, Str]
  requires: dev != 0
  requires: root_sig != 0
{
  return Err("d3d12_create_pipeline_state: C bridge not yet linked -- xiom-directx12 is in SPEC phase");
}
