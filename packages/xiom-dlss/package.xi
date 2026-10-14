// XIOM -- xiom.dlss package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// CLOSED-SDK pattern: nothing from NVIDIA is vendored.  `surface.xi` is
// generated from the pinned public headers of the reference-only clone
// (E:\repos\DLSS) and the modules are independent declarations of the NGX
// API (interface facts only).  xiom.std is the standard library: a platform
// dependency, excluded from the registry install closure.

package xiom_dlss {
  name: "xiom.dlss";
  version: "0.1.0";
  description: "NVIDIA DLSS / NGX bindings (CLOSED-SDK pattern -- independent declarations from the pinned public headers, no NVIDIA code or binaries): 85-entry resolvable NGX surface (D3D11/D3D12/CUDA/Vulkan core + parameter C API + globals), 435 parameter keys, 74 effective-key codes, typed D3D12 DLSS-SR flow + optimal-settings query; dynamic-load nvngx_dlss.dll / nvngx.dll SKIP-safe (runtime not shipped)";
  categories: ["graphics"];
  keywords: ["dlss", "ngx", "nvidia", "upscaling", "frame-generation", "ray-reconstruction", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.dlss", "xiom.dlss.surface"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
