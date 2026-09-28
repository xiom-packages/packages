// XIOM -- xiom.l10n-phone package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module uses
// xiom.string, xiom.string.compare and xiom.convert from it; the tests
// additionally use xiom.io and xiom.test.
//
// Naming note: the package (manifest) name is "xiom.l10n-phone" as
// requested, but the compiler module name must be a dotted identifier
// (v0.61.3 rejects '-' in `module` declarations: error[P001] at 1:17), so
// the module is xiom.l10n.phone.

package xiom_l10n_phone {
  name: "xiom.l10n-phone";
  version: "0.1.1";
  description: "E.164 / international phone-number structures: embedded country-code table, parse, validate, format, tel URI";
  categories: ["data", "i18n"];
  keywords: ["phone", "e164", "telephone", "l10n", "i18n", "itu", "validation"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.l10n.phone"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
