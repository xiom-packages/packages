// XIOM -- xiom.png package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module uses xiom.string.builder and
// xiom.convert from it; the tests add xiom.test/xiom.io/xiom.string.compare.

package xiom_png {
  name: "xiom.png";
  version: "0.1.0";
  description: "PNG (W3C PNG 1.2) container codec: signature, chunk stream, CRC-32, IHDR/PLTE/tRNS/gAMA/pHYs/sRGB/text validation";
  categories: ["graphics"];
  keywords: ["png", "image", "container", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.png"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
