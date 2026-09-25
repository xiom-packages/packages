// XIOM -- xiom.plist package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test and xiom.io.

package xiom_plist {
  name: "xiom.plist";
  version: "0.1.0";
  description: "Apple XML property-list codec for a documented subset";
  categories: ["data"];
  keywords: ["plist", "apple", "xml", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.plist"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
