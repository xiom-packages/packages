// XIOM -- xiom.hcl package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test and xiom.io.

package xiom_hcl {
  name: "xiom.hcl";
  version: "0.1.0";
  description: "Pure-XIOM structural HCL2 subset parser with a canonical emitter";
  categories: ["systems"];
  keywords: ["hcl", "terraform", "config", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.hcl"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
