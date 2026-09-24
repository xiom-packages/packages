// XIOM -- xiom.fixed package manifest
// Port task: greenfield pure-XIOM fixed-width table parser/writer (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_fixed {
  name: "xiom.fixed";
  version: "0.1.0";
  description: "Fixed-width text table parsing and writing by column widths";
  categories: ["data", "text"];
  keywords: ["fixed-width", "table", "parser", "columns"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.fixed"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
