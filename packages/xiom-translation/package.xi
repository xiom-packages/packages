// XIOM -- xiom.translation package manifest
// Port task: replace the xiom.translation placeholder with a real, tested,
// documented, pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_translation {
  name: "xiom.translation";
  version: "0.1.0";
  description: "Message catalogs: key/value translation entries with locale fallback and placeholder interpolation";
  categories: ["text", "tooling"];
  keywords: ["translation", "i18n", "catalog", "fallback"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.translation"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
