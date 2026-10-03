// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// XIOM -- xiom.translate package manifest
// Port task: replace the xiom.translate placeholder with a real, tested,
// pure-XIOM package (no FFI, no network).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.string.builder from it; the tests additionally
// use xiom.io and xiom.test.

package xiom_translate {
  name: "xiom.translate";
  version: "0.1.0";
  description: "Deterministic offline translation core: in-package phrasebook terms, stopword/n-gram language detection, Cyrillic/Greek script transliteration, domain glossaries";
  categories: ["text-nlp"];
  keywords: ["translation", "phrasebook", "language-detection", "transliteration", "glossary", "l10n"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.translate"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
