// XIOM -- xiom.pem package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_pem {
  name: "xiom.pem";
  version: "0.1.0";
  description: "PEM armor codec: BEGIN/END blocks, RFC 1421 headers, strict base64";
  categories: ["data"];
  keywords: ["pem", "base64", "armor", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pem"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
