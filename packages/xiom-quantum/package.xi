// XIOM -- xiom.quantum package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports only xiom.convert from it (the
// Int -> Float64 conversion; no FFI); the tests use xiom.test, xiom.io,
// xiom.math and xiom.quantum itself.

package xiom_quantum {
  name: "xiom.quantum";
  version: "0.1.0";
  description: "Introductory quantum formulas: de Broglie, hydrogen levels and transitions, Balmer wavelengths, photon momentum";
  categories: ["science"];
  keywords: ["quantum","hydrogen","de-broglie","photon"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas","The XIOM Authors"];
  modules: ["xiom.quantum"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
