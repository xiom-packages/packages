// XIOM -- xiom.flash package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing from it; the
// tests use xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_flash {
  name: "xiom.flash";
  version: "0.1.3";
  description: "SPI NOR flash identification codec: JEDEC ID, 25-series command set, status register 1, SFDP (JESD216) header/parameter/BFPT decode and sector maps";
  categories: ["systems"];
  keywords: ["flash", "spi", "nor", "jedec", "sfdp", "jesd216", "embedded"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.flash"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
