// XIOM -- xiom.radix package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.core from it; the tests additionally use
// xiom.test, xiom.io, xiom.string and xiom.string.compare.

package xiom_radix {
  name: "xiom.radix";
  version: "0.1.0";
  description: "Base 2..36 integer text conversion with canonical lowercase digits and strict overflow detection";
  categories: ["data"];
  keywords: ["radix", "base", "conversion", "numbers"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.radix"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
