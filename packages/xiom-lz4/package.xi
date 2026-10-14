// XIOM -- xiom.lz4 Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_lz4 {
  name: "xiom.lz4";
  version: "0.1.0";
  description: "LZ4 v1.10.0 bindings: block (lz4.h), high-compression (lz4hc.h) and frame (lz4frame.h) at 100% declared surface (vendored lib/ BSD-2-Clause)";
  categories: ["data", "compression"];
  keywords: ["lz4", "compression", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.lz4", "xiom.lz4.ffi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
