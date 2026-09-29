// XIOM -- xiom.lemmatization package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string (byte
// access, slicing and case folding) from it; the tests additionally use
// xiom.test, xiom.io and xiom.string.compare.

package xiom_lemmatization {
  name: "xiom.lemmatization";
  version: "0.1.0";
  description: "Deterministic rule-based English lemmatizer with POS-tagged suffix rules";
  categories: ["text"];
  keywords: ["lemmatization", "lemma", "nlp", "morphology", "text"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.lemmatization"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
