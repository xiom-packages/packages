// XIOM -- glslang Bindings Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.glslang"
  version: "0.1.0"
  description: "glslang (Khronos GLSL/ESSL/HLSL compiler) bindings for XIOM -- dynamic loader over glslang.dll (57 C entry points: the glslang_c_interface compile API + the legacy Sh* surface) and glslang-default-resource-limits.dll (4 C resource-limit helpers); typed wrappers, owned-slot out-params, source-generated constant tables (244 values) and a GLSL->SPIR-V compile path with owned-buffer copy-out"
  categories: ["graphics"]
  keywords: ["glslang", "glsl", "spir-v", "shader", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
