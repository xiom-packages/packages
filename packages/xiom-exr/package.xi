// XIOM -- xiom.exr Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.exr"
  version: "0.1.0"
  description: "OpenEXR reader for XIOM via vendored tinyexr v3.2.0 (BSD-3; single TU + miniz): read from memory/file into owned planar float32 channel buffers, metadata queries (dimensions, channel names/count, declared pixel types, compression, data window), save-to-memory round trips, typed errors"
  categories: ["graphics", "media"]
  keywords: ["exr", "openexr", "tinyexr", "hdr", "image", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  modules: ["xiom.exr"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
