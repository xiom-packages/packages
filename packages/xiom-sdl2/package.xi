// XIOM -- SDL2 Bindings Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.sdl2"
  version: "0.1.0"
  description: "SDL2 (Simple DirectMedia Layer 2) bindings for XIOM -- 100% of the exported public C API surface (844 functions) from the shipped SDL2 2.32.10 headers: generated family-split dynamic loader (no link-time dependency; runtime SKIP when SDL2.dll is absent), typed per-function wrappers over owned slots, symbol resolvers, and 1385 generated constant tables (enums/macros)"
  categories: ["graphics", "media"]
  keywords: ["sdl2", "windowing", "input", "audio", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
