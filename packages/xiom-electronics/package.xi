// XIOM -- xiom.electronics package manifest
// Port task: promote the xiom.electronics placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string.compare from it;
// the tests additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_electronics {
  name: "xiom.electronics";
  version: "0.1.0";
  description: "Resistor color codes, E24 series, voltage dividers, and LED resistors (integer math)";
  categories: ["science","engineering"];
  keywords: ["electronics","resistor","voltage","circuits"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.electronics"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
