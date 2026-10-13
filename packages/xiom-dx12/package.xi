package xiom_dx12 {
  name: "xiom.dx12";
  version: "0.3.1";
  description: "Direct3D 12 bindings for XIOM (runtime d3d12.dll + dxgi.dll; COM/vtable ABI pinned from microsoft/DirectX-Headers; d3d12: 358 method wrappers + 9 free functions; DXGI: 43 interfaces / 163 wrappers / 6 free functions; d3d12video: 30 interfaces / 190 wrappers; struct metadata: 434 shapes / 2238 size+offset consts; live device/WARP/swapchain/video chains; probe + SKIP semantics; stable)";
  categories: ["graphics"];
  keywords: ["d3d12", "directx", "dx12", "gpu", "rendering", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
