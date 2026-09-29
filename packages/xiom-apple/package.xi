// XIOM -- xiom.apple package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.convert.int from it; the tests add xiom.test, xiom.io,
// xiom.string.compare and xiom.convert.int.

package xiom_apple {
  name: "xiom.apple";
  version: "0.1.2";
  description: "Pure-XIOM Apple executable/container structure parser (Mach-O thin and fat/universal headers, header fields and load-command walk)";
  categories: ["systems"];
  keywords: ["mach-o", "macho", "apple", "binary", "executable", "fat", "universal"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.apple"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
