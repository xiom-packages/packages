// XIOM -- xiom.dbase package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_dbase {
  name: "xiom.dbase";
  version: "0.1.0";
  description: "dBASE III/IV table header codec: parse and build .dbf tables";
  categories: ["data"];
  keywords: ["dbase", "dbf", "table", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.dbase"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
