// XIOM -- xiom.dtb package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.builder from it; the tests add xiom.test, xiom.io,
// xiom.string.compare and xiom.encoding.hex.

package xiom_dtb {
  name: "xiom.dtb";
  version: "0.1.0";
  description: "Flattened Device Tree (DTB) parsing, validation and canonical v17 emission";
  categories: ["systems"];
  keywords: ["dtb", "devicetree", "firmware", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.dtb"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
