// XIOM -- xiom.l10n-currency package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module uses
// xiom.string, xiom.string.compare and xiom.convert from it; the tests
// additionally use xiom.io and xiom.test.
//
// Naming note: the package (manifest) name is "xiom.l10n-currency" as
// requested, but the compiler module name must be a dotted identifier
// (v0.61.3 rejects '-' in `module` declarations: error[P001] at 1:17), so
// the module is xiom.l10n.currency.

package xiom_l10n_currency {
  name: "xiom.l10n-currency";
  version: "0.1.2";
  description: "ISO 4217 currency table, lookups, and exact integer minor-unit amount parse/format";
  categories: ["data", "finance"];
  keywords: ["currency", "iso4217", "money", "l10n", "i18n", "formatting"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.l10n.currency"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
