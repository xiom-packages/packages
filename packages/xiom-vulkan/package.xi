// XIOM -- Vulkan Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.vulkan"
  version: "0.6.0"
  description: "Vulkan bindings for XIOM via dynamic loader (vulkan-1.dll at runtime, no SDK required, SKIP when absent); capability probe + engine RHI bring-up (instance/device/queue/real submit) + WSI (Win32 surface, swapchain, clear+present) + render pipeline (embedded SPIR-V, 3-vertex draw, readback proof, present) + C07 stable capture-copy (full-frame checksum across frames) + B05 query readback (timestamp duration + occlusion samples) + the generated SDK100 raw command surface (845 commands, 5983 constants)"
  categories: ["graphics"]
  keywords: ["vulkan", "gpu", "rendering", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
