// XIOM -- xiom.maidenhead package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield pure-XIOM Maidenhead locator codec over integer microdegrees
// (no FFI).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_maidenhead {
  name: "xiom.maidenhead";
  version: "0.1.0";
  description: "Integer-only Maidenhead grid locator codec over integer-microdegree coordinates";
  categories: ["science"];
  keywords: ["maidenhead", "grid", "locator", "radio"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.maidenhead"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
