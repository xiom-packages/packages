// XIOM -- xiom.locale package manifest
// Port task: promote the xiom.locale placeholder to a real, tested, pure-XIOM
// package (BCP-47 language tag parsing, canonicalization, RFC 4647 lookup and
// fallback chains).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_locale {
  name: "xiom.locale";
  version: "0.1.1";
  description: "BCP-47 language tag parsing, canonicalization, RFC 4647 lookup and fallback chains";
  categories: ["text-nlp", "data"];
  keywords: ["locale", "bcp47", "language", "l10n", "i18n"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.locale"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
