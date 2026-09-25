// XIOM -- xiom.fits package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_fits {
  name: "xiom.fits";
  version: "0.1.0";
  description: "FITS header codec: 80-character cards, 2880-byte blocks, validated values";
  categories: ["science"];
  keywords: ["fits", "astronomy", "header", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.fits"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
