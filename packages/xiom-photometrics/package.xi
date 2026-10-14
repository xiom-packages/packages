// XIOM -- xiom.photometrics package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.math; the tests additionally use xiom.test
// and xiom.io.

package xiom_photometrics {
  name: "xiom.photometrics";
  version: "0.1.0";
  description: "Photometric profile import: IESNA LM-63 (1986/1991/1995/2002) reader and Adobe .cube 1D/3D LUT reader, pure XIOM";
  categories: ["graphics","media"];
  keywords: ["ies","lm-63","photometry","lighting","cube","lut","3d-lut","colormanagement"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.photometrics"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
