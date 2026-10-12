package xiom_dx12 {
  name: "xiom.dx12";
  version: "0.2.0";
  description: "Direct3D 12 bindings for XIOM (runtime d3d12.dll; COM/vtable ABI pinned from microsoft/DirectX-Headers; full d3d12.h core surface: 90 interfaces / 355 generated method wrappers / 1162 enum consts / 9 free functions; probe + SKIP semantics; DXGI next)";
  categories: ["graphics"];
  keywords: ["d3d12", "directx", "dx12", "gpu", "rendering", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
