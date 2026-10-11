// XIOM -- shaderc Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.shaderc"
  version: "0.1.0"
  description: "shaderc bindings for XIOM via dynamic loader (shaderc_shared.dll at runtime, SKIP when absent); generated 100% coverage of the public C API (45/45 entry points): GLSL/HLSL -> SPIR-V compilation, assembly round trip, preprocessing, full compile-options surface, result queries, SPIR-V version/profile parsing"
  categories: ["graphics"]
  keywords: ["shaderc", "glsl", "hlsl", "spirv", "compiler", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
