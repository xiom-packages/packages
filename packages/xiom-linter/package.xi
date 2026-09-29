// XIOM -- xiom.linter package manifest
// Port task: promote the xiom.linter placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io, xiom.string and
// xiom.string.compare.

package xiom_linter {
  name: "xiom.linter";
  version: "0.1.0";
  description: "Line-oriented lint engine: rule registry, diagnostic bag, built-in rules, config, text and CSV reports";
  categories: ["tooling", "testing"];
  keywords: ["lint", "linter", "static-analysis", "diagnostics", "rules", "conformance"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.linter"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
