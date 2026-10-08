// XIOM -- Vulkan Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.vulkan"
  version: "0.2.0"
  description: "Vulkan capability probe for XIOM (runtime vulkan-1.dll, no SDK required, SKIP when absent)"
  categories: ["graphics"]
  keywords: ["vulkan", "gpu", "rendering", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
