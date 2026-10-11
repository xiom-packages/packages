// XIOM -- spirv-cross Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.spirv-cross"
  version: "0.1.0"
  description: "SPIRV-Cross bindings for XIOM: dynamic loader + generated typed wrappers for the complete C API (169/169 spvc_* functions in spirv_cross_c.h, SPVC_C_API_VERSION 0.68.0) -- context/compiler/resources/type/constant/buffer/glsl/hlsl/msl/reflect families, every enum member + macro as constants, functional GLSL cross-compile probe over an embedded SPIR-V fixture, SKIP-green when spirv-cross-c-shared.dll is absent"
  categories: ["graphics"]
  keywords: ["spirv-cross", "spirv", "shader", "glsl", "hlsl", "msl", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  modules: ["xiom.spirv.cross"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
