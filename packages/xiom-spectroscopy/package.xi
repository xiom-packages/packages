// XIOM -- xiom.spectroscopy package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing (only
// scalar Float64 arithmetic and the documented constants); the tests use
// xiom.test, xiom.io, xiom.math and xiom.string.compare from the same
// dependency.

package xiom_spectroscopy {
  name: "xiom.spectroscopy";
  version: "0.1.0";
  description: "Electromagnetic spectrum conversions: wavelength, frequency, wavenumber, photon energy";
  categories: ["science"];
  keywords: ["spectroscopy","wavelength","frequency","photon"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas","The XIOM Authors"];
  modules: ["xiom.spectroscopy"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
