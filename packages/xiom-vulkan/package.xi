// XIOM -- Vulkan Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.vulkan"
  version: "0.3.0"
  description: "Vulkan bindings for XIOM via dynamic loader (vulkan-1.dll at runtime, no SDK required, SKIP when absent); capability probe + engine RHI bring-up (instance/device/queue/real submit)"
  categories: ["graphics"]
  keywords: ["vulkan", "gpu", "rendering", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
