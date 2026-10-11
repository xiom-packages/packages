// XIOM -- SPIRV-Tools Bindings Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.spirv-tools"
  version: "0.1.0"
  description: "SPIRV-Tools C API bindings for XIOM via dynamic loader (SPIRV-Tools-shared.dll at runtime, no link-time SDK dependency, SKIP when absent); generated bindings for the full header-declared extern \"C\" surface (67 spv* functions: assembly, disassembly, validation, diagnostics, binary parse, validator/optimizer/reducer/fuzzer options) + source-generated constants (222 enum values) + typed resolver with runtime resolve proof (55/67 exported at the SDK 1.4.350.0 pin; 12 documented shipping gaps)"
  categories: ["graphics", "tooling"]
  keywords: ["spirv", "spirv-tools", "shader", "validation", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
