// XIOM -- SPIR-V Headers Constants Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.spirv.headers"
  version: "0.1.0"
  description: "SPIR-V header constants for XIOM -- every Spv* enum value and macro from the shipped SPIR-V headers (SPIRV-Headers vulkan-sdk-1.4.350.0): 74 enum types / 2378 enumerators / 2385 constants across family-split generated modules (core, image, fp, decorations, controls, capabilities, opcodes by numeric range). No runtime library: pure constants, source-generated, oracle-verified."
  categories: ["graphics"]
  keywords: ["spirv", "spir-v", "vulkan", "shader", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
