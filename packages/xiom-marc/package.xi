// XIOM -- xiom.marc package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_marc {
  name: "xiom.marc";
  version: "0.1.0";
  description: "MARC21 ISO 2709 record codec: parse and build library records";
  categories: ["data"];
  keywords: ["marc", "library", "iso2709", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.marc"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
