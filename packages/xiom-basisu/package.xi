// XIOM -- xiom.basisu package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_basisu {
  name: "xiom.basisu";
  version: "0.1.0";
  description: "basis_universal v2_50 bindings for XIOM (KTX2 supercompressed texture transcode + encode; vendored, no system library)";
  categories: ["graphics"];
  keywords: ["basisu", "basis", "ktx2", "transcode", "texture", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.basisu"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
