// XIOM -- xiom.pci package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing from it (all
// names it returns are literals); the tests use xiom.test, xiom.io,
// xiom.string.compare and xiom.encoding.hex from it.

package xiom_pci {
  name: "xiom.pci";
  version: "0.1.0";
  description: "PCI configuration-space codec: decode a 256-byte function and build a canonical type-0 header";
  categories: ["systems"];
  keywords: ["pci", "config", "hardware", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pci"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
