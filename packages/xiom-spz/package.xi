// XIOM -- xiom.spz Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_spz {
  name: "xiom.spz";
  version: "0.1.0";
  description: "nianticlabs/spz v3.0.0 Gaussian-splat compression bindings (NGSP v4 zstd + legacy v1-3 gzip; vendored C++ + zlib + zstd)";
  categories: ["graphics", "data"];
  keywords: ["spz", "gaussian-splat", "splat", "compression", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.spz", "xiom.spz.ffi", "xiom.spz.math"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
