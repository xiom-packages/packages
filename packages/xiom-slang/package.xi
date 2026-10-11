// XIOM -- Slang C API Bindings Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.slang"
  version: "0.1.0"
  description: "Slang shader compiler C API bindings for XIOM -- generated dynamic-loader facade over slang.dll (Vulkan SDK): every exported C entry point (slang_* + legacy sp* API, 277 functions) resolved by name with typed wrappers, family-split modules, enum/macro constants, and a conformance suite (resolved=N/N + session/compile/diagnostics functional probe; SKIP-green when the DLL is absent)"
  categories: ["graphics", "tools"]
  keywords: ["slang", "shader", "compiler", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
