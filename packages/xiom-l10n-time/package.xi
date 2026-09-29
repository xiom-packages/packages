// XIOM -- xiom.l10n.time package manifest
// Port task: promote the xiom.l10n.time placeholder to a real, tested,
// pure-XIOM package (time-of-day formatting/parsing, 12h/24h conversion,
// day-period classification and timezone offsets, caller-supplied labels).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.compare
// and xiom.convert from it; the tests additionally use xiom.test and xiom.io.

package xiom_l10n_time {
  name: "xiom.l10n-time";
  version: "0.1.1";
  description: "Locale-style time-of-day formatting, parsing, day periods and timezone offsets (caller-supplied labels)";
  categories: ["text", "data"];
  keywords: ["l10n", "time", "format", "timezone"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.l10n.time"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
