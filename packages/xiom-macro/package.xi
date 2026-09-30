// XIOM -- xiom.macro package manifest
// Port task: replace the xiom.macro placeholder with a real, tested,
// documented, pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.builder,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_macro {
  name: "xiom.macro";
  version: "0.1.0";
  description: "Pure deterministic text macro-expansion processor with define/undef directives";
  categories: ["text", "tooling"];
  keywords: ["macro", "preprocessor", "expand", "text", "template"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.macro"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
