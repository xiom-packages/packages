// XIOM -- xiom.l10n.name package manifest
// Port task: promote the xiom.l10n.name placeholder to a real, tested,
// pure-XIOM package (personal-name display ordering, lists, initials and
// honorific resolution).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io, xiom.string and
// xiom.string.compare.

package xiom_l10n_name {
  name: "xiom.l10n.name";
  version: "0.1.0";
  description: "Locale-style personal-name display ordering, lists, initials and honorifics";
  categories: ["text", "data"];
  keywords: ["l10n", "name", "personal", "display"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.l10n.name"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
