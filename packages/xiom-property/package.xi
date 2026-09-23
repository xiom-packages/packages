// XIOM -- xiom.property package manifest
// Port task: promote the xiom.property placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_property {
  name: "xiom.property";
  version: "0.1.0";
  description: "Deterministic property-based testing: seeds, generators, and shrinking";
  categories: ["tooling","testing"];
  keywords: ["property","testing","generator","shrink"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.property"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
