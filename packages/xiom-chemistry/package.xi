// XIOM -- xiom.chemistry package manifest
// Port task: replace the xiom.chemistry placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.compare from it; the tests additionally use xiom.test and xiom.io.

package xiom_chemistry {
  name: "xiom.chemistry";
  version: "0.1.0";
  description: "Chemical formula parsing with molar masses and mass fractions (integer mg/mol)";
  categories: ["science"];
  keywords: ["chemistry", "molar-mass", "formula", "stoichiometry"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.chemistry"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
