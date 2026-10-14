// XIOM -- Intel XeSS Bindings Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.xess"
  version: "0.1.0"
  description: "Intel XeSS bindings for XIOM -- dynamic loader for libxess.dll (SR core: context create/destroy, init/execute param structs, properties/version/resolution queries, jitter/velocity/exposure/mask accessors) + libxess_dx11.dll companion (D3D11 surface) + D3D12/Vulkan backends + public debug surface (network model, dump, profiling); 41/41 declared public entries; typed SKIP when the runtime is absent"
  categories: ["graphics"]
  keywords: ["xess", "intel", "upscaling", "super-resolution", "d3d12", "vulkan", "d3d11", "gpu", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  modules: ["xiom.xess"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
