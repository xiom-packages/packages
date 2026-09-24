// XIOM -- xiom.transliteration package manifest
// Port task: replace the xiom.transliteration placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.builder from it; the tests additionally use xiom.test, xiom.io
// and xiom.string.compare.

package xiom_transliteration {
  name: "xiom.transliteration";
  version: "0.1.0";
  description: "UTF-8 to ASCII transliteration for Latin, Greek, and Cyrillic text";
  categories: ["text"];
  keywords: ["transliteration", "unicode", "ascii", "slug"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.transliteration"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
