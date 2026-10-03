// XIOM -- xiom.l10n-unit package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module uses
// xiom.string, xiom.string.compare and xiom.convert from it; the tests
// additionally use xiom.io and xiom.test.
//
// Naming note: the package (manifest) name is "xiom.l10n-unit" as requested,
// but the compiler module name must be a dotted identifier (v0.61.3 rejects
// '-' in `module` declarations: error[P001] at 1:17), so the module is
// xiom.l10n.unit.

package xiom_l10n_unit {
  name: "xiom.l10n-unit";
  version: "0.1.2";
  description: "Exact integer unit conversion over an embedded rational-factor table with affine temperatures";
  categories: ["data", "text-nlp"];
  keywords: ["units", "conversion", "measurement", "l10n", "i18n", "temperature"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.l10n.unit"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
