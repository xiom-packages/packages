// XIOM -- xiom.coverage package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// New package: a pure-XIOM (no FFI) gcov coverage-text codec and summary.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module imports xiom.string, xiom.string.compare and
// xiom.convert from it; the tests additionally use xiom.test and xiom.io.

package xiom_coverage {
  name: "xiom.coverage";
  version: "0.1.0";
  description: "Pure-XIOM gcov coverage-text codec and per-file/overall summary math";
  categories: ["testing"];
  keywords: ["gcov", "coverage", "parser", "summary"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.coverage"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
