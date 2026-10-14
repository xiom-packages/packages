// XIOM -- xiom.ktx2 Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.ktx2"
  version: "0.1.0"
  description: "KTX2 texture container + Basis Universal transcode bindings for XIOM (vendored libktx v4.4.2: create/write/read, ETC1S/UASTC encode, Basis transcode, ASTC encode/decode)"
  categories: ["graphics"]
  keywords: ["ktx2", "texture", "basis", "transcode", "astc", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  modules: ["xiom.ktx2"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
