// XIOM -- xiom.l10n.address package manifest
// Port task: promote the xiom.l10n.address placeholder to a real, tested,
// pure-XIOM package (country address templates, rendering and validation).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.compare
// and xiom.convert from it; the tests additionally use xiom.test and xiom.io.

package xiom_l10n_address {
  name: "xiom.l10n.address";
  version: "0.1.0";
  description: "Country address templates and rendering (12-country illustrative dataset)";
  categories: ["text", "data"];
  keywords: ["l10n", "address", "postal", "locale"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.l10n.address"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
