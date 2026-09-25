// XIOM -- xiom.pcx package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_pcx {
  name: "xiom.pcx";
  version: "0.1.0";
  description: "PCX header, palette-trailer and pixel-span codec (documented subset)";
  categories: ["graphics"];
  keywords: ["pcx", "image", "palette", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pcx"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
